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
                               "-DabbleDebugComposePhotoURLs", photos, "-entryTextSize", "2",
                               "-DabbleDebugCalendar", "YES", // a made-up day's events, for the lightbulb row
                               "-DabbleDebugDictation", "YES", // the simulator has no SpeechTranscriber, so the bar's mic would hide
                               "-stats.heatmapCell", "13"] // Stats' grid at its own size, whatever a test pinched it to
        app.launch()

        // iPhone has a bottom tab bar; iPad shows tabs at the top as plain buttons.
        func tab(_ name: String) -> XCUIElement {
            let bar = app.tabBars.buttons[name]
            return bar.exists ? bar : app.buttons.matching(identifier: name).firstMatch
        }

        func shot(_ name: String) {
            sleep(2) // let images finish loading
            // iPhone Duo: XCUIScreen gives the outer screen, dark while it's open, and the inner one
            // comes back black. With TEST_RUNNER_DABBLE_SCREENSHOT_DISPLAY set, a script on the Mac
            // takes the shot instead (`simctl io <device> screenshot --display=<n>`): this leaves a
            // `<name>.request` file in the folder and waits for the script to remove it.
            if env["DABBLE_SCREENSHOT_DISPLAY"] != nil {
                let request = URL(fileURLWithPath: "\(dir)/\(name).request")
                try? Data().write(to: request)
                for _ in 0..<60 where FileManager.default.fileExists(atPath: request.path) { usleep(500_000) }
                XCTAssertFalse(FileManager.default.fileExists(atPath: request.path), "No one took \(name)")
                return
            }
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }

        // Opens a timeline entry. On a short screen (iPhone Duo, either way up) the phone's way
        // scrolls a tall row's text off the top and taps its photo: move the list by a set amount
        // instead, then tap the text.
        func openEntry(_ row: XCUIElement, text: String) {
            guard app.windows.firstMatch.frame.height < 700 else { return app.openTimelineEntry(row) }
            _ = row.waitForExistence(timeout: 5)
            let label = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
            for _ in 0..<12 where !(label.exists && label.isHittable && label.frame.minY > 90 && label.frame.minY < 300) {
                // Not loaded yet: further down, a swipe away (the list's lazy).
                if !label.exists { app.collectionViews.firstMatch.swipeUp(velocity: .slow); continue }
                let up = label.frame.minY > 300
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: up ? 0.75 : 0.35))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: up ? -200 : 120)),
                            withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            // A long entry unfolds on the first tap and opens on the next. (Beside the pane, the
            // first opens it, in place of the one there.)
            label.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).tap()
            for _ in 0..<2 where !app.buttons["Edit Entry"].waitForExistence(timeout: 3) {
                label.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).tap()
            }
        }

        // Back from an entry. (By its label: on iPhone Duo closed it sits in the side rail, and
        // the bar's first button is Edit.)
        func back() {
            let button = app.buttons["Back"].firstMatch
            (button.exists ? button : app.navigationBars.buttons.element(boundBy: 0)).tap()
        }

        // 1. Today: prompt, write button, On This Day, and the last five days as dots.
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 20))
        sleep(3) // the dots come in a moment after Today
        shot("01-today")

        // 4. (Taken here, from Today.) A past entry with the same day in other years under it.
        let memory = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bruges! Wandered")).firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 10))
        openEntry(memory, text: "Bruges! Wandered")
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 10))
        // Up a little, so the last of the other years sits clear of the floating buttons.
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        if app.windows.firstMatch.frame.height < 700 {
            // A short screen (iPhone Duo's): the other years start below the photo, a swipe up.
            // (Not swipeUp(): from that low, it brings up the home indicator, which then stays.)
            let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.7))
            low.press(forDuration: 0.01, thenDragTo: low.withOffset(CGVector(dx: 0, dy: -360)))
        } else {
            middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -110)), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        shot("04-on-this-day")
        // (Scrolled that far, the bar's hidden: back up to it.)
        for _ in 0..<3 where !app.buttons["Back"].exists { app.scrollViews.firstMatch.swipeDown() }
        back()

        // Journal's Photos and Stats views, from the title menu.
        func journalView(_ current: String, _ mode: String) {
            let title = app.navigationBars.buttons[current].exists ? app.navigationBars.buttons[current] : app.navigationBars.staticTexts[current]
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            title.tap()
            // The menu's items, not the tab bar's buttons of the same name.
        let item = app.buttons["JournalMode-\(mode)"]
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.tap()
        }
        // 2. Journal timeline.
        tab("Journal").tap()
        // In the timeline, whichever view the app was left in (the Journal keeps it).
        for mode in ["Photos", "Songs", "Stats"] where app.navigationBars[mode].waitForExistence(timeout: 1) {
            journalView(mode, "Journal")
        }
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
        // A wide screen (iPhone Duo open, iPad) opens entries in a pane beside the list, not over it.
        // (The pane may come back with the entry it last showed.)
        let wide = app.staticTexts["No entry open"].waitForExistence(timeout: 3) || app.buttons["Edit Entry"].exists
        func openTimelineEntry(_ text: String) {
            openEntry(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch, text: text)
            XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        }

        // 3. An entry with formatting and a photo. On a wide screen the Journal shot has it open
        // beside the timeline, and the entry shot is another one.
        if wide {
            openTimelineEntry("Finally made it to Yosemite")
            shot("02-journal")
            openTimelineEntry("Day trip to the falls")
            shot("03-entry")
        } else {
            shot("02-journal")
            openTimelineEntry("Finally made it to Yosemite")
            shot("03-entry")
            back()
        }
        // Back to the top, where the title bar (and its New Entry) shows again.
        let first = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        for _ in 0..<8 where !(first.exists && first.isHittable) || !app.buttons["New Entry"].isHittable {
            app.collectionViews.firstMatch.swipeDown()
        }

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
        journalView("Journal", "Photos")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch.waitForExistence(timeout: 10))
        sleep(6) // the cells load full-size photos; on a cold cache two seconds showed one of eight
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
        if wide {
            // A result open in the pane beside the list.
            openTimelineEntry("Finally made it to Yosemite")
        }
        shot("10-search")
    }
}
