import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingSignOut = false
    @State private var confirmingDeletion = false
    @State private var deletionEmail: String?
    @State private var deletionError: String?

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
