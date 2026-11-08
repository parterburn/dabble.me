import CryptoKit
import Foundation
import Security

/// RFC 7636 proof key (S256), required by the server's Doorkeeper config (`force_pkce`).
struct PKCE: Sendable {
    let verifier: String
    let challenge: String

    init(verifier: String = PKCE.randomURLSafeString(byteCount: 32)) {
        self.verifier = verifier
        challenge = PKCE.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
