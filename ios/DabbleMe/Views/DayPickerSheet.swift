import SwiftUI
import UIKit

/// Jump to a Day (from the Journal's timeline scrubber, Search, or a day's sheet): a calendar of
/// the days you wrote (a dot under each, and only those can be picked); the day picked comes up
/// in the day sheet. Opened again, it's on the month of the day last looked at. Hold a day for a
/// preview of its entry, or (a day without one) to write it. The app's own calendar: UIKit's
/// can't be held, and its arrows aren't ours.
struct DayPickerSheet: View {
    let onPick: (JournalDay) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<String>?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(title: "Jump to a Day")
            if let days {
                EntryCalendar(days: days, opensOn: model.dayPickerOpensOn, today: model.today?.day ?? JournalDay(localDate: .now),
                              model: model, onPick: { day in
                    dismiss()
                    onPick(day)
                }, onWrite: model.me?.canWrite == false ? nil : { day in
                    model.writeAfterDayPicker = day
                    dismiss()
                })
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

/// A month of the journal at a time, from the first entry's to today's: the Slab arrows (or a
/// swipe) step through the months, and the month's name is a menu of the years.
private struct EntryCalendar: View {
    let days: Set<String>
    /// The day last looked at: the calendar opens on its month (else on the latest entry's).
    var opensOn: JournalDay? = nil
    let today: JournalDay
    let model: AppModel
    let onPick: (JournalDay) -> Void
    var onWrite: ((JournalDay) -> Void)?

    /// Months counted from year 0, so stepping is adding one.
    @State private var month: Int?
    /// The months' entries, for previews that are ready when a day's held.
    @State private var summaries: [Int: [String: EntrySummary]] = [:]

    private static func index(_ day: JournalDay) -> Int {
        let parts = day.iso.split(separator: "-").compactMap { Int($0) }
        return parts.count == 3 ? parts[0] * 12 + parts[1] - 1 : 0
    }

    private var first: Int { days.min().flatMap(JournalDay.init).map(Self.index) ?? Self.index(today) }
    private var last: Int { max(Self.index(today), days.max().flatMap(JournalDay.init).map(Self.index) ?? 0) }
    private var shown: Int { min(max(month ?? Self.index(opensOn ?? days.max().flatMap(JournalDay.init) ?? today), first), last) }

    /// The month's days, after blanks for the weekdays before its first (Sunday starts the week,
    /// as in Stats).
    private func cells(_ month: Int) -> [JournalDay?] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let start = calendar.date(from: DateComponents(year: month / 12, month: month % 12 + 1, day: 1)),
              let count = calendar.range(of: .day, in: .month, for: start)?.count else { return [] }
        let blanks = calendar.component(.weekday, from: start) - 1
        return [JournalDay?](repeating: nil, count: blanks)
            + (1...count).map { JournalDay(String(format: "%04d-%02d-%02d", month / 12, month % 12 + 1, $0)) }
    }

    private func title(_ month: Int) -> String {
        JournalDay(String(format: "%04d-%02d-01", month / 12, month % 12 + 1))?.monthTitle ?? ""
    }

    var body: some View {
        let shown = shown
        VStack(spacing: 14) {
            HStack {
                Menu {
                    Picker("Year", selection: Binding(get: { shown / 12 }, set: { month = min(max($0 * 12 + shown % 12, first), last) })) {
                        ForEach(Array((first / 12...last / 12).reversed()), id: \.self) { Text(String($0)).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(title(shown))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        appIcon("slab-angle-down")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 11, height: 11)
                            .foregroundStyle(.tint)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(shown))
                .accessibilityHint("Chooses another year")
                Spacer()
                step("slab-angle-left", "Previous Month", to: shown - 1)
                step("slab-angle-right", "Next Month", to: shown + 1)
            }
            HStack(spacing: 0) {
                ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                ForEach(Array(cells(shown).enumerated()), id: \.offset) { _, day in
                    if let day { cell(day, in: shown) } else { Color.clear.frame(height: 48) }
                }
            }
            // Six rows' room whatever the month, so the sheet doesn't jump between them.
            .frame(height: 6 * 48 + 5 * 6, alignment: .top)
            .id(shown)
            .transition(.opacity)
        }
        .contentShape(.rect)
        .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
            guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
            go(to: shown + (drag.translation.width < 0 ? 1 : -1))
        })
        .task(id: shown) {
            guard summaries[shown] == nil else { return }
            summaries[shown] = (try? await model.entrySummaries(year: shown / 12, month: shown % 12 + 1)) ?? [:]
        }
    }

    private func go(to target: Int) {
        guard (first...last).contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { month = target }
    }

    private func step(_ icon: String, _ label: String, to target: Int) -> some View {
        Button { go(to: target) } label: {
            appIcon(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(!(first...last).contains(target))
        .opacity((first...last).contains(target) ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    /// A day: its number, with a dot under it when it has an entry (those open; the rest are
    /// grey). Today's is ringed. Held, any day gone by previews.
    @ViewBuilder
    private func cell(_ day: JournalDay, in month: Int) -> some View {
        let written = days.contains(day.iso)
        let ahead = day > today
        let face = VStack(spacing: 3) {
            Text(day.dayNumber)
                .font(.body.weight(written ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(written ? AnyShapeStyle(.primary) : ahead ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tertiary))
                .frame(width: 34, height: 34)
                .overlay { if day == today { Circle().strokeBorder(.tint, lineWidth: 1.5) } }
            Circle()
                .fill(written ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(.rect)
        .accessibilityElement()
        .accessibilityLabel(day.long)
        .accessibilityValue(written ? "Has an entry" : "No entry")
        if ahead && !written {
            face
        } else {
            Button { if written { onPick(day) } } label: { face }
                .buttonStyle(.plain)
                .dayPreview(day, isWritten: written, summary: summaries[month]?[day.iso], model: model,
                            open: { onPick(day) }, write: onWrite.map { write in { write(day) } })
        }
    }
}
