import SwiftUI

/// Which copy the signed-out form shows: Sign In or Start Your Journal (sign up). Both take the
/// same steps: an email, then the code emailed to it.
enum AuthFormMode: String, Identifiable {
    case signIn, signUp

    var id: String { rawValue }
}

/// The app's own sign-in and sign-up, in a sheet over the welcome screens. Passwordless:
///
/// 1. An email. The field offers the account's passkeys above the keyboard (`AppModel.passkeyAutoFill`),
///    and on sign-in the "Sign In with a Passkey" link under Continue opens the system's sheet:
///    either signs straight in. A mistyped common domain gets a "Did you mean …?" (`EmailTypo`).
///    The main buttons always look ready: tapped too soon, they say what's missing under the
///    field and put the cursor there, rather than sitting greyed out.
/// 2. Continue always emails a six-digit code and shows the code screen, with or without an
///    account at that address (the server never says which). An unknown address becomes an
///    account once its code is entered, so a typo leaves nothing behind: the screen shows where
///    the code went, with "Wrong email? Change It" and "Send a New Code". The code fills from
///    the email above the keyboard (one-time-code), and goes as soon as six digits are in.
///    "Use Password Instead" signs in the old way (the App Review demo account does). Either
///    way, an account with 2FA then asks for its authenticator code.
///
/// Sign in with Apple, when it's added, goes at the top of the email step, with an "or" between.
struct AuthFormView: View {
    @State var mode: AuthFormMode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private enum Step { case email, code }

