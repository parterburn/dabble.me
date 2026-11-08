import XCTest

/// Drives the real app against a local Rails server. Needs a token from
/// `bundle exec rails ios:demo_account`, passed as TEST_RUNNER_DABBLE_TOKEN.
final class FlowTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let token = ProcessInfo.processInfo.environment["DABBLE_TOKEN"] else {
            throw XCTSkip("Needs a local server and TEST_RUNNER_DABBLE_TOKEN (rails ios:demo_account)")
        }
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

    func testPullUpOpensPreviousDays() throws {
        openJournal()
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Biscuit has discovered the heated blanket")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))

        // Each pull up past the bottom should open the previous day with an entry, every time.
        for expected in ["Ran 5 miles", "Rainy day", "Hard conversation"] {
            sleep(1)
            let scroll = app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
            let previous = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
            XCTAssertTrue(previous.waitForExistence(timeout: 5), "Pulling up should open the entry with \"\(expected)\"")
        }
    }

    func testScrubberJumpsToOldestMonth() throws {
        openJournal()
        let scroll = app.collectionViews.firstMatch
        scroll.swipeUp(velocity: .slow) // the scrubber appears while scrolling
        let scrubber = app.otherElements["Timeline scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        let bottom = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.88))
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.3, thenDragTo: bottom)
        let oldest = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "November 2023")).firstMatch
        XCTAssertTrue(oldest.waitForExistence(timeout: 5), "Dragging to the bottom should jump to the oldest month")
        XCTAssertTrue(oldest.isHittable)
        let loaded = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Moved into the new apartment")).firstMatch
        XCTAssertTrue(loaded.waitForExistence(timeout: 3), "The month the scrubber lands on should load right away")
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

    func testRefreshPicksUpChangesInOlderMonths() throws {
        openJournal()
        scrubToBottom()
        sleep(2)
        snap("stale-before")
        if let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] {
            try? app.debugDescription.write(toFile: dir + "/stale-before.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(app.staticTexts["November 2023"].waitForExistence(timeout: 10))
        sleep(1) // let the month's entries load so it's cached before the change

        // Change that entry behind the app's back, as an email reply or the website would.
        let marker = "Edited elsewhere \(Int(Date().timeIntervalSince1970))"
        try api("PATCH", "entries/\(try entryID(year: 2023, month: 11))",
                body: ["document": [["type": "paragraph", "runs": [["text": marker]]]]])

        // Back to the top, then a deliberate pull to refresh.
        let timeline = app.collectionViews.firstMatch
        for _ in 0..<4 { timeline.swipeDown(velocity: .fast) }
        sleep(1)
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo: timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        sleep(3)
        scrubToBottom()
        sleep(3)
        snap("stale-after")
        if let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] {
            try? app.debugDescription.write(toFile: dir + "/stale-after.txt", atomically: true, encoding: .utf8)
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch.waitForExistence(timeout: 10),
                      "A cached older month should reload after a refresh")

        // Put the demo entry back.
        try api("PATCH", "entries/\(try entryID(year: 2023, month: 11))", body: ["document": [["type": "paragraph", "runs": [
            ["text": "Moved into the new apartment today. Boxes everywhere, no curtains yet, pizza on the floor. It already feels like home."],
        ]]]])
    }

    private func scrubToBottom() {
        let scroll = app.collectionViews.firstMatch
        scroll.swipeUp(velocity: .slow)
        let scrubber = app.otherElements["Timeline scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        let bottom = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.88))
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.3, thenDragTo: bottom)
    }

    // MARK: - Direct API calls (to simulate changes made outside the app)

    private func entryID(year: Int, month: Int) throws -> Int {
        let json = try api("GET", "entries?year=\(year)&month=\(month)")
        let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        return try XCTUnwrap(entries.first?["id"] as? Int)
    }

    @discardableResult
    private func api(_ method: String, _ path: String, body: [String: Any]? = nil) throws -> [String: Any] {
        let token = try XCTUnwrap(ProcessInfo.processInfo.environment["DABBLE_TOKEN"])
        var request = URLRequest(url: URL(string: "http://localhost:3000/api/v1/\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let done = expectation(description: "\(method) \(path)")
        nonisolated(unsafe) var result: Data?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            result = data
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)
        return (try? JSONSerialization.jsonObject(with: result ?? Data())) as? [String: Any] ?? [:]
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
