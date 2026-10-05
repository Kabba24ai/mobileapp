//
//  EquipmentAuditUITests.swift
//  RentnKingUITests — the mobile Equipment Audit against a seeded staging audit
//  (2026-10-05). Drives the real screens through the DEBUG-only
//  StagingTestHarness, like AuthFlowUITests:
//
//    John (all audit permissions, Bon Aqua's Section Auditor):
//      Home → Equipment Audit → his audit ("Bon Aqua — Assigned to You")
//      → lands on Bon Aqua → one-tap Verify turns a row green
//      → a Waverly unit found in Bon Aqua: Location Mismatch → Verify & Move
//      → Mark Unresolved (note required) → a rental found in the yard
//      → Move Off-Site (Equipment's fields) → an Off-Site unit returned On-Site
//      → Verified By for one unit only.
//    Vera (View + Verify only): one-tap verify where Kabba shows it; a
//      mismatch can only be recorded as Unresolved; no Move Off-Site.
//    Billy (no audit permission): told plainly, nothing to act on.
//
//  Env (runner): KABBA_BASE_URL (e.g. http://localhost:8124/api/admin/v1/),
//  KABBA_PASSWORD; KABBA_SHOT_DIR (optional) writes screenshots to disk.
//  The staging audit is seeded by the Laravel side (seed_audit.php) — each
//  scenario touches its own units, and a re-run needs a fresh seed.
//

import XCTest

final class EquipmentAuditUITests: XCTestCase {

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

    // MARK: - John: the yard workflow

