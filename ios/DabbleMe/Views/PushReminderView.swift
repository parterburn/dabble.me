import SwiftUI
import UIKit

/// Settings → Reminders → Push: the daily notification. Whether it's on, when and on which days,
/// and the past entry it carries: shown in the notification or only mentioned, and (PRO) which
/// entries can come up, like the email's past entries but the reminder's own. Kept on this
/// device; the reminders are rebuilt as anything changes.
struct PushReminderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @AppStorage(ReminderSettings.enabledKey) private var isOn = false
    /// The time set for it, or `followsEmail` until one is: then it's the daily email's.
    @AppStorage(ReminderSettings.timeKey) private var time = ReminderSettings.followsEmail
    @AppStorage(ReminderSettings.emailTimeKey) private var emailTime = ReminderSettings.defaultTime
    @AppStorage(ReminderSettings.daysKey) private var days = EmailSchedule.allDays.joined(separator: ",")
    @AppStorage(ReminderSettings.pastEntriesKey) private var includesPastEntry = true
    @AppStorage(ReminderSettings.previewsKey) private var showsPreviews = true
    @AppStorage(ReminderSettings.pastFilterKey) private var pastFilter = ""
    @AppStorage(ReminderSettings.includeOldKey) private var includesOld = true
    /// The words being typed; kept on Return or on leaving the field.
    @State private var filterDraft: String?
    @FocusState private var filterFocused: Bool
    @State private var notificationsDenied = false
    @State private var filteredCount: Int?
    #if DEBUG
    @State private var pending = 0
    #endif

    private var isPro: Bool { model.me?.isPro == true }
    /// Everything that changes what's scheduled.
    private var settings: String { "\(isOn)|\(time)|\(days)|\(includesPastEntry)|\(showsPreviews)|\(pastFilter)|\(includesOld)" }

    var body: some View {
        Form {
            Section {
                Toggle("Daily Reminder", isOn: $isOn)
                    #if DEBUG
                    // For the reminders UI test only: an invisible count of what's scheduled.
                    .background {
                        Color.clear.frame(width: 1, height: 1)
                            .accessibilityElement()
                            .accessibilityLabel("\(pending) reminders scheduled")
                    }
                    #endif
                if isOn {
                    // The daily email's time until another is picked here.
                    DatePicker("Time", selection: Binding(
                        get: { ReminderSettings.date(fromMinutes: time >= 0 ? time : emailTime) },
                        set: { time = ReminderSettings.minutes(from: $0) }), displayedComponents: .hourAndMinute)
                }
                if notificationsDenied {
                    Button("Turn On Notifications in Settings", systemImage: "bell.slash") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            } footer: {
                Text("One notification a day. It's skipped on a day you've already written.")
            }

            if isOn {
                Section {
                    DayPicker(days: ReminderSettings.days(from: days), canChooseAll: true) { chosen in
                        days = chosen.joined(separator: ",")
                    }
                } header: {
                    Text("Days")
                }

                Section {
                    Toggle("Include a Past Entry", isOn: $includesPastEntry)
                    if includesPastEntry {
                        Toggle("Show Entry Previews", isOn: $showsPreviews)
                        // PRO, like the email's; greyed out for free accounts.
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Leave out entries with these words (separate them with commas)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("Words, separated by commas", text: Binding(get: { filterDraft ?? pastFilter }, set: { filterDraft = $0 }))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($filterFocused)
                                .onSubmit(keepFilter)
                        }
                        .padding(.vertical, 2)
                        .disabled(!isPro)
                        Toggle("Include Entries Over a Year Old", isOn: $includesOld)
                            .disabled(!isPro)
                    }
                } header: {
                    Text("Past Entries")
                } footer: {
                    Text(pastEntriesNote)
                }
                .onChange(of: filterFocused) { _, focused in if !focused { keepFilter() } }
            }
        }
        .onDisappear(perform: keepFilter)
        .navigationTitle("Push")
        .navigationBarTitleDisplayMode(.inline)
        .task { notificationsDenied = await ReminderScheduler.shared.isDenied() }
        .onChange(of: isOn) { _, on in Task { await turned(on: on) } }
        // Anything else that changes: the reminders are built again (the switch asks for
        // permission first, above).
        .task(id: settings) {
            await ReminderScheduler.shared.reschedule(for: model)
            filteredCount = ReminderScheduler.shared.filteredCount
            #if DEBUG
            try? await Task.sleep(for: .seconds(1))
            pending = await ReminderScheduler.shared.pendingCount()
            #endif
        }
    }

    private var pastEntriesNote: String {
        guard includesPastEntry else { return "The reminder only asks how your day was." }
        var note = showsPreviews
            ? "The reminder shows a past entry to look back on: the start of it and its photo, which can be seen without unlocking your phone."
            : "The reminder says there's a past entry to look back on, without showing it."
        if !isPro {
            note += " Leaving out entries is part of Dabble Me PRO."
        } else if !pastFilter.isEmpty, let filteredCount {
            note += " \(filteredCount == 1 ? "1 entry is" : "\(filteredCount.formatted()) entries are") left out."
        }
        return note
    }

    private func keepFilter() {
        guard let draft = filterDraft else { return }
        filterDraft = nil
        // "work , doctor" → "work, doctor"
        let words = draft.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if isPro { pastFilter = words.joined(separator: ", ") }
    }

    private func turned(on: Bool) async {
        if on, !(await ReminderScheduler.shared.requestPermission()) {
            notificationsDenied = true
            isOn = false
            return
        }
        notificationsDenied = false
        await ReminderScheduler.shared.reschedule(for: model)
    }
}
