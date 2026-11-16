import SwiftUI
import UIKit

/// Settings → Reminders → Push: the daily notification. Whether it's on, when and on which days.
/// And whether it shows the past entry it looks back on, or just says there is one. (Which
/// entries can come up is on Past Entry Filters, shared with the email and the widget.) Kept on this device; the reminders are rebuilt as anything changes.
struct PushReminderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @AppStorage(ReminderSettings.enabledKey) private var isOn = false
    /// The time set for it, or `followsEmail` until one is: then it's the daily email's.
    @AppStorage(ReminderSettings.timeKey) private var time = ReminderSettings.followsEmail
    @AppStorage(ReminderSettings.emailTimeKey) private var emailTime = ReminderSettings.defaultTime
    @AppStorage(ReminderSettings.daysKey) private var days = EmailSchedule.allDays.joined(separator: ",")
    @AppStorage(ReminderSettings.includesPastEntryKey) private var showsPastEntryStored = true
    /// The email's past-entry switch, which this one follows until it's set here.
    var emailShowsPastEntry = true
    @State private var notificationsDenied = false
    #if DEBUG
    @State private var pending = 0
    #endif

    /// Everything that changes what's scheduled.
    private var settings: String { "\(isOn)|\(time)|\(days)|\(showsPastEntryStored)" }

    var body: some View {
        Form {
            Section {
                Toggle("Push Notifications", isOn: $isOn)
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
                // A morning reminder (10 or earlier) is for the day before: see NotificationRouter.
                if isOn, (time >= 0 ? time : emailTime) <= AppModel.morningEnds {
                    Text("One notification a day. It's skipped on a day you've already written. Set for 10 AM or earlier, tapping it opens yesterday's entry to write, or today's if yesterday is already written.")
                } else {
                    Text("One notification a day. It's skipped on a day you've already written.")
                }
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
                    Toggle("Show Past Entry", isOn: Binding(get: { ReminderSettings.includesPastEntry ?? emailShowsPastEntry },
                                                            set: { showsPastEntryStored = $0 }))
                } footer: {
                    Text("The notification can show an entry to look back on: its first lines and its photo. With this off it only says how many there are.")
                }
            }
        }
        .slabBackButton()
        .navigationTitle("Push Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { notificationsDenied = await ReminderScheduler.shared.isDenied() }
        .onChange(of: isOn) { _, on in Task { await turned(on: on) } }
        // Anything else that changes: the reminders are built again (the switch asks for
        // permission first, above).
        .task(id: settings) {
            await ReminderScheduler.shared.reschedule(for: model)
            #if DEBUG
            try? await Task.sleep(for: .seconds(1))
            pending = await ReminderScheduler.shared.pendingCount()
            #endif
        }
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
