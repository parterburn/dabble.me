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
                // The page title, set like Today's date (the nav bar shows none).
                Text("Settings")
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))
                if let me = model.me {
                    Section("Account") {
                        LabeledContent("Email", value: me.email)
                        if canLinkToSubscribe {
                            Link(destination: AppConfig.webURL("subscribe")) {
                                LabeledContent("Plan") {
                                    HStack(spacing: 8) {
                                        Text(me.isPro ? "PRO" : "Free")
                                        ExternalLinkIcon()
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
                        WidgetSettingsView()
                    } label: {
                        Label {
                            Text("Home Screen Widget")
                        } icon: {
                            // No Slab widget icon: an SF Symbol, sized like the Slab ones.
                            Image(systemName: "widget.small")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                        }
                    }
                    NavigationLink {
                        AccessibilitySettingsView()
                    } label: {
                        LabeledContent {
                            Text("\(textSize.label), \(fontStyle.label)")
                        } label: {
                            Label("Accessibility", icon: "slab-universal-access")
                        }
                    }
                }

                Section {
                    // Connecting happens on the web (OAuth on dabble.me, PRO plus a passkey or 2FA);
                    // the guide links to Claude's and ChatGPT's directories.
                    if let connectors = model.me?.aiConnectors {
                        Link(destination: connectors.guideUrl) {
                            ExternalLinkLabel("Claude/ChatGPT Connector", icon: "slab-claude")
                        }
                    }
                    Link(destination: model.me?.securityUrl ?? AppConfig.webURL("security")) {
                        ExternalLinkLabel("Account Security", icon: "slab-shield")
                    }
                    Link(destination: URL(string: "#export", relativeTo: AppConfig.webURL("users/edit"))!.absoluteURL) {
                        ExternalLinkLabel("Export Entries", icon: "slab-arrow-up-from-line")
                    }
                } header: {
                    Text("On dabble.me")
                }

                Section {
                    Link(destination: AppConfig.webURL("support")) {
                        ExternalLinkLabel("Help & Support", icon: "slab-circle-question")
                    }
                    Link(destination: AppConfig.webURL("privacy")) {
                        ExternalLinkLabel("Privacy Policy", icon: "slab-hand")
                    }
                    Link(destination: AppConfig.webURL("terms")) {
                        ExternalLinkLabel("Terms", icon: "slab-anchor")
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
            .toolbar(removing: .title) // the heading in the list is the title
            .toolbarVisibility(.hidden, for: .navigationBar) // like Today: no empty bar above it
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
    // MARK: - Reminders (writing: everyone; On This Day: PRO)

    @ViewBuilder
    var remindersSection: some View {
        let isPro = model.me?.isPro == true
        Section {
            do {
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
                // On This Day is PRO, so its reminder is too (greyed out on a free plan).
                Toggle("On This Day Memories", isOn: $memoriesReminder)
                    .disabled(!isPro)
                if memoriesReminder, isPro {
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
        } footer: {
            if !isPro {
                Text("On This Day reminders and choosing your email's days are part of Dabble Me PRO.")
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
        if JournalIntelligence.isSupported {
            Section {
                // The sparkles mean on-device Apple Intelligence wherever they appear in the app.
                Toggle(isOn: $onDeviceAI) {
                    Label("Apple Intelligence", icon: "slab-sparkles")
                }
            } header: {
                Text("On-Device AI")
            } footer: {
                Text("Reflections on your entries, a daily writing prompt from your recent days, and hashtag suggestions as you write. They run on this device with Apple Intelligence; your journal isn't sent anywhere for them.")
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
                        WidgetSync.update(from: model)
                    }
                }
            ))
            .disabled(!lock.isAvailable)
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

/// A Settings row that opens dabble.me (or another site) in the browser: its label, and a light
/// grey "opens outside" arrow at the far right.
private struct ExternalLinkLabel: View {
    let title: String
    let icon: String

    init(_ title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack {
            Label(title, icon: icon)
            Spacer()
            ExternalLinkIcon()
        }
    }
}

private struct ExternalLinkIcon: View {
    var body: some View {
        appIcon("slab-external-link")
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}
