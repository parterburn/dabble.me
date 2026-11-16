import AppIntents
import Foundation

/// "New Entry" from outside the app's own screens: the control (Control Center, the Lock Screen,
/// the Action button) and Shortcuts. It opens the app, which then opens the composer as its other
/// New Entry shortcuts do: before 10 AM on yesterday if that isn't written, otherwise on today.
struct NewEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "New Entry"
    static let description = IntentDescription("Opens Dabble Me to write. In the morning it's yesterday's entry, if you haven't written it; otherwise today's.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NewEntryControlRequest.post()
        return .result()
    }
}

/// The intent's word to the app that New Entry was asked for. Kept in the App Group, so it
/// arrives whichever process ran the intent, and for a moment only: one the app didn't pick up
/// (it was signed out, say) doesn't open the composer some later day.
enum NewEntryControlRequest {
    static let key = "control.newEntryRequestedAt"
    static let notification = Notification.Name("me.dabble.app.newEntryRequested")
    static let lifetime: TimeInterval = 60

    static func post(at date: Date = .now) {
        record(at: date)
        // Heard when the intent runs in the app itself; otherwise the app looks when it comes forward.
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// Leaves the word without announcing it.
    static func record(at date: Date = .now) {
        WidgetSnapshot.defaults?.set(date.timeIntervalSince1970, forKey: key)
    }

    /// Whether New Entry was just asked for. Once: asking again says no.
    static func take(at date: Date = .now) -> Bool {
        guard let defaults = WidgetSnapshot.defaults, defaults.object(forKey: key) != nil else { return false }
        let asked = defaults.double(forKey: key)
        defaults.removeObject(forKey: key)
        let age = date.timeIntervalSince1970 - asked
        return age >= 0 && age <= lifetime
    }
}
