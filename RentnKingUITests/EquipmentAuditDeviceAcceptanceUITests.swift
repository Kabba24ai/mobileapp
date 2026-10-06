//
//  EquipmentAuditDeviceAcceptanceUITests.swift
//  RentnKingUITests — physical-iPhone acceptance for the mobile Equipment Audit
//  (2026-10-05). A–G run ONLY against a staging Laravel seeded with
//  EquipmentAuditStagingSeed-style data (the device seed: 26 Skid Steer units,
//  John = Bon Aqua Section Auditor) — never production; P is the read-only
//  production smoke. Every step attaches a
//  screenshot (export with `xcresulttool export attachments`) for review.
//
//    A  Home tile / list / board landing, canonical sort, filters, search (read-only)
//    B  scrolling smoothness (XCTOSSignpost scroll metrics)
//    C  write flows on STAGING data: one-tap verify, Verified By override,
//       Location Mismatch → Verify & Move, Mark Unresolved, Move Off-Site form
//    D  pull to refresh, background → foreground, 30 s refresh with a
//       colleague's verification arriving — the list must not jump
//    E  real Airplane Mode (Control Center): an audit action says nothing
//       was recorded; then Z restores the network and E3 confirms nothing
//       was queued — the unit still needs verification
//    F  server unreachable drill (opt-in, KABBA_SERVER_DRILL=1): the Mac stops
//       Laravel when it sees the marker request, restarts it 20 s later
//    G  Off-Site form keyboard flow (Return walks the fields; Cancel moves nothing)
//    P  PRODUCTION smoke on a Release build with the session already signed in on
//       the phone — read-only walkthrough (P1) and offline wording (P2, then Z)
//
//  Env (runner): KABBA_BASE_URL, KABBA_PASSWORD.
//

import XCTest

final class EquipmentAuditDeviceAcceptanceUITests: XCTestCase {

    private var env: [String: String] = [:]
    private var app: XCUIApplication!

