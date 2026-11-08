import SwiftUI

/// Shown over the app while it's locked; asks for Face ID right away.
struct LockScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(.rect(cornerRadius: 20))
                .accessibilityHidden(true)
            Text("Dabble Me is locked")
                .font(.system(.title2, design: .serif, weight: .semibold))
            Button {
                Task { await model.lock.authenticate() }
            } label: {
                Label("Unlock with \(model.lock.methodName)", systemImage: "lock.open")
                    .frame(minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Paper").ignoresSafeArea())
        .task {
            // Prompt once each time the lock appears. (The Face ID sheet itself makes the app
            // briefly inactive, so re-prompting on every activation would loop after a cancel.)
            try? await Task.sleep(for: .milliseconds(300))
            await model.lock.authenticate()
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
