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

/// The app's own sign-in and sign-up (`Api::V1::SessionsController`, `PasskeySessionsController`,
/// `RegistrationsController`). They answer with tokens shaped like /oauth/token's, so the
/// Keychain, refreshes and sign-out work as they did after the old web sign-in. Sign in with
/// Apple, when it comes, is one more call here that hands Apple's identity token to the server.
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

    /// GET /api/v1/session/passkey: the challenge (base64url) and its signed token, which goes
    /// back with the assertion.
    struct PasskeyChallenge: Decodable, Sendable {
        let challengeToken: String
        let challenge: String
        let rpId: String
    }

    static func passkeyChallenge(session: URLSession = .shared) async throws -> PasskeyChallenge {
        var request = URLRequest(url: AppConfig.webURL("api/v1/session/passkey"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, status) = try await send(request, session: session)
        guard (200..<300).contains(status) else { throw failure(status: status, data: data) }
        guard let challenge = try? APIClient.decoder.decode(PasskeyChallenge.self, from: data) else {
            throw NativeAuthError.message(APIError.decoding.errorDescription ?? "Sign-in failed.")
        }
        return challenge
    }

    static func signIn(with assertion: PasskeyAssertion, for challenge: PasskeyChallenge, session: URLSession = .shared) async throws -> Session {
        try await post("api/v1/session/passkey", PasskeyConfirmation(assertion: assertion, challenge: challenge), session: session)
    }

    /// A passkey assertion and its challenge token, as sign-in and Delete Account send them, in
    /// WebAuthn's JSON (camelCase keys, as the server's webauthn gem reads them). Encode it with
    /// a plain `JSONEncoder`, never `APIClient`'s snake_case one (`APIClient.post(_:json:)`).
    struct PasskeyConfirmation: Encodable, Sendable {
        struct Credential: Encodable, Sendable {
            struct Response: Encodable, Sendable {
                let clientDataJSON, authenticatorData, signature, userHandle: String
            }
            let id, rawId, type: String
            let response: Response
        }
        let challengeToken: String
        let credential: Credential

        enum CodingKeys: String, CodingKey {
            case challengeToken = "challenge_token", credential
        }

        init(assertion: PasskeyAssertion, challenge: PasskeyChallenge) {
            let id = NativeAuth.base64URL(assertion.credentialID)
            challengeToken = challenge.challengeToken
            credential = Credential(id: id, rawId: id, type: "public-key", response: .init(
                clientDataJSON: NativeAuth.base64URL(assertion.clientDataJSON),
                authenticatorData: NativeAuth.base64URL(assertion.authenticatorData),
                signature: NativeAuth.base64URL(assertion.signature),
                userHandle: NativeAuth.base64URL(assertion.userID)))
        }
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(base64URL string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?
        let deletionCancelled: Bool?
    }

    private static func post(_ path: String, _ body: some Encodable, session: URLSession) async throws -> Session {
        var request = URLRequest(url: AppConfig.webURL(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30

        let (data, status) = try await send(request, session: session)
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

    private static func send(_ request: URLRequest, session: URLSession) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw NativeAuthError.message("Couldn't reach Dabble Me. Check your connection and try again.")
        }
    }

    static func failure(status: Int, data: Data) -> NativeAuthError {
        // Rack::Attack's answer is plain text, not the API's JSON.
        if status == 429 { return .message("Too many tries. Wait a few minutes, then try again.") }
        let body = try? APIClient.decoder.decode(APIErrorBody.self, from: data)
        if body?.error == "otp_required" { return .needsCode }
        return .message(body?.details?.joined(separator: "\n") ?? body?.message ?? "Something went wrong (\(status)). Please try again.")
    }
}
