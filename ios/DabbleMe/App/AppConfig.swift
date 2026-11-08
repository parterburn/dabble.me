import Foundation

/// Matches `MobileApp` on the Rails side (app/lib/mobile_app.rb).
enum AppConfig {
    static let clientID = "dabble-me-ios"
    static let scope = "app:journal"
    static let callbackScheme = "me.dabble.app"
    static let redirectURI = "me.dabble.app:/oauth/callback"

    static let productionURL = URL(string: "https://dabble.me")!

    /// `DABBLE_BASE_URL` build setting (Info.plist `DabbleBaseURL`): localhost for Debug, dabble.me for Release.
    static let defaultBaseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "DabbleBaseURL") as? String,
           !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        return productionURL
    }()

    static var baseURL: URL {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: serverOverrideKey), let url = URL(string: raw) {
            return url
        }
        #endif
        return defaultBaseURL
    }

    #if DEBUG
    /// Debug builds can point at another server from the sign-in screen (see ServerPicker).
    static let serverOverrideKey = "DabbleServerOverride"

    static func setServerOverride(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.absoluteString, forKey: serverOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: serverOverrideKey)
        }
    }
    #endif

    static func webURL(_ path: String) -> URL {
        baseURL.appending(path: path)
    }
}
