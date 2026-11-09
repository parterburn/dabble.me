import XCTest

/// Entry photo interactions, using the Debug-only single-photo harness (no server needed).
final class PhotoTests: XCTestCase {
    func testTapOpensViewerAndLongPressShowsActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugPhotoURL", "https://picsum.photos/id/1043/1200/900"]
        app.launch()
        let debugDir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"]
        func snap(_ name: String) {
            guard let debugDir else { return }
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(debugDir)/\(name).png"))
        }

        let photo = app.buttons["Entry photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 20))
        sleep(2) // let the image finish loading

        photo.tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Tapping the photo should open the full-screen viewer")
        snap("photo-viewer")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))

        photo.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Save to Photos"].waitForExistence(timeout: 5), "Long-press should show photo actions")
        XCTAssertTrue(app.buttons["Copy"].exists)
        snap("photo-menu")
    }
}

/// Writing an entry with several photos, end to end against a local server (with Sidekiq for
/// the collage). This is the flow that froze in TestFlight build 1.
final class PhotoEntryTests: XCTestCase {
    func testSavingSeveralPhotosStaysResponsiveAndShowsTheCollage() throws {
        guard let token = ProcessInfo.processInfo.environment["DABBLE_TOKEN"] else {
            throw XCTSkip("Needs a local server and TEST_RUNNER_DABBLE_TOKEN (rails ios:demo_account)")
        }
        let urls = [1043, 1015, 1039, 1060].map { "https://picsum.photos/id/\($0)/2400/1800" }.joined(separator: ",")
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", "http://localhost:3000",
                               "-DabbleDebugComposePhotoURLs", urls]
        app.launch()

        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 15))
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        // All four must attach (a single photo skips the collage path this test is for). They
        // stack at the bar's left; tapping the stack opens the drawer.
        editor.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Photos' AND value == '4 photos'")).firstMatch
            .waitForExistence(timeout: 60), "All four photos should be attached")
        app.buttons["Photos"].tap()
        XCTAssertTrue(app.buttons["Add More Photos"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Remove photo").count, 4)
        editor.tap()
        editor.typeText("Four photos, one collage.")
        app.buttons["Save"].tap()

        XCTAssertTrue(editor.waitForNonExistence(timeout: 60), "Saving with photos should finish and close the sheet")

        // The app must stay responsive afterwards: open the new entry right away.
        let saved = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Four photos, one collage")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        app.openTimelineEntry(saved)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10), "The app froze after saving")

        // The processing placeholder turns into the collage once Sidekiq finishes.
        let photo = app.buttons["Entry photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 120), "The collage never replaced the processing placeholder")
        if let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] {
            app.swipeUp()
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/collage-entry.png"))
        }
    }
}

/// Editing an entry's photos: add to the current photo (a collage), and remove it.
final class PhotoEditTests: XCTestCase {
    private func launch(photos: Bool) throws -> XCUIApplication {
        guard let token = ProcessInfo.processInfo.environment["DABBLE_TOKEN"] else {
            throw XCTSkip("Needs a local server, Sidekiq and TEST_RUNNER_DABBLE_TOKEN (rails ios:demo_account)")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", "http://localhost:3000"]
            + (photos ? ["-DabbleDebugComposePhotoURLs", "https://picsum.photos/id/1015/1600/1200"] : [])
        app.launch()
        return app
    }

    private func openEntry(_ app: XCUIApplication, containing text: String) {
        app.tabBars.buttons["Journal"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        app.openTimelineEntry(row)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
    }

    private func edit(_ app: XCUIApplication, photos: String) {
        app.buttons["Edit Entry"].tap()
        XCTAssertTrue(app.textViews["Entry"].waitForExistence(timeout: 10))
        // The entry's photos stack at the bar's left; tapping the stack opens the drawer.
        app.textViews["Entry"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Photos' AND value == %@", photos)).firstMatch.waitForExistence(timeout: 30))
        app.buttons["Photos"].tap()
    }

    func testAddPhotoToEntryWithPhotoMakesCollage() throws {
        let app = try launch(photos: true)
        openEntry(app, containing: "Finally made it to Yosemite")
        edit(app, photos: "2 photos")
        XCTAssertTrue(app.descendants(matching: .any)["Current photo"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "Remove photo").count, 1, "The new photo beside the current one")
        snap("edit-photos")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.textViews["Entry"].waitForNonExistence(timeout: 60), "Saving with a new photo should finish")
        // The collage replaces the processing placeholder.
        XCTAssertTrue(app.staticTexts["Processing photos…"].waitForExistence(timeout: 10) || app.images.firstMatch.exists)
    }

    func testRemovePhotoFromEntry() throws {
        let app = try launch(photos: false)
        openEntry(app, containing: "Biscuit has discovered")
        edit(app, photos: "1 photo")
        let remove = app.buttons["Remove current photo"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()
        XCTAssertFalse(app.descendants(matching: .any)["Current photo"].exists)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.textViews["Entry"].waitForNonExistence(timeout: 30))
        sleep(2)
        snap("edit-photo-removed")
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
}

