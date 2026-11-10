import XCTest

extension XCUIElement {
    /// Taps a timeline row on its text, near the top: a tap on its photo opens the photo instead.
    /// Below the sticky month header, which covers a row scrolled up to the top of the list.
    func tapRowText() {
        let y = min(max(6, 150 - frame.minY), max(frame.height - 6, 6))
        coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.width * 0.6, dy: y)).tap()
    }

    /// Swipes a timeline row near its top, which is on screen even when a tall row isn't all in
    /// view (a swipe at its middle can land off screen).
    func swipeRow(left: Bool) {
        let start = coordinate(withNormalizedOffset: CGVector(dx: left ? 0.85 : 0.15, dy: 0.05))
        start.press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: left ? 0.15 : 0.85, dy: 0.05)))
    }
}

extension XCUIApplication {
    /// Scrolls the current list until `element` is on screen (rows are tall, with big photos).
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 10) {
        _ = element.waitForExistence(timeout: 5)
        var swipes = 0
        // On screen, and in the upper half: near the tab bar, taps and swipes on it aren't reliable.
        let half = windows.firstMatch.frame.height / 2
        while !(element.exists && element.isHittable && element.frame.minY < half), swipes < maxSwipes {
            collectionViews.firstMatch.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    /// Opens a timeline entry: scrolls to it, then taps its text (a long one expands first).
    func openTimelineEntry(_ row: XCUIElement) {
        scrollTo(row)
        row.tapRowText()
        // A long entry expands on the first tap and moves; find it again before tapping to open.
        for _ in 0..<2 where !buttons["Edit Entry"].waitForExistence(timeout: 3) {
            scrollTo(row)
            row.tapRowText()
        }
    }
}
