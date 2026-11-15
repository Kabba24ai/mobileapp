//
//  HomeTilesUITests.swift
//  RentnKingUITests — Home's eight tiles (mobile issue #10, 2026-11-15)
//
//  Against a local Laravel with synthetic data (any signed-in account; the
//  CustomerCallPhoneStagingSeed.php driver works). Run on each supported size
//  (iPhone SE 3rd gen, 13 mini, 17, 17 Pro Max):
//
//    H1  the owner's four rows, in order, every tile on screen above the tab bar
//    H2  every tile's button opens that tile's feature, and Back returns Home
//
//  Env: KABBA_BASE_URL / KABBA_EMAIL / KABBA_PASSWORD (staging harness login).
//  Read-only: it only opens screens.
//

import XCTest

final class HomeTilesUITests: XCTestCase {

    /// Row by row: the tile's button id, its label, and the title of the screen it opens.
    private let rows: [[(id: String, title: String, screen: String)]] = [
        [("home.queueLine", "Queue Line", "Queue Line"), ("home.dispatch", "Dispatch", "Dispatch")],
        [("home.orders", "Orders", "ORDERS"), ("home.schedule", "Schedule", "Schedule")],
        [("home.equipmentAudit", "Equipment Audit", "Equipment Audit"), ("home.equipment", "Equipment", "Machine Profile")],
        [("home.crm", "CRM", "Customer"), ("home.suppliers", "Suppliers", "Suppliers")],
    ]

    private var base = "", email = "", password = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        base = env["KABBA_BASE_URL"] ?? ""
        email = env["KABBA_EMAIL"] ?? "driver@callphone.local"
        password = env["KABBA_PASSWORD"] ?? "callphone-pass-123"
    }

    func testH1_theEightTilesSitInTheOwnersFourRowsOnScreen() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        let app = signedIn()
        let first = app.buttons[rows[0][0].id]
        XCTAssertTrue(first.waitForExistence(timeout: 30), "Home did not appear")
        sleep(1)
        let screen = app.windows.firstMatch.frame
        let tabBar = app.tabBars.firstMatch
        let floor = tabBar.exists ? tabBar.frame.minY : screen.maxY
        var previousBottom = -CGFloat.infinity
        for (r, row) in rows.enumerated() {
            let left = app.buttons[row[0].id], right = app.buttons[row[1].id]
            for (tile, element) in [(row[0], left), (row[1], right)] {
                XCTAssertTrue(element.waitForExistence(timeout: 10), "\(tile.title) is on Home")
                XCTAssertTrue(element.isHittable, "\(tile.title) can be tapped")
                XCTAssertEqual(element.label, tile.title)
                XCTAssertLessThanOrEqual(element.frame.maxY, floor + 0.5, "\(tile.title) is above the tab bar")
                XCTAssertGreaterThanOrEqual(element.frame.minX, screen.minX)
                XCTAssertLessThanOrEqual(element.frame.maxX, screen.maxX)
            }
            XCTAssertEqual(left.frame.minY, right.frame.minY, accuracy: 1, "row \(r + 1) is one row")
            XCTAssertLessThan(left.frame.maxX, right.frame.minX, "row \(r + 1): \(row[0].title) | \(row[1].title)")
            XCTAssertEqual(left.frame.size.width, right.frame.size.width, accuracy: 1)
            XCTAssertGreaterThan(left.frame.minY, previousBottom, "row \(r + 1) below row \(r)")
            previousBottom = left.frame.maxY
        }
        shoot(app, "home-\(Self.deviceName)")
    }

    func testH2_everyTileOpensItsFeature() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        let app = signedIn()
        for tile in rows.joined() {
            let button = app.buttons[tile.id]
            XCTAssertTrue(button.waitForExistence(timeout: 30), "\(tile.title) on Home")
            button.tap()
            let opened = navigationBar(app, tile.screen)
            if !opened.waitForExistence(timeout: 25) { dump(app, "no-\(tile.id)") }
            XCTAssertTrue(opened.exists, "\(tile.title) opened \(tile.screen)")
            sleep(2)
            clearAlerts(app)
            shoot(app, "\(tile.id)-\(Self.deviceName)")
            back(app)
            XCTAssertTrue(app.buttons["home.queueLine"].waitForExistence(timeout: 20), "Back from \(tile.screen) returns Home")
        }
    }

    // MARK: - Helpers

    private static var deviceName: String {
        (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.name).replacingOccurrences(of: " ", with: "-")
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

    private func navigationBar(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.navigationBars.matching(NSPredicate(format: "identifier == %@ OR label == %@", title, title)).firstMatch
    }

    private func back(_ app: XCUIApplication) {
        clearAlerts(app)
        let back = app.navigationBars.buttons["icon back"].firstMatch
        if back.waitForExistence(timeout: 5) { back.tap() } else { app.navigationBars.buttons.firstMatch.tap() }
        sleep(1)
    }

    /// The app's own notices (no permission, nothing to show) and the system's (location, notifications).
    private func clearAlerts(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            var tapped = false
            for host in [springboard, app] {
                for label in ["Not Now", "Allow While Using App", "Allow", "OK", "Close"] where host.buttons[label].firstMatch.exists {
                    host.buttons[label].firstMatch.tap(); tapped = true; break
                }
            }
            if !tapped { break }
            usleep(800_000)
        }
    }

    private func dump(_ app: XCUIApplication, _ tag: String) {
        print("┏━━ DUMP[\(tag)] ━━━━━━━━━━━━━━━━━━━━━━━━")
        print(app.debugDescription)
        print("┗━━ END DUMP[\(tag)] ━━━━━━━━━━━━━━━━━━━━")
        shoot(app, tag)
    }

    private func shoot(_ app: XCUIApplication, _ tag: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = tag
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
