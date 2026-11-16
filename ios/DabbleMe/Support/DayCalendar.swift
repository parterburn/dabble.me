import CoreGraphics
import EventKit
import Foundation

/// One thing on the phone's calendar on a day: its title and when ("9:00 AM", "All day").
struct DayEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let time: String
}

/// One of the phone's calendars, to choose in Settings → Calendars whether its events show.
struct CalendarChoice: Identifiable {
    let id: String
    let title: String
    /// The account it's in ("iCloud", "Gmail"), to group them by.
    let account: String
    let color: CGColor?
    var isOn: Bool
}

/// The phone's own calendar, read for one day at a time when the writer asks to see it (the
/// composer's calendar row): a reminder of what the day held. Read on the device and shown;
/// nothing of it goes to Dabble Me unless it's tapped into an entry.
@MainActor
enum DayCalendar {
    enum Access { case allowed, notAsked, denied }

    private static let store = EKEventStore()

    static var access: Access {
        #if DEBUG
        if usesSamples { return .allowed }
        #endif
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .allowed
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    /// iOS's own question, the first time the row is opened.
    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    // MARK: - Which calendars

    /// The choices made in Settings → Calendars, by calendar. One not chosen either way is on,
    /// unless it's a subscribed one (holidays, a team's fixtures): those are mostly not the
    /// writer's own day. (iOS doesn't say which calendars are ticked in the Calendar app.)
    private static let choicesKey = "calendar.choices"

    private static var choices: [String: Bool] {
        get { UserDefaults.standard.dictionary(forKey: choicesKey) as? [String: Bool] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: choicesKey) }
    }

    private static func isOn(_ calendar: EKCalendar) -> Bool {
        choices[calendar.calendarIdentifier] ?? (calendar.type != .subscription)
    }

    /// Every calendar on the phone, by account and then name.
    static func calendars() -> [CalendarChoice] {
        guard access == .allowed else { return [] }
        return store.calendars(for: .event)
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "", color: $0.cgColor, isOn: isOn($0)) }
            .sorted { ($0.account.lowercased(), $0.title.lowercased()) < ($1.account.lowercased(), $1.title.lowercased()) }
    }

    static func setCalendar(_ id: String, on: Bool) {
        choices[id] = on
    }

    /// The day's events from the chosen calendars, all-day ones first and then by time. Not the
    /// ones declined or cancelled, and one that repeats across calendars shows once.
    static func events(on day: Date, calendar: Calendar = .current) -> [DayEvent] {
        #if DEBUG
        if usesSamples { return samples }
        #endif
        let start = calendar.startOfDay(for: day)
        guard access == .allowed, let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let chosen = store.calendars(for: .event).filter(isOn)
        guard !chosen.isEmpty else { return [] } // (no calendars would mean all of them)
        let found = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: chosen))
            .filter { event in
                event.status != .canceled && !(event.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                    && event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined
            }
            .sorted { first, second in
                let (a, b) = (first.isAllDay || first.startDate < start, second.isAllDay || second.startDate < start)
                return a != b ? a : first.startDate < second.startDate
            }
        var seen = Set<String>()
        return found.compactMap { event in
            // One that began before the day (a trip, say) is there all day too.
            let time = event.isAllDay || event.startDate < start ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened)
            let title = event.title.trimmingCharacters(in: .whitespaces)
            guard seen.insert("\(time)|\(title.lowercased())").inserted else { return nil }
            return DayEvent(id: "\(event.eventIdentifier ?? title)|\(time)", title: title, time: time)
        }
    }

    #if DEBUG
    /// UI tests and screenshots: -DabbleDebugCalendar YES shows a made-up day, without asking
    /// for the simulator's calendar.
    private static var usesSamples: Bool { UserDefaults.standard.bool(forKey: "DabbleDebugCalendar") }
    private static let samples = [
        DayEvent(id: "1", title: "Leo's birthday", time: "All day"),
        DayEvent(id: "2", title: "Dentist", time: "9:00 AM"),
        DayEvent(id: "3", title: "Lunch with Sam", time: "12:30 PM"),
        DayEvent(id: "4", title: "Pick up the cake", time: "3:15 PM"),
        DayEvent(id: "5", title: "Book club", time: "7:00 PM"),
    ]
    #endif
}