    @State private var step: Step = .email
    @State private var email = ""
    /// Where the code went, as the server has it.
    @State private var sentTo = ""
    @State private var emailCode = ""
    @State private var password = ""
    @State private var otpCode = ""
    /// "Use Password Instead": the password field shows, and the main button signs in with it.
    @State private var usesPassword = false
    /// The server asked for the 2FA code: the field shows, and the next submit sends it.
    @State private var needsOTP = false
    /// The typo suggestion was shown for this address, so Continue goes ahead the second time.
    @State private var typoShownFor: String?
    @State private var isWorking = false
    @State private var error: String?
    @State private var notice: String?
    /// What to fill in first, from a main button tapped too soon. Shown under that field.
    @State private var hint: String?
    @State private var autoFill: Task<Void, Never>?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case email, code, password, otp
    }

    private var isSignUp: Bool { mode == .signUp }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var codeDigits: String { emailCode.filter(\.isNumber) }

    private var hasEmail: Bool { trimmedEmail.contains("@") }

    /// What the email step still needs before Continue can go, if anything.
    private var emailHint: String? {
        if trimmedEmail.isEmpty { return "Enter your email first, and we'll send you a code." }
        if !hasEmail { return "That doesn't look like an email address yet." }
        return nil
    }

    /// What the code step still needs, and the field to put the cursor in.
    private var codeHint: (text: String, field: Field)? {
        if usesPassword && password.isEmpty { return ("Enter your password first.", .password) }
        if !usesPassword && codeDigits.count != 6 { return ("Enter the 6-digit code from your email.", .code) }
        if needsOTP && otpCode.isEmpty { return ("Enter your two-factor code.", .otp) }
        return nil
    }


    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        Text(title)
                            .font(.custom("InstrumentSerif-Regular", size: 34))
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                switch step {
                case .email: emailStep
                case .code: codeStep
                }
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
            .onAppear {
                focus = .email
                startAutoFill()
            }
            .onDisappear { stopAutoFill() }
        }
    }

    private var title: String {
        switch step {
        case .email: isSignUp ? "Start your journal" : "Welcome back"
        case .code: "Check your email"
        }
    }

    private var subtitle: String {
        switch step {
        case .email: isSignUp ? "One entry a day, by email or right here." : "Sign in to your Dabble Me journal."
        case .code: "We sent a 6-digit code to"
        }
    }

    // MARK: - Email

    @ViewBuilder private var emailStep: some View {
        Section {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .focused($focus, equals: .email)
                .onSubmit(continueWithEmail)
                .onChange(of: email) {
                    typoShownFor = nil
                    hint = nil
                }
        } footer: {
            if let hint {
                hintText(hint)
            } else if let suggestion = shownSuggestion {
                Button {
                    email = suggestion
                    typoShownFor = nil
                } label: {
                    Text("Did you mean **\(suggestion)**?")
                }
                .font(.footnote)
            } else {
                Text("We'll email you a 6-digit code. No password needed.")
            }
        }

        Section {
            Button(action: continueWithEmail) {
                Group {
                    if isWorking { ProgressView() } else { Text("Continue") }
                }
                .frame(maxWidth: .infinity, minHeight: 30)
            }
            .filledButtonStyle()
            .controlSize(.large)
            .disabled(isWorking)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            // Sign-in only: a passkey can't start an account. A returning writer on sign-up still
            // gets their passkey offered above the keyboard (autofill) and "I Already Have an Account".
            if !isSignUp { passkeyLink }

            errorRow
        } footer: {
            Text(Self.agreement)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }

        Section {
            if isSignUp {
                Button("I Already Have an Account") { switchMode(to: .signIn) }
            } else {
                Button("New to Dabble Me? Start Your Journal") { switchMode(to: .signUp) }
            }
        }
        .frame(maxWidth: .infinity)
        .font(.subheadline)
        .disabled(isWorking)
    }

    /// Shown once the field is left, or after a Continue that stopped for it.
    private var shownSuggestion: String? {
        guard focus != .email || typoShownFor == trimmedEmail else { return nil }
        return EmailTypo.suggestion(for: trimmedEmail)
    }

    // MARK: - Code

    @ViewBuilder private var codeStep: some View {
        Section {
            VStack(spacing: 8) {
                Text(sentTo)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Button("Wrong email? Change It", action: changeEmail)
                    .font(.subheadline)
                    .disabled(isWorking)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }

        if !usesPassword {
            Section {
                TextField("6-digit code", text: $emailCode)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(.title2.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .focused($focus, equals: .code)
                    .onChange(of: emailCode) {
                        hint = nil
                        // Filled from the email or pasted: go as soon as six digits are in.
                        if codeDigits.count == 6 && !needsOTP { submitCode() }
                    }
            } footer: {
                if let hint, codeHint?.field == .code {
                    hintText(hint)
                } else {
                    Text("It works for 10 minutes. Not there? Check spam, or send a new one.")
                }
            }
        } else {
            Section {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(needsOTP ? .next : .go)
                    .focused($focus, equals: .password)
                    .onSubmit { if needsOTP { focus = .otp } else { submitCode() } }
                    .onChange(of: password) { hint = nil }
                    .disabled(needsOTP)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let hint, codeHint?.field == .password { hintText(hint) }
                    Button("Forgot Password?") { openURL(AppConfig.webURL("users/password/new")) }
                        .font(.footnote)
                }
            }
        }

        if needsOTP {
            Section {
                TextField("Code", text: $otpCode)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.asciiCapableNumberPad)
                    .focused($focus, equals: .otp)
                    .onSubmit(submitCode)
                    .onChange(of: otpCode) { hint = nil }
            } header: {
                Text("Two-Factor Code")
            } footer: {
                if let hint, codeHint?.field == .otp {
                    hintText(hint)
                } else {
                    Text("From your authenticator app, or one of your recovery codes.")
                }
            }
        }

        Section {
            Button(action: submitCode) {
                Group {
                    if isWorking { ProgressView() } else { Text(usesPassword ? "Sign In with Password" : "Continue") }
                }
                .frame(maxWidth: .infinity, minHeight: 30)
            }
            .filledButtonStyle()
            .controlSize(.large)
            .disabled(isWorking)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            errorRow
        }

        Section {
            if !usesPassword {
                Button("Send a New Code", action: resendCode)
            }
            Button(usesPassword ? "Use an Emailed Code Instead" : "Use Password Instead") {
                withAnimation {
                    usesPassword.toggle()
                    needsOTP = false
                    otpCode = ""
                    error = nil
                    notice = nil
                    hint = nil
                }
                focus = usesPassword ? .password : .code
            }
        }
        .frame(maxWidth: .infinity)
        .font(.subheadline)
        .disabled(isWorking)
    }

    /// The secondary way in: olive words under Continue, a link rather than a second button.
    private var passkeyLink: some View {
        Button(action: signInWithPasskey) {
            Text("Sign In with a Passkey")
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.accentColor)
        .disabled(isWorking)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0))
    }

    /// A main button's "fill this in first", in a field's footer: olive, not an error's red.
    private func hintText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Color.accentColor)
            .transition(.opacity)
    }

    /// Says what's missing, out loud too, and puts the cursor in that field.
    private func remind(_ text: String, in field: Field) {
        withAnimation { hint = text }
        focus = field
        AccessibilityNotification.Announcement(text).post()
    }

    @ViewBuilder private var errorRow: some View {
        if let error {
            Text(error)
                .font(.footnote)
                .foregroundStyle(Color.deleteRed)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        }
    }

    /// Markdown links built from the server's address (a literal with interpolated URLs
    /// wouldn't be read as links).
    private static var agreement: AttributedString {
        let terms = AppConfig.webURL("terms").absoluteString
        let privacy = AppConfig.webURL("privacy").absoluteString
        return (try? AttributedString(markdown: "By continuing you agree to the [Terms](\(terms)) and [Privacy Policy](\(privacy))."))
            ?? AttributedString("By continuing you agree to the Terms and Privacy Policy.")
    }

    // MARK: - Actions

    private func switchMode(to newMode: AuthFormMode) {
        withAnimation {
            mode = newMode
            error = nil
        }
    }

    private func continueWithEmail() {
        guard !isWorking else { return }
        if let missing = emailHint {
            remind(missing, in: .email)
            return
        }
        // A likely typo: say so once, and let a second Continue go ahead as typed.
        if EmailTypo.suggestion(for: trimmedEmail) != nil && typoShownFor != trimmedEmail {
            withAnimation { typoShownFor = trimmedEmail }
            return
        }
        isWorking = true
        error = nil
        let address = trimmedEmail
        Task {
            defer { isWorking = false }
            do {
                let sent = try await model.sendSignInCode(email: address)
                await stopAutoFillAndWait()
                withAnimation {
                    sentTo = sent.email
                    emailCode = ""
                    password = ""
                    otpCode = ""
                    usesPassword = false
                    needsOTP = false
                    notice = nil
                    step = .code
                }
                focus = .code
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func changeEmail() {
        withAnimation {
            step = .email
            error = nil
            notice = nil
            hint = nil
        }
        focus = .email
        startAutoFill()
    }

    private func resendCode() {
        isWorking = true
        error = nil
        notice = nil
        Task {
            defer { isWorking = false }
            do {
                _ = try await model.sendSignInCode(email: sentTo)
                emailCode = ""
                notice = "We sent a new code. The one before still works for a few minutes."
                focus = .code
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func submitCode() {
        guard !isWorking else { return }
        if let missing = codeHint {
            remind(missing.text, in: missing.field)
            return
        }
        isWorking = true
        error = nil
        notice = nil
        Task {
            defer { isWorking = false }
            do {
                let otp = needsOTP ? otpCode : nil
                if usesPassword {
                    try await model.signIn(email: sentTo, password: password, code: otp)
                } else {
                    try await model.signIn(email: sentTo, emailCode: codeDigits, otpCode: otp)
                }
                // Signed in: the welcome screens (and this sheet with them) give way to the journal.
            } catch NativeAuthError.needsCode {
                withAnimation { needsOTP = true }
                focus = .otp
            } catch {
                self.error = error.localizedDescription
                if needsOTP {
                    otpCode = ""
                } else if !usesPassword {
                    emailCode = ""
                }
            }
        }
    }

    private func signInWithPasskey() {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            await stopAutoFillAndWait()
            do {
                try await model.signInWithPasskey()
            } catch is CancellationError {
                // The passkey sheet was closed: back to the form, nothing to say.
                startAutoFill()
            } catch {
                self.error = error.localizedDescription
                startAutoFill()
            }
        }
    }

    // MARK: - Passkey autofill

    private func startAutoFill() {
        guard autoFill == nil, step == .email else { return }
        autoFill = Task {
            do {
                try await model.passkeyAutoFill()
            } catch is CancellationError {
                // Stopped (Continue, the passkey button, or the sheet closing): nothing to say.
            } catch {
                self.error = error.localizedDescription
            }
            autoFill = nil
        }
    }

    private func stopAutoFill() {
        guard autoFill != nil else { return }
        model.stopPasskeyAutoFill()
    }

    /// Stops autofill and waits for its request to end, so the system's passkey sheet can start.
    private func stopAutoFillAndWait() async {
        guard let running = autoFill else { return }
        model.stopPasskeyAutoFill()
        await running.value
    }
}
