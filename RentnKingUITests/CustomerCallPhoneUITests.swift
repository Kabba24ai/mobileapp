//
//  CustomerCallPhoneUITests.swift
//  RentnKingUITests — the customer's number on Call Customer → Delivery Address (mobile issue #10)
//
//  Against a local Laravel seeded with CustomerCallPhoneStagingSeed.php (synthetic orders only):
//
//    P1  Dispatch → Start Delivery → Driver Checklist: the customer's number opens Call / Send
//        Message; Call Customer → Step 1 of 3 → Delivery Address: the same number, now a
//        button, opens the SAME sheet. Call reaches iOS's own "Call?" prompt (a physical
//        phone; the test always cancels it — nothing is dialled), Send Message opens Messages
//        addressed to the number (cancelled — nothing is sent). Neither tap verifies anything;
//        Verify Address still verifies when pressed.
//    P2  an order without a phone number: the address page says so and offers nothing to tap.
//
//  Env: KABBA_BASE_URL / KABBA_EMAIL / KABBA_PASSWORD; KABBA_CALL_CUSTOMER (default "Pat Phone"),
//  KABBA_CALL_PHONE (default "(865) 555-0142", a reserved fictional number), KABBA_NOPHONE_CUSTOMER
//  (default "Nora Nophone"). KABBA_FORCE_SIGNIN is implied: every test signs in through the harness.
//

import XCTest

final class CustomerCallPhoneUITests: XCTestCase {

