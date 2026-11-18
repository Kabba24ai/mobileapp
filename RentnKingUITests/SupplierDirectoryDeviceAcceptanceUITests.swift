//
//  SupplierDirectoryDeviceAcceptanceUITests.swift
//  RentnKingUITests — Supplier Directory on a PHYSICAL phone against the company's own
//  Kabba (2026-11-14), using the session already signed in on the phone. No harness
//  arguments are passed, so nothing about the sign-in or the server is changed.
//
//  Env (forwarded by xcodebuild as TEST_RUNNER_*):
//    KABBA_SUPPLIER_SEARCH        text that finds at least one existing supplier (required)
//    KABBA_SUPPLIER_CREATE_NAME   when set, D2 ADDS a supplier with this exact name — a real
//                                 record in that company's Kabba. Leave unset to skip D2.
//

import XCTest

final class SupplierDirectoryDeviceAcceptanceUITests: XCTestCase {

    private var searchText = ""
    private var createName = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        searchText = env["KABBA_SUPPLIER_SEARCH"] ?? ""
        createName = env["KABBA_SUPPLIER_CREATE_NAME"] ?? ""
    }

    /// Home → Suppliers → the directory loads → search → open a supplier → its record shows.
    func test_d1_lookUpOnTheSignedInKabba() throws {
        XCTAssertFalse(searchText.isEmpty, "set KABBA_SUPPLIER_SEARCH")
        let app = launchSignedIn()
        app.buttons["home.suppliers"].tap()
        let table = app.tables["suppliers.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 20), "the directory did not open")
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 30), "no suppliers listed")
        XCTAssertFalse(app.staticTexts["suppliers.message"].exists && !app.staticTexts["suppliers.message"].label.isEmpty
                       && table.cells.count == 0, "the directory shows a message instead of suppliers")
        shoot(app, "d1-directory")
        search(app, searchText)
        let first = table.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), "searching '\(searchText)' found nothing")
        shoot(app, "d1-search")
        first.tap()
        let name = app.staticTexts["suppliers.detail.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 20), "the supplier record did not open")
        XCTAssertFalse(name.label.isEmpty)
        shoot(app, "d1-record")
    }

    /// Add Supplier → Saved → the record opens → it is searchable at once.
    func test_d2_addASupplierToTheSignedInKabba() throws {
        try XCTSkipIf(createName.isEmpty, "KABBA_SUPPLIER_CREATE_NAME not set — nothing is added")
        let app = launchSignedIn()
        app.buttons["home.suppliers"].tap()
        tap(app.buttons["suppliers.add"])
        let field = app.textFields["suppliers.add.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        tap(field)
        field.typeText(createName)
        dismissKeyboard(app)
        shoot(app, "d2-form")
        tap(app.buttons["suppliers.add.save"])

        let saved = app.alerts["Supplier Saved"]
        if !saved.waitForExistence(timeout: 30) { shoot(app, "d2-not-saved") }
        XCTAssertTrue(saved.exists, "the employee was not told it was saved (a duplicate sheet or an error?)")
        shoot(app, "d2-saved")
        saved.buttons["OK"].tap()
        let title = app.staticTexts["suppliers.detail.name"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, createName, "the new record opens")
        XCTAssertTrue(app.staticTexts["suppliers.detail.status"].label.hasPrefix("Active"), "added as Active")
        shoot(app, "d2-record")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.tables["suppliers.table"].waitForExistence(timeout: 10))
        search(app, createName)
        XCTAssertTrue(app.staticTexts[createName].waitForExistence(timeout: 20), "not searchable right away")
        shoot(app, "d2-searchable")
    }

    // MARK: - Helpers

    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        for host in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] where host.buttons["Not Now"].firstMatch.exists {
            host.buttons["Not Now"].firstMatch.tap()
        }
        let tile = app.buttons["home.suppliers"]
        if !tile.waitForExistence(timeout: 40) {
            shoot(app, "not-signed-in")
            XCTFail(app.buttons["login.button"].exists
                    ? "the phone is not signed in to Kabba — sign in once on the phone, then re-run"
                    : "Home with the Suppliers tile did not appear")
        }
        return app
    }

    private func search(_ app: XCUIApplication, _ text: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        if field.buttons["Clear text"].exists { field.buttons["Clear text"].tap() }
        field.typeText(text + "\n")
        sleep(3)
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        let done = app.toolbars.buttons["Done"].firstMatch
        if done.exists { done.tap() } else { app.scrollViews.firstMatch.swipeDown() }
        let deadline = Date().addingTimeInterval(4)
        while app.keyboards.count > 0 && Date() < deadline { usleep(200_000) }
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "\(element) never appeared")
        var tries = 0
        while !element.isHittable && tries < 6 { XCUIApplication().swipeUp(); tries += 1 }
        element.tap()
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
