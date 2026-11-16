import SwiftUI

/// The launch animation when signed in: "Dabble me." typed onto the page, then the site's blinking
/// cursor, until the journal is ready (about 0.9 seconds at least, 2 at most). Signed out, the welcome
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
        // The wordmark types itself; then a beat with it whole before the app appears. Short:
        // this is the least anyone waits at launch, however fast the journal loads.
        let typing = reduceMotion ? 0 : Wordmark.typingDuration
        try? await Task.sleep(for: .milliseconds(typing + (reduceMotion ? 400 : 250)))
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
