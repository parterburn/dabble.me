import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var confirmingSignOut = false
    @State private var confirmingDeletion = false
    @State private var deletionEmail: String?
    @State private var deletionError: String?
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReadingFontStyle.storageKey) private var fontStyle = ReadingFontStyle.serif
    @AppStorage(ReminderSettings.writingEnabledKey) private var writingReminder = false
    @AppStorage(ReminderSettings.writingTimeKey) private var writingTime = ReminderSettings.defaultWritingTime
    @AppStorage(ReminderSettings.memoriesEnabledKey) private var memoriesReminder = false
    @AppStorage(ReminderSettings.memoriesTimeKey) private var memoriesTime = ReminderSettings.defaultMemoriesTime
    @State private var notificationsDenied = false
    @AppStorage(WidgetSnapshot.showMemoriesKey, store: WidgetSnapshot.defaults) private var widgetShowsMemories = false
    @AppStorage(JournalIntelligence.enabledKey) private var onDeviceAI = true
    /// The plan links to dabble.me/subscribe only on the US App Store, where Apple allows links to
    /// buy outside the app (guideline 3.1.1(a), US storefront). Elsewhere it's plain text.
    @State private var canLinkToSubscribe = false
    #if DEBUG
    @State private var pendingReminders = 0
    #endif

    var body: some View {
        NavigationStack {
            List {
                if let me = model.me {
                    Section("Account") {
                        LabeledContent("Email", value: me.email)
                        if canLinkToSubscribe {
                            Link(destination: AppConfig.webURL("subscribe")) {
                                LabeledContent("Plan") {
                                    HStack(spacing: 4) {
                                        Text(me.isPro ? "PRO" : "Free")
                                        Image(systemName: "arrow.up.forward").font(.caption)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        } else {
                            LabeledContent("Plan", value: me.isPro ? "PRO" : "Free")
                        }
                        // Dates for #tags (PRO, like the web settings); greyed out for free accounts.
                        NavigationLink {
                            TagDatesView()
                        } label: {
                            Label("Manage Hashtags", icon: "slab-tag")
                        }
                        .disabled(!me.isPro)
                    }
                }

                remindersSection
                intelligenceSection
                privacySection

                Section {
                    NavigationLink {
                        AccessibilitySettingsView()
                    } label: {
                        LabeledContent {
                            Text("\(textSize.label), \(fontStyle.label)")
                        } label: {
                            Label("Accessibility", systemImage: "textformat.size")
                        }
                    }
                }

                Section {
                    // Connecting happens on the web (OAuth on dabble.me, PRO plus a passkey or 2FA);
                    // the guide links to Claude's and ChatGPT's directories.
                    if let connectors = model.me?.aiConnectors {
                        Link(destination: connectors.guideUrl) {
                            Label("Claude/ChatGPT Connector", icon: "slab-sparkles")
                        }
                    }
                    Link(destination: model.me?.securityUrl ?? AppConfig.webURL("security")) {
                        Label("Account Security", icon: "slab-shield")
                    }
                    Link(destination: URL(string: "#export", relativeTo: AppConfig.webURL("users/edit"))!.absoluteURL) {
                        Label("Export Entries", icon: "slab-arrow-up-from-line")
                    }
                } header: {
                    Text("On dabble.me")
                }

                Section {
                    Link(destination: AppConfig.webURL("support")) {
                        Label("Help & Support", icon: "slab-circle-question")
                    }
                    Link(destination: AppConfig.webURL("privacy")) {
                        Label("Privacy Policy", icon: "slab-hand")
                    }
                    Link(destination: AppConfig.webURL("terms")) {
                        Label("Terms", icon: "slab-anchor")
                    }
                }

                Section {
                    // Each dialog is attached to its button so it appears next to it, not at the top.
                    Button("Sign Out", role: .destructive) { confirmingSignOut = true }
                        .confirmationDialog("Sign out of Dabble Me?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                            Button("Sign Out", role: .destructive) { Task { await model.signOut() } }
                        }
                    Button("Delete Account…", role: .destructive) { confirmingDeletion = true }
                        // Deleting takes three deliberate steps: confirm here, open the emailed link, then
                        // confirm with your password on dabble.me (and it can still be undone for an hour).
                        .confirmationDialog("Delete your Dabble Me account?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                            Button("Email Me a Deletion Link", role: .destructive) { Task { await requestDeletion() } }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("We'll email you a link to finish on dabble.me, where you'll confirm with your password. You can export your entries there first.")
                        }
                } footer: {
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text("Dabble Me for iOS \(version)")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title) // the tab says where you are
            .task { notificationsDenied = await ReminderScheduler.shared.isDenied() }
            .task { canLinkToSubscribe = await Storefront.current?.countryCode == "USA" }
            .onChange(of: writingReminder) { _, on in Task { await remindersChanged(turnedOn: on) } }
            .onChange(of: memoriesReminder) { _, on in Task { await remindersChanged(turnedOn: on) } }
            .onChange(of: writingTime) { Task { await ReminderScheduler.shared.reschedule(for: model) } }
            .onChange(of: memoriesTime) { Task { await ReminderScheduler.shared.reschedule(for: model) } }
            .alert("Check your email", isPresented: .present($deletionEmail)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("We sent a link to \(deletionEmail ?? "your email") to finish deleting your account. Nothing has been deleted yet.")
            }
            .alert("Couldn't send the email", isPresented: .present($deletionError)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deletionError ?? "")
            }
        }
    }
}

private extension SettingsView {
    // MARK: - Reminders (PRO)

    @ViewBuilder
    var remindersSection: some View {
        Section {
            if model.me?.isPro != true {
                Label("Reminders are part of Dabble Me PRO.", systemImage: "bell")
                    .foregroundStyle(.secondary)
                EmailScheduleRow()
            } else {
                Toggle("Daily Writing Reminder", isOn: $writingReminder)
                    #if DEBUG
                    // For the reminders UI test only: an invisible count of what's scheduled.
                    .background {
                        Color.clear.frame(width: 1, height: 1)
                            .accessibilityElement()
                            .accessibilityLabel("\(pendingReminders) reminders scheduled")
                            .task(id: "\(writingReminder)\(memoriesReminder)\(writingTime)\(memoriesTime)") {
                                try? await Task.sleep(for: .seconds(2))
                                pendingReminders = await ReminderScheduler.shared.pendingCount()
                            }
                    }
                    #endif
                if writingReminder {
                    DatePicker("Time", selection: minutesBinding($writingTime), displayedComponents: .hourAndMinute)
                }
                Toggle("On This Day Memories", isOn: $memoriesReminder)
                if memoriesReminder {
                    DatePicker("Time", selection: minutesBinding($memoriesTime), displayedComponents: .hourAndMinute)
                }
                EmailScheduleRow()
                if notificationsDenied {
                    Button("Turn On Notifications in Settings", systemImage: "bell.slash") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            }
        } header: {
            Text("Reminders")
        }
    }

    func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: { ReminderSettings.date(fromMinutes: minutes.wrappedValue) },
                set: { minutes.wrappedValue = ReminderSettings.minutes(from: $0) })
    }

    func remindersChanged(turnedOn: Bool) async {
        if turnedOn, !(await ReminderScheduler.shared.requestPermission()) {
            notificationsDenied = true
            writingReminder = false
            memoriesReminder = false
            return
        }
        notificationsDenied = false
        await ReminderScheduler.shared.reschedule(for: model)
    }

    // MARK: - On-device AI

    @ViewBuilder
    var intelligenceSection: some View {
        if model.me?.isPro == true, JournalIntelligence.isSupported {
            Section {
                Toggle("Apple Intelligence", isOn: $onDeviceAI)
            } header: {
                Text("On-Device AI")
            }
        }
    }

    // MARK: - Privacy

    @ViewBuilder
    var privacySection: some View {
        let lock = model.lock
        Section {
            Toggle("Require \(lock.methodName)", isOn: Binding(
                get: { lock.isEnabled },
                set: { enabled in
                    Task {
                        await lock.setEnabled(enabled)
                        WidgetSync.update(from: model) // the personal prompt leaves the widget while locked
                    }
                }
            ))
            .disabled(!lock.isAvailable)
            if model.me?.isPro == true {
                Toggle("On This Day in Widget", isOn: $widgetShowsMemories)
                    .onChange(of: widgetShowsMemories) { _, shows in WidgetSync.setShowsMemories(shows) }
            }
        } header: {
            Text("Privacy")
        }
    }

    func requestDeletion() async {
        do {
            deletionEmail = try await model.requestAccountDeletion()
        } catch {
            deletionError = error.localizedDescription
        }
    }
}

/// Explains PRO-only features. No purchase links: plans are managed on the web, and
/// App Store rules don't allow steering to outside purchases from inside the app.
struct ProInfoView: View {
    enum Feature {
        case writing, search, stats
    }

    let feature: Feature
    var showsDoneButton = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: feature == .writing ? "square.and.pencil" : feature == .stats ? "chart.bar" : "magnifyingglass")
            } description: {
                Text(message)
            }
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var title: String {
        switch feature {
        case .writing: "Writing in the app is a PRO feature"
        case .search: "Search is a PRO feature"
        case .stats: "Stats are a PRO feature"
        }
    }

    private var message: String {
        switch feature {
        case .writing:
            "You can always write for free by replying to your Dabble Me email. Your reply shows up here as an entry."
        case .search:
            "With Dabble Me PRO you can search every entry you've ever written."
        case .stats:
            "With Dabble Me PRO you can see your streaks, writing days, words and top hashtags."
        }
    }
}
