import Foundation

// Shapes mirror Api::EntrySerializer and Api::V1::MeController. Keys are snake_case on the wire.

struct Me: Decodable, Sendable, Equatable {
    let id: Int
    let email: String
    let firstName: String?
    /// First and last name, as set on dabble.me (nil from an older server, or when not set).
    var name: String? = nil
    let plan: String
    let isPro: Bool
    let timezone: String?
    /// The journal's time zone by its IANA name ("America/Denver"; nil from an older server).
    var timezoneIdentifier: String? = nil
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
    /// The UUID to buy PRO in the app with (StoreKit's appAccountToken): Apple puts it in the
    /// signed transaction, which is how the server knows which account bought it. Nil from an
    /// older server, and then the app sells nothing.
    var appleAccountToken: String? = nil
    /// False once Dabble Me's closing is announced: nothing new is sold (purchases already made
    /// are still reported). Missing from older servers.
    var canBuyInApp: Bool? = nil
    /// The app may offer the in-app purchase.
    var sellsInApp: Bool { appleAccountToken != nil && canBuyInApp != false }
    /// Where PRO comes from: "apple" (an App Store subscription), "web" (dabble.me), or nil.
    var proSource: String? = nil
    /// The App Store subscription that makes the account PRO, if one does.
    var appleSubscription: AppleSubscriptionInfo? = nil

    var isProThroughApple: Bool { isPro && proSource == "apple" }
    var isProThroughWeb: Bool { isPro && proSource != "apple" }

    struct AppleSubscriptionInfo: Decodable, Sendable, Equatable {
        let productId: String
        let expiresAt: String?
        let willRenew: Bool?
        let inGracePeriod: Bool?
        let sandbox: Bool?
    }

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
    /// The whole entry's word count (nil from an older server).
    var wordCount: Int? = nil

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
    /// Entries written this calendar year (nil from a server that doesn't send it yet).
    var entriesThisYear: Int? = nil
    /// A past entry when On This Day is empty, like the daily email's ("Throwback").
    var throwback: EntrySummary? = nil

    var day: JournalDay? { JournalDay(date) }
}

struct Song: Decodable, Sendable, Hashable {
    let title: String?
    let artists: [String]
    let spotifyUrl: URL

    /// The track's Spotify id (the last part of its link), for playing it in the app.
    var trackID: String? {
        let id = spotifyUrl.lastPathComponent
        return !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } ? id : nil
    }

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
    /// Editable structured body (nil only from an older server, for an entry with formatting it
    /// kept for the web editor).
    let document: [DocumentBlock]?
    /// The document leaves out formatting it can't hold (styles, quotes, images…): saving an edit
    /// rewrites the entry without it.
    var documentSimplified: Bool? = nil
    let songs: [Song]
    /// Hashtags in this entry that have a date on dabble.me (a birthday, an anniversary), with
    /// how long it had been on this entry's day. Optional for older servers.
    var datedHashtags: [DatedHashtag]? = nil
    let webUrl: URL
    let previousEntry: EntryNeighbour?
    let nextEntry: EntryNeighbour?

    var day: JournalDay? { JournalDay(date) }
    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }
    /// The entry's edit page on the web (`/entries/499512/edit`), for one the app can't edit.
    var webEditURL: URL { URL(string: "/entries/\(id)/edit", relativeTo: webUrl)?.absoluteURL ?? webUrl }

    var summary: EntrySummary {
        // The whole text as the preview, so nothing's left to load; songs and dated tags carry over.
        EntrySummary(id: id, date: date, excerpt: excerpt, imageUrl: imageUrl,
                     imageProcessing: imageProcessing, hashtags: hashtags, updatedAt: updatedAt, previewText: bodyText,
                     datedHashtags: datedHashtags, songs: songs, previewTruncated: false)
    }
}

/// GET /api/v1/entries/:id/same_day: the entry's calendar day in other years, newest first.
/// A free account gets only how many there are (`available` false, no entries).
struct SameDayEntries: Decodable, Sendable {
    let available: Bool
    let count: Int
    let entries: [EntrySummary]
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

/// GET /api/v1/account_deletion: what Delete Account's confirmation says.
struct AccountDeletionInfo: Decodable, Sendable, Equatable {
    struct SeparateBilling: Decodable, Sendable, Equatable {
        /// Gumroad, PayPal, Stripe, or Apple (an App Store subscription, cancelled in iOS Settings).
        let provider: String
        /// False for Stripe with no customer on file: there may be nothing left to cancel.
        let certain: Bool
    }

    let entryCount: Int
    /// PRO billing that deleting the account doesn't stop; nil when there's none to cancel.
    let separateBilling: SeparateBilling?
}

/// A POST with nothing to send (encodes as `{}`).
struct EmptyBody: Encodable, Sendable {}

/// POST /api/v1/exports: the export is on its way to `email`.
struct ExportRequestResult: Decodable, Sendable {
    /// "started" or "preparing" (emailed when it's ready), or "sent" (a recent one, emailed again).
    let status: String
    let email: String

