import XCTest

/// Journal's List / Stats / Photos views, the Search hashtag cloud, and list formatting,
/// against a local server with the demo account (rails ios:demo_account).
final class JournalViewsTests: XCTestCase {
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

    private func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.tabBars.buttons[name].exists ? app.tabBars.buttons[name] : app.buttons[name].firstMatch
    }

    private func switchJournal(_ app: XCUIApplication, from current: String, to mode: String) {
        let title = app.navigationBars.buttons[current].exists ? app.navigationBars.buttons[current] : app.navigationBars.staticTexts[current]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        // The menu's items, not the tab bar's buttons of the same name.
        let inMenu = app.collectionViews.buttons[mode]
        let item = inMenu.waitForExistence(timeout: 2) ? inMenu : app.buttons[mode].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
    }

    func testJournalStatsAndPhotos() throws {
        let app = launch()
        let journal = tab(app, "Journal")
        XCTAssertTrue(journal.waitForExistence(timeout: 15))
        journal.tap()

        switchJournal(app, from: "Journal", to: "Stats")
        XCTAssertTrue(app.staticTexts["Current Streak"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Entries per Month"].exists)
        sleep(1)
        snap("journal-stats")
        app.swipeUp()
        snap("journal-stats-2")

        switchJournal(app, from: "Stats", to: "Photos")
        let photo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        sleep(2)
        snap("journal-photos")
        photo.tap()
        XCTAssertTrue(app.navigationBars.buttons["Photos"].waitForExistence(timeout: 5) || app.navigationBars.buttons.firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()

        switchJournal(app, from: "Photos", to: "Journal")
        XCTAssertTrue(app.navigationBars.staticTexts["Journal"].waitForExistence(timeout: 5) || app.navigationBars.buttons["Journal"].exists)
    }

    func testSearchHashtagCloud() throws {
        let app = launch()
        let search = tab(app, "Search")
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        XCTAssertTrue(app.staticTexts["Your Hashtags This Year"].waitForExistence(timeout: 10))
        snap("search-cloud")
        let tag = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '#'")).firstMatch
        XCTAssertTrue(tag.exists)
        tag.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'entries' OR label ENDSWITH 'entry'")).firstMatch.waitForExistence(timeout: 10))
        // The search field stays at the top while the results scroll.
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.searchFields.firstMatch.isHittable)
        snap("search-sticky")
        // With a search submitted (keyboard gone, search still active), tapping Search again
        // still focuses the field.
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("trail\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        tab(app, "Search").tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Search tab focuses the field with a search showing")
    }

    /// Lists hang in the editor; PRO gets on-device hashtag suggestions (when Apple Intelligence is available).
    func testComposerListsAndSuggestions() throws {
        let app = launch()
        let write = app.buttons["Write Today's Entry"].waitForExistence(timeout: 15) ? app.buttons["Write Today's Entry"] : app.buttons["Add to Today's Entry"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        editor.typeText("Hiked the Mist Trail at Yosemite with Sam before sunrise. Things to remember:\n- The rainbow in the spray halfway up the trail, which lasted much longer than either of us expected\nCold sandwiches at the top")
        sleep(1)
        snap("compose-lists")
        // "- " became a bullet, and Return continued the list.
        let text = editor.value as? String ?? ""
        XCTAssertTrue(text.contains("• The rainbow"), text)
        XCTAssertTrue(text.contains("• Cold sandwiches"), text)
        XCTAssertFalse(app.buttons["Bold"].exists)
        XCTAssertFalse(app.toolbars.buttons["Dictate"].exists, "Dictation is the keyboard's own")

        app.buttons["Add"].tap()
        let suggest = app.buttons["Suggest Hashtags"]
        if suggest.waitForExistence(timeout: 3) {
            suggest.tap()
            let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '#'")).firstMatch
            XCTAssertTrue(chip.waitForExistence(timeout: 60))
            snap("compose-hashtags")
            chip.tap()
        } else {
            print("AI_UNAVAILABLE")
            app.tap() // close the menu
        }
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    func testTodayPromptEntrySummaryAndSettings() throws {
        let app = launch()
        // With Apple Intelligence on, Today writes its own prompt (no button to ask for one).
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Prompt from My Recent Entries"].exists)
        let another = app.buttons["Another Prompt"]
        if another.waitForExistence(timeout: 60) {
            snap("today-ai-prompt")
            another.tap()
            XCTAssertTrue(another.waitForExistence(timeout: 60))
        } else {
            print("AI_UNAVAILABLE_OR_ENTRY_WRITTEN")
        }

        tab(app, "Journal").tap()
        let firstEntry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(firstEntry.waitForExistence(timeout: 10))
        firstEntry.tap() // expands in the timeline
        sleep(1)
        firstEntry.tap() // opens
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))
        sleep(1)
        snap("entry-lists")
        // The title is the date; tapping it shows how long ago it was, and back.
        let title = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", 2026")).firstMatch
        XCTAssertTrue(title.exists)
        title.tap()
        sleep(1)
        snap("entry-relative-date")
        title.tap()
        app.buttons["Entry Actions"].tap()
        let reflect = app.buttons["Reflect on This Entry"]
        if reflect.waitForExistence(timeout: 3) {
            reflect.tap()
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 90))
            snap("entry-reflection")
            app.buttons["Done"].tap()
        } else {
            app.tap() // close the menu
        }

        // Tapping Search again focuses the search field.
        tab(app, "Search").tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        tab(app, "Search").tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let close = app.buttons.matching(NSPredicate(format: "label IN {'Close', 'Cancel'}")).firstMatch
        XCTAssertTrue(close.exists)
        close.tap()

        tab(app, "Settings").tap()
        XCTAssertTrue(app.staticTexts["Entry Text Size"].waitForExistence(timeout: 5))
        snap("settings-top")
        app.swipeUp()
        snap("settings-privacy")
    }

    private func pullUp(_ app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
    }

    /// Tapping a #hashtag in an entry opened from search results goes back to the results for it.
    func testHashtagFromSearchResultEntry() throws {
        let app = launch()
        tab(app, "Search").tap()
        XCTAssertTrue(app.buttons["#hiking"].waitForExistence(timeout: 10))
        app.buttons["#hiking"].tap()
        let yosemite = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(yosemite.waitForExistence(timeout: 10))
        yosemite.tap() // expands
        yosemite.tap() // opens
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))
        let tag = app.links["#hiking"].firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        tag.tap()
        XCTAssertTrue(app.staticTexts["2 entries"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Entry Actions"].exists, "The entry should close to show the results")
    }

    /// First tap expands an entry in the timeline; a second opens it. Swipes reveal Reflect and
    /// Edit; on the entry, swiping left shows its actions.
    func testTimelineExpandSwipeAndEntryActions() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Big presentation went well")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        // Expanded: the rest of the entry shows in place.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Taking that one with me")).firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        snap("timeline-expanded")

        row.swipeLeft()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 3))
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textViews["Entry"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.textViews["Entry"].waitForNonExistence(timeout: 10))

        row.swipeRight()
        let reflect = app.buttons["Reflect"]
        if reflect.waitForExistence(timeout: 3) {
            snap("timeline-swipe-reflect")
            reflect.tap()
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 90))
            app.buttons["Done"].tap()
        }

        let expanded = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Big presentation went well")).firstMatch
        expanded.tap() // second tap opens
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))
        app.scrollViews.firstMatch.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5), "Swiping left on the entry shows its actions")
        snap("entry-swipe-actions")
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textViews["Entry"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
    }

    /// Long-press an entry to preview it; long-press a dated #hashtag to see how old it was.
    func testLongPressPreviewAndHashtagAge() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Biscuit has discovered")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1.2)
        let open = app.buttons["Open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        sleep(1)
        snap("entry-preview")
        open.tap()
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))

        let chip = app.buttons["#Biscuit"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.press(forDuration: 1.2)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "since entry")).firstMatch.waitForExistence(timeout: 5))
        snap("hashtag-age")
    }

    /// With no hashtags yet, suggestions aren't limited to (an empty) vocabulary. Needs a PRO
    /// account with no entries: TEST_RUNNER_DABBLE_EMPTY_TOKEN.
    func testHashtagSuggestionsForNewWriter() throws {
        guard let empty = ProcessInfo.processInfo.environment["DABBLE_EMPTY_TOKEN"] else {
            throw XCTSkip("Set TEST_RUNNER_DABBLE_EMPTY_TOKEN to a PRO account with no hashtags")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", empty, "-DabbleServerOverride", "http://localhost:3000"]
        app.launch()
        let write = app.buttons["Write Today's Entry"]
        XCTAssertTrue(write.waitForExistence(timeout: 15))
        write.tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        editor.typeText("Took the kids to the climbing gym after school. Maya made it to the top of the blue wall.")
        app.buttons["Add"].tap()
        let suggest = app.buttons["Suggest Hashtags"]
        guard suggest.waitForExistence(timeout: 3) else { throw XCTSkip("Apple Intelligence isn't available here") }
        suggest.tap()
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '#'")).firstMatch
        let found = chip.waitForExistence(timeout: 60)
        snap("hashtags-new-writer")
        XCTAssertTrue(found, app.alerts.firstMatch.exists ? app.alerts.firstMatch.debugDescription : "no suggestions")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))

        tab(app, "Settings").tap()
        if !app.staticTexts["Entry Text Size"].waitForExistence(timeout: 5) { tab(app, "Settings").tap() }
        XCTAssertTrue(app.staticTexts["Entry Text Size"].waitForExistence(timeout: 10))
        print("PLAN_LINK=\(app.links.matching(NSPredicate(format: "label CONTAINS 'Plan'")).firstMatch.exists)")
        snap("settings-plan")
    }

    /// On This Day cards preview like entries elsewhere: the whole entry, not just the card's excerpt.
    func testOnThisDayPreview() throws {
        let app = launch()
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bruges!")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 5))
        sleep(2)
        snap("today-preview")
    }

    /// Today's AI prompt treats earlier entries as earlier (EMPTY token account seeded with a
    /// "yesterday" basketball entry). Prints each prompt for review.
    func testAIPromptKeepsPastInThePast() throws {
        guard let token = ProcessInfo.processInfo.environment["DABBLE_EMPTY_TOKEN"] else { throw XCTSkip("Needs TEST_RUNNER_DABBLE_EMPTY_TOKEN") }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", "http://localhost:3000"]
        app.launch()
        let another = app.buttons["Another Prompt"]
        guard another.waitForExistence(timeout: 60) else { throw XCTSkip("Apple Intelligence isn't available here") }
        for round in 0..<4 {
            let prompt = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH '?'")).firstMatch
            print("PROMPT\(round)=\(prompt.label)")
            another.tap()
            sleep(1)
            XCTAssertTrue(another.waitForExistence(timeout: 60))
        }
        snap("ai-prompt-dated")
    }

    /// Tapping Journal again from Stats (or deep in the list) goes back to the list's newest entry.
    func testJournalTabRetapReturnsToTopOfList() throws {
        let app = launch()
        tab(app, "Journal").tap()
        switchJournal(app, from: "Journal", to: "Stats")
        XCTAssertTrue(app.staticTexts["Current Streak"].waitForExistence(timeout: 10))
        tab(app, "Journal").tap()
        let newest = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Current Streak"].exists)

        app.swipeUp(); app.swipeUp(); app.swipeUp()
        XCTAssertFalse(newest.isHittable)
        tab(app, "Journal").tap()
        sleep(1)
        XCTAssertTrue(newest.isHittable, "Back at the top")
    }

    /// Pulling down on an entry asks Apple Intelligence for a reflection.
    func testPullDownOnEntryReflects() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap(); sleep(1); row.tap()
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        guard app.buttons["Done"].waitForExistence(timeout: 90) else {
            throw XCTSkip("Apple Intelligence isn't available here")
        }
        XCTAssertTrue(app.navigationBars["Reflection"].exists || app.staticTexts["Reflection"].exists)
        snap("pull-reflection")
        app.buttons["Done"].tap()
    }
}
