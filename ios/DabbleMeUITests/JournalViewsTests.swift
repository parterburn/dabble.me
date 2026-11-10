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
        // The default square size, whatever an earlier run pinched it to (the tap below is measured).
        let app = launch(["-stats.heatmapCell", "13"])
        let journal = tab(app, "Journal")
        XCTAssertTrue(journal.waitForExistence(timeout: 15))
        journal.tap()

        switchJournal(app, from: "Journal", to: "Stats")
        XCTAssertTrue(app.staticTexts["Current Streak"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Entries per Month"].exists)
        sleep(1)
        snap("journal-stats")

        // Past Year: tapping yesterday's square (the demo always wrote yesterday) opens its entries
        // in the drawer, every time. Today is in the newest column at its weekday's row (Sunday on
        // top), so yesterday is the row above, or the bottom of the column before on a Sunday.
        let heatmap = app.otherElements["Writing days in the past year"]
        XCTAssertTrue(heatmap.waitForExistence(timeout: 5))
        let pitch: CGFloat = 13 + 3, monthRow: CGFloat = 2 + 16 + 4
        let todayRow = Calendar(identifier: .gregorian).component(.weekday, from: .now) - 1
        let (column, row) = todayRow == 0 ? (1, 6) : (0, todayRow - 1)
        let yesterday = CGVector(dx: heatmap.frame.width - 6.5 - CGFloat(column) * pitch,
                                 dy: monthRow + CGFloat(row) * pitch + 6.5)
        for attempt in 1...3 {
            heatmap.coordinate(withNormalizedOffset: .zero).withOffset(yesterday).tap()
            XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10), "The day's entries open (try \(attempt))")
            if attempt == 1 { sleep(1); snap("stats-day-sheet") }
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["Open"].waitForNonExistence(timeout: 5))
        }

        // Pinch out for bigger squares (kept for next time), then back.
        heatmap.pinch(withScale: 2, velocity: 1)
        sleep(1)
        snap("stats-heatmap-zoomed")
        heatmap.pinch(withScale: 0.5, velocity: -1)

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

        app.buttons["Hashtags"].tap() // the row: Suggest, then recent tags
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
        app.openTimelineEntry(firstEntry)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        sleep(1)
        snap("entry-lists")
        // The title is the date; tapping it shows how long ago it was, and back.
        let title = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", 2026")).firstMatch
        XCTAssertTrue(title.exists)
        title.tap()
        sleep(1)
        snap("entry-relative-date")
        title.tap()
        app.swipeLeft() // the entry's Actions
        let reflect = app.buttons["Reflection"]
        if reflect.waitForExistence(timeout: 3) {
            reflect.tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5), "The reflection's sheet opens right away")
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Written on this device")).firstMatch.waitForExistence(timeout: 90))
            snap("entry-reflection")
            app.buttons["Close"].tap()
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
        app.openTimelineEntry(yosemite)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        let tag = app.links["#hiking"].firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        tag.tap()
        XCTAssertTrue(app.staticTexts["2 matching entries"].waitForExistence(timeout: 10))
        // Results sit under sticky month headers, like the Journal.
        let month = Calendar.current.date(byAdding: .day, value: -1, to: .now)!.formatted(.dateTime.month(.wide).year())
        XCTAssertTrue(app.staticTexts[month].exists, "A month header over the results")
        XCTAssertFalse(app.buttons["Edit Entry"].exists, "The entry should close to show the results")
    }

    /// A long entry's preview says "Show more" and a tap expands it in place (the month header
    /// stays); a short one, or an expanded one, opens on a tap. Swipe left to Open, right for
    /// Actions; on the entry, swiping left shows its actions.
    func testTimelineExpandSwipeAndEntryActions() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let long = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(long.waitForExistence(timeout: 10))
        let collapsed = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Finally made it to Yosemite", "Show more")).firstMatch
        XCTAssertTrue(collapsed.exists, "A long entry's preview says Show more")
        long.tapRowText()
        XCTAssertTrue(collapsed.waitForNonExistence(timeout: 5), "Tapping it expands it in place")
        XCTAssertFalse(app.buttons["Edit Entry"].exists, "Expanding doesn't open it")
        let month = Calendar.current.date(byAdding: .day, value: -1, to: .now)!.formatted(.dateTime.month(.wide).year())
        XCTAssertTrue(app.staticTexts[month].exists, "The sticky header stays the month")
        sleep(1)
        snap("timeline-expanded")

        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Big presentation went well")).firstMatch
        app.scrollTo(row)
        // Swipe left: Actions, with Edit (and the entry's tags). There's no right swipe.
        row.swipeRow(left: false)
        XCTAssertFalse(app.buttons["Actions"].waitForExistence(timeout: 2), "Nothing on a right swipe")
        row.swipeRow(left: true)
        // A long swipe opens the sheet straight away; a shorter one shows the Actions button.
        if app.buttons["Actions"].waitForExistence(timeout: 2) { app.buttons["Actions"].tap() }
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(identifier: "ActionsSheetTag").matching(NSPredicate(format: "label == %@", "#work")).firstMatch.exists, "The entry's tags are in the Actions sheet")
        snap("timeline-actions-sheet")
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textViews["Entry"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.textViews["Entry"].waitForNonExistence(timeout: 10))

        row.swipeLeft()
        app.buttons["Actions"].tap()
        let reflect = app.buttons["Reflection"]
        if reflect.waitForExistence(timeout: 10) {
            snap("timeline-actions-reflect")
            reflect.tap()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 90))
            app.buttons["Close"].tap()
        }

        app.openTimelineEntry(row)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
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
        // Text and a photo: the preview shows the whole entry, not a truncated start.
        let yosemite = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(yosemite.waitForExistence(timeout: 10))
        yosemite.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Sam singing badly")).firstMatch.exists,
                      "The preview shows the entry's text, not just the start")
        sleep(1)
        snap("preview-yosemite")
        // Tapping the preview grows it into the entry.
        // The preview sits just above its menu.
        let menuTop = app.buttons.matching(NSPredicate(format: "label IN %@", ["Reflection", "Edit", "Open"]))
            .allElementsBoundByIndex.map { $0.frame.minY }.min() ?? app.buttons["Open"].frame.minY
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: menuTop - 150)).tap()
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10), "Tapping the preview opens the entry")
        XCTAssertTrue(app.buttons["Open"].waitForNonExistence(timeout: 5))
        sleep(1)
        snap("preview-opened")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)

        app.scrollTo(row)
        row.press(forDuration: 1.2)
        let open = app.buttons["Open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        sleep(1)
        snap("entry-preview")
        open.tap()
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))

        let chip = app.buttons["#Biscuit"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.press(forDuration: 1.2)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "since entry")).firstMatch.waitForExistence(timeout: 5))
        snap("hashtag-age")
    }

    /// With no hashtags yet, suggestions aren't limited to (an empty) vocabulary. Needs a PRO
    /// With nothing on this date in past years and no earlier entries, Today shows Throwback with
    /// a nudge to write. TEST_RUNNER_DABBLE_EMPTY_TOKEN (an account with no past entries).
    func testThrowbackNudgeWithoutPastEntries() throws {
        guard let empty = ProcessInfo.processInfo.environment["DABBLE_EMPTY_TOKEN"] else {
            throw XCTSkip("Set TEST_RUNNER_DABBLE_EMPTY_TOKEN to an account with no entries")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", empty, "-DabbleServerOverride", "http://localhost:3000"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Throwback"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["On This Day"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "This is where your past entries come back")).firstMatch.exists)
        snap("today-throwback-empty")
    }

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
        app.buttons["Hashtags"].tap() // the row: Suggest, then recent tags
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

    /// On This Day rows show dated #tags (how old Biscuit was) above the photo, like the Journal's.
    func testOnThisDayShowsDatedTags() throws {
        let app = launch()
        // Below the fold under the photo memories: scroll down to it.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bruges!")).firstMatch.waitForExistence(timeout: 15))
        let memory = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Biscuit ate the carrot nose")).firstMatch
        app.scrollTo(memory)
        XCTAssertTrue(memory.exists)
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "#Biscuit")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "The memory shows its dated tag")
        snap("on-this-day-dated-tag")
    }

    /// Pulling down on an entry asks Apple Intelligence for a reflection.
    func testPullDownOnEntryReflects() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        app.openTimelineEntry(row)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        guard app.buttons["Close"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Apple Intelligence isn't available here")
        }
        // The sheet opens first, reflecting inside it, then the text arrives.
        XCTAssertTrue(app.navigationBars["Reflection"].exists || app.staticTexts["Reflection"].exists)
        XCTAssertTrue(app.staticTexts["Generating…"].exists, "The sheet shows it's reflecting")
        snap("pull-reflecting")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Written on this device")).firstMatch.waitForExistence(timeout: 90))
        XCTAssertFalse(app.staticTexts["Generating…"].exists)
        snap("pull-reflection")
        app.buttons["Close"].tap()
    }

    /// After a reflection, answering its question starts a short chat (on the device): a reply
    /// streams in, the note says it isn't saved, and reopening starts fresh.
    func testReflectionChat() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        app.openTimelineEntry(row)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        func pullForReflection() {
            let scroll = app.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        }
        pullForReflection()
        guard app.buttons["Close"].waitForExistence(timeout: 5) else { throw XCTSkip("Apple Intelligence isn't available here") }
        let written = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Written on this device")).firstMatch
        XCTAssertTrue(written.waitForExistence(timeout: 90))

        let field = app.textFields["ReflectionReply"].exists ? app.textFields["ReflectionReply"] : app.textViews["ReflectionReply"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "A field to answer the reflection")
        field.tap()
        field.typeText("Honestly the sunrise on the trail was the best part.")
        app.buttons["Send"].tap()
        sleep(1)
        XCTAssertFalse((field.value as? String ?? "").contains("sunrise"), "Sending clears the field")
        // A shake while the reflection is up leaves it there (no random memory in its place).
        XCUIDevice.shared.system.open(URL(string: "me.dabble.app:/shake")!) // Debug stand-in for a shake
        XCTAssertFalse(app.staticTexts["A Random Memory"].waitForExistence(timeout: 3), "A shake doesn't replace the reflection")
        XCTAssertTrue(app.buttons["Send"].exists)
        let reply = app.descendants(matching: .any).matching(identifier: "ReflectionChatReply").firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 90), "Apple Intelligence replies")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "not saved anywhere")).firstMatch.exists)
        sleep(2)
        snap("reflection-chat")

        // After the first answer: an offer to sum it up and add it to the entry.
        let sumUp = app.buttons["Sum Up & Add to Entry"]
        XCTAssertTrue(sumUp.waitForExistence(timeout: 10), "It offers to add a summary to the entry")
        sumUp.tap()
        let summary = app.staticTexts["ReflectionSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 60), "A summary to look over first")
        let summed = summary.label
        snap("reflection-summary")
        sleep(1) // the buttons fade in with the summary
        app.buttons["Add to Entry"].tap()
        XCTAssertTrue(app.staticTexts["Added to this day's entry."].waitForExistence(timeout: 15))
        app.buttons["Close"].tap()
        let added = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@",
                                                                         String(summed.prefix(30)), String(summed.prefix(30)))).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10), "The summary is in the entry")
        app.swipeUp()
        snap("entry-with-reflection")
        app.swipeDown() // back to the top, where pulling down asks for a reflection
        sleep(1)

        pullForReflection()
        XCTAssertTrue(written.waitForExistence(timeout: 90))
        XCTAssertFalse(reply.exists, "The chat isn't kept: reopening starts fresh")
        app.buttons["Close"].tap()
    }

    /// Prompt (the sparkles) while writing: always there; on an empty page it offers a way in from
    /// recent entries, and once there's writing it asks about that. Add puts it in the entry.
    func testPromptWhileWriting() throws {
        let app = launch()
        tab(app, "Journal").tap()
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        // A draft left by an earlier run comes back: start from a blank page.
        if app.buttons["Start Over"].exists { app.buttons["Start Over"].tap(); editor.tap() }
        // On an empty page: a prompt from recent entries, to get started.
        let prompt = app.buttons["Prompt"]
        guard prompt.waitForExistence(timeout: 5) else { throw XCTSkip("Apple Intelligence isn't available here") }
        prompt.tap()
        XCTAssertTrue(app.staticTexts["AskMeQuestion"].waitForExistence(timeout: 60), "A prompt to start with")
        snap("prompt-empty")
        prompt.tap() // close it
        editor.tap()
        editor.typeText("Took Biscuit to the lake this morning. He chased the ducks and then fell asleep in the car on the way home.")
        // No random memory over the composer, even with the keyboard down.
        app.swipeDown()
        XCUIDevice.shared.system.open(URL(string: "me.dabble.app:/shake")!) // Debug stand-in for a shake
        XCTAssertFalse(app.staticTexts["A Random Memory"].waitForExistence(timeout: 3), "No random memory while writing")
        XCTAssertTrue(editor.exists)
        editor.tap()
        prompt.tap()
        let question = app.staticTexts["AskMeQuestion"]
        // "Generating prompt…" while it works (it can be quick enough to miss).
        XCTAssertTrue(app.staticTexts["Generating prompt…"].waitForExistence(timeout: 5) || question.exists)
        XCTAssertTrue(question.waitForExistence(timeout: 60), "Prompt asks a question")
        let asked = question.label
        XCTAssertTrue(asked.hasSuffix("?"), "It's a question: \(asked)")
        snap("prompt-row")
        app.buttons["Add"].tap()
        XCTAssertTrue((editor.value as? String ?? "").contains(asked), "Add puts the question in the entry")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    /// From Today: an entry's reflection closes with a pull down (Today's pull to reset doesn't
    /// leak into its sheets or entry pages).
    func testPullDownClosesReflectionFromToday() throws {
        let app = launch()
        let memory = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bruges!")).firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 15))
        app.openTimelineEntry(memory)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        guard app.buttons["Close"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Apple Intelligence isn't available here")
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Written on this device")).firstMatch.waitForExistence(timeout: 90))
        XCTAssertFalse(app.activityIndicators.firstMatch.exists, "No refresh spinner on the entry")
        // Pull down on the reflection's text (the sheet opens half height, its text near the bottom).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)),
                   withVelocity: .fast, thenHoldForDuration: 0)
        snap("reflection-after-pull")
        XCTAssertTrue(app.buttons["Close"].waitForNonExistence(timeout: 5), "Pulling down closes the reflection")
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
        // A long entry's preview says "Show more"; expanded, it doesn't.
        let collapsed = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Finally made it to Yosemite", "Show more")).firstMatch
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch

        tab(app, "Journal").tap()
        XCTAssertTrue(collapsed.waitForExistence(timeout: 10))
        row.tapRowText()
        XCTAssertTrue(collapsed.waitForNonExistence(timeout: 5), "Expanded")
        pullDown(app.collectionViews.firstMatch)
        XCTAssertTrue(collapsed.waitForExistence(timeout: 10), "Pulling down collapses it")

        tab(app, "Search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Yosemite\n")
        let result = row
        XCTAssertTrue(collapsed.waitForExistence(timeout: 10))
        result.tapRowText()
        XCTAssertTrue(collapsed.waitForNonExistence(timeout: 5), "Expanded in the results")
        pullDown(app.collectionViews.firstMatch)
        XCTAssertTrue(collapsed.waitForExistence(timeout: 10), "Pulling down collapses it")
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
        app.buttons["Done"].tap()
        sleep(10) // let the saves finish

        app.terminate()
        app = launch()
        let picker = openBiscuit(app)
        let shown = original.formatted(.dateTime.month(.abbreviated).day().year())
        XCTAssertTrue(picker.label.contains(shown) || (picker.value as? String ?? "").contains(shown),
                      "Expected \(shown), got \(picker.label) \(picker.value ?? "")")
    }

    /// Settings → Accessibility: the text size and font change entry text across the app, not just
    /// an open entry.
    func testAccessibilitySettingsApplyToTimeline() throws {
        let app = launch()
        func accessibility(_ change: () -> Void) {
            tab(app, "Settings").tap()
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Accessibility")).firstMatch
            for _ in 0..<5 where !link.isHittable { app.collectionViews.firstMatch.swipeUp() }
            link.tap()
            change()
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        func setSize(_ label: String) {
            // The slider's stops: Small, Default, Large, Extra Large, Largest.
            let stops = ["Small": 0.0, "Default": 0.25, "Largest": 1.0]
            app.sliders["Entry Text Size"].adjust(toNormalizedSliderPosition: stops[label]!)
        }
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Ran 5 miles without stopping")).firstMatch
        accessibility { setSize("Small") }
        tab(app, "Journal").tap()
        app.scrollTo(row)
        let small = row.frame.width * row.frame.height

        accessibility {
            setSize("Largest")
            app.buttons["Sans Serif"].tap()
            app.buttons["Night"].tap()
            snap("accessibility-settings")
        }
        tab(app, "Journal").tap()
        app.scrollTo(row)
        XCTAssertGreaterThan(row.frame.width * row.frame.height, small * 1.3, "The timeline's text is larger")
        snap("accessibility-timeline")

        accessibility { // back to the defaults for other runs
            setSize("Default")
            app.buttons["Serif"].tap()
            app.buttons["System"].tap()
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Default, Serif")).firstMatch.waitForExistence(timeout: 5))
    }

    /// A web address written into an entry is a link.
    /// Long-pressing a row's preview offers More, which opens its Actions sheet; long-pressing
    /// an entry's Edit button does the same (a tap still edits).
    func testMoreActionsFromPreviewAndEditButton() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Biscuit has discovered")).firstMatch
        app.scrollTo(row)
        row.press(forDuration: 1.2)
        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "The preview's menu has More")
        snap("preview-more")
        more.tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 10), "More opens the Actions sheet")
        XCTAssertTrue(app.buttons.matching(identifier: "ActionsSheetTag").firstMatch.exists, "with the entry's tags as pills")
        snap("actions-pills")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap() // close it (above the sheet)
        XCTAssertTrue(app.buttons["Delete"].waitForNonExistence(timeout: 5))

        app.openTimelineEntry(row)
        let edit = app.buttons["Edit Entry"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5), "Holding Edit opens the Actions sheet")
        XCTAssertFalse(app.textViews["Entry"].exists, "and doesn't start editing")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["Delete"].waitForNonExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.textViews["Entry"].waitForExistence(timeout: 10), "A tap still edits")
        app.buttons["Cancel"].tap()
    }

    func testURLsInEntriesAreLinks() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "The Overstory")).firstMatch
        app.scrollTo(row, maxSwipes: 20) // a few months back
        app.openTimelineEntry(row)
        let link = app.links.matching(NSPredicate(format: "label CONTAINS %@", "goodreads.com")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "The web address is a link")
        snap("entry-url-link")
    }

    /// An easter egg: at the bottom of Today, keep pulling up and let go for a random memory.
    func testPullUpAtBottomOfTodayShowsRandomMemory() throws {
        let app = launch()
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        for _ in 0..<6 { list.swipeUp(velocity: .fast) }
        sleep(1)
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.staticTexts["A Random Memory"].waitForExistence(timeout: 10))
        snap("pull-up-random-memory")
    }

    /// An entry's Spotify songs show in its long-press preview.
    func testSongsShowInPreviews() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Slow Saturday")).firstMatch
        app.scrollTo(row)
        row.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Blinding Lights")).firstMatch.exists,
                      "The song is in the preview")
        snap("preview-song")
    }

    /// With the search field focused, swiping down hides the keyboard (over the hashtags and the results).
    func testSwipeDownHidesSearchKeyboard() throws {
        let app = launch()
        tab(app, "Search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Over the hashtags")

        field.tap()
        field.typeText("Yosemite\n")
        let result = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.collectionViews.firstMatch.swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Over the results")
    }

    /// Tapping a hashtag in the row tags the word where it's already written (keeping its
    /// capitalization) rather than adding it at the end.
    func testHashtagTagsTheWordInTheText() throws {
        let app = launch()
        tab(app, "Journal").tap()
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        editor.typeText("Went Hiking with Sam. More hiking soon.")
        app.buttons["Hashtags"].tap()
        let chip = app.buttons["#hiking"] // the most recently used tag, first in the row
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        snap("compose-hashtag-row")
        chip.tap()
        XCTAssertEqual(editor.value as? String, "Went #Hiking with Sam. More hiking soon.")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    /// Today's streak (top right) opens Stats.
    func testStreakOpensStats() throws {
        let app = launch()
        let streak = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "day streak")).firstMatch
        XCTAssertTrue(streak.waitForExistence(timeout: 15))
        snap("today-streak")
        streak.tap()
        XCTAssertTrue(app.staticTexts["Past Year"].waitForExistence(timeout: 10), "Stats, in the Journal tab")
    }

    /// Settings → Home Screen Widget: choosing what shows beside the streak updates the preview.
    func testWidgetSettingsPreview() throws {
        let app = launch()
        tab(app, "Settings").tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10), "Settings has its heading")
        snap("settings-top")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home Screen Widget'")).firstMatch
        for _ in 0..<4 where !row.exists { app.swipeUp() } // below Reminders and Privacy
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["On This Day Entry"].waitForExistence(timeout: 5) || app.staticTexts["On This Day Entry"].exists)

        app.staticTexts["On This Day Entry"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bruges!")).firstMatch.waitForExistence(timeout: 5),
                      "The preview shows the start of a memory")
        snap("widget-entry")

        app.staticTexts["On This Day Count"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "memories from this day")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bruges!")).firstMatch.exists, "No entry text")
        snap("widget-count")

        app.staticTexts["Today's Prompt"].tap()
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "memories from this day")).firstMatch.exists)
        snap("widget-prompt")
    }

    /// A free account writes without photos or links, can delete but not edit, and has no Stats.
    /// TEST_RUNNER_DABBLE_FREE_TOKEN.
    func testFreeAccountLimits() throws {
        guard let free = ProcessInfo.processInfo.environment["DABBLE_FREE_TOKEN"] else { throw XCTSkip("Needs TEST_RUNNER_DABBLE_FREE_TOKEN") }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", free, "-DabbleServerOverride", "http://localhost:3000"]
        app.launch()

        // On This Day is PRO: Today says so (no throwback in its place).
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["See what you wrote on this date in past years with Dabble Me PRO."].exists)
        XCTAssertFalse(app.staticTexts["Throwback"].exists)
        snap("free-on-this-day")
        // Meanwhile, a random memory (free): the same sheet as shaking the phone.
        app.buttons["Try a Random Memory"].tap()
        XCTAssertTrue(app.staticTexts["A Random Memory"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["A Random Memory"].waitForNonExistence(timeout: 5))

        // Writing: no photos, no link button.
        tab(app, "Journal").tap()
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        XCTAssertTrue(app.buttons["Hashtags"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Link"].exists, "Links are PRO")
        XCTAssertFalse(app.buttons["Add Photos"].exists, "Photos are PRO")
        snap("free-compose-bar")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard Changes"].waitForExistence(timeout: 2) { app.buttons["Discard Changes"].tap() }

        // An entry: Delete, but no Edit.
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "A quiet walk after dinner")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["Actions"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Edit"].exists)
        snap("free-actions")
        // Delete confirms in its button: a tap turns it into "Hold to Delete", and holding it deletes.
        app.buttons["Delete"].tap()
        let hold = app.buttons["Hold to Delete"]
        XCTAssertTrue(hold.waitForExistence(timeout: 3))
        XCTAssertTrue(row.exists, "A tap alone doesn't delete")
        hold.press(forDuration: 0.6) // let go early: nothing happens
        XCTAssertTrue(hold.exists)
        sleep(1)
        snap("free-hold-released") // the red fill has emptied again
        hold.press(forDuration: 2.6)
        XCTAssertTrue(hold.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), "Holding deletes the entry")
        XCTAssertFalse(app.alerts.firstMatch.exists, "No alert after deleting")

        // Stats (from the Journal title's menu): a PRO screen.
        app.navigationBars.buttons["Journal"].tap()
        app.buttons["Stats"].tap()
        XCTAssertTrue(app.staticTexts["Stats are a PRO feature"].waitForExistence(timeout: 10))
        snap("free-stats")

        // Reminders: writing for everyone; On This Day (a PRO feature) is greyed out.
        tab(app, "Settings").tap()
        let writing = app.switches["Daily Writing Reminder"]
        XCTAssertTrue(writing.waitForExistence(timeout: 10))
        XCTAssertTrue(writing.isEnabled)
        XCTAssertFalse(app.switches["On This Day Memories"].isEnabled)
        snap("free-reminders")
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
        app.openTimelineEntry(row)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))

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
        XCTAssertTrue(app.buttons["Edit Entry"].exists, "Still on the entry underneath")

        XCUIDevice.shared.system.open(URL(string: "me.dabble.app:/shake")!)
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10))
        sleep(1)
        app.buttons["Open"].tap()
        XCTAssertTrue(app.staticTexts["A Random Memory"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
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
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        let collapsed = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Finally made it to Yosemite", "Show more")).firstMatch
        XCTAssertTrue(collapsed.waitForExistence(timeout: 10))
        row.tapRowText() // a long entry expands
        XCTAssertTrue(collapsed.waitForNonExistence(timeout: 5))

        row.swipeLeft()
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
        // A short entry opens on a tap; its dated tag is a pill with its age.
        app.scrollTo(row)
        row.tapRowText()
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        let pill = app.buttons.matching(NSPredicate(format: "label == %@ AND value CONTAINS %@", "#Biscuit", "since entry")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        snap("entry-dated-pill")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["Actions"].tap()
        let tag = app.buttons.matching(identifier: "ActionsSheetTag").matching(NSPredicate(format: "label == %@", "#Biscuit")).firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 10))
        XCTAssertTrue((tag.value as? String ?? "").contains("since entry"), "Dated tag shows its age")
        snap("actions-dated-tag")
        tag.tap() // searches it
        XCTAssertTrue(app.staticTexts["2 matching entries"].waitForExistence(timeout: 10)) // #Biscuit is on two
    }

    /// On This Day rows are the Journal's rows: swipe left for Actions.
    func testOnThisDayRowsSwipe() throws {
        let app = launch()
        let memory = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bruges!")).firstMatch
        XCTAssertTrue(memory.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1 year ago")).firstMatch.exists)
        memory.swipeLeft()
        XCTAssertTrue(app.buttons["Actions"].waitForExistence(timeout: 3))
        app.buttons["Actions"].tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 10))
    }
}
