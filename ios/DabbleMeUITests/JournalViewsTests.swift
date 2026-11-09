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
        if app.buttons["Write Today's Entry"].waitForExistence(timeout: 15) {
            app.buttons["Write Today's Entry"].tap()
        } else {
            tab(app, "Journal").tap()
            app.buttons["New Entry"].tap()
        }
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
        XCTAssertTrue(app.staticTexts["Email"].waitForExistence(timeout: 5))
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
        // While it's expanded, the sticky header is the entry's date (not just the month).
        XCTAssertTrue(app.staticTexts[Calendar.current.date(byAdding: .day, value: -4, to: .now)!.formatted(.dateTime.weekday(.wide).month(.wide).day().year())].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Open"].exists, "No Open link on the expanded row")
        sleep(1)
        snap("timeline-expanded")

        // Dated #tags show as pills (with their age) once the row is expanded.
        // Swipe left: Open. Swipe right: Actions, with Edit (and the entry's tags).
        row.swipeLeft()
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Actions"].exists, "Actions is the right swipe now")
        row.swipeRight() // closes Open
        row.swipeRight()
        app.buttons["Actions"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(identifier: "ActionsSheetTag").matching(NSPredicate(format: "label == %@", "#work")).firstMatch.exists, "The entry's tags are in the Actions sheet")
        snap("timeline-actions-sheet")
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textViews["Entry"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.textViews["Entry"].waitForNonExistence(timeout: 10))

        row.swipeRight()
        app.buttons["Actions"].tap()
        let reflect = app.buttons["Reflect on This Entry"]
        if reflect.waitForExistence(timeout: 10) {
            snap("timeline-actions-reflect")
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
        // Text and a photo: the preview shows the whole entry, not a truncated start.
        let yosemite = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(yosemite.waitForExistence(timeout: 10))
        yosemite.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Sam singing badly")).firstMatch.exists,
                      "The preview shows the entry's text, not just the start")
        sleep(1)
        snap("preview-yosemite")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.8)).tap() // dismiss, away from the preview and menu
        XCTAssertTrue(app.buttons["Open"].waitForNonExistence(timeout: 5))
        sleep(1)

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
        if !app.staticTexts["Email"].waitForExistence(timeout: 5) { tab(app, "Settings").tap() }
        XCTAssertTrue(app.staticTexts["Email"].waitForExistence(timeout: 10))
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

    private func openDailyEmail(_ app: XCUIApplication) {
        tab(app, "Settings").tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Daily Email'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<3 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.buttons["Monday"].waitForExistence(timeout: 10))
    }

    private func pickTimeZone(_ app: XCUIApplication, _ name: String) {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Time Zone'")).firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(name)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Time Zone' AND label CONTAINS %@", name)).firstMatch.waitForExistence(timeout: 10))
    }

    private func pickHour(_ app: XCUIApplication, _ prefix: String, _ meridiem: String) {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Time,'")).firstMatch.tap()
        // iOS writes "7:00 AM" with a narrow no-break space before AM.
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", prefix, meridiem)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
        sleep(1)
    }

    /// Settings → Reminders → Daily Email: days, hour and time zone save to the account (PRO demo).
    func testEmailScheduleSaves() throws {
        var app = launch()
        openDailyEmail(app)
        let wasOn = (app.buttons["Monday"].value as? String) == "On"
        app.buttons["Monday"].tap()
        pickHour(app, "7:00", "PM") // the menu opens around the current 8 PM
        pickTimeZone(app, "Hawaii")
        sleep(1)
        snap("email-schedule")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Daily Email' AND label CONTAINS '7:00'")).firstMatch.waitForExistence(timeout: 5))
        snap("email-schedule-row")

        // Saved on the server: a fresh launch shows the same.
        app.terminate()
        app = launch()
        openDailyEmail(app)
        XCTAssertEqual((app.buttons["Monday"].value as? String) == "On", !wasOn)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '7:00' AND label CONTAINS 'PM'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Hawaii'")).firstMatch.exists)

        // Put the demo account back (its time zone is the journal's "today" for other tests).
        app.buttons["Monday"].tap()
        pickHour(app, "8:00", "PM")
        pickTimeZone(app, "Mountain")
    }

    /// Past entries in the email: on/off, words that leave entries out, and entries over a year old.
    func testDailyEmailPastEntries() throws {
        let app = launch()
        openDailyEmail(app)
        let include = app.switches["Include a Past Entry"]
        app.swipeUp()
        XCTAssertTrue(include.waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Include Entries Over a Year Old"].exists, "The demo account has entries over a year old")
        let words = app.textFields["Words, separated by commas"]
        words.tap()
        words.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "waffles\n")
        XCTAssertTrue(app.staticTexts["1 entry is left out of past entries."].waitForExistence(timeout: 10))
        snap("email-past-entries")

        // Off hides the rest; on brings it back, with the words saved.
        include.switches.firstMatch.tap()
        XCTAssertTrue(words.waitForNonExistence(timeout: 5))
        include.switches.firstMatch.tap()
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        XCTAssertEqual(words.value as? String, "waffles")

        // Put the demo account back.
        words.tap()
        words.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "\n")
        XCTAssertTrue(app.staticTexts["Each email can end with one of your past entries."].waitForExistence(timeout: 10))
    }

    /// Settings → Manage Hashtags: dated tags, adding one by name, and removing it.
    func testManageHashtags() throws {
        let app = launch()
        tab(app, "Settings").tap()
        app.buttons["Manage Hashtags"].tap()
        XCTAssertTrue(app.staticTexts["#Biscuit"].waitForExistence(timeout: 10), "The demo's dated #Biscuit")
        snap("manage-hashtags")
        app.buttons["Another Hashtag…"].tap()
        let name = app.textFields["Hashtag"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Leo")
        app.buttons["Add"].tap()
        let leo = app.staticTexts["#Leo"]
        XCTAssertTrue(leo.waitForExistence(timeout: 10))
        // Swipe to remove.
        app.cells.containing(.staticText, identifier: "#Leo").firstMatch.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(leo.waitForNonExistence(timeout: 10))
    }

    /// Pulling down far enough resets a tab: expanded entries collapse (Journal and Search).
    func testPullToResetCollapsesEntries() throws {
        let app = launch()
        func pullDown(_ list: XCUIElement) {
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            start.press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        }
        // Only an expanded entry shows its full date: the sticky header in Journal, a line in Search.
        let day = Calendar.current.date(byAdding: .day, value: -4, to: .now)!
        let header = app.staticTexts[day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())]
        let dateLine = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@",
            day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))).firstMatch

        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Big presentation went well")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5), "Expanded")
        pullDown(app.collectionViews.firstMatch)
        XCTAssertTrue(header.waitForNonExistence(timeout: 10), "Pulling down collapses it")

        tab(app, "Search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("presentation\n")
        let result = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Big presentation went well")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).tap() // away from #hashtag links
        XCTAssertTrue(dateLine.waitForExistence(timeout: 5), "Expanded in the results")
        pullDown(app.collectionViews.firstMatch)
        XCTAssertTrue(dateLine.waitForNonExistence(timeout: 10), "Pulling down collapses it")
        XCTAssertTrue(result.exists, "The results stay")
    }

    /// Quick date changes save in order, and the last pick wins, even going back to the original
    /// date (which used to be skipped, leaving the earlier change saved).
    func testTagDateRapidChangesKeepTheLastPick() throws {
        // The demo dates #Biscuit 3 years and 5 months back.
        let original = Calendar.current.date(byAdding: DateComponents(year: -3, month: -5), to: .now)!
        let step = Calendar.current.component(.day, from: original) <= 26 ? 1 : -1
        func day(_ offset: Int) -> String {
            Calendar.current.date(byAdding: .day, value: offset * step, to: original)!.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        func openBiscuit(_ app: XCUIApplication) -> XCUIElement {
            tab(app, "Settings").tap()
            app.buttons["Manage Hashtags"].tap()
            let cell = app.cells.containing(.staticText, identifier: "#Biscuit").firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 10))
            return cell.buttons.firstMatch
        }

        // Slow saves, so the picks overlap requests still in flight.
        var app = launch(["-DabbleDebugSlowWrites", "2500"])
        openBiscuit(app).tap()
        XCTAssertTrue(app.buttons[day(1)].waitForExistence(timeout: 5))
        app.buttons[day(1)].tap()
        app.buttons[day(2)].tap()
        app.buttons[day(0)].tap()
        app.buttons["dismiss popup"].tap()
        sleep(10) // let the saves finish

        app.terminate()
        app = launch()
        let picker = openBiscuit(app)
        let shown = original.formatted(.dateTime.month(.abbreviated).day().year())
        XCTAssertTrue(picker.label.contains(shown) || (picker.value as? String ?? "").contains(shown),
                      "Expected \(shown), got \(picker.label) \(picker.value ?? "")")
    }

    /// A free account sees Daily Email greyed out with the rest of Reminders. TEST_RUNNER_DABBLE_FREE_TOKEN.
    func testEmailScheduleFreeAccount() throws {
        guard let free = ProcessInfo.processInfo.environment["DABBLE_FREE_TOKEN"] else { throw XCTSkip("Needs TEST_RUNNER_DABBLE_FREE_TOKEN") }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", free, "-DabbleServerOverride", "http://localhost:3000"]
        app.launch()
        tab(app, "Settings").tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Daily Email'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(row.isEnabled)
        snap("email-schedule-free")
    }

    /// Shaking shows a random entry as a preview over what you're reading; Open goes to it.
    func testShakeForRandomMemory() throws {
        let app = launch()
        tab(app, "Journal").tap()
        XCTAssertFalse(app.buttons["Random Entry"].exists, "No shuffle button")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Big presentation went well")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap(); sleep(1); row.tap()
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))

        XCUIDevice.shared.system.open(URL(string: "me.dabble.app:/shake")!) // Debug stand-in for a shake
        XCTAssertTrue(app.staticTexts["A Random Memory"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10))
        sleep(1)
        snap("shake-memory")
        app.buttons["Another"].tap()
        sleep(1)
        // Close: still reading the same entry underneath.
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["A Random Memory"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Taking that one with me")).firstMatch.exists)

        XCUIDevice.shared.system.open(URL(string: "me.dabble.app:/shake")!)
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10))
        sleep(1)
        app.buttons["Open"].tap()
        XCTAssertTrue(app.staticTexts["A Random Memory"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))
    }

    /// Quick taps on several days all stick: saves go one at a time with the latest selection.
    func testEmailScheduleRapidTapsAllSave() throws {
        var app = launch()
        openDailyEmail(app)
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday"]
        let before = days.map { (app.buttons[$0].value as? String) == "On" }
        for day in days { app.buttons[day].tap() } // as fast as XCUITest taps
        sleep(3)

        app.terminate()
        app = launch()
        openDailyEmail(app)
        for (day, wasOn) in zip(days, before) {
            XCTAssertEqual((app.buttons[day].value as? String) == "On", !wasOn, "\(day) should have flipped and been saved")
        }
        // Put them back.
        for day in days { app.buttons[day].tap() }
        sleep(3)
    }

    /// An expanded timeline row shows the edited text right after saving an edit.
    func testExpandedRowShowsEdits() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Big presentation went well")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap() // expand
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Taking that one with me")).firstMatch.waitForExistence(timeout: 5))

        row.swipeRight()
        app.buttons["Actions"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 10))
        app.buttons["Edit"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText(" Edited from the timeline.")
        app.buttons["Save"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Edited from the timeline")).firstMatch.waitForExistence(timeout: 10),
                      "The expanded row should show the edit")
    }

    /// Swipe left → Actions lists the entry's tags; a dated tag shows its age right there.
    func testActionsSheetShowsDatedTagAge() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Biscuit has discovered")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap() // expand: the dated tag shows as a pill with its age
        let pill = app.buttons.matching(NSPredicate(format: "label == %@ AND value CONTAINS %@", "#Biscuit", "since entry")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        snap("expanded-dated-pill")
        row.swipeRight()
        app.buttons["Actions"].tap()
        let tag = app.buttons.matching(identifier: "ActionsSheetTag").matching(NSPredicate(format: "label == %@", "#Biscuit")).firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 10))
        XCTAssertTrue((tag.value as? String ?? "").contains("since entry"), "Dated tag shows its age")
        snap("actions-dated-tag")
        tag.tap() // searches it
        XCTAssertTrue(app.staticTexts["1 entry"].waitForExistence(timeout: 10))
    }

    /// On This Day rows are the Journal's rows: swipe left offers Open and Actions.
    func testOnThisDayRowsSwipe() throws {
        let app = launch()
        let memory = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bruges!")).firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1 year ago")).firstMatch.exists)
        memory.swipeRight()
        XCTAssertTrue(app.buttons["Actions"].waitForExistence(timeout: 3))
        memory.swipeLeft() // closes the Actions swipe
        memory.swipeLeft()
        app.buttons["Open"].tap()
        XCTAssertTrue(app.buttons["Entry Actions"].waitForExistence(timeout: 10))
    }
}
