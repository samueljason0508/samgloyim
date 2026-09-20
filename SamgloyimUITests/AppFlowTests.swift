import XCTest

final class AppFlowTests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    private func tap(_ element: XCUIElement) {
        if !element.exists { XCTAssertTrue(element.waitForExistence(timeout: 8)) }
        if !element.isHittable {
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
            _ = XCTWaiter.wait(for: [hittable], timeout: 3)
        }
        if !element.isHittable {
            if element.elementType == .textField {
                print("FORM DEBUG: \(app.debugDescription)")
                screenshot("Form before typing")
            } else {
                for _ in 0..<5 where !element.isHittable { app.scrollViews.firstMatch.swipeUp() }
            }
        }
        XCTAssertTrue(element.isEnabled, "The control must be enabled before tapping")
        element.tap()
    }
    private func fill(_ identifier: String, _ value: String) {
        let field = app.textFields[identifier]
        tap(field)
        // Right-aligned amount fields place a center tap before the existing text.
        // Move to the trailing edge so backspaces actually replace the full value.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        if let current = field.value as? String, !current.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)) }
        field.typeText(value)
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    /// A SwiftUI `List` keeps offscreen rows out of the accessibility tree entirely, so a row
    /// below the fold has to be scrolled into range before it can be found. How far down a
    /// Settings row sits depends on how many accounts and banks are connected.
    private func revealInList(_ element: XCUIElement) {
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        for _ in 0..<8 where !element.exists { list.swipeUp() }
    }

    func testCreateEditPersistAndDeleteTransaction() {
        tap(app.buttons["add-expense"])
        fill("transaction-amount", "12.34")
        fill("transaction-merchant", "UITest Lunch")
        tap(app.buttons["save-transaction"])
        tap(app.buttons["tab-Activity"])
        fill("transaction-search", "UITest Lunch")
        app.textFields["transaction-search"].typeText("\n")
        tap(app.buttons["transaction-UITest Lunch"].firstMatch)
        fill("transaction-amount", "18.75")
        tap(app.buttons["save-transaction"])
        XCTAssertTrue(app.staticTexts["−$18.75"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--uitesting", "--keep-data"]
        app.launch()
        tap(app.buttons["tab-Activity"])
        fill("transaction-search", "UITest Lunch")
        app.textFields["transaction-search"].typeText("\n")
        XCTAssertTrue(app.staticTexts["−$18.75"].waitForExistence(timeout: 5))
        tap(app.buttons["transaction-UITest Lunch"].firstMatch)
        tap(app.buttons["delete-transaction"])
        tap(app.sheets.buttons["Delete transaction"].firstMatch)
        XCTAssertTrue(app.staticTexts["Nothing here just yet"].waitForExistence(timeout: 5))
    }

    func testSampleImportExcludesExistingDuplicate() {
        tap(app.buttons["import-transactions"])
        tap(app.buttons["sample-import"])
        XCTAssertTrue(app.staticTexts["2 found · 1 possible duplicate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["confirm-import"].label.contains("1 transaction"))
        screenshot("Import review")
        tap(app.buttons["confirm-import"])
        XCTAssertTrue(app.staticTexts["All settled."].waitForExistence(timeout: 5))
        tap(app.buttons["Back to my money"])
        tap(app.buttons["tab-Activity"])
        fill("transaction-search", "Sample Campus Café")
        app.textFields["transaction-search"].typeText("\n")
        XCTAssertTrue(app.staticTexts["Sample Campus Café"].waitForExistence(timeout: 5))
    }

    func testFreshStartAndAccountCreation() {
        tap(app.buttons["Settings"])
        revealInList(app.buttons["start-fresh"])
        tap(app.buttons["start-fresh"])
        tap(app.buttons["Clear data and start fresh"])
        XCTAssertTrue(app.staticTexts["$0.00"].firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["Settings"])
        tap(app.buttons["add-account"])
        fill("account-name", "Travel cash")
        fill("account-balance", "250.00")
        tap(app.buttons["save-account"])
        XCTAssertTrue(app.staticTexts["Travel cash"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["$250.00"].waitForExistence(timeout: 5))
    }

    /// Scans the fixture receipt and stops on the match screen.
    /// Requires it in the simulator library first:
    /// `xcrun simctl addmedia <device> Samples/receipt_trader_joes.png`.
    private func scanFixtureReceipt() throws {
        tap(app.buttons["import-transactions"])
        tap(app.buttons["scan-receipt"])
        XCTAssertTrue(app.buttons["scan-library"].waitForExistence(timeout: 5))
        tap(app.buttons["scan-library"])
        // The system picker hosts its grid cells as images, newest first.
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        guard photo.waitForExistence(timeout: 15) else {
            throw XCTSkip("The system photo picker presented no images. Add the fixture with simctl addmedia.")
        }
        photo.tap()
        XCTAssertTrue(app.staticTexts["We found a match"].waitForExistence(timeout: 25))
    }

    /// The fixture's $68.42 total matches the Trader Joe's purchase in the sample data.
    func testScannedReceiptMapsToCardPurchase() throws {
        try scanFixtureReceipt()
        XCTAssertTrue(app.staticTexts["Trader Joe’s"].exists)
        XCTAssertTrue(app.staticTexts["$68.42"].firstMatch.exists)
        screenshot("Receipt matched to purchase")
        tap(app.buttons["confirm-match"])
        XCTAssertTrue(app.staticTexts["Matched."].waitForExistence(timeout: 5))
        screenshot("Receipt attached")
    }

    func testUserCanMapAReceiptToADifferentPurchaseByHand() throws {
        try scanFixtureReceipt()
        tap(app.buttons["Pick a different purchase"])
        XCTAssertTrue(app.textFields["purchase-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["confirm-manual-match"].isEnabled, "Nothing is attached until the user picks a purchase")
        fill("purchase-search", "Chipotle")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Map receipt to Chipotle'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        screenshot("Mapping a receipt by hand")
        tap(app.buttons["confirm-manual-match"])
        XCTAssertTrue(app.staticTexts["Matched."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This receipt is now filed with Chipotle · $14.85."].exists)
    }

    func testFollowYourMoneyCanBreakDownByAccount() {
        tap(app.buttons["tab-Insights"])
        XCTAssertTrue(app.buttons["flow-Account"].waitForExistence(timeout: 5))
        tap(app.buttons["flow-Account"])
        let share = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'percent of spending'"))
        XCTAssertTrue(share.firstMatch.waitForExistence(timeout: 5), "Each account should report its own share of spending")
        screenshot("Spending by account")
        tap(app.buttons["flow-Flow"])
        XCTAssertTrue(app.staticTexts["ACCOUNTS"].waitForExistence(timeout: 5))
    }

    func testManualTransactionShowsItsTime() {
        tap(app.buttons["add-expense"])
        fill("transaction-amount", "9.99")
        fill("transaction-merchant", "Timed Coffee")
        tap(app.buttons["save-transaction"])
        tap(app.buttons["tab-Activity"])
        fill("transaction-search", "Timed Coffee")
        app.textFields["transaction-search"].typeText("\n")
        XCTAssertTrue(app.staticTexts["Timed Coffee"].waitForExistence(timeout: 5))
        // Manual entries carry a real clock time; imported rows land on midnight and stay date-only.
        let timed = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*\\d{1,2}:\\d{2}.*")).firstMatch
        XCTAssertTrue(timed.waitForExistence(timeout: 5), "A manually added transaction should show the time it was recorded")
        screenshot("Activity with time")
    }

    func testScreensAndCategoryDrilldown() {
        screenshot("Overview")
        tap(app.buttons["tab-Activity"])
        screenshot("Activity")
        tap(app.buttons["tab-Insights"])
        screenshot("Insights")
        tap(app.buttons["category-Home & bills"])
        XCTAssertTrue(app.staticTexts["Monthly rent"].waitForExistence(timeout: 5))
    }
}
