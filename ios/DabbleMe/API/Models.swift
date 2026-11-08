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
    let canSearch: Bool
    let settingsUrl: URL
    let securityUrl: URL
    let aiConnectors: AIConnectors?

    struct AIConnectors: Decodable, Sendable, Equatable {
        let claudeUrl: URL
        let chatgptUrl: URL
        let guideUrl: URL
        /// What the account still needs before Claude/ChatGPT can connect.
        let requiresPro: Bool
        let requiresSecuritySetup: Bool
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

    var day: JournalDay? { JournalDay(date) }
    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }
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
    let webUrl: URL

    var day: JournalDay? { JournalDay(date) }
    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }

    var summary: EntrySummary {
        EntrySummary(id: id, date: date, excerpt: excerpt, imageUrl: imageUrl,
                     imageProcessing: imageProcessing, hashtags: hashtags, updatedAt: updatedAt)
    }
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

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
