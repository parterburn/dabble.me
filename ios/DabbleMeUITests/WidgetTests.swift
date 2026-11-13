import XCTest

/// Adds the Today widget to the home screen (after the app has written its snapshot) and takes
/// a screenshot. Opt-in: set TEST_RUNNER_DABBLE_WIDGET=1 with a local server and demo token.
final class WidgetTests: XCTestCase {
    func testAddTodayWidget() throws {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["DABBLE_TOKEN"], env["DABBLE_WIDGET"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_DABBLE_WIDGET=1 and TEST_RUNNER_DABBLE_TOKEN")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", testServer]
        app.launch()
        XCTAssertTrue(app.buttons["Journal"].firstMatch.waitForExistence(timeout: 15))
        sleep(3) // refresh writes the widget snapshot

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        sleep(1)
        // Long-press an empty spot low on the first home screen page.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(forDuration: 1.5)
        sleep(1)
        print("SB_BUTTONS=" + springboard.buttons.allElementsBoundByIndex.map { "\($0.label)|\($0.identifier)" }.joined(separator: ", "))
        snapshot(springboard, "widget-longpress")
        let edit = springboard.buttons["Edit"]
        if edit.waitForExistence(timeout: 3) {
            edit.tap()
            let addWidget = springboard.buttons["Add Widget"]
            XCTAssertTrue(addWidget.waitForExistence(timeout: 3))
            addWidget.tap()
        } else {
            let plus = springboard.buttons["Add Widget"].exists ? springboard.buttons["Add Widget"] : springboard.buttons["add-button"]
            XCTAssertTrue(plus.waitForExistence(timeout: 3))
            plus.tap()
        }
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Dabble")
        let result = springboard.cells.containing(NSPredicate(format: "label CONTAINS 'Dabble'")).firstMatch
        let resultButton = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Dabble'")).firstMatch
        if result.waitForExistence(timeout: 5) { result.tap() } else { XCTAssertTrue(resultButton.waitForExistence(timeout: 5)); resultButton.tap() }
        sleep(1)
        springboard.swipeLeft() // the medium size
        sleep(1)
        snapshot(springboard, "widget-gallery")
        let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        sleep(1)
        if springboard.buttons["Done"].exists { springboard.buttons["Done"].tap() }
        sleep(3)
        snapshot(springboard, "widget-home")
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}
