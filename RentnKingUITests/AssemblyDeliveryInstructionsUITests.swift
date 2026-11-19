//
//  AssemblyDeliveryInstructionsUITests.swift
//  RentnKingUITests — Order / Delivery Instructions at the top of the Assembly Review (2026-11-18)
//
//  Against a local Laravel seeded with AssemblyDeliveryInstructionsStagingSeed.php (synthetic
//  orders only). Every scenario goes Home → Dispatch → the customer's card → Start Delivery,
//  which opens the Assembly Review (driver origin).
//
//    V1  several paragraphs from the office + the customer's checkout note: the section sits
//        under the order number and above the first equipment confirmation; the office's
//        Billing note never appears.
//    V2  an order without notes: one compact "No delivery instructions" line, no box.
//    V3  an order whose line has no unit (the assembly is at STOP): the instructions are
//        still on top, Continue stays blocked.
//    V4  (needs KABBA_SIGNAL_DIR + the host watcher described below) the office edits the
//        note → reopening the order shows the new wording; then the server goes away →
//        reopening shows the saved instructions with the offline line.
//
//  Env: KABBA_BASE_URL / KABBA_EMAIL / KABBA_PASSWORD; KABBA_SHOT_DIR (optional) writes PNGs.
//  KABBA_SIGNAL_DIR (V4 only): the test creates `edit.request` / `offline.request` there and
//  waits for `edit.done` / `offline.done`, which a script on the Mac writes after it has
//  changed the note (to KABBA_EDITED_TEXT) / stopped the local server.
//

import XCTest

final class AssemblyDeliveryInstructionsUITests: XCTestCase {

