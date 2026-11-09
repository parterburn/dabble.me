import SwiftUI

/// Shown over the app while it's locked; asks for Face ID right away.
struct LockScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Just the unlock symbol: tap it to try again after a cancel.
        Button {
            Task { await model.lock.authenticate() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 96, height: 96)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unlock with \(model.lock.methodName)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Paper").ignoresSafeArea())
        .task {
            // Prompt once each time the lock appears. (The Face ID sheet itself makes the app
            // briefly inactive, so re-prompting on every activation would loop after a cancel.)
            try? await Task.sleep(for: .milliseconds(300))
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
