import AuthenticationServices
import UIKit

enum WebAuthError: LocalizedError {
    case cancelled
    case couldNotStart
    case invalidCallback(String?)

    var errorDescription: String? {
        switch self {
        case .cancelled: nil
        case .couldNotStart: "Couldn't open the sign-in page."
        case .invalidCallback(let reason): reason ?? "Sign-in didn't complete. Please try again."
        }
    }
}

/// Runs the dabble.me sign-in page in ASWebAuthenticationSession. It shares Safari's
/// cookies (not ephemeral), so a user already signed in on the web just taps through,
/// and passkeys / 2FA work exactly as they do on the website. After an explicit Sign Out,
/// the next sign-in is `ephemeral` instead: it ignores Safari's session, so it asks for the
/// password again (and another account can sign in).
@MainActor
final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, ephemeral: Bool = false) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(AppConfig.callbackScheme)) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: WebAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? WebAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = ephemeral
            self.session = session
            if !session.start() {
                continuation.resume(throwing: WebAuthError.couldNotStart)
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard let scene else { preconditionFailure("No window scene to present sign-in from") }
            return scene.keyWindow ?? UIWindow(windowScene: scene)
        }
    }
}