    func test_john_audits_his_section_from_the_phone() {
        let app = signIn(as: "john@audit.local")
        openAudit(app)

        // Lands on his own section; Waverly (Ashley's) is not in his default view.
        XCTAssertTrue(app.staticTexts["ASSIGNED TO YOU"].waitForExistence(timeout: 10), "his section is marked Assigned to You")
        XCTAssertTrue(app.staticTexts["Bon Aqua — John Yard"].exists)
        XCTAssertFalse(app.cells["equipmentAudit.row.SS-104"].exists, "Waverly is not in his default filter")
        XCTAssertTrue(app.buttons["equipmentAudit.workingStore"].label.contains("Bon Aqua"), "working at his assigned store")
        shoot(app, "01-board-landing")

        // 1. Normal case: one tap.
        tap(app.buttons["equipmentAudit.verify.TAK-SS-14"])
        waitForState(app, "TAK-SS-14", "Verified")
        XCTAssertTrue(app.staticTexts["equipmentAudit.freshness"].label.contains("TAK-SS-14 verified."), "Kabba's confirmation, without blocking the next tap")
        XCTAssertTrue(app.cells["equipmentAudit.row.TAK-SS-14"].staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Verified · Bon Aqua · John'")).firstMatch.exists)
        shoot(app, "02-one-tap-verified")

        // 2. A Waverly unit standing in Bon Aqua: explicit mismatch, canonical move.
        search(app, "SS-88")
        tap(app.buttons["equipmentAudit.verify.SS-88"])
        let mismatch = app.alerts["Location Mismatch"]
        XCTAssertTrue(mismatch.waitForExistence(timeout: 5))
        XCTAssertTrue(mismatch.staticTexts.matching(NSPredicate(format: "label CONTAINS 'System Location: Waverly'")).firstMatch.exists)
        XCTAssertTrue(mismatch.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Observed Location: Bon Aqua'")).firstMatch.exists)
        XCTAssertTrue(mismatch.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Verified By: John Yard'")).firstMatch.exists,
                      "found at Bon Aqua: Bon Aqua's auditor, not Waverly's")
        shoot(app, "03-location-mismatch")
        mismatch.buttons["Verify & Move to Bon Aqua"].tap()
        waitForState(app, "SS-88", "Verified")
        XCTAssertTrue(app.cells["equipmentAudit.row.SS-88"].staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Verified · Bon Aqua · John'")).firstMatch.exists)
        clearSearch(app)
        XCTAssertTrue(app.cells["equipmentAudit.row.SS-88"].waitForExistence(timeout: 10), "it now lives in Bon Aqua, John's section")

        // 3. Mark Unresolved — a note is required.
        tap(app.buttons["equipmentAudit.more.TAK-SS-16"])
        choose(app, "Mark Unresolved…")
        let noteAlert = app.alerts["Mark Unresolved"]
        XCTAssertTrue(noteAlert.waitForExistence(timeout: 5))
        XCTAssertFalse(noteAlert.buttons["Mark Unresolved"].isEnabled, "no note, no Unresolved")
        noteAlert.textFields.firstMatch.typeText("Unable to establish actual location.")
        noteAlert.buttons["Mark Unresolved"].tap()
        waitForState(app, "TAK-SS-16", "Unresolved")
        XCTAssertTrue(scrollTo(app, app.staticTexts["Unresolved — No Section Auditor"]), "the shared Unresolved queue is in John's view")
        app.tables["equipmentAudit.rows"].swipeDown()
        shoot(app, "04-unresolved")

        // 4. A rented unit found in the yard: Unresolved, seen at Bon Aqua — the rental is not touched.
        search(app, "SS-110")
        tap(app.buttons["equipmentAudit.verify.SS-110"])
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.sheets.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Verify & Move'")).firstMatch.exists)
        choose(app, "Found at Bon Aqua — Mark Unresolved…")
        let rentalNote = app.alerts.firstMatch
        XCTAssertTrue(rentalNote.waitForExistence(timeout: 5))
        rentalNote.textFields.firstMatch.typeText("Customer rental sitting on the Bon Aqua lot.")
        rentalNote.buttons["Mark Unresolved"].tap()
        waitForState(app, "SS-110", "Unresolved")
        clearSearch(app)

        // 5. Move Off-Site — Equipment's own fields; an empty manual entry gets Equipment's message.
        search(app, "TAK-SS-2")
        tap(app.buttons["equipmentAudit.more.TAK-SS-2"])
        choose(app, "Move Off-Site…")
        XCTAssertTrue(app.buttons["equipmentAudit.offSite.submit"].waitForExistence(timeout: 10))
        app.segmentedControls["equipmentAudit.offSite.source"].buttons["Manual Entry"].tap()
        tap(app.buttons["equipmentAudit.offSite.submit"])
        XCTAssertTrue(app.staticTexts["Enter a location name."].waitForExistence(timeout: 10), "Equipment's validation message, from Kabba")
        shoot(app, "05-off-site-validation")
        typeInto(app.textFields["equipmentAudit.offSite.location_name"], "Humphreys County Fair")
        typeInto(app.textFields["equipmentAudit.offSite.address_line_1"], "1 Fair Way")
        tap(app.buttons["equipmentAudit.offSite.submit"])
        waitForState(app, "TAK-SS-2", "Verified")
        XCTAssertTrue(app.staticTexts["Off-Site — No Section Auditor"].waitForExistence(timeout: 10), "now in the Off-Site section")
        shoot(app, "06-moved-off-site")
        clearSearch(app)

        // 6. An Off-Site unit found at Bon Aqua comes back through Return On-Site.
        search(app, "SS-4")
        tap(app.buttons["equipmentAudit.verify.SS-4"])
        let returning = app.alerts["Off-Site Unit Found"]
        XCTAssertTrue(returning.waitForExistence(timeout: 5))
        returning.buttons["Return On-Site to Bon Aqua"].tap()
        waitForState(app, "SS-4", "Verified")
        clearSearch(app)

        // 7. Verified By for one unit only.
        tap(app.buttons["equipmentAudit.more.TAK-SS-7"])
        choose(app, "Verified By…")
        let picker = app.tables["equipmentAudit.picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.staticTexts["Billy Bob"].tap()
        XCTAssertTrue(app.cells["equipmentAudit.row.TAK-SS-7"].staticTexts.matching(NSPredicate(format: "label CONTAINS 'By Billy'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.cells["equipmentAudit.row.TAK-SS-11"].staticTexts.matching(NSPredicate(format: "label CONTAINS 'By Billy'")).firstMatch.exists,
                       "the other units keep John")
        tap(app.buttons["equipmentAudit.verify.TAK-SS-7"])
        waitForState(app, "TAK-SS-7", "Verified")
        XCTAssertTrue(app.cells["equipmentAudit.row.TAK-SS-7"].staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Verified · Bon Aqua · Billy'")).firstMatch.exists)

        // Progress and completion follow the server.
        XCTAssertTrue(app.staticTexts["equipmentAudit.completion"].label.hasPrefix("Not ready to complete"))
        shoot(app, "07-board-after")
    }

    // MARK: - Vera: verify-only

    func test_a_verifier_without_correct_location_can_only_mark_a_mismatch_unresolved() {
        let app = signIn(as: "vera@audit.local")
        openAudit(app)

        // No assignment: every section is shown.
        search(app, "SS-104")
        tap(app.buttons["equipmentAudit.verify.SS-104"])
        waitForState(app, "SS-104", "Verified")
        clearSearch(app)

        // She is standing in Bon Aqua; a Waverly unit there cannot be moved by her.
        tap(app.buttons["equipmentAudit.workingStore"])
        let stores = app.tables["equipmentAudit.picker"]
        XCTAssertTrue(stores.waitForExistence(timeout: 5))
        stores.staticTexts["Bon Aqua"].tap()
        search(app, "SS-9")
        tap(app.buttons["equipmentAudit.more.SS-9"])
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.sheets.buttons["Move Off-Site…"].exists, "no Correct Location, no Move Off-Site")
        choose(app, "Found at Bon Aqua…")
        let mismatch = app.alerts["Location Mismatch"]
        XCTAssertTrue(mismatch.waitForExistence(timeout: 5))
        XCTAssertFalse(mismatch.buttons["Verify & Move to Bon Aqua"].exists)
        shoot(app, "08-verifier-mismatch")
        mismatch.buttons["Mark Unresolved…"].tap()
        let note = app.alerts["Mark Unresolved"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.textFields.firstMatch.typeText("Seen in Bon Aqua; Kabba says Waverly.")
        note.buttons["Mark Unresolved"].tap()
        waitForState(app, "SS-9", "Unresolved")
    }

    // MARK: - Billy: no audit permission

    func test_an_account_without_audit_permission_is_told_plainly() {
        let app = signIn(as: "billy@audit.local")
        tap(app.buttons["home.equipmentAudit"])
        let message = app.staticTexts["equipmentAudit.list.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 20))
        XCTAssertTrue(message.label.contains("does not have access"))
        shoot(app, "09-no-access")
    }

    // MARK: - Helpers

    private func signIn(as email: String) -> XCUIApplication {
        let base = env["KABBA_BASE_URL"] ?? ""
        XCTAssertFalse(base.isEmpty, "KABBA_BASE_URL not provided")
        let app = XCUIApplication()
        app.launchArguments += ["-KabbaBaseURL", base, "-KabbaCompanyCode", "KABBA",
                                "-KabbaEmail", email, "-KabbaPassword", env["KABBA_PASSWORD"] ?? "audit-pass-123"]
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
        XCTAssertTrue(app.buttons["home.equipmentAudit"].waitForExistence(timeout: 20), "Equipment Audit tile on Home")
        XCTAssertTrue(app.buttons["home.equipmentAudit"].isHittable, "the tile fits on screen")
        shoot(app, "home")
        return app
    }

    private func openAudit(_ app: XCUIApplication) {
        tap(app.buttons["home.equipmentAudit"])
        let card = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'equipmentAudit.audit.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the active audit is listed")
        shoot(app, "00-audit-list")
        card.tap()
        XCTAssertTrue(app.staticTexts["equipmentAudit.title"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["equipmentAudit.progress"].waitForExistence(timeout: 20))
    }

    /// Searches every section; "\n" submits, which dismisses the keyboard.
    private func search(_ app: XCUIApplication, _ text: String) {
        clearSearch(app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text + "\n")
    }

    /// Clearing returns to the list and puts the keyboard away (the board does that).
    private func clearSearch(_ app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        guard field.exists else { return }
        if field.buttons["Clear text"].exists {
            field.buttons["Clear text"].tap()
        }
        let deadline = Date().addingTimeInterval(4)
        while app.keyboards.count > 0 && Date() < deadline { usleep(200_000) }
        XCTAssertEqual(app.keyboards.count, 0, "clearing the search puts the keyboard away")
    }

    /// Scrolls the board until the element is on screen (off-screen headers are not in the tree).
    @discardableResult
    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.tables["equipmentAudit.rows"].swipeUp()
        }
        return element.exists
    }

    /// Picks a row-menu item once the menu has settled — it animates out of the
    /// tapped row, and a tap mid-animation can land on the neighbouring item.
    private func choose(_ app: XCUIApplication, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let item = app.sheets.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 8), "menu item \(title) missing", file: file, line: line)
        let deadline = Date().addingTimeInterval(5)
        while !item.isHittable && Date() < deadline { usleep(200_000) }
        usleep(700_000)
        item.tap()
    }

    private func typeInto(_ field: XCUIElement, _ text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    /// Taps once the element is on screen (scrolling the board if needed).
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "\(element) never appeared", file: file, line: line)
        var tries = 0
        while !element.isHittable && tries < 6 { XCUIApplication().swipeUp(); tries += 1 }
        element.tap()
    }

    private func waitForState(_ app: XCUIApplication, _ equipmentId: String, _ state: String, file: StaticString = #filePath, line: UInt = #line) {
        let icon = app.images["equipmentAudit.state.\(equipmentId)"]
        let predicate = NSPredicate(format: "label == %@", state)
        let found = XCTNSPredicateExpectation(predicate: predicate, object: icon)
        if XCTWaiter().wait(for: [found], timeout: 20) != .completed {
            let alert = app.alerts.firstMatch
            XCTFail("\(equipmentId) never became \(state)\(alert.exists ? " — alert: \(alert.label) \(alert.staticTexts.allElementsBoundByIndex.map(\.label))" : "")", file: file, line: line)
        }
    }

    private func dismissSystemSheets(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for host in [app, springboard] where host.buttons["Not Now"].firstMatch.exists {
            host.buttons["Not Now"].firstMatch.tap()
        }
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        if let dir = env["KABBA_SHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
