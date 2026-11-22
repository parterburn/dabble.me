import SwiftUI

/// Where an account with no password (made by email code) confirms a change the password would
/// otherwise confirm: "Email Me a Code", then the code from that email (filled above the
/// keyboard). Delete Account and adding a passkey use it when `AppModel.confirmsWithEmailCode`.
struct EmailCodeConfirmField: View {
    @Environment(AppModel.self) private var model
    @Binding var code: String
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}

    @State private var sending = false
    @State private var sentTo: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sentTo != nil {
                TextField("6-digit code", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused(focused)
                    .submitLabel(.done)
                    .onSubmit(onSubmit)
            }
            Button(action: send) {
                if sending {
                    ProgressView()
                } else {
                    Text(sentTo == nil ? "Email Me a Code" : "Send a New Code")
                }
            }
            .disabled(sending)
            if let sentTo {
                Text("We sent a code to \(sentTo).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.deleteRed)
            }
        }
    }

    private func send() {
        sending = true
        error = nil
        Task {
            defer { sending = false }
            do {
                let sent = try await model.sendConfirmationCode()
                sentTo = sent.email
                code = ""
                focused.wrappedValue = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
