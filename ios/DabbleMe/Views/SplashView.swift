import SwiftUI

/// The launch animation when signed in: "Dabble me." typed onto the page, then the site's blinking
/// cursor, until the journal is ready (at most a couple of seconds). Signed out, the welcome
/// screen types the wordmark itself instead. With Reduce Motion it's the wordmark,
/// already written. It never takes touches, so nothing waits on it.
struct SplashView: View {
    /// The journal has loaded (or there's nothing to load): the splash can go once it's typed.
    let isReady: Bool
    let onFinish: () -> Void

    @State private var minimumShown = false
    @State private var isTimedOut = false
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color("Paper").ignoresSafeArea()
            Wordmark(size: 60, typesOut: true, showsCursor: true)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await play() }
        .onChange(of: isReady) { finishIfDone() }
        .onChange(of: minimumShown) { finishIfDone() }
    }

    private func play() async {
        // The wordmark types itself; then the cursor blinks a moment before the app appears.
        let typing = reduceMotion ? 0 : Wordmark.typingDuration
        try? await Task.sleep(for: .milliseconds(typing + (reduceMotion ? 600 : 700)))
        minimumShown = true
        // Never hold the app back for long.
        try? await Task.sleep(for: .milliseconds(1200))
        isTimedOut = true
        finishIfDone()
    }

    private func finishIfDone() {
        guard !finished, minimumShown, isReady || isTimedOut else { return }
        finished = true
        onFinish()
    }
}
