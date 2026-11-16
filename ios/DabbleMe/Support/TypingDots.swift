import SwiftUI

/// The app's "working on it": three dots that rise and darken one after another, like someone
/// typing. In place of iOS's spinner wherever something's being written, refreshed or
/// uploaded (a prompt, a reflection, a pull down, a photo), since writing is what the app's for.
struct TypingDots: View {
    enum Size {
        case small, regular, large

        var dot: CGFloat {
            switch self {
            case .small: 5
            case .regular: 7
            case .large: 10
            }
        }
    }

    var size: Size = .regular
    /// How far along a pull is (0...1), for a pull to refresh: the dots come in one by one with
    /// it, and start moving once it's let go. Nil: just working.
    var progress: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || progress.map { $0 < 1 } == true)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: size.dot * 0.7) {
                ForEach(0..<3, id: \.self) { index in
                    let lift = lift(index, at: time)
                    Circle()
                        .frame(width: size.dot, height: size.dot)
                        .opacity(0.3 + 0.7 * lift)
                        .offset(y: -size.dot * 0.45 * lift)
                }
            }
            // Room for the rise, so the row it's in doesn't move with it.
            .padding(.vertical, size.dot * 0.45)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement()
        .accessibilityLabel("Working")
    }

    /// 0...1: how far up (and how dark) a dot is. Each follows the one before it by a beat.
    private func lift(_ index: Int, at time: TimeInterval) -> Double {
        if let progress, progress < 1 {
            // Pulled part way: this many dots are in.
            return progress * 3 > Double(index) + 0.5 ? 0.6 : 0
        }
        guard !reduceMotion else { return 0.5 }
        let period = 1.2
        let phase = (time / period - Double(index) * 0.16).truncatingRemainder(dividingBy: 1)
        // Up and down over the first half of the beat, resting for the second.
        return phase < 0.5 ? sin(phase * 2 * .pi) : 0
    }
}

extension View {
    /// A pull to refresh shown with the app's dots instead of iOS's spinner (which the app
    /// keeps clear: see `DabbleMeApp`). On the scrolling view, beside its `.refreshable`.
    func refreshDots() -> some View { modifier(RefreshDots()) }
}

private struct RefreshDots: ViewModifier {
    @State private var pull: CGFloat = 0
    /// How far a pull goes before letting go refreshes (iOS's own distance, near enough).
    private let threshold: CGFloat = 70

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, overscroll in
                pull = max(0, overscroll)
            }
            .overlay(alignment: .top) {
                if pull > 14 {
                    TypingDots(size: .regular, progress: min(1, pull / threshold))
                        .opacity(min(1, (pull - 14) / 24))
                        // In the middle of the gap the pull opens above the page.
                        .offset(y: max(2, pull / 2 - 10))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}