    /// John's Bon Aqua section in AuditSort order (name, then natural Equipment ID).
    private static let bonAquaOrder = ["SS-101", "SS-102", "SS-104", "SS-106",
                                       "TAK-SS-1", "TAK-SS-2", "TAK-SS-3", "TAK-SS-5", "TAK-SS-7", "TAK-SS-9",
                                       "TAK-SS-11", "TAK-SS-12", "TAK-SS-14", "TAK-SS-16",
                                       "SS-120", "SS-112", "SS-113"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        env = ProcessInfo.processInfo.environment
        addUIInterruptionMonitor(withDescription: "system") { alert in
            for label in ["Allow", "Allow While Using App", "OK", "Not Now", "Don’t Allow", "Don't Allow"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
    }

    // MARK: - A. Home, list, board, sort, filter, search

    func test_A_home_list_board_sort_filters_search() {
        signIn("john@audit.local")

        // Home: the tile sits with the others, clear of the tab bar.
        let tile = app.buttons["home.equipmentAudit"]
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tile.isHittable)
        XCTAssertLessThan(tile.frame.maxY, tabBar.frame.minY, "tile clear of the tab bar")
        let queueLine = app.staticTexts["Queue Line"]
        if queueLine.exists { XCTAssertGreaterThan(tile.frame.minY, queueLine.frame.maxY) }
        note("home tile frame \(tile.frame), tab bar top \(tabBar.frame.minY), screen \(app.frame.size)")
        shoot("A1-home")

        // List: both audits, John's section called out with its progress.
        tap(tile)
        let skid = auditCell("Skid Steer Audit")
        XCTAssertTrue(skid.waitForExistence(timeout: 30))
        XCTAssertTrue(skid.staticTexts["Bon Aqua — Assigned to You"].exists)
        XCTAssertTrue(skid.staticTexts["0 of 17 Verified"].exists)
        XCTAssertTrue(auditCell("Mini Excavator Audit").exists, "the second audit is listed too")
        shoot("A2-list")

        // Board lands on Bon Aqua (+ the Unresolved queue); Waverly is not in the default view.
        skid.tap()
        XCTAssertTrue(app.staticTexts["ASSIGNED TO YOU"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Bon Aqua — John Yard"].exists)
        XCTAssertTrue(app.buttons["equipmentAudit.workingStore"].label.contains("Bon Aqua"))
        shoot("A3-board-landing")

        // Canonical sort through the whole section: Equipment Name, then natural Equipment ID.
        XCTAssertEqual(rowsInOrder(), Self.bonAquaOrder, "rows in AuditSort order")
        XCTAssertFalse(app.cells["equipmentAudit.row.TAK-SS-20"].exists, "Waverly hidden by default")
        shoot("A4-board-scrolled-end")
        table.swipeDown(velocity: .fast); table.swipeDown(velocity: .fast)

        // Filters: All → every section; Off-Site only; back to My Sections.
        openFilter()
        app.buttons["equipmentAudit.filter.all"].tap()
        shoot("A5-filter-sheet-all")
        app.buttons["equipmentAudit.filter.apply"].tap()
        for header in ["Waverly — Ashley Lot", "Customer Rentals — No Section Auditor", "Off-Site — No Section Auditor"] {
            XCTAssertTrue(scrollTo(app.staticTexts[header]), "\(header) shown with All")
        }
        shoot("A6-filter-all-board")
        table.swipeDown(velocity: .fast); table.swipeDown(velocity: .fast); table.swipeDown(velocity: .fast)

        openFilter()
        let filterTable = app.tables["equipmentAudit.filter"]
        for cell in filterTable.cells.allElementsBoundByIndex where !cell.identifier.hasSuffix("off_site") {
            cell.tap()   // All was selected — untick everything but Off-Site
        }
        app.buttons["equipmentAudit.filter.apply"].tap()
        XCTAssertTrue(app.staticTexts["Off-Site — No Section Auditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells["equipmentAudit.row.SS-4"].exists)
        XCTAssertFalse(app.staticTexts["Bon Aqua — John Yard"].exists)
        shoot("A7-filter-off-site-only")
        openFilter()
        app.buttons["equipmentAudit.filter.mine"].tap()
        XCTAssertTrue(app.staticTexts["Bon Aqua — John Yard"].waitForExistence(timeout: 5), "My Sections restores the default")

        // Search by name (across sections) and by Equipment ID.
        search("kubota")
        for id in ["SS-112", "SS-113", "SS-115"] { XCTAssertTrue(app.cells["equipmentAudit.row.\(id)"].waitForExistence(timeout: 5), id) }
        XCTAssertEqual(app.keyboards.count, 0, "submitting the search puts the keyboard away")
        shoot("A8-search-name")
        search("TAK-SS-14")
        XCTAssertTrue(app.cells["equipmentAudit.row.TAK-SS-14"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.cells["equipmentAudit.row.TAK-SS-12"].exists)
        XCTAssertTrue(app.buttons["equipmentAudit.verify.TAK-SS-14"].isHittable, "the row's Verify is not under the keyboard")
        shoot("A9-search-id")
        clearSearch()
        XCTAssertTrue(app.cells["equipmentAudit.row.SS-101"].waitForExistence(timeout: 5), "clearing returns to the list")
    }

    // MARK: - B. Scrolling

    func test_B_scrolling_through_the_section_is_smooth() {
        signIn("john@audit.local")
        openSkidAudit()
        openFilter()
        app.buttons["equipmentAudit.filter.all"].tap()
        app.buttons["equipmentAudit.filter.apply"].tap()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric, XCTOSSignpostMetric.scrollDraggingMetric], options: options) {
            table.swipeUp(velocity: .fast)
            table.swipeUp(velocity: .fast)
            table.swipeDown(velocity: .fast)
            table.swipeDown(velocity: .fast)
        }
        openFilter()
        app.buttons["equipmentAudit.filter.mine"].tap()
    }

    // MARK: - C. Write flows (staging data only)

    func test_C_write_flows_on_staging() {
        signIn("john@audit.local")
        openSkidAudit()

        // One tap, turns green, recorded for John (Bon Aqua's Section Auditor).
        tap(app.buttons["equipmentAudit.verify.TAK-SS-14"])
        waitForState("TAK-SS-14", "Verified")
        XCTAssertTrue(detail(of: "TAK-SS-14").hasPrefix("Verified · Bon Aqua · John"))
        shoot("C1-one-tap-verified")

        // Verified By for one unit only.
        tap(app.buttons["equipmentAudit.more.TAK-SS-16"])
        choose("Verified By…")
        XCTAssertTrue(app.tables["equipmentAudit.picker"].waitForExistence(timeout: 5))
        shoot("C2-verified-by-picker")
        app.tables["equipmentAudit.picker"].staticTexts["Billy Bob"].tap()
        XCTAssertTrue(waitFor { self.detail(of: "TAK-SS-16").contains("By Billy") })
        XCTAssertFalse(detail(of: "TAK-SS-12").contains("By Billy"), "only that unit")
        shoot("C3-override-one-unit")

        // A Waverly unit standing in Bon Aqua: explicit mismatch, then the canonical move.
        search("SS-88")
        tap(app.buttons["equipmentAudit.verify.SS-88"])
        let mismatch = app.alerts["Location Mismatch"]
        XCTAssertTrue(mismatch.waitForExistence(timeout: 10))
        XCTAssertTrue(mismatch.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Verified By: John Yard'")).firstMatch.exists)
        shoot("C4-mismatch")
        mismatch.buttons["Verify & Move to Bon Aqua"].tap()
        waitForState("SS-88", "Verified")
        clearSearch()

        // Mark Unresolved: note required.
        tap(app.buttons["equipmentAudit.more.TAK-SS-9"])
        choose("Mark Unresolved…")
        let note = app.alerts["Mark Unresolved"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertFalse(note.buttons["Mark Unresolved"].isEnabled)
        note.textFields.firstMatch.tap()
        note.textFields.firstMatch.typeText("Not on the Bon Aqua lot; checking with Waverly.")
        shoot("C5-unresolved-note-keyboard")
        note.buttons["Mark Unresolved"].tap()
        waitForState("TAK-SS-9", "Unresolved")

        // Move Off-Site: supplier picker, reason and notes with the keyboard up.
        search("TAK-SS-3")
        tap(app.buttons["equipmentAudit.more.TAK-SS-3"])
        choose("Move Off-Site…")
        XCTAssertTrue(app.buttons["equipmentAudit.offSite.submit"].waitForExistence(timeout: 20))
        shoot("C6-off-site-form")
        app.buttons["equipmentAudit.offSite.supplier"].tap()
        XCTAssertTrue(app.tables["equipmentAudit.picker"].waitForExistence(timeout: 5))
        app.tables["equipmentAudit.picker"].staticTexts["Parman Tractor"].tap()
        let reason = app.textFields["equipmentAudit.offSite.reason"]
        reason.tap(); reason.typeText("Hydraulic hose repair")
        shoot("C7-off-site-reason-keyboard")
        let notes = app.textFields["equipmentAudit.offSite.notes"]
        if !notes.isHittable { app.swipeUp() }
        notes.tap(); notes.typeText("Back by Friday")
        shoot("C8-off-site-notes-keyboard")
        app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] 'return' OR label ==[c] 'done'")).firstMatch.tap()
        tap(app.buttons["equipmentAudit.offSite.submit"])
        waitForState("TAK-SS-3", "Verified")
        XCTAssertTrue(app.staticTexts["Off-Site — No Section Auditor"].waitForExistence(timeout: 10))
        shoot("C9-moved-off-site")
        clearSearch()
    }

    // MARK: - D. Refresh, background, the 30 s refresh with a colleague's work

    func test_D_refresh_background_and_concurrent_update() throws {
        signIn("john@audit.local")
        openSkidAudit()
        table.swipeUp()
        let anchor = firstVisibleRow()
        note("anchor row \(anchor)")

        // Pull to refresh (from the top), then back to the same place.
        table.swipeDown(velocity: .fast); table.swipeDown(velocity: .fast)
        table.swipeDown(velocity: .slow)
        XCTAssertTrue(app.staticTexts["equipmentAudit.freshness"].waitForExistence(timeout: 10))
        table.swipeUp()
        let afterPull = firstVisibleRow()

        // Background and return: same screen, same place.
        XCUIDevice.shared.press(.home)
        sleep(4)
        app.activate()
        XCTAssertTrue(app.staticTexts["equipmentAudit.title"].waitForExistence(timeout: 10), "back on the board")
        XCTAssertEqual(firstVisibleRow(), afterPull, "background/foreground keeps the list where it was")
        shoot("D1-after-background")

        // Ashley verifies SS-102 from her phone; John's board shows it within the 30 s refresh.
        XCTAssertEqual(detailState("SS-102"), "Needs Verification")
        try colleagueVerifies("SS-102", as: "ashley@audit.local")
        let turned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Verified'"), object: app.images["equipmentAudit.state.SS-102"])
        XCTAssertEqual(XCTWaiter().wait(for: [turned], timeout: 45), .completed, "the open board picked up Ashley's verification by itself")
        XCTAssertTrue(detail(of: "SS-102").contains("Ashley"))
        XCTAssertEqual(firstVisibleRow(), afterPull, "the refresh did not jump the list")
        shoot("D2-colleague-update-arrived")
    }

    // MARK: - E. Real loss of connectivity

    // Turning Airplane Mode back OFF can invalidate Xcode's link to the phone,
    // which throws away the running test's screenshots. So E ends with the
    // phone still offline; run Z (restore) and then E3 as separate invocations.

    func test_E_airplane_mode_records_nothing() throws {
        signIn("john@audit.local")
        openSkidAudit()
        XCTAssertEqual(detailState("SS-113"), "Needs Verification")

        try setAirplaneMode(true)
        app.activate()
        sleep(3)
        tap(app.buttons["equipmentAudit.verify.SS-113"])
        let alert = app.alerts["Equipment Audit"]
        XCTAssertTrue(alert.waitForExistence(timeout: 30))
        let message = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        note("offline alert: \(message)")
        XCTAssertTrue(message.contains("nothing was recorded"), message)
        shoot("E1-offline-not-recorded")
        alert.buttons["OK"].tap()
        XCTAssertEqual(detailState("SS-113"), "Needs Verification", "no pretend success")
        table.swipeDown(velocity: .slow)
        sleep(3)
        XCTAssertEqual(detailState("SS-113"), "Needs Verification", "still not verified after an offline refresh")
        shoot("E2-offline-refresh")
    }

    /// After Z: a fresh launch online — the offline attempt was never queued and sent.
    func test_E3_back_online_nothing_was_queued() {
        signIn("john@audit.local")
        openSkidAudit()
        XCTAssertTrue(waitFor(timeout: 30) { self.app.staticTexts["equipmentAudit.freshness"].label.hasPrefix("Updated") })
        sleep(35)                               // one 30 s refresh cycle, in case anything was waiting to send
        XCTAssertEqual(detailState("SS-113"), "Needs Verification", "nothing was queued and sent after reconnecting")
        shoot("E3-back-online")
    }

    // MARK: - F. Server unreachable (Mac-orchestrated, opt-in)

    func test_F_server_unreachable_drill() throws {
        guard env["KABBA_SERVER_DRILL"] == "1" else { throw XCTSkip("set KABBA_SERVER_DRILL=1 with the Mac-side watcher running") }
        signIn("john@audit.local")
        openSkidAudit()
        XCTAssertEqual(detailState("SS-112"), "Needs Verification")
        ping("SERVER-DRILL-STOP")              // the Mac stops Laravel when it logs this path
        // Never tap Verify against a live server — that would really record it.
        XCTAssertTrue(waitFor(timeout: 20) { (self.apiStatus() ?? 0) >= 500 }, "Laravel did not stop for the drill")
        tap(app.buttons["equipmentAudit.verify.SS-112"])
        let alert = app.alerts["Equipment Audit"]
        XCTAssertTrue(alert.waitForExistence(timeout: 30))
        let message = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        note("server-down alert: \(message)")
        XCTAssertTrue(message.contains("nothing was recorded"), message)
        XCTAssertFalse(message.lowercased().contains("will retry"), message)
        shoot("F1-server-unreachable")
        alert.buttons["OK"].tap()
        XCTAssertTrue(waitFor(timeout: 60) { (self.apiStatus() ?? 0) == 401 }, "Laravel is back")   // restarted 20 s after the stop
        table.swipeDown(velocity: .slow)
        XCTAssertTrue(waitFor(timeout: 30) { self.app.staticTexts["equipmentAudit.freshness"].label.hasPrefix("Updated") })
        XCTAssertEqual(detailState("SS-112"), "Needs Verification", "nothing was queued and sent once the server returned")
        shoot("F2-server-back")
    }

    // MARK: - G. Off-Site form keyboard flow (opens the form, cancels — no movement)

    func test_G_off_site_form_keyboard_flow() {
        signIn("john@audit.local")
        openSkidAudit()
        search("TAK-SS-5")
        tap(app.buttons["equipmentAudit.more.TAK-SS-5"])
        choose("Move Off-Site…")
        XCTAssertTrue(app.buttons["equipmentAudit.offSite.submit"].waitForExistence(timeout: 20))
        let reason = app.textFields["equipmentAudit.offSite.reason"]
        reason.tap()
        reason.typeText("Hydraulic hose repair\n")          // Return → Notes
        let notes = app.textFields["equipmentAudit.offSite.notes"]
        XCTAssertTrue(waitFor { (notes.value(forKey: "hasKeyboardFocus") as? Bool) == true }, "Return moved to Notes")
        notes.typeText("Back by Friday\n")                  // Done → keyboard away
        XCTAssertTrue(waitFor { self.app.keyboards.count == 0 }, "Done puts the keyboard away")
        XCTAssertTrue(app.buttons["equipmentAudit.offSite.submit"].isHittable, "Move Off-Site is clear to tap")
        shoot("G1-off-site-keyboard-done")
        app.navigationBars.buttons.element(boundBy: 0).tap()   // Cancel — nothing moved
        XCTAssertTrue(app.cells["equipmentAudit.row.TAK-SS-5"].waitForExistence(timeout: 10))
        XCTAssertEqual(detailState("TAK-SS-5"), "Needs Verification")
    }

    // MARK: - P. Production smoke (Release build, the session signed in on the phone)
    //
    // Harness-free — no launch arguments, so it runs on a Release build — and
    // read-only: filters, search and the Off-Site form are opened and dismissed,
    // nothing is submitted. P2 taps Verify only after proving the phone has no
    // connection (Equipment Audit never queues), then Z restores the network —
    // run P2 and Z in ONE invocation (a reinstalled runner cannot launch offline).
    // Runner env: KABBA_BASE_URL = the production API base (an unauthenticated GET → 401).

    func test_P1_production_read_only_walkthrough() {
        attachToSignedInApp()
        let tile = app.buttons["home.equipmentAudit"]
        XCTAssertLessThan(tile.frame.maxY, app.tabBars.firstMatch.frame.minY, "tile clear of the tab bar")
        shoot("P1-home")

        openFirstAudit(listShot: "P2-list")
        note("board: \(app.staticTexts["equipmentAudit.title"].label) · \(app.staticTexts["equipmentAudit.progress"].label)")
        note("sections (default view): \(sectionHeaders())")
        let rows = table.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'equipmentAudit.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "the board shows units")
        note("first rows: \(rows.allElementsBoundByIndex.prefix(6).map { $0.label })")
        shoot("P3-board")

        // Filters: All, then back to the default.
        openFilter()
        app.buttons["equipmentAudit.filter.all"].tap()
        app.buttons["equipmentAudit.filter.apply"].tap()
        sleep(1)
        note("sections (All): \(sectionHeaders())")
        shoot("P4-filter-all")
        openFilter()
        app.buttons["equipmentAudit.filter.mine"].tap()
        if app.buttons["equipmentAudit.filter.apply"].exists { app.buttons["equipmentAudit.filter.apply"].tap() }
        sleep(1)

        // Search by Equipment ID and by name.
        let first = rows.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let id = String(first.identifier.dropFirst("equipmentAudit.row.".count))
        search(id)
        XCTAssertTrue(app.cells["equipmentAudit.row.\(id)"].waitForExistence(timeout: 5), "search by Equipment ID")
        XCTAssertEqual(app.keyboards.count, 0, "submitting the search puts the keyboard away")
        shoot("P5-search-id")
        let word = first.label.components(separatedBy: " ").first ?? ""
        if word.count >= 3 {
            search(word)
            XCTAssertTrue(app.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'equipmentAudit.row.'")).firstMatch.waitForExistence(timeout: 5), "search by name '\(word)'")
            shoot("P6-search-name")
        }
        clearSearch()

        // Off-Site form: open it from the first unit that offers it, look, Cancel.
        var opened = false
        for candidate in rows.allElementsBoundByIndex.prefix(8) where !opened {
            let unit = String(candidate.identifier.dropFirst("equipmentAudit.row.".count))
            let more = app.buttons["equipmentAudit.more.\(unit)"]
            guard more.exists, more.isHittable else { continue }
            let stateBefore = detailState(unit)
            more.tap()
            let item = app.sheets.buttons["Move Off-Site…"]
            if item.waitForExistence(timeout: 4) {
                choose("Move Off-Site…")
                XCTAssertTrue(app.buttons["equipmentAudit.offSite.submit"].waitForExistence(timeout: 20), "the Off-Site form opened")
                XCTAssertTrue(app.descendants(matching: .any)["equipmentAudit.offSite.source"].exists, "Drivable Supplier / Manual Entry")
                XCTAssertTrue(app.textFields["equipmentAudit.offSite.reason"].exists, "Reason")
                XCTAssertTrue(app.textFields["equipmentAudit.offSite.notes"].exists, "Notes")
                note("off-site form for \(unit)")
                shoot("P7-off-site-form")
                app.navigationBars.buttons.element(boundBy: 0).tap()        // Cancel — nothing moved
                XCTAssertTrue(app.cells["equipmentAudit.row.\(unit)"].waitForExistence(timeout: 10))
                XCTAssertEqual(detailState(unit), stateBefore, "cancelling changed nothing")
                opened = true
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()   // dismiss the menu
                sleep(1)
            }
        }
        if !opened { note("no unit on screen offers Move Off-Site (permission or location)") }
    }

    func test_P2_production_offline_wording() throws {
        attachToSignedInApp()
        openFirstAudit(listShot: nil)
        try setAirplaneMode(true)
        app.activate()
        sleep(3)
        // Nothing is tapped until the runner itself proves there is no connection.
        XCTAssertNil(apiStatus(), "the phone is still online — refusing to tap anything")
        // The board learns it is offline from its next refresh; one already in flight when the
        // network dropped can hang until it times out (pulls are ignored meanwhile), so keep pulling.
        let freshness = app.staticTexts["equipmentAudit.freshness"]
        let started = Date()
        let offline = waitFor(timeout: 60) {
            if freshness.label.hasPrefix("Offline") { return true }
            self.table.swipeDown(velocity: .slow)
            sleep(4)
            return freshness.label.hasPrefix("Offline")
        }
        note("offline banner after \(Int(Date().timeIntervalSince(started))) s: \(freshness.label)")
        XCTAssertTrue(offline, freshness.label)
        shoot("P8-offline-banner")

        let verify = table.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'equipmentAudit.verify.'")).firstMatch
        guard verify.waitForExistence(timeout: 5), verify.isHittable else { note("no Verify button on screen"); return }
        let unit = String(verify.identifier.dropFirst("equipmentAudit.verify.".count))
        let stateBefore = detailState(unit)
        XCTAssertNil(apiStatus(), "still offline")
        verify.tap()
        let alert = app.alerts.firstMatch
        let picker = app.tables["equipmentAudit.picker"]
        XCTAssertTrue(waitFor(timeout: 30) { alert.exists || picker.exists })
        if picker.exists {
            // "Verified By" asked first (a section with no Section Auditor): back out — choosing would store a phone setting.
            shoot("P9-verified-by-asked")
            app.navigationBars.buttons["Cancel"].tap()
            note("Verify asked Verified By first — cancelled, nothing chosen")
            XCTAssertEqual(detailState(unit), stateBefore)
            return
        }
        let message = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        note("offline verify: \(message)")
        shoot("P9-offline-verify")
        if alert.label == "Equipment Audit" {
            XCTAssertTrue(message.contains("nothing was recorded"), message)
            alert.buttons["OK"].tap()
        } else {
            // A question before sending (mismatch, Verified By): back out — offline, nothing could leave anyway.
            let cancel = alert.buttons["Cancel"]
            if cancel.exists { cancel.tap() } else { alert.buttons.element(boundBy: alert.buttons.count - 1).tap() }
        }
        XCTAssertEqual(detailState(unit), stateBefore, "no pretend success")
    }

    /// The session already on the phone: a plain launch (no harness arguments).
    private func attachToSignedInApp() {
        app = XCUIApplication()
        app.launch()
        dismissSaveSheets()
        let tile = app.buttons["home.equipmentAudit"]
        if !tile.waitForExistence(timeout: 45) {
            XCTAssertFalse(app.buttons["login.button"].exists, "sign in on the phone first — this test never types credentials")
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Equipment Audit tile on Home")
    }

    /// Opens the audit with a section assigned to me (the list calls it out), else the first one.
    private func openFirstAudit(listShot: String?) {
        tap(app.buttons["home.equipmentAudit"])
        let audits = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'equipmentAudit.audit.'"))
        XCTAssertTrue(audits.firstMatch.waitForExistence(timeout: 30), "an active audit is listed")
        note("audits: \(audits.allElementsBoundByIndex.map { $0.identifier + " — " + $0.label })")
        if let shot = listShot { shoot(shot) }
        let mine = app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS '.mine.'")).firstMatch
        var target = audits.firstMatch
        if mine.exists, let ref = mine.identifier.components(separatedBy: ".mine.").first, app.cells[ref].exists {
            target = app.cells[ref]
            note("assigned section: \(mine.identifier) — \(mine.label)")
        }
        target.tap()
        XCTAssertTrue(app.staticTexts["equipmentAudit.progress"].waitForExistence(timeout: 30), "the board loaded")
        XCTAssertTrue(waitFor(timeout: 30) { self.app.staticTexts["equipmentAudit.freshness"].label.hasPrefix("Updated") }, "the board is current")
    }

    private func sectionHeaders() -> [String] {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'equipmentAudit.section.'"))
            .allElementsBoundByIndex.map { $0.identifier + " " + $0.label }
    }

    // MARK: - Helpers

    private var table: XCUIElement { app.tables["equipmentAudit.rows"] }

    private func signIn(_ email: String) {
        app = XCUIApplication()
        app.launchArguments += ["-KabbaBaseURL", env["KABBA_BASE_URL"] ?? "", "-KabbaCompanyCode", "KABBA",
                                "-KabbaEmail", email, "-KabbaPassword", env["KABBA_PASSWORD"] ?? "audit-pass-123"]
        app.launch()
        let login = app.buttons["login.button"]
        XCTAssertTrue(login.waitForExistence(timeout: 60), "staging Login did not appear")
        login.tap()
        let deadline = Date().addingTimeInterval(90)
        var lastTap = Date()
        while Date() < deadline, login.exists {
            usleep(500_000)
            dismissSaveSheets()
            if login.exists, Date().timeIntervalSince(lastTap) > 8 { login.tap(); lastTap = Date() }
        }
        XCTAssertFalse(login.exists, "still on Login")
        dismissSaveSheets()
        XCTAssertTrue(app.buttons["home.equipmentAudit"].waitForExistence(timeout: 30))
    }

    private func openSkidAudit() {
        tap(app.buttons["home.equipmentAudit"])
        let skid = auditCell("Skid Steer Audit")
        XCTAssertTrue(skid.waitForExistence(timeout: 30))
        skid.tap()
        XCTAssertTrue(app.staticTexts["equipmentAudit.progress"].waitForExistence(timeout: 30))
    }

    private func auditCell(_ title: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func openFilter() {
        let filter = app.navigationBars.buttons["icon Filter"].exists ? app.navigationBars.buttons["icon Filter"] : app.buttons["icon Filter"]
        tap(filter)
        XCTAssertTrue(app.tables["equipmentAudit.filter"].waitForExistence(timeout: 5))
    }

    /// Every row of the visible sections, top to bottom, scrolling until nothing new appears.
    private func rowsInOrder() -> [String] {
        var seen: [String] = []
        var idle = 0
        while idle < 2 && seen.count < 60 {
            let ids = table.cells.allElementsBoundByIndex
                .filter { $0.exists && $0.identifier.hasPrefix("equipmentAudit.row.") && $0.frame.height > 0 }
                .sorted { $0.frame.minY < $1.frame.minY }
                .map { String($0.identifier.dropFirst("equipmentAudit.row.".count)) }
            let before = seen.count
            for id in ids where !seen.contains(id) { seen.append(id) }
            idle = seen.count == before ? idle + 1 : 0
            table.swipeUp(velocity: .slow)
        }
        return seen
    }

    private func firstVisibleRow() -> String {
        table.cells.allElementsBoundByIndex
            .filter { $0.identifier.hasPrefix("equipmentAudit.row.") && $0.isHittable }
            .min { $0.frame.minY < $1.frame.minY }?.identifier ?? ""
    }

    private func detail(of id: String) -> String {
        app.cells["equipmentAudit.row.\(id)"].staticTexts.allElementsBoundByIndex.map(\.label)
            .first { $0.hasPrefix("Verified") || $0.hasPrefix("Needs") || $0.hasPrefix("Unresolved") } ?? ""
    }

    private func detailState(_ id: String) -> String {
        let icon = app.images["equipmentAudit.state.\(id)"]
        if !icon.exists { _ = scrollTo(icon) }
        return icon.label
    }

    private func search(_ text: String) {
        clearSearch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text + "\n")
    }

    private func clearSearch() {
        let field = app.searchFields.firstMatch
        guard field.exists else { return }
        if field.buttons["Clear text"].exists { field.buttons["Clear text"].tap() }
        XCTAssertTrue(waitFor(timeout: 4) { self.app.keyboards.count == 0 }, "clearing puts the keyboard away")
    }

    private func choose(_ title: String) {
        let item = app.sheets.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 8), "menu item \(title)")
        let deadline = Date().addingTimeInterval(5)
        while !item.isHittable && Date() < deadline { usleep(200_000) }
        usleep(700_000)
        item.tap()
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement) -> Bool {
        for _ in 0..<10 where !(element.exists && element.isHittable) { table.swipeUp() }
        return element.exists
    }

    /// Taps once the element is on screen. Table rows off screen are not in
    /// the tree at all, so scroll the board (down the list) until it appears.
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 12 {
            if table.exists { table.swipeUp(velocity: .slow) } else { app.swipeUp() }
            tries += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) never appeared", file: file, line: line)
        element.tap()
    }

    private func waitForState(_ id: String, _ state: String, file: StaticString = #filePath, line: UInt = #line) {
        let found = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", state), object: app.images["equipmentAudit.state.\(id)"])
        if XCTWaiter().wait(for: [found], timeout: 30) != .completed {
            let alert = app.alerts.firstMatch
            XCTFail("\(id) never became \(state)\(alert.exists ? " — alert: \(alert.staticTexts.allElementsBoundByIndex.map(\.label))" : "")", file: file, line: line)
        }
    }

    private func waitFor(timeout: TimeInterval = 15, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline { if condition() { return true }; usleep(300_000) }
        return condition()
    }

    private func dismissSaveSheets() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for host in [app!, springboard] where host.buttons["Not Now"].firstMatch.exists {
            host.buttons["Not Now"].firstMatch.tap()
        }
    }

    // Control Center Airplane Mode (physical device only). iOS 26 exposes a switch
    // ("airplane-mode-button", value "0"/"1") and a module button ("On"/"Off").
    private func setAirplaneMode(_ on: Bool) throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.002))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.55)))
        sleep(2)
        let toggle = springboard.switches["airplane-mode-button"].exists
            ? springboard.switches["airplane-mode-button"]
            : springboard.descendants(matching: .any).matching(identifier: "com.apple.ControlCenter.Airplane").firstMatch
        guard toggle.waitForExistence(timeout: 5) else {
            shoot("control-center-no-toggle")
            XCUIDevice.shared.press(.home)
            throw XCTSkip("Airplane Mode toggle not found in Control Center")
        }
        note("airplane toggle before: value=\(String(describing: toggle.value))")
        for _ in 0..<2 where Self.airplaneIsOn(toggle) != on {
            toggle.tap()
            sleep(2)
        }
        note("airplane toggle after: value=\(String(describing: toggle.value))")
        shoot(on ? "control-center-airplane-on" : "control-center-airplane-off")
        XCTAssertEqual(Self.airplaneIsOn(toggle), on, "Airplane Mode did not switch")
        XCUIDevice.shared.press(.home)
        sleep(1)
    }

    /// Back online means Kabba answers (any HTTP status) — not just that the toggle moved.
    private func waitForKabba(timeout: TimeInterval = 90) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var reached = false
            let done = expectation(description: "probe")
            var request = URLRequest(url: URL(string: (env["KABBA_BASE_URL"] ?? "") + "equipment-audits")!)
            request.timeoutInterval = 8
            URLSession.shared.dataTask(with: request) { _, response, _ in
                reached = response is HTTPURLResponse
                done.fulfill()
            }.resume()
            wait(for: [done], timeout: 12)
            if reached { return true }
            sleep(3)
        }
        return false
    }

    /// iOS 26 Control Center reports the toggle's state as text ("On"/"Off"), older ones as 1/0.
    private static func airplaneIsOn(_ toggle: XCUIElement) -> Bool {
        if let n = toggle.value as? NSNumber { return n.intValue == 1 }
        let v = (toggle.value as? String ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return v == "1" || v == "on"
    }

    /// Read-only: how this iOS reports the Airplane Mode toggle (nothing is tapped).
    func test_Y_inspect_airplane_toggle() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.002))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.55)))
        sleep(2)
        let matches = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS[c] 'airplane' OR label CONTAINS[c] 'Airplane' OR label CONTAINS[c] 'Wi-Fi'"))
        var lines: [String] = []
        for i in 0..<min(matches.count, 12) {
            let e = matches.element(boundBy: i)
            lines.append("type=\(e.elementType.rawValue) id=\(e.identifier) label=\(e.label) value=\(String(describing: e.value)) selected=\(e.isSelected)")
        }
        note(lines.joined(separator: "\n"))
        shoot("Y1-control-center")
        XCUIDevice.shared.press(.home)
    }

    /// Safety valve: switch Airplane Mode OFF (and prove it) — nothing else.
    func test_Z_restore_airplane_mode_off() throws {
        app = XCUIApplication()
        try setAirplaneMode(false)
        XCTAssertTrue(waitForKabba(), "the phone is back online")
    }

    // A colleague's phone, through the same API (staging only).
    private func colleagueVerifies(_ equipmentId: String, as email: String) throws {
        let base = env["KABBA_BASE_URL"] ?? ""
        let login = try call("POST", base + "login", ["email": email, "password": env["KABBA_PASSWORD"] ?? "audit-pass-123"], token: nil)
        let token = ((login["user"] as? [String: Any])?["token"] as? String) ?? ""
        let index = try call("GET", base + "equipment-audits", nil, token: token)
        let audits = ((index["data"] as? [String: Any])?["audits"] as? [[String: Any]]) ?? []
        guard let audit = audits.first(where: { ($0["title"] as? String) == "Skid Steer Audit" })?["unique_id"] as? String else { throw XCTSkip("audit not found") }
        let board = try call("GET", base + "equipment-audits/\(audit)", nil, token: token)
        let data = board["data"] as? [String: Any] ?? [:]
        let me = (data["me"] as? [String: Any])?["id"] as? Int ?? 0
        let rows = ((data["sections"] as? [[String: Any]]) ?? []).flatMap { ($0["rows"] as? [[String: Any]]) ?? [] }
        guard let row = rows.first(where: { (($0["equipment"] as? [String: Any])?["equipment_id"] as? String) == equipmentId }) else { throw XCTSkip("unit not found") }
        let system = row["system"] as? [String: Any] ?? [:]
        _ = try call("POST", base + "equipment-audits/\(audit)/verify", [
            "equipment": (row["equipment"] as? [String: Any])?["unique_id"] as? String ?? "",
            "expected_key": row["expected_key"] as? String ?? "",
            "performed_by": me,
            "verification_type": "physical",
            "observed_store_id": system["store_id"] as? Int ?? 0,
        ], token: token, operationId: "EA-ACCEPT-" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
    }

    /// The marker rides in the PATH: the PHP dev server logs paths, not query strings.
    private func ping(_ marker: String) {
        _ = try? call("GET", (env["KABBA_BASE_URL"] ?? "") + "equipment-audits/\(marker)", nil, token: nil)
    }

    /// The audit index without a token: 401 while Laravel is up, 502 from the tunnel while it is down.
    private func apiStatus() -> Int? {
        var request = URLRequest(url: URL(string: (env["KABBA_BASE_URL"] ?? "") + "equipment-audits")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        var status: Int?
        let done = expectation(description: "status")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 15)
        return status
    }

    private func call(_ method: String, _ url: String, _ body: [String: Any]?, token: String?, operationId: String? = nil) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let op = operationId { request.setValue(op, forHTTPHeaderField: "X-Operation-Id") }
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        var result: [String: Any] = [:]
        let done = expectation(description: url)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            result = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 30)
        return result
    }

    private func note(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "note-" + String(text.prefix(while: { $0 != ":" }).replacingOccurrences(of: " ", with: "-"))
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
