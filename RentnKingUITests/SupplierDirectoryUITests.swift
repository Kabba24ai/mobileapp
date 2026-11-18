//
//  SupplierDirectoryUITests.swift
//  RentnKingUITests — Supplier Directory (2026-11-13)
//
//  End to end against a local Laravel serving the suppliers API
//  (SupplierDirectoryStagingSeed.php; instructions in its header):
//
//   - look up a supplier, open it, follow its Website and Directions links
//     (Safari / Apple Maps open) and see the contacts on file;
//   - the directory pages past the first 25 suppliers;
//   - add a supplier from the phone → "Supplier Saved", the record opens and is
//     searchable at once; adding it again offers the existing record;
//   - an account outside the employee policy is told plainly.
//
//  TEST_RUNNER_KABBA_BASE_URL=http://localhost:8124/api/admin/v1/ \
//  [TEST_RUNNER_KABBA_SHOT_DIR=<dir>] xcodebuild test -project RentnKing.xcodeproj \
//    -scheme RentnKingUITests -destination 'platform=iOS Simulator,name=iPhone 17' \
//    -only-testing:RentnKingUITests/SupplierDirectoryUITests
//

import XCTest

final class SupplierDirectoryUITests: XCTestCase {

    private var env: [String: String] = [:]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        env = ProcessInfo.processInfo.environment
        addUIInterruptionMonitor(withDescription: "system-permission") { alert in
            for label in ["Allow", "Allow While Using App", "OK", "Not Now", "Don’t Allow", "Don't Allow"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
    }

    // MARK: - Look up

    func test_lookUp_openASupplier_andFollowItsLinks() {
        let app = signIn(as: "erin@suppliers.local")
        tap(app.buttons["home.suppliers"])
        XCTAssertTrue(app.tables["suppliers.table"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Directory Filler 01"].waitForExistence(timeout: 20), "alphabetical Active suppliers")
        XCTAssertTrue(app.buttons["suppliers.add"].exists, "Add Supplier is offered")
        shoot(app, "s01-directory")

        // Pages past the first 25.
        for _ in 0..<12 where !app.staticTexts["Directory Filler 30"].exists { app.tables["suppliers.table"].swipeUp() }
        XCTAssertTrue(app.staticTexts["Directory Filler 30"].waitForExistence(timeout: 10), "the next page loads as the list scrolls")

        // Search by a contact's name.
        search(app, "Dana")
        let smoky = app.staticTexts["Smoky Mountain Hydraulics"]
        XCTAssertTrue(smoky.waitForExistence(timeout: 15), "found by the primary contact's name")
        XCTAssertFalse(app.staticTexts["Directory Filler 01"].exists)
        shoot(app, "s02-search-contact")
        smoky.tap()

        XCTAssertTrue(app.staticTexts["suppliers.detail.name"].waitForExistence(timeout: 15))
        for id in ["suppliers.detail.phone", "suppliers.detail.email", "suppliers.detail.website", "suppliers.detail.address",
                   "suppliers.detail.primary_contact.phone", "suppliers.detail.inside_sales.phone"] {
            XCTAssertTrue(app.buttons[id].exists, "\(id) is shown and tappable")
        }
        XCTAssertFalse(app.buttons["suppliers.detail.billing_contact.phone"].exists, "no billing contact on file — none invented")
        XCTAssertFalse(app.staticTexts["Payment terms"].exists, "payment terms are not shown to an employee")
        shoot(app, "s03-detail")

        // Website → Safari.
        tap(app.buttons["suppliers.detail.website"])
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20), "the website opens in Safari")
        app.activate()
        XCTAssertTrue(app.staticTexts["suppliers.detail.name"].waitForExistence(timeout: 15))

        // Address → Apple Maps directions.
        tap(app.buttons["suppliers.detail.address"])
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        XCTAssertTrue(maps.wait(for: .runningForeground, timeout: 20), "the address opens Apple Maps")
        sleep(3)
        shootScreen("s04-maps-directions")
        app.activate()
        XCTAssertTrue(app.staticTexts["suppliers.detail.name"].waitForExistence(timeout: 15))
    }

    // MARK: - Add

    func test_addASupplier_itOpens_isSearchable_andADuplicateOffersTheExistingRecord() {
        let app = signIn(as: "erin@suppliers.local")
        tap(app.buttons["home.suppliers"])
        tap(app.buttons["suppliers.add"])
        XCTAssertTrue(app.textFields["suppliers.add.name"].waitForExistence(timeout: 15))

        // The name is the only required field.
        tap(app.buttons["suppliers.add.save"])
        XCTAssertTrue(app.staticTexts["suppliers.add.error.name"].waitForExistence(timeout: 5))
        shoot(app, "s05-name-required")

        let name = "Phone Added Supply \(Int(Date().timeIntervalSince1970) % 100_000)"
        type(app, "suppliers.add.name", name)
        type(app, "suppliers.add.phone", "6155550188")
        type(app, "suppliers.add.email", "orders@phoneadded.example")
        dismissKeyboard(app)
        tap(app.buttons["suppliers.add.section.primary_contact"])
        type(app, "suppliers.add.primary_contact_name", "Robin Field")
        dismissKeyboard(app)
        shoot(app, "s06-form")
        tap(app.buttons["suppliers.add.save"])

        let saved = app.alerts["Supplier Saved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 20), "the employee is told it was saved")
        shoot(app, "s07-saved")
        saved.buttons["OK"].tap()
        let title = app.staticTexts["suppliers.detail.name"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, name, "the new record opens")
        XCTAssertTrue(app.staticTexts["suppliers.detail.status"].label.hasPrefix("Active"), "added as Active")

        // Back lands on the directory, where it is searchable at once.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.tables["suppliers.table"].waitForExistence(timeout: 10))
        search(app, name)
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15))
        shoot(app, "s08-searchable")

        // Adding it again offers the existing record.
        tap(app.buttons["suppliers.add"])
        type(app, "suppliers.add.name", name.uppercased() + " LLC")
        dismissKeyboard(app)
        tap(app.buttons["suppliers.add.save"])
        let open = app.buttons["Open \(name)"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "the likely duplicate is offered")
        XCTAssertTrue(app.buttons["Add as a Different Supplier"].exists)
        shoot(app, "s09-duplicate")
        open.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, name, "the existing record opened instead of a second one")
    }

    // MARK: - Refused

    func test_anAccountOutsideTheEmployeePolicyIsToldPlainly() {
        let app = signIn(as: "casey@suppliers.local")
        tap(app.buttons["home.suppliers"])
        let message = app.staticTexts["suppliers.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 20))
        XCTAssertTrue(message.label.contains("does not have access"))
        XCTAssertFalse(app.buttons["suppliers.add"].isHittable)
        shoot(app, "s10-refused")
    }

    // MARK: - Helpers

    private func signIn(as email: String) -> XCUIApplication {
        let base = env["KABBA_BASE_URL"] ?? ""
        XCTAssertFalse(base.isEmpty, "KABBA_BASE_URL not provided")
        let app = XCUIApplication()
        app.launchArguments += ["-KabbaBaseURL", base, "-KabbaCompanyCode", "KABBA",
                                "-KabbaEmail", email, "-KabbaPassword", env["KABBA_PASSWORD"] ?? "supplier-pass-123"]
        app.launch()
        let login = app.buttons["login.button"]
        XCTAssertTrue(login.waitForExistence(timeout: 40), "staging Login screen did not appear")
        login.tap()
        let deadline = Date().addingTimeInterval(60)
        var lastTap = Date()
        while Date() < deadline, login.exists {
            usleep(400_000)
            dismissSystemSheets(app)
            if login.exists, Date().timeIntervalSince(lastTap) > 6 { login.tap(); lastTap = Date() }
        }
        XCTAssertFalse(login.exists, "still on the Login screen after sign-in")
        dismissSystemSheets(app)
        XCTAssertTrue(app.buttons["home.suppliers"].waitForExistence(timeout: 20), "Suppliers tile on Home")
        XCTAssertTrue(app.buttons["home.suppliers"].isHittable, "the tile fits on screen")
        XCTAssertTrue(app.buttons["home.equipmentAudit"].isHittable, "Equipment Audit keeps its place")
        shoot(app, "home")
        return app
    }

    private func search(_ app: XCUIApplication, _ text: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if field.buttons["Clear text"].exists { field.buttons["Clear text"].tap() }
        field.typeText(text + "\n")
    }

    private func type(_ app: XCUIApplication, _ id: String, _ text: String) {
        let field = app.textFields[id]
        tap(field)
        field.typeText(text)
    }

    /// The app-wide keyboard toolbar sits over whatever is below the field — put it away first.
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        let done = app.toolbars.buttons["Done"].firstMatch
        if done.exists { done.tap() } else { app.scrollViews.firstMatch.swipeDown() }
        let deadline = Date().addingTimeInterval(4)
        while app.keyboards.count > 0 && Date() < deadline { usleep(200_000) }
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "\(element) never appeared", file: file, line: line)
        var tries = 0
        while !element.isHittable && tries < 6 { XCUIApplication().swipeUp(); tries += 1 }
        element.tap()
    }

    private func dismissSystemSheets(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for host in [app, springboard] where host.buttons["Not Now"].firstMatch.exists {
            host.buttons["Not Now"].firstMatch.tap()
        }
    }

    private func shoot(_ app: XCUIApplication, _ name: String) { save(app.screenshot(), name) }

    private func shootScreen(_ name: String) { save(XCUIScreen.main.screenshot(), name) }

    private func save(_ screenshot: XCUIScreenshot, _ name: String) {
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        if let dir = env["KABBA_SHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
