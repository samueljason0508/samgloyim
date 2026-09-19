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

    func testBudgetAndSavingsGoalCanBeUpdated() {
        tap(app.buttons["tab-Plan"])
        XCTAssertTrue(app.staticTexts["Little by little."].waitForExistence(timeout: 5))
        screenshot("Plan before edit")
        tap(app.buttons["budget-Home & bills"])
        XCTAssertTrue(app.textFields["budget-amount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["budget-amount"].value as? String, "700.00")
        fill("budget-amount", "800.00")
        tap(app.buttons["save-budget"])
        XCTAssertTrue(app.staticTexts["of $800"].waitForExistence(timeout: 5))
        tap(app.buttons["plan-Savings goals"])
        tap(app.buttons["Add savings goal"])
        fill("goal-name", "Test adventure")
        fill("goal-target", "500.00")
        fill("goal-saved", "100.00")
        tap(app.buttons["save-goal"])
        tap(app.buttons["goal-Test adventure"])
        XCTAssertEqual(app.textFields["goal-saved"].value as? String, "100.00")
    }

    func testFreshStartAndAccountCreation() {
        tap(app.buttons["Settings"])
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

    func testScreensAndCategoryDrilldown() {
        screenshot("Overview")
        tap(app.buttons["tab-Activity"])
        screenshot("Activity")
        tap(app.buttons["tab-Plan"])
        screenshot("Budgets")
        tap(app.buttons["tab-Insights"])
        screenshot("Insights")
        tap(app.buttons["category-Home & bills"])
        XCTAssertTrue(app.staticTexts["Monthly rent"].waitForExistence(timeout: 5))
    }
}
