import SwiftUI

/// The launch animation: "Dabble me." typed onto the page, then the site's blinking cursor, until
/// the journal is ready (at most a couple of seconds). With Reduce Motion it's the wordmark,
/// already written. It never takes touches, so nothing waits on it.
struct SplashView: View {
    /// The journal has loaded (or there's nothing to load): the splash can go once it's typed.
    let isReady: Bool
    let onFinish: () -> Void

    @State private var typed = 0
    @State private var minimumShown = false
    @State private var isTimedOut = false
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color("Paper").ignoresSafeArea()
            Wordmark(size: 60, typed: typed, showsCursor: true)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await play() }
        .onChange(of: isReady) { finishIfDone() }
        .onChange(of: minimumShown) { finishIfDone() }
    }

    private func play() async {
        let letters = Wordmark.letters.count
        if reduceMotion {
            typed = letters
            try? await Task.sleep(for: .milliseconds(600))
        } else {
            try? await Task.sleep(for: .milliseconds(200))
            // A little unevenly, like someone typing; a beat before the period.
            for index in 1...letters {
                typed = index
                let pause = index == letters - 1 ? 180 : 55 + (index * 37) % 45
                try? await Task.sleep(for: .milliseconds(pause))
            }
            // The cursor blinks a moment before the app appears.
            try? await Task.sleep(for: .milliseconds(700))
        }
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
