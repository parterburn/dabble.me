import XCTest

/// Draft autosave, reminders, and the Face ID lock, against a local server.
final class HabitTests: XCTestCase {
    var token: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let token = ProcessInfo.processInfo.environment["DABBLE_TOKEN"] else {
            throw XCTSkip("Needs a local server and TEST_RUNNER_DABBLE_TOKEN (rails ios:demo_account)")
        }
        self.token = token
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", "http://localhost:3000"] + extra
        app.launch()
        return app
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    func testDraftSurvivesQuittingTheApp() throws {
        var app = launch()
        let write = app.buttons["Write Today's Entry"].exists ? app.buttons["Write Today's Entry"] : app.buttons["Add to Today's Entry"]
        XCTAssertTrue(write.waitForExistence(timeout: 15))
        write.tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        editor.typeText("A draft that should survive.")
        sleep(2) // autosave settles
        app.terminate()

        app = launch()
        XCTAssertTrue(write.waitForExistence(timeout: 15))
        app.buttons[write.label].tap()
        XCTAssertTrue(app.staticTexts["Restored your unsaved draft."].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews["Entry"].value as? String ?? "").contains("A draft that should survive."))
        snap("draft-restored")

        app.buttons["Start Over"].tap()
        XCTAssertFalse((app.textViews["Entry"].value as? String ?? "").contains("A draft that should survive."))
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    func testRemindersScheduleNotifications() throws {
        let app = launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.tabBars.buttons["Settings"].tap()
        let writing = app.switches["Daily Writing Reminder"]
        XCTAssertTrue(writing.waitForExistence(timeout: 10))
        if (writing.value as? String) != "1" { writing.switches.firstMatch.tap() }
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let memories = app.switches["On This Day Memories"]
        if (memories.value as? String) != "1" { memories.switches.firstMatch.tap() }

        let scheduled = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[1-9][0-9]* reminders scheduled")).firstMatch
        XCTAssertTrue(scheduled.waitForExistence(timeout: 15), "Turning reminders on should schedule notifications")
        snap("reminders-settings")
    }

    /// Needs Face ID enrolled on the simulator and a host-side helper that sends one face match
    /// whenever this test creates `$DABBLE_DEBUG_DIR/faceid-match` (see ios/README.md).
    func testFaceIDLockLocksAndUnlocks() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["DABBLE_FACE_ID"] == "1", let dir = env["DABBLE_DEBUG_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_DABBLE_FACE_ID=1 and TEST_RUNNER_DABBLE_DEBUG_DIR with the face-match helper running")
        }
        func matchFace() {
            FileManager.default.createFile(atPath: "\(dir)/faceid-match", contents: Data())
        }
        let app = launch(["-lock.enabled", "YES", "-DabbleLockGrace", "0"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let locked = app.staticTexts["Dabble Me is locked"]
        let journal = app.tabBars.buttons["Journal"]

        XCTAssertTrue(locked.waitForExistence(timeout: 15), "The app should open locked")
        if springboard.buttons["OK"].waitForExistence(timeout: 3) { springboard.buttons["OK"].tap() } // Face ID permission
        matchFace()
        XCTAssertTrue(journal.waitForExistence(timeout: 15), "Face ID should unlock the app")

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(locked.waitForExistence(timeout: 10), "Coming back should lock again")
        snap("locked")
        sleep(2)
        XCTAssertTrue(locked.exists, "It should stay locked until Face ID succeeds")
        matchFace()
        XCTAssertTrue(journal.waitForExistence(timeout: 15), "And unlock again with Face ID")
    }
}
