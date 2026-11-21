import Foundation

/// Why a native sign-in or sign-up didn't go through, worded for the form.
enum NativeAuthError: LocalizedError, Equatable {
    /// The password was right and the account has 2FA: ask for the code, then send all three again.
    case needsCode
    case message(String)

    var errorDescription: String? {
        switch self {
        case .needsCode: "Enter the 6-digit code from your authenticator app."
        case .message(let text): text
        }
    }
}

/// The app's own sign-in and sign-up forms (`Api::V1::SessionsController`,
/// `RegistrationsController`). They answer with tokens shaped like /oauth/token's, so the
/// Keychain, refreshes and sign-out work as they do after the web sign-in. Sign in with Apple,
/// when it comes, is one more call here that hands Apple's identity token to the server.
enum NativeAuth {
    struct Session: Sendable {
        let tokens: OAuthTokens
        /// The account was set to be deleted, and signing in kept it.
        let deletionCancelled: Bool
    }

    static func signIn(email: String, password: String, code: String?, session: URLSession = .shared) async throws -> Session {
        var body = ["email": email, "password": password]
        if let code, !code.isEmpty { body["otp_code"] = code }
        return try await post("api/v1/session", body, session: session)
    }

    static func signUp(email: String, password: String, firstName: String?, session: URLSession = .shared) async throws -> Session {
        var body = ["email": email, "password": password]
        if let firstName, !firstName.isEmpty { body["first_name"] = firstName }
        return try await post("api/v1/registration", body, session: session)
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?
        let deletionCancelled: Bool?
    }

    private static func post(_ path: String, _ body: [String: String], session: URLSession) async throws -> Session {
        var request = URLRequest(url: AppConfig.webURL(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NativeAuthError.message("Couldn't reach Dabble Me. Check your connection and try again.")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw failure(status: status, data: data) }
        guard let body = try? APIClient.decoder.decode(TokenResponse.self, from: data) else {
            throw NativeAuthError.message(APIError.decoding.errorDescription ?? "Sign-in failed.")
        }
        return Session(
            tokens: OAuthTokens(accessToken: body.accessToken, refreshToken: body.refreshToken,
                                expiresAt: body.expiresIn.map { Date().addingTimeInterval($0) }),
            deletionCancelled: body.deletionCancelled ?? false
        )
    }

    static func failure(status: Int, data: Data) -> NativeAuthError {
        // Rack::Attack's answer is plain text, not the API's JSON.
        if status == 429 { return .message("Too many tries. Wait a few minutes, then try again.") }
        let body = try? APIClient.decoder.decode(APIErrorBody.self, from: data)
        if body?.error == "otp_required" { return .needsCode }
        return .message(body?.details?.joined(separator: "\n") ?? body?.message ?? "Something went wrong (\(status)). Please try again.")
    }
}
