import SwiftUI

/// "Add a passkey": one tap to the system's passkey sheet, which saves a passkey for dabble.me
/// (iCloud Keychain, or the password manager picked). Shown after a password or email-code
/// sign-in (`PasskeyPrompt`), and from Settings → Add a Passkey.
/// Within a few minutes of signing in it needs nothing more; otherwise it asks for the password
/// first, as the web does (or an emailed code, on an account with no password).
struct PasskeyPromptSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Opened from Settings: its button says Cancel, and closing it isn't a "Not Now".
    var fromSettings = false
    @State private var password = ""
    @State private var adding = false
    @State private var error: String?
    @State private var added = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        // Scrolls (and can grow to full height) at the larger text sizes.
        ScrollView {
        VStack(spacing: 18) {
            Image(systemName: added ? "checkmark.circle.fill" : "person.badge.key.fill")
                .font(.system(size: 48))
                .foregroundStyle(added ? Color.green : Color.accentColor)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
                .padding(.top, 28)

            Text(added ? "Passkey added" : "Add a passkey")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Text(added
                 ? "Next time, sign in with Face ID or Touch ID. It works on dabble.me too."
                 : "Sign in with Face ID or Touch ID instead of your password, here and on dabble.me. A passkey can't be phished or leaked.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !added && model.addingPasskeyNeedsPassword {
                if model.confirmsWithEmailCode {
                    // No password on this account (made by email code): an emailed code instead.
                    EmailCodeConfirmField(code: $password, focused: $passwordFocused, onSubmit: add)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                } else {
                    PasswordField(title: "Your Dabble Me password", text: $password, focus: $passwordFocused, equals: true)
                        .submitLabel(.go)
                        .onSubmit(add)
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                }
            }

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            if added {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 16) {
                    Button(action: add) {
                        Group {
                            if adding { ProgressView() } else { Text("Add a Passkey") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(adding || (model.addingPasskeyNeedsPassword && password.isEmpty))

                    Button(fromSettings ? "Cancel" : "Not Now") { dismiss() }
                        .controlSize(.large)
                        .disabled(adding)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(adding)
    }

    private func add() {
        guard !adding else { return }
        adding = true
        error = nil
        passwordFocused = false
        Task {
            defer { adding = false }
            do {
                try await model.addPasskey(password: model.addingPasskeyNeedsPassword ? password : nil)
                withAnimation { added = true }
            } catch is CancellationError {
                // The system's sheet was closed: back here, nothing to say.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
