import XCTest

/// Drives the real app against a local Rails server. Needs a token from
/// `bundle exec rails ios:demo_account`, passed as TEST_RUNNER_DABBLE_TOKEN.
final class FlowTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let token = try XCTUnwrap(ProcessInfo.processInfo.environment["DABBLE_TOKEN"], "Set TEST_RUNNER_DABBLE_TOKEN")
        app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", "http://localhost:3000"]
        app.launch()
    }

    func testWriteEntryThenKeepUsingTheApp() throws {
        openJournal()
        app.buttons["New Entry"].tap()

        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Testing the app after saving.")
        app.buttons["Save"].tap()

        // The sheet should close and the app should stay responsive.
        XCTAssertTrue(editor.waitForNonExistence(timeout: 15), "Compose sheet never closed")
        sleep(3)
        if let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/after-save.png"))
            try? app.debugDescription.write(toFile: dir + "/after-save.txt", atomically: true, encoding: .utf8)
        }
        let saved = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Testing the app after saving")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "New entry missing from the timeline")
        saved.tap()
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10), "Entry detail never opened")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10), "Could not get back to the journal")
    }

    func testReadingTextSizeSetting() throws {
        openJournal()
        app.tabBars.buttons["Settings"].tap()
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Entry Text Size")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["Largest"].tap()
        snap("text-size-settings")

        app.tabBars.buttons["Journal"].tap()
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))
        sleep(1)
        snap("text-size-entry")

        // Pinching in on the entry steps the size down; then put it back to Default for other runs.
        let body = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Things I want to remember")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.pinch(withScale: 0.6, velocity: -1)
        snap("text-size-pinched")
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Largest")).firstMatch.waitForExistence(timeout: 3),
                       "Pinching in on an entry should make the text smaller than Largest")
        picker.tap()
        app.buttons["Default"].tap()
    }

    func testAIConnectorsInSettings() throws {
        openJournal()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let claude = app.links["Connect to Claude"]
        for _ in 0..<4 where !claude.isHittable {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(claude.waitForExistence(timeout: 5))
        XCTAssertTrue(app.links["Connect to ChatGPT"].exists)
        XCTAssertTrue(app.links["Set Up a Passkey First"].exists, "Demo account has no passkey/2FA yet")
        snap("settings-ai")
    }

    func testTodayTab() throws {
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Random Entry"].isHittable, "Today has no random-entry button")
        XCTAssertTrue(app.staticTexts["1 year ago · 2025"].waitForExistence(timeout: 5), "Demo account has an entry from a year ago today")
        snap("today")
    }

    func testScrubberJumpsToOldestMonth() throws {
        openJournal()
        let scroll = app.scrollViews.firstMatch
        scroll.swipeUp(velocity: .slow) // the scrubber appears while scrolling
        let scrubber = app.otherElements["Timeline scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        let bottom = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.88))
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.3, thenDragTo: bottom)
        let oldest = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "November 2023")).firstMatch
        XCTAssertTrue(oldest.waitForExistence(timeout: 5), "Dragging to the bottom should jump to the oldest month")
        XCTAssertTrue(oldest.isHittable)
        snap("journal-scrubbed")
    }

    func testPullDownOpensNextDay() throws {
        openJournal()
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Biscuit has discovered the heated blanket")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))

        let scroll = app.scrollViews.firstMatch
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))

        // The next (newer) day in the demo journal is the presentation entry.
        let next = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Big presentation went well")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5), "Pulling down past the top should open the next day's entry")
        snap("pulled-next-day")
    }

    private func openJournal() {
        XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 15))
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}
