//
//  OrderNotificationEntryUITests.swift
//  RentnKingUITests — mobile issue #9 (2026-11-14), against a STAGING backend.
//
//  Tapping a new-order notification opens the SAME Order Details as Home → Orders → the row:
//  same heading, same buttons, same checklist return, and Back goes Order Details → Orders → Home.
//  The tap is a real notification tap (UNUserNotificationCenterDelegate.didReceive) with the data a
//  Kabba push carries, delivered as a local notification by the DEBUG harness
//  (`-KabbaTestOrderNotification`), so it runs on a simulator or an iPhone without APNs keys.
//
//  Seed: RentnKingUITests/OrderNotificationEntryStagingSeed.php (synthetic orders BASE+1…+3).
//  Env (forwarded by xcodebuild as TEST_RUNNER_*):
//    KABBA_BASE_URL / KABBA_EMAIL / KABBA_PASSWORD   staging harness login (office@notify.local)
//    KABBA_NOTIFY_NEW      push data of BASE+2 (the new order), JSON
//    KABBA_NOTIFY_HIDDEN   push data of BASE+1 (not on the Orders list's first page), JSON
//    KABBA_NOTIFY_OTHER    push data of BASE+3, JSON
//
//    N1  app open on Home: the tap opens Home → Orders → Order Details; same screen as the row
//    N2  app in the background
//    N3  app closed (terminated): a cold launch opens it
//    N4  signed out: nothing opens over Login; after sign-in it opens
//    N5  an order that is not in the loaded Orders list still opens, by its stable id
//    N6  in the middle of another workflow (Assembly Review): nothing is closed; it opens on Orders
//    N7  the same order's notification twice: one Order Details, never two
//    N8  an order Kabba doesn't have: "This order isn't available"
//

import XCTest

final class OrderNotificationEntryUITests: XCTestCase {

    private var base = ""
    private var email = ""
    private var password = ""
    private var newOrder: [String: String] = [:]
    private var hiddenOrder: [String: String] = [:]
    private var otherOrder: [String: String] = [:]
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        base = env["KABBA_BASE_URL"] ?? ""
        email = env["KABBA_EMAIL"] ?? ""
        password = env["KABBA_PASSWORD"] ?? ""
        newOrder = Self.payload(env["KABBA_NOTIFY_NEW"])
        hiddenOrder = Self.payload(env["KABBA_NOTIFY_HIDDEN"])
        otherOrder = Self.payload(env["KABBA_NOTIFY_OTHER"])
        addUIInterruptionMonitor(withDescription: "system-permission") { alert in
            for label in ["Allow", "Allow While Using App", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
    }

    private static func payload(_ json: String?) -> [String: String] {
        guard let data = json?.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return object.mapValues { "\($0)" }
    }

    private func json(_ payload: [String: String]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
    }

    private func number(_ payload: [String: String]) -> String { payload["order_number"] ?? "" }

    // MARK: - N1 app open

    func testN1_appOpenTheTapOpensTheSameOrderDetailsAsTheOrdersList() {
        XCTAssertFalse(base.isEmpty || newOrder.isEmpty, "set KABBA_BASE_URL and KABBA_NOTIFY_NEW")
        let n = number(newOrder)
        let app = launch(notifying: newOrder, delay: 8)
        XCTAssertTrue(text(app, "Dispatch").waitForExistence(timeout: 30), "Home")
        tapBanner(for: n)
        expectOrderDetails(app, n, tag: "N1-notification")
        let fromNotification = signature(app)

        // Checklist Deliv opens the review and Back returns to this order.
        expectChecklistRoundTrip(app, n, tag: "N1-notification")

        // Back: Orders (with the new order on it), then Home — the stack an employee builds by hand.
        goBack(app)
        expectOrdersList(app, tag: "N1-back-1")
        XCTAssertTrue(row(app, n).waitForExistence(timeout: 20), "the Orders list shows the new order")
        goBack(app)
        XCTAssertTrue(text(app, "Dispatch").waitForExistence(timeout: 15), "second Back lands on Home")

        // The same order the organic way.
        openFromOrders(app, n)
        expectOrderDetails(app, n, tag: "N1-orders-list")
        let fromList = signature(app)
        XCTAssertEqual(fromNotification, fromList, "same heading, details and buttons by both entries")
        expectChecklistRoundTrip(app, n, tag: "N1-orders-list")
        goBack(app)
        expectOrdersList(app, tag: "N1-organic-back")
    }

    // MARK: - N2 background

    func testN2_inTheBackgroundTheTapOpensHomeOrdersOrderDetails() {
        let n = number(newOrder)
        let app = launch(notifying: newOrder, delay: 10)
        XCTAssertTrue(text(app, "Dispatch").waitForExistence(timeout: 30), "Home")
        XCUIDevice.shared.press(.home)
        tapBanner(for: n)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        expectOrderDetails(app, n, tag: "N2")
        goBack(app)
        expectOrdersList(app, tag: "N2-back")
        goBack(app)
        XCTAssertTrue(text(app, "Dispatch").waitForExistence(timeout: 15), "Home")
    }

    // MARK: - N3 closed

    func testN3_withTheAppClosedTheTapLaunchesItIntoOrderDetails() {
        let n = number(newOrder)
        let app = launch(notifying: newOrder, delay: 15)
        XCTAssertTrue(text(app, "Dispatch").waitForExistence(timeout: 30), "Home")
        sleep(2)   // the harness schedules the notification when Home appears
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        tapBanner(for: n)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "the tap launches the app")
        dismissSaveSheets(app)
        expectOrderDetails(app, n, tag: "N3", timeout: 60)
        goBack(app)
        expectOrdersList(app, tag: "N3-back")
        goBack(app)
        XCTAssertTrue(text(app, "Dispatch").waitForExistence(timeout: 15), "Home")
    }

