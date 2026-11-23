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

    /// I Already Have an Account opens the app's own form (no web page): an email, then the code
    /// screen, where Use Password Instead signs the demo account in. Needs the local server with
    /// `rails ios:demo_account` run (any TEST_RUNNER_DABBLE_TOKEN says it's there).
    func testSignInFormSignsInWithAPassword() throws {
        guard ProcessInfo.processInfo.environment["DABBLE_TOKEN"] != nil else {
            throw XCTSkip("Needs a local server and the demo account (rails ios:demo_account)")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugSignedOut", "YES", "-DabbleServerOverride", testServer]
        app.launch()
        let haveAccount = app.buttons["I Already Have an Account"]
        XCTAssertTrue(haveAccount.waitForExistence(timeout: 10))
        haveAccount.tap()

        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "A native form, not a web page")
        XCTAssertTrue(app.buttons["Sign In with a Passkey"].exists)
        XCTAssertFalse(app.secureTextFields["Password"].exists, "Email first: no password field")
        email.tap()
        email.typeText("demo@dabble.ex")
        app.buttons["Continue"].firstMatch.tap()

        // The code screen says where the code went, and offers the password.
        XCTAssertTrue(app.staticTexts["demo@dabble.ex"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Wrong email? Change It"].exists)
        XCTAssertTrue(app.buttons["Send a New Code"].exists)
        snap("sign-in-code")
        app.buttons["Use Password Instead"].tap()

        let password = app.secureTextFields["Password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("wrong-password")
        app.buttons["Sign In with Password"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Incorrect email or password."].waitForExistence(timeout: 10))
        snap("sign-in-wrong-password")

        password.tap()
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        password.typeText("dabble-demo")
        app.buttons["Sign In with Password"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 15) && !email.exists, "Signed in, the journal's tabs")
    }

    func testStartYourJournalOpensTheSignUpForm() {
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugSignedOut", "YES"]
        app.launch()
        let start = app.buttons["Start Your Journal"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["First Name (optional)"].exists, "Sign-up asks for no name")
        XCTAssertFalse(app.secureTextFields["Password"].exists, "Sign-up asks for no password")
        XCTAssertFalse(app.buttons["Continue"].isEnabled, "Nothing to send until there's an email")

        // A mistyped domain gets a suggestion before anything is sent.
        email.tap()
        email.typeText("someone@gmial.com")
        app.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Did you mean someone@gmail.com?"].waitForExistence(timeout: 5))
        snap("sign-up-form")
        app.buttons["I Already Have an Account"].tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
    }
}
