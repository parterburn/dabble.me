import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 22))
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("Dabble Me")
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                Text("Your private journal. Read back through the years, and write whenever the mood strikes.")
                    .font(.system(.body, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    Task { await model.signIn() }
                } label: {
                    Group {
                        if model.isSigningIn {
                            ProgressView()
                        } else {
                            Text("Sign In")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isSigningIn)

                if let error = model.signInError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Text("Sign in with your passkey, password, or two-factor code on dabble.me. New here? You can create a free account on the sign-in page.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                #if DEBUG
                ServerPicker()
                    .padding(.top, 4)
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(Color("Paper").ignoresSafeArea())
    }
}
