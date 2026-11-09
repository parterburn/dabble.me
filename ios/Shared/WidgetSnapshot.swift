import Foundation

/// What the home-screen widget shows, written by the app into the shared App Group.
/// Counts and a writing prompt only, never entry text: widgets are visible without unlocking.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let appGroup = "group.me.dabble.ios"
    static let storageKey = "widget.snapshot"
    /// Off by default: entries (On This Day, or a throwback) appear on the widget only if the user
    /// turns on "Show Entries in Widget".
    static let showMemoriesKey = "widget.showMemories"

    /// The journal day this snapshot describes (YYYY-MM-DD).
    var day: String
    var wroteToday: Bool
    var streak: Int
    var memories: Int
    var memoriesFirstYear: Int?
    var prompt: String?
    /// With "Show Entries in Widget" on (and no Face ID lock): an entry to look back on, e.g.
    /// "1 year ago · 2025" or "Throwback · 31 days ago", and the start of its text.
    var entryTitle: String? = nil
    var entryText: String? = nil

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults?.set(data, forKey: Self.storageKey)
    }

    static func clear() {
        defaults?.removeObject(forKey: storageKey)
    }

    static var showsMemories: Bool {
        defaults?.bool(forKey: showMemoriesKey) ?? false
    }

    /// The snapshot as of `date` (local calendar): a new day hasn't been written yet, and a
    /// streak survives until the end of the day after the last entry.
    func state(on date: Date, calendar: Calendar = .current) -> (wroteToday: Bool, streak: Int, memories: Int?) {
        let today = Self.iso(date, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date).map { Self.iso($0, calendar: calendar) }
        if day == today {
            return (wroteToday, streak, memories > 0 ? memories : nil)
        } else if day == yesterday {
            return (false, wroteToday ? streak : 0, nil)
        }
        return (false, 0, nil)
    }

    static func iso(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Links the widget opens (the app's registered URL scheme, shared with OAuth sign-in).
    static let writeURL = URL(string: "me.dabble.app:/write")!
    static let todayURL = URL(string: "me.dabble.app:/today")!
}
