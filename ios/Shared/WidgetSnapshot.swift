import Foundation

/// What the home-screen widget has to show, written by the app into the shared App Group:
/// whether today is written, a writing prompt, and the start of today's entry and of one to look
/// back on. Which of those a widget puts on the Home Screen is the person's choice (in
/// Settings → Home Screen Widget, or on the widget itself): entry text only with previews on.
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
    /// Today's own entry once it's written, and the entry to look back on (On This Day's first,
    /// or else the day's Rewind), for a widget with previews on.
    var todayEntry: Shown? = nil
    var rewindEntry: Shown? = nil

    /// An entry as a widget shows it: a label ("1 year ago · 2025", "31 days ago", "Today's
    /// entry"), the start of its text, its id (a tap on it opens it) and its photo, a small copy
    /// saved in the App Group (`photoURL(named:)`).
    struct Shown: Codable, Equatable, Sendable {
        var title: String
        var text: String
        var id: Int
        var photo: String? = nil
    }
    /// Rewind for `day` and the days after it, so the widget has something to look back on each
    /// morning without the app being opened first. They're the reminders' own picks, so the
    /// filters in Settings → Reminders → Past Entries hold (the words left out, over a year old).
    var upcoming: [Day]? = nil
    /// The days written lately (YYYY-MM-DD, the past few weeks'), for the row of the last five
    /// days under the date. Optional: snapshots saved by older builds don't have it.
    var writtenDays: [String]? = nil
    /// The last day `upcoming` was worked out for (YYYY-MM-DD): up to it, `upcoming`, not the
    /// fields above, says what a Rewind widget shows, a day with nothing in it included. Past
    /// it (the app not opened for a couple of weeks) nothing's known. Not set by older builds,
    /// or before the first answer.
    var plannedThrough: String? = nil

    /// One later day's look back: the same things the snapshot holds for its own day.
    struct Day: Codable, Equatable, Sendable {
        var day: String
        /// Entries on this date in earlier years (nil when the look back is another past entry).
        var memories: Int? = nil
        var memoryNote: String? = nil
        var entryTitle: String? = nil
        var entryText: String? = nil
        var entryID: Int? = nil
        var entryPhoto: String? = nil
    }

    /// The entry a widget with `content` shows on the snapshot's own day: none without previews.
    func shown(for content: WidgetContent) -> Shown? {
        switch content {
        case .prompt, .memoryCount: nil
        case .promptEntry: todayEntry
        case .memoryEntry: rewindEntry
        }
    }

    /// What a Rewind widget looks back on, on `date`. `known` for a day the plan reaches (then
    /// `day` is that day's look back, or nil when there's nothing to look back on), and for a
    /// later day that has one; otherwise the snapshot's own fields say (its own day, before
    /// the plan's come or past where it reached).
    func rewind(on date: Date, calendar: Calendar = .current) -> (known: Bool, day: Day?) {
        let iso = Self.iso(date, calendar: calendar)
        let planned = upcoming?.first { $0.day == iso }
        let reached = plannedThrough.map { iso >= day && iso <= $0 } ?? false
        return (reached || (iso != day && planned != nil), planned)
    }

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

    /// Whether each of the five days up to `date` was written, oldest first (the last is
    /// `date` itself); nil when the snapshot doesn't say (an older build's).
    func lastFiveDays(on date: Date, calendar: Calendar = .current) -> [Bool]? {
        guard let writtenDays else { return nil }
        let written = Set(writtenDays)
        let today = Self.iso(date, calendar: calendar)
        return (0..<5).reversed().map { back in
            let iso = calendar.date(byAdding: .day, value: -back, to: date).map { Self.iso($0, calendar: calendar) } ?? ""
            // Today's by the snapshot's own word when it's the snapshot's day.
            return iso == today && iso == day ? wroteToday : written.contains(iso)
        }
    }

    static func iso(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Links the widget opens (the app's registered URL scheme, shared with OAuth sign-in).
    static let todayURL = URL(string: "me.dabble.app:/today")!
    /// Today, scrolled to the look back (On This Day, or the Rewind).
    static let todayLookBackURL = URL(string: "me.dabble.app:/today/lookback")!
    /// Today, scrolled to that entry among its look backs.
    static func todayEntryURL(_ id: Int) -> URL { URL(string: "me.dabble.app:/today/entry/\(id)")! }
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
            case .prompt: "A Prompt for You"
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
