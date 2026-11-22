import Foundation

/// When the app asks someone to add a passkey: right after a password sign-in or sign-up, and
/// otherwise on opening the app, to an account without one. "Not Now" puts it off for
/// `snoozeDays`; after `maxAsks` of those it stops for good (Settings still has Add a Passkey).
/// Once the account has a passkey it never asks. The web asks the same way (`PasskeyNudge`).
enum PasskeyPrompt {
    static let snoozeDays = 30
    static let maxAsks = 3

    /// What the passkey is called on dabble.me/security.
    static let nickname = "Added in the iOS app"

    static let dismissalsKey = "passkeyPrompt.dismissals"
    static let snoozedUntilKey = "passkeyPrompt.snoozedUntil"

    /// Whether to ask now. A fresh sign-in asks even while put off (the password was just typed,
    /// so adding one is a single tap). It still stops after `maxAsks`.
    static func shouldAsk(hasPasskey: Bool?, justSignedIn: Bool, now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard hasPasskey == false, !isAutomated else { return false }
        if defaults.integer(forKey: dismissalsKey) >= maxAsks { return false }
        if justSignedIn { return true }
        let until = defaults.double(forKey: snoozedUntilKey)
        return until == 0 || now.timeIntervalSince1970 >= until
    }

    /// "Not Now", or the sheet swiped away: put off for `snoozeDays`, and counted.
    static func dismiss(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: dismissalsKey) + 1, forKey: dismissalsKey)
        defaults.set(now.addingTimeInterval(TimeInterval(snoozeDays) * 86_400).timeIntervalSince1970, forKey: snoozedUntilKey)
    }

    /// UI tests and screenshots sign in with a debug token: no prompt in their way.
    private static var isAutomated: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "DabbleDebugAccessToken")?.isEmpty == false
        #else
        false
        #endif
    }
}
