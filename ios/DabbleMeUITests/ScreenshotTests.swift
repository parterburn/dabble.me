import XCTest

/// App Store screenshots from the demo account (`rails ios:demo_account`; never a real journal).
/// Run on the 6.9" iPhone and 13" iPad simulators with TEST_RUNNER_DABBLE_TOKEN and
/// TEST_RUNNER_DABBLE_SCREENSHOT_DIR set; skipped otherwise, so regular test runs don't need it.
final class ScreenshotTests: XCTestCase {
    func testAppStoreScreenshots() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["DABBLE_SCREENSHOT_DIR"], let token = env["DABBLE_TOKEN"] else {
            throw XCTSkip("Screenshots are opt-in: set TEST_RUNNER_DABBLE_SCREENSHOT_DIR and TEST_RUNNER_DABBLE_TOKEN")
        }
        let photos = ["1426604966848-d7adac402bff", "1442512595331-e89e73853f31"]
            .map { "https://images.unsplash.com/photo-\($0)?w=2400&h=1800&fit=crop&fm=jpg&q=80" }.joined(separator: ",")

        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", testServer,
                               "-DabbleDebugComposePhotoURLs", photos, "-readingTextSize", "1",
                               "-DabbleDebugCalendar", "YES", // a made-up day's events, for the "?" row
                               "-stats.heatmapCell", "13"] // Stats' grid at its own size, whatever a test pinched it to
        app.launch()

        // iPhone has a bottom tab bar; iPad shows tabs at the top as plain buttons.
        func tab(_ name: String) -> XCUIElement {
            let bar = app.tabBars.buttons[name]
            return bar.exists ? bar : app.buttons.matching(identifier: name).firstMatch
        }

        func shot(_ name: String) {
            sleep(2) // let images finish loading
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }

        // 1. Today: prompt, write button, On This Day, and the last five days as dots.
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 20))
        sleep(3) // the dots come in a moment after Today
        shot("01-today")

        // 4. (Taken here, from Today.) A past entry with the same day in other years under it.
        let memory = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bruges! Wandered")).firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 10))
        app.openTimelineEntry(memory)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 10))
        // Up a little, so the last of the other years sits clear of the floating buttons.
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -110)), withVelocity: .slow, thenHoldForDuration: 0.2)
        shot("04-on-this-day")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 2. Journal timeline.
        tab("Journal").tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
        shot("02-journal")

        // 3. An entry with formatting and a photo.
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        app.openTimelineEntry(entry)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        shot("03-entry")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 4. Writing, with the formatting bar, photos and on-device hashtag suggestions.
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Photos' AND value == '2 photos'")).firstMatch.waitForExistence(timeout: 30))
        // A fresh simulator shows the one-time "slide to type" tip over the keyboard.
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        editor.typeText("Slow Saturday. Made pour-over with the beans from the farmers market and read on the porch until noon.\nGrateful for:\n- Quiet mornings\nThe first cold brew of fall")
        app.buttons["Hashtags"].tap() // the row: suggestions for what's written, then recent tags
        _ = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '#'")).firstMatch.waitForExistence(timeout: 60)
        _ = app.descendants(matching: .any)["Suggesting hashtags"].waitForNonExistence(timeout: 60)
        // Open the photo drawer from the stack, so the shot shows the photos (the bar and its
        // rows sit on the keyboard, so the keyboard stays up).
        app.buttons["Photos"].tap()
        sleep(1)
        shot("05-write")
        app.buttons["Cancel"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        sleep(1)

        // 6. What to write about, on a blank page: the day's calendar over a prompt.
        app.buttons["New Entry"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        // (No tap on the page: on a blank one that brings up Paste / AutoFill over it.)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        if app.buttons["Start Over"].waitForExistence(timeout: 2) { app.buttons["Start Over"].tap() }
        app.buttons["Prompt"].tap()
        XCTAssertTrue(app.staticTexts["AskMeQuestion"].waitForExistence(timeout: 60))
        sleep(1)
        shot("06-ideas")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        sleep(1)

        // 7–8. Journal's Photos and Stats views, from the title menu.
        func journalView(_ current: String, _ mode: String) {
            let title = app.navigationBars.buttons[current].exists ? app.navigationBars.buttons[current] : app.navigationBars.staticTexts[current]
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            title.tap()
            // The menu's items, not the tab bar's buttons of the same name.
        let item = app.buttons["JournalMode-\(mode)"]
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.tap()
        }
        journalView("Journal", "Photos")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch.waitForExistence(timeout: 10))
        shot("07-photos")
        journalView("Photos", "Stats")
        XCTAssertTrue(app.statTile("Words").waitForExistence(timeout: 10))
        shot("08-stats")
        journalView("Stats", "Journal")

        // 9–10. Search: the hashtag cloud, then a hashtag's entries.
        tab("Search").tap()
        XCTAssertTrue(app.staticTexts["Your Hashtags This Year"].waitForExistence(timeout: 10))
        shot("09-hashtags")
        app.buttons["#hiking"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Yosemite")).firstMatch
            .waitForExistence(timeout: 10))
        if app.keyboards.count > 0 { app.swipeDown() }
        shot("10-search")
    }
}
