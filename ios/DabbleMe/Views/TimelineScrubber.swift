import SwiftUI

/// Google Photos-style fast scroller for the Journal: a thumb on the right edge that appears
/// while scrolling; drag it to see the years and jump to any month. Positions are proportional
/// to entry counts, which matches the timeline's layout (rows and placeholders are similar heights).
struct TimelineScrubber: View {
    let months: [MonthCount]
    let progress: CGFloat
    let isScrolling: Bool
    let onSelect: (MonthCount) -> Void
    /// The month the scrubber was released on, so its entries can load right away.
    var onRelease: (MonthCount) -> Void = { _ in }

    @State private var dragFraction: CGFloat?
    @State private var selected: MonthCount?
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?

    private static let space = "TimelineScrubber"
    /// The thumb is a circle three-quarters on screen, tucked into the right edge.
    private let thumbHeight: CGFloat = 52
    private let stripWidth: CGFloat = 52
    private var tucked: CGFloat { thumbHeight / 4 }

    var body: some View {
        GeometryReader { geometry in
            let track = max(geometry.size.height - thumbHeight, 1)
            let fraction = dragFraction ?? progress

            ZStack(alignment: .topTrailing) {
                if dragFraction != nil {
                    yearLabels(trackHeight: track)
                        .transition(.opacity)
                }

                if let selected, let dragFraction {
                    Text(selected.shortTitle)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: .capsule)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                        .offset(x: -stripWidth - 56, y: dragFraction * track + thumbHeight / 2 - 18)
                        .allowsHitTesting(false)
                }

                // Only the thumb takes touches, so scrolling near the edge still scrolls the list.
                // It stays grabbable after fading out, like Google Photos.
                Circle()
                    .fill(.regularMaterial)
                    .overlay(alignment: .leading) {
                        // Centered in the part that's on screen, as bold as the toolbar's +.
                        appIcon("slab-sort")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.primary)
                            .frame(width: thumbHeight - tucked)
                    }
                    .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 6, x: -1, y: 2)
                    .scaleEffect(dragFraction != nil ? 1.08 : 1, anchor: .trailing)
                    .frame(width: thumbHeight, height: thumbHeight)
                    .opacity(visible || dragFraction != nil ? 1 : 0.001)
                    .contentShape(.rect)
                    .offset(x: tucked, y: fraction * track)
                    .gesture(drag(trackHeight: track))
                    .accessibilityElement()
                    .accessibilityLabel("Timeline scrubber")
                    .accessibilityValue(month(at: fraction)?.title ?? "")
                    .accessibilityAdjustableAction { direction in
                        adjust(direction)
                    }
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
                let fraction = min(max((value.location.y - thumbHeight / 2) / trackHeight, 0), 1)
                dragFraction = fraction
                if let month = month(at: fraction), month != selected {
                    selected = month
                    onSelect(month)
                }
            }
            .onEnded { _ in
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
