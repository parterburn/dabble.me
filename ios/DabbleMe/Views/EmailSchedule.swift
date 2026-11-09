import SwiftUI

/// Settings → Reminders → Daily Email: a summary row ("Mon, Wed, Fri · 8 PM") that opens a page
/// for the days, hour and time zone of the "How was your day?" email. PRO; greyed out for free
/// accounts, like the rest of Reminders.
struct EmailScheduleRow: View {
    @Environment(AppModel.self) private var model
    @State private var schedule: EmailSchedule?

    var body: some View {
        let isPro = model.me?.isPro == true
        NavigationLink {
            EmailScheduleView(schedule: $schedule)
        } label: {
            LabeledContent("Daily Email", value: schedule.map(Self.summary) ?? "")
        }
        .disabled(!isPro || schedule == nil)
        .task { if schedule == nil { schedule = try? await model.emailSchedule() } }
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

/// The Daily Email page: which days, what hour and in which time zone. Saves as you change it.
struct EmailScheduleView: View {
    @Binding var schedule: EmailSchedule?
    @Environment(AppModel.self) private var model
    @State private var error: String?
    /// The schedule as the server last confirmed it (to roll back to), and the save queue.
    @State private var confirmed: EmailSchedule?
    @State private var generation = 0
    @State private var isSaving = false
    @State private var needsSave = false

    var body: some View {
        Form {
            if let schedule {
                Section {
                    DayPicker(days: schedule.days, canChooseAll: schedule.canChooseDays) { days in
                        save { $0.days = days }
                    }
                } header: {
                    Text("Days")
                }
                Section {
                    Picker("Time", selection: Binding(get: { schedule.hour }, set: { hour in
                        save { $0.hour = hour }
                    })) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(Self.hourLabel(hour)).tag(hour)
                        }
                    }
                    NavigationLink {
                        TimeZonePicker(zones: schedule.timeZones, selected: schedule.timezone) { zone in
                            save { $0.timezone = zone }
                        }
                    } label: {
                        LabeledContent("Time Zone", value: Self.shortName(schedule.timezone))
                    }
                }
                .disabled(schedule.days.isEmpty)
            }
        }
        .navigationTitle("Daily Email")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't save your email schedule", isPresented: .present($error)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    /// Shows the change right away, then saves. One request at a time, always sending the latest
    /// whole schedule: taps made while a save is in flight are sent together once it returns, so
    /// requests can't land out of order and an older response never overwrites a newer choice.
    private func save(_ apply: (inout EmailSchedule) -> Void) {
        guard var changed = schedule else { return }
        if confirmed == nil { confirmed = changed }
        apply(&changed)
        schedule = changed
        generation += 1
        needsSave = true
        if !isSaving { Task { await flush() } }
    }

    private func flush() async {
        isSaving = true
        defer { isSaving = false }
        while needsSave, let current = schedule {
            needsSave = false
            let sent = generation
            do {
                let saved = try await model.updateEmailSchedule(
                    EmailScheduleUpdate(days: current.days, hour: current.hour, timezone: current.timezone))
                confirmed = saved
                if sent == generation { schedule = saved } // nothing newer is waiting
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

    static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "Pacific Time (US & Canada)" → "Pacific Time".
    static func shortName(_ zone: String) -> String {
        zone.replacingOccurrences(of: " (US & Canada)", with: "")
    }
}

/// S M T W T F S toggles. Free accounts can only turn Sunday on or off.
private struct DayPicker: View {
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
