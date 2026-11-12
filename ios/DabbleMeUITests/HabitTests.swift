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
        // Today's button, or the Journal's + once today has an entry.
        func startWriting() {
            if app.buttons["Write Today's Entry"].waitForExistence(timeout: 15) {
                app.buttons["Write Today's Entry"].tap()
            } else {
                app.tabBars.buttons["Journal"].tap()
                app.buttons["New Entry"].tap()
            }
        }
        startWriting()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        editor.typeText("A draft that should survive.")
        sleep(2) // autosave settles
        app.terminate()

        app = launch()
        startWriting()
        XCTAssertTrue(app.staticTexts["Restored your unsaved draft."].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews["Entry"].value as? String ?? "").contains("A draft that should survive."))
        snap("draft-restored")

        app.buttons["Start Over"].tap()
        XCTAssertFalse((app.textViews["Entry"].value as? String ?? "").contains("A draft that should survive."))
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    /// A blank new entry's Prompt button shows the prompt Today showed, and Cancel offers to keep
    /// what's written as a draft.
    func testPromptShowsTodaysAndCancelCanSaveADraft() throws {
        let app = launch()
        let write = app.buttons["Write Today's Entry"]
        XCTAssertTrue(write.waitForExistence(timeout: 15))
        sleep(3) // a prompt written on the device may replace the general one
        let todays = app.staticTexts["TodayPrompt"].label
        XCTAssertFalse(todays.isEmpty)
        write.tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        if app.buttons["Start Over"].exists { app.buttons["Start Over"].tap(); editor.tap() }
        app.buttons["Prompt"].tap()
        let question = app.staticTexts["AskMeQuestion"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        XCTAssertEqual(question.label, todays, "The prompt from Today")
        snap("compose-todays-prompt")
        app.buttons["Prompt"].tap() // closes the row
        editor.typeText("Saved for later.")
        app.buttons["Cancel"].tap()
        let saveDraft = app.buttons["Save Draft"]
        XCTAssertTrue(saveDraft.waitForExistence(timeout: 5))
        snap("compose-save-draft")
        saveDraft.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        write.tap()
        XCTAssertTrue(app.staticTexts["Restored your unsaved draft."].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews["Entry"].value as? String ?? "").contains("Saved for later."))
        app.buttons["Start Over"].tap()
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    func testRemindersScheduleNotifications() throws {
        let app = launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.tabBars.buttons["Settings"].tap()
        let daily = app.switches["Daily Reminder"]
        XCTAssertTrue(daily.waitForExistence(timeout: 10))
        if (daily.value as? String) != "1" { daily.switches.firstMatch.tap() }
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        // Its time (the daily email's until one is set) and entry previews, on to begin with.
        let previews = app.switches["Show Entry Previews"]
        XCTAssertTrue(previews.waitForExistence(timeout: 5))
        XCTAssertEqual(previews.value as? String, "1")
        XCTAssertFalse(app.switches["On This Day Memories"].exists, "One reminder now")

        let scheduled = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", "[1-9][0-9]* reminders scheduled")).firstMatch
        XCTAssertTrue(scheduled.waitForExistence(timeout: 15), "Turning reminders on should schedule notifications")
        snap("reminders-settings")
    }

    /// The daily reminder as it arrives: how the day was, with the entry to look back on (previews
    /// are on). Touch and hold it for Read the Memory, which opens that entry.
    func testDailyReminderShowsAMemoryAndOpensIt() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let app = launch(["-DabbleDebugReminderSoon", "YES"])
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        // On (it may be already, from an earlier run): the first one comes twelve seconds after
        // it's scheduled, by which time the app is in the background.
        let daily = app.switches["Daily Reminder"]
        XCTAssertTrue(daily.waitForExistence(timeout: 10))
        if (daily.value as? String) != "1" {
            daily.switches.firstMatch.tap()
            let allow = springboard.buttons["Allow"]
            if allow.waitForExistence(timeout: 3) { allow.tap() }
        }
        XCUIDevice.shared.press(.home)
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "How was your day?")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 25), "The reminder arrives")
        snap("reminder-banner")
        XCTAssertTrue(banner.label.contains("On This Day") || banner.label.contains("Rewind"), banner.label)
        banner.press(forDuration: 1.2)
        let read = springboard.buttons["Read the Memory"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        snap("reminder-expanded")
        read.tap()
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 15), "The memory opens")
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
        let locked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Unlock with")).firstMatch
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
