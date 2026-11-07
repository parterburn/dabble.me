import Foundation
import Observation

/// App-wide state: auth, the signed-in account, and the journal timeline. Detail,
/// compose and search screens call through here so edits show up in the timeline.
@MainActor
@Observable
final class AppModel {
    private(set) var isSignedIn: Bool
    private(set) var isSigningIn = false
    var signInError: String?

    private(set) var me: Me?
    private(set) var entries: [EntrySummary] = []
    private(set) var onThisDay: [EntrySummary] = []
    private(set) var nextPage: Int? = 1
    private(set) var isLoadingPage = false
    private(set) var hasLoaded = false
    var timelineError: String?

    let api: APIClient
    private let tokens: TokenProvider
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
            await tokens.store(try await OAuthEndpoints.exchange(code: code, pkce: pkce))
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
        entries = []
        onThisDay = []
        nextPage = 1
        hasLoaded = false
        timelineError = nil
    }

    // MARK: - Timeline

    /// Reloads the account and the first page (pull to refresh, app foreground).
    func refresh() async {
        guard isSignedIn else { return }
        do {
            async let meRequest: Me = api.get("api/v1/me")
            async let pageRequest: EntryPage = api.get("api/v1/entries", query: ["page": "1"])
            let (me, page) = try await (meRequest, pageRequest)
            self.me = me
            entries = page.entries
            nextPage = page.nextPage
            timelineError = nil
            hasLoaded = true
            await loadOnThisDay()
        } catch is CancellationError {
        } catch {
            report(error)
        }
    }

    func loadMoreIfNeeded(after entry: EntrySummary) async {
        guard entry.id == entries.last?.id, let page = nextPage, !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        do {
            let result: EntryPage = try await api.get("api/v1/entries", query: ["page": String(page)])
            let known = Set(entries.map(\.id))
            entries += result.entries.filter { !known.contains($0.id) }
            nextPage = result.nextPage
        } catch is CancellationError {
        } catch {
            report(error)
        }
    }

    private func loadOnThisDay() async {
        guard me?.isPro == true else {
            onThisDay = []
            return
        }
        onThisDay = (try? await api.get("api/v1/entries/on_this_day") as EntryList)?.entries ?? []
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

    /// Creates an entry (or appends to that day's entry, like the web) with an optional photo.
    func createEntry(day: JournalDay, text: String, photo: PreparedPhoto?) async throws -> EntryEnvelope {
        var imageKey: String?
        if let photo {
            let upload: ImageUpload = try await api.post("api/v1/image_uploads",
                                                        ImageUploadRequest(filename: photo.filename, contentType: photo.contentType))
            try await api.upload(photo.data, to: upload)
            imageKey = upload.uploadedImageKey
        }
        let envelope: EntryEnvelope = try await api.post("api/v1/entries",
                                                        NewEntryRequest(date: day.iso, body: text, uploadedImageKey: imageKey))
        upsert(envelope.entry.summary)
        return envelope
    }

    func updateEntry(id: Int, text: String) async throws -> EntryDetail {
        let envelope: EntryEnvelope = try await api.patch("api/v1/entries/\(id)", UpdateEntryRequest(body: text))
        upsert(envelope.entry.summary)
        return envelope.entry
    }

    func deleteEntry(id: Int) async throws {
        try await api.delete("api/v1/entries/\(id)")
        entries.removeAll { $0.id == id }
        onThisDay.removeAll { $0.id == id }
    }

    func search(_ query: String, page: Int = 1) async throws -> EntryPage {
        try await api.get("api/v1/search", query: ["q": query, "page": String(page)])
    }

    /// Keeps the timeline sorted newest first without refetching.
    private func upsert(_ summary: EntrySummary) {
        if let index = entries.firstIndex(where: { $0.id == summary.id }) {
            entries[index] = summary
        } else if hasLoaded {
            let insertAt = entries.firstIndex { $0.date < summary.date } ?? (nextPage == nil ? entries.endIndex : nil)
            if let insertAt { entries.insert(summary, at: insertAt) }
        }
    }
}
