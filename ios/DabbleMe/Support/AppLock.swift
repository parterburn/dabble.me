import Foundation
import LocalAuthentication
import Observation

/// Optional Face ID / Touch ID (or device passcode) lock. Locks on launch and after a minute in
/// the background; while the app isn't active, a cover hides the journal in the app switcher.
@MainActor
@Observable
final class AppLock {
    static let enabledKey = "lock.enabled"
    static var gracePeriod: TimeInterval {
        #if DEBUG
        // UI tests: -DabbleLockGrace 0 locks as soon as the app leaves the foreground.
        if let raw = UserDefaults.standard.string(forKey: "DabbleLockGrace"), let seconds = Double(raw) { return seconds }
        #endif
        return 60
    }

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    private(set) var isLocked: Bool
    private var backgroundedAt: Date?
    private var isAuthenticating = false

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    /// "Face ID", "Touch ID", "Optic ID", or "Passcode" when there's no biometry.
    var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// Whether the device can lock at all (a passcode is required for any of these).
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func didEnterBackground() {
        backgroundedAt = Date()
    }

    func willEnterForeground() {
        guard isEnabled, let backgroundedAt else { return }
        if Date().timeIntervalSince(backgroundedAt) >= Self.gracePeriod { isLocked = true }
        self.backgroundedAt = nil
    }

    /// Prompts for Face ID (falling back to the passcode). Returns true when unlocked.
    @discardableResult
    func authenticate(reason: String = "Unlock your journal") async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        let success = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
        if success { isLocked = false }
        return success
    }

    /// Turning the lock on asks to authenticate first, so nobody gets locked out of a device
    /// without a passcode (or by a mistaken tap).
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            guard await authenticate(reason: "Turn on the lock for your journal") else { return }
        }
        isEnabled = enabled
        if !enabled { isLocked = false }
    }

    func reset() {
        isEnabled = false
        isLocked = false
    }
}
