import XCTest

extension XCUIElement {
    /// Taps a timeline row on its text, near the top: a tap on its photo opens the photo instead.
    func tapRowText() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.03)).tap()
    }
}

extension XCUIApplication {
    /// Scrolls the current list until `element` is on screen (rows are tall, with big photos).
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 10) {
        _ = element.waitForExistence(timeout: 5)
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < maxSwipes {
            collectionViews.firstMatch.swipeUp(velocity: .slow)
            swipes += 1
        }
    }

    /// Opens a timeline entry: scrolls to it, then taps its text (a long one expands first).
    func openTimelineEntry(_ row: XCUIElement) {
        scrollTo(row)
        row.tapRowText()
        if !buttons["Entry Actions"].waitForExistence(timeout: 3) { row.tapRowText() }
    }
}
