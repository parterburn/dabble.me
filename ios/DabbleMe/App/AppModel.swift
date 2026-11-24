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
    /// Bumped when what the widget shows is chosen (it's kept in the shared settings, which
    /// views can't watch): Settings' rows that say what it is are drawn again.
    var widgetChoiceChanges = 0
    /// The days written in the past few weeks (YYYY-MM-DD), once fetched: for the row of the
    /// last five days on Today, in Stats and on the widget.
    var recentWrittenDays: [String]?

    /// Whether each of the last five days was written, oldest first (today's last, by what
    /// Today says of it): five dots, never a count. Nil until the days are known.
    var lastFiveDays: [Bool]? {
        guard let recentWrittenDays, let today, let day = today.day else { return nil }
        let written = Set(recentWrittenDays)
        return (0..<5).reversed().map { back in
            guard back > 0 else { return today.entry != nil }
            guard let date = Calendar.current.date(byAdding: .day, value: -back, to: day.localDate) else { return false }
            return written.contains(JournalDay(localDate: date).iso)
        }
    }
    var searchRequest: String?
    /// Set when New Entry is asked for from outside Today (a reminder's "New Entry", a quick
    /// action, a link); Today opens the composer.
    var composeRequest = false
    /// With `composeRequest`, in the morning: yesterday's entry instead, when it hasn't been
    /// written (people who write about a day the next morning).
    var composePrefersYesterday = false
    /// With `composeRequest`: whether it prefers yesterday is still to be worked out, from the
    /// journal's own time of day, once the account and Today have loaded.
    var composeByMorningRule = false
    /// Up to this time of day (10:00 AM, in minutes), writing is likely about the day before.
    static let morningEnds = 10 * 60

    /// "New Entry" from outside the app (the widget, the Home Screen quick action): in the
    /// morning it's yesterday's, if that isn't written; otherwise today's.
    func requestNewEntry() {
        selectedTab = .today
        // Whether it's morning is the journal's clock's to say: decided once the account has
        // loaded (the app may only just be starting), by Today.
        composeByMorningRule = true
        composeRequest = true
    }

    /// Morning by the journal's clock, as the web's new-entry page judges it, so the two agree
    /// for someone away from their journal's time zone (the device's clock until that's known).
    static func isMorning(at date: Date, in zone: TimeZone?) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone ?? .current
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0) <= morningEnds * 60
    }
    /// The widget's "Edit today": Today opens today's entry for editing once it has it.
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
    var openEntryRequest: Int?
    /// An entry to open on Today (one just written from there for another day).
    var todayEntryRequest: Int?
    /// Counts taps on the Today tab: its wordmark types itself out for each.
    var todayTabTaps = 0
    /// Bumped to bring Today back to its own page (a link to it, with an entry left open there).
    var todayRootRequest = 0
    /// Something on Today to scroll to (the widget's right side was tapped), once Today has it.
    var todayFocusRequest: TodayFocus?
    /// A dabble.me link tapped before the app could act on it (signed out, or still loading):
    /// followed once the journal has loaded.
    var pendingLink: AppLink?
    /// The Journal view an entry opens over, so Back lands there (the list unless set: Rewind's
    /// photos open over the Photos grid).
    var openEntryOver: JournalMode?
    /// Jump to a Day: the calendar's sheet (from the Journal's scrubber or its "me" mark held,
    /// Search, or an open entry's date held). A written day picked opens its entry in full once
    /// the calendar has closed.
    var showsDayPicker = false
    var pickedDay: JournalDay?
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
    /// PRO bought in the app (StoreKit), reported to the server for the signed-in account.
    let subscriptions: SubscriptionStore
    private let tokens: TokenProvider
    private var processingWatches: Set<Int> = []
    private let passkeys = PasskeyAuthenticator()
    /// The email field's passkey autofill, apart from `passkeys` (one request each at a time).
    private let autoFillPasskeys = PasskeyAuthenticator()

    init(tokens: TokenProvider = TokenProvider()) {
        self.tokens = tokens
        api = APIClient(tokens: tokens)
        subscriptions = SubscriptionStore(api: api)
        isSignedIn = KeychainStore.load() != nil
        Task { [weak self] in
            await tokens.setSignedOutHandler { self?.didLoseSession() }
        }
        // Purchases are for the account that's loaded: none while signed out or still loading.
        subscriptions.accountToken = { [weak self] in
            guard let self, isSignedIn else { return nil }
            return me?.appleAccountToken.flatMap(UUID.init(uuidString:))
        }
        subscriptions.didChangePlan = { [weak self] in await self?.refresh() }
        subscriptions.start()
    }

    // MARK: - Auth

    /// The sign-in or sign-up form, when it's showing (the signed-out screens present it).
    var authForm: AuthFormMode?
    /// Said on the welcome screen after the account's deletion is set (not an error).
    var signInNotice: String?

    /// Emails a sign-in code (`AuthFormView`'s Continue). The answer is the same for every
    /// address, so the code screen always follows.
    func sendSignInCode(email: String) async throws -> NativeAuth.CodeSent {
        try await NativeAuth.sendCode(email: email)
    }

    /// The emailed code: signs in, or makes the account. Then the 2FA code if the server asks for
    /// one (`NativeAuthError.needsCode`). A sign-in (not a sign-up) asks to add a passkey after.
    func signIn(email: String, emailCode: String, otpCode: String?) async throws {
        let session = try await NativeAuth.signIn(email: email, emailCode: emailCode, otpCode: otpCode)
        await didSignIn(with: session.tokens, passkeySetupToken: session.passkeySetupToken, asksForPasskey: !session.created)
    }

    /// Passkeys above the keyboard while the email field is focused. Waits until one is picked
    /// (then signs in) or `stopPasskeyAutoFill()`, which throws `CancellationError`.
    func passkeyAutoFill() async throws {
        autoFillPasskeys.prepareAutoFill()
        // Quiet when the challenge can't be had: nobody asked for anything yet.
        guard let challenge = try? await NativeAuth.passkeyChallenge(),
              let bytes = NativeAuth.data(base64URL: challenge.challenge) else { return }
        let assertion = try await autoFillPasskeys.autoFillAssertion(relyingParty: challenge.rpId, challenge: bytes)
        let session = try await NativeAuth.signIn(with: assertion, for: challenge)
        await didSignIn(with: session.tokens)
    }

    func stopPasskeyAutoFill() {
        autoFillPasskeys.cancel()
    }

    /// "Use Password Instead" on the code screen: email and password, then the 2FA code if the
    /// server asks for one (`NativeAuthError.needsCode`). Throws what the form should say.
    func signIn(email: String, password: String, code: String?) async throws {
        let session = try await NativeAuth.signIn(email: email, password: password, code: code)
        // (session.deletionCancelled: the account was set to be deleted and this kept it, as
        // the welcome screen's notice promised.)
        await didSignIn(with: session.tokens, passkeySetupToken: session.passkeySetupToken, asksForPasskey: true)
    }

    func signUp(email: String, password: String, firstName: String?) async throws {
        let session = try await NativeAuth.signUp(email: email, password: password, firstName: firstName)
        await didSignIn(with: session.tokens, passkeySetupToken: session.passkeySetupToken)
    }

    /// The system's passkey sheet, then the server checks the assertion. Throws
    /// `CancellationError` when the sheet is closed, else what the form should say.
    func signInWithPasskey() async throws {
        let challenge = try await NativeAuth.passkeyChallenge()
        guard let bytes = NativeAuth.data(base64URL: challenge.challenge) else {
            throw NativeAuthError.message(APIError.decoding.errorDescription ?? "Sign-in failed.")
        }
        let assertion = try await passkeys.assert(relyingParty: challenge.rpId, challenge: bytes)
        let session = try await NativeAuth.signIn(with: assertion, for: challenge)
        await didSignIn(with: session.tokens)
    }

    /// `asksForPasskey`: a password or email-code sign-in (not sign-up), after which the passkey prompt comes
    /// up once the journal has loaded. Adding one needs no password for the next few minutes
    /// (the server's PasskeysController::SETUP_WINDOW), from the prompt or Settings.
    private func didSignIn(with fresh: OAuthTokens, passkeySetupToken: String? = nil, asksForPasskey: Bool = false) async {
        passkeySetup = passkeySetupToken.map { ($0, Date().addingTimeInterval(14 * 60)) }
        passkeyPromptChecked = false
        justSignedIn = asksForPasskey && passkeySetupToken != nil
        await tokens.signIn(with: fresh)
        signInError = nil
        signInNotice = nil
        authForm = nil
        isSignedIn = true
        await refresh()
    }

    // MARK: - Passkey

    /// Ask to add a passkey (`PasskeyPrompt` says when): MainTabs presents it when nothing else
    /// is up. Settings' Add a Passkey opens the same sheet.
    var passkeyPromptPending = false
    var showsPasskeyPrompt = false
    /// Checked once per password or email-code sign-in.
    private var passkeyPromptChecked = false
    private var justSignedIn = false
    private var passkeySetup: (token: String, expires: Date)?

    /// The account has no password (made by email code): confirmations use an emailed code.
    var confirmsWithEmailCode: Bool { me?.hasPassword == false }

    /// Emails a code to the signed-in account, for `confirmsWithEmailCode` (adding a passkey,
    /// Delete Account).
    func sendConfirmationCode() async throws -> ConfirmationCodeSent {
        try await api.post("api/v1/confirmation_code", EmptyBody())
    }

    /// The sheet needs the password (or an emailed code): there's been no sign-in in the last
    /// few minutes.
    var addingPasskeyNeedsPassword: Bool {
        guard let passkeySetup else { return true }
        return passkeySetup.expires < Date()
    }

    /// The prompt closed without a passkey (Not Now, or swiped away): put off, and counted.
    func passkeyPromptClosed() {
        if me?.hasPasskey == false { PasskeyPrompt.dismiss() }
    }

    private func considerPasskeyPrompt() {
        guard !passkeyPromptChecked, let me else { return }
        passkeyPromptChecked = true
        if PasskeyPrompt.shouldAsk(hasPasskey: me.hasPasskey, justSignedIn: justSignedIn) {
            passkeyPromptPending = true
        }
        justSignedIn = false
    }

    /// The system's sheet makes a passkey for dabble.me (iCloud Keychain, or the password manager
    /// picked), then the server keeps it. Throws `CancellationError` when the sheet is closed.
    /// `password` is the password, or the emailed code when `confirmsWithEmailCode`.
    func addPasskey(password: String?) async throws {
        // Chosen once, before the system's sheet: the setup token can run out while it's up.
        let token = addingPasskeyNeedsPassword ? nil : passkeySetup?.token
        let byCode = token == nil && confirmsWithEmailCode
        let proof = NativeAuth.PasskeyProof(setupToken: token, currentPassword: token == nil && !byCode ? password : nil,
                                            emailCode: byCode ? password : nil)
        let creation: NativeAuth.PasskeyCreation = try await api.post("api/v1/passkeys/options",
                                                                      json: try JSONEncoder().encode(proof))
        guard let challenge = NativeAuth.data(base64URL: creation.challenge),
              let userID = NativeAuth.data(base64URL: creation.userId) else {
            throw NativeAuthError.message(APIError.decoding.errorDescription ?? "Something went wrong.")
        }
        let excluded = (creation.excludeCredentials ?? []).compactMap { NativeAuth.data(base64URL: $0) }
        let registration = try await passkeys.register(relyingParty: creation.rpId, challenge: challenge,
                                                       userName: creation.userName, userID: userID, excluding: excluded)
        // An emailed code works once: the options answer's setup token goes with the passkey.
        let body = try JSONEncoder().encode(NativeAuth.NewPasskey(
            registration: registration, creation: creation, nickname: PasskeyPrompt.nickname,
            setupToken: creation.setupToken ?? proof.setupToken, password: proof.currentPassword))
        let _: PasskeyAdded = try await api.post("api/v1/passkeys", json: body)
        passkeySetup = nil
        // Known now, even if the refresh below doesn't get through (Done shouldn't count as Not Now).
        me?.hasPasskey = true
        if let me: Me = try? await api.get("api/v1/me") { self.me = me }
    }

    // MARK: - Name

    /// Set when a name save fails; Settings shows it, so a save made on going Back isn't lost silently.
    var nameSaveError: String?
    /// The last name save queued, so saves reach the server in the order they were made.
    private var nameSave: Task<Void, Never>?

    /// Saves your name to the account (as the web settings do); the server hands back the account.
    /// Saves run one at a time, so a quick Done then Back can't land out of order.
    func saveName(_ update: NameUpdate) {
        let previous = nameSave
        nameSave = Task {
            await previous?.value
            do {
                let me: Me = try await api.patch("api/v1/me", update)
                self.me = me
            } catch {
                nameSaveError = error.localizedDescription
            }
        }
    }

    // MARK: - Export

    /// Starts the web's export of the whole journal; the server emails the link.
    func requestExport() async throws -> ExportRequestResult {
        try await api.post("api/v1/exports", EmptyBody())
    }

    // MARK: - Account deletion

    func accountDeletionInfo() async throws -> AccountDeletionInfo {
        try await api.get("api/v1/account_deletion")
    }

    /// Confirmed with the password. The server deletes the account an hour later unless the
    /// person signs back in, and has already ended this session; the app signs out here.
    func deleteAccount(password: String) async throws {
        let result: AccountDeletionResult = try await api.post("api/v1/account_deletion", AccountDeletionRequest(password: password))
        await finishDeletion(result)
    }

    /// The same, confirmed with a code emailed to an account with no password (`sendConfirmationCode`).
    func deleteAccount(emailCode: String) async throws {
        let result: AccountDeletionResult = try await api.post("api/v1/account_deletion", AccountDeletionRequest(emailCode: emailCode))
        await finishDeletion(result)
    }

    /// The same, confirmed with one of the account's passkeys (for someone who signs in with a
    /// passkey and may not know the password). Throws `CancellationError` if the sheet is closed.
    func deleteAccountWithPasskey() async throws {
        let challenge = try await NativeAuth.passkeyChallenge()
        guard let bytes = NativeAuth.data(base64URL: challenge.challenge) else {
            throw NativeAuthError.message(APIError.decoding.errorDescription ?? "Something went wrong.")
        }
        let assertion = try await passkeys.assert(relyingParty: challenge.rpId, challenge: bytes)
        let body = try JSONEncoder().encode(NativeAuth.PasskeyConfirmation(assertion: assertion, challenge: challenge))
        let result: AccountDeletionResult = try await api.post("api/v1/account_deletion", json: body)
        await finishDeletion(result)
    }

    private func finishDeletion(_ result: AccountDeletionResult) async {
        await signOut()
        let deletesAt = ISO8601DateFormatter().date(from: result.deletesAt) ?? Date().addingTimeInterval(3600)
        signInNotice = "Your account will be deleted at \(deletesAt.formatted(date: .omitted, time: .shortened)). Sign back in before then to keep it."
    }

    /// Set when Sign Out of All Devices couldn't reach dabble.me; Settings shows it. The app
    /// stays signed in then, so it never looks like other devices were signed out when they weren't.
    var signOutEverywhereError: String?

    /// Signs out every browser and app on the account (connected apps like Claude are
    /// disconnected too), then this app. dabble.me revokes this app's token along with the rest.
    func signOutEverywhere() async {
        do {
            try await api.delete("api/v1/device_sessions")
        } catch {
            signOutEverywhereError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't reach Dabble Me. Check your connection and try again."
            return
        }
        await signOut()
    }

    func signOut() async {
        if let token = await tokens.clear() {
            Task.detached { await OAuthEndpoints.revoke(token) }
        }
        await WebLinks.clearWebsiteData()
        DraftStore.clearAll()
        // (Kept on the account: they come back at the next sign-in.)
        EntryTemplate.clear()
        AccountSettings.clear()
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
        // (And that this account opened its Rewind from Today, and what its push reminder shows.)
        for key in ["ai.prompt.day", "ai.prompt.text", "ai.stats.key", "ai.stats.text", "today.rewindTapped",
                    ReminderSettings.includesPastEntryKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func resetSession() {
        isSignedIn = false
        me = nil
        passkeySetup = nil
        passkeyPromptPending = false
        showsPasskeyPrompt = false
        reviewPromptPending = false
        showsReviewPromptStandIn = false
        subscriptions.reset()
        today = nil
        recentWrittenDays = nil
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
            // A purchase the server hasn't heard about yet (offline, or made while signed out).
            Task { await subscriptions.reportUnfinished() }
            months = monthList.months
            // Entries can change by email or on the web: keep cached months on screen, reload the
            // visible ones (and the newest) now, and the rest when they scroll back into view.
            monthEntries = monthEntries.filter { key, _ in months.contains { $0.key == key } }
            staleMonths = Set(monthEntries.keys)
            timelineError = nil
            hasLoaded = true
            considerPasskeyPrompt()
            WidgetSync.update(from: self)
            // The template and widget choice as the account has them (another phone may have
            // changed them), or sent up if they were changed here.
            AccountSettings.sync(with: self)
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
            // A photo still being processed (added from the web, or before the app was last
            // closed): watched, so Today shows it when it's ready.
            if let entry = today?.entry, entry.imageProcessing { watchProcessing(id: entry.id) }
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

    /// Whether the month's header is on screen (a jump there has arrived).
    func isMonthVisible(_ key: String) -> Bool {
        visibleMonths.contains(key)
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
            #if DEBUG
            // -DabbleDebugMonthDelay <seconds>: a slow connection, for tests of far jumps.
            let delay = UserDefaults.standard.double(forKey: "DabbleDebugMonthDelay")
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            #endif
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

    /// The day before today (the journal's today, once it's known).
    var yesterday: JournalDay? {
        guard let day = today?.day, let date = Calendar.current.date(byAdding: .day, value: -1, to: day.localDate) else { return nil }
        return JournalDay(localDate: date)
    }

    /// Asked of the server, so an entry sent by email counts. If it can't be reached: written,
    /// as far as anyone knows (and so today's entry is the one to write).
    func yesterdayIsUnwritten() async -> Bool {
        guard let yesterday else { return false }
        do { return try await entrySummary(on: yesterday) == nil } catch { return false }
    }

    /// After the Jump to a Day calendar closes: the day picked opens its entry in full, or, for
    /// a day without an entry, the composer opens on it.
    func finishDayPicker() {
        if let day = writeAfterDayPicker {
            writeAfterDayPicker = nil
            composingDay = StatsDay(day: day)
        } else if let day = pickedDay {
            pickedDay = nil
            dayPickerOpensOn = day
            openDay(day)
        }
    }

    /// Opens a written day's entry in full, in the Journal: over its list, or over the view it
    /// was picked from (Stats' grid), so Back lands there.
    func openDay(_ day: JournalDay, over mode: JournalMode? = nil) {
        Task {
            do {
                guard let entry = try await entrySummary(on: day) else { return }
                selectedTab = .journal
                openEntryOver = mode
                openEntryRequest = entry.id
            } catch is CancellationError {
            } catch {
                report(error)
            }
        }
    }

    /// Every day with an entry (YYYY-MM-DD), for the Journal's jump-to-a-day calendar.
    func entryDays(since: String? = nil) async throws -> [String] {
        struct DayList: Decodable { let days: [String] }
        // `since` (YYYY-MM-DD): only the days from then on. (An older server sends them all.)
        let list: DayList = try await api.get("api/v1/entries/days", query: since.map { ["since": $0] } ?? [:])
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
        entriesChanged += 1
        if envelope.entry.imageProcessing { watchProcessing(id: envelope.entry.id) }
        await loadToday()
        // Today's writing reminder isn't needed once there's an entry.
        await ReminderScheduler.shared.reschedule(for: self)
        ReviewPrompt.recordNewEntry()
        // Not waited on: the composer closes as soon as the entry is saved.
        Task { await considerReviewPrompt() }
        return envelope
    }

    // MARK: - App Store review

    /// Ask for a rating (`ReviewPrompt` says when): MainTabs asks once the composer has closed
    /// and nothing else is up.
    var reviewPromptPending = false
    /// TestFlight: the alert that stands in for the system prompt iOS won't show there.
    var showsReviewPromptStandIn = false
    private var reviewPromptVersion = ""
    private var reviewPromptInTestFlight = false

    private func considerReviewPrompt() async {
        let inTestFlight = await ReviewPrompt.runsFromTestFlight()
        let version = ReviewPrompt.version(inTestFlight: inTestFlight)
        let decision = ReviewPrompt.decision(version: version, ignoresGap: inTestFlight)
        ReviewPrompt.log.info("New entry saved, version \(version, privacy: .public): \(String(describing: decision), privacy: .public)")
        // Not on top of (or right after) the passkey prompt.
        guard decision == .ask, !passkeyPromptPending, !showsPasskeyPrompt else { return }
        reviewPromptVersion = version
        reviewPromptInTestFlight = inTestFlight
        reviewPromptPending = true
    }

    /// MainTabs is about to ask: counted as asked for this version, whether or not iOS shows it.
    /// Returns whether to show TestFlight's stand-in alert as well.
    func reviewPromptAsked() -> Bool {
        reviewPromptPending = false
        ReviewPrompt.markAsked(version: reviewPromptVersion)
        ReviewPrompt.log.info("Asked for a review, version \(self.reviewPromptVersion, privacy: .public)")
        return reviewPromptInTestFlight
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

    /// Counts the entries written, changed and deleted from the app: views that hold numbers
    /// counted from the journal (Stats) count again when it moves.
    private(set) var entriesChanged = 0

    /// Counts the photos that have finished processing while the app watched: views with their
    /// own lists (Photos) load again when it moves.
    private(set) var photosFinished = 0

    /// Re-fetches an entry until its photo or collage finishes processing, so the placeholder
    /// turns into the real image, in the timeline and on Today, without a manual refresh.
    func watchProcessing(id: Int) {
        guard !processingWatches.contains(id) else { return }
        processingWatches.insert(id)
        Task { [weak self] in
            defer { self?.processingWatches.remove(id) }
            for _ in 0..<60 { // ~5 minutes
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isSignedIn else { return }
                guard let entry = try? await self.entry(id: id) else { continue }
                if !entry.imageProcessing {
                    // Today holds its own copy of today's entry (and of the ones it looks back
                    // on), and so do the views that list photos: they pick the photo up too.
                    if self.today?.entry?.id == id || self.today?.onThisDay.contains(where: { $0.id == id }) == true
                        || self.today?.throwback?.id == id {
                        await self.loadToday()
                    }
                    self.photosFinished += 1
                    return
                }
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
        entriesChanged += 1
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
        entriesChanged += 1
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
        if let today: TodaySummary = try? await api.get("api/v1/today") {
            self.today = today
            WidgetSync.update(from: self) // the widget's day, and its look backs for the days ahead
        }
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
        return "\(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())) · \(day.ago(from: today))"
    }

    /// An on-device Apple Intelligence reflection on an entry (PRO). Only the entry itself: with other
    /// entries as context, the small model kept mixing their details in.
    func reflection(on entry: EntryDetail) async throws -> EntryReflection {
        let today = today?.day ?? JournalDay(localDate: .now)
        let text = try await JournalIntelligence.reflection(on: entry.bodyText, date: entry.day?.long ?? entry.date,
                                                            ago: entry.day?.ago(from: today) ?? "",
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

    /// An entry's calendar day in other years, for On This Day under it (nil from a server
    /// without the endpoint, or when it can't be reached: the entry just shows without it).
    func sameDay(as entryID: Int) async -> SameDayEntries? {
        try? await api.get("api/v1/entries/\(entryID)/same_day")
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