    // MARK: - N4 signed out

    func testN4_signedOutNothingOpensOverLoginAndItOpensAfterSignIn() {
        let n = number(newOrder)
        let app = launch(notifying: newOrder, delay: 10, at: "launch", signIn: false)
        let login = app.buttons["login.button"]
        XCTAssertTrue(login.waitForExistence(timeout: 40), "Login")
        XCUIDevice.shared.press(.home)
        tapBanner(for: n)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(login.waitForExistence(timeout: 10), "still on Login")
        XCTAssertFalse(element(app, "orderDetails.checklist.delivery").exists, "nothing opens over Login")
        shoot("N4-login-after-tap")
        signIn(app)
        expectOrderDetails(app, n, tag: "N4-after-sign-in", timeout: 40)
        goBack(app)
        expectOrdersList(app, tag: "N4-back")
    }

    // MARK: - N5 not in the loaded list

    func testN5_anOrderNotInTheLoadedOrdersListStillOpens() {
        XCTAssertFalse(hiddenOrder.isEmpty, "set KABBA_NOTIFY_HIDDEN")
        let n = number(hiddenOrder)
        let app = launch(notifying: hiddenOrder, delay: 20)
        XCTAssertTrue(text(app, "Orders").waitForExistence(timeout: 30), "Home")
        text(app, "Orders").tap()
        expectOrdersList(app, tag: "N5-list")
        XCTAssertTrue(row(app, number(newOrder)).waitForExistence(timeout: 20), "the list's first page loaded")
        XCTAssertFalse(row(app, n).exists, "precondition: \(n) is not in the loaded list")
        tapBanner(for: n)
        expectOrderDetails(app, n, tag: "N5")
        XCTAssertTrue(text(app, "Notify Excavator").waitForExistence(timeout: 20), "the order itself loaded (its product line)")
        goBack(app)
        expectOrdersList(app, tag: "N5-back")
        goBack(app)
        XCTAssertTrue(text(app, "Dispatch").waitForExistence(timeout: 15), "Home")
    }

    // MARK: - N6 busy elsewhere

