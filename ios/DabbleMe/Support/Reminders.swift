import Foundation
import UIKit
import UserNotifications

/// Reminder preferences (per device). Times are minutes after midnight, local time.
enum ReminderSettings {
    /// The daily reminder: one notification a day, with an entry to look back on.
    static let enabledKey = "reminders.daily.enabled"
    /// Its time, once the person has set one; until then it follows the daily email's hour.
    static let timeKey = "reminders.daily.minutes"
    /// The daily email's hour as minutes, last heard from the server.
    static let emailTimeKey = "reminders.emailMinutes"
    /// The notification shows the start of the entry and its photo (on unless switched off).
    static let previewsKey = "reminders.previews"
    /// The days it goes out ("Sun"…"Sat", comma-separated; every day unless chosen).
    static let daysKey = "reminders.days"
    /// It carries a past entry to look back on (on unless switched off), and which ones (PRO):
    /// words that leave entries out, and whether to go back over a year. Like the email's, but
    /// the reminder's own.
    static let pastEntriesKey = "reminders.pastEntries"
    static let pastFilterKey = "reminders.pastFilter"
    static let includeOldKey = "reminders.includeOld"
    static let followsEmail = -1
    static let defaultTime = 20 * 60 // 8:00 PM, until the email's hour is known

    /// The two reminders this one replaced (a writing nudge, and On This Day on its own).
    private static let oldWritingEnabledKey = "reminders.writing.enabled"
    private static let oldWritingTimeKey = "reminders.writing.minutes"
    private static let oldMemoriesEnabledKey = "reminders.memories.enabled"

    static var showsPreviews: Bool { UserDefaults.standard.object(forKey: previewsKey) as? Bool ?? true }
    static var includesPastEntries: Bool { UserDefaults.standard.object(forKey: pastEntriesKey) as? Bool ?? true }
    static var includesOldEntries: Bool { UserDefaults.standard.object(forKey: includeOldKey) as? Bool ?? true }
    static var pastFilter: String { UserDefaults.standard.string(forKey: pastFilterKey) ?? "" }

    /// The days it goes out, in the week's order.
    static var days: [String] {
        guard let stored = UserDefaults.standard.string(forKey: daysKey) else { return EmailSchedule.allDays }
        return days(from: stored)
    }

    static func days(from stored: String) -> [String] {
        let chosen = Set(stored.split(separator: ",").map(String.init))
        return EmailSchedule.allDays.filter(chosen.contains)
    }

    /// "Every day · 8:00 PM", "Weekdays · 7:30 AM", "Off": the reminder in a line, for Settings.
    static func summary(enabled: Bool, days: [String], minutes: Int) -> String {
        guard enabled, !days.isEmpty else { return "Off" }
        let when: String
        switch days {
        case EmailSchedule.allDays: when = "Every day"
        case ["Mon", "Tue", "Wed", "Thu", "Fri"]: when = "Weekdays"
        case ["Sun", "Sat"]: when = "Weekends"
        case let one where one.count == 1:
            when = Calendar.current.weekdaySymbols[EmailSchedule.allDays.firstIndex(of: one[0]) ?? 0] + "s"
        default: when = days.joined(separator: ", ")
        }
        return "\(when) · \(date(fromMinutes: minutes).formatted(date: .omitted, time: .shortened))"
    }

    /// When the reminder goes out: the time set, or else the daily email's.
    static var minutes: Int {
        let defaults = UserDefaults.standard
        if let set = defaults.object(forKey: timeKey) as? Int, set >= 0 { return set }
        return defaults.object(forKey: emailTimeKey) as? Int ?? defaultTime
    }

    /// Once: someone with either of the old reminders on has the daily one on, at the time they
    /// had picked for writing.
    static func migrate() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: enabledKey) == nil else { return }
        let writing = defaults.bool(forKey: oldWritingEnabledKey)
        defaults.set(writing || defaults.bool(forKey: oldMemoriesEnabledKey), forKey: enabledKey)
        if writing, let time = defaults.object(forKey: oldWritingTimeKey) as? Int { defaults.set(time, forKey: timeKey) }
    }

    static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// GET /api/v1/reminders: the entry to look back on for each of the coming days.
struct ReminderPlan: Decodable, Sendable {
    let emailHour: Int
    /// How many entries the reminder's left-out words leave out (nil from an older server).
    var filteredCount: Int? = nil
    let days: [Day]

    struct Day: Decodable, Sendable {
        let date: String
        /// "on_this_day" (this date in an earlier year) or "rewind" (another past entry).
        let kind: String
        let count: Int
        let entry: Entry

        var isOnThisDay: Bool { kind == "on_this_day" }
    }

    struct Entry: Decodable, Sendable {
        let id: Int
        let date: String
        let excerpt: String
        let imageUrl: String?
    }
}

