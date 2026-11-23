import StoreKitTest
import XCTest

/// Settings → Plan → buy PRO Yearly against Xcode's StoreKit testing (DabbleMe.storekit) and a
/// local server, with screenshots in TEST_RUNNER_DABBLE_DEBUG_DIR. Opt-in:
/// TEST_RUNNER_DABBLE_PURCHASE_TOKEN, a Free account's app token. The server refuses the purchase
/// ("could not be verified"): Xcode signs it, not Apple. testPlanShowsAppleSubscription needs the
/// account given an AppleSubscription by hand, and TEST_RUNNER_DABBLE_PURCHASE_GRANTED=1.
@MainActor
final class PurchaseSmokeTests: XCTestCase {
    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["DABBLE_DEBUG_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    func testBuyYearlyFromPlan() throws {
        guard let token = ProcessInfo.processInfo.environment["DABBLE_PURCHASE_TOKEN"] else {
            throw XCTSkip("Needs a local server and a Free account's token")
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "DabbleMe", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = false

        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", testServer]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan'")).firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 10), "Settings has the Plan row")
        sleep(1)
        snap("1-settings")
        plan.tap()

        let yearly = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'PRO Yearly'")).firstMatch
        XCTAssertTrue(yearly.waitForExistence(timeout: 15), "The plans load from StoreKit")
        sleep(1)
        snap("2-plan-paywall")
        yearly.tap()

        // The purchase sheet is StoreKit's own; its button may be in the app or in SpringBoard.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirm = NSPredicate(format: "label IN {'Subscribe', 'Confirm', 'Start Free Trial', 'Try It Free', 'Purchase'}")
        let candidates = [app.buttons.matching(confirm).firstMatch, springboard.buttons.matching(confirm).firstMatch]
        var button: XCUIElement?
        for _ in 0..<20 where button == nil {
            button = candidates.first { $0.exists }
            if button == nil { sleep(1) }
        }
        sleep(1)
        snap("3-purchase-sheet")
        try XCTUnwrap(button, "StoreKit's purchase sheet has a confirm button").tap()

        let ok = app.buttons["OK"]
        let done = ok.waitForExistence(timeout: 15) ? ok : springboard.buttons["OK"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "StoreKit says the purchase went through")
        snap("4-storekit-done")
        done.tap()
        sleep(3)
        snap("5-after-purchase")
    }

    /// The Plan page once the server has an App Store subscription for the account.
    func testPlanShowsAppleSubscription() throws {
        guard let token = ProcessInfo.processInfo.environment["DABBLE_PURCHASE_TOKEN"],
              ProcessInfo.processInfo.environment["DABBLE_PURCHASE_GRANTED"] != nil else {
            throw XCTSkip("Needs a local server and an account with an App Store subscription")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-DabbleDebugAccessToken", token, "-DabbleServerOverride", testServer]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Plan'")).firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 10))
        sleep(1)
        snap("6-settings-pro")
        plan.tap()
        XCTAssertTrue(app.buttons["Manage Subscription"].waitForExistence(timeout: 10))
        sleep(1)
        snap("7-plan-pro")
    }
}