    func testN6_anotherWorkflowIsNotInterruptedAndTheOrderOpensOnOrders() {
        let n = number(newOrder), other = number(otherOrder)
        let app = launch(notifying: newOrder, delay: 35)
        XCTAssertTrue(text(app, "Orders").waitForExistence(timeout: 30), "Home")
        openFromOrders(app, other)
        expectOrderDetails(app, other, tag: "N6-other")
        element(app, "orderDetails.checklist.delivery").tap()
        XCTAssertTrue(element(app, "assemblyReview.order").waitForExistence(timeout: 20), "Assembly Review (work in progress)")
        tapBanner(for: n)
        let notice = app.alerts.firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "the employee is told the order will open later")
        XCTAssertTrue(notice.label.contains(n) || notice.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", n)).count > 0)
        shoot("N6-notice")
        notice.buttons["OK"].tap()
        XCTAssertTrue(element(app, "assemblyReview.order").exists, "the review was not closed")
        goBack(app)
        expectOrderDetails(app, other, tag: "N6-back-on-other")
        goBack(app)   // back on Orders: the waiting order opens
        expectOrderDetails(app, n, tag: "N6-opened-on-orders", timeout: 20)
        goBack(app)
        expectOrdersList(app, tag: "N6-back")
    }

    // MARK: - N7 twice

    func testN7_theSameOrdersNotificationTwiceNeverStacksTwoScreens() {
        let n = number(newOrder)
        let app = launch(notifying: newOrder, delay: 8, count: 2, spacing: 20)
        XCTAssertTrue(text(app, "Dispatch").waitForExistence(timeout: 30), "Home")
        tapBanner(for: n)
        expectOrderDetails(app, n, tag: "N7-first")
        tapBanner(for: n)
        expectOrderDetails(app, n, tag: "N7-second")
        goBack(app)
        expectOrdersList(app, tag: "N7-one-back-is-orders")
    }

    // MARK: - N8 unknown order

    func testN8_anOrderKabbaDoesNotHaveSaysItIsNotAvailable() {
        let missing = ["order_unique_id": "ORD-NOTIFY-MISSING-0000", "order_number": "NOTIFY-MISSING"]
        let app = launch(notifying: missing, delay: 8)
        XCTAssertTrue(text(app, "Dispatch").waitForExistence(timeout: 30), "Home")
        tapBanner(for: "NOTIFY-MISSING")
        XCTAssertTrue(app.navigationBars["NOTIFY-MISSING"].waitForExistence(timeout: 20), "Order Details for the tapped order")
        XCTAssertTrue(text(app, "This order isn't available").waitForExistence(timeout: 30), "a clear message, not an endless skeleton")
        shoot("N8-unavailable")
        goBack(app)
        expectOrdersList(app, tag: "N8-back")
    }

    // MARK: - N9 a real remote push (simulator)

