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
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", testServer]
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
        // The new entry opens in full; back from it, it's in the timeline.
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10), "The new entry never opened")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10), "Could not get back to the journal")
        let saved = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Testing the app after saving")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "New entry missing from the timeline")
    }

    /// Text size is a pinch on the entry (there's no setting for it any more).
    func testPinchChangesEntryTextSize() throws {
        openJournal()
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        app.openTimelineEntry(entry)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))

        // A multi-line paragraph: room for two fingers, and its height shows the text size.
        // (The entry's text is one selectable text view; its height shows the size.)
        let paragraph = app.textViews.firstMatch
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
        XCTAssertTrue(app.links["Account Security"].exists)
        XCTAssertFalse(app.links["Email Preferences"].exists, "Email settings are in the app now")
        snap("settings-ai")
    }

    func testTodayTab() throws {
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Random Entry"].isHittable, "Today has no random-entry button")
        // The demo account is seeded with entries 1, 2 and 3 years before today.
        let memory = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ years? ago • .*[0-9]{4}")).firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 5), "On This Day shows the demo's memories")
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
        if !oldest.waitForExistence(timeout: 5) {
            // The scrubber fades in while scrolling; a drag that starts as it appears can miss it.
            scroll.swipeUp(velocity: .slow)
            scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.3, thenDragTo: bottom)
        }
        XCTAssertTrue(oldest.waitForExistence(timeout: 5), "Dragging to the bottom should jump to the oldest month")
        XCTAssertTrue(oldest.isHittable)
        let loaded = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Moved into the new apartment")).firstMatch
        XCTAssertTrue(loaded.waitForExistence(timeout: 8), "The month the scrubber lands on should load right away")
        snap("journal-scrubbed")
    }

    /// Tapping (not dragging) the scrubber opens a calendar of written days; picking one opens
    /// that day's entry in full.
    func testTappingScrubberJumpsToADay() throws {
        openJournal()
        scrubToBottom() // start far from the day picked below
        let scrubber = app.otherElements["Timeline scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        scrubber.tap()
        XCTAssertTrue(app.staticTexts["Jump to a Day"].waitForExistence(timeout: 5), "A tap opens the calendar")
        sleep(1)
        snap("day-picker")
        // The demo's Biscuit entry is five days ago, in the month the calendar opens on.
        let date = Calendar.current.date(byAdding: .day, value: -5, to: .now)!
        let label = date.formatted(.dateTime.month(.wide).day())
        let day = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 10), "\(label) is in the calendar")
        day.tap()
        let text = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Biscuit has discovered", "Biscuit has discovered")).firstMatch
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10), "The day's entry opens in full")
        XCTAssertTrue(text.waitForExistence(timeout: 10), "It's that day's")
        snap("day-picked")
    }

    /// The medium widget's entry half opens that entry (me.dabble.app:/entry/<id>).
    func testWidgetEntryLinkOpensTheEntry() throws {
        let today = Calendar.current.dateComponents([.year, .month], from: .now)
        let id = try entryID(year: today.year!, month: today.month!)
        XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 15))
        app.open(URL(string: "me.dabble.app:/entry/\(id)")!)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10), "The widget's entry link opens it")
    }

    /// Touch and hold the app icon: New Entry, View Journal and Search Journal open those places.
    func testHomeScreenQuickActions() throws {
        XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 15))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func quickAction(_ title: String) {
            XCUIDevice.shared.press(.home)
            let icon = springboard.icons["Dabble Me"]
            XCTAssertTrue(icon.waitForExistence(timeout: 10), "The app icon is on the Home Screen")
            icon.press(forDuration: 1.5)
            let action = springboard.buttons[title]
            XCTAssertTrue(action.waitForExistence(timeout: 5), "\(title) is a quick action")
            action.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        }

        quickAction("View Journal")
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10) || app.buttons["Journal"].isSelected)

        quickAction("Search Journal")
        let field = app.searchFields["Search your journal"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Search Journal focuses the search field")

        quickAction("New Entry")
        XCTAssertTrue(app.textViews["Entry"].waitForExistence(timeout: 10), "New Entry opens the composer")
        snap("quick-action-new-entry")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
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
        app.tabBars.buttons["Journal"].tap() // tapping the current tab goes back to the top
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
        var request = URLRequest(url: URL(string: "\(testServer)/api/v1/\(path)")!)
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

    /// The composer's date opens a calendar under it (a dot marks the days already written),
    /// and picking a day there dates the entry and closes it.
    func testEntryDateIsPickedFromTheCalendar() throws {
        openJournal()
        app.buttons["New Entry"].tap()
        let date = app.buttons["Entry date"]
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        date.tap()
        // Three days ago (in the month before, early in a month).
        let picked = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
        let label = picked.formatted(.dateTime.month(.wide).day())
        let day = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(app.buttons["Previous Month"].waitForExistence(timeout: 5), "The date opens the calendar")
        if Calendar.current.component(.day, from: .now) <= 3 { app.buttons["Previous Month"].tap() }
        XCTAssertTrue(day.waitForExistence(timeout: 10), "\(label) is in the calendar")
        sleep(1) // the dots
        snap("entry-date")
        day.tap()
        XCTAssertTrue(app.buttons["Previous Month"].waitForNonExistence(timeout: 5), "Picking a day closes the calendar")
        XCTAssertTrue((date.value as? String)?.contains(label) == true, "The entry is dated \(label): \(date.value ?? "")")
        snap("entry-date-picked")
    }

    /// Swiping an open entry's date steps to the entry before it (right) and back (left).
    func testSwipingAnEntrysDateStepsBetweenEntries() throws {
        openJournal()
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        app.openTimelineEntry(entry)
        // Yesterday's entry; the one before it is the day before's.
        func title(_ ago: Int) -> XCUIElement {
            let date = Calendar.current.date(byAdding: .day, value: -ago, to: .now)!
            return app.buttons[date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())]
        }
        XCTAssertTrue(title(1).waitForExistence(timeout: 10))
        title(1).swipeRight()
        XCTAssertTrue(title(2).waitForExistence(timeout: 10), "A swipe right is the entry before")
        snap("entry-swiped-back")
        title(2).swipeLeft()
        XCTAssertTrue(title(1).waitForExistence(timeout: 10), "A swipe left is the entry after")
    }

    /// Pulling an open entry down and to one side, then letting go, steps to the entry before
    /// it (left) or after (right).
    func testPullingAnEntryDownAndAsideStepsBetweenEntries() throws {
        openJournal()
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        app.openTimelineEntry(entry)
        func title(_ ago: Int) -> XCUIElement {
            let date = Calendar.current.date(byAdding: .day, value: -ago, to: .now)!
            return app.buttons[date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())]
        }
        XCTAssertTrue(title(1).waitForExistence(timeout: 10))
        func pull(toward x: Double) {
            let scroll = app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.8)),
                       withVelocity: .slow, thenHoldForDuration: 1.5)
        }
        pull(toward: 0.2)
        XCTAssertTrue(title(2).waitForExistence(timeout: 10), "Down and left is the entry before")
        pull(toward: 0.8)
        XCTAssertTrue(title(1).waitForExistence(timeout: 10), "Down and right is the entry after")
    }

    /// An open entry's back arrow, held, opens Jump to a Day (a tap still goes back).
    func testHoldingAnEntrysBackArrowJumpsToADay() throws {
        openJournal()
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        app.openTimelineEntry(entry)
        let back = app.descendants(matching: .any)["Back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.press(forDuration: 1.0)
        XCTAssertTrue(app.staticTexts["Jump to a Day"].waitForExistence(timeout: 5), "Held, the arrow opens the calendar")
        snap("jump-sheet")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 5), "Still on the entry")
        back.tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10), "A tap goes back")
    }

    /// A swipe in from the left edge of an open entry goes back, as it does anywhere in iOS.
    func testSwipingFromTheLeftEdgeLeavesAnEntry() throws {
        openJournal()
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        app.openTimelineEntry(entry)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        sleep(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 5), "The edge swipe goes back to the Journal")
        XCTAssertFalse(app.buttons["Edit Entry"].exists)
    }

    /// Under an open entry, On This Day lists the same date in other years, briefly; a tap on
    /// one opens that entry.
    func testOnThisDayUnderAnEntryOpensTheOtherYears() throws {
        let memory = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "First snow of the year")).firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 20))
        app.openTimelineEntry(memory)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 10))
        let other = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Bruges! Wandered the canals")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 10), "The year after is listed under the entry")
        sleep(1)
        snap("entry-on-this-day")
        other.tap()
        let year = Calendar.current.component(.year, from: .now) - 1
        let title = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", String(year))).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "A tap opens that year's entry")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Bruges! Wandered", "Bruges! Wandered")).firstMatch.waitForExistence(timeout: 10),
                      "And it's that entry's writing")
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}
