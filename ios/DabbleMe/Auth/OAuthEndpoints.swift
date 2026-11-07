import Foundation

/// Doorkeeper token endpoints. The app is a public client: no secret, PKCE on the code grant.
enum OAuthEndpoints {
    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?
    }

    static func authorizeURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: AppConfig.webURL("oauth/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: AppConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: AppConfig.redirectURI),
            URLQueryItem(name: "scope", value: AppConfig.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    static func exchange(code: String, pkce: PKCE, session: URLSession = .shared) async throws -> OAuthTokens {
        try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": AppConfig.clientID,
            "redirect_uri": AppConfig.redirectURI,
            "code_verifier": pkce.verifier,
        ], session: session)
    }

    static func refresh(_ refreshToken: String, session: URLSession = .shared) async throws -> OAuthTokens {
        try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": AppConfig.clientID,
        ], session: session)
    }

    /// Best effort: signing out locally must not depend on the network.
    static func revoke(_ token: String, session: URLSession = .shared) async {
        var request = formRequest(path: "oauth/revoke", ["token": token, "client_id": AppConfig.clientID])
        request.timeoutInterval = 10
        _ = try? await session.data(for: request)
    }

    private static func tokenRequest(_ form: [String: String], session: URLSession) async throws -> OAuthTokens {
        let (data, response) = try await session.data(for: formRequest(path: "oauth/token", form))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Doorkeeper answers 400/401 with invalid_grant when a code or refresh token is spent or revoked.
        if status == 400 || status == 401 { throw APIError.signedOut }
        guard (200..<300).contains(status) else { throw APIError.server(status: status, code: "oauth_error", message: "Sign-in failed (\(status)).") }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let body = try decoder.decode(TokenResponse.self, from: data)
        return OAuthTokens(
            accessToken: body.accessToken,
            refreshToken: body.refreshToken,
            expiresAt: body.expiresIn.map { Date().addingTimeInterval($0) }
        )
    }

    private static func formRequest(path: String, _ form: [String: String]) -> URLRequest {
        var request = URLRequest(url: AppConfig.webURL(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" alone, which a form decoder would read as a space.
        request.httpBody = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        return request
    }
}
