import SwiftUI

/// The account's notification settings on dabble.me (GET/PATCH /api/v1/email_schedule): when the
/// daily email goes out, and which past entries a notification can carry, push or email. One
/// copy for Settings' rows and their pages. A change shows right away, then saves: one request
/// at a time, always sending the latest whole schedule, so taps made while a save is in flight
/// go together once it returns, requests can't land out of order, and an older response never
/// overwrites a newer choice.
@MainActor
@Observable
final class EmailScheduleStore {
    private(set) var schedule: EmailSchedule?
    var error: String?
    /// The schedule as the server last confirmed it (to roll back to), and the save queue.
    private var confirmed: EmailSchedule?
    private var generation = 0
    private var isSaving = false
    private var needsSave = false

    func load(with model: AppModel) async {
        guard schedule == nil else { return }
        schedule = try? await model.emailSchedule()
    }

    func save(with model: AppModel, _ apply: (inout EmailSchedule) -> Void) {
        guard var changed = schedule else { return }
        if confirmed == nil { confirmed = changed }
        apply(&changed)
        schedule = changed
        generation += 1
        needsSave = true
        if !isSaving { Task { await flush(model) } }
    }

    private func flush(_ model: AppModel) async {
        isSaving = true
        defer { isSaving = false }
        while needsSave, let current = schedule {
            needsSave = false
            let sent = generation
            do {
                // Filtering is PRO: free accounts don't send it (the server would refuse the save).
                let pro = current.canChooseDays
                let saved = try await model.updateEmailSchedule(
                    EmailScheduleUpdate(days: current.days, hour: current.hour, timezone: current.timezone,
                                        includePastEntries: current.includePastEntries,
                                        pastFilter: pro ? current.pastFilter : nil,
                                        includeOldEntries: pro ? current.includeOldEntries : nil))
                confirmed = saved
                if sent == generation { schedule = saved } // nothing newer is waiting
                // The push reminder carries the same past entries: built again with the choice.
                await ReminderScheduler.shared.settingsChanged(for: model)
            } catch is CancellationError {
                return
            } catch {
                // Back to what the server last confirmed, unless a newer change will be sent anyway.
                if sent == generation, !needsSave {
                    schedule = confirmed
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

/// Settings → Reminders → Past Entries: a summary row ("On", "Off") that opens the choices both
/// notifications share.
struct PastEntriesRow: View {
    let store: EmailScheduleStore

    var body: some View {
        NavigationLink {
            PastEntriesView(store: store)
        } label: {
            LabeledContent("Past Entries", value: store.schedule.map { $0.includePastEntries ? "On" : "Off" } ?? "")
        }
        .disabled(store.schedule == nil)
    }
}

/// The past entry a notification can carry, for the push reminder and the daily email alike
/// (like the web settings): whether there is one, words that leave entries out, and whether
/// entries over a year old can come up (those two are PRO). Saves as you change it.
struct PastEntriesView: View {
    let store: EmailScheduleStore
    @Environment(AppModel.self) private var model
    /// The words being typed; saved on Return or on leaving the page.
    @State private var filterDraft: String?
    @FocusState private var filterFocused: Bool

    var body: some View {
        @Bindable var store = store
        Form {
            if let schedule = store.schedule {
                Section {
                    Toggle("Include Past Entries in Notifications", isOn: Binding(get: { schedule.includePastEntries }, set: { on in
                        store.save(with: model) { $0.includePastEntries = on }
                    }))
                } footer: {
                    Text("Push and email notifications can each come with one of your past entries to look back on.")
                }
                if schedule.includePastEntries {
                    Section {
                        // PRO, like the web; greyed out for free accounts.
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Leave out entries with these words (separate them with commas)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("Words, separated by commas", text: Binding(get: { filterDraft ?? schedule.pastFilter }, set: { filterDraft = $0 }))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($filterFocused)
                                .onSubmit(saveFilter)
                        }
                        .padding(.vertical, 2)
                        .disabled(!schedule.canChooseDays)
                        if schedule.canChooseDays, schedule.hasOldEntries {
                            Toggle("Include Entries Over a Year Old", isOn: Binding(get: { schedule.includeOldEntries }, set: { on in
                                store.save(with: model) { $0.includeOldEntries = on }
                            }))
                        }
                    } footer: {
                        if !schedule.canChooseDays {
                            Text("Leaving out entries is part of Dabble Me PRO.")
                        } else if !schedule.pastFilter.isEmpty {
                            Text("\(schedule.filteredCount == 1 ? "1 entry is" : "\(schedule.filteredCount.formatted()) entries are") left out of past entries.")
                        }
                    }
                }
            }
        }
        .onChange(of: filterFocused) { _, focused in if !focused { saveFilter() } }
        // Shows the words as saved ("work, doctor") once they are.
        .onChange(of: store.schedule?.pastFilter) { if !filterFocused { filterDraft = nil } }
        .onDisappear(perform: saveFilter)
        .navigationTitle("Past Entries")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't save your settings", isPresented: .present($store.error)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.error ?? "")
        }
    }

    private func saveFilter() {
        guard let draft = filterDraft, let schedule = store.schedule, schedule.canChooseDays, draft != schedule.pastFilter else { return }
        store.save(with: model) { $0.pastFilter = draft }
    }
}

/// Settings → Reminders → Email: a summary row ("Mon, Wed, Fri · 8 PM") that opens a page
/// for the days, hour and time zone of the "How was your day?" email. PRO; greyed out for free
/// accounts.
struct EmailScheduleRow: View {
    let store: EmailScheduleStore
    @Environment(AppModel.self) private var model

    var body: some View {
        let isPro = model.me?.isPro == true
        NavigationLink {
            EmailScheduleView(store: store)
        } label: {
            LabeledContent("Email", value: store.schedule.map(Self.summary) ?? "")
        }
        .disabled(!isPro || store.schedule == nil)
    }

    /// "Every day · 8 PM", "Weekdays · 7 AM", "Sundays · 8 PM", "Mon, Wed, Fri · 9 PM", "Off".
    static func summary(_ schedule: EmailSchedule) -> String {
        let days = EmailSchedule.allDays.filter(schedule.days.contains)
        let when: String
        switch days {
        case []: return "Off"
        case EmailSchedule.allDays: when = "Every day"
        case ["Mon", "Tue", "Wed", "Thu", "Fri"]: when = "Weekdays"
        case ["Sun", "Sat"]: when = "Weekends"
        case let one where one.count == 1:
            when = Calendar.current.weekdaySymbols[EmailSchedule.allDays.firstIndex(of: one[0]) ?? 0] + "s"
        default: when = days.joined(separator: ", ")
        }
        return "\(when) · \(EmailScheduleView.hourLabel(schedule.hour))"
    }
}

/// The Email Notifications page: which days, what hour and in which time zone the daily email
/// goes out. Saves as you change it. (Which past entry it includes is on Past Entries.)
struct EmailScheduleView: View {
    let store: EmailScheduleStore
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var store = store
        Form {
            if let schedule = store.schedule {
                Section {
                    DayPicker(days: schedule.days, canChooseAll: schedule.canChooseDays) { days in
                        store.save(with: model) { $0.days = days }
                    }
                } header: {
                    Text("Days")
                }
                Section {
                    Picker("Time", selection: Binding(get: { schedule.hour }, set: { hour in
                        store.save(with: model) { $0.hour = hour }
                    })) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(Self.hourLabel(hour)).tag(hour)
                        }
                    }
                    NavigationLink {
                        TimeZonePicker(zones: schedule.timeZones, selected: schedule.timezone) { zone in
                            store.save(with: model) { $0.timezone = zone }
                        }
                    } label: {
                        LabeledContent("Time Zone", value: Self.shortName(schedule.timezone))
                    }
                }
                .disabled(schedule.days.isEmpty)
            }
        }
        .navigationTitle("Email Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't save your email schedule", isPresented: .present($store.error)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.error ?? "")
        }
    }

    static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "Pacific Time (US & Canada)" → "Pacific Time".
    static func shortName(_ zone: String) -> String {
        zone.replacingOccurrences(of: " (US & Canada)", with: "")
    }
}

