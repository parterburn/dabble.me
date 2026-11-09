import Foundation

// Shapes mirror Api::EntrySerializer and Api::V1::MeController. Keys are snake_case on the wire.

struct Me: Decodable, Sendable, Equatable {
    let id: Int
    let email: String
    let firstName: String?
    let plan: String
    let isPro: Bool
    let timezone: String?
    /// Today's date in the user's journal time zone (YYYY-MM-DD).
    let today: String
    let entryCount: Int
    let canWrite: Bool
    /// PRO: photos, editing/deleting entries, search.
    let canAddPhotos: Bool
    let canEdit: Bool
    let canSearch: Bool
    /// Newer flags (absent from an older server, so they fall back to the plan).
    let canDelete: Bool?
    let canAddLinks: Bool?
    let canSeeStats: Bool?
    let settingsUrl: URL
    let securityUrl: URL
    let aiConnectors: AIConnectors?

    /// Free accounts can write and delete; editing, photos, links, search and Stats are PRO.
    var mayDelete: Bool { canDelete ?? canEdit }
    var mayAddLinks: Bool { canAddLinks ?? isPro }
    var maySeeStats: Bool { canSeeStats ?? isPro }

    struct AIConnectors: Decodable, Sendable, Equatable {
        let claudeUrl: URL
        let chatgptUrl: URL
        let guideUrl: URL
        /// The account needs PRO before Claude/ChatGPT can connect.
        let requiresPro: Bool
    }
}

struct EntrySummary: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let date: String
    let excerpt: String
    let imageUrl: String?
    let imageProcessing: Bool
    let hashtags: [String]
    let updatedAt: String
    /// The entry's text (light Markdown, capped) for long-press previews. Optional for older servers.
    var previewText: String? = nil
    /// Only on Today's "On This Day" memories.
    var yearsAgo: Int? = nil
    /// Its #tags with a date (birthdays, anniversaries), and how long it had been.
    var datedHashtags: [DatedHashtag]? = nil
    /// Spotify songs found in it.
    var songs: [Song]? = nil
    /// `previewText` was cut short (the rest loads when the row is expanded).
    var previewTruncated: Bool? = nil

    var day: JournalDay? { JournalDay(date) }
    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }
}

struct EntryNeighbour: Decodable, Sendable, Hashable {
    let id: Int
    let date: String

    var day: JournalDay? { JournalDay(date) }
}

/// A month that has entries, for the Journal tab's sections and scrubber.
struct MonthCount: Decodable, Sendable, Hashable, Identifiable {
    let year: Int
    let month: Int
    var count: Int

    var id: String { key }
    /// "2026-11", the same as `JournalDay.monthKey`.
    var key: String { String(format: "%04d-%02d", year, month) }
    var title: String { JournalDay(key + "-01")?.monthTitle ?? key }
    var shortTitle: String { JournalDay(key + "-01")?.formatted(.dateTime.month(.abbreviated).year()) ?? key }

    init(year: Int, month: Int, count: Int) {
        self.year = year
        self.month = month
        self.count = count
    }

    init?(key: String, count: Int) {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(year: parts[0], month: parts[1], count: count)
    }
}

struct MonthList: Decodable, Sendable {
    let months: [MonthCount]
}

struct TodaySummary: Decodable, Sendable {
    let date: String
    let entry: EntryDetail?
    let onThisDay: [EntrySummary]
    let onThisDayAvailable: Bool
    let prompt: String?
    /// Days in a row with an entry, up to today (or yesterday while today is unwritten).
    var currentStreak: Int? = nil
    /// A past entry when On This Day is empty, like the daily email's ("Throwback").
    var throwback: EntrySummary? = nil

    var day: JournalDay? { JournalDay(date) }
}

struct Song: Decodable, Sendable, Hashable {
    let title: String?
    let artists: [String]
    let spotifyUrl: URL

    var label: String {
        [artists.joined(separator: ", "), title].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " – ")
    }
}


