import EventKit
import Foundation

/// One thing on the phone's calendar on a day: its title and when ("9:00 AM", "All day").
struct DayEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let time: String
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

    /// The day's events, all-day ones first and then by time. Not the ones declined or
    /// cancelled, and one that repeats across calendars shows once.
    static func events(on day: Date, calendar: Calendar = .current) -> [DayEvent] {
        #if DEBUG
        if usesSamples { return samples }
        #endif
        let start = calendar.startOfDay(for: day)
        guard access == .allowed, let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let found = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
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
        DayEvent(id: "4", title: "Book club", time: "7:00 PM"),
    ]
    #endif
}
