import XCTest

/// App Store screenshots from the demo account (`rails ios:demo_account`; never a real journal).
/// Run on the 6.9" iPhone and 13" iPad simulators with TEST_RUNNER_DABBLE_TOKEN and
/// TEST_RUNNER_DABBLE_SCREENSHOT_DIR set. Not part of the regular suite's assertions.
final class ScreenshotTests: XCTestCase {
    func testAppStoreScreenshots() throws {
        let env = ProcessInfo.processInfo.environment
        let token = try XCTUnwrap(env["DABBLE_TOKEN"])
        let dir = try XCTUnwrap(env["DABBLE_SCREENSHOT_DIR"])
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

        // 4. Writing, with the formatting bar and photos.
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add More"].waitForExistence(timeout: 30))
        editor.tap()
        editor.typeText("Slow Saturday. Made pour-over with the beans from the farmers market and read on the porch until noon.\n\nGrateful for ")
        app.buttons["Bold"].tap()
        editor.typeText("quiet mornings")
        app.buttons["Bold"].tap()
        editor.typeText(".")
        shot("04-write")
        app.buttons["Cancel"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        sleep(1)

        // 5. Search.
        tab("Search").tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 10))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("#hiking\n")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Yosemite")).firstMatch
            .waitForExistence(timeout: 10))
        if app.keyboards.count > 0 { app.swipeDown() }
        shot("05-search")
    }
}