struct EntryDetail: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let date: String
    let excerpt: String
    let imageUrl: String?
    let imageProcessing: Bool
    let hashtags: [String]
    let updatedAt: String
    let bodyText: String
    /// Editable structured body, or nil when the entry has formatting only the web editor keeps.
    let document: [DocumentBlock]?
    let songs: [Song]
    /// Hashtags in this entry that have a date on dabble.me (a birthday, an anniversary), with
    /// how long it had been on this entry's day. Optional for older servers.
    var datedHashtags: [DatedHashtag]? = nil
    let webUrl: URL
    let previousEntry: EntryNeighbour?
    let nextEntry: EntryNeighbour?

    var day: JournalDay? { JournalDay(date) }
    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }

    var summary: EntrySummary {
        // The whole text as the preview, so nothing's left to load; songs and dated tags carry over.
        EntrySummary(id: id, date: date, excerpt: excerpt, imageUrl: imageUrl,
                     imageProcessing: imageProcessing, hashtags: hashtags, updatedAt: updatedAt, previewText: bodyText,
                     datedHashtags: datedHashtags, songs: songs, previewTruncated: false)
    }
}

struct DatedHashtag: Decodable, Sendable, Hashable, Identifiable {
    let tag: String
    let date: String
    /// e.g. "1 year and 4 months since entry".
    let age: String

    var id: String { tag.lowercased() }
    var day: JournalDay? { JournalDay(date) }
}

struct EntryPage: Decodable, Sendable {
    let entries: [EntrySummary]
    let page: Int
    let nextPage: Int?
    let totalCount: Int
}

struct EntryEnvelope: Decodable, Sendable {
    let entry: EntryDetail
    let merged: Bool?
}

struct EntryList: Decodable, Sendable {
    let entries: [EntrySummary]
}

struct ImageUploadBatch: Decodable, Sendable {
    let uploads: [ImageUpload]
}

struct ImageUpload: Decodable, Sendable {
    let uploadMethod: String
    let uploadUrl: URL
    let uploadHeaders: [String: String]
    let uploadedImageKey: String
    let maxBytes: Int
}

struct AccountDeletionRequest: Decodable, Sendable {
    let email: String
}

struct APIErrorBody: Decodable, Sendable {
    let error: String
    let message: String?
    let details: [String]?
}

// MARK: - Requests

struct NewEntryRequest: Encodable, Sendable {
    let date: String
    let document: [DocumentBlock]
    /// One photo is stored as-is; several (or adding to a day that has a photo) become a collage.
    let uploadedImageKeys: [String]
}

struct UpdateEntryRequest: Encodable, Sendable {
    let document: [DocumentBlock]
    /// New photos: they join the entry's photo in a collage, or replace it with `removeImage`.
    var uploadedImageKeys: [String]? = nil
    var removeImage: Bool? = nil
}

struct ImageUploadRequest: Encodable, Sendable {
    let photos: [Photo]

    struct Photo: Encodable, Sendable {
        let filename: String
        let contentType: String
    }
}

/// A calendar day as the server sends it (YYYY-MM-DD). Kept in UTC so formatting never
/// shifts an entry to the previous or next day.
struct JournalDay: Hashable, Sendable, Comparable {
    let date: Date
    let iso: String

    init?(_ iso: String) {
        guard let date = try? Date(iso, strategy: Date.ISO8601FormatStyle().year().month().day()) else { return nil }
        self.date = date
        self.iso = iso
    }

