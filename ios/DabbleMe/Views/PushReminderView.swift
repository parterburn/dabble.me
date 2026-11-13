import SwiftUI
import UIKit

/// Settings → Reminders → Push: the daily notification. Whether it's on, when and on which days,
/// and whether the past entry it carries is shown in it or only mentioned. (Which past entries
/// can come up is on Past Entries, shared with the email.) Kept on this device; the reminders
/// are rebuilt as anything changes.
struct PushReminderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @AppStorage(ReminderSettings.enabledKey) private var isOn = false
    /// The time set for it, or `followsEmail` until one is: then it's the daily email's.
    @AppStorage(ReminderSettings.timeKey) private var time = ReminderSettings.followsEmail
    @AppStorage(ReminderSettings.emailTimeKey) private var emailTime = ReminderSettings.defaultTime
    @AppStorage(ReminderSettings.daysKey) private var days = EmailSchedule.allDays.joined(separator: ",")
    @AppStorage(ReminderSettings.previewsKey) private var showsPreviews = true
    @State private var notificationsDenied = false
    #if DEBUG
    @State private var pending = 0
    #endif

    /// Everything that changes what's scheduled.
    private var settings: String { "\(isOn)|\(time)|\(days)|\(showsPreviews)" }

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
                    Toggle("Show Entry Previews", isOn: $showsPreviews)
                } footer: {
                    Text(showsPreviews
                        ? "With a past entry (Settings › Include Past Entries), the notification shows the start of it and its photo, which can be seen without unlocking your phone."
                        : "With a past entry (Settings › Include Past Entries), the notification says there's one to look back on, without showing it.")
                }
            }
        }
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
