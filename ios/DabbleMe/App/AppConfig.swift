import Foundation

/// Matches `MobileApp` on the Rails side (app/lib/mobile_app.rb).
enum AppConfig {
    static let clientID = "dabble-me-ios"
    static let scope = "app:journal"
    static let callbackScheme = "me.dabble.app"
    static let redirectURI = "me.dabble.app:/oauth/callback"

    /// `DABBLE_BASE_URL` build setting (Info.plist `DabbleBaseURL`): localhost for Debug, dabble.me for Release.
    static let baseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "DabbleBaseURL") as? String,
           !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://dabble.me")!
    }()

    static func webURL(_ path: String) -> URL {
        baseURL.appending(path: path)
    }
}
