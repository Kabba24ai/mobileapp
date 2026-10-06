//
//  ChecklistBatchIsolationUITests.swift
//  RentnKingUITests — independent equipment checklists inside one order
//  (Combine ON / OFF, Delivery / Return) against a STAGING backend.
//
//  Seed: RentnKingUITests/ChecklistBatchIsolationStagingSeed.php — three-line
//  orders 9401–9405 (lines "Batch Alpha/Bravo/Charlie", units CB<order>-A/B/C;
//  9403's Charlie has no unit; 9404/9405 delivered and awaiting return). Run
//  each test once, in order, against a fresh seed: D1 → D2 → D2b share one
//  install (the draft carries over); every other test starts from a clean
//  install (`xcrun simctl uninstall <sim> com.RentnKingNew.app`). The runner
//  checks server state between steps (executions, signatures, charges and
//  mobile_operations per line) — see the seed file's footer.
//
//  Footer controls (note / employee / location) are not in the accessibility
//  tree, so they are tapped by position below the line's last question cell
//  (measured on the iPhone 17 simulator).
//
//  Env (forwarded by xcodebuild as TEST_RUNNER_*):
//    KABBA_BASE_URL / KABBA_EMAIL / KABBA_PASSWORD   staging harness login
//

import XCTest

final class ChecklistBatchIsolationUITests: XCTestCase {

