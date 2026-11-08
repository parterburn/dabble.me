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
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 15))
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
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 15))
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
        snap("text-size-entry")

        // The entry menu steps it down; then put it back to Default for other runs.
        app.buttons["Entry Actions"].tap()
        let smaller = app.buttons["Smaller Text"]
        XCTAssertTrue(smaller.waitForExistence(timeout: 5))
        smaller.tap()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Extra Large")).firstMatch.waitForExistence(timeout: 5),
                      "Smaller Text in the entry menu should step Largest down to Extra Large")
        picker.tap()
        app.buttons["Default"].tap()
    }

    func testAIConnectorsInSettings() throws {
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 15))
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

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}
