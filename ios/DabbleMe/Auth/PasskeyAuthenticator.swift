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

/// Signs in with a dabble.me passkey from the system's passkey sheet (Face ID, then the
/// passkey from iCloud Keychain or a password manager, or another device by QR code). The app
/// may use the site's passkeys because of `webcredentials:dabble.me` in its entitlements and the
/// matching entry in the site's apple-app-site-association file.
@MainActor
final class PasskeyAuthenticator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<PasskeyAssertion, Error>?
    private var controller: ASAuthorizationController?

    /// Throws `CancellationError` when the person closes the sheet.
    func assert(relyingParty: String, challenge: Data) async throws -> PasskeyAssertion {
        defer { controller = nil }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingParty)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.userVerificationPreference = .required
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
            guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
                finish(.failure(NativeAuthError.message("That passkey didn't work. Try again, or use your password.")))
                return
            }
            finish(.success(PasskeyAssertion(
                credentialID: credential.credentialID,
                clientDataJSON: credential.rawClientDataJSON,
                authenticatorData: credential.rawAuthenticatorData,
                signature: credential.signature,
                userID: credential.userID
            )))
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            if let error = error as? ASAuthorizationError, error.code == .canceled {
                finish(.failure(CancellationError()))
            } else {
                finish(.failure(NativeAuthError.message("Couldn't use a passkey. Try again, or use your password.")))
            }
        }
    }

    private func finish(_ result: Result<PasskeyAssertion, Error>) {
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
