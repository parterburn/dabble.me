import Foundation
import UIKit
import UserNotifications

/// Reminder preferences (per device). Times are minutes after midnight, local time.
enum ReminderSettings {
    static let writingEnabledKey = "reminders.writing.enabled"
    static let writingTimeKey = "reminders.writing.minutes"
    static let memoriesEnabledKey = "reminders.memories.enabled"
    static let memoriesTimeKey = "reminders.memories.minutes"

    static let defaultWritingTime = 20 * 60 // 8:00 PM
    static let defaultMemoriesTime = 9 * 60 // 9:00 AM

    static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

struct MemoryDay: Decodable, Sendable {
    let date: String
    let count: Int
    let firstYear: Int
}

struct MemoryDayList: Decodable, Sendable {
    let days: [MemoryDay]
}

/// Local notifications for PRO reminders: a daily nudge to write (skipped on days that already
/// have an entry) and "On This Day" on days with memories. Everything is scheduled on the device
/// and rebuilt whenever something changes, so there's no server push to set up. Notifications
/// never include entry text; they can appear on a lock screen.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private let center = UNUserNotificationCenter.current()
    private let prefix = "dabbleme."
    private let writingDays = 14
    private let memoryDays = 30

    /// Asks for permission if needed. Returns false when the user has said no (now or before).
    func requestPermission() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }.count
    }

    func isDenied() async -> Bool {
        await center.notificationSettings().authorizationStatus == .denied
    }

    func removeAll() {
        Task {
            let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Rebuilds every pending reminder from the current settings and account.
    func reschedule(for model: AppModel) async {
        let existing = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)

        let defaults = UserDefaults.standard
        guard model.isSignedIn, model.me?.isPro == true,
              await center.notificationSettings().authorizationStatus == .authorized else { return }

        if defaults.bool(forKey: ReminderSettings.writingEnabledKey) {
            let minutes = defaults.object(forKey: ReminderSettings.writingTimeKey) as? Int ?? ReminderSettings.defaultWritingTime
            let wroteToday = model.today?.entry != nil
            for offset in 0..<writingDays where !(offset == 0 && wroteToday) {
                guard let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()) else { continue }
                let content = UNMutableNotificationContent()
                content.title = "How was your day?"
                content.body = "Take a minute to write it down in Dabble Me."
                content.sound = .default
                content.userInfo = ["destination": "write"]
                await add(content, id: "write.\(Self.isoDay(day))", on: day, minutes: minutes)
            }
        }

        if defaults.bool(forKey: ReminderSettings.memoriesEnabledKey),
           let list: MemoryDayList = try? await model.api.get("api/v1/entries/memory_days", query: ["days": String(memoryDays)]) {
            let minutes = defaults.object(forKey: ReminderSettings.memoriesTimeKey) as? Int ?? ReminderSettings.defaultMemoriesTime
            for memory in list.days {
                guard let day = JournalDay(memory.date)?.localDate else { continue }
                let content = UNMutableNotificationContent()
                content.title = "On This Day"
                content.body = memory.count == 1
                    ? "You wrote on this day in \(memory.firstYear). Take a look back."
                    : "You have \(memory.count) memories from this day, going back to \(memory.firstYear)."
                content.sound = .default
                content.userInfo = ["destination": "today"]
                await add(content, id: "memories.\(memory.date)", on: day, minutes: minutes)
            }
        }
    }

    private func add(_ content: UNMutableNotificationContent, id: String, on day: Date, minutes: Int) async {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        guard let fireDate = Calendar.current.date(from: parts), fireDate > Date() else { return }
        let request = UNNotificationRequest(identifier: prefix + id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        try? await center.add(request)
    }

    private static func isoDay(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Routes notification taps into the app: writing reminders open the composer, memories open Today.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()
    @MainActor weak var model: AppModel?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let destination = response.notification.request.content.userInfo["destination"] as? String
        await MainActor.run {
            guard let model else { return }
            model.selectedTab = .today
            if destination == "write" { model.composeRequest = true }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
