import SwiftUI

/// Settings → Account: who you are and how you sign in. Your name (changed here), your email,
/// Add a Passkey while the account has none, Account Security on dabble.me (password, passkeys,
/// two-factor), and Export Entries.
struct AccountSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var addingPasskey = false

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
        }
        .slabBackButton()
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        // On the list, not the row: the row goes once the passkey is added, and would take
        // the sheet (and its "Passkey added") with it.
        .sheet(isPresented: $addingPasskey) { PasskeyPromptSheet(fromSettings: true) }
    }
}
