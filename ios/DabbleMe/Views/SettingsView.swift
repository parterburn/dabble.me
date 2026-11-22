import StoreKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(ShakeSetting.storageKey) private var shakeForRandomEntry = true
    @Environment(\.openURL) private var openURL
    @State private var confirmingSignOut = false
    @State private var deletingAccount = false
    @State private var addingPasskey = false
    @AppStorage(AppTheme.storageKey) private var theme = AppTheme.system
    @AppStorage(ReminderSettings.enabledKey) private var dailyReminder = false
    /// The time set for it, or `followsEmail` until one is: then it's the daily email's.
    @AppStorage(ReminderSettings.timeKey) private var reminderTime = ReminderSettings.followsEmail
    @AppStorage(ReminderSettings.emailTimeKey) private var emailTime = ReminderSettings.defaultTime
    @AppStorage(ReminderSettings.daysKey) private var reminderDays = EmailSchedule.allDays.joined(separator: ",")
    /// The account's email schedule and past-entry choices, shared by the Reminders rows.
    @State private var emailSchedule = EmailScheduleStore()
    @AppStorage(JournalIntelligence.enabledKey) private var onDeviceAI = true
    @AppStorage(DictationSettings.enabledKey) private var dictationEnabled = true
    @AppStorage(DictationSettings.styleKey) private var dictationStyle = DictationStyle.polished
    /// With an older server (no in-app purchase), the plan links to dabble.me/subscribe only on
    /// the US App Store, where Apple allows links to buy outside the app (guideline 3.1.1(a), US
    /// storefront). Otherwise the Plan row opens PlanView, which sells PRO in the app.
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
                        // Your name, changed here and saved to the account.
                        PaneLink {
                            NameSettingsView()
                        } label: {
                            LabeledContent("Name", value: me.name ?? me.firstName ?? "Add your name")
                        }
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
                        // Until the account has one (managed, and removed, on Account Security).
                        if me.hasPasskey == false {
                            Button {
                                addingPasskey = true
                            } label: {
                                Label("Add a Passkey", icon: "slab-lock")
                            }
                            .foregroundStyle(.primary)
                        }
                        if me.appleAccountToken != nil {
                            // The plan, and PRO bought here (or managed, when it was bought here).
                            PaneLink {
                                PlanView()
                            } label: {
                                LabeledContent("Plan", value: me.isPro ? "PRO" : "Free")
                            }
                        } else if canLinkToSubscribe {
                            // An older server, which can't take an in-app purchase.
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
                        PaneLink {
                            TagDatesView()
                        } label: {
                            Label("Manage Hashtags", icon: "slab-tag")
                        }
                        .disabled(!me.isPro)
                        // Emailed, as the web's Export page does, with no sign-in to the web first.
                        // Black words like the rows around it, and an olive icon like theirs
                        // (a button would tint both; .primary on the whole row greyed the icon).
                        ExportEntriesButton {
                            Label {
                                Text("Export Entries").foregroundStyle(.primary)
                            } icon: {
                                appIcon("slab-arrow-up-from-line").foregroundStyle(.tint)
                            }
                        }
                    }
                }

                remindersSection
                intelligenceSection

                Section("App") {
                    // What an entry can start from: added from the composer's lightbulb or to every new one.
                    PaneLink {
                        EntryTemplateView()
                    } label: {
                        Label("Entry Template", icon: "slab-equals")
                    }
                    // The composer's microphone: on or off, Polished or Verbatim, and words to expect.
                    if Dictation.isSupported {
                        PaneLink {
                            DictationSettingsView()
                        } label: {
                            LabeledContent {
                                Text(dictationEnabled ? dictationStyle.label : "Off")
                            } label: {
                                Label("Dictation", icon: "slab-microphone")
                            }
                        }
                    }
                    // Which calendars the composer's lightbulb lists the day's events from.
                    PaneLink {
                        CalendarSettingsView()
                    } label: {
                        Label("Calendars", icon: "slab-calendar")
                    }
                    PaneLink {
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
                    lockToggle
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
                    // Deleting happens here: the password, then one last confirmation, in a sheet.
                    Button("Delete Account…", role: .destructive) { deletingAccount = true }
                        .sheet(isPresented: $deletingAccount) {
                            DeleteAccountView()
                                .opensDabbleLinksInApp()
                        }
                } footer: {
                    // The app's name and version, centered at the foot: a tap goes to its page.
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                       let page = URL(string: "https://dabble.me/journal-app") {
                        Button { openURL(page) } label: {
                            Text("Dabble Me for iOS \(version)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                                .padding(.bottom, 28)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the app's page on dabble.me")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title) // the heading in the list is the title
            .toolbarVisibility(.hidden, for: .navigationBar) // like Today: no empty bar above it
            .task { canLinkToSubscribe = await Storefront.current?.countryCode == "USA" }
            // On the list, not the row: the row goes once the passkey is added, and would take
            // the sheet (and its "Passkey added") with it.
            .sheet(isPresented: $addingPasskey) { PasskeyPromptSheet(fromSettings: true) }
        }
        // A name save that failed, from the Name page (on Done or on going Back). On the stack,
        // so it shows over the Name page too.
        .alert("Couldn't save your name", isPresented: Binding(
            get: { model.nameSaveError != nil },
            set: { if !$0 { model.nameSaveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.nameSaveError ?? "")
        }
    }
}

private extension SettingsView {
    // MARK: - Reminders (each on a page of its own)

    @ViewBuilder
    var remindersSection: some View {
        Section {
            // Each kind on a page of its own; then what any of them can look back on.
            PaneLink {
                PushReminderView(emailShowsPastEntry: emailSchedule.schedule?.includePastEntries ?? true)
            } label: {
                LabeledContent("Push", value: ReminderSettings.summary(enabled: dailyReminder, days: ReminderSettings.days(from: reminderDays),
                                                                       minutes: reminderTime >= 0 ? reminderTime : emailTime))
            }
            // The widget's a nudge to write too, and its look backs are the reminders' own.
            PaneLink {
                WidgetSettingsView()
            } label: {
                let _ = model.widgetChoiceChanges // redrawn when the choice changes
                LabeledContent("Home Screen Widget", value: WidgetSnapshot.content.source.title)
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

    // MARK: - Lock

    /// Face ID (or Touch ID) to open the app: the last of the App rows.
    private var lockToggle: some View {
        let lock = model.lock
        return Toggle(isOn: Binding(
            get: { lock.isEnabled },
            set: { enabled in
                Task {
                    await lock.setEnabled(enabled)
                    WidgetSync.update(from: model)
                }
            }
        )) {
            Label("Require \(lock.methodName)", icon: "slab-lock")
        }
        .disabled(!lock.isAvailable)
    }
}

/// Explains PRO-only features, with the in-app purchase under it for a Free account
/// (SubscribeOptions; nothing is linked to buy outside the app here).
struct ProInfoView: View {
    enum Feature {
        case writing, search, stats, photos
    }

    let feature: Feature
    var showsDoneButton = true
    /// In its season, Stats' page names the year's Rewind too: Today's corner leads here for
    /// everyone, and a free account should know there'd be one.
    var rewindYear: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(message)
            } actions: {
                SubscribeOptions()
            }
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        // Tall enough for the plans and their terms when there's something to buy.
        .presentationDetents(model.me?.isPro == false && model.me?.sellsInApp == true ? [.large] : [.medium])
    }

    private var icon: String {
        switch feature {
        case .writing: "square.and.pencil"
        case .search: "magnifyingglass"
        case .stats: "chart.bar"
        case .photos: "photo.on.rectangle"
        }
    }

    private var title: String {
        switch feature {
        case .photos: "Photos are a PRO feature"
        case .writing: "Writing in the app is a PRO feature"
        case .search: "Search is a PRO feature"
        case .stats: rewindYear.map { "\(String($0)) Rewind and Stats are PRO features" } ?? "Stats are a PRO feature"
        }
    }

    private var message: String {
        switch feature {
        case .photos:
            "With Dabble Me PRO you can add up to \(AppModel.maxPhotos) photos to an entry."
        case .writing:
            "You can always write for free by replying to your Dabble Me email. Your reply shows up here as an entry."
        case .search:
            "With Dabble Me PRO you can search every entry you've ever written."
        case .stats:
            if let rewindYear {
                "With Dabble Me PRO you get your \(String(rewindYear)) Rewind, a look back on the year you wrote down, along with your streaks, writing days, words and top hashtags."
            } else {
                "With Dabble Me PRO you can see your streaks, writing days, words and top hashtags."
            }
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
