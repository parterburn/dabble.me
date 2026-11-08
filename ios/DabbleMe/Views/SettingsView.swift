import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var confirmingSignOut = false
    @State private var confirmingDeletion = false
    @State private var deletionEmail: String?
    @State private var deletionError: String?
    @AppStorage(ReadingTextSize.storageKey) private var textSize = ReadingTextSize.standard
    @AppStorage(ReminderSettings.writingEnabledKey) private var writingReminder = false
    @AppStorage(ReminderSettings.writingTimeKey) private var writingTime = ReminderSettings.defaultWritingTime
    @AppStorage(ReminderSettings.memoriesEnabledKey) private var memoriesReminder = false
    @AppStorage(ReminderSettings.memoriesTimeKey) private var memoriesTime = ReminderSettings.defaultMemoriesTime
    @State private var notificationsDenied = false
    @AppStorage(WidgetSnapshot.showMemoriesKey, store: WidgetSnapshot.defaults) private var widgetShowsMemories = false
    @AppStorage(JournalIntelligence.enabledKey) private var onDeviceAI = true
    #if DEBUG
    @State private var pendingReminders = 0
    #endif
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 17

    var body: some View {
        NavigationStack {
            List {
                if let me = model.me {
                    Section("Account") {
                        LabeledContent("Email", value: me.email)
                        LabeledContent("Plan", value: me.isPro ? "PRO" : "Free")
                        LabeledContent("Entries", value: me.entryCount.formatted())
                    }
                }

                Section {
                    Picker("Entry Text Size", selection: $textSize) {
                        ForEach(ReadingTextSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    Text("How was your day? A little preview of how entries will read.")
                        .font(.system(size: bodySize * textSize.scale, design: .serif))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Changes the text size when reading entries. It adds to your iPhone's own text size setting.")
                }

                remindersSection
                intelligenceSection
                privacySection

                if let connectors = model.me?.aiConnectors {
                    aiSection(connectors)
                }

                Section {
                    Link(destination: model.me?.settingsUrl ?? AppConfig.webURL("settings")) {
                        Label("Email Schedule & Preferences", systemImage: "envelope.badge")
                    }
                    Link(destination: model.me?.securityUrl ?? AppConfig.webURL("security")) {
                        Label("Passkeys & Two-Factor", systemImage: "lock.shield")
                    }
                } header: {
                    Text("On dabble.me")
                } footer: {
                    Text("Choose which days and what time your \u{201C}How was your day?\u{201D} email arrives.")
                }

                Section {
                    Link(destination: AppConfig.webURL("support")) {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }
                    Link(destination: AppConfig.webURL("privacy")) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    Link(destination: AppConfig.webURL("terms")) {
                        Label("Terms", systemImage: "doc.text")
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) { confirmingSignOut = true }
                    Button("Delete Account…", role: .destructive) { confirmingDeletion = true }
                } footer: {
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text("Dabble Me for iOS \(version)")
                    }
                }
            }
            .navigationTitle("Settings")
            .task { notificationsDenied = await ReminderScheduler.shared.isDenied() }
            .onChange(of: writingReminder) { _, on in Task { await remindersChanged(turnedOn: on) } }
            .onChange(of: memoriesReminder) { _, on in Task { await remindersChanged(turnedOn: on) } }
            .onChange(of: writingTime) { Task { await ReminderScheduler.shared.reschedule(for: model) } }
            .onChange(of: memoriesTime) { Task { await ReminderScheduler.shared.reschedule(for: model) } }
            .confirmationDialog("Sign out of Dabble Me?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { Task { await model.signOut() } }
            }
            // Deleting takes three deliberate steps: confirm here, open the emailed link, then
            // confirm with your password on dabble.me (and it can still be undone for an hour).
            .confirmationDialog("Delete your Dabble Me account?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("Email Me a Deletion Link", role: .destructive) { Task { await requestDeletion() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("We'll email you a link to finish on dabble.me, where you'll confirm with your password. You can export your entries there first.")
            }
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
            } else {
                Toggle("Daily Writing Reminder", isOn: $writingReminder)
                if writingReminder {
                    DatePicker("Time", selection: minutesBinding($writingTime), displayedComponents: .hourAndMinute)
                }
                Toggle("On This Day Memories", isOn: $memoriesReminder)
                if memoriesReminder {
                    DatePicker("Time", selection: minutesBinding($memoriesTime), displayedComponents: .hourAndMinute)
                }
                #if DEBUG
                Text("\(pendingReminders) reminders scheduled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .task(id: "\(writingReminder)\(memoriesReminder)\(writingTime)\(memoriesTime)") {
                        try? await Task.sleep(for: .seconds(2))
                        pendingReminders = await ReminderScheduler.shared.pendingCount()
                    }
                #endif
                if notificationsDenied {
                    Button("Turn On Notifications in Settings", systemImage: "bell.slash") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            if model.me?.isPro == true {
                Text("Writing reminders skip days you've already written. Memory reminders only come on days you have entries from past years. Notifications never show what you wrote.")
            }
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
            } footer: {
                Text("Hashtag suggestions while you write, entry summaries, and prompts from your recent entries. It all runs on this device; your journal isn't sent anywhere for it.")
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
                set: { enabled in Task { await lock.setEnabled(enabled) } }
            ))
            .disabled(!lock.isAvailable)
            if model.me?.isPro == true {
                Toggle("On This Day in Widget", isOn: $widgetShowsMemories)
                    .onChange(of: widgetShowsMemories) { _, shows in WidgetSync.setShowsMemories(shows) }
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text((lock.isAvailable
                  ? "Locks Dabble Me when you open it and after a minute away. Your journal is hidden in the app switcher."
                  : "Set a passcode on this device to lock Dabble Me.")
                 + " The home-screen widget shows your streak and never what you wrote"
                 + (model.me?.isPro == true ? "; it can also say how many memories you have from this day." : "."))
        }
    }

    /// Links to the Dabble Me plugins in Claude's and ChatGPT's directories. Connecting happens
    /// there (OAuth on dabble.me); it needs PRO plus a passkey or two-factor sign-in.
    @ViewBuilder
    func aiSection(_ connectors: Me.AIConnectors) -> some View {
        Section {
            if connectors.requiresPro {
                Label("Connecting Claude or ChatGPT is part of Dabble Me PRO.", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
            } else {
                if connectors.requiresSecuritySetup {
                    Link(destination: model.me?.securityUrl ?? AppConfig.webURL("security")) {
                        Label("Set Up a Passkey First", systemImage: "person.badge.key")
                    }
                }
                Link(destination: connectors.claudeUrl) {
                    Label("Connect to Claude", systemImage: "sparkles")
                }
                Link(destination: connectors.chatgptUrl) {
                    Label("Connect to ChatGPT", systemImage: "bubble.left.and.text.bubble.right")
                }
                Link(destination: connectors.guideUrl) {
                    Label("How It Works", systemImage: "info.circle")
                }
            }
        } header: {
            Text("Ask AI About Your Journal")
        } footer: {
            if connectors.requiresPro {
                EmptyView()
            } else if connectors.requiresSecuritySetup {
                Text("To keep your journal safe, connecting an AI assistant needs a passkey or two-factor sign-in on your account.")
            } else {
                Text("Ask questions about your entries, rediscover old memories, or save a new entry from a chat. You approve access on dabble.me and can remove it any time under Passkeys & Two-Factor → Connected Apps.")
            }
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
        case writing, search
    }

    let feature: Feature
    var showsDoneButton = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: feature == .writing ? "square.and.pencil" : "magnifyingglass")
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
        feature == .writing ? "Writing in the app is a PRO feature" : "Search is a PRO feature"
    }

    private var message: String {
        switch feature {
        case .writing:
            "You can always write for free by replying to your Dabble Me email. Your reply shows up here as an entry."
        case .search:
            "With Dabble Me PRO you can search every entry you've ever written. Everything else in the app is free."
        }
    }
}
