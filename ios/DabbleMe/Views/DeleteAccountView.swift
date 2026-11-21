import SwiftUI

/// Settings → Delete Account, all in the app (App Store guideline 5.1.1(v)): what goes, an
/// export first, billing to cancel elsewhere, the password (or one of the account's passkeys),
/// then one last confirmation. The
/// server deletes the account an hour later (`DeleteUserJob`, which cancels a Stripe
/// subscription), unless the person signs back in before then.
struct DeleteAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var info: AccountDeletionInfo?
    @State private var loadError: String?
    @State private var password = ""
    @State private var confirming = false
    /// The last confirmation, before the passkey sheet (in place of the password).
    @State private var confirmingWithPasskey = false
    @State private var isDeleting = false
    @State private var error: String?
    @FocusState private var passwordFocused: Bool

    private var entries: String {
        let count = info?.entryCount ?? 0
        return count == 1 ? "1 entry" : "\(count.formatted()) entries"
    }

    var body: some View {
        NavigationStack {
            Form {
                if let info {
                    Section {
                        Text("This deletes your account and all \(entries), with their photos, for good.")
                        Text("It happens an hour after you confirm. Signing back in before then keeps your account.")
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        ExportEntriesButton { Text("Email Me an Export") }
                    } footer: {
                        Text("We'll email you a link to your entries. Download it before you delete: exports are deleted along with everything else.")
                    }

                    if let billing = info.separateBilling {
                        Section {
                            Label {
                                Text("You \(billing.certain ? "will" : "may") need to cancel your PRO subscription at \(billing.provider) yourself if billing is active there.")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                        }
                    }

                    Section {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($passwordFocused)
                            .submitLabel(.done)
                            .onSubmit { if !password.isEmpty { confirming = true } }
                    } header: {
                        Text("Confirm with Your Password")
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            if let error {
                                Text(error).foregroundStyle(Color.deleteRed)
                            }
                            // Someone who signs in with a passkey may not know the password.
                            Button("Confirm with a Passkey Instead") { confirmingWithPasskey = true }
                                .font(.footnote)
                                .disabled(isDeleting)
                                .confirmationDialog("Delete your account and \(entries)?", isPresented: $confirmingWithPasskey, titleVisibility: .visible) {
                                    Button("Continue with Passkey", role: .destructive) { deleteWithPasskey() }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text("Confirm with your passkey next. You'll be signed out. After an hour this can't be undone.")
                                }
                        }
                    }

                    Section {
                        Button(role: .destructive) { confirming = true } label: {
                            Group {
                                if isDeleting {
                                    ProgressView()
                                } else {
                                    Text("Delete Account")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(password.isEmpty || isDeleting)
                        .confirmationDialog("Delete your account and \(entries)?", isPresented: $confirming, titleVisibility: .visible) {
                            Button("Delete Account", role: .destructive) { delete() }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("You'll be signed out. After an hour this can't be undone.")
                        }
                    }
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't Load", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try Again") { Task { await load() } }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isDeleting)
                }
            }
            .interactiveDismissDisabled(isDeleting)
            .task { await load() }
        }
    }

    private func load() async {
        loadError = nil
        do {
            info = try await model.accountDeletionInfo()
        } catch is CancellationError {
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func deleteWithPasskey() {
        isDeleting = true
        error = nil
        Task {
            defer { isDeleting = false }
            do {
                try await model.deleteAccountWithPasskey()
            } catch is CancellationError {
                // The passkey sheet was closed: nothing deleted, nothing to say.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func delete() {
        isDeleting = true
        error = nil
        Task {
            defer { isDeleting = false }
            do {
                // Signs the app out: the welcome screen (this sheet goes with Settings) says when.
                try await model.deleteAccount(password: password)
            } catch {
                self.error = error.localizedDescription
                password = ""
                passwordFocused = true
            }
        }
    }
}
