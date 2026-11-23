//
//  DeliveredByUITests.swift
//  RentnKingUITests — Delivered By on the customer checklist (Rent 'n King order #5657,
//  2026-11-23), against a STAGING backend.
//
//  Seed: RentnKingUITests/DeliveredByStagingSeed.php (DELIVERED_BY_BASE, default 9750). Every
//  order is opened the way #5657 was: Dispatch → Start Delivery → Main Order → Delivery Checklist
//  (where the picker used to do nothing). Signed in as the driver, Dana.
//
//    D1  skid steer (Dana) + grapple (no driver), Combine on: Preview opens and names Dana (it
//        was blank and Preview refused); back; pick "Olive Oldest", who is only on page 2 of
//        POST users; Preview names her; sign; Submit.
//    D2  the same two lines, Combine off: Preview names Dana for both; back; pick "Yara Yard"
//        on the skid steer, the grapple follows; Preview; sign each line; Submit.
//    D3  skid steer only (Dana): Preview names Dana; Submit.
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
        shoot("D1-delivered-by-default")

        // The default: Preview opens (it used to refuse) and names the skid steer's driver.
        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "D1: Preview refused the default Delivered By")
        XCTAssertTrue(previewNames(app, "Dana Driver"), "D1: the combined Delivered By names the skid steer's driver (it was blank)")
        goBack(app)

        // A change before submission: pick an employee who is only on page 2 of POST users.
        openDeliveredBy(app, line: .last)
        choose(app, employee: "Olive Oldest")
        shoot("D1-delivered-by-picked")
        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "D1: Preview refused the pick")
        XCTAssertTrue(previewNames(app, "Olive Oldest"), "D1: Preview names the pick")
        XCTAssertFalse(previewNames(app, "Dana Driver"), "D1: the pick replaced the default on every line")
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

        // Both lines name the skid steer's driver: the grapple has none of its own.
        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "D2: Preview refused the defaults")
        XCTAssertTrue(previewNames(app, "Dana Driver"), "D2: both lines name the skid steer's driver")
        shoot("D2-preview-defaults")
        goBack(app)

        // A pick on the skid steer's screen; the grapple's screen follows it.
        openDeliveredBy(app, line: .first)
        choose(app, employee: "Yara Yard")
        shoot("D2-skid-steer-yara")
        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "D2: Preview refused")
        XCTAssertTrue(previewNames(app, "Yara Yard"), "D2: Preview names Yara Yard")
        XCTAssertFalse(previewNames(app, "Dana Driver"), "D2: the grapple followed the pick on the line before")
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
        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "D3: Preview refused")
        XCTAssertTrue(previewNames(app, "Dana Driver"), "D3: the line's driver")
        sign(app, line: nil)
        submit(app)
    }

    // MARK: - Delivered By

    private enum Line { case first, last }

    /// Taps a line's Delivered By field. Checklist footers are cells used as section footers and
    /// expose nothing to XCUITest on a phone, so the tap is anchored to what is exposed: the line's
    /// last question cell ("Keys handed over?"), which the footer sits right under — Delivery Note,
    /// then Delivered By ~222 pt (iPhone 17 width; the layout scales with the screen width) below it.
    private func openDeliveredBy(_ app: XCUIApplication, line: Line) {
        let table = app.tables.firstMatch
        for _ in 0..<8 { line == .first ? table.swipeDown() : table.swipeUp(); usleep(200_000) }
        let width = app.windows.firstMatch.frame.width
        let offset = 222 * width / 402
        let limit = app.windows.firstMatch.frame.height - 150
        var cell = line == .first ? bring(app, "Keys handed over?", line: 0, top: 120, bottom: 280)
                                  : (questionCells(app, "Keys handed over?").last ?? table)
        if line == .last {
            for _ in 0..<4 where cell.frame.maxY + offset > limit {
                drag(app, by: -min(220, cell.frame.maxY + offset - limit + 30)); usleep(500_000)
                cell = questionCells(app, "Keys handed over?").last ?? cell
            }
        }
        let y = cell.frame.maxY + offset
        XCTAssertLessThan(y, limit, "the \(line) line's Delivered By is not on screen")
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: width / 2, dy: y)).tap()
    }

    /// Preview (one equipment per screen) names `employee` somewhere, top or bottom.
    private func previewNames(_ app: XCUIApplication, _ employee: String) -> Bool {
        let named = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", employee, employee)).firstMatch
        if named.exists { return true }
        for _ in 0..<5 { app.swipeDown(); usleep(250_000) }
        if named.exists { return true }
        for _ in 0..<8 { app.swipeUp(); usleep(250_000) }
        return named.exists
    }

    /// Preview → back to the checklist. The tap is retried on the visible back button: right after
    /// Preview scrolls, a first tap can land on nothing (seen on a phone).
    private func goBack(_ app: XCUIApplication) {
        usleep(800_000)
        for _ in 0..<3 {
            let back = app.buttons.matching(identifier: "icon back").allElementsBoundByIndex.first { $0.isHittable }
                ?? app.buttons["icon back"].firstMatch
            back.tap()
            if app.staticTexts["Preview"].firstMatch.waitForExistence(timeout: 8) { usleep(1_500_000); return }
        }
        dump(app, "back-from-preview")
        XCTFail("did not return to the checklist")
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
