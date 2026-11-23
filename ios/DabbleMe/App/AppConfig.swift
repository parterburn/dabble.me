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

    /// "iPhone", "iPad" or "Mac", sent as X-Dabble-Device so the Sessions list on dabble.me can
    /// name this device. Read from hw.machine (e.g. "iPad14,1"); no name or identifier leaves it.
    static let deviceFamily: String = {
        if ProcessInfo.processInfo.isiOSAppOnMac { return "Mac" }
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "iPhone" }
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let model = machine.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return model.hasPrefix("iPad") ? "iPad" : "iPhone"
    }()

    static func webURL(_ path: String) -> URL {
        baseURL.appending(path: path)
    }
}
