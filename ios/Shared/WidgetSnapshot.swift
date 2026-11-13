import Foundation

/// What the home-screen widget shows, written by the app into the shared App Group.
/// Whether today is written, a writing prompt and, only if the person turns previews on in
/// Settings → Home Screen Widget, the start of an entry.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let appGroup = "group.me.dabble.ios"
    static let storageKey = "widget.snapshot"
    /// What the medium widget shows next to today's date (Settings → Home Screen Widget).
    static let contentKey = "widget.content"
    /// The older on/off setting ("Show Entries in Widget"), read once for people who turned it on.
    static let showMemoriesKey = "widget.showMemories"

    /// The journal day this snapshot describes (YYYY-MM-DD).
    var day: String
    var wroteToday: Bool
    /// Entries written in `day`'s year so far, for the Lock Screen's circular widget.
    /// Optional: snapshots saved by older builds don't have it.
    var yearCount: Int?
    var memories: Int
    var memoriesFirstYear: Int?
    /// With nothing on this day in past years: that there's another past entry to look back on
    /// ("You have a memory from 36 days ago."), for Rewind without previews.
    var memoryNote: String? = nil
    var prompt: String?
    /// With previews on: an entry (a look back, or today's own), e.g. "1 year ago · 2025",
    /// "31 days ago" or "Today's entry", and the start of its text.
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
    /// Today's entry, open for editing (the widget's "Edit today's entry", once today's written).
    static let editTodayURL = URL(string: "me.dabble.app:/today/edit")!
    static func entryURL(_ id: Int) -> URL { URL(string: "me.dabble.app:/entry/\(id)")! }
}

/// What the medium widget shows beside today's date: today's prompt or a look back (Rewind),
/// each with or without entry previews. Only the two preview cases put entry text or photos on
/// the home screen. The person's choice alone decides it; the Face ID lock doesn't change it.
enum WidgetContent: String, CaseIterable, Identifiable, Sendable {
    /// Today's writing prompt: nothing from the journal.
    case prompt
    /// Today's prompt until today's written, then the start of today's entry.
    case promptEntry
    /// How many entries you wrote on this day in past years, or that there's a past entry (no text).
    case memoryCount
    /// The start of one of them (or of another past entry when there are none).
    case memoryEntry

    /// The two things to choose between; previews are a separate switch.
    enum Source: String, CaseIterable, Identifiable, Sendable {
        case prompt, rewind

        var id: Self { self }

        var title: String {
            switch self {
            case .prompt: "Today's Prompt"
            case .rewind: "Rewind"
            }
        }
    }

    init(source: Source, showsPreviews: Bool) {
        switch source {
        case .prompt: self = showsPreviews ? .promptEntry : .prompt
        case .rewind: self = showsPreviews ? .memoryEntry : .memoryCount
        }
    }

    var id: Self { self }

    var source: Source {
        switch self {
        case .prompt, .promptEntry: .prompt
        case .memoryCount, .memoryEntry: .rewind
        }
    }

    /// Entry text and photos can show on the widget.
    var showsPreviews: Bool { self == .promptEntry || self == .memoryEntry }

    var summary: String {
        switch self {
        case .prompt: "A writing prompt for today."
        case .promptEntry: "A writing prompt for today, then your entry once you've written it."
        case .memoryCount: "How many entries you wrote on this day in past years or a past entry, without the text."
        case .memoryEntry: "The start of an entry from this day in past years, or another past entry, with its photo."
        }
    }
}
