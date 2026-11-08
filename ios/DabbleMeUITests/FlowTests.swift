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
        saved.tap() // expands in the timeline
        sleep(1)
        saved.tap() // opens
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10), "Entry detail never opened")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10), "Could not get back to the journal")
    }

    /// Text size is a pinch on the entry (there's no setting for it any more).
    func testPinchChangesEntryTextSize() throws {
        openJournal()
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap() // expands in the timeline
        sleep(1)
        entry.tap() // opens
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))

        // A multi-line paragraph: room for two fingers, and its height shows the text size.
        let paragraph = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 5))
        // The size is remembered between runs: start from the smallest.
        paragraph.pinch(withScale: 0.3, velocity: -2)
        sleep(1)
        let smallest = paragraph.frame.height
        paragraph.pinch(withScale: 2.5, velocity: 2)
        sleep(1)
        XCTAssertGreaterThan(paragraph.frame.height, smallest + 10, "Pinching out makes the text larger")
        snap("text-size-pinched")
        // Back down to Default (three steps from Largest) for other runs.
        paragraph.pinch(withScale: 0.5, velocity: -2)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.staticTexts["Entry Text Size"].exists)
        XCTAssertFalse(app.staticTexts["Entries"].exists)
    }

    func testAIConnectorsInSettings() throws {
        openJournal()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Email"].waitForExistence(timeout: 10))
        let connector = app.links["Claude/ChatGPT Connector"]
        for _ in 0..<4 where !connector.isHittable {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(connector.waitForExistence(timeout: 5))
        XCTAssertTrue(app.links["Export Entries"].exists)
        snap("settings-ai")
    }

    func testTodayTab() throws {
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Random Entry"].isHittable, "Today has no random-entry button")
        // Memories depend on the date the demo account was seeded; either state is fine here.
        let memory = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ years? ago · [0-9]{4}")).firstMatch
        let empty = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Nothing from this date")).firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 5) || empty.exists, "On This Day should show memories or its empty state")
        snap("today")
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
