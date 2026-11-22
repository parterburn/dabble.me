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

    private func perform(_ request: ASAuthorizationRequest, registering: Bool) async throws -> Outcome {
        self.registering = registering
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
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
