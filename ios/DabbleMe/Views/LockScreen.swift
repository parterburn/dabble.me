import SwiftUI

/// Shown over the app while it's locked: "Dabble me." types itself out, like the launch, and stays;
/// then the Face ID symbol fades in below it and Face ID is asked for. Tap the symbol to try again
/// after a cancel.
struct LockScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                // Once the wordmark is typed, the symbol fades in and Face ID is asked for, once
                // each time the lock appears. (The Face ID sheet itself makes the app briefly
                // inactive, so re-prompting on every activation would loop after a cancel.)
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : Wordmark.typingDuration + 250))
                withAnimation(.easeIn(duration: 0.4)) { showsUnlock = true }
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