/// Local notifications: one a day at the reminder's time, with an entry to look back on (this
/// date in an earlier year, or else the day's Rewind, as Today shows). Today's is skipped once
/// today is written. With entry previews on (Settings), it's that entry: "Rewind · 22 days ago"
/// over the start of it, and its photo. Without, "How was your day?" and only that there's a
/// memory. A tap opens Today; touch and hold offers reading the memory or writing. Everything is scheduled on the device, two weeks ahead,
/// and rebuilt whenever the app opens or something changes (and now and then in the background),
/// so there's no server push to set up.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    nonisolated static let memoryCategory = "dabbleme.daily.memory"
    nonisolated static let readAction = "dabbleme.read"
    nonisolated static let writeAction = "dabbleme.write"

    private let center = UNUserNotificationCenter.current()
    private let prefix = "dabbleme."
    private let days = 14
    /// The last plan fetched, kept a while: the app reschedules on every refresh.
    private var cached: (plan: ReminderPlan, key: String, at: Date)?
    #if DEBUG
    private var debugSoonID: String?
    #endif
    /// How many entries the left-out words leave out, as the server last said (for Settings).
    private(set) var filteredCount: Int?
    /// Bumped on sign-out: a rebuild checks it's still on the session it started in before it
    /// keeps or schedules anything.
    private var session = 0
    private var isScheduling = false
    private var needsAnotherPass = false

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

    /// Signing out: nothing pending stays, and a rebuild that's under way (waiting on the plan or
    /// a photo) stops short of scheduling that account's entries after it.
    func removeAll() {
        session += 1
        cached = nil
        Task {
            let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Rebuilds every pending reminder from the current settings and account. One pass at a time:
    /// a change that comes in the middle of one is picked up by another pass after it.
    func reschedule(for model: AppModel) async {
        guard !isScheduling else { needsAnotherPass = true; return }
        isScheduling = true
        defer { isScheduling = false }
        repeat {
            needsAnotherPass = false
            await rebuild(for: model)
        } while needsAnotherPass
    }

    private func rebuild(for model: AppModel) async {
        ReminderSettings.migrate()
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.memoryCategory, actions: [
            UNNotificationAction(identifier: Self.readAction, title: "Read the Memory", options: .foreground),
            UNNotificationAction(identifier: Self.writeAction, title: "Write Today's Entry", options: .foreground),
        ], intentIdentifiers: [])])

        let defaults = UserDefaults.standard
        let session = session
        // Still the account this pass began with (not signed out since, perhaps into another).
        func isCurrent() -> Bool { session == self.session && model.isSignedIn }
        guard model.isSignedIn, defaults.bool(forKey: ReminderSettings.enabledKey),
              await center.notificationSettings().authorizationStatus == .authorized else {
            await removePending()
            return
        }
        let plan = await plan(for: model, session: session)
        guard isCurrent() else { return }
        if let plan { defaults.set(plan.emailHour * 60, forKey: ReminderSettings.emailTimeKey) }
        let minutes = ReminderSettings.minutes
        let previews = ReminderSettings.showsPreviews
        let weekdays = Set(ReminderSettings.days)
        // Without a past entry it's the plain nudge.
        let memories = ReminderSettings.includesPastEntries
            ? Dictionary((plan?.days ?? []).map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first }) : [:]
        let wroteToday = model.today?.entry != nil

        // Built first, photos and all, then swapped in, so nothing's missing in between.
        var requests: [UNNotificationRequest] = []
        for offset in 0..<days where !(offset == 0 && wroteToday) {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()),
                  weekdays.contains(EmailSchedule.allDays[Calendar.current.component(.weekday, from: day) - 1]) else { continue }
            let iso = Self.isoDay(day)
            let content = UNMutableNotificationContent()
            content.title = "How was your day?"
            content.sound = .default
            content.userInfo = ["destination": "today"]
            if let memory = memories[iso] {
                content.categoryIdentifier = Self.memoryCategory
                content.userInfo["entryID"] = memory.entry.id
                let label = Self.label(for: memory, on: iso)
                if previews {
                    // The memory is the notification: its label for a title, no "How was your day?".
                    content.title = label
                    content.body = memory.entry.excerpt.isEmpty ? "📷 Photo" : Self.clipped(memory.entry.excerpt)
                    if let attachment = await photo(for: memory, on: iso) { content.attachments = [attachment] }
                    guard isCurrent() else { return } // signed out while the photo came down
                } else {
                    content.body = "\(Self.teaser(for: memory, on: iso)) Take a look back, then write today's."
                }
            } else {
                content.body = "Take a minute to write it down in Dabble Me."
            }
            if let request = request(content, id: "daily.\(iso)", on: day, minutes: minutes) { requests.append(request) }
        }
        #if DEBUG
        // UI tests: -DabbleDebugReminderSoon YES brings the first one up twelve seconds on (once:
        // later passes leave it be, or each would put it off again).
        if UserDefaults.standard.bool(forKey: "DabbleDebugReminderSoon"), let first = requests.first {
            if debugSoonID == nil {
                debugSoonID = first.identifier
                requests[0] = UNNotificationRequest(identifier: first.identifier, content: first.content,
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 12, repeats: false))
            } else if first.identifier == debugSoonID {
                requests.removeFirst()
            }
        }
        #endif
        // Adding one with the same identifier replaces it. Only the ones no longer wanted are
        // removed: removing everything and adding again at once can take the new ones too (the
        // removal is carried out a moment later).
        var wanted = Set(requests.map(\.identifier))
        #if DEBUG
        if let debugSoonID { wanted.insert(debugSoonID) }
        #endif
        guard isCurrent() else { return }
        await removePending(except: wanted)
        for request in requests {
            guard isCurrent() else { break }
            try? await center.add(request)
        }
        // Signed out in the middle of adding them: none of this account's stay.
        if !isCurrent() { await removePending() }
    }

    private func removePending(except kept: Set<String> = []) async {
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) && !kept.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
    }

    /// The coming days' memories, fetched again when the journal has changed or half an hour on.
    private func plan(for model: AppModel, session: Int) async -> ReminderPlan? {
        // The reminder's own choice of past entries (PRO; without them the server uses the email's).
        var query = ["days": String(days)]
        if model.me?.isPro == true {
            query["filter"] = ReminderSettings.pastFilter
            query["include_old"] = ReminderSettings.includesOldEntries ? "1" : "0"
        }
        let key = "\(model.today?.date ?? "")|\(model.me?.entryCount ?? 0)|\(model.today?.entry?.updatedAt ?? "")|\(query["filter"] ?? "-")|\(query["include_old"] ?? "-")"
        if let cached, cached.key == key, Date().timeIntervalSince(cached.at) < 30 * 60 { return cached.plan }
        guard let plan: ReminderPlan = try? await model.api.get("api/v1/reminders", query: query) else {
            return cached?.plan // an older server, or offline: what was known (or just the nudge)
        }
        // Not kept if the account signed out while it was on its way (the caller drops it too).
        guard session == self.session else { return nil }
        cached = (plan, key, Date())
        filteredCount = plan.filteredCount
        return plan
    }

    /// "On This Day · 3 years ago", "Rewind · 2 months and 1 week ago": as of the day it shows.
    static func label(for memory: ReminderPlan.Day, on iso: String) -> String {
        let ago = JournalDay(memory.entry.date).flatMap { entry in JournalDay(iso).map { entry.relative(to: $0) } } ?? ""
        let name = memory.isOnThisDay ? "On This Day" : "Rewind"
        return ago.isEmpty ? name : "\(name) · \(ago)"
    }

    /// Without previews: that there's something to look back on, and from when (no entry text).
    static func teaser(for memory: ReminderPlan.Day, on iso: String) -> String {
        let entryDay = JournalDay(memory.entry.date)
        if memory.isOnThisDay {
            let year = entryDay?.year ?? ""
            return memory.count == 1 ? "You wrote on this day in \(year)." : "You have \(memory.count) memories from this day."
        }
        let ago = entryDay.flatMap { entry in JournalDay(iso).map { entry.relative(to: $0) } } ?? "the past"
        return "You have a memory from \(ago.prefix(1).lowercased() + ago.dropFirst())."
    }

    private static func clipped(_ text: String, limit: Int = 220) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        return String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)]) + "…"
    }

    /// The memory's photo, a small copy for the notification (which takes the file for itself).
    private func photo(for memory: ReminderPlan.Day, on iso: String) async -> UNNotificationAttachment? {
        guard let url = EntrySummary.thumbnailURL(memory.entry.imageUrl, width: 700),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
        let file = FileManager.default.temporaryDirectory.appending(path: "reminder-\(iso)-\(memory.entry.id).jpg")
        guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "photo", url: file, options: nil)
    }

    private func request(_ content: UNMutableNotificationContent, id: String, on day: Date, minutes: Int) -> UNNotificationRequest? {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        guard let fireDate = Calendar.current.date(from: parts), fireDate > Date() else { return nil }
        return UNNotificationRequest(identifier: prefix + id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    private static func isoDay(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Routes notification taps into the app: a tap opens Today; its actions read the memory or write.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()
    @MainActor weak var model: AppModel?

    // Completion-handler versions, not `async`: Swift runs an async delegate method off the main
    // thread and calls the system's completion handler from there, which crashed on tapping a
    // notification. These hop to the main queue and finish there.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        // A tap opens Today. Touch and hold for the rest: "Read the Memory" opens that entry, and
        // "Write Today's Entry" the composer.
        let reading = response.actionIdentifier == ReminderScheduler.readAction ? info["entryID"] as? Int : nil
        let writing = response.actionIdentifier == ReminderScheduler.writeAction
        nonisolated(unsafe) let done = completionHandler
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let model = self.model {
                    if let reading {
                        model.selectedTab = .journal
                        model.openEntryRequest = reading
                    } else {
                        model.selectedTab = .today
                        if writing { model.composeRequest = true }
                    }
                }
            }
            done()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        nonisolated(unsafe) let done = completionHandler
        DispatchQueue.main.async { done([.banner, .sound]) }
    }
}