    /// A remote notification in Kabba's FCM shape (`aps` + top-level data keys), delivered by the
    /// runner with `xcrun simctl push` once this test prints its marker. Simulator only
    /// (KABBA_REMOTE_PUSH=1); a phone receives pushes only through APNs.
    func testN9_aRemotePushInKabbasShapeOpensTheOrder() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["KABBA_REMOTE_PUSH"] == "1", "set KABBA_REMOTE_PUSH=1 (simulator)")
        let n = number(newOrder)
        let app = XCUIApplication()
        app.launchArguments += ["-KabbaBaseURL", base, "-KabbaCompanyCode", "KABBA", "-KabbaEmail", email, "-KabbaPassword", password]
        app.launch()
        allowNotifications()
        signIn(app)
        XCTAssertTrue(text(app, "Dispatch").waitForExistence(timeout: 30), "Home")
        XCUIDevice.shared.press(.home)
        print("N9-READY-FOR-PUSH")
        tapBanner(for: n, timeout: 120)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        expectOrderDetails(app, n, tag: "N9-remote-push")
        goBack(app)
        expectOrdersList(app, tag: "N9-back")
    }

    // MARK: - Launch / sign-in

    private func launch(notifying payload: [String: String], delay: Int, at trigger: String = "home",
                        count: Int = 1, spacing: Int = 2, signIn: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-KabbaBaseURL", base, "-KabbaCompanyCode", "KABBA", "-KabbaEmail", email, "-KabbaPassword", password,
                                "-KabbaTestOrderNotification", json(payload), "-KabbaTestNotificationAt", trigger,
                                "-KabbaTestNotificationDelay", String(delay), "-KabbaTestNotificationCount", String(count),
                                "-KabbaTestNotificationSpacing", String(spacing)]
        app.launch()
        allowNotifications()
        if signIn { self.signIn(app) }
        return app
    }

    private func signIn(_ app: XCUIApplication) {
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
    }

    private func allowNotifications() {
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 6) { allow.tap() }
    }

    // MARK: - The notification

    private func tapBanner(for orderNumber: String, timeout: TimeInterval = 60) {
        let title = "New Order Placed \(orderNumber)"
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        if !banner.waitForExistence(timeout: timeout) { print(springboard.debugDescription); shoot("no-banner-\(orderNumber)") }
        XCTAssertTrue(banner.exists, "no notification banner for \(orderNumber)")
        banner.tap()
        sleep(2)
    }

    // MARK: - Screens

    private func expectOrderDetails(_ app: XCUIApplication, _ orderNumber: String, tag: String, timeout: TimeInterval = 30) {
        let heading = app.navigationBars[orderNumber]
        if !heading.waitForExistence(timeout: timeout) { dump(app, "\(tag)-no-heading") }
        XCTAssertTrue(heading.exists, "\(tag): Order Details heading is the order number \(orderNumber)")
        XCTAssertTrue(element(app, "orderDetails.checklist.delivery").waitForExistence(timeout: 20), "\(tag): Order Details buttons")
        XCTAssertEqual(app.navigationBars.count, 1, "\(tag): one navigation bar — not a second, presented stack")
        sleep(2)   // the live copy replaces the cached one
        shoot(tag)
    }

    private func expectOrdersList(_ app: XCUIApplication, tag: String) {
        let list = app.navigationBars["ORDERS"]
        if !list.waitForExistence(timeout: 15) { dump(app, "\(tag)-no-orders") }
        XCTAssertTrue(list.exists, "\(tag): Back lands on Orders")
        shoot(tag)
    }

    private func expectChecklistRoundTrip(_ app: XCUIApplication, _ orderNumber: String, tag: String) {
        element(app, "orderDetails.checklist.delivery").tap()
        if !element(app, "assemblyReview.order").waitForExistence(timeout: 20) { dump(app, "\(tag)-no-review") }
        XCTAssertTrue(element(app, "assemblyReview.order").exists, "\(tag): Checklist Deliv opens the Assembly Review")
        shoot("\(tag)-review")
        goBack(app)
        XCTAssertTrue(app.navigationBars[orderNumber].waitForExistence(timeout: 15), "\(tag): Back from the review returns to the order")
    }

    /// What Order Details shows: heading, labels and buttons (sorted, without volatile system text).
    private func signature(_ app: XCUIApplication) -> [String] {
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label) + app.buttons.allElementsBoundByIndex.map(\.label)
        return Array(Set(labels.filter { !$0.isEmpty })).sorted()
    }

    private func openFromOrders(_ app: XCUIApplication, _ orderNumber: String) {
        let entry = text(app, "Orders")
        if entry.waitForExistence(timeout: 10) { entry.tap() }
        let r = row(app, orderNumber)
        for _ in 0..<6 where !(r.waitForExistence(timeout: 5) && r.isHittable) { app.swipeUp() }
        XCTAssertTrue(r.exists, "no Orders row for \(orderNumber)")
        r.tap()
    }

    private func row(_ app: XCUIApplication, _ orderNumber: String) -> XCUIElement {
        app.tables.staticTexts.matching(NSPredicate(format: "label == %@", orderNumber)).firstMatch
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["icon back"].firstMatch
        if back.waitForExistence(timeout: 8) { back.tap(); usleep(1_500_000) }
    }

    private func dismissSaveSheets(_ app: XCUIApplication) {
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