    var title: String { status == "sent" ? "Export Sent" : "Export Started" }

    /// Asked for on the Delete Account page: the export goes with the account.
    func message(beforeDeleting: Bool) -> String {
        guard beforeDeleting else { return message }
        return message + "\n\nDownload it before you delete your account: deleting it deletes the export too."
    }

    var message: String {
        switch status {
        case "sent": "We've emailed your latest export to \(email) again. The link works for 7 days."
        case "preparing": "Your export is already being prepared. We'll email it to \(email) when it's ready."
        default: "We'll email your export to \(email) when it's ready. The link works for 7 days."
        }
    }
}

/// POST /api/v1/account_deletion.
struct AccountDeletionResult: Decodable, Sendable {
    let deletesAt: String
}

struct AccountDeletionRequest: Encodable, Sendable {
    let password: String
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
    /// Another day for the entry (YYYY-MM-DD), when it's being moved.
    var date: String? = nil
    /// Moving onto a day that has an entry: add this one to it (asked first).
    var merge: Bool? = nil
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

    /// Between a span's two units, wherever the app says how long ago: "2 years, 3 months ago".
    static let unitJoiner = ", "

    /// How long ago this day was, said one way wherever the app says it (an open entry's title, a
    /// photo's band, Today's Rewind, the widget, a reminder): "Today", "Yesterday", whole days up
    /// to 60 ("36 days ago"), then years and months by the calendar, without days ("2 months
    /// ago", "5 years, 2 months ago", "3 years ago"), to the nearest month. (The daily email
    /// words its own, on the server.)
    func ago(from today: JournalDay) -> String {
        let days = Self.utc.dateComponents([.day], from: date, to: today.date).day ?? 0
        guard days >= 0 else { return "In the future" }
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        case ...60: return "\(days) days ago"
        default: break
        }
        let span = Self.utc.dateComponents([.year, .month, .day], from: date, to: today.date)
        // Over half a month more counts as the next month.
        let months = (span.year ?? 0) * 12 + (span.month ?? 0) + ((span.day ?? 0) > 15 ? 1 : 0)
        let parts = [(months / 12, "year"), (months % 12, "month")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        return parts.joined(separator: Self.unitJoiner) + " ago"
    }

    /// What an empty new entry asks about this day: "How has today been?", "How was yesterday?",
    /// or the day by name ("How was Tuesday, November 3?", with its year when it isn't this one).
    func writingQuestion(today: JournalDay) -> String {
        switch ago(from: today) {
        case "Today": return "How has today been?"
        case "Yesterday": return "How was yesterday?"
        default:
            let named = year == today.year ? formatted(.dateTime.weekday(.wide).month(.wide).day())
                                           : formatted(.dateTime.weekday(.wide).month(.wide).day().year())
            return "How was \(named)?"
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
    /// The year the longest streak ended in (nil from an older server, or with no entries).
    var longestStreakYear: Int? = nil
    let entriesThisYear: Int
    /// Each year's entries, newest first (nil from an older server).
    var entriesByYear: [YearCount]? = nil

    struct YearCount: Decodable, Sendable, Equatable {
        let year: Int
        let count: Int
    }

    /// YYYY-MM-DD days with an entry in the past year, oldest first.
    let writingDays: [String]
    /// The last 12 months, oldest first (zero counts included).
    let months: [MonthCount]
    let busiestWeekday: String?
    let topHashtags: [HashtagCount]

    var firstEntryDay: JournalDay? { firstEntryDate.flatMap(JournalDay.init) }
}

/// GET /api/v1/stats/days?year=: one calendar year, for Stats' year picker.
struct YearDays: Decodable, Sendable {
    let year: Int
    /// YYYY-MM-DD days with an entry, oldest first.
    let days: [String]
    /// The year's hashtags, most used first (nil from an older server).
    var topHashtags: [HashtagCount]? = nil
    /// The days with a photo and its address (nil from an older server).
    var photos: [String: String]? = nil
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
    /// None: the email is off.
    var days: [String]
    /// The days it had when it was last turned off (nil from an older server).
    var previousDays: [String]? = nil
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

/// GET /api/v1/plan (Settings → Plan): when a PRO plan bought on dabble.me renews or ends.
/// Only Stripe plans have a date; nil for anything else, or when Stripe couldn't be asked.
struct PlanDetails: Decodable, Sendable, Equatable {
    var webSubscription: WebSubscriptionInfo? = nil

    struct WebSubscriptionInfo: Decodable, Sendable, Equatable {
        let provider: String?
        let expiresAt: String?
        let willRenew: Bool?
    }
}
