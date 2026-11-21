import SwiftUI

/// Which form the signed-out screens show: Sign In or Start Your Journal (sign up).
enum AuthFormMode: String, Identifiable {
    case signIn, signUp

    var id: String { rawValue }
}

/// The app's own sign-in and sign-up forms, in a sheet over the welcome screens. Email and
/// password (the App Review demo account signs in here), then the 2FA code when the account
/// has it. Passkeys go to dabble.me's sign-in page (`AppModel.signInOnWeb`).
///
/// Sign in with Apple, when it's added, goes at the top of both forms, above the fields, with
/// an "or" between: the fields and buttons below don't need to change for it.
struct AuthFormView: View {
    @State var mode: AuthFormMode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var firstName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    /// The server asked for the 2FA code: the code field shows, and the next submit sends it.
    @State private var needsCode = false
    @State private var isWorking = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case firstName, email, password, code
    }

    private var isSignUp: Bool { mode == .signUp }

    private var canSubmit: Bool {
        !isWorking && email.contains("@") && !password.isEmpty && (!needsCode || !code.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        Text(isSignUp ? "Start your journal" : "Welcome back")
                            .font(.custom("InstrumentSerif-Regular", size: 34))
                        Text(isSignUp ? "One entry a day, by email or right here." : "Sign in to your Dabble Me journal.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    if isSignUp {
                        TextField("First Name (optional)", text: $firstName)
                            .textContentType(.givenName)
                            .submitLabel(.next)
                            .focused($focus, equals: .firstName)
                            .onSubmit { focus = .email }
                    }
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                        .disabled(needsCode)
                    SecureField("Password", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .submitLabel(isSignUp || !needsCode ? .go : .next)
                        .focused($focus, equals: .password)
                        .onSubmit {
                            if needsCode { focus = .code } else { submit() }
                        }
                        .disabled(needsCode)
                } footer: {
                    if isSignUp {
                        Text("At least 6 characters.")
                    }
                }

                if needsCode {
                    Section {
                        TextField("Code", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.asciiCapableNumberPad)
                            .focused($focus, equals: .code)
                            .onSubmit(submit)
                    } header: {
                        Text("Two-Factor Code")
                    } footer: {
                        Text("From your authenticator app, or one of your recovery codes.")
                    }
                }

                Section {
                    Button(action: submit) {
                        Group {
                            if isWorking {
                                ProgressView()
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .filledButtonStyle()
                    .controlSize(.large)
                    .disabled(!canSubmit)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.deleteRed)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } footer: {
                    if isSignUp {
                        Text(Self.agreement)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                }

                Section {
                    if isSignUp {
                        Button("I Already Have an Account") { switchMode(to: .signIn) }
                    } else {
                        Button("Forgot Password?") { openURL(AppConfig.webURL("users/password/new")) }
                        Button("Sign In with a Passkey") {
                            dismiss()
                            Task { await model.signInOnWeb() }
                        }
                        Button("New to Dabble Me? Start Your Journal") { switchMode(to: .signUp) }
                    }
                }
                .frame(maxWidth: .infinity)
                .font(.subheadline)
                .disabled(isWorking)
            }
            .scrollContentBackground(.hidden)
            .background(Color("Paper").ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isWorking)
            .onAppear { focus = isSignUp ? .firstName : .email }
        }
    }

    /// Markdown links built from the server's address (a literal with interpolated URLs
    /// wouldn't be read as links).
    private static var agreement: AttributedString {
        let terms = AppConfig.webURL("terms").absoluteString
        let privacy = AppConfig.webURL("privacy").absoluteString
        return (try? AttributedString(markdown: "By creating an account you agree to the [Terms](\(terms)) and [Privacy Policy](\(privacy))."))
            ?? AttributedString("By creating an account you agree to the Terms and Privacy Policy.")
    }

    private func switchMode(to newMode: AuthFormMode) {
        withAnimation {
            mode = newMode
            needsCode = false
            code = ""
            error = nil
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isWorking = true
        error = nil
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isWorking = false }
            do {
                if isSignUp {
                    try await model.signUp(email: email, password: password, firstName: firstName)
                } else {
                    try await model.signIn(email: email, password: password, code: needsCode ? code : nil)
                }
                // Signed in: the welcome screens (and this sheet with them) give way to the journal.
            } catch NativeAuthError.needsCode {
                withAnimation { needsCode = true }
                focus = .code
            } catch {
                self.error = error.localizedDescription
                if needsCode { code = "" }
            }
        }
    }
}
