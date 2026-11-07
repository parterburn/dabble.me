import Foundation

/// Owns the OAuth tokens. Refreshes are coalesced so parallel requests that all see
/// an expired token trigger a single refresh (Doorkeeper rotates refresh tokens).
actor TokenProvider {
    private var tokens: OAuthTokens?
    private var refreshTask: Task<OAuthTokens, Error>?
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

        let task = Task { try await OAuthEndpoints.refresh(refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            store(fresh)
            return fresh
        } catch APIError.signedOut {
            expire()
            throw APIError.signedOut
        }
    }

    func store(_ fresh: OAuthTokens) {
        tokens = fresh
        KeychainStore.save(fresh)
    }

    /// Clears tokens locally and returns the access token so the caller can revoke it.
    func clear() -> String? {
        let old = tokens?.accessToken
        tokens = nil
        KeychainStore.delete()
        return old
    }

    /// The server no longer accepts our tokens (password changed, app revoked on /security, ...).
    private func expire() {
        _ = clear()
        if let onSignedOut {
            Task { @MainActor in onSignedOut() }
        }
    }
}
