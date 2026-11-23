import AuthenticationServices
import UIKit

/// What the passkey sheet hands back, ready for `POST /api/v1/session/passkey`.
struct PasskeyAssertion: Sendable {
    let credentialID: Data
    let clientDataJSON: Data
    let authenticatorData: Data
    let signature: Data
    let userID: Data
}

/// What the sheet hands back after making a passkey, ready for `POST /api/v1/passkeys`.
struct PasskeyRegistration: Sendable {
    let credentialID: Data
    let clientDataJSON: Data
    let attestationObject: Data
}

/// Signs in with a dabble.me passkey from the system's passkey sheet (Face ID, then the
/// passkey from iCloud Keychain or a password manager, or another device by QR code), and makes
/// new ones the same way. The app may use the site's passkeys because of `webcredentials:dabble.me`
/// in its entitlements and the matching entry in the site's apple-app-site-association file.
@MainActor
final class PasskeyAuthenticator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    /// What the delegate hands back, already read out of the system's (non-Sendable) objects.
    private enum Outcome: Sendable {
        case assertion(PasskeyAssertion)
        case registration(PasskeyRegistration)
    }

    private var continuation: CheckedContinuation<Outcome, Error>?
    /// Making a passkey rather than using one: its errors read differently.
    private var registering = false
    private var controller: ASAuthorizationController?

    /// Throws `CancellationError` when the person closes the sheet.
    func assert(relyingParty: String, challenge: Data) async throws -> PasskeyAssertion {
        defer { controller = nil }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.userVerificationPreference = .required
        guard case .assertion(let assertion) = try await perform(request, registering: false) else {
            throw NativeAuthError.message("That passkey didn't work. Try again, or use your password.")
        }
        return assertion
    }

    /// The account's passkeys offered above the keyboard while the email field is focused (the
    /// QuickType bar), the app's version of the web's passkey autofill. Waits until one is picked;
    /// `cancel()` ends the wait with `CancellationError`. Use its own authenticator, apart from
    /// the one the passkey button uses: each handles one request at a time.
    func autoFillAssertion(relyingParty: String, challenge: Data) async throws -> PasskeyAssertion {
        // Cancelled while the challenge was on its way: don't start.
        if cancelRequested {
            cancelRequested = false
            throw CancellationError()
        }
        defer { controller = nil }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.userVerificationPreference = .required
        guard case .assertion(let assertion) = try await perform(request, registering: false, autoFill: true) else {
            throw NativeAuthError.message("That passkey didn't work. Try again, or use your email.")
        }
        return assertion
    }

    /// Ends a waiting request (autofill, when the form goes away or the passkey button is used),
    /// or the next one, when it hasn't started yet (`prepareAutoFill` clears that).
    func cancel() {
        if let controller {
            controller.cancel()
        } else {
            cancelRequested = true
        }
    }

    /// Before fetching an autofill request's challenge: forget a cancel meant for an earlier one.
    func prepareAutoFill() {
        cancelRequested = false
    }

    private var cancelRequested = false

    /// Makes a passkey for the signed-in account (saved to iCloud Keychain, or the password
    /// manager the person picks). `userID` is the account's user handle, as the server gives it.
    /// Throws `CancellationError` when the person closes the sheet.
    func register(relyingParty: String, challenge: Data, userName: String, userID: Data, excluding: [Data] = []) async throws -> PasskeyRegistration {
        defer { controller = nil }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userID)
        request.userVerificationPreference = .required
        request.excludedCredentials = excluding.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0) }
        guard case .registration(let registration) = try await perform(request, registering: true) else {
            throw NativeAuthError.message("Couldn't add a passkey. Try again.")
        }
        return registration
    }

    private func perform(_ request: ASAuthorizationRequest, registering: Bool, autoFill: Bool = false) async throws -> Outcome {
        self.registering = registering
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            if autoFill {
                controller.performAutoFillAssistedRequests()
            } else {
                controller.performRequests()
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
                finish(.success(.assertion(PasskeyAssertion(
                    credentialID: credential.credentialID,
                    clientDataJSON: credential.rawClientDataJSON,
                    authenticatorData: credential.rawAuthenticatorData,
                    signature: credential.signature,
                    userID: credential.userID
                ))))
            } else if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
                      let attestation = credential.rawAttestationObject {
                finish(.success(.registration(PasskeyRegistration(
                    credentialID: credential.credentialID,
                    clientDataJSON: credential.rawClientDataJSON,
                    attestationObject: attestation
                ))))
            } else {
                finish(.failure(NativeAuthError.message(registering ? "Couldn't add a passkey. Try again."
                                                                    : "That passkey didn't work. Try again, or use your password.")))
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            if let error = error as? ASAuthorizationError, error.code == .canceled {
                finish(.failure(CancellationError()))
            } else if registering {
                finish(.failure(NativeAuthError.message("Couldn't add a passkey. Try again.")))
            } else {
                finish(.failure(NativeAuthError.message("Couldn't use a passkey. Try again, or use your password.")))
            }
        }
    }

    private func finish(_ result: Result<Outcome, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard let scene else { preconditionFailure("No window scene to present the passkey sheet from") }
            return scene.keyWindow ?? UIWindow(windowScene: scene)
        }
    }
}
