import Foundation
import OSLog
import StoreKit

/// When the app asks for an App Store rating (SwiftUI's `requestReview`, which iOS may or may not
/// show, and caps at three times a year): right after a new entry saves from the composer, on the
/// `minimumWritingDays`th different day (by the phone's calendar) a new entry has been saved in
/// the app. Once per app version, and never within `minimumDaysBetweenAsks` of the last ask.
/// Edits, failed saves and entries written by email never count. Days are counted from this
/// build on: nothing from before it is known.
///
/// TestFlight never shows the system prompt, so there the app says, in an alert, that this is
/// where it would have been; and there "this version" is the version and build, so each new
/// build can be checked again. Every decision goes to the log (category "ReviewPrompt").
enum ReviewPrompt {
    static let minimumWritingDays = 3
    static let minimumDaysBetweenAsks = 120
    /// Only the most recent days are kept: enough to count to `minimumWritingDays`.
    static let keptDays = 10

    static let writingDaysKey = "reviewPrompt.writingDays"
    static let askedVersionKey = "reviewPrompt.askedVersion"
    static let askedAtKey = "reviewPrompt.askedAt"

    static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "me.dabble.ios", category: "ReviewPrompt")

    enum Decision: Equatable {
        case ask
        case tooFewDays(Int)
        case askedThisVersion
        case askedRecently(daysAgo: Int)
        case automated
    }

    /// A new entry saved in the app, today: today is counted as a writing day.
    static func recordNewEntry(now: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        let today = JournalDay(localDate: now, calendar: calendar).iso
        var days = defaults.stringArray(forKey: writingDaysKey) ?? []
        guard !days.contains(today) else { return }
        days.append(today)
        defaults.set(Array(days.sorted().suffix(keptDays)), forKey: writingDaysKey)
    }

    /// Whether to ask now, and if not, why (for the log).
    static func decision(version: String, ignoresGap: Bool = false, now: Date = Date(),
                         defaults: UserDefaults = .standard) -> Decision {
        if isAutomated { return .automated }
        let days = defaults.stringArray(forKey: writingDaysKey)?.count ?? 0
        guard days >= minimumWritingDays else { return .tooFewDays(days) }
        if defaults.string(forKey: askedVersionKey) == version { return .askedThisVersion }
        let askedAt = defaults.double(forKey: askedAtKey)
        if !ignoresGap, askedAt > 0 {
            let daysAgo = Int(now.timeIntervalSince1970 - askedAt) / 86_400
            if daysAgo < minimumDaysBetweenAsks { return .askedRecently(daysAgo: daysAgo) }
        }
        return .ask
    }

    /// The prompt was asked for (whether iOS showed it, nobody can tell).
    static func markAsked(version: String, now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: askedVersionKey)
        defaults.set(now.timeIntervalSince1970, forKey: askedAtKey)
    }

    /// The version an ask is kept against: the App Store version, plus the build in TestFlight.
    static func version(inTestFlight: Bool, bundle: Bundle = .main) -> String {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        guard inTestFlight else { return short }
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Installed from TestFlight (StoreKit's sandbox), where iOS never shows the prompt. Not an
    /// Xcode build: there the prompt shows every time it's asked for.
    static func runsFromTestFlight() async -> Bool {
        guard let result = try? await AppTransaction.shared else { return false }
        switch result {
        case .verified(let transaction), .unverified(let transaction, _):
            return transaction.environment == .sandbox
        }
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
