//
//  DeliveredByUITests.swift
//  RentnKingUITests — Delivered By on the customer checklist (Rent 'n King order #5657,
//  2026-11-23), against a STAGING backend.
//
//  Seed: RentnKingUITests/DeliveredByStagingSeed.php (DELIVERED_BY_BASE, default 9750). Every
//  order is opened the way #5657 was: Dispatch → Start Delivery → Main Order → Delivery Checklist
//  (where the picker used to do nothing). Signed in as the driver, Dana.
//
//    D1  skid steer (Dana) + grapple (no driver), Combine on: Delivered By names Dana (it was
//        blank); pick "Olive Oldest", who is only on page 2 of POST users; Preview; Submit.
//    D2  the same two lines, Combine off: both lines name Dana; pick "Yara Yard" on the skid
//        steer and the grapple follows; Preview; sign each line; Submit.
//    D3  skid steer only (Dana): Delivered By names Dana; Preview; Submit.
//
//  The runner then checks Kabba (delivery_by per line = the employee picked, one completed
//  cycle per line, each line's own answers, one completion operation per cycle).
//
//  Env (forwarded by xcodebuild as TEST_RUNNER_*):
//    KABBA_BASE_URL / KABBA_EMAIL / KABBA_PASSWORD   staging harness login (driver@deliveredby.local)
//    KABBA_DB_BASE                                   the seed's base (default 9750)
//    KABBA_DB_CARDS                                  the orders' Dispatch card numbers (cards show "#<order id>")
//

import XCTest

final class DeliveredByUITests: XCTestCase {

    private var base = ""
    private var email = ""
    private var password = ""
    private var seedBase = 9750
    private var cards: [String] = []

    private func order(_ n: Int) -> String { String(seedBase + n) }
    private func card(_ n: Int) -> String { n <= cards.count ? "#" + cards[n - 1] : order(n) }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        base = env["KABBA_BASE_URL"] ?? ""
        email = env["KABBA_EMAIL"] ?? ""
        password = env["KABBA_PASSWORD"] ?? ""
        seedBase = Int(env["KABBA_DB_BASE"] ?? "") ?? 9750
        cards = (env["KABBA_DB_CARDS"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        addUIInterruptionMonitor(withDescription: "system-permission") { alert in
            for label in ["Allow", "Allow While Using App", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
    }

    // MARK: - Scenarios

    func testD1_order5657CombinedNamesTheDriverAndAnyActiveEmployeeCanBePicked() throws {
        try XCTSkipIf(base.isEmpty, "staging harness not configured")
        let app = signedIn()
        openMainOrderFromDispatch(app, card: card(1))
        openChecklistFromMainOrder(app, order: order(1))
        let combine = app.switches.firstMatch
        XCTAssertTrue(combine.waitForExistence(timeout: 10), "D1: no Combine Delivery Checklists switch for two lines")
        XCTAssertEqual(combine.value as? String, "1", "D1: two lines open combined")
        answerEveryLine(app, lines: 2)

        let field = deliveredBy(app, line: .last)
        shoot("D1-delivered-by-default")
        XCTAssertEqual(value(of: field), "Dana Driver", "D1: the combined Delivered By names the skid steer's driver (it was blank)")
        pick(app, field: field, employee: "Olive Oldest")
        XCTAssertEqual(value(of: deliveredBy(app, line: .last)), "Olive Oldest", "D1: any active employee can be picked, from page 2 too")
        shoot("D1-delivered-by-picked")

        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "D1: Preview refused")
        let named = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Olive Oldest' OR value CONTAINS 'Olive Oldest'")).firstMatch
        for _ in 0..<6 where !named.exists { app.swipeUp(); usleep(400_000) }
        if !named.exists { dump(app, "D1-preview-no-name") }
        XCTAssertTrue(named.exists, "D1: Preview names the pick")
        shoot("D1-preview")
        sign(app, line: nil)
        submit(app)
    }

    func testD2_separateChecklistsFollowAPickOnTheLineBefore() throws {
        try XCTSkipIf(base.isEmpty, "staging harness not configured")
        let app = signedIn()
        openMainOrderFromDispatch(app, card: card(2))
        openChecklistFromMainOrder(app, order: order(2))
        let combine = app.switches.firstMatch
        XCTAssertTrue(combine.waitForExistence(timeout: 10), "D2: no Combine switch")
        if combine.value as? String == "1" { combine.tap(); usleep(800_000) }
        XCTAssertEqual(combine.value as? String, "0", "D2: Combine is off")
        answerEveryLine(app, lines: 2)

        // Separate footers do not expose their controls to XCUITest (the combined one does): the
        // grapple's field is checked on screen (screenshot) and through Preview and Kabba.
        bringFooter(app, line: .last)
        shoot("D2-grapple-names-the-skid-steer-driver")
        openFirstLineDeliveredBy(app)                                      // the skid steer's screen
        choose(app, employee: "Yara Yard")
        bringFooter(app, line: .last)
        shoot("D2-grapple-follows-yara")

        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "D2: Preview refused")
        // Preview shows one equipment at a time (skid steer at the top, grapple at the bottom) and
        // exposes only some of its labels to XCUITest: both are photographed, Yara must be named,
        // and the runner checks each line's delivery_by in Kabba.
        for _ in 0..<6 { app.swipeDown(); usleep(300_000) }
        shoot("D2-preview-skid-steer")
        for _ in 0..<6 { app.swipeUp(); usleep(300_000) }
        shoot("D2-preview-grapple")
        let yara = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Yara Yard' OR value == 'Yara Yard'")).firstMatch
        XCTAssertTrue(yara.exists, "D2: Preview names Yara Yard")
        sign(app, line: "Skid Steer w/Cab")
        sign(app, line: "Skid Steer - Grapple")
        submit(app)
    }

    func testD3_aSingleLineKeepsItsDriver() throws {
        try XCTSkipIf(base.isEmpty, "staging harness not configured")
        let app = signedIn()
        openMainOrderFromDispatch(app, card: card(3))
        openChecklistFromMainOrder(app, order: order(3))
        XCTAssertFalse(app.switches.firstMatch.exists && app.switches.firstMatch.isHittable, "D3: one line, no Combine switch")
        answerEveryLine(app, lines: 1)
        XCTAssertEqual(value(of: deliveredBy(app, line: .last)), "Dana Driver", "D3: the line's driver")
        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "D3: Preview refused")
        sign(app, line: nil)
        submit(app)
    }