    private var base = "", email = "", password = ""
    private var customer = "", phone = "", noPhoneCustomer = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        base = env["KABBA_BASE_URL"] ?? ""
        email = env["KABBA_EMAIL"] ?? "driver@callphone.local"
        password = env["KABBA_PASSWORD"] ?? "callphone-pass-123"
        customer = env["KABBA_CALL_CUSTOMER"] ?? "Pat Phone"
        phone = env["KABBA_CALL_PHONE"] ?? "(865) 555-0142"
        noPhoneCustomer = env["KABBA_NOPHONE_CUSTOMER"] ?? "Nora Nophone"
    }

    func testP1_theChecklistAndTheAddressPageOfferTheSameCallSheetAndVerifyNothing() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        let app = signedIn()
        openDriverChecklist(app, customer: customer)
        let status = element(app, "driverChecklist.call.status")
        XCTAssertTrue(reveal(app, status), "the Call Customer block")
        let statusBefore = status.label

        // 1. The Driver Checklist's number (a label under the screen's call button: tap where it is).
        let number = app.staticTexts[phone].firstMatch
        if !onScreen(app, number) { dump(app, "no-checklist-number") }
        XCTAssertTrue(onScreen(app, number), "the Driver Checklist shows \(phone)")
        number.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let checklistSheet = sheetTitles(app)
        XCTAssertEqual(checklistSheet, ["Call \(phone)", "Send Message", "Cancel"], "the Driver Checklist's sheet")
        shoot(app, "checklist-sheet")
        app.buttons["Cancel"].firstMatch.tap()
        usleep(800_000)

        // 2. Call Customer → Step 1 of 3 → Delivery Address.
        openWizard(app)
        XCTAssertTrue(app.staticTexts["Step 1 of 3"].exists)
        XCTAssertTrue(element(app, "callWizard.customer").label.contains(customer), "the name stays")
        XCTAssertFalse(element(app, "callWizard.address").label.isEmpty, "the address stays")
        let primary = app.buttons["callWizard.primary"]
        XCTAssertEqual(primary.label, "Verify Address")
        let phoneButton = app.buttons["callWizard.phone"]
        XCTAssertTrue(phoneButton.waitForExistence(timeout: 5), "the number is a button")
        XCTAssertTrue(phoneButton.isHittable)
        XCTAssertEqual(phoneButton.label, "Call or text \(phone)")
        XCTAssertGreaterThanOrEqual(phoneButton.frame.height, 44, "a full-size tap target")
        shoot(app, "address-page")

        phoneButton.tap()
        XCTAssertEqual(sheetTitles(app), checklistSheet, "the same sheet as the Driver Checklist")
        shoot(app, "address-sheet")

        // Call: iOS asks first. A physical phone shows the prompt naming the number; the test
        // cancels it. (The simulator has no Phone app: nothing happens.)
        app.buttons["Call \(phone)"].firstMatch.tap()
        cancelSystemCallPrompt(app)
        assertStillOnTheAddressPage(app, "after Call")

        // Send Message: Messages opens addressed to the number (a phone that can text); cancelled.
        phoneButton.tap()
        XCTAssertEqual(sheetTitles(app), checklistSheet)
        app.buttons["Send Message"].firstMatch.tap()
        cancelMessages(app)
        assertStillOnTheAddressPage(app, "after Send Message")

        // Back on the Driver Checklist: the numbers verified nothing.
        back(app)
        XCTAssertTrue(reveal(app, status))
        XCTAssertEqual(status.label, statusBefore, "tapping the number changes nothing on the checklist")

        // Verify Address still verifies — only when pressed.
        openWizard(app)
        app.buttons["callWizard.primary"].tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 3"].waitForExistence(timeout: 10), "Verify Address moves on to Equipment Order")
        back(app)
        XCTAssertTrue(reveal(app, status))
        XCTAssertTrue(status.label.contains("of 3 verified"), "Verify Address was recorded: \(status.label)")
        shoot(app, "checklist-after-verify")
    }

    func testP2_withoutANumberTheAddressPageSaysSoAndOffersNothingToTap() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        let app = signedIn()
        openDriverChecklist(app, customer: noPhoneCustomer)
        openWizard(app)
        XCTAssertTrue(app.staticTexts["No phone number on this order."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["callWizard.phone"].exists, "nothing to tap")
        XCTAssertEqual(app.buttons["callWizard.primary"].label, "Verify Address")
        shoot(app, "address-page-no-phone")
        back(app)
    }

    // MARK: - The system's own prompts (never tap Call, never tap Send)

    private func cancelSystemCallPrompt(_ app: XCUIApplication) {
        #if targetEnvironment(simulator)
        sleep(2)
        #else
        let hosts = [XCUIApplication(bundleIdentifier: "com.apple.springboard"), XCUIApplication(bundleIdentifier: "com.apple.InCallService")]
        let deadline = Date().addingTimeInterval(12)
        var cancelled = false
        while Date() < deadline, !cancelled {
            for host in hosts {
                let cancel = host.buttons["Cancel"].firstMatch
                if cancel.exists {
                    let digits = phone.filter(\.isNumber)
                    let prompt = host.descendants(matching: .any).allElementsBoundByIndex.map(\.label).joined(separator: " | ")
                    print("CALL PROMPT: \(prompt)")
                    XCTAssertTrue(prompt.filter(\.isNumber).contains(digits), "iOS's prompt names \(phone)")
                    shoot(app, "call-prompt", host: host)
                    cancel.tap()
                    cancelled = true
                    break
                }
            }
            if !cancelled { usleep(300_000) }
        }
        if !cancelled {
            print(XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription)
            // Belt and braces: whatever happened, end any call before failing.
            for host in hosts where host.buttons["End call"].firstMatch.exists { host.buttons["End call"].firstMatch.tap() }
        }
        XCTAssertTrue(cancelled, "iOS asked before calling and the prompt was cancelled")
        sleep(1)
        #endif
    }

    private func cancelMessages(_ app: XCUIApplication) {
        #if targetEnvironment(simulator)
        sleep(1)
        #else
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 10) {
            shoot(app, "messages")
            cancel.tap()
        } else {
            shoot(app, "messages-no-cancel")
            app.swipeDown(velocity: .fast)
        }
        sleep(2)
        #endif
    }

    private func assertStillOnTheAddressPage(_ app: XCUIApplication, _ when: String) {
        XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 10), "still on Delivery Address \(when)")
        XCTAssertEqual(app.buttons["callWizard.primary"].label, "Verify Address", when)
        XCTAssertTrue(app.buttons["callWizard.phone"].exists, when)
    }

    // MARK: - Navigation

    /// Home → Dispatch → the customer's card → Start Delivery → (the Assembly Review, driver
    /// origin: confirm the unit → Continue to Driver Checklist) → the Driver Checklist.
    private func openDriverChecklist(_ app: XCUIApplication, customer: String) {
        let dispatch = app.buttons["home.dispatch"]
        XCTAssertTrue(dispatch.waitForExistence(timeout: 30), "Home")
        dispatch.tap()
        sleep(4)
        clearAlerts(app)
        let card = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", customer)).firstMatch
        for _ in 0..<10 where !(card.exists && card.isHittable) { app.swipeUp(); usleep(600_000) }
        if !card.exists { dump(app, "no-card-\(customer)") }
        XCTAssertTrue(card.exists, "a Dispatch card for \(customer)")
        let start = card.staticTexts["Start Delivery"].firstMatch
        (start.exists ? start : card).tap()
        sleep(3)
        if element(app, "assemblyReview.order").waitForExistence(timeout: 8) {
            confirmEverything(app)
            let go = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.continue' AND enabled == true")).firstMatch
            XCTAssertTrue(reveal(app, go), "Continue to Driver Checklist")
            go.tap()
            sleep(3)
        }
        let address = element(app, "driverChecklist.call.step.address")
        if !address.waitForExistence(timeout: 30) { dump(app, "no-checklist-\(customer)") }
        XCTAssertTrue(address.exists, "the Driver Checklist for \(customer)")
        // A fresh install's first context / review fetch reloads the screen a moment after it
        // opens; a touch in flight during that reload is cancelled (seen once on the SE). No retry:
        // a tap that does nothing on a settled screen still fails.
        sleep(3)
    }

    private func openWizard(_ app: XCUIApplication) {
        let address = element(app, "driverChecklist.call.step.address")
        XCTAssertTrue(reveal(app, address), "the Delivery Address step")
        address.tap()
        XCTAssertTrue(element(app, "callWizard.step").waitForExistence(timeout: 10), "Call Customer opened")
        XCTAssertEqual(element(app, "callWizard.title").label, "Delivery Address")
        usleep(800_000)
    }

    private func sheetTitles(_ app: XCUIApplication) -> [String] {
        let call = app.buttons["Call \(phone)"].firstMatch
        if !call.waitForExistence(timeout: 8) { dump(app, "no-sheet"); return [] }
        return ["Call \(phone)", "Send Message", "Cancel"].filter { app.buttons[$0].firstMatch.exists }
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

    /// Scrolls until `el` is inside the window (for an element another view covers, so never "hittable").
    private func onScreen(_ app: XCUIApplication, _ el: XCUIElement) -> Bool {
        let window = app.windows.firstMatch.frame.insetBy(dx: 0, dy: 90)
        let visible = { el.exists && window.contains(CGPoint(x: el.frame.midX, y: el.frame.midY)) }
        for _ in 0..<8 where !visible() { app.swipeDown(); usleep(400_000) }
        for _ in 0..<8 where !visible() { app.swipeUp(); usleep(400_000) }
        return visible()
    }

    @discardableResult
    private func reveal(_ app: XCUIApplication, _ el: XCUIElement) -> Bool {
        for _ in 0..<8 where !(el.exists && el.isHittable) { app.swipeUp(); usleep(500_000) }
        for _ in 0..<8 where !(el.exists && el.isHittable) { app.swipeDown(); usleep(500_000) }
        return el.exists
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

    private func shoot(_ app: XCUIApplication, _ tag: String, host: XCUIApplication? = nil) {
        let attachment = XCTAttachment(screenshot: (host ?? app).screenshot())
        attachment.name = tag
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