    /// Builds the server's YYYY-MM-DD from a date picked in the device's calendar.
    init(localDate: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: localDate)
        let iso = String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
        self.init(iso)!
    }

    /// The same calendar day as a date in the device's time zone (for DatePicker).
    var localDate: Date {
        let parts = Self.utc.dateComponents([.year, .month, .day], from: date)
        return Calendar.current.date(from: parts) ?? date
    }

    var monthKey: String { String(iso.prefix(7)) }

    func formatted(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = .gmt
        return date.formatted(style)
    }

    var long: String { formatted(.dateTime.weekday(.wide).month(.wide).day().year()) }
    var monthTitle: String { formatted(.dateTime.month(.wide).year()) }
    var dayNumber: String { formatted(.dateTime.day()) }
    var weekdayShort: String { formatted(.dateTime.weekday(.abbreviated)) }
    var year: String { formatted(.dateTime.year()) }

    static func < (lhs: JournalDay, rhs: JournalDay) -> Bool { lhs.iso < rhs.iso }

    /// "Today", "Yesterday", "345 days ago", "1 year, 35 days ago", "3 years ago".
    func relative(to today: JournalDay) -> String {
        let parts = Self.utc.dateComponents([.year, .day], from: date, to: today.date)
        let years = parts.year ?? 0, days = parts.day ?? 0
        guard date <= today.date else { return "In the future" }
        if years == 0 {
            switch days {
            case 0: return "Today"
            case 1: return "Yesterday"
            default: return "\(days.formatted()) days ago"
            }
        }
        let yearText = years == 1 ? "1 year" : "\(years) years"
        if days == 0 { return "\(yearText) ago" }
        return "\(yearText), \(days == 1 ? "1 day" : "\(days) days") ago"
    }

    /// For a shared photo's band, rounded down to the largest unit: "Today", "Yesterday",
    /// "12 days ago", "5 months ago", "3 years ago".
    func shareLabel(to today: JournalDay) -> String {
        let parts = Self.utc.dateComponents([.year, .month, .day], from: date, to: today.date)
        let years = parts.year ?? 0, months = parts.month ?? 0, days = parts.day ?? 0
        guard date <= today.date else { return relative(to: today) }
        if years > 0 { return years == 1 ? "1 year ago" : "\(years) years ago" }
        if months > 0 { return months == 1 ? "1 month ago" : "\(months) months ago" }
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}

/// GET /api/v1/stats (Api::JournalStats): the Journal tab's Stats view.
struct JournalStats: Decodable, Sendable, Equatable {
    let totalEntries: Int
    let totalWords: Int
    let photoEntries: Int
    let firstEntryDate: String?
    let currentStreak: Int
    let longestStreak: Int
    let entriesThisYear: Int
    /// YYYY-MM-DD days with an entry in the past year, oldest first.
    let writingDays: [String]
    /// The last 12 months, oldest first (zero counts included).
    let months: [MonthCount]
    let busiestWeekday: String?
    let topHashtags: [HashtagCount]

    var firstEntryDay: JournalDay? { firstEntryDate.flatMap(JournalDay.init) }
}

struct HashtagCount: Decodable, Sendable, Hashable, Identifiable {
    let tag: String
    let count: Int

    var id: String { tag.lowercased() }
}

struct HashtagList: Decodable, Sendable {
    let hashtags: [HashtagCount]
}

/// GET/PATCH /api/v1/email_schedule: when the "How was your day?" email arrives.
struct EmailSchedule: Decodable, Sendable, Equatable {
    var days: [String]
    var hour: Int
    var timezone: String
    /// PRO: any days. Free: Sunday or nothing.
    let canChooseDays: Bool
    let timeZones: [TimeZoneOption]
    /// The past entry at the bottom of each email, like the web settings: on or off for everyone;
    /// words that keep entries out (comma-separated) and entries over a year old are PRO.
    var includePastEntries: Bool
    var pastFilter: String
    let filteredCount: Int
    var includeOldEntries: Bool
    let hasOldEntries: Bool

    static let allDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    struct TimeZoneOption: Decodable, Sendable, Hashable, Identifiable {
        let name: String
        let iana: String
        let offset: String

        var id: String { name }
    }
}

struct EmailScheduleUpdate: Encodable, Sendable {
    var days: [String]? = nil
    var hour: Int? = nil
    var timezone: String? = nil
    var includePastEntries: Bool? = nil
    var pastFilter: String? = nil
    var includeOldEntries: Bool? = nil
}

/// A date for a #tag (a birthday, an anniversary), so entries show how long it had been (PRO).
struct TagDate: Codable, Sendable, Hashable, Identifiable {
    let id: Int
    var tag: String
    var date: String

    var day: JournalDay? { JournalDay(date) }
}

struct TagDateList: Decodable, Sendable {
    var hashtags: [TagDate]
    /// Tags used lately that don't have a date yet.
    let suggestions: [String]
}

struct TagDateUpdate: Encodable, Sendable {
    var tag: String? = nil
    var date: String? = nil
}