    // MARK: - Delivered By

    private enum Line { case first, last }

    /// The Delivered By control of the first or the last line (the combined one sits under the last).
    private func deliveredBy(_ app: XCUIApplication, line: Line) -> XCUIElement {
        let controls = app.buttons.matching(identifier: "checklist.deliveredBy")
        let table = app.tables.firstMatch
        // Scroll the other way first: a footer laid out again comes back with its controls exposed
        // (after Combine reloads the table in place, the visible footer's element tree goes stale).
        for _ in 0..<6 { line == .first ? table.swipeUp() : table.swipeDown(); usleep(200_000) }
        for _ in 0..<8 { line == .first ? table.swipeDown() : table.swipeUp(); usleep(250_000) }
        for _ in 0..<16 {
            let onScreen = controls.allElementsBoundByIndex.filter { $0.isHittable }
            let found = line == .first ? onScreen.min { $0.frame.minY < $1.frame.minY } : onScreen.max { $0.frame.minY < $1.frame.minY }
            if let found = found { return found }
            if line == .last { break }
            drag(app, by: -220); usleep(500_000)
        }
        dump(app, "no-delivered-by-\(line)")
        XCTFail("no Delivered By control for the \(line) line")
        return controls.firstMatch
    }

    private func value(of control: XCUIElement) -> String {
        let text = (control.value as? String ?? "").trimmingCharacters(in: .whitespaces)
        return text == "Select Employee" ? "" : text
    }

    /// A line's checklist footer ("Delivery Note" … "Delivered By"), scrolled fully on screen.
    @discardableResult
    private func bringFooter(_ app: XCUIApplication, line: Line) -> XCUIElement {
        let table = app.tables.firstMatch
        for _ in 0..<8 { line == .first ? table.swipeDown() : table.swipeUp(); usleep(250_000) }
        let footers = app.otherElements.matching(identifier: "Delivery Note")
        for _ in 0..<16 {
            let all = footers.allElementsBoundByIndex.filter { $0.frame.height > 200 }
            guard let footer = line == .first ? all.min(by: { $0.frame.minY < $1.frame.minY }) : all.max(by: { $0.frame.minY < $1.frame.minY }) else {
                drag(app, by: line == .first ? -220 : 220); usleep(500_000); continue
            }
            if footer.frame.maxY > 760 { drag(app, by: -min(260, footer.frame.maxY - 740)) }
            else if footer.frame.minY < 120 { drag(app, by: min(260, 140 - footer.frame.minY)) }
            else { return footer }
            usleep(500_000)
        }
        dump(app, "no-footer-\(line)")
        XCTFail("no checklist footer for the \(line) line")
        return footers.firstMatch
    }

