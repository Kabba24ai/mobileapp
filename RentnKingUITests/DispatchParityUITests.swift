//
//  DispatchParityUITests.swift
//  RentnKingUITests — Dispatch parity (Phase 6A blocker) device/simulator
//  acceptance. Signs into the staging stack through the DEBUG-only
//  StagingTestHarness, opens the Dispatch screen, and asserts the driver's
//  MIXED workload (rental legs + Manual Dispatch cards) matches what the web
//  Dispatch board says.
//
//  Parameterized so ONE test drives every reassignment scenario: the runner
//  mutates the assignment server-side between invocations (the same
//  out-of-band pattern the Phase 6A revoked-token check used) and passes the
//  expectation via env:
//    KABBA_EXPECT_PRESENT  comma-separated strings that MUST be on screen
//    KABBA_EXPECT_ABSENT   comma-separated strings that MUST NOT be on screen
//  plus the standard KABBA_BASE_URL / KABBA_EMAIL / KABBA_PASSWORD.
//

import XCTest

final class DispatchParityUITests: XCTestCase {

    private var base = ""
    private var email = ""
    private var password = ""
    private var expectPresent: [String] = []
    private var expectAbsent: [String] = []

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        base = env["KABBA_BASE_URL"] ?? ""
        email = env["KABBA_EMAIL"] ?? ""
        password = env["KABBA_PASSWORD"] ?? ""
        expectPresent = (env["KABBA_EXPECT_PRESENT"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        expectAbsent = (env["KABBA_EXPECT_ABSENT"] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

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

    /// Anywhere-on-screen text search: cards mix staticTexts and buttons.
    private func textElement(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    func test_dispatch_workload_matches_expectation() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        XCTAssertFalse(expectPresent.isEmpty || email.isEmpty, "set KABBA_EMAIL / KABBA_EXPECT_PRESENT")

        let app = makeApp()
        app.launch()

        // Sign in (harness pre-filled the credentials).
        let loginButton = app.buttons["login.button"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 40), "staging Login screen did not appear")
        loginButton.tap()

        // Signed in ⇔ the Login screen is gone (same anchor AuthFlowUITests uses).
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, loginButton.exists { usleep(400_000) }
        XCTAssertFalse(loginButton.exists, "still on the Login screen after sign-in")

        // Home → Dispatch.
        let dispatchEntry = textElement(app, "Dispatch")
        XCTAssertTrue(dispatchEntry.waitForExistence(timeout: 30), "Home screen offered no Dispatch entry")
        dispatchEntry.tap()

        // The workload must contain every expected string…
        for expected in expectPresent {
            XCTAssertTrue(textElement(app, expected).waitForExistence(timeout: 30),
                          "expected '\(expected)' on the Dispatch screen")
        }

        // …and, once the list settled, none of the forbidden ones.
        sleep(3)
        for forbidden in expectAbsent {
            XCTAssertFalse(textElement(app, forbidden).exists,
                           "'\(forbidden)' must NOT be on this driver's Dispatch screen")
        }
    }
}
