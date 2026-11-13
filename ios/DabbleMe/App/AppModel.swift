import Foundation
import Observation

/// App-wide state: auth, the signed-in account, Today, and the journal timeline. Detail,
/// compose and search screens call through here so edits show up everywhere.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case today, journal, search, settings
    }

    /// Selected tab, and a search another screen asked for (e.g. tapping a #hashtag).
    var selectedTab: Tab = .today
    var searchRequest: String?
    /// Set when a writing reminder is tapped; Today opens the composer.
    var composeRequest = false
    /// The widget's "Add to today": Today opens today's entry for editing once it has it.
    var editTodayRequest = false
    /// Bumped when the Search tab is tapped while already showing, to focus the search field.
    var searchFocusRequest = 0
    /// Bumped when the Journal tab is tapped while already showing: back to the list, at the top.
    var journalTopRequest = 0
    /// The Journal shows Stats (Today's count for the year was tapped).
    var statsRequest = 0
    /// Another of the Journal's views, asked for from elsewhere: Photos from the photo viewer,
    /// the Playlist from an entry's song player.
    var journalModeRequest: JournalMode?
    /// Shake the phone for a random memory (a preview sheet); `openEntryRequest` opens it in Journal.
    var showsRandomEntry = false
    /// A day tapped in Stats → Past Year: its entries come up in a sheet, presented with the
    /// random memory's at the top of the app (from inside Stats it didn't always appear).
    var statsDay: StatsDay?
    var openEntryRequest: Int?
    /// The Journal view an entry opens over, so Back lands there (the list unless set: Rewind's
    /// photos open over the Photos grid).
    var openEntryOver: JournalMode?
    /// Jump to a Day: the calendar of written days (from the Journal's scrubber, Search, or a
    /// day's sheet). The day picked comes up in the day sheet (`statsDay`) once the calendar has
    /// closed; `reopensDayPicker` brings the calendar back after a day's sheet closes.
    var showsDayPicker = false
    var pickedDay: JournalDay?
    var reopensDayPicker = false
    /// The day last looked at from the calendar: it opens on that month again.
    var dayPickerOpensOn: JournalDay?
    /// A day without an entry picked to write one for (Stats' grid, the calendar): the composer
    /// opens on it. From the calendar it waits (`writeAfterDayPicker`) until that sheet has closed.
    var composingDay: StatsDay?
    var writeAfterDayPicker: JournalDay?
    let lock = AppLock()

    func search(hashtag: String) {
        searchRequest = "#\(hashtag)"
        selectedTab = .search
    }

    private(set) var isSignedIn: Bool
    private(set) var isSigningIn = false
    var signInError: String?

    private(set) var me: Me?
    private(set) var today: TodaySummary?

    /// The journal is one section per month (newest first). Months load their entries when they
    /// scroll into view, so the scrubber can jump years back without loading everything between.
    private(set) var months: [MonthCount] = []
    private(set) var monthEntries: [String: [EntrySummary]] = [:]
    private var loadingMonths: Set<String> = []
    /// Cached months a refresh hasn't reloaded yet (they reload when they scroll into view),
    /// and the months currently on screen (reloaded right away on refresh).
    private var staleMonths: Set<String> = []
    private var visibleMonths: Set<String> = []
    private(set) var hasLoaded = false
    var timelineError: String?

    let api: APIClient
    private let tokens: TokenProvider
    private var processingWatches: Set<Int> = []
    private let authenticator = WebAuthenticator()

    init(tokens: TokenProvider = TokenProvider()) {
        self.tokens = tokens
        api = APIClient(tokens: tokens)
        isSignedIn = KeychainStore.load() != nil
        Task { [weak self] in
            await tokens.setSignedOutHandler { self?.didLoseSession() }
        }
    }

    // MARK: - Auth

    func signIn(createAccount: Bool = false) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }

        let pkce = PKCE()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        do {
            let callback = try await authenticator.authenticate(
                url: OAuthEndpoints.authorizeURL(pkce: pkce, state: state, createAccount: createAccount),
                ephemeral: UserDefaults.standard.bool(forKey: Self.signedOutKey))
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let value = { (name: String) in items.first { $0.name == name }?.value }

            if let error = value("error") {
                throw WebAuthError.invalidCallback(value("error_description") ?? "Sign-in was not completed (\(error)).")
            }
            guard value("state") == state, let code = value("code") else {
                throw WebAuthError.invalidCallback(nil)
            }
            await tokens.signIn(with: try await OAuthEndpoints.exchange(code: code, pkce: pkce))
            UserDefaults.standard.removeObject(forKey: Self.signedOutKey)
            isSignedIn = true
            await refresh()
        } catch WebAuthError.cancelled {
            // User closed the sheet; nothing to report.
        } catch {
            signInError = error.localizedDescription
        }
    }

    /// Set by Sign Out until the next sign-in, which then asks for the password again rather than
    /// riding on Safari's dabble.me session.
    private static let signedOutKey = "auth.signedOut"

    func signOut() async {
        if let token = await tokens.clear() {
            Task.detached { await OAuthEndpoints.revoke(token) }
        }
        UserDefaults.standard.set(true, forKey: Self.signedOutKey)
        await WebLinks.clearWebsiteData()
        DraftStore.clearAll()
        clearJournalCopies()
        lock.reset()
        resetSession()
    }

    /// The session ended on the server's side (the token was revoked, or the account deleted on
    /// dabble.me): back to the sign-in page, with nothing of the journal left to show up later.
    private func didLoseSession() {
        guard isSignedIn else { return }
        clearJournalCopies()
        resetSession()
        signInError = APIError.signedOut.errorDescription
    }

    /// What the app keeps of the journal outside itself: the reminders waiting to go out (each
    /// with an entry), the widget's snapshot, and what Apple Intelligence wrote from it.
    private func clearJournalCopies() {
        ReminderScheduler.shared.removeAll()
        WidgetSync.clear()
        for key in ["ai.prompt.day", "ai.prompt.text", "ai.stats.key", "ai.stats.text"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func resetSession() {
        isSignedIn = false
        me = nil
        today = nil
        months = []
        monthEntries = [:]
        loadingMonths = []
        staleMonths = []
        visibleMonths = []
        hasLoaded = false
        selectedTab = .today
        timelineError = nil
    }

    // MARK: - Timeline

    /// Reloads the account, Today, and the month index (pull to refresh, app foreground).
    func refresh() async {
        guard isSignedIn else { return }
        do {
            async let meRequest: Me = api.get("api/v1/me")
            async let monthsRequest: MonthList = api.get("api/v1/entries/months")
            async let todayRequest: TodaySummary = api.get("api/v1/today")
            let (me, monthList, today) = try await (meRequest, monthsRequest, todayRequest)
            self.me = me
            self.today = today
            months = monthList.months
            // Entries can change by email or on the web: keep cached months on screen, reload the
            // visible ones (and the newest) now, and the rest when they scroll back into view.
            monthEntries = monthEntries.filter { key, _ in months.contains { $0.key == key } }
            staleMonths = Set(monthEntries.keys)
            timelineError = nil
            hasLoaded = true
            WidgetSync.update(from: self)
            Task { await ReminderScheduler.shared.reschedule(for: self) }
            var reloadNow = visibleMonths.intersection(staleMonths)
            if let newest = months.first { reloadNow.insert(newest.key) }
            await withTaskGroup(of: Void.self) { group in
                for key in reloadNow {
                    group.addTask { await self.loadMonth(key, force: true) }
                }
            }
        } catch is CancellationError {
        } catch {
            report(error)
        }
    }

    /// Entries written this calendar year, for Today's header and the widget: from the server, or
    /// (an older server) added up from the Journal's months once they've loaded.
    var entriesThisYear: Int? {
        guard let today else { return nil }
        if let count = today.entriesThisYear { return count }
        guard hasLoaded, let year = Int(today.date.prefix(4)) else { return nil }
        return months.filter { $0.year == year }.reduce(0) { $0 + $1.count }
    }

    /// Refreshes Today and the account together, so "today" (in the journal's time zone) stays
    /// in step everywhere, e.g. when the app stays open past midnight.
    func loadToday() async {
        guard isSignedIn else { return }
        do {
            async let todayRequest: TodaySummary = api.get("api/v1/today")
            async let meRequest: Me = api.get("api/v1/me")
            (today, me) = try await (todayRequest, meRequest)
            // An older server: the year's count comes from the month index, so that's refreshed too.
            if today?.entriesThisYear == nil, hasLoaded, let list: MonthList = try? await api.get("api/v1/entries/months") {
                months = list.months
            }
            WidgetSync.update(from: self)
        } catch is CancellationError {
        } catch {
            report(error)
        }
    }

    func monthAppeared(_ key: String) {
        visibleMonths.insert(key)
    }

    func monthDisappeared(_ key: String) {
        visibleMonths.remove(key)
    }

    func isStale(_ key: String) -> Bool {
        staleMonths.contains(key)
    }

    /// The month at `key` and the next couple of older ones (what fills the screen after a jump).
    func loadMonths(around key: String) async {
        guard let index = months.firstIndex(where: { $0.key == key }) else { return }
        let keys = months[index..<min(index + 3, months.count)].map(\.key)
        await withTaskGroup(of: Void.self) { group in
            for key in keys {
                group.addTask { await self.loadMonth(key) }
            }
        }
    }

    func loadMonth(_ key: String, force: Bool = false) async {
        guard force || monthEntries[key] == nil || staleMonths.contains(key), !loadingMonths.contains(key),
              let month = months.first(where: { $0.key == key }) else { return }
        loadingMonths.insert(key)
        defer { loadingMonths.remove(key) }
        do {
            let page: EntryPage = try await api.get("api/v1/entries",
                                                    query: ["year": String(month.year), "month": String(month.month), "per": "50"])
            monthEntries[key] = page.entries
            staleMonths.remove(key)
            for entry in page.entries where entry.imageProcessing { watchProcessing(id: entry.id) }
        } catch is CancellationError {
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        if case APIError.signedOut = error { return } // handled by didLoseSession
        timelineError = error.localizedDescription
    }

    // MARK: - Entries

    /// Every day with an entry (YYYY-MM-DD), for the Journal's jump-to-a-day calendar.
    func entryDays() async throws -> [String] {
        struct DayList: Decodable { let days: [String] }
        let list: DayList = try await api.get("api/v1/entries/days")
        return list.days
    }

    /// A day's entries in full (Stats → Past Year). Fetched directly rather than through the
    /// timeline's month cache, which can be mid-load or not loaded yet.
    func entries(on day: JournalDay) async throws -> [EntryDetail] {
        let parts = day.monthKey.split(separator: "-")
        guard parts.count == 2 else { return [] }
        let page: EntryPage = try await api.get("api/v1/entries", query: ["year": String(parts[0]), "month": String(parts[1]), "per": "50"])
        var entries: [EntryDetail] = []
        for summary in page.entries where summary.date == day.iso {
            entries.append(try await entry(id: summary.id))
        }
        return entries
    }

    func entry(id: Int) async throws -> EntryDetail {
        let envelope: EntryEnvelope = try await api.get("api/v1/entries/\(id)")
        upsert(envelope.entry.summary)
        return envelope.entry
    }

    func randomEntry() async throws -> EntryDetail {
        let envelope: EntryEnvelope = try await api.get("api/v1/entries/random")
        return envelope.entry
    }

    /// Most photos an entry can hold; the server collages them (CollageGenerator::MAX_IMAGES).
    static let maxPhotos = 8

    /// Creates an entry (or appends to that day's entry, like the web) with up to `maxPhotos` photos.
    /// Photos go straight to S3 in parallel; `onProgress` reports how many have finished.
    func createEntry(day: JournalDay, document: [DocumentBlock], photos: [PreparedPhoto],
                     onProgress: @escaping @MainActor (Int) -> Void = { _ in }) async throws -> EntryEnvelope {
        let imageKeys = try await uploadPhotos(photos, onProgress: onProgress)
        let envelope: EntryEnvelope = try await api.post("api/v1/entries",
                                                        NewEntryRequest(date: day.iso, document: document, uploadedImageKeys: imageKeys))
        upsert(envelope.entry.summary)
        if envelope.entry.imageProcessing { watchProcessing(id: envelope.entry.id) }
        await loadToday()
        // Today's writing reminder isn't needed once there's an entry.
        await ReminderScheduler.shared.reschedule(for: self)
        return envelope
    }

    /// Uploads photos straight to S3 in parallel (presigned) and returns their keys for the entry request.
    private func uploadPhotos(_ photos: [PreparedPhoto], onProgress: @escaping @MainActor (Int) -> Void) async throws -> [String] {
        guard !photos.isEmpty else { return [] }
        let batch: ImageUploadBatch = try await api.post(
            "api/v1/image_uploads",
            ImageUploadRequest(photos: photos.map { .init(filename: $0.filename, contentType: $0.contentType) })
        )
        guard batch.uploads.count == photos.count else { throw APIError.decoding }

        let api = api
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (photo, target) in zip(photos, batch.uploads) {
                group.addTask { try await api.upload(photo.data, to: target) }
            }
            var finished = 0
            for try await _ in group {
                finished += 1
                onProgress(finished)
            }
        }
        return batch.uploads.map(\.uploadedImageKey)
    }

    /// Re-fetches an entry until its photo or collage finishes processing, so the timeline's
    /// placeholder turns into the real image without a manual refresh.
    func watchProcessing(id: Int) {
        guard !processingWatches.contains(id) else { return }
        processingWatches.insert(id)
        Task { [weak self] in
            defer { self?.processingWatches.remove(id) }
            for _ in 0..<60 { // ~5 minutes
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isSignedIn else { return }
                guard let entry = try? await self.entry(id: id) else { continue }
                if !entry.imageProcessing { return }
            }
        }
    }

    func updateEntry(id: Int, document: [DocumentBlock], day: JournalDay? = nil, merging: Bool = false,
                     photos: [PreparedPhoto] = [], removeImage: Bool = false,
                     onProgress: @escaping @MainActor (Int) -> Void = { _ in }) async throws -> EntryDetail {
        let keys = try await uploadPhotos(photos, onProgress: onProgress)
        let request = UpdateEntryRequest(document: document, date: day?.iso, merge: merging ? true : nil,
                                         uploadedImageKeys: keys.isEmpty ? nil : keys,
                                         removeImage: removeImage ? true : nil)
        let envelope: EntryEnvelope = try await api.patch("api/v1/entries/\(id)", request)
        // Merged into that day's entry: this one is gone from the timeline.
        if envelope.entry.id != id { for key in monthEntries.keys { monthEntries[key]?.removeAll { $0.id == id } } }
        upsert(envelope.entry.summary)
        if envelope.entry.imageProcessing { watchProcessing(id: envelope.entry.id) }
        if day != nil {
            // Moved to another day: its place in the timeline, the months' counts and Today
            // (it may have been today's, or be today's now) all come from the server again.
            await refresh()
        } else if envelope.entry.id == today?.entry?.id { await loadToday() }
        return envelope.entry
    }

    func deleteEntry(id: Int) async throws {
        try await api.delete("api/v1/entries/\(id)")
        for (key, entries) in monthEntries where entries.contains(where: { $0.id == id }) {
            monthEntries[key] = entries.filter { $0.id != id }
            if let index = months.firstIndex(where: { $0.key == key }) {
                months[index].count -= 1
                if months[index].count <= 0 { months.remove(at: index) }
            }
        }
        await loadToday()
    }

    /// A random handful of dabble.me's curated writing prompts, for Apple Intelligence to choose
    /// from (none from a server without the endpoint).
    func curatedPrompts() async -> [String] {
        struct Prompts: Decodable { let prompts: [String] }
        let list: Prompts? = try? await api.get("api/v1/prompts", query: ["count": "20"])
        return list?.prompts ?? []
    }

    /// From the background refresh: Today again (is today written?), then the reminders.
    func refreshRemindersInBackground() async {
        BackgroundRefresh.schedule()
        guard isSignedIn else { return }
        if let today: TodaySummary = try? await api.get("api/v1/today") { self.today = today }
        await ReminderScheduler.shared.reschedule(for: self)
    }

    /// The newest few entries (for on-device reflection prompts).
    func recentEntries() async throws -> [EntrySummary] {
        let page: EntryPage = try await api.get("api/v1/entries", query: ["per": "5"])
        return page.entries
    }

    /// "Sunday, Nov 9, 2025 · 1 year ago": an entry's date and how long ago it was, for the
    /// Random Memory and Reflection sheets.
    func dateLine(for day: JournalDay?, fallback: String) -> String {
        guard let day else { return fallback }
        let today = today?.day ?? JournalDay(localDate: .now)
        return "\(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())) · \(day.relative(to: today))"
    }

    /// An on-device Apple Intelligence reflection on an entry (PRO). Only the entry itself: with other
    /// entries as context, the small model kept mixing their details in.
    func reflection(on entry: EntryDetail) async throws -> EntryReflection {
        let today = today?.day ?? JournalDay(localDate: .now)
        let text = try await JournalIntelligence.reflection(on: entry.bodyText, date: entry.day?.long ?? entry.date,
                                                            ago: entry.day?.relative(to: today) ?? "",
                                                            today: today.long, firstName: me?.firstName, recent: [])
        return EntryReflection(date: entry.day?.long ?? entry.date, text: text)
    }

    func emailSchedule() async throws -> EmailSchedule {
        try await api.get("api/v1/email_schedule")
    }

    func tagDates() async throws -> TagDateList {
        try await api.get("api/v1/dated_hashtags")
    }

    func addTagDate(tag: String, date: String) async throws -> TagDate {
        try await api.post("api/v1/dated_hashtags", TagDateUpdate(tag: tag, date: date))
    }

    func updateTagDate(id: Int, date: String) async throws -> TagDate {
        try await api.patch("api/v1/dated_hashtags/\(id)", TagDateUpdate(date: date))
    }

    func removeTagDate(id: Int) async throws {
        try await api.delete("api/v1/dated_hashtags/\(id)")
    }

    func updateEmailSchedule(_ update: EmailScheduleUpdate) async throws -> EmailSchedule {
        let schedule: EmailSchedule = try await api.patch("api/v1/email_schedule", update)
        // The time zone is also the journal's: "today" may have moved.
        if update.timezone != nil { await loadToday() }
        return schedule
    }

    /// The days (YYYY-MM-DD) with an entry in a calendar year, for Stats' earlier years.
    func writingDays(year: Int) async throws -> [String] {
        try await statsYear(year).days
    }

    /// A calendar year for Stats: its days with an entry, and its hashtags.
    func statsYear(_ year: Int) async throws -> YearDays {
        try await api.get("api/v1/stats/days", query: ["year": String(year)])
    }

    /// A month's entries as the timeline has them, by day (YYYY-MM-DD): the calendar's previews.
    func entrySummaries(year: Int, month: Int) async throws -> [String: EntrySummary] {
        let page: EntryPage = try await api.get("api/v1/entries", query: ["year": String(year), "month": String(month), "per": "50"])
        return Dictionary(page.entries.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// A day's entry as the timeline has it (text capped), for a quick look: Stats' day grid.
    func entrySummary(on day: JournalDay) async throws -> EntrySummary? {
        let parts = day.monthKey.split(separator: "-")
        guard parts.count == 2 else { return nil }
        let page: EntryPage = try await api.get("api/v1/entries", query: ["year": String(parts[0]), "month": String(parts[1]), "per": "50"])
        return page.entries.first { $0.date == day.iso }
    }

    func stats() async throws -> JournalStats {
        try await api.get("api/v1/stats")
    }

    /// Every entry of a year (its text capped, as in the timeline), for the year's Rewind.
    func entries(year: Int) async throws -> [EntrySummary] {
        var all: [EntrySummary] = []
        var page: Int? = 1
        while let next = page {
            let result: EntryPage = try await api.get("api/v1/entries", query: ["year": String(year), "page": String(next), "per": "50"])
            all += result.entries
            page = result.nextPage
        }
        return all
    }

    /// Entries with a Spotify song, newest first (Journal > Playlist).
    func songEntries(page: Int) async throws -> EntryPage {
        try await api.get("api/v1/entries", query: ["songs": "1", "page": String(page), "per": "30"])
    }

    func photoEntries(page: Int) async throws -> EntryPage {
        try await api.get("api/v1/entries", query: ["photos": "1", "page": String(page), "per": "48"])
    }

    /// Every hashtag the writer has used (most used first), the vocabulary for suggestions.
    func allHashtags() async throws -> [HashtagCount] {
        let list: HashtagList = try await api.get("api/v1/hashtags", query: ["days": "3650", "limit": "200"])
        return list.hashtags
    }

    /// Most recently used first, for the composer's hashtag bar.
    func recentHashtags() async throws -> [String] {
        let list: HashtagList = try await api.get("api/v1/hashtags", query: ["days": "3650", "limit": "20", "order": "recent"])
        return list.hashtags.map(\.tag)
    }

    func topHashtags() async throws -> [HashtagCount] {
        let list: HashtagList = try await api.get("api/v1/hashtags", query: ["days": "365"])
        return list.hashtags
    }

    func search(_ query: String, page: Int = 1) async throws -> EntryPage {
        try await api.get("api/v1/search", query: ["q": query, "page": String(page)])
    }

    /// Keeps month sections (and their counts) current without refetching.
    private func upsert(_ summary: EntrySummary) {
        guard hasLoaded, let day = summary.day else { return }
        let key = day.monthKey
        // An entry can move months when its date changes; drop it from anywhere else first.
        for (otherKey, entries) in monthEntries where otherKey != key && entries.contains(where: { $0.id == summary.id }) {
            monthEntries[otherKey] = entries.filter { $0.id != summary.id }
        }
        if let index = months.firstIndex(where: { $0.key == key }) {
            guard var entries = monthEntries[key] else { return } // loads fresh when scrolled to
            if let existing = entries.firstIndex(where: { $0.id == summary.id }) {
                entries[existing] = summary
            } else {
                entries.insert(summary, at: entries.firstIndex { $0.date < summary.date } ?? entries.endIndex)
                months[index].count += 1
            }
            monthEntries[key] = entries
        } else if let month = MonthCount(key: key, count: 1) {
            months.insert(month, at: months.firstIndex { $0.key < key } ?? months.endIndex)
            monthEntries[key] = [summary]
        }
    }
}
