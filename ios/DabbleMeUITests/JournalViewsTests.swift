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
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", testServer] + extra
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
        XCTAssertTrue(app.statTile("Words").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Entries per Month"].exists)
        sleep(1)
        snap("journal-stats")

        // The year: tapping yesterday's square (the demo always wrote yesterday) opens its entries
        // in the drawer, every time. Today is at its weekday's row (Sunday on top), so yesterday is
        // the row above, or the bottom of the column before on a Sunday.
        let heatmap = app.otherElements["Writing days in \(Calendar.current.component(.year, from: .now))"]
        XCTAssertTrue(heatmap.waitForExistence(timeout: 5))
        app.raiseStats()
        let pitch: CGFloat = 13 + 3, monthRow: CGFloat = 2 + 16 + 4
        let todayRow = Calendar(identifier: .gregorian).component(.weekday, from: .now) - 1
        // Today's column is up to four weeks from the right edge: the year's days to come follow it.
        let calendar = Calendar(identifier: .gregorian)
        let sunday = calendar.date(byAdding: .day, value: -todayRow, to: calendar.startOfDay(for: .now))!
        let yearEnd = calendar.date(from: DateComponents(year: calendar.component(.year, from: .now), month: 12, day: 31))!
        let ahead = min(4, (calendar.dateComponents([.day], from: sunday, to: yearEnd).day ?? 0) / 7)
        let (column, row) = todayRow == 0 ? (ahead + 1, 6) : (ahead, todayRow - 1)
        let yesterday = CGVector(dx: heatmap.frame.width - 6.5 - CGFloat(column) * pitch,
                                 dy: monthRow + CGFloat(row) * pitch + 6.5)
        for attempt in 1...3 {
            heatmap.coordinate(withNormalizedOffset: .zero).withOffset(yesterday).tap()
            XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10), "The day's entries open (try \(attempt))")
            if attempt == 1 {
                sleep(1)
                snap("stats-day-sheet")
                // The arrows beside Open: the entry before yesterday's takes the sheet, under its date.
                XCTAssertTrue(app.buttons["Next Entry"].exists)
                app.buttons["Previous Entry"].tap()
                sleep(2)
                snap("stats-day-sheet-previous")
                XCTAssertTrue(app.buttons["Open"].exists)
            }
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["Open"].waitForNonExistence(timeout: 5))
        }

        // Pinch out for bigger squares (kept for next time), then back. Up the page first, so the
        // pinch's fingers stay clear of the tab bar under the heatmap.
        let middle = heatmap.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -260)))
        heatmap.pinch(withScale: 2, velocity: 1)
        sleep(1)
        snap("stats-heatmap-zoomed")
        heatmap.pinch(withScale: 0.5, velocity: -1)

        app.swipeUp()
        snap("journal-stats-2")
        // At the bottom: where to take sentiment analysis, with a prompt to copy.
        XCTAssertTrue(app.staticTexts["Sentiment analysis"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Copy Prompt"].exists)
        app.swipeDown()
        app.swipeDown()

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
        // Jump to a Day is here too: it opens the calendar of written days.
        app.buttons["Jump to a Day"].tap()
        XCTAssertTrue(app.staticTexts["Jump to a Day"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Chat with your journal")).firstMatch.waitForExistence(timeout: 5),
                      "A pointer to the Claude/ChatGPT connector")
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
    /// With nothing on this date in past years and no earlier entries, Today shows Rewind with
    /// a nudge to write. TEST_RUNNER_DABBLE_EMPTY_TOKEN (an account with no past entries).
    func testThrowbackNudgeWithoutPastEntries() throws {
        guard let empty = ProcessInfo.processInfo.environment["DABBLE_EMPTY_TOKEN"] else {
            throw XCTSkip("Set TEST_RUNNER_DABBLE_EMPTY_TOKEN to an account with no entries")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", empty, "-DabbleServerOverride", testServer]
        app.launch()
        XCTAssertTrue(app.staticTexts["Rewind"].waitForExistence(timeout: 15))
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
        app.launchArguments = ["-DabbleDebugAccessToken", empty, "-DabbleServerOverride", testServer]
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
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", testServer]
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
        XCTAssertTrue(app.statTile("Words").waitForExistence(timeout: 10))
        tab(app, "Journal").tap()
        let newest = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to Yosemite")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 10))
        XCTAssertFalse(app.statTile("Words").exists)

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
        if !app.staticTexts["Added to this day's entry."].waitForExistence(timeout: 15) { snap("reflection-add-failed") }
        XCTAssertTrue(app.staticTexts["Added to this day's entry."].waitForExistence(timeout: 1))
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
        app.buttons["Insert"].tap()
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
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Email'")).firstMatch
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
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Email' AND label CONTAINS '7:00'")).firstMatch.waitForExistence(timeout: 5))
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

    /// Settings → Reminders → Past Entries, for push and email notifications alike: on/off, words
    /// that leave entries out, and entries over a year old.
    func testPastEntriesForNotifications() throws {
        let app = launch()
        tab(app, "Settings").tap()
        // Reminders: Push and Email, each to a page of its own, then Include Past Entries under them.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Include Past Entries'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let push = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Push'")).firstMatch
        let email = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Email'")).firstMatch
        XCTAssertTrue(push.exists && email.exists)
        XCTAssertLessThan(push.frame.minY, email.frame.minY)
        XCTAssertLessThan(email.frame.minY, row.frame.minY, "Under Email")
        snap("settings-reminders")
        row.tap()
        let include = app.switches["Include Past Entries in Notifications"]
        XCTAssertTrue(include.waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Include Entries Over a Year Old"].exists, "The demo account has entries over a year old")
        let words = app.textFields["Words, separated by commas"]
        words.tap()
        words.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "waffles\n")
        XCTAssertTrue(app.staticTexts["1 entry is left out of past entries."].waitForExistence(timeout: 10))
        snap("past-entries")

        // Off hides the rest (and the row says so); on brings it back, with the words saved.
        include.switches.firstMatch.tap()
        XCTAssertTrue(words.waitForNonExistence(timeout: 5))
        include.switches.firstMatch.tap()
        XCTAssertTrue(words.waitForExistence(timeout: 5))
        XCTAssertEqual(words.value as? String, "waffles")

        // Put the demo account back.
        words.tap()
        words.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "\n")
        XCTAssertTrue(app.staticTexts["1 entry is left out of past entries."].waitForNonExistence(timeout: 10))
        // The email's page is its days and time; past entries aren't repeated there.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Email'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Email Notifications"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Include a Past Entry"].exists)
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

    /// Settings → Theme: the text size and font change entry text across the app, not just
    /// an open entry.
    func testAccessibilitySettingsApplyToTimeline() throws {
        let app = launch()
        func accessibility(_ change: () -> Void) {
            tab(app, "Settings").tap()
            let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Theme")).firstMatch
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
            app.buttons["Dark"].tap()
            snap("accessibility-settings")
        }
        tab(app, "Journal").tap()
        app.scrollTo(row)
        XCTAssertGreaterThan(row.frame.width * row.frame.height, small * 1.3, "The timeline's text is larger")
        snap("accessibility-timeline")

        accessibility { // back to the defaults for other runs
            setSize("Default")
            app.buttons["Serif"].tap()
            app.buttons["Auto"].tap()
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Theme", "Auto")).firstMatch.waitForExistence(timeout: 5))
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

    /// Under the tiles, Stats is one year at a time: picking another from the year's menu turns the
    /// grid, the months and the hashtags to it. A month held in the bars is named in full.
    func testStatsFollowTheYearPicked() throws {
        let app = launch(["-stats.heatmapCell", "13"])
        tab(app, "Journal").tap()
        switchJournal(app, from: "Journal", to: "Stats")
        let thisYear = Calendar.current.component(.year, from: .now)
        let menu = app.buttons["Year, \(thisYear)"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        func bringUp(_ element: XCUIElement) {
            for _ in 0..<6 where !(element.exists && element.isHittable && element.frame.minY < 520) { app.swipeUp(velocity: .slow) }
        }
        bringUp(app.staticTexts["Entries per Month"])
        sleep(1)
        snap("stats-year-section")

        // A month held: its name in full under the bars (seen in the screenshot, taken mid-hold).
        let bars = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Entries per month")).firstMatch
        XCTAssertTrue(bars.waitForExistence(timeout: 5))
        let named = expectation(description: "The month is named while it's held")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
            if app.staticTexts.matching(identifier: "StatsSelectedMonth").firstMatch.exists { named.fulfill() }
            self.snap("stats-month-held")
        }
        bars.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5)).press(forDuration: 3)
        wait(for: [named], timeout: 5)

        // Last year: the demo wrote once, about Bruges (#travel).
        app.swipeDown(); app.swipeDown()
        menu.tap()
        app.buttons[String(thisYear - 1)].tap()
        let summary = app.staticTexts.matching(identifier: "StatsYearSummary").firstMatch
        XCTAssertTrue(app.staticTexts.matching(identifier: "StatsYearSummary").matching(NSPredicate(format: "label BEGINSWITH %@", "1 entry")).firstMatch.waitForExistence(timeout: 10),
                      "The year's own count: \(summary.label)")
        let hashtags = app.staticTexts["Top Hashtags in \(thisYear - 1)"]
        bringUp(hashtags)
        XCTAssertTrue(hashtags.waitForExistence(timeout: 10), "The hashtags are the year's")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "#travel, 1 ")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "#hiking")).firstMatch.exists)
        snap("stats-last-year")
    }

    /// A day held down in the year's grid: its entry in a preview with Open, or, for a day gone by
    /// without one, "Nothing written on this day." with Write Entry (the composer, on that day).
    func testHoldingADayInTheGridShowsItOrOffersToWriteIt() throws {
        let app = launch(["-stats.heatmapCell", "13"])
        tab(app, "Journal").tap()
        switchJournal(app, from: "Journal", to: "Stats")
        let calendar = Calendar(identifier: .gregorian)
        let heatmap = app.otherElements["Writing days in \(calendar.component(.year, from: .now))"]
        XCTAssertTrue(heatmap.waitForExistence(timeout: 10))
        app.raiseStats()
        // Where a day `back` days ago sits: today's column is up to four weeks from the right edge.
        func square(daysAgo back: Int) -> XCUICoordinate {
            let pitch: CGFloat = 13 + 3, monthRow: CGFloat = 2 + 16 + 4
            let today = calendar.startOfDay(for: .now)
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            func sunday(_ date: Date) -> Date { calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: date) - 1), to: date)! }
            let yearEnd = calendar.date(from: DateComponents(year: calendar.component(.year, from: .now), month: 12, day: 31))!
            let ahead = min(4, (calendar.dateComponents([.day], from: sunday(today), to: yearEnd).day ?? 0) / 7)
            let column = ahead + (calendar.dateComponents([.day], from: sunday(day), to: sunday(today)).day ?? 0) / 7
            let row = calendar.component(.weekday, from: day) - 1
            return heatmap.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: heatmap.frame.width - 6.5 - CGFloat(column) * pitch, dy: monthRow + CGFloat(row) * pitch + 6.5))
        }
        // Yesterday (always written): the entry, previewed as the Journal previews one, with Open.
        square(daysAgo: 1).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10), "A written day has Open")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to")).firstMatch.waitForExistence(timeout: 10),
                      "Yesterday's entry is previewed")
        sleep(1)
        snap("stats-day-held")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap() // away from it: closes it
        XCTAssertTrue(app.buttons["Open"].waitForNonExistence(timeout: 5))
        sleep(1)

        // Eleven days ago: nothing written.
        square(daysAgo: 11).press(forDuration: 1.2)
        let write = app.buttons["Write Entry"]
        XCTAssertTrue(write.waitForExistence(timeout: 5), "A day without an entry offers one")
        XCTAssertTrue(app.staticTexts["Nothing written on this day."].exists)
        sleep(1)
        snap("stats-day-write")
        let day = calendar.date(byAdding: .day, value: -11, to: .now)!
        write.tap()
        XCTAssertTrue(app.textViews["Entry"].waitForExistence(timeout: 10), "The composer opens")
        let date = day.formatted(.dateTime.month(.abbreviated).day().year())
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", date, date)).firstMatch.waitForExistence(timeout: 5),
                      "On that day: \(date)")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    /// A web address pasted over selected words links them, instead of replacing them.
    func testPastingAnAddressOverSelectedTextLinksIt() throws {
        UIPasteboard.general.string = "https://example.com/trail"
        let app = launch()
        tab(app, "Journal").tap()
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        if app.buttons["Start Over"].exists { app.buttons["Start Over"].tap() } // a draft from an earlier run
        editor.typeText("Trailhead")
        editor.doubleTap() // selects the word
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        let allow = app.alerts.buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        sleep(1)
        snap("compose-paste-link")
        XCTAssertEqual(editor.value as? String, "Trailhead", "The word stays; the address isn't pasted in as text")
        // (The word's link shows in the screenshot: the editor doesn't offer its links to the tests.)
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    /// Settings → Email is a switch, like Push: off hides its days and time (and the row says Off);
    /// back on, the days it had are back.
    func testEmailNotificationsSwitch() throws {
        let app = launch()
        tab(app, "Settings").tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Email'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        snap("settings-sections")
        row.tap()
        let email = app.switches["Email Notifications"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        XCTAssertEqual(email.value as? String, "1", "The demo's email is on (Sundays)")
        XCTAssertEqual(app.buttons["Sunday"].value as? String, "On")
        snap("email-on")
        email.switches.firstMatch.tap()
        XCTAssertTrue(app.buttons["Sunday"].waitForNonExistence(timeout: 5), "Off: no days or time")
        snap("email-off")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Email' AND label CONTAINS 'Off'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Email'")).firstMatch.tap()
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.switches.firstMatch.tap()
        XCTAssertTrue(app.buttons["Sunday"].waitForExistence(timeout: 5), "On again")
        XCTAssertEqual(app.buttons["Sunday"].value as? String, "On", "With the day it had")
        XCTAssertEqual(app.buttons["Monday"].value as? String, "Off")
    }

    /// The photo viewer's Photos button goes to the Journal's grid of photos; a swipe to the right
    /// on an entry's song player goes to the Playlist.
    func testPhotoViewerAndSongPlayerLeadToTheirViews() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Last farmers market")).firstMatch
        app.scrollTo(row)
        app.openTimelineEntry(row)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        snap("entry-back-arrow")
        let player = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Spotify player, ")).firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 10))
        player.swipeRight()
        XCTAssertTrue(app.buttons["The Weeknd – Blinding Lights"].waitForExistence(timeout: 10), "The Playlist")
        XCTAssertTrue(app.navigationBars.buttons["Playlist"].exists || app.navigationBars.staticTexts["Playlist"].exists)
        snap("journal-title-menu")

        switchJournal(app, from: "Playlist", to: "Journal")
        app.scrollTo(row)
        app.openTimelineEntry(row)
        let photo = app.buttons["Entry photo"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        sleep(2)
        photo.tap()
        let photos = app.buttons["Photos"]
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        sleep(1)
        snap("photo-viewer")
        photos.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch.waitForExistence(timeout: 10), "The photo grid")
    }

    /// Jump to a Day's calendar: the Slab arrows step through the months, and a day held down
    /// previews its entry (with Open) or offers Write Entry.
    func testCalendarStepsMonthsAndPreviewsDays() throws {
        let app = launch()
        tab(app, "Search").tap()
        app.buttons["Jump to a Day"].tap()
        let now = Date.now, calendar = Calendar.current
        XCTAssertTrue(app.buttons[now.formatted(.dateTime.month(.wide).year())].waitForExistence(timeout: 10), "It opens on this month")
        sleep(1)
        snap("calendar")
        XCTAssertFalse(app.buttons["Next Month"].isEnabled, "Nothing after this month")
        app.buttons["Previous Month"].tap()
        let before = calendar.date(byAdding: .month, value: -1, to: now)!
        XCTAssertTrue(app.buttons[before.formatted(.dateTime.month(.wide).year())].waitForExistence(timeout: 5), "The month before")
        app.buttons["Next Month"].tap()
        XCTAssertTrue(app.buttons[now.formatted(.dateTime.month(.wide).year())].waitForExistence(timeout: 5))

        func day(_ back: Int) -> XCUIElement {
            let date = calendar.date(byAdding: .day, value: -back, to: now)!
            return app.buttons.matching(NSPredicate(format: "label CONTAINS %@", date.formatted(.dateTime.month(.wide).day()) + ",")).firstMatch
        }
        // Held: yesterday's entry, with Open.
        if calendar.component(.day, from: now) > 1 {
            day(1).press(forDuration: 1.2)
            XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Finally made it to")).firstMatch.waitForExistence(timeout: 10))
            sleep(1)
            snap("calendar-day-held")
            app.buttons["Open"].tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "· Yesterday")).firstMatch.waitForExistence(timeout: 10), "Open brings the day up")
        }
    }

    /// The Journal's title is a menu of its views: the one showing has its filled icon, and no
    /// checkmark; picking another shows it.
    func testJournalTitleMenu() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let title = app.navigationBars.buttons["Journal"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        let photos = app.collectionViews.buttons["Photos"].exists ? app.collectionViews.buttons["Photos"] : app.buttons["Photos"].firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        sleep(1)
        snap("journal-menu-open")
        photos.tap()
        XCTAssertTrue(app.navigationBars.buttons["Photos"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Photos"].tap()
        sleep(1)
        snap("journal-menu-open-photos")
    }

    /// Screenshots, for looking over: each of the Journal's views (and Today and Search) with an
    /// empty journal, and on a free account. TEST_RUNNER_DABBLE_EMPTY_TOKEN and _FREE_TOKEN.
    func testSnapEmptyAndFreeViews() throws {
        let env = ProcessInfo.processInfo.environment
        guard let empty = env["DABBLE_EMPTY_TOKEN"], let free = env["DABBLE_FREE_TOKEN"] else { throw XCTSkip("Needs the empty and free tokens") }
        for (name, token) in [("empty", empty), ("free", free)] {
            let app = XCUIApplication()
            app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", testServer]
            app.launch()
            XCTAssertTrue(tab(app, "Journal").waitForExistence(timeout: 15))
            sleep(3)
            snap("\(name)-today")
            tab(app, "Journal").tap()
            sleep(3)
            snap("\(name)-journal")
            var current = "Journal"
            for mode in ["Stats", "Photos", "Playlist"] {
                switchJournal(app, from: current, to: mode)
                current = mode
                sleep(3)
                snap("\(name)-\(mode.lowercased())")
            }
            tab(app, "Search").tap()
            sleep(3)
            snap("\(name)-search")
            app.terminate()
        }
    }

    /// Stats' tiles go to what they count: Entries to the Journal, Photos to the photo grid, the
    /// streak to its year in the year card, and Words to the top hashtags.
    func testStatsTilesGoToWhatTheyCount() throws {
        let app = launch()
        tab(app, "Journal").tap()
        switchJournal(app, from: "Journal", to: "Stats")
        XCTAssertTrue(app.statTile("Words").waitForExistence(timeout: 10))
        snap("stats-tiles")

        app.statTile("Photos").tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Photo from'")).firstMatch.waitForExistence(timeout: 10), "Photos opens the grid")
        switchJournal(app, from: "Photos", to: "Stats")
        XCTAssertTrue(app.statTile("Words").waitForExistence(timeout: 10))

        app.statTile("Words").tap()
        let hashtags = app.staticTexts["Top Hashtags This Year"]
        XCTAssertTrue(hashtags.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertLessThan(hashtags.frame.minY, 320, "Words scrolls to the hashtags")
        snap("stats-words-to-hashtags")
        app.swipeDown(); app.swipeDown()

        let streak = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Streak'")).firstMatch
        XCTAssertTrue(streak.waitForExistence(timeout: 5))
        streak.tap()
        let summary = app.staticTexts.matching(identifier: "StatsYearSummary").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertLessThan(summary.frame.minY, 320, "The streak scrolls to its year")
        snap("stats-streak-to-year")
        app.swipeDown(); app.swipeDown()

        app.statTile("Entries").tap()
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10), "Entries opens the Journal's list")
    }

    /// An entry with songs has Spotify's player under it, showing the first (in bold above) and
    /// not started. A tap on another song puts that one in the player; a swipe left puts the
    /// player away, and a tap on a song brings it back.
    func testEntryWithSongsHasThePlayerUnderIt() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Last farmers market")).firstMatch
        app.scrollTo(row)
        app.openTimelineEntry(row)
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        func player(_ song: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Spotify player, \(song)")).firstMatch
        }
        let first = app.buttons["The Killers – Mr. Brightside"], second = app.buttons["Rick Astley – Never Gonna Give You Up"]
        XCTAssertTrue(player("The Killers – Mr. Brightside").waitForExistence(timeout: 10), "The first song is in the player")
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(second.isSelected)
        XCTAssertTrue(app.links["Open in Spotify"].exists || app.buttons["Open in Spotify"].exists)
        sleep(6) // Spotify's player loads
        snap("entry-song-player")

        second.tap()
        XCTAssertTrue(player("Rick Astley – Never Gonna Give You Up").waitForExistence(timeout: 5), "One song at a time: the one tapped")
        XCTAssertFalse(player("The Killers – Mr. Brightside").exists)
        XCTAssertTrue(second.isSelected)
        XCTAssertFalse(first.isSelected)

        player("Rick Astley – Never Gonna Give You Up").swipeLeft()
        XCTAssertTrue(player("Rick Astley – Never Gonna Give You Up").waitForNonExistence(timeout: 5), "A swipe left puts the player away")
        XCTAssertFalse(second.isSelected)
        snap("entry-song-player-hidden")
        first.tap()
        XCTAssertTrue(player("The Killers – Mr. Brightside").waitForExistence(timeout: 5), "A tap on a song brings the player back")
    }

    /// A web address in a row (Today's and the Journal's are the same row) is a link without
    /// expanding or opening the entry first: a tap on it goes to the browser.
    func testALinkInARowOpensWithoutOpeningTheEntry() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "The Overstory")).firstMatch
        app.scrollTo(row)
        let link = app.links.matching(NSPredicate(format: "label CONTAINS %@", "goodreads")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "The address is a link in the row")
        link.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15), "The link opens in the browser")
        app.activate()
        XCTAssertFalse(app.buttons["Edit Entry"].waitForExistence(timeout: 3), "The entry itself didn't open")
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

    /// Journal > Playlist: the entries with songs, each with a short preview and its songs; a
    /// song plays in Spotify's player docked at the bottom, and tapping the row opens the entry.
    func testPlaylistListsEntriesWithSongsAndPlaysOne() throws {
        let app = launch()
        tab(app, "Journal").tap()
        switchJournal(app, from: "Journal", to: "Playlist")
        let song = app.buttons["The Weeknd – Blinding Lights"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["The Killers – Mr. Brightside"].exists)
        XCTAssertTrue(app.buttons["Rick Astley – Never Gonna Give You Up"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Biscuit has discovered")).firstMatch.exists,
                       "Only entries with songs")
        snap("playlist")
        song.tap()
        // The player, with a way out to Spotify beside it (no close button: it's swiped away).
        let player = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Spotify player, The Weeknd – Blinding Lights")).firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertTrue(app.links["Open in Spotify"].exists || app.buttons["Open in Spotify"].exists)
        XCTAssertFalse(app.buttons["Close Player"].exists)
        XCTAssertEqual(song.value as? String, "Playing")
        sleep(6) // Spotify's player loads
        snap("playlist-playing")
        player.swipeLeft()
        XCTAssertTrue(player.waitForNonExistence(timeout: 5), "A swipe left puts the player away")
        XCTAssertNotEqual(song.value as? String, "Playing")
        // The row itself opens the entry.
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Slow Saturday")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
    }

    /// A long entry's last line stays in view above the bar, and above a row opened in it (the
    /// row used to sit over it). Checked by eye from the screenshots: the text is one element.
    func testOpenRowLeavesTheEndOfALongEntryInView() throws {
        let app = launch()
        tab(app, "Journal").tap()
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        if app.buttons["Start Over"].exists { app.buttons["Start Over"].tap(); editor.tap() }
        editor.typeText((1...16).map { "Line \($0)" }.joined(separator: "\n") + "\nThe last line about hiking")
        sleep(1)
        snap("long-entry-end")
        app.buttons["Hashtags"].tap()
        XCTAssertTrue(app.buttons["#hiking"].waitForExistence(timeout: 10))
        sleep(1)
        snap("long-entry-hashtags")
        app.buttons["Link"].tap()
        XCTAssertTrue(app.textFields["Link address"].waitForExistence(timeout: 5))
        sleep(1)
        snap("long-entry-link")
        app.buttons["Link"].tap()
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    /// An open row is part of the keyboard's bar, above its buttons: it hides with the keyboard and
    /// comes back with it, still above the buttons.
    func testComposerRowClearsBarAfterKeyboardReturns() throws {
        let app = launch()
        tab(app, "Journal").tap()
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        if app.buttons["Start Over"].exists { app.buttons["Start Over"].tap(); editor.tap() }
        editor.typeText("Went hiking with Sam.")
        let buttons = app.buttons["Hashtags"]
        buttons.tap()
        let chip = app.buttons["#hiking"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(chip.frame.maxY, buttons.frame.minY, "Above the buttons")
        snap("compose-row-open")
        app.swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertFalse(chip.isHittable, "Hidden with the keyboard")
        snap("compose-row-keyboard-hidden")
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        sleep(1) // the keyboard finishes coming in
        snap("compose-row-keyboard-back")
        XCTAssertLessThanOrEqual(chip.frame.maxY, buttons.frame.minY, "Still above the buttons")
        chip.tap()
        XCTAssertEqual(editor.value as? String, "Went #hiking with Sam.")
        // A prompt (it can wrap) clears the buttons too.
        let prompt = app.buttons["Prompt"]
        if prompt.exists {
            prompt.tap()
            let question = app.staticTexts["AskMeQuestion"]
            XCTAssertTrue(question.waitForExistence(timeout: 60))
            sleep(1)
            snap("compose-prompt-row")
            XCTAssertLessThanOrEqual(question.frame.maxY, prompt.frame.minY, "Prompt above the buttons")
        }
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    /// Link opens a row in the bar for the address; selecting a link's text opens it again to
    /// change or remove the link.
    func testLinkRowInsertsEditsAndRemoves() throws {
        let app = launch()
        tab(app, "Journal").tap()
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        // A draft left by an earlier run comes back: discard it and start from a blank page.
        if app.buttons["Start Over"].waitForExistence(timeout: 1) {
            app.buttons["Cancel"].tap()
            app.buttons["Discard"].tap()
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
            app.buttons["New Entry"].tap()
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            editor.tap()
        }
        editor.typeText("Read this: ")
        let link = app.buttons["Link"]
        link.tap()
        let address = app.textFields["Link address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(address.frame.maxY, link.frame.minY, "Above the buttons")
        XCTAssertFalse(app.buttons["Insert"].isEnabled, "Nothing to insert yet")
        sleep(1)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "The keyboard stays up for the address")
        snap("link-row-focused")
        // Typing goes to the address without tapping it first: Link gave it the keyboard.
        app.typeText("dabble.me/write")
        XCTAssertEqual(address.value as? String, "dabble.me/write")
        XCTAssertEqual(editor.value as? String, "Read this: ", "Nothing typed into the entry")
        snap("link-row")
        app.buttons["Insert"].tap()
        XCTAssertEqual(editor.value as? String, "Read this: https://dabble.me/write")
        XCTAssertTrue(address.waitForNonExistence(timeout: 5), "The row closes")
        editor.typeText(" ok") // the keyboard is back on the entry
        XCTAssertEqual(editor.value as? String, "Read this: https://dabble.me/write ok")
        // Link a word: select it, tap Link (the second time the row opens), and type the address.
        editor.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: 30)).doubleTap()
        link.tap()
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        sleep(1)
        app.typeText("example.com")
        XCTAssertEqual(address.value as? String, "example.com", "The address has the keyboard again")
        snap("link-row-word") // "Read" stays tinted while its address is typed
        app.buttons["Insert"].tap()
        XCTAssertTrue(address.waitForNonExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Read this: https://dabble.me/write ok", "Linking a word doesn't change the text")
        // Tap the link: its row opens (it doesn't leave for the browser).
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0)).withOffset(CGVector(dx: 0, dy: 30)).tap()
        XCTAssertTrue(address.waitForExistence(timeout: 5), "Tapping a link opens its row")
        XCTAssertEqual(address.value as? String, "https://dabble.me/write")
        snap("link-row-existing")
        XCTAssertTrue(app.buttons["Update"].exists)
        app.buttons["Remove Link"].tap()
        XCTAssertTrue(address.waitForNonExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Read this: https://dabble.me/write ok", "The text stays")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    /// Where there's a camera, it has a button of its own beside Add Photos. (The simulator has
    /// none, so the button is switched on for the test.)
    func testAddPhotosOffersTheCamera() throws {
        let app = launch(["-DabbleDebugCameraMenu", "YES"])
        tab(app, "Journal").tap()
        app.buttons["New Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        // With no photos yet, the library and the camera are each one tap away.
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add Photos"].exists)
        snap("add-photos-buttons")
        app.buttons["Add Photos"].tap()
        XCTAssertFalse(app.buttons["Choose Photos"].waitForExistence(timeout: 2), "Straight to the library, no menu")
        sleep(2)
        snap("add-photos-library")
    }

    /// A dabble.me page from Settings opens in a Safari sheet inside the app, not in Safari.
    func testDabbleLinksOpenInTheApp() throws {
        let app = launch()
        tab(app, "Settings").tap()
        let link = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Privacy Policy")).firstMatch
        for _ in 0..<6 where !(link.exists && link.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        link.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10), "The page is up in the app, with a Close button")
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertNotEqual(XCUIApplication(bundleIdentifier: "com.apple.mobilesafari").state, .runningForeground)
        snap("in-app-page")
        app.buttons["Close"].tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5))
    }

    /// Jump to a Day from Search: the day's sheet, and Open shows the entry (in the Journal).
    func testJumpToADayFromSearchOpensTheEntry() throws {
        let app = launch()
        tab(app, "Search").tap()
        let jump = app.buttons["Jump to a Day"]
        XCTAssertTrue(jump.waitForExistence(timeout: 10))
        jump.tap()
        // The demo's Biscuit entry is five days ago, in the month the calendar opens on.
        let date = Calendar.current.date(byAdding: .day, value: -5, to: .now)!
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", date.formatted(.dateTime.month(.wide).day()))).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 10))
        day.tap()
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10))
        // The drawer is titled Jump to a Day, with the entry's date (and how long ago) in its body.
        XCTAssertTrue(app.staticTexts["Jump to a Day"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "· 5 days ago")).firstMatch.exists)
        snap("day-drawer")
        // Back three entries (twelve days ago), then the calendar again: it opens on that month.
        for _ in 0..<3 {
            app.buttons["Previous Entry"].tap()
            sleep(2)
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "· 12 days ago")).firstMatch.waitForExistence(timeout: 5))
        // The drawer's calendar button (Search has one of the same name behind the sheet).
        app.buttons["DayDrawerCalendar"].tap()
        let earlier = Calendar.current.date(byAdding: .day, value: -12, to: .now)!
        let earlierDay = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", earlier.formatted(.dateTime.month(.wide).day()))).firstMatch
        XCTAssertTrue(earlierDay.waitForExistence(timeout: 10), "The calendar is on the month last looked at")
        sleep(1)
        snap("day-picker-reopened")
        earlierDay.tap()
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10))
        app.buttons["Open"].tap()
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10), "The entry opens, not left behind Search")
    }

    /// Links in a day's drawer work: a #tag closes it and searches.
    func testLinksInTheDayDrawerWork() throws {
        let app = launch()
        tab(app, "Search").tap()
        let jump = app.buttons["Jump to a Day"]
        XCTAssertTrue(jump.waitForExistence(timeout: 10))
        jump.tap()
        // Four days ago: "Big presentation went well… #work #gratitude".
        let date = Calendar.current.date(byAdding: .day, value: -4, to: .now)!
        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", date.formatted(.dateTime.month(.wide).day()))).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 10))
        day.tap()
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10))
        let tag = app.links["#work"]
        XCTAssertTrue(tag.waitForExistence(timeout: 5), "The #tag is a link")
        tag.tap()
        // (The tap lands on one of the entry's two tags.)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'matching entr'")).firstMatch.waitForExistence(timeout: 10),
                      "It searches for the tag")
        XCTAssertFalse(app.buttons["Open"].exists, "The drawer closed")
    }

    /// An entry with formatting the editor can't hold (a heading, a quote, a style) still opens
    /// in the app, simplified, and says so.
    func testEntryWithOtherFormattingEditsSimplified() throws {
        let app = launch()
        tab(app, "Search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("plant a tree\n")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Reading notes")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        app.openTimelineEntry(row)
        app.buttons["Edit Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "It opens in the app, not on the web")
        XCTAssertTrue(app.staticTexts["SimplifiedBanner"].exists)
        let text = editor.value as? String ?? ""
        XCTAssertTrue(text.hasPrefix("Reading notes\nThe best time to plant a tree"), text)
        XCTAssertTrue(text.contains("Worth remembering"), text)
        snap("edit-simplified")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
    }

    /// Moving an entry onto a day that has one asks first, then merges the two.
    func testChangingTheDateToATakenDayOffersToMerge() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let editor = app.textViews["Entry"]
        func pickDay(_ offset: Int) {
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let target = Calendar.current.date(byAdding: .day, value: offset, to: .now)!
            let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", target.formatted(.dateTime.weekday(.wide).month(.wide).day()))).firstMatch
            XCTAssertTrue(day.waitForExistence(timeout: 5))
            day.tap()
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap() // closes the calendar
        }
        // Two entries of the test's own, on days the demo leaves empty (three and six days ago).
        func write(_ text: String, daysAgo: Int) {
            app.buttons["New Entry"].tap()
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            editor.tap()
            if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
            if app.buttons["Start Over"].exists { app.buttons["Start Over"].tap(); editor.tap() }
            editor.typeText(text)
            pickDay(-daysAgo)
            app.buttons["Save"].tap()
            XCTAssertTrue(editor.waitForNonExistence(timeout: 15))
        }
        write("Kept on its day.", daysAgo: 6)
        write("Moved onto it.", daysAgo: 3)
        let moved = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Moved onto it.")).firstMatch
        app.openTimelineEntry(moved)
        app.buttons["Edit Entry"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        pickDay(-6)
        app.buttons["Save"].tap()
        let merge = app.buttons["Merge"]
        XCTAssertTrue(merge.waitForExistence(timeout: 10), "That day has an entry: asked first")
        snap("merge-question")
        // Cancel puts the date back (nothing left to save), and the entry stays where it was.
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(merge.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Back on its own day")
        pickDay(-6)
        app.buttons["Save"].tap()
        XCTAssertTrue(merge.waitForExistence(timeout: 10))
        merge.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 15))
        // The open entry is the merged one: that day's, with the moved one after a rule.
        let shown = app.textViews.firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: 10))
        let text = shown.value as? String ?? ""
        XCTAssertTrue(text.contains("Kept on its day.") && text.contains("Moved onto it."), text)
        snap("merged-entry")
        // Clean up: delete it.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Kept on its day.")).firstMatch
        app.scrollTo(row)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Moved onto it.")).firstMatch.exists,
                       "The moved entry is gone from its old day")
        row.swipeLeft()
        app.buttons["Actions"].tap()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        app.buttons["Hold to Delete"].press(forDuration: 2.6)
        XCTAssertTrue(row.waitForNonExistence(timeout: 15))
    }

    /// Editing an entry, its date can be changed: the entry moves to that day.
    func testEditingCanChangeTheDate() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Big presentation went well")).firstMatch
        app.openTimelineEntry(row)
        // Four days ago to begin with; three days ago has no entry.
        func title(_ offset: Int) -> String {
            Calendar.current.date(byAdding: .day, value: offset, to: .now)!.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
        }
        func move(to offset: Int) {
            let edit = app.buttons["Edit Entry"]
            XCTAssertTrue(edit.waitForExistence(timeout: 10))
            edit.tap()
            // The date, in the middle of the editor's bar, opens a calendar.
            XCTAssertTrue(app.textViews["Entry"].waitForExistence(timeout: 10))
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let target = Calendar.current.date(byAdding: .day, value: offset, to: .now)!
            let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", target.formatted(.dateTime.weekday(.wide).month(.wide).day()))).firstMatch
            XCTAssertTrue(day.waitForExistence(timeout: 5))
            day.tap()
            // Close the calendar, then save.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            let save = app.buttons["Save"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            XCTAssertTrue(save.isEnabled, "A new date alone is a change to save")
            save.tap()
            XCTAssertTrue(app.staticTexts[title(offset)].waitForExistence(timeout: 15), "The entry is on \(title(offset))")
        }
        move(to: -3)
        snap("entry-date-changed")
        move(to: -4) // back where it was, for the other tests
    }

    /// Results that span a few months get the Journal's timeline scrubber; a tap on it opens the calendar.
    func testSearchResultsHaveTheTimelineScrubber() throws {
        let app = launch()
        tab(app, "Search").tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("the\n")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'matching entries'")).firstMatch.waitForExistence(timeout: 10))
        app.swipeUp(velocity: .slow) // the scrubber shows while scrolling
        let scrubber = app.otherElements["Timeline scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        snap("search-scrubber")
        scrubber.tap()
        XCTAssertTrue(app.staticTexts["Jump to a Day"].waitForExistence(timeout: 5), "A tap opens the calendar")
    }

    /// Once today's written, the pencil beside today's date opens it for editing. (Deletes the
    /// entry afterwards, so Today is unwritten again for the other tests.)
    func testPencilBesideTodaysDateEditsTodaysEntry() throws {
        let app = launch()
        let write = app.buttons["Write Today's Entry"]
        XCTAssertTrue(write.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Edit Today's Entry"].exists, "Nothing to edit yet")
        write.tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        if app.buttons["Start Over"].exists { app.buttons["Start Over"].tap(); editor.tap() }
        editor.typeText("A quiet day at home.")
        app.buttons["Save"].tap()
        let pencil = app.buttons["Edit Today's Entry"]
        XCTAssertTrue(pencil.waitForExistence(timeout: 15))
        snap("today-edit-pencil")
        pencil.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Straight into editing")
        XCTAssertEqual(editor.value as? String, "A quiet day at home.")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
        // The widget's "Add to today" link does the same.
        XCUIDevice.shared.system.open(URL(string: "me.dabble.app:/today/edit")!)
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Add to today opens today's entry for editing")
        XCTAssertEqual(editor.value as? String, "A quiet day at home.")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
        // Clean up: delete today's entry from its Actions.
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "A quiet day at home.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["Actions"].tap()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        app.buttons["Hold to Delete"].press(forDuration: 2.6)
        XCTAssertTrue(write.waitForExistence(timeout: 15), "Today is unwritten again")
    }

    /// Stats offers the year's Rewind in its season: it opens full screen and is tapped through
    /// like a story, back a card and on to the end, where one more tap closes it.
    func testRewindOpensFromStatsAndPagesThrough() throws {
        let year = Calendar.current.component(.year, from: .now)
        // (Stand-in photos: the demo's own need storage the test server may not have.)
        let app = launch(["-DabbleDebugRewindYear", String(year), "-DabbleDebugRewindPhotos", "YES"])
        tab(app, "Journal").tap()
        switchJournal(app, from: "Journal", to: "Stats")
        let card = app.buttons["\(year) Rewind"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        snap("rewind-card")
        card.tap()
        // The year is read (and, with Apple Intelligence, a few lines written) before the cover.
        let cover = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Here’s what you wrote down.")).firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 300), "The cover comes up")
        snap("rewind-1")
        // Near the top, clear of the last card's photos (which open their days).
        let forward = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.14))
        forward.tap()
        XCTAssertTrue(app.staticTexts["You showed up"].waitForExistence(timeout: 5))
        snap("rewind-2")
        // The left edge goes back.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.14)).tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        forward.tap()
        XCTAssertTrue(app.staticTexts["You showed up"].waitForExistence(timeout: 5))
        // On through the rest; a tap on the last card closes it, back to Stats.
        var cards = 2
        let close = app.buttons["Close"] // the Rewind's X: there while it's open
        while close.exists, cards < 16 {
            forward.tap()
            cards += 1
            sleep(2) // photos come in
            if close.exists { snap("rewind-\(cards)") }
        }
        XCTAssertFalse(close.exists, "Tapping on from the last card closes the Rewind")
        XCTAssertTrue(card.isHittable)
        XCTAssertGreaterThan(cards, 5)
        XCTAssertFalse(app.buttons["Start Over"].exists)
        // The X closes it from anywhere.
        card.tap()
        XCTAssertTrue(cover.waitForExistence(timeout: 60))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5), "Back on Stats")
    }

    /// Today's count of the journal's entries (top right) opens Stats, where the year of writing
    /// days is titled with its year, says how many entries it has and the share of its days with
    /// one, and can go back to an earlier year.
    func testEntryCountOpensStats() throws {
        let app = launch()
        let count = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "[0-9,]+ entries")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        snap("today-entry-count")
        count.tap()
        XCTAssertTrue(app.statTile("Words").waitForExistence(timeout: 10), "Stats, in the Journal tab")
        let thisYear = Calendar.current.component(.year, from: .now)
        func summary(_ pattern: String) -> Bool {
            app.staticTexts.matching(identifier: "StatsYearSummary").matching(NSPredicate(format: "label MATCHES %@", pattern))
                .firstMatch.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(summary("[0-9,]+ entries • [0-9]+% of days"))
        snap("stats-year")
        // The demo's first entry is three years back: last year has one entry (its On This Day).
        let menu = app.buttons["Year, \(thisYear)"]
        XCTAssertTrue(menu.exists)
        menu.tap()
        app.buttons[String(thisYear - 1)].tap()
        XCTAssertTrue(app.otherElements["Writing days in \(thisYear - 1)"].waitForExistence(timeout: 10))
        XCTAssertTrue(summary("1 entry • 1% of days"))
        snap("stats-year-earlier")
    }

    /// Settings → Home Screen Widget: choosing what shows beside today's date updates the preview.
    func testWidgetSettingsPreview() throws {
        let app = launch()
        tab(app, "Settings").tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 10), "Settings has its heading")
        snap("settings-top")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home Screen Widget'")).firstMatch
        for _ in 0..<4 where !row.exists { app.swipeUp() } // below Reminders and Privacy
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let previews = app.switches["Show Entry Previews"]
        XCTAssertTrue(previews.waitForExistence(timeout: 5))
        let memory = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Bruges!")).firstMatch
        let count = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "memories from this day")).firstMatch

        // Rewind without previews: how many memories, none of their text.
        app.staticTexts["Rewind"].tap()
        if previews.value as? String == "1" { previews.switches.firstMatch.tap() }
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertFalse(memory.exists, "No entry text")
        snap("widget-count")

        // With previews: the start of a memory.
        previews.switches.firstMatch.tap()
        XCTAssertTrue(memory.waitForExistence(timeout: 5), "The preview shows the start of a memory")
        snap("widget-entry")

        // Today's Prompt (the demo hasn't written today): the prompt, with or without previews.
        app.staticTexts["Today's Prompt"].tap()
        XCTAssertTrue(memory.waitForNonExistence(timeout: 5))
        XCTAssertFalse(count.exists)
        snap("widget-prompt")
        previews.switches.firstMatch.tap() // back to the default: no previews
    }

    /// Settings → Delete Account: says what's about to happen, then signs the app out and opens
    /// the deletion page in the browser (it's finished on dabble.me).
    /// TEST_RUNNER_DABBLE_DELETION_TOKEN: a token of its own, since signing out spends it (the
    /// free demo account's will do).
    func testDeletingTheAccountSignsOutAndOpensTheBrowser() throws {
        guard let spare = ProcessInfo.processInfo.environment["DABBLE_DELETION_TOKEN"] else { throw XCTSkip("Needs TEST_RUNNER_DABBLE_DELETION_TOKEN") }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", spare, "-DabbleServerOverride", testServer]
        app.launch()
        XCTAssertTrue(tab(app, "Settings").waitForExistence(timeout: 15))
        tab(app, "Settings").tap()
        let delete = app.buttons["Delete Account…"]
        for _ in 0..<6 where !(delete.exists && delete.isHittable) { app.swipeUp() }
        snap("delete-account-row")
        delete.tap()
        let go = app.buttons["Sign Out and Continue"]
        XCTAssertTrue(go.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Email Me a Deletion Link"].exists)
        snap("delete-account-confirm")
        go.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15), "The deletion page opens in the browser")
        sleep(2)
        snap("delete-account-browser")
        app.activate()
        XCTAssertTrue(app.buttons["I Already Have an Account"].waitForExistence(timeout: 10), "Signed out, back at the first page")
    }

    /// A free account writes without photos or links, can delete but not edit, and has no Stats.
    /// TEST_RUNNER_DABBLE_FREE_TOKEN.
    func testFreeAccountLimits() throws {
        guard let free = ProcessInfo.processInfo.environment["DABBLE_FREE_TOKEN"] else { throw XCTSkip("Needs TEST_RUNNER_DABBLE_FREE_TOKEN") }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", free, "-DabbleServerOverride", testServer]
        app.launch()

        // On This Day is PRO: Today says so (no throwback in its place).
        XCTAssertTrue(app.staticTexts["On This Day"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["See what you wrote on this date in past years with Dabble Me PRO."].exists)
        XCTAssertFalse(app.staticTexts["Rewind"].exists)
        snap("free-on-this-day")
        // Meanwhile, a random memory (free): the same sheet as shaking the phone.
        app.buttons["See a Random Memory"].tap()
        XCTAssertTrue(app.staticTexts["A Random Memory"].waitForExistence(timeout: 5))
        // The journal's only entry: Open, with no arrows to step to another.
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Previous Entry"].exists)
        XCTAssertFalse(app.buttons["Next Entry"].exists)
        snap("random-only-entry")
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
        // Photos are PRO: the button is there, and says so.
        if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
        editor.tap()
        XCTAssertTrue(app.buttons["Add Photos"].waitForExistence(timeout: 5))
        app.buttons["Add Photos"].tap()
        XCTAssertTrue(app.alerts["Photos are a PRO feature"].waitForExistence(timeout: 5))
        snap("free-photos-pro")
        app.alerts.buttons["OK"].tap()
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

        // Reminders: the daily one is for everyone.
        tab(app, "Settings").tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Push'")).firstMatch.tap()
        let daily = app.switches["Push Notifications"]
        XCTAssertTrue(daily.waitForExistence(timeout: 10))
        XCTAssertTrue(daily.isEnabled)
        snap("free-reminders")
    }

    /// A free account sees Daily Email greyed out with the rest of Reminders. TEST_RUNNER_DABBLE_FREE_TOKEN.
    func testEmailScheduleFreeAccount() throws {
        guard let free = ProcessInfo.processInfo.environment["DABBLE_FREE_TOKEN"] else { throw XCTSkip("Needs TEST_RUNNER_DABBLE_FREE_TOKEN") }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", free, "-DabbleServerOverride", testServer]
        app.launch()
        tab(app, "Settings").tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Email'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(row.isEnabled)
        snap("email-schedule-free")
    }

    /// Shaking shows a random entry as a preview over what you're reading; Open goes to it.
    /// Settings → Shake for Random Entry: switched off, a shake does nothing.
    func testShakeCanBeSwitchedOff() throws {
        let app = launch()
        tab(app, "Settings").tap()
        let toggle = app.switches["Shake for Random Entry"]
        for _ in 0..<5 where !toggle.exists { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1", "On to begin with")
        snap("settings-shake")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        XCUIDevice.shared.system.open(URL(string: "me.dabble.app:/shake")!) // Debug stand-in for a shake
        XCTAssertFalse(app.staticTexts["A Random Memory"].waitForExistence(timeout: 4), "Nothing comes up")
        // Back on (for the other tests), and it works again.
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCUIDevice.shared.system.open(URL(string: "me.dabble.app:/shake")!)
        XCTAssertTrue(app.staticTexts["A Random Memory"].waitForExistence(timeout: 10))
    }

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
        // The arrows beside Open step to the entry before or after (one is off at either end).
        let previous = app.buttons["Previous Entry"], next = app.buttons["Next Entry"]
        XCTAssertTrue(previous.exists && next.exists)
        let arrow = previous.isEnabled ? previous : next
        let before = arrow.value as? String
        arrow.tap()
        sleep(2)
        XCTAssertNotEqual(arrow.value as? String, before, "A different entry is showing")
        snap("shake-memory-stepped")
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

    /// A list inside a list item reads set in under it, numbered on its own, and opens in the
    /// editor the same way (it used to be web-only, and read as a bare "1." over its text).
    func testNestedListReadsAndEdits() throws {
        let app = launch()
        tab(app, "Journal").tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Planning the cabin weekend")).firstMatch
        app.scrollTo(row)
        row.tapRowText()
        // A long entry expands on the first tap and opens on the second.
        if !app.buttons["Edit Entry"].waitForExistence(timeout: 3) { row.tapRowText() }
        XCTAssertTrue(app.buttons["Edit Entry"].waitForExistence(timeout: 10))
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        let shown = text.value as? String ?? ""
        XCTAssertTrue(shown.contains("1. Food\n    1. Chili for Friday night\n    2. Pancake mix"), shown)
        XCTAssertTrue(shown.contains("2. Games\n    • Cards"), shown)
        snap("nested-list")
        app.buttons["Edit Entry"].tap()
        let editor = app.textViews["Entry"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "Editable in the app")
        XCTAssertTrue((editor.value as? String ?? "").contains("1. Food\n    1. Chili for Friday night"))
        snap("nested-list-editing")
        app.buttons["Cancel"].tap()
        if app.buttons["Discard"].waitForExistence(timeout: 2) { app.buttons["Discard"].tap() }
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
