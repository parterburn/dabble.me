import XCTest

/// The signed-out experience: the wordmark, sign-up/sign-in, and a glimpse of each tab.
final class WelcomeTests: XCTestCase {
    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    func testSignedOutGlimpse() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugSignedOut", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Dabble Me"].waitForExistence(timeout: 10) || app.otherElements["Dabble Me"].exists)
        XCTAssertTrue(app.buttons["Start Your Journal"].exists)
        XCTAssertTrue(app.buttons["I Already Have an Account"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'passkey'")).firstMatch.exists)
        sleep(2)
        snap("welcome-today")
        for tab in ["Journal", "Search", "Settings"] {
            let button = app.tabBars.buttons[tab].exists ? app.tabBars.buttons[tab] : app.buttons[tab].firstMatch
            button.tap()
            sleep(1)
            XCTAssertTrue(app.buttons["Sign In"].firstMatch.waitForExistence(timeout: 5), "\(tab) offers sign in")
            snap("welcome-\(tab.lowercased())")
        }
    }
}
