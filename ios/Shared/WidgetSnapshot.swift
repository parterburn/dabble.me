import Foundation

/// What the home-screen widget shows, written by the app into the shared App Group.
/// The year's entry count, a writing prompt and, only if the person chooses it in Settings → Home Screen
/// Widget, an entry to look back on.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let appGroup = "group.me.dabble.ios"
    static let storageKey = "widget.snapshot"
    /// What the medium widget shows next to the year's count (Settings → Home Screen Widget).
    static let contentKey = "widget.content"
    /// The older on/off setting ("Show Entries in Widget"), read once for people who turned it on.
    static let showMemoriesKey = "widget.showMemories"

    /// The journal day this snapshot describes (YYYY-MM-DD).
    var day: String
    var wroteToday: Bool
    /// Entries written in `day`'s year so far. Optional: snapshots saved by older builds don't have it.
    var yearCount: Int?
    var memories: Int
    var memoriesFirstYear: Int?
    var prompt: String?
    /// With "On This Day Entry" chosen: an entry to look back on, e.g.
    /// "1 year ago · 2025" or "Throwback · 31 days ago", and the start of its text.
    var entryTitle: String? = nil
    var entryText: String? = nil
    /// The shown entry, so tapping it on the widget opens it.
    var entryID: Int? = nil
    /// The shown entry's photo, a small copy saved in the App Group (`photoURL(named:)`).
    var entryPhoto: String? = nil

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// The folder of the widget's photo copies, inside the App Group's shared folder (which also
    /// holds the shared settings: clean up in here only).
    static var photoFolder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "WidgetPhotos", directoryHint: .isDirectory)
    }

    static func photoURL(named name: String) -> URL? {
        photoFolder?.appending(path: name)
    }

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

    static var content: WidgetContent {
        get {
            if let raw = defaults?.string(forKey: contentKey), let content = WidgetContent(rawValue: raw) { return content }
            return defaults?.bool(forKey: showMemoriesKey) == true ? .memoryEntry : .prompt
        }
        set {
            defaults?.set(newValue.rawValue, forKey: contentKey)
            defaults?.removeObject(forKey: showMemoriesKey)
        }
    }

    /// The snapshot as of `date` (local calendar): a new day hasn't been written yet, and the
    /// year's count holds until a new year starts it again.
    func state(on date: Date, calendar: Calendar = .current) -> (wroteToday: Bool, yearCount: Int, memories: Int?) {
        let today = Self.iso(date, calendar: calendar)
        let count = day.prefix(4) == today.prefix(4) ? yearCount ?? 0 : 0
        if day == today {
            return (wroteToday, count, memories > 0 ? memories : nil)
        }
        return (false, count, nil)
    }

    static func iso(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Links the widget opens (the app's registered URL scheme, shared with OAuth sign-in).
    static let writeURL = URL(string: "me.dabble.app:/write")!
    static let todayURL = URL(string: "me.dabble.app:/today")!
    static func entryURL(_ id: Int) -> URL { URL(string: "me.dabble.app:/entry/\(id)")! }
}

/// What the medium widget shows beside the year's count. Only `.memoryEntry` puts entry text on the home
/// screen. The person's choice alone decides it; the Face ID lock doesn't change it.
enum WidgetContent: String, CaseIterable, Identifiable, Sendable {
    /// Today's writing prompt: nothing from the journal.
    case prompt
    /// How many entries you wrote on this day in past years (no text).
    case memoryCount
    /// The start of one of them (or a throwback when there are none).
    case memoryEntry

    var id: Self { self }

    var title: String {
        switch self {
        case .prompt: "Today's Prompt"
        case .memoryCount: "On This Day Count"
        case .memoryEntry: "On This Day Entry"
        }
    }

    var summary: String {
        switch self {
        case .prompt: "A writing prompt for today. No entry text."
        case .memoryCount: "How many entries you wrote on this day in past years, without their text."
        case .memoryEntry: "The start of an entry from this day in past years (with its photo), or a throwback when there isn't one."
        }
    }
}
