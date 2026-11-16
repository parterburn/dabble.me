import SwiftUI

/// Shown over the app while it's locked: "Dabble me." types itself out, like the launch, and stays.
/// Face ID is asked for at once, while it types (nothing waits on the typing), and the Face ID
/// symbol fades in below it. Tap the symbol to try again after a cancel.
struct LockScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showsUnlock = false

    var body: some View {
        Wordmark(size: 60, typesOut: true, showsCursor: true)
            .overlay(alignment: .bottom) {
                Button {
                    Task { await model.lock.authenticate() }
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.tint)
                        .frame(width: 88, height: 88)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unlock with \(model.lock.methodName)")
                .opacity(showsUnlock ? 1 : 0)
                .offset(y: 120)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("Paper").ignoresSafeArea())
            .task {
                // The symbol fades in and Face ID is asked for straight away, while the wordmark
                // types, once each time the lock appears. (The Face ID sheet itself makes the app
                // briefly inactive, so re-prompting on every activation would loop after a cancel.)
                withAnimation(.easeIn(duration: 0.4)) { showsUnlock = true }
                // As soon as the app is in front (up to 2 seconds): asked for while it's still
                // coming forward, Face ID is refused without being shown.
                for _ in 0..<40 where UIApplication.shared.applicationState != .active {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                await model.lock.authenticate()
            }
    }

    private var symbol: String {
        switch model.lock.methodName {
        case "Face ID": "faceid"
        case "Touch ID": "touchid"
        case "Optic ID": "opticid"
        default: "lock"
        }
    }
}

/// Covers the journal while the app isn't active (app switcher, Control Center).
struct PrivacyCover: View {
    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: 88, height: 88)
            .clipShape(.rect(cornerRadius: 20))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("Paper").ignoresSafeArea())
            .accessibilityHidden(true)
    }
}
