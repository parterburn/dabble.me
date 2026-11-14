import SwiftUI

/// Jump to a Day (from the Journal's timeline scrubber or its "me" mark held, Search, or an open
/// entry's date held): iOS's month calendar with a dot under each day you wrote, from the first
/// of them on. A written day opens its entry in full; a day without one opens the composer on
/// it. Opened again, it's on the month of the day last looked at.
struct DayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SheetHeader(title: "Jump to a Day")
            DayPickerCalendar { dismiss() }
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
        }
        .padding([.horizontal, .top], 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(540)])
        .presentationDragIndicator(.visible)
    }
}

/// The sheet's calendar. What
/// was picked is left with the model (`pickedDay`, or `writeAfterDayPicker` for a day without an
/// entry), which acts on it once this has closed (`finishDayPicker`).
struct DayPickerCalendar: View {
    let close: () -> Void
    @Environment(AppModel.self) private var model
    /// The days with an entry, once they've loaded.
    @State private var days: Set<String>?

    var body: some View {
        WrittenDaysCalendar(opensOn: model.dayPickerOpensOn, written: days ?? [], startsAtFirstWritten: true) { day in
            Task { await pick(day) }
        }
        .task { days = await loadedDays() }
    }

    private func loadedDays() async -> Set<String>? {
        if let days { return days }
        return (try? await model.entryDays()).map(Set.init)
    }

    private func pick(_ day: JournalDay) async {
        // A tap before the days arrived waits for them. If they can't be had, the day's sheet
        // says what's there.
        let written = await loadedDays()
        if written?.contains(day.iso) == false {
            guard model.me?.canWrite != false else { return }
            model.writeAfterDayPicker = day
        } else {
            model.pickedDay = day
        }
        close()
    }
}
