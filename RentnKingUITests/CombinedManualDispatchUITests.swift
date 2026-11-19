//
//  CombinedManualDispatchUITests.swift
//  RentnKingUITests — a combined manual dispatch reads as ONE trip; items are confirmed one at a time (2026-11-18)
//
//  Against a local Laravel seeded with CombinedManualDispatchStagingSeed.php (synthetic tasks
//  only): two tasks the office combined (one pickup, one destination) and one separate task
//  to a different address, all on one driver today.
//
//    C1  Dispatch: the first combined card states the one pickup and the one destination and
//        is marked COMBINED 1/2; the second says it shares that stop (COMBINED 2/2); the
//        separate task is its own card with no COMBINED mark. Each card lists its items.
//    C2  Task detail: the Combined Dispatch section, the Items card, and one item taken
//        through Mark Picked Up → Mark Delivered without touching the other item.
//
//  Env: KABBA_BASE_URL / KABBA_EMAIL / KABBA_PASSWORD; KABBA_SHOT_DIR (optional) writes PNGs.
//

import XCTest

final class CombinedManualDispatchUITests: XCTestCase {

    private var base = "", email = "", password = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        base = env["KABBA_BASE_URL"] ?? ""
        email = env["KABBA_EMAIL"] ?? "driver@combined.local"
        password = env["KABBA_PASSWORD"] ?? "combined-pass-123"
    }

    private func text(_ app: XCUIApplication, containing fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func openDispatch(_ app: XCUIApplication) {
        let dispatch = app.buttons["home.dispatch"]
        XCTAssertTrue(dispatch.waitForExistence(timeout: 30), "Home")
        dispatch.tap()
        sleep(4)
        clearAlerts(app)
    }

    func testC1_theCombinedTasksReadAsOneTripAndTheSeparateTaskStaysSeparate() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        let app = signedIn()
        openDispatch(app)

        let first = text(app, containing: "One trip · 2 tasks")
        if !first.waitForExistence(timeout: 20) { dump(app, "c1-no-combined") }
        XCTAssertTrue(first.exists, "the first combined card states the trip")
        XCTAssertTrue(first.label.contains("Pickup: "), first.label)
        XCTAssertTrue(first.label.contains("Combined North Yard") || first.label.contains("10550 Highway 46"), "the one pickup: \(first.label)")
        XCTAssertTrue(first.label.contains("Destination: "), first.label)
        XCTAssertTrue(first.label.contains("200 Transfer Road") || first.label.contains("Combined South Yard"), "the one destination: \(first.label)")
        XCTAssertTrue(app.staticTexts["COMBINED 1/2"].exists)
        XCTAssertTrue(app.staticTexts["COMBINED 2/2"].exists)
        XCTAssertTrue(app.staticTexts["Same pickup and destination as the task above"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'COMBINED '")).count, 2, "only the two combined tasks carry the mark")
        XCTAssertTrue(text(app, containing: "Trench Roller, Plate Compactor").exists, "task 1's items")
        XCTAssertTrue(text(app, containing: "Light Tower").exists, "task 2's item")
        shoot(app, "c1-dispatch-combined")

        let solo = text(app, containing: "Trash Pump")
        for _ in 0..<6 where !(solo.exists && solo.isHittable) { app.swipeUp(); usleep(500_000) }
        XCTAssertTrue(solo.exists, "the separate task to Mill Rd is its own card")
        shoot(app, "c1-dispatch-separate")
    }

    func testC2_anItemIsPickedUpAndDeliveredOnItsOwn() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        let app = signedIn()
        openDispatch(app)
        let card = app.cells.containing(NSPredicate(format: "label CONTAINS 'Trench Roller'")).firstMatch
        if !card.waitForExistence(timeout: 20) { dump(app, "c2-no-card") }
        XCTAssertTrue(card.exists)
        card.tap()
        sleep(3)

        if !app.staticTexts["Combined Dispatch"].waitForExistence(timeout: 15) && !text(app, containing: "COMBINED DISPATCH").exists { dump(app, "c2-no-detail") }
        XCTAssertTrue(text(app, containing: "2 tasks on one trip").exists, "Travels With")
        let steps = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'manual-item-step-'"))
        for _ in 0..<6 where steps.count == 0 || !steps.firstMatch.isHittable { app.swipeUp(); usleep(500_000) }
        XCTAssertEqual(steps.count, 2, "one action per item")
        XCTAssertEqual(steps.allElementsBoundByIndex.map(\.label), ["Mark Picked Up", "Mark Picked Up"])
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'NOT PICKED UP YET'")).count, 2)
        shoot(app, "c2-detail-before")

        let firstId = steps.firstMatch.identifier
        app.buttons[firstId].tap()
        sleep(2)
        clearAlerts(app)
        XCTAssertTrue(app.staticTexts["PICKED UP — NOT DELIVERED YET"].waitForExistence(timeout: 10), "the item is picked up")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'NOT PICKED UP YET'")).count, 1, "the other item is untouched")
        XCTAssertEqual(app.buttons[firstId].label, "Mark Delivered")
        shoot(app, "c2-detail-picked-up")

        app.buttons[firstId].tap()
        sleep(2)
        clearAlerts(app)
        XCTAssertTrue(app.staticTexts["DELIVERED"].waitForExistence(timeout: 10), "the item is delivered")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'NOT PICKED UP YET'")).count, 1, "the other item is still untouched")
        shoot(app, "c2-detail-delivered")
    }

    // MARK: - Harness

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
