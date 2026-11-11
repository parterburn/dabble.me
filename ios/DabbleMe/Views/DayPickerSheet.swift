import SwiftUI
import UIKit

/// Jump to a Day (from the Journal's timeline scrubber, Search, or a day's sheet): a calendar of
/// the days you wrote (a dot under each, and only those can be picked); the day picked comes up
/// in the day sheet. UIKit's calendar, since SwiftUI's
/// DatePicker can't limit which days are selectable.
struct DayPickerSheet: View {
    let onPick: (JournalDay) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<String>?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Jump to a Day", icon: "slab-calendar")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                SheetCloseButton()
            }
            if let days {
                EntryCalendar(days: days) { day in
                    dismiss()
                    onPick(day)
                }
            } else if let error {
                ContentUnavailableView("Couldn't load your days", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .padding([.horizontal, .top], 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            do {
                days = Set(try await model.entryDays())
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct EntryCalendar: UIViewRepresentable {
    let days: Set<String>
    let onPick: (JournalDay) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(days: days, onPick: onPick) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Calendar(identifier: .gregorian)
        view.locale = .current
        view.tintColor = UIColor(named: "AccentColor")
        view.delegate = context.coordinator
        view.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
        let sorted = days.sorted()
        let calendar = view.calendar
        // From the first entry to today or the latest entry, whichever is later: a day can be
        // ahead of the phone's (a journal time zone ahead of it, or an entry dated forward).
        if let first = sorted.first.flatMap(JournalDay.init)?.components, let start = calendar.date(from: first) {
            let latest = sorted.last.flatMap(JournalDay.init)?.components.flatMap { calendar.date(from: $0) } ?? start
            view.availableDateRange = DateInterval(start: start, end: max(start, latest, .now))
        }
        // Open on the month of the latest entry.
        if let latest = sorted.last.flatMap(JournalDay.init)?.components {
            view.visibleDateComponents = DateComponents(calendar: calendar, year: latest.year, month: latest.month)
        }
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        // Its own minimum width would push the sheet's column (and its title and X) past the
        // screen edges; it fits the width it's given instead.
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let height = uiView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                    withHorizontalFittingPriority: .required,
                                                    verticalFittingPriority: .fittingSizeLevel).height
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        let days: Set<String>
        let onPick: (JournalDay) -> Void

        init(days: Set<String>, onPick: @escaping (JournalDay) -> Void) {
            self.days = days
            self.onPick = onPick
        }

        private func iso(_ components: DateComponents) -> String? {
            guard let year = components.year, let month = components.month, let day = components.day else { return nil }
            return String(format: "%04d-%02d-%02d", year, month, day)
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let iso = iso(dateComponents), days.contains(iso) else { return nil }
            return .default(color: UIColor(named: "AccentColor"), size: .small)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?) -> Bool {
            guard let dateComponents, let iso = iso(dateComponents) else { return false }
            return days.contains(iso)
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let iso = iso(dateComponents), let day = JournalDay(iso) else { return }
            onPick(day)
        }
    }
}

private extension JournalDay {
    /// Year, month and day, for UIKit's calendar (a calendar date, no time zone).
    var components: DateComponents? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }
}
