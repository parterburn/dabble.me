import StoreKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(ShakeSetting.storageKey) private var shakeForRandomEntry = true
    @Environment(\.openURL) private var openURL
    @State private var confirmingSignOut = false
    @State private var confirmingDeletion = false
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.system
    @AppStorage(ReminderSettings.enabledKey) private var dailyReminder = false
    /// The time set for it, or `followsEmail` until one is: then it's the daily email's.
    @AppStorage(ReminderSettings.timeKey) private var reminderTime = ReminderSettings.followsEmail
    @AppStorage(ReminderSettings.emailTimeKey) private var emailTime = ReminderSettings.defaultTime
    @AppStorage(ReminderSettings.daysKey) private var reminderDays = EmailSchedule.allDays.joined(separator: ",")
    /// The account's email schedule and past-entry choices, shared by the Reminders rows.
    @State private var emailSchedule = EmailScheduleStore()
    @AppStorage(JournalIntelligence.enabledKey) private var onDeviceAI = true
    /// The plan links to dabble.me/subscribe only on the US App Store, where Apple allows links to
    /// buy outside the app (guideline 3.1.1(a), US storefront). Elsewhere it's plain text.
    @State private var canLinkToSubscribe = false

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
                        // Your name opens Settings on dabble.me, where it's changed.
                        Link(destination: me.settingsUrl) {
                            LabeledContent("Name") {
                                HStack(spacing: 8) {
                                    Text(me.name ?? me.firstName ?? "Add your name")
                                        .foregroundStyle((me.name ?? me.firstName) == nil ? .secondary : .primary)
                                    ExternalLinkIcon()
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityHint("Opens your settings on dabble.me")
                        // Your email opens Account Security on dabble.me (password, passkeys, 2FA).
                        Link(destination: me.securityUrl) {
                            LabeledContent("Email") {
                                HStack(spacing: 8) {
                                    Text(me.email)
                                    ExternalLinkIcon()
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityHint("Opens Account Security on dabble.me")
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
                            Text(theme.label)
                        } label: {
                            Label("Theme", icon: "slab-universal-access")
                        }
                    }
                    // Shaking the phone brings up a random entry; off for anyone it surprises.
                    Toggle(isOn: $shakeForRandomEntry) {
                        Label("Shake for Random Entry", icon: "slab-dice")
                    }
                }

                Section {
                    // Connecting happens on the web (OAuth on dabble.me, PRO only);
                    // the guide links to Claude's and ChatGPT's directories.
                    if let connectors = model.me?.aiConnectors {
                        Link(destination: connectors.guideUrl) {
                            ExternalLinkLabel("Claude/ChatGPT Connector", icon: "slab-claude")
                        }
                    }
                    Link(destination: model.me?.securityUrl ?? AppConfig.webURL("security")) {
                        ExternalLinkLabel("Account Security", icon: "slab-shield")
                    }
                    Link(destination: AppConfig.webURL("entries/export")) {
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
                    // Deleting finishes on dabble.me (signed in there, confirmed with the password, and
                    // it can still be undone for an hour), so this says what's about to happen, signs
                    // the app out and hands over to the browser.
                    Button(role: .destructive) { confirmingDeletion = true } label: {
                        HStack {
                            Text("Delete Account…")
                            Spacer()
                            ExternalLinkIcon()
                        }
                    }
                    .confirmationDialog("Delete your Dabble Me account?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                        Button("Sign Out and Continue", role: .destructive) { Task { await continueDeletionInBrowser() } }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("You'll be signed out of the app, and your browser will open dabble.me, where you finish deleting your account with your password. You can export your entries there first.")
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
            .task { canLinkToSubscribe = await Storefront.current?.countryCode == "USA" }
        }
    }
}

private extension SettingsView {
    // MARK: - Reminders (each on a page of its own)

    @ViewBuilder
    var remindersSection: some View {
        Section {
            // Each kind on a page of its own; then what either can look back on.
            NavigationLink {
                PushReminderView()
            } label: {
                LabeledContent("Push", value: ReminderSettings.summary(enabled: dailyReminder, days: ReminderSettings.days(from: reminderDays),
                                                                       minutes: reminderTime >= 0 ? reminderTime : emailTime))
            }
            EmailScheduleRow(store: emailSchedule)
            PastEntriesRow(store: emailSchedule)
        } header: {
            Text("Reminders")
        }
        .task { await emailSchedule.load(with: model) }
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

    /// The browser itself, not the page inside the app: that one's signed out along with the app.
    func continueDeletionInBrowser() async {
        await model.signOut()
        await UIApplication.shared.open(AppConfig.webURL("settings/delete-account"))
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
struct ExternalLinkLabel: View {
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

struct ExternalLinkIcon: View {
    var body: some View {
        appIcon("slab-external-link")
            .resizable()
            .scaledToFit()
            .frame(width: 14, height: 14)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}
