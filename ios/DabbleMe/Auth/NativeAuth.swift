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

/// The app's own sign-in and sign-up (`Api::V1::EmailCodesController`, `SessionsController`,
/// `PasskeySessionsController`, and `RegistrationsController` for older builds). They answer with tokens shaped like /oauth/token's, so the
/// Keychain, refreshes and sign-out work as they did after the old web sign-in. Sign in with
/// Apple, when it comes, is one more call here that hands Apple's identity token to the server.
enum NativeAuth {
    struct Session: Sendable {
        let tokens: OAuthTokens
        /// The account was set to be deleted, and signing in kept it.
        let deletionCancelled: Bool
        /// After a password or email-code sign-in or sign-up, for an account with no passkey:
        /// lets the app add one in the next few minutes without asking for the password again.
        var passkeySetupToken: String? = nil
        /// An email-code sign-in that made the account (a sign-up, so no passkey prompt).
        var created = false
    }

    /// POST /api/v1/session/code's answer. The same for every address, with an account or
    /// without (the server never says which), so the code screen always follows.
    struct CodeSent: Decodable, Sendable {
        let email: String
        let expiresIn: Int?
        let resendAfter: Int?
    }

    /// Emails a six-digit code to `email`: the passwordless way in, for an account or a new one.
    static func sendCode(email: String, session: URLSession = .shared) async throws -> CodeSent {
        var request = URLRequest(url: AppConfig.webURL("api/v1/session/code"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["email": email])
        request.timeoutInterval = 30
        let (data, status) = try await send(request, session: session)
        guard (200..<300).contains(status) else { throw failure(status: status, data: data) }
        guard let sent = try? APIClient.decoder.decode(CodeSent.self, from: data) else {
            throw NativeAuthError.message(APIError.decoding.errorDescription ?? "Couldn't send a code.")
        }
        return sent
    }

    /// The emailed code: signs in, or makes the account when the address had none. With 2FA on,
    /// the server asks for the authenticator code (`.needsCode`) and the same emailed code goes
    /// again with it.
    static func signIn(email: String, emailCode: String, otpCode: String?, session: URLSession = .shared) async throws -> Session {
        var body = ["email": email, "code": emailCode]
        if let otpCode, !otpCode.isEmpty { body["otp_code"] = otpCode }
        return try await post("api/v1/session/code/verify", body, session: session)
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

    /// The password, or the sign-in's setup token, that adding a passkey needs: sent for the
    /// options (so a wrong one is caught before the system's sheet saves a passkey on the phone)
    /// and again with the passkey.
    struct PasskeyProof: Encodable, Sendable {
        let setupToken: String?
        let currentPassword: String?
        /// For an account with no password: a code from POST /api/v1/confirmation_code. It works
        /// once, so the options answer carries a setup token for the call after.
        var emailCode: String? = nil

        enum CodingKeys: String, CodingKey {
            case setupToken = "setup_token", currentPassword = "current_password", emailCode = "email_code"
        }
    }

    /// POST /api/v1/passkeys/options: what the system needs to make a passkey for the signed-in
    /// account. `userId` and the excluded IDs are base64url, as WebAuthn's JSON has them.
    struct PasskeyCreation: Decodable, Sendable {
        let challengeToken: String
        let challenge: String
        let rpId: String
        let userId: String
        let userName: String
        let excludeCredentials: [String]?
        /// Sent back when an emailed code was the proof: it stands in for the code with the passkey.
        let setupToken: String?
    }

    /// The new passkey, for POST /api/v1/passkeys, with the password or the sign-in's setup
    /// token. Encode it with a plain `JSONEncoder` (WebAuthn's camelCase keys), as above.
    struct NewPasskey: Encodable, Sendable {
        struct Credential: Encodable, Sendable {
            struct Response: Encodable, Sendable {
                let clientDataJSON, attestationObject: String
            }
            let id, rawId, type: String
            let response: Response
        }
        let challengeToken: String
        let credential: Credential
        let nickname: String
        let setupToken: String?
        let currentPassword: String?

        enum CodingKeys: String, CodingKey {
            case challengeToken = "challenge_token", credential, nickname
            case setupToken = "setup_token", currentPassword = "current_password"
        }

        init(registration: PasskeyRegistration, creation: PasskeyCreation, nickname: String, setupToken: String?, password: String?) {
            let id = NativeAuth.base64URL(registration.credentialID)
            challengeToken = creation.challengeToken
            credential = Credential(id: id, rawId: id, type: "public-key", response: .init(
                clientDataJSON: NativeAuth.base64URL(registration.clientDataJSON),
                attestationObject: NativeAuth.base64URL(registration.attestationObject)))
            self.nickname = nickname
            self.setupToken = setupToken
            currentPassword = password
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
        let passkeySetupToken: String?
        let created: Bool?
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
            deletionCancelled: body.deletionCancelled ?? false,
            passkeySetupToken: body.passkeySetupToken,
            created: body.created ?? false
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
        let body = try? APIClient.decoder.decode(APIErrorBody.self, from: data)
        // Rack::Attack's answer is plain text, not the API's JSON (a code sent moments ago is JSON).
        if status == 429 { return .message(body?.message ?? "Too many tries. Wait a few minutes, then try again.") }
        if body?.error == "otp_required" { return .needsCode }
        return .message(body?.details?.joined(separator: "\n") ?? body?.message ?? "Something went wrong (\(status)). Please try again.")
    }
}