    /// Taps line 0's Delivered By field. Separate footers expose nothing to XCUITest, so the tap is
    /// anchored to what is exposed: the line's last question cell, which the footer sits right
    /// under (Delivery Note, then Delivered By ~222 pt below the cell's bottom).
    private func openFirstLineDeliveredBy(_ app: XCUIApplication) {
        for _ in 0..<8 { app.tables.firstMatch.swipeDown(); usleep(200_000) }
        let cell = bring(app, "Keys handed over?", line: 0, top: 120, bottom: 300)
        let y = cell.frame.maxY + 222
        XCTAssertLessThan(y, 760, "line 0's Delivered By is not on screen")
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 201, dy: y)).tap()
    }

    private func choose(_ app: XCUIApplication, employee: String) {
        let wheel = app.pickerWheels.firstMatch
        if !wheel.waitForExistence(timeout: 10) { dump(app, "employee-picker-\(employee)") }
        XCTAssertTrue(wheel.exists, "the Delivered By picker did not open")
        wheel.adjust(toPickerWheelValue: employee)
        usleep(500_000)
        XCTAssertEqual(wheel.value as? String, employee, "\(employee) is not offered")
        app.buttons["Select"].firstMatch.tap()
        usleep(900_000)
    }

    private func pick(_ app: XCUIApplication, field: XCUIElement, employee: String) {
        field.tap()
        choose(app, employee: employee)
    }

    private func answerEveryLine(_ app: XCUIApplication, lines: Int) {
        for line in 0..<lines {
            answer(app, line: line, question: "Any body damage at delivery?", value: "No damage")
            answer(app, line: line, question: "Keys handed over?", value: "Yes")
        }
    }

    private func questionCells(_ app: XCUIApplication, _ question: String) -> [XCUIElement] {
        app.tables.firstMatch.cells.allElementsBoundByIndex
            .filter { $0.staticTexts[question].exists }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

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

    private func answer(_ app: XCUIApplication, line: Int, question: String, value: String) {
        let cell = bring(app, question, line: line)
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

    // MARK: - Shared helpers (CustomerSiteVideoSyncUITests' proven gestures)

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

    /// Home → Dispatch → the stop's card → Start Delivery: at Arrived it opens Main Order.
    private func openMainOrderFromDispatch(_ app: XCUIApplication, card order: String) {
        let entry = text(app, "Dispatch")
        if !element(app, "orderDetails.checklist.delivery").exists, entry.waitForExistence(timeout: 15) { entry.tap(); sleep(4) }
        let card = app.cells.containing(NSPredicate(format: "label == %@", order)).firstMatch
        for _ in 0..<10 where !(card.exists && card.isHittable) { app.swipeUp(); usleep(600_000) }
        if !card.exists { dump(app, "no-dispatch-card-\(order)") }
        XCTAssertTrue(card.exists, "no Dispatch card for \(order)")
        let start = card.staticTexts["Start Delivery"].firstMatch
        (start.exists ? start : card).tap()
        if !element(app, "orderDetails.checklist.delivery").waitForExistence(timeout: 20) { dump(app, "start-delivery-\(order)") }
        XCTAssertTrue(element(app, "orderDetails.checklist.delivery").exists, "Start Delivery for \(order) did not open Main Order")
        usleep(1_500_000)
    }

    private func openChecklistFromMainOrder(_ app: XCUIApplication, order: String) {
        element(app, "orderDetails.checklist.delivery").tap()
        usleep(2_500_000)
        if element(app, "assemblyReview.order").waitForExistence(timeout: 6) {
            confirmEverything(app)
            let go = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.continue' AND enabled == true")).firstMatch
            XCTAssertTrue(reveal(app, go), "no Continue to Checklist on the review")
            go.tap()
            usleep(2_500_000)
        }
        if !app.staticTexts["Preview"].firstMatch.waitForExistence(timeout: 30) { dump(app, "open-checklist-\(order)") }
        XCTAssertTrue(app.staticTexts["Preview"].firstMatch.exists, "the checklist for \(order) did not open")
        usleep(1_500_000)
    }

    private func drag(_ app: XCUIApplication, by dy: CGFloat) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)), withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    private func tapPreview(_ app: XCUIApplication) {
        let preview = app.staticTexts["Preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "no Preview button")
        preview.tap()
        usleep(1_500_000)
    }

    /// The customer signs (the one combined signature, or one line's from the equipment sheet).
    private func sign(_ app: XCUIApplication, line: String?) {
        let button = element(app, "checklist.customerSignature")
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no customer signature control")
        button.tap()
        usleep(1_200_000)
        if let line = line {
            let choice = app.sheets.buttons.matching(NSPredicate(format: "label CONTAINS %@", line)).firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 6), "no '\(line)' on the equipment sheet")
            choice.tap()
        }
        usleep(1_500_000)
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
        XCTAssertTrue(submit.isEnabled, "Submit must be enabled once signed")
        submit.tap()
        let yes = app.alerts.buttons["Yes"].firstMatch
        XCTAssertTrue(yes.waitForExistence(timeout: 10), "no 'ready to submit?' confirmation")
        yes.tap()
        sleep(12)
        shoot("after-submit")
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
