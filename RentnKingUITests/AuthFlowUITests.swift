//
//  AuthFlowUITests.swift
//  RentnKingUITests — on-device UI automation for the Phase 6A authentication
//  device checks. Runs the SIGNED app on a real iPhone against a controlled
//  STAGING backend (a Cloudflare tunnel to a local Laravel), driven by the
//  DEBUG-only StagingTestHarness (launch arguments below). Nothing here runs in
//  Release; nothing weakens auth.
//
//  Launch arguments (consumed by StagingTestHarness, DEBUG only):
//    -KabbaBaseURL <https://…/api/admin/v1/>   point the app at staging, skip the prod clients lookup
//    -KabbaCompanyCode KABBA  -KabbaEmail <e>  -KabbaPassword <p>   pre-fill + clean-start the login
//
//  Env passed by the runner:
//    KABBA_BASE_URL, KABBA_EMAIL, KABBA_PASSWORD  (Scripts/run-device-uitests.sh)
//

import XCTest

final class AuthFlowUITests: XCTestCase {

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

        // System permission dialogs (notifications) must not block the flow.
        addUIInterruptionMonitor(withDescription: "system-permission") { alert in
            for label in ["Allow", "Allow While Using App", "OK", "Don’t Allow", "Don't Allow"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-KabbaBaseURL", base,
            "-KabbaCompanyCode", "KABBA",
            "-KabbaEmail", email,
            "-KabbaPassword", password,
        ]
        return app
    }

    private func signIn(_ app: XCUIApplication, timeout: TimeInterval = 40) {
        let loginButton = app.buttons["login.button"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: timeout), "staging Login screen did not appear")
        // The harness pre-filled the fields; a single tap authenticates.
        loginButton.tap()
    }

    /// Signed in ⇔ the Login screen is gone. That is the reliable, localization-independent
    /// signal (the server confirms the sign-in by serving the Home screen's queue-line load);
    /// the tab bar's title and the Home root view are not dependable XCUITest anchors here.
    @discardableResult
    private func waitUntilSignedIn(_ app: XCUIApplication, timeout: TimeInterval = 45) -> Bool {
        let login = app.buttons["login.button"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !login.exists { return true }
            usleep(400_000)
        }
        return !login.exists
    }

    private func assertSignedIn(_ app: XCUIApplication, timeout: TimeInterval = 45) {
        XCTAssertTrue(waitUntilSignedIn(app, timeout: timeout), "still on the Login screen after sign-in")
    }

    private func assertSignedOut(_ app: XCUIApplication, timeout: TimeInterval = 40) {
        XCTAssertTrue(app.buttons["login.button"].waitForExistence(timeout: timeout),
                      "did not return to the Login screen")
    }

    // MARK: - Check 2 — explicit logout, then login again

    func test_login_then_explicit_logout_then_login_again() {
        XCTAssertFalse(base.isEmpty, "KABBA_BASE_URL not provided")
        let app = makeApp()
        app.launch()

        app.tap()   // let the interruption monitor dismiss any system permission dialog
        signIn(app)
        assertSignedIn(app)

        // Settings tab → Log Out → confirm.
        let settingsTab = app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()

        let logout = app.buttons["settings.logout"]
        XCTAssertTrue(logout.waitForExistence(timeout: 10), "Log Out button not found")
        logout.tap()
        // Confirm alert ("Logout" destructive action).
        let confirm = app.alerts.buttons["Logout"]
        if confirm.waitForExistence(timeout: 5) { confirm.tap() }

        assertSignedOut(app)

        // Sign back in — the harness re-fills the fields when Login re-appears.
        signIn(app)
        assertSignedIn(app)
    }

    // MARK: - Check 3 — a genuinely revoked token → 401 → back to Login

    /// The app signs in and idles on Home. The test harness (external orchestrator,
    /// Scripts/run-device-uitests.sh) deletes the token row on the server once the login
    /// lands, then this test repeatedly foregrounds the app (each activation triggers an
    /// authenticated request) until the app discovers the 401 and returns to Login.
    func test_revoked_token_returns_to_login_on_next_request() {
        XCTAssertFalse(base.isEmpty, "KABBA_BASE_URL not provided")
        let app = makeApp()
        app.launch()

        app.tap()   // dismiss any system permission dialog via the interruption monitor
        signIn(app)
        assertSignedIn(app)

        let login = app.buttons["login.button"]
        let deadline = Date().addingTimeInterval(150)
        var recovered = false
        while Date() < deadline {
            XCUIDevice.shared.press(.home)
            usleep(2_500_000)
            app.activate()                       // foreground → KabbaSync.kick + Home reloads → authed request
            if login.waitForExistence(timeout: 6) { recovered = true; break }
        }
        XCTAssertTrue(recovered, "app never returned to Login after the token was revoked server-side")
    }
}
