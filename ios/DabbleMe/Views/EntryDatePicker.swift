import SwiftUI
import UIKit

/// The composer's date: iOS's own month calendar in a popover under the date, with a dot under
/// each day that already has an entry. Any day from the first entry's up to today can be picked
/// (a written one too: writing there adds to its entry); picking one closes it.
struct EntryDatePopover: View {
    @Binding var date: Date
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var written: Set<String> = []

    var body: some View {
        // Not before the first entry: a journal starts where it started.
        WrittenDaysCalendar(selected: date, written: written, startsAtFirstWritten: true) { day in
            date = day.localDate
            dismiss()
        }
        .calendarDropdownSize()
        // The calendar is there right away; the dots come in once the days are known.
        .task { written = Set((try? await model.entryDays()) ?? []) }
        .presentationCompactAdaptation(.popover)
    }
}

extension View {
    /// The calendar's size in a popover: a whole month with its dots.
    func calendarDropdownSize() -> some View {
        frame(width: 330, height: 430)
            .padding(.horizontal, 8)
            .padding(.top, 8)
    }
}

/// iOS's month calendar (`UICalendarView`: SwiftUI's DatePicker can't mark days) up to today,
/// with a dot under each written day. A tap on any day picks it.
struct WrittenDaysCalendar: UIViewRepresentable {
    /// The day filled in when it opens (an entry's date), if any.
    var selected: Date? = nil
    /// The month it opens on, when that isn't the selected day's or this one.
    var opensOn: JournalDay? = nil
    let written: Set<String>
    /// No further back than the first written day.
    var startsAtFirstWritten = false
    /// Changes each time the calendar should turn to this month (a Today button beside it).
    var showsToday = 0
    /// Today by the journal's clock, which can be a day off the phone's (travelling).
    var today: JournalDay?
    let onPick: (JournalDay) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// The last day to pick: today, the later of the phone's and the journal's.
    private var lastDay: Date { max(.now, today?.localDate ?? .now) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = .current
        view.availableDateRange = DateInterval(start: .distantPast, end: lastDay)
        view.tintColor = UIColor(named: "AccentColor")
        view.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        if let selected {
            selection.selectedDate = Calendar.current.dateComponents([.year, .month, .day], from: selected)
        } else if let opensOn {
            view.visibleDateComponents = Calendar.current.dateComponents([.year, .month], from: opensOn.localDate)
        }
        view.selectionBehavior = selection
        // As wide and tall as it's given, not its own preferred size.
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        if context.coordinator.parent.showsToday != showsToday {
            view.setVisibleDateComponents(Calendar.current.dateComponents([.year, .month], from: today?.localDate ?? .now), animated: true)
        }
        context.coordinator.parent = self
        guard context.coordinator.written != written else { return }
        context.coordinator.written = written
        if startsAtFirstWritten, let first = written.min().flatMap(JournalDay.init)?.localDate, first < lastDay {
            view.availableDateRange = DateInterval(start: first, end: lastDay)
        }
        // The month on screen; others ask for their dots as they come into view.
        let month = view.visibleDateComponents
        let prefix = String(format: "%04d-%02d-", month.year ?? 0, month.month ?? 0)
        let days = written.filter { $0.hasPrefix(prefix) }.compactMap { iso -> DateComponents? in
            guard let day = Int(iso.suffix(2)) else { return nil }
            return DateComponents(calendar: .current, year: month.year, month: month.month, day: day)
        }
        view.reloadDecorations(forDateComponents: days, animated: true)
    }

    @MainActor
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: WrittenDaysCalendar
        var written: Set<String> = []

        init(_ parent: WrittenDaysCalendar) { self.parent = parent }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            let iso = String(format: "%04d-%02d-%02d", dateComponents.year ?? 0, dateComponents.month ?? 0, dateComponents.day ?? 0)
            return written.contains(iso) ? .default(color: UIColor(named: "AccentColor"), size: .medium) : nil
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let picked = Calendar.current.date(from: dateComponents) else { return }
            parent.onPick(JournalDay(localDate: picked))
        }

        // A day stays picked: tapping it again doesn't clear it.
        func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool {
            dateComponents != nil
        }
    }
}