    private var base = "", email = "", password = ""
    private let heading = "Order / Delivery Instructions"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        base = env["KABBA_BASE_URL"] ?? ""
        email = env["KABBA_EMAIL"] ?? "driver@instructions.local"
        password = env["KABBA_PASSWORD"] ?? "instructions-pass-123"
    }

    func testV1_instructionsAreAtTheTopOfTheAssemblyReview() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        let app = signedIn()
        openAssemblyReview(app, customer: "Ivy Instructions")

        XCTAssertEqual(element(app, "assemblyReview.instructions.heading").label, heading)
        let office = element(app, "assemblyReview.instructions.0.text")
        XCTAssertTrue(office.label.hasPrefix("Deliver to the back lot, not the front office."), office.label)
        XCTAssertTrue(office.label.contains("Gate code 4471."), "the second paragraph")
        XCTAssertTrue(office.label.contains("- Leave the keys in the lockbox (code 0912)"), "the list lines")
        XCTAssertTrue(office.label.hasSuffix("before you leave."), "the last paragraph is not cut off")
        XCTAssertTrue(element(app, "assemblyReview.instructions.0.byline").label.hasPrefix("Amber Office"))
        let customer = element(app, "assemblyReview.instructions.1.text")
        XCTAssertEqual(customer.label, "Dog in the yard. Please close the gate behind you.")
        XCTAssertTrue(element(app, "assemblyReview.instructions.1.byline").label.hasPrefix("Customer"))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'BILLING ONLY'")).firstMatch.exists,
                       "a Billing note is not a delivery instruction")

        // Under the order number, on the first screen, above equipment verification.
        let order = element(app, "assemblyReview.order"), card = element(app, "assemblyReview.instructions.heading")
        XCTAssertTrue(order.isHittable, "the review opens at its top")
        XCTAssertTrue(card.isHittable, "the instructions are visible without scrolling")
        XCTAssertGreaterThan(card.frame.minY, order.frame.maxY - 1)
        XCTAssertLessThan(card.frame.minY - order.frame.maxY, 60, "directly beneath the order number")
        let firstCheck = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.available'")).firstMatch
        XCTAssertTrue(firstCheck.exists)
        XCTAssertGreaterThan(firstCheck.frame.minY, customer.frame.maxY, "equipment verification comes after the instructions")
        shoot(app, "v1-instructions-top")

        // Long notes: the rest is reached by scrolling, never clipped.
        app.swipeUp()
        usleep(700_000)
        shoot(app, "v1-instructions-scrolled")
    }

    func testV2_anOrderWithoutInstructionsShowsOneCompactLine() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        let app = signedIn()
        openAssemblyReview(app, customer: "Nate Nonotes")

        let none = element(app, "assemblyReview.instructions.none")
        XCTAssertTrue(none.waitForExistence(timeout: 15))
        XCTAssertEqual(none.label, "No delivery instructions")
        XCTAssertLessThan(none.frame.height, 28, "one compact line")
        XCTAssertFalse(element(app, "assemblyReview.instructions.heading").exists, "no empty box")
        shoot(app, "v2-no-instructions")
    }

    func testV3_instructionsStayVisibleWhenTheAssemblyCannotProceed() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        let app = signedIn()
        openAssemblyReview(app, customer: "Wanda Wrongyard")

        XCTAssertEqual(element(app, "assemblyReview.instructions.0.text").label, "Customer will meet you at the north gate at 8:00.")
        XCTAssertTrue(element(app, "assemblyReview.instructions.heading").isHittable)
        let go = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.continue'")).firstMatch
        XCTAssertTrue(go.exists, "the forward action is on the card")
        XCTAssertEqual(go.value as? String, "blocked", "no unit: the assembly is at STOP")
        XCTAssertFalse(go.isEnabled)
        shoot(app, "v3-blocked-with-instructions")
    }

    func testV4_anEditAppearsOnReopenAndTheSavedCopyIsShownOffline() throws {
        let env = ProcessInfo.processInfo.environment
        guard let signals = env["KABBA_SIGNAL_DIR"], !signals.isEmpty, let edited = env["KABBA_EDITED_TEXT"], !edited.isEmpty else {
            throw XCTSkip("set KABBA_SIGNAL_DIR and KABBA_EDITED_TEXT (and run the host watcher)")
        }
        let app = signedIn()
        openAssemblyReview(app, customer: "Wanda Wrongyard")
        XCTAssertEqual(element(app, "assemblyReview.instructions.0.text").label, "Customer will meet you at the north gate at 8:00.")
        back(app)

        // The office edits the note on the desktop.
        signal(signals, "edit")
        openAssemblyReview(app, customer: "Wanda Wrongyard", fromHome: false)
        let text = element(app, "assemblyReview.instructions.0.text")
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, text.label != edited { usleep(400_000) }
        XCTAssertEqual(text.label, edited, "reopening the order shows the edited instruction")
        shoot(app, "v4-edited")
        back(app)

        // The server goes away: the saved copy still carries the instructions.
        signal(signals, "offline")
        openAssemblyReview(app, customer: "Wanda Wrongyard", fromHome: false)
        XCTAssertEqual(element(app, "assemblyReview.instructions.0.text").label, edited, "the saved instructions, offline")
        let freshness = element(app, "assemblyReview.freshness")
        XCTAssertTrue(freshness.waitForExistence(timeout: 30), "the review says it is showing the saved copy")
        XCTAssertTrue(freshness.label.contains("Offline"), freshness.label)
        XCTAssertFalse(element(app, "assemblyReview.instructions.notLoaded").exists)
        shoot(app, "v4-offline-saved")
    }

    // MARK: - Host signals (V4)

    private func signal(_ dir: String, _ name: String) {
        let request = URL(fileURLWithPath: dir).appendingPathComponent("\(name).request")
        let done = URL(fileURLWithPath: dir).appendingPathComponent("\(name).done")
        try? Data().write(to: request)
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, !FileManager.default.fileExists(atPath: done.path) { usleep(300_000) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: done.path), "the Mac answered '\(name)'")
        sleep(1)
    }

    // MARK: - Navigation

    private func openAssemblyReview(_ app: XCUIApplication, customer: String, fromHome: Bool = true) {
        if fromHome {
            let dispatch = app.buttons["home.dispatch"]
            XCTAssertTrue(dispatch.waitForExistence(timeout: 30), "Home")
            dispatch.tap()
            sleep(4)
            clearAlerts(app)
        }
        let card = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", customer)).firstMatch
        for _ in 0..<10 where !(card.exists && card.isHittable) { app.swipeUp(); usleep(600_000) }
        if !card.exists { dump(app, "no-card-\(customer)") }
        XCTAssertTrue(card.exists, "a Dispatch card for \(customer)")
        let start = card.staticTexts["Start Delivery"].firstMatch
        (start.exists ? start : card).tap()
        if !element(app, "assemblyReview.order").waitForExistence(timeout: 20) { dump(app, "no-review-\(customer)") }
        XCTAssertTrue(element(app, "assemblyReview.order").exists, "the Assembly Review for \(customer)")
        // The saved copy renders first; the server's answer replaces it a moment later.
        sleep(3)
    }

    private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons["icon back"].firstMatch
        if back.waitForExistence(timeout: 5) { back.tap() } else { app.navigationBars.buttons.firstMatch.tap() }
        sleep(2)
    }

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
        clearAlerts(app)
        return app
    }

    private func clearAlerts(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            var tapped = false
            for host in [springboard, app] {
                for label in ["Not Now", "Allow While Using App", "Allow", "OK"] where host.buttons[label].firstMatch.exists {
                    host.buttons[label].firstMatch.tap(); tapped = true; break
                }
            }
            if !tapped { break }
            usleep(800_000)
        }
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func dump(_ app: XCUIApplication, _ tag: String) {
        print("┏━━ DUMP[\(tag)] ━━━━━━━━━━━━━━━━━━━━━━━━")
        print(app.debugDescription)
        print("┗━━ END DUMP[\(tag)] ━━━━━━━━━━━━━━━━━━━━")
        shoot(app, tag)
    }

    private func shoot(_ app: XCUIApplication, _ tag: String) {
        let shot = app.screenshot()
        if let dir = ProcessInfo.processInfo.environment["KABBA_SHOT_DIR"], !dir.isEmpty {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(tag).png"))
        }
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = tag
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
