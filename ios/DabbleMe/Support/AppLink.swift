import Foundation

/// A dabble.me page the app opens itself when its link is tapped (a universal link): the Journal,
/// Today, a new entry, a day's entry, Search, or Rewind (which the app has in Stats). The server lists the same pages for iOS
/// (`MobileApp::LINK_PATHS`, served at /.well-known/apple-app-site-association).
enum AppLink: Equatable {
    case journal, today, newEntry
    /// https://dabble.me/rewind and /rewind/2026: the year in review is a card at the top of Stats.
    case stats
    /// https://dabble.me/entries/2026/11/13
    case day(JournalDay)
    /// https://dabble.me/search, and with what the web's own search links carry
    /// (?search[term]=hiking): the Search tab, with that searched for.
    case search(String?)

    init?(_ url: URL) {
        guard url.scheme == "https", let host = url.host()?.lowercased(), host == "dabble.me" || host == "www.dabble.me" else { return nil }
        let parts = url.path().split(separator: "/").map(String.init)
        switch parts {
        case ["entries"]: self = .journal
        case ["today"]: self = .today
        case ["write"], ["entries", "new"]: self = .newEntry
        case ["search"]:
            // As a form sends it: a space is "+" (and a real plus "%2B"), so the "+" goes to a
            // space before the percent-escapes are read.
            let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems?
                .first { ["search[term]", "term", "q"].contains($0.name.removingPercentEncoding ?? $0.name) }?.value?
                .replacingOccurrences(of: "+", with: " ").removingPercentEncoding?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self = .search(term?.isEmpty == false ? term : nil)
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

/// What Today scrolls to when the medium widget's right side is tapped: the entry it shows, or
/// the look back as a whole (On This Day, or the Rewind) when it shows a count or a note.
enum TodayFocus: Equatable {
    case entry(Int)
    case lookBack

    /// me.dabble.app:/today/entry/<id> and :/today/lookback (`WidgetSnapshot`'s links).
    init?(_ url: URL) {
        let parts = url.path.split(separator: "/").map(String.init)
        switch parts {
        case ["today", "lookback"]: self = .lookBack
        case let entry where entry.count == 3 && entry[0] == "today" && entry[1] == "entry":
            guard let id = Int(entry[2]) else { return nil }
            self = .entry(id)
        default: return nil
        }
    }

    /// The row's id in Today's list.
    var anchor: String {
        switch self {
        case .entry(let id): "today-entry-\(id)"
        case .lookBack: "today-lookback"
        }
    }
}

extension AppModel {
    /// Goes where a dabble.me link points. A day's link opens its entry; a day without one opens
    /// the composer on it (not a day still to come, by the journal's own today).
    func open(_ link: AppLink) {
        // Not yet (signed out, or the journal's still loading): kept, and followed once it can be.
        guard isSignedIn, hasLoaded else { pendingLink = link; return }
        switch link {
        case .journal:
            // The Journal itself: its list, whatever view or entry was left open there. (A request
            // the Journal also acts on when it first appears: its tab may not exist yet.)
            selectedTab = .journal
            journalModeRequest = .list
        case .today:
            selectedTab = .today
            todayRootRequest += 1
        case .newEntry:
            // As the web's own page does: in the morning, yesterday's entry if it's unwritten.
            requestNewEntry()
        case .stats:
            selectedTab = .journal
            statsRequest += 1
        case .search(let term):
            // The tab; with something to look for, that search run in it.
            if let term { searchRequest = term }
            selectedTab = .search
        case .day(let day):
            selectedTab = .journal
            Task {
                // The composer only once the day is known to be empty: if the lookup fails,
                // writing there could add to an entry nobody's looking at.
                do {
                    if let entry = try await entrySummary(on: day) {
                        openEntryRequest = entry.id
                    } else if me?.canWrite != false, day <= (today?.day ?? JournalDay(localDate: .now)) {
                        composingDay = StatsDay(day: day)
                    }
                } catch is CancellationError {
                } catch {
                    timelineError = error.localizedDescription
                }
            }
        }
    }

    /// Follows a link that arrived before the app was ready for it.
    func openPendingLink() {
        guard isSignedIn, hasLoaded, let link = pendingLink else { return }
        pendingLink = nil
        open(link)
    }
}
