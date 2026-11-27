import SwiftUI

/// Settings → Account: who you are and how you sign in. Your name (changed here), your email,
/// Add a Passkey while the account has none, Account Security on dabble.me (password, passkeys,
/// two-factor), Export Entries, Sign Out (this device, or every device) and Delete Account.
struct AccountSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var addingPasskey = false
    @State private var confirmingSignOut = false
    @State private var deletingAccount = false

    var body: some View {
        List {
            if let me = model.me {
                Section {
                    // Your name, changed here and saved to the account.
                    PaneLink {
                        NameSettingsView()
                    } label: {
                        LabeledContent("Name", value: me.name ?? me.firstName ?? "Add your name")
                    }
                    // Changed on Account Security, the row below.
                    LabeledContent("Email", value: me.email)
                }

                Section {
                    // Until the account has one (managed, and removed, on Account Security).
                    // Black words and an olive icon, like the rows around it (a button tints
                    // both; .primary on the whole row greys the icon).
                    if me.hasPasskey == false {
                        Button {
                            addingPasskey = true
                        } label: {
                            Label {
                                Text("Add a Passkey").foregroundStyle(.primary)
                            } icon: {
                                appIcon("slab-lock").foregroundStyle(.tint)
                            }
                        }
                    }
                    Link(destination: me.securityUrl) {
                        ExternalLinkLabel("Account Security", icon: "slab-shield")
                    }
                    .accessibilityHint("Opens Account Security on dabble.me")
                } footer: {
                    Text("Your email, password, passkeys and two-factor sign-in are managed on dabble.me.")
                }

                Section {
                    // Emailed, as the web's Export page does, with no sign-in to the web first.
                    ExportEntriesButton {
                        Label {
                            Text("Export Entries").foregroundStyle(.primary)
                        } icon: {
                            appIcon("slab-arrow-up-from-line").foregroundStyle(.tint)
                        }
                    }
                }
            }

            Section {
                // Each dialog is attached to its button so it appears next to it, not at the top.
                Button("Sign Out", role: .destructive) { confirmingSignOut = true }
                    .confirmationDialog("Sign out of Dabble Me?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) { Task { await model.signOut() } }
                        // Every browser and app on the account, this one included.
                        Button("Sign Out of All Devices", role: .destructive) { Task { await model.signOutEverywhere() } }
                    } message: {
                        Text("Sign Out signs out this device only. Sign Out of All Devices signs out every browser and app signed in to your account, and disconnects connected apps like Claude.")
                    }
                // Deleting happens here (App Review guideline 5.1.1(v)): what goes, an export,
                // the password, then one last confirmation, in a sheet.
                Button("Delete Account…", role: .destructive) { deletingAccount = true }
                    .sheet(isPresented: $deletingAccount) {
                        DeleteAccountView()
                            .opensDabbleLinksInApp()
                    }
            }
        }
        .slabBackButton()
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        // On the list, not the row: the row goes once the passkey is added, and would take
        // the sheet (and its "Passkey added") with it.
        .sheet(isPresented: $addingPasskey) { PasskeyPromptSheet(fromSettings: true) }
    }
}
