import SwiftUI

/// Google Photos-style fast scroller for the Journal: a tab on the right edge (rounded on its
/// left, flush with the screen) that appears while scrolling; drag it to see the years and the
/// month you're on, and jump to any month, or tap it for a calendar of the days you wrote.
/// Positions are proportional to entry counts, which matches the timeline's layout (rows and
/// placeholders are similar heights).
struct TimelineScrubber: View {
    let months: [MonthCount]
    let progress: CGFloat
    let isScrolling: Bool
    let onSelect: (MonthCount) -> Void
    /// The month the scrubber was released on, so its entries can load right away.
    var onRelease: (MonthCount) -> Void = { _ in }
    /// A tap on the thumb (no drag): jump to a day from a calendar.
    var onTap: () -> Void = {}

    @State private var dragFraction: CGFloat?
    @State private var selected: MonthCount?
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?

    private static let space = "TimelineScrubber"
    private let thumbHeight: CGFloat = 56
    private let stripWidth: CGFloat = 46

    var body: some View {
        GeometryReader { geometry in
            let track = max(geometry.size.height - thumbHeight, 1)
            let fraction = dragFraction ?? progress

            ZStack(alignment: .topTrailing) {
                if dragFraction != nil {
                    yearLabels(trackHeight: track)
                        .transition(.opacity)
                    // The month you're on, beside the thumb, until you let go.
                    if let month = month(at: fraction) {
                        Text(month.title)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: .capsule)
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                            .frame(height: thumbHeight)
                            // Well left of the thumb, so the finger dragging it doesn't cover it.
                            .offset(x: -(stripWidth + 70), y: fraction * track)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    }
                }

                // Only the thumb takes touches, so scrolling near the edge still scrolls the list.
                // It stays grabbable after fading out, like Google Photos.
                UnevenRoundedRectangle(topLeadingRadius: thumbHeight / 2, bottomLeadingRadius: thumbHeight / 2)
                    .fill(Color(uiColor: .tertiarySystemBackground))
                    .overlay {
                        // Slab's up and down angles, stacked (slab-scrub), drawn a little larger
                        // than the 24pt icons so the chevrons read at a glance.
                        appIcon("slab-scrub")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 33, height: 33)
                            .foregroundStyle(.primary)
                            .padding(.leading, 4)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 8, x: -1, y: 2)
                    .scaleEffect(dragFraction != nil ? 1.06 : 1, anchor: .trailing)
                    .frame(width: stripWidth, height: thumbHeight)
                    .opacity(visible || dragFraction != nil ? 1 : 0.001)
                    .contentShape(.rect)
                    .offset(y: fraction * track)
                    .gesture(drag(trackHeight: track))
                    .accessibilityElement()
                    .accessibilityLabel("Timeline scrubber")
                    .accessibilityValue(month(at: fraction)?.title ?? "")
                    .accessibilityAdjustableAction { direction in
                        adjust(direction)
                    }
                    .accessibilityAction(named: "Jump to a Day") { onTap() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .coordinateSpace(.named(Self.space))
        .frame(width: 260)
        .padding(.vertical, 8)
        .animation(.easeOut(duration: 0.2), value: dragFraction == nil)
        .animation(.easeOut(duration: 0.25), value: visible)
        .sensoryFeedback(.selection, trigger: selected)
        .onChange(of: isScrolling) { _, scrolling in
            if scrolling { show() } else { scheduleHide() }
        }

    }

    // MARK: - Mapping


    /// Where each month starts, as a fraction of all entries (newest month at 0).
    private var starts: [CGFloat] {
        let total = CGFloat(max(months.reduce(0) { $0 + $1.count }, 1))
        var running = 0
        return months.map { month in
            defer { running += month.count }
            return CGFloat(running) / total
        }
    }

    private func month(at fraction: CGFloat) -> MonthCount? {
        let starts = starts
        guard let index = starts.lastIndex(where: { $0 <= fraction + 0.0001 }) else { return months.first }
        return months[index]
    }

    private func yearLabels(trackHeight: CGFloat) -> some View {
        let starts = starts
        var labels: [(year: Int, y: CGFloat)] = []
        for (index, month) in months.enumerated() where labels.last?.year != month.year {
            let y = starts[index] * trackHeight
            if let last = labels.last, y - last.y < 26 { continue } // avoid overlapping labels
            labels.append((month.year, y))
        }
        return ZStack(alignment: .topTrailing) {
            ForEach(labels, id: \.year) { label in
                Text(String(label.year))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: .capsule)
                    .offset(x: -stripWidth, y: label.y + thumbHeight / 2 - 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Interaction

    private func drag(trackHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                hideTask?.cancel()
                show()
                // Scrubbing starts once the finger moves, so a tap doesn't jump the list.
                guard dragFraction != nil || abs(value.translation.height) > 5 else { return }
                let fraction = min(max((value.location.y - thumbHeight / 2) / trackHeight, 0), 1)
                dragFraction = fraction
                if let month = month(at: fraction), month != selected {
                    selected = month
                    onSelect(month)
                }
            }
            .onEnded { _ in
                if dragFraction == nil {
                    onTap() // it never moved: a tap
                    scheduleHide()
                    return
                }
                if let selected { onRelease(selected) }
                dragFraction = nil
                selected = nil
                scheduleHide()
            }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let current = month(at: progress).flatMap { months.firstIndex(of: $0) } ?? 0
        let next = direction == .increment ? max(current - 1, 0) : min(current + 1, months.count - 1)
        onSelect(months[next])
    }

    private func show() {
        hideTask?.cancel()
        visible = true
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            visible = false
        }
    }
}