    private var base = ""
    private var email = ""
    private var password = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        base = env["KABBA_BASE_URL"] ?? ""
        email = env["KABBA_EMAIL"] ?? ""
        password = env["KABBA_PASSWORD"] ?? ""
        addUIInterruptionMonitor(withDescription: "system-permission") { alert in
            for label in ["Allow", "Allow While Using App", "OK", "Don’t Allow", "Don't Allow", "Allow Full Access"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
    }

    // MARK: - D1 · Delivery, Combine ON (order 9401)

    /// Untouched rows and the shared employee alone never make a batch; only the entered
    /// line (C) is previewed and submitted; Back from Preview leaves every row as it was.
    func testD1_combinedDeliveryOnlyTheEnteredLineIsPreviewedAndSubmitted() {
        let app = signedIn()
        openChecklist(app, order: "9401", leg: "delivery")
        XCTAssertEqual(app.switches.firstMatch.value as? String, "1", "Combine starts ON with three lines")

        tapPreview(app)
        expectAlert(app, contains: "Complete at least one equipment checklist")
        shoot("D1-untouched-refused")

        // The shared employee lives under the LAST line in Combine mode.
        chooseEmployee(app, line: 2)
        tapPreview(app)
        expectAlert(app, contains: "Complete at least one equipment checklist")
        shoot("D1-shared-employee-only-refused")

        answer(app, line: 2, question: "Any body damage at delivery?", value: "No damage")
        answer(app, line: 2, question: "Keys handed over?", value: "Yes")
        shoot("D1-only-C-entered")

        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "Preview did not open")
        XCTAssertTrue(text(app, "Batch Charlie").waitForExistence(timeout: 5), "Preview shows the entered line")
        XCTAssertFalse(text(app, "Batch Alpha").exists, "untouched A is not in the batch")
        XCTAssertFalse(text(app, "Batch Bravo").exists, "untouched B is not in the batch")
        shoot("D1-preview-C-only")

        // Back: the source rows are untouched by the preview.
        goBack(app)
        XCTAssertTrue(app.staticTexts["Preview"].firstMatch.waitForExistence(timeout: 15), "Back returns to the checklist")
        XCTAssertEqual(answerShown(app, line: 0, question: "Any body damage at delivery?"), "Select")
        XCTAssertEqual(answerShown(app, line: 1, question: "Any body damage at delivery?"), "Select")
        XCTAssertEqual(answerShown(app, line: 2, question: "Any body damage at delivery?"), "No damage")
        shoot("D1-back-rows-intact")

        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20))
        sign(app)
        submit(app)
        shoot("D1-submitted")
    }

    // MARK: - D2 · Delivery, the rest of 9401 (run right after D1, same install)

    /// The draft keeps the unsubmitted siblings and the shared selection; Save sends only the
    /// entered line; a background + relaunch restores the draft; A submits alone; the LAST
    /// remaining line (Combine toggle hidden) still gets the restored shared employee.
    func testD2_restoredDraftThenTheLastRemainingLine() {
        var app = relaunchKeepingSession()
        openChecklist(app, order: "9401", leg: "delivery")
        XCTAssertFalse(text(app, "Batch Charlie").exists, "the submitted line has left the draft")
        XCTAssertEqual(app.switches.firstMatch.value as? String, "1", "Combine restored ON for the two remaining lines")
        shoot("D2-restored-two-lines")

        answer(app, line: 0, question: "Any body damage at delivery?", value: "No damage")
        answer(app, line: 0, question: "Keys handed over?", value: "Yes")
        tapSave(app)
        shoot("D2-saved-A")

        // Background, then a cold relaunch: the draft (A's answers, B untouched) survives.
        XCUIDevice.shared.press(.home)
        sleep(3)
        app = relaunchKeepingSession(app)
        openChecklist(app, order: "9401", leg: "delivery")
        XCTAssertEqual(answerShown(app, line: 0, question: "Any body damage at delivery?"), "No damage", "A's draft restored")
        XCTAssertEqual(answerShown(app, line: 1, question: "Any body damage at delivery?"), "Select", "B still untouched")
        shoot("D2-relaunched-draft")

        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "Preview did not open (shared employee must be restored)")
        XCTAssertTrue(text(app, "Batch Alpha").exists)
        XCTAssertFalse(text(app, "Batch Bravo").exists, "untouched B is not in the batch")
        sign(app)
        submit(app)

        // Last remaining line: see testD2b.
    }

    /// The LAST remaining line of 9401 (run after D2, same install): the Combine toggle is
    /// hidden, the restored shared employee still applies, and B submits on its own.
    func testD2b_theLastRemainingLineKeepsTheSharedSelection() {
        let app = relaunchKeepingSession()
        openChecklist(app, order: "9401", leg: "delivery", firstLine: "Batch Bravo")
        XCTAssertFalse(text(app, "Batch Alpha").exists, "submitted A has left the draft")
        XCTAssertFalse(app.switches.firstMatch.isHittable, "one line left: no Combine toggle")
        shoot("D2b-one-line-left")
        for (question, value) in [("Any body damage at delivery?", "No damage"), ("Keys handed over?", "Yes")]
            where answerShown(app, line: 0, question: question) == "Select" {
            answer(app, line: 0, question: question, value: value)
        }
        tapPreview(app)
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            let body = app.alerts.firstMatch.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            shoot("D2b-preview-alert")
            XCTFail("Preview refused the last line: \(body)")
            return
        }
        if !element(app, "checklist.submit").waitForExistence(timeout: 20) { dump(app, "D2b-no-preview") }
        XCTAssertTrue(element(app, "checklist.submit").exists, "the restored shared employee satisfies the last line")
        XCTAssertTrue(text(app, "Batch Bravo").exists)
        shoot("D2b-last-line-preview")
        sign(app)
        submit(app)
    }

    // MARK: - D3 · Delivery, Combine OFF (order 9402)

    /// Each line keeps its own employee and signature: a missing employee on B blocks and
    /// points at B; Submit waits until A and B are each signed; C stays out.
    func testD3_individualDeliveryPerLineEmployeeAndSignature() {
        let app = signedIn()
        openChecklist(app, order: "9402", leg: "delivery")
        app.switches.firstMatch.tap()
        usleep(800_000)
        XCTAssertEqual(app.switches.firstMatch.value as? String, "0", "Combine OFF")

        for line in [0, 1] {
            answer(app, line: line, question: "Any body damage at delivery?", value: "No damage")
            answer(app, line: line, question: "Keys handed over?", value: "Yes")
        }
        chooseEmployee(app, line: 0)
        tapPreview(app)
        expectAlert(app, contains: "Please select who delivered the equipment")
        shoot("D3-B-employee-missing-focused")

        chooseEmployee(app, line: 1)
        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "Preview did not open")
        XCTAssertTrue(text(app, "Batch Alpha").exists)
        XCTAssertTrue(text(app, "Batch Bravo").exists)
        XCTAssertFalse(text(app, "Batch Charlie").exists, "untouched C is not in the batch")

        sign(app, equipment: "CB9402-A")
        XCTAssertFalse(element(app, "checklist.submit").isEnabled, "B is not signed yet")
        shoot("D3-only-A-signed")
        sign(app, equipment: "CB9402-B")
        shoot("D3-both-signed")
        submit(app)
    }

    // MARK: - D4 · Delivery, partial lines block and are pointed at (order 9403)

    /// A partly answered B is kept and validated (its required question is pointed at);
    /// C has answers but no unit: Preview names C. Nothing is sent.
    func testD4_partialLinesBlockPreviewAndPointAtTheRightLine() {
        let app = signedIn()
        openChecklist(app, order: "9403", leg: "delivery")

        answer(app, line: 1, question: "Keys handed over?", value: "Yes")     // B: optional only
        tapPreview(app)
        XCTAssertFalse(element(app, "checklist.submit").waitForExistence(timeout: 4), "partial B must block Preview")
        shoot("D4-partial-B-required-question-flagged")

        answer(app, line: 1, question: "Any body damage at delivery?", value: "No damage")
        // C has no unit, so no questions either: its only entry point is its own Delivery Note —
        // the LAST note on the screen. A note is entered work: C must be pointed at, not dropped.
        // Footers are not accessible: at the very bottom the last footer (C's) is pinned above
        // Save, its note box ~303 pt above the Save label's centre (measured on the iPhone 17).
        for _ in 0..<8 { app.tables.firstMatch.swipeUp(); usleep(400_000) }
        let saveLabel = app.staticTexts["Save"].firstMatch
        XCTAssertTrue(saveLabel.exists)
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 200, dy: saveLabel.frame.midY - 303)).tap()
        usleep(800_000)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "C's Delivery Note did not take focus")
        app.typeText("Gate code 1234")
        if app.toolbars.buttons["Done"].firstMatch.exists { app.toolbars.buttons["Done"].firstMatch.tap() }
        else { app.staticTexts["Check List - Delivered"].firstMatch.tap() }
        usleep(800_000)
        shoot("D4-C-note-entered")
        tapPreview(app)
        expectAlert(app, contains: "Please select an equipment ID for Batch Charlie")
        shoot("D4-C-without-unit-focused")
    }

    // MARK: - R1 · Return, Combine ON (order 9404)

    /// Only B is returned (damaged): the shared employee and location are copied onto B alone,
    /// the damage charge lands on B, and A/C stay open with nothing sent for them.
    func testR1_combinedReturnOnlyTheEnteredLineCarriesTheSharedFieldsAndCharge() {
        let app = signedIn()
        openChecklist(app, order: "9404", leg: "return")
        XCTAssertEqual(app.switches.firstMatch.value as? String, "1", "Combine starts ON")
        tapPreview(app)
        expectAlert(app, contains: "Complete at least one equipment checklist")

        answer(app, line: 1, question: "Any body damage at delivery?", value: "Damaged")
        answer(app, line: 1, question: "Keys handed over?", value: "Yes")
        chooseEmployee(app, line: 2, delivery: false)     // shared fields: under the last line
        chooseStore(app, line: 2)
        shoot("R1-B-damaged-shared-fields")

        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "Preview did not open")
        XCTAssertTrue(text(app, "Batch Bravo").exists)
        XCTAssertFalse(text(app, "Batch Alpha").exists, "untouched A is not in the batch")
        XCTAssertFalse(text(app, "Batch Charlie").exists, "untouched C is not in the batch")
        shoot("R1-preview-B-only")
        sign(app)
        submit(app)
    }

    // MARK: - R2 · Return, Combine OFF (order 9405)

    /// A and C are returned with their own employee, location and signature; the damage
    /// charge is C's alone; untouched B stays open.
    func testR2_individualReturnPerLineFieldsSignaturesAndCharge() {
        let app = signedIn()
        openChecklist(app, order: "9405", leg: "return")
        app.switches.firstMatch.tap()
        usleep(800_000)
        XCTAssertEqual(app.switches.firstMatch.value as? String, "0", "Combine OFF")

        answer(app, line: 0, question: "Any body damage at delivery?", value: "No damage")
        answer(app, line: 0, question: "Keys handed over?", value: "Yes")
        answer(app, line: 2, question: "Any body damage at delivery?", value: "Damaged")
        answer(app, line: 2, question: "Keys handed over?", value: "Yes")
        for line in [0, 2] {
            chooseEmployee(app, line: line, delivery: false)
            chooseStore(app, line: line)
        }
        shoot("R2-A-and-C-entered")

        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "Preview did not open")
        XCTAssertTrue(text(app, "Batch Alpha").exists)
        XCTAssertTrue(text(app, "Batch Charlie").exists)
        XCTAssertFalse(text(app, "Batch Bravo").exists, "untouched B is not in the batch")
        sign(app, equipment: "CB9405-A")
        XCTAssertFalse(element(app, "checklist.submit").isEnabled, "C is not signed yet")
        sign(app, equipment: "CB9405-C")
        shoot("R2-both-signed")
        submit(app)
    }

    // MARK: - Checklist actions

    private func tapSave(_ app: XCUIApplication) {
        let save = app.staticTexts["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "no Save button")
        save.tap()
        sleep(4)
        if app.alerts.firstMatch.exists { shoot("save-alert"); app.alerts.buttons.firstMatch.tap(); usleep(600_000) }
        // A complete Save stages the line and may route to the delivery video upload; come back.
        if !app.staticTexts["Preview"].firstMatch.exists { goBack(app) }
        XCTAssertTrue(app.staticTexts["Preview"].firstMatch.waitForExistence(timeout: 10), "back on the checklist after Save")
        sleep(4)   // let the prepare operation reach the server
    }


    /// The question cells for `question`, one per line, in screen order (off-screen cells included).
    private func questionCells(_ app: XCUIApplication, _ question: String) -> [XCUIElement] {
        app.tables.firstMatch.cells.allElementsBoundByIndex
            .filter { $0.staticTexts[question].exists }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    /// Scrolls the checklist until `cell` sits in the band between `top` and `bottom` (points).
    private func bring(_ app: XCUIApplication, _ question: String, line: Int, top: CGFloat = 170, bottom: CGFloat = 560) -> XCUIElement {
        for _ in 0..<14 {
            let cells = questionCells(app, question)
            guard line < cells.count else { app.tables.firstMatch.swipeUp(); usleep(600_000); continue }
            let cell = cells[line]
            if cell.frame.minY < top { drag(app, by: min(300, top - cell.frame.minY + 40)) }
            else if cell.frame.minY > bottom { drag(app, by: -min(300, cell.frame.minY - bottom + 40)) }
            else { return cell }
            usleep(600_000)
        }
        let cells = questionCells(app, question)
        XCTAssertTrue(line < cells.count, "no '\(question)' cell for line \(line)")
        return cells[min(line, max(0, cells.count - 1))]
    }

    /// Drags the table content by `dy` points (positive = content moves down, revealing earlier rows).
    private func drag(_ app: XCUIApplication, by dy: CGFloat) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)), withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    private func answer(_ app: XCUIApplication, line: Int, question: String, value: String) {
        let cell = bring(app, question, line: line)
        // A return cell shows the delivery answer (left) beside the return control (right).
        let control = cell.buttons.allElementsBoundByIndex.max { $0.frame.minX < $1.frame.minX } ?? cell.buttons.firstMatch
        XCTAssertTrue(control.exists, "no answer control in line \(line)'s '\(question)'")
        control.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 8), "answer picker did not open")
        wheel.adjust(toPickerWheelValue: value)
        usleep(400_000)
        app.buttons["Select"].firstMatch.tap()
        usleep(900_000)
    }

    /// The answer shown in a line's question cell ("Select" when unanswered).
    private func answerShown(_ app: XCUIApplication, line: Int, question: String) -> String {
        let cell = bring(app, question, line: line)
        return cell.staticTexts.allElementsBoundByIndex.map(\.label).first { $0 != question && !$0.isEmpty } ?? ""
    }

    /// Footer controls are not in the accessibility tree, so they are tapped by position
    /// below the line's last question cell (delivery footer: note at +94 pt, employee at +222 pt;
    /// return footer adds the location field below the employee).
    private func tapFooter(_ app: XCUIApplication, line: Int, offset: CGFloat, lastQuestion: String) {
        let anchor = bring(app, lastQuestion, line: line, top: 150, bottom: 260)
        let y = anchor.frame.maxY + offset
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 200, dy: y)).tap()
    }

    private func chooseEmployee(_ app: XCUIApplication, line: Int, delivery: Bool = true) {
        _ = delivery   // return cells show the delivery question text too
        tapFooter(app, line: line, offset: 222, lastQuestion: "Keys handed over?")
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 8), "employee picker did not open for line \(line)")
        usleep(400_000)
        app.buttons["Select"].firstMatch.tap()
        usleep(800_000)
    }

    /// Return footer: Returned Location sits below Returned By (~318 pt under the last question cell).
    private func chooseStore(_ app: XCUIApplication, line: Int) {
        tapFooter(app, line: line, offset: 318, lastQuestion: "Keys handed over?")
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 8), "location picker did not open for line \(line)")
        usleep(400_000)
        app.buttons["Select"].firstMatch.tap()
        usleep(800_000)
    }

    private func tapPreview(_ app: XCUIApplication) {
        let preview = app.staticTexts["Preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "no Preview button")
        preview.tap()
        usleep(1_500_000)
    }

    private func expectAlert(_ app: XCUIApplication, contains message: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "expected an alert containing '\(message)'")
        let body = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(body.contains(message), "alert said: \(body)")
        alert.buttons.firstMatch.tap()
        usleep(600_000)
    }

    /// Draws a stroke on the signature pad and confirms it.
    private func sign(_ app: XCUIApplication, equipment: String? = nil) {
        let button = element(app, "checklist.customerSignature")
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no customer signature control")
        button.tap()
        if let equipment = equipment {
            let item = app.sheets.buttons.matching(NSPredicate(format: "label CONTAINS %@", equipment)).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 8), "no signature choice for \(equipment)")
            usleep(600_000)
            item.tap()
        }
        usleep(2_000_000)
        let pad = app.windows.firstMatch
        let a = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
        a.press(forDuration: 0.1, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.55)))
        usleep(500_000)
        let done = app.staticTexts["Submit"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "signature pad has no Submit")
        done.tap()
        usleep(2_500_000)
    }

    private func submit(_ app: XCUIApplication) {
        let submit = element(app, "checklist.submit")
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        XCTAssertTrue(submit.isEnabled, "Submit must be enabled once every line is signed")
        submit.tap()
        let yes = app.alerts.buttons["Yes"].firstMatch
        XCTAssertTrue(yes.waitForExistence(timeout: 10), "no 'ready to submit?' confirmation")
        yes.tap()
        // The completion is queued durably, then sent by the Sync Engine; give it time to reach the server.
        sleep(10)
        shoot("after-submit")
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["icon back"].firstMatch
        if back.waitForExistence(timeout: 5) { back.tap(); usleep(1_500_000) }
    }

    // MARK: - Navigation

    private func signedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-KabbaBaseURL", base, "-KabbaCompanyCode", "KABBA", "-KabbaEmail", email, "-KabbaPassword", password]
        app.launch()
        let login = app.buttons["login.button"]
        XCTAssertTrue(login.waitForExistence(timeout: 40), "staging Login screen did not appear")
        login.tap()
        let deadline = Date().addingTimeInterval(60)
        var lastTap = Date()
        while Date() < deadline, login.exists {
            usleep(400_000)
            if login.exists, Date().timeIntervalSince(lastTap) > 6 { login.tap(); lastTap = Date() }
        }
        XCTAssertFalse(login.exists, "still on the Login screen after sign-in")
        dismissSaveSheets(app)
        return app
    }

    /// Orders → order row → Order Details → the leg's checklist tile (→ Assembly Review → Continue for delivery).
    /// A plain launch (no harness arguments) keeps the signed-in session and every local draft.
    private func relaunchKeepingSession(_ previous: XCUIApplication? = nil) -> XCUIApplication {
        previous?.terminate()
        let app = XCUIApplication()
        app.launch()
        dismissSaveSheets(app)
        XCTAssertTrue(text(app, "Orders").waitForExistence(timeout: 40), "relaunch did not land on Home (session lost?)")
        return app
    }

    private func openChecklist(_ app: XCUIApplication, order: String, leg: String, firstLine: String = "Batch Alpha") {
        let entry = text(app, "Orders")
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "Home offered no Orders entry")
        entry.tap()
        usleep(2_500_000)
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", order)).firstMatch
        for _ in 0..<10 where !(row.exists && row.isHittable) { app.swipeUp(); usleep(600_000) }
        if !row.exists { dump(app, "no-order-\(order)") }
        XCTAssertTrue(row.exists, "no Orders row for \(order)")
        row.tap()
        let tile = element(app, "orderDetails.checklist.\(leg)")
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "Order Details for \(order) has no \(leg) checklist tile")
        tile.tap()
        usleep(2_500_000)
        if element(app, "assemblyReview.order").waitForExistence(timeout: 8) {
            confirmEverything(app)
            let go = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.continue' AND enabled == true")).firstMatch
            XCTAssertTrue(reveal(app, go), "no Continue to Checklist on the review")
            go.tap()
            usleep(2_500_000)
        }
        if !text(app, firstLine).waitForExistence(timeout: 30) { dump(app, "open-checklist-\(order)-\(leg)") }
        XCTAssertTrue(text(app, firstLine).exists, "the checklist did not show \(firstLine)")
    }

    private func confirmEverything(_ app: XCUIApplication) {
        let unconfirmed = NSPredicate(format: "identifier ENDSWITH '.available' AND value == 'not confirmed'")
        for _ in 0..<12 {
            guard let next = app.buttons.matching(unconfirmed).allElementsBoundByIndex.first(where: { $0.isEnabled }) else { break }
            if !next.isHittable { _ = reveal(app, next) }
            next.tap()
            usleep(700_000)
        }
        for _ in 0..<6 { app.swipeDown(); usleep(200_000) }
    }

    @discardableResult
    private func reveal(_ app: XCUIApplication, _ el: XCUIElement) -> Bool {
        for _ in 0..<8 where !(el.exists && el.isHittable) { app.swipeUp(); usleep(500_000) }
        for _ in 0..<8 where !(el.exists && el.isHittable) { app.swipeDown(); usleep(500_000) }
        return el.exists
    }

    private func dismissSaveSheets(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for host in [app, springboard] where host.buttons["Not Now"].firstMatch.exists {
            host.buttons["Not Now"].firstMatch.tap()
        }
    }

    // MARK: - Evidence

    private func text(_ app: XCUIApplication, _ value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", value)).firstMatch
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func dump(_ app: XCUIApplication, _ tag: String) {
        print("┏━━ DUMP[\(tag)] ━━━━━━━━━━━━━━━━━━━━━━━━")
        print(app.debugDescription)
        print("┗━━ END DUMP[\(tag)] ━━━━━━━━━━━━━━━━━━━━")
        shoot(tag)
    }

    private func shoot(_ tag: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = tag
        shot.lifetime = .keepAlways
        add(shot)
    }
}