/// S M T W T F S toggles. For the email, free accounts can only turn Sunday on or off.
struct DayPicker: View {
    let days: [String]
    let canChooseAll: Bool
    let onChange: ([String]) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(EmailSchedule.allDays, id: \.self) { day in
                let on = days.contains(day)
                let locked = !canChooseAll && day != "Sun"
                Button {
                    let updated = on ? days.filter { $0 != day } : days + [day]
                    onChange(EmailSchedule.allDays.filter(updated.contains))
                } label: {
                    Text(day.prefix(1))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(on ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.12)), in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(locked)
                .opacity(locked ? 0.35 : 1)
                .accessibilityLabel(Calendar.current.weekdaySymbols[EmailSchedule.allDays.firstIndex(of: day) ?? 0])
                .accessibilityValue(on ? "On" : "Off")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TimeZonePicker: View {
    let zones: [EmailSchedule.TimeZoneOption]
    let selected: String
    let onSelect: (String) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    /// This device's zone, when the list has it (matched by IANA identifier).
    private var deviceZone: EmailSchedule.TimeZoneOption? {
        zones.first { $0.iana == TimeZone.current.identifier }
    }

    private var filtered: [EmailSchedule.TimeZoneOption] {
        query.isEmpty ? zones : zones.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if query.isEmpty, let deviceZone, deviceZone.name != selected {
                Section {
                    Button("Use This Device's Time Zone (\(EmailScheduleView.shortName(deviceZone.name)))") { pick(deviceZone.name) }
                }
            }
            ForEach(filtered) { zone in
                Button {
                    pick(zone.name)
                } label: {
                    HStack {
                        Text(zone.name).foregroundStyle(.primary)
                        Spacer()
                        Text("GMT\(zone.offset)").foregroundStyle(.secondary).monospacedDigit()
                        if zone.name == selected {
                            appIcon("slab-check").foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search time zones")
        .navigationTitle("Time Zone")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pick(_ name: String) {
        onSelect(name)
        dismiss()
    }
}
