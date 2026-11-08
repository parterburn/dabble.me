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
        let photos = [1043, 1060].map { "https://picsum.photos/id/\($0)/2400/1800" }.joined(separator: ",")

        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", "http://localhost:3000",
                               "-DabbleDebugComposePhotoURLs", photos, "-readingTextSize", "1"]
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

        // 1. Today: prompt, write button, On This Day.
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 20))
        shot("01-today")

        // 2. Journal timeline.
        tab("Journal").tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
        shot("02-journal")

        // 3. An entry with formatting and a photo.
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))
        shot("03-entry")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 4. Writing, with the formatting bar, photos and on-device hashtag suggestions.
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add More"].waitForExistence(timeout: 30))
        editor.tap()
        // A fresh simulator shows the one-time "slide to type" tip over the keyboard.
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        editor.typeText("Slow Saturday. Made pour-over with the beans from the farmers market and read on the porch until noon.\n\nGrateful for:\n- Quiet mornings\nThe first cold brew of fall")
        app.buttons["Add"].tap()
        let suggest = app.buttons["Suggest Hashtags"]
        if suggest.waitForExistence(timeout: 3) {
            suggest.tap()
            _ = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '#'")).firstMatch.waitForExistence(timeout: 60)
        } else {
            app.tap()
        }
        // Drag the text down into the keyboard to hide it, so the whole entry shows.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        sleep(1)
        shot("04-write")
        app.buttons["Cancel"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        sleep(1)

        // 5–6. Journal's Photos and Stats views, from the title menu.
        func journalView(_ current: String, _ mode: String) {
            let title = app.navigationBars.buttons[current].exists ? app.navigationBars.buttons[current] : app.navigationBars.staticTexts[current]
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            title.tap()
            // The menu's items, not the tab bar's buttons of the same name.
        let inMenu = app.collectionViews.buttons[mode]
        let item = inMenu.waitForExistence(timeout: 2) ? inMenu : app.buttons[mode].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.tap()
        }
        journalView("Journal", "Photos")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch.waitForExistence(timeout: 10))
        shot("05-photos")
        journalView("Photos", "Stats")
        XCTAssertTrue(app.staticTexts["Current Streak"].waitForExistence(timeout: 10))
        shot("06-stats")
        journalView("Stats", "Journal")

        // 7–8. Search: the hashtag cloud, then a hashtag's entries.
        tab("Search").tap()
        XCTAssertTrue(app.staticTexts["Your Hashtags This Year"].waitForExistence(timeout: 10))
        shot("07-hashtags")
        app.buttons["#hiking"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Yosemite")).firstMatch
            .waitForExistence(timeout: 10))
        if app.keyboards.count > 0 { app.swipeDown() }
        shot("08-search")
    }
}
