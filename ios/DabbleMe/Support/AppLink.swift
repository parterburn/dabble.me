import Foundation

/// A dabble.me page the app opens itself when its link is tapped (a universal link): the Journal,
/// Today, a new entry, a day's entry, or Rewind (which the app has in Stats). The server lists the same pages for iOS
/// (`MobileApp::LINK_PATHS`, served at /.well-known/apple-app-site-association).
enum AppLink: Equatable {
    case journal, today, newEntry
    /// https://dabble.me/rewind and /rewind/2026: the year in review is a card at the top of Stats.
    case stats
    /// https://dabble.me/entries/2026/11/13
    case day(JournalDay)

    init?(_ url: URL) {
        guard url.scheme == "https", let host = url.host()?.lowercased(), host == "dabble.me" || host == "www.dabble.me" else { return nil }
        let parts = url.path().split(separator: "/").map(String.init)
        switch parts {
        case ["entries"]: self = .journal
        case ["today"]: self = .today
        case ["write"], ["entries", "new"]: self = .newEntry
        case ["rewind"]: self = .stats
        case let rewind where rewind.count == 2 && rewind[0] == "rewind" && Int(rewind[1]) != nil: self = .stats
        default:
            // The web writes days unpadded (2026/4/21); either way here.
            guard parts.count == 4, parts[0] == "entries", let year = Int(parts[1]), let month = Int(parts[2]), let dayOfMonth = Int(parts[3]),
                  let day = JournalDay(String(format: "%04d-%02d-%02d", year, month, dayOfMonth)) else { return nil }
            self = .day(day)
        }
    }
}

extension AppModel {
    /// Goes where a dabble.me link points. A day's link opens its entry; a day without one opens
    /// the composer on it (not a day still to come).
    func open(_ link: AppLink) {
        switch link {
        case .journal:
            selectedTab = .journal
        case .today:
            selectedTab = .today
        case .newEntry:
            // As the web's own page does: in the morning, yesterday's entry if it's unwritten.
            requestNewEntry()
        case .stats:
            selectedTab = .journal
            statsRequest += 1
        case .day(let day):
            selectedTab = .journal
            Task {
                if let entry = try? await entrySummary(on: day) {
                    openEntryRequest = entry.id
                } else if me?.canWrite != false, day.localDate <= .now {
                    composingDay = StatsDay(day: day)
                }
            }
        }
    }
}
