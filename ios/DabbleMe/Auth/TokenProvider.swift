import Foundation

/// Owns the OAuth tokens. Refreshes are coalesced so parallel requests that all see
/// an expired token trigger a single refresh (Doorkeeper rotates refresh tokens).
actor TokenProvider {
    private var tokens: OAuthTokens?
    private var refreshTask: Task<OAuthTokens, Error>?
    /// Bumped on sign-in and sign-out. A refresh that started in an earlier session must not
    /// write its result back (that would restore a signed-out session or clobber a new one).
    private var generation = 0
    private var onSignedOut: (@MainActor @Sendable () -> Void)?

    init() {
        tokens = KeychainStore.load()
    }

    var isSignedIn: Bool { tokens != nil }

    func setSignedOutHandler(_ handler: @escaping @MainActor @Sendable () -> Void) {
        onSignedOut = handler
    }

    func accessToken() async throws -> String {
        guard let tokens else { throw APIError.signedOut }
        if tokens.isNearExpiry, tokens.refreshToken != nil {
            return try await refresh().accessToken
        }
        return tokens.accessToken
    }

    func refresh() async throws -> OAuthTokens {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = tokens?.refreshToken else {
            expire()
            throw APIError.signedOut
        }

        let startedIn = generation
        let task = Task { try await OAuthEndpoints.refresh(refreshToken) }
        refreshTask = task
        defer { if generation == startedIn { refreshTask = nil } }
        do {
            let fresh = try await task.value
            guard generation == startedIn else { throw APIError.signedOut }
            save(fresh)
            return fresh
        } catch APIError.signedOut {
            if generation == startedIn { expire() }
            throw APIError.signedOut
        }
    }

    /// Starts a new session with tokens from sign-in.
    func signIn(with fresh: OAuthTokens) {
        startNewGeneration()
        save(fresh)
    }

    /// Clears tokens locally and returns the access token so the caller can revoke it.
    func clear() -> String? {
        startNewGeneration()
        let old = tokens?.accessToken
        tokens = nil
        KeychainStore.delete()
        return old
    }

    private func save(_ fresh: OAuthTokens) {
        tokens = fresh
        KeychainStore.save(fresh)
    }

    private func startNewGeneration() {
        generation += 1
        refreshTask = nil
    }

    /// The server no longer accepts our tokens (password changed, app revoked on /security, ...).
    private func expire() {
        _ = clear()
        if let onSignedOut {
            Task { @MainActor in onSignedOut() }
        }
    }
}
