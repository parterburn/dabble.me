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

    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }

        let pkce = PKCE()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        do {
            let callback = try await authenticator.authenticate(url: OAuthEndpoints.authorizeURL(pkce: pkce, state: state))
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let value = { (name: String) in items.first { $0.name == name }?.value }

            if let error = value("error") {
                throw WebAuthError.invalidCallback(value("error_description") ?? "Sign-in was not completed (\(error)).")
            }
            guard value("state") == state, let code = value("code") else {
                throw WebAuthError.invalidCallback(nil)
            }
            await tokens.signIn(with: try await OAuthEndpoints.exchange(code: code, pkce: pkce))
            isSignedIn = true
            await refresh()
        } catch WebAuthError.cancelled {
            // User closed the sheet; nothing to report.
        } catch {
            signInError = error.localizedDescription
        }
    }

    func signOut() async {
        if let token = await tokens.clear() {
            Task.detached { await OAuthEndpoints.revoke(token) }
        }
        resetSession()
    }

    private func didLoseSession() {
        guard isSignedIn else { return }
        resetSession()
        signInError = APIError.signedOut.errorDescription
    }

    private func resetSession() {
        isSignedIn = false
        me = nil
        today = nil
        months = []
        monthEntries = [:]
        loadingMonths = []
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
            // Months reload as they come back into view; keep what's on screen until then.
            monthEntries = monthEntries.filter { key, _ in months.contains { $0.key == key } }
            loadingMonths = []
            timelineError = nil
            hasLoaded = true
            if let newest = months.first { await loadMonth(newest.key, force: true) }
        } catch is CancellationError {
        } catch {
            report(error)
        }
    }

    func loadToday() async {
        guard isSignedIn else { return }
        do {
            today = try await api.get("api/v1/today")
        } catch is CancellationError {
        } catch {
            report(error)
        }
    }

    func loadMonth(_ key: String, force: Bool = false) async {
        guard force || monthEntries[key] == nil, !loadingMonths.contains(key),
              let month = months.first(where: { $0.key == key }) else { return }
        loadingMonths.insert(key)
        defer { loadingMonths.remove(key) }
        do {
            let page: EntryPage = try await api.get("api/v1/entries",
                                                    query: ["year": String(month.year), "month": String(month.month), "per": "50"])
            monthEntries[key] = page.entries
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
        var imageKeys: [String] = []
        if !photos.isEmpty {
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
            imageKeys = batch.uploads.map(\.uploadedImageKey)
        }

        let envelope: EntryEnvelope = try await api.post("api/v1/entries",
                                                        NewEntryRequest(date: day.iso, document: document, uploadedImageKeys: imageKeys))
        upsert(envelope.entry.summary)
        if envelope.entry.imageProcessing { watchProcessing(id: envelope.entry.id) }
        await loadToday()
        return envelope
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

    func updateEntry(id: Int, document: [DocumentBlock]) async throws -> EntryDetail {
        let envelope: EntryEnvelope = try await api.patch("api/v1/entries/\(id)", UpdateEntryRequest(document: document))
        upsert(envelope.entry.summary)
        if envelope.entry.id == today?.entry?.id { await loadToday() }
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

    /// Emails a link to the web deletion page. Nothing is deleted from the app itself.
    func requestAccountDeletion() async throws -> String {
        struct Empty: Encodable, Sendable {}
        let response: AccountDeletionRequest = try await api.post("api/v1/account/deletion_request", Empty())
        return response.email
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
