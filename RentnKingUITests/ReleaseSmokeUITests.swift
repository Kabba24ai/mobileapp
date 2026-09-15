//
//  ReleaseSmokeUITests.swift
//  RentnKingUITests
//
//  Harness-free smoke for a RELEASE-configuration build against a live backend
//  (the StagingTestHarness is compiled out of Release, so nothing here uses
//  launch arguments): sign in through the real Login screen — company code →
//  tenant lookup → login — open Queue Line, open the first Pending card's
//  Update into Assembly Review, and read Settings → About's Version.
//
//  Env (forwarded by xcodebuild as TEST_RUNNER_*):
//      KABBA_COMPANY_CODE   tenant code typed into the Login screen
//      KABBA_EMAIL / KABBA_PASSWORD
//      KABBA_EXPECT_VERSION optional, e.g. "1.0.21 (1006)" — must appear in the Version row
//
//  Run: xcodebuild test -configuration Release -scheme RentnKingUITests \
//         -destination 'id=<phone>' -only-testing:RentnKingUITests/ReleaseSmokeUITests
//

import XCTest

final class ReleaseSmokeUITests: XCTestCase {

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    func testReleaseBuildSignsInOpensAssemblyReviewAndReportsItsVersion() {
        let app = XCUIApplication()
        app.launch()
        clearSystemAlerts()

        let loginButton = app.buttons["login.button"]
        let queueLine = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Queue Line'")).firstMatch

        // Either the Login screen (fresh install / expired session) or Home (a kept session).
        var deadline = Date().addingTimeInterval(45)
        while Date() < deadline, !loginButton.exists, !queueLine.exists { usleep(500_000); clearSystemAlerts() }

        if loginButton.exists {
            typeInto(app, "login.companyCode", env["KABBA_COMPANY_CODE"] ?? "")
            typeInto(app, "login.email", env["KABBA_EMAIL"] ?? "")
            typeInto(app, "login.password", env["KABBA_PASSWORD"] ?? "")
            shoot("release-login-filled")
            loginButton.tap()
            // tenant lookup + login are two network round trips; a system alert can swallow the tap.
            deadline = Date().addingTimeInterval(90)
            var lastTap = Date()
            while Date() < deadline, loginButton.exists, !queueLine.exists {
                usleep(500_000); clearSystemAlerts()
                if loginButton.exists, Date().timeIntervalSince(lastTap) > 20 { loginButton.tap(); lastTap = Date() }
            }
        }
        XCTAssertTrue(queueLine.waitForExistence(timeout: 30), "Home did not show the Queue Line entry")
        dismissSavePasswordSheet(app)     // iOS Passwords "Save Password?" after a typed sign-in
        clearSystemAlerts()
        shoot("release-home")

        // Queue Line → first Pending card's Update → Assembly Review → back.
        queueLine.tap()
        if !app.buttons["Pending"].firstMatch.waitForExistence(timeout: 8) {
            // A late system sheet may have swallowed the tap: clear and tap once more.
            dismissSavePasswordSheet(app); clearSystemAlerts()
            if queueLine.exists { queueLine.tap() }
        }
        XCTAssertTrue(app.buttons["Pending"].firstMatch.waitForExistence(timeout: 30), "Queue Line board did not appear")
        let update = app.buttons.matching(identifier: "queueLineUpdate").firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 30), "no Update button on a Pending card")
        usleep(1_500_000)
        shoot("release-board")
        update.tap()
        let review = app.descendants(matching: .any).matching(identifier: "assemblyReview.order").firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 30), "Update did not open the Assembly Review")
        usleep(2_000_000)
        shoot("release-assembly-review")
        goBack(app)
        XCTAssertTrue(app.buttons["Pending"].firstMatch.waitForExistence(timeout: 20), "Back did not return to the board")
        goBack(app)

        // Settings → About: the installed version.
        let settingsTab = app.tabBars.buttons.element(boundBy: max(0, app.tabBars.buttons.count - 1))
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 20), "tab bar not visible")
        settingsTab.tap()
        let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Version:'")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 15), "Version row not found")
        usleep(800_000)
        shoot("release-about")
        if let expect = env["KABBA_EXPECT_VERSION"], !expect.isEmpty {
            XCTAssertTrue(version.label.contains(expect), "Version row '\(version.label)' should contain \(expect)")
        }
    }

    // MARK: helpers

    private func typeInto(_ app: XCUIApplication, _ id: String, _ text: String) {
        let field = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no field '\(id)'")
        field.tap()
        usleep(300_000)
        field.typeText(text)
        usleep(300_000)
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["icon back"].firstMatch
        if back.waitForExistence(timeout: 5) { back.tap(); usleep(1_200_000); return }
        if let btn = app.buttons.allElementsBoundByIndex.first(where: { $0.frame.minY < 110 && $0.frame.minX < 70 }) {
            btn.tap(); usleep(1_200_000)
        }
    }

    private func shoot(_ tag: String) {
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        att.name = "shot-\(tag)"
        att.lifetime = .keepAlways
        add(att)
    }

    /// The iOS Passwords sheet ("Save Password?" · Not Now / Save) that follows a typed sign-in.
    /// It is hosted inside the app's process on iOS 18+, so look in the app first, then Springboard.
    private func dismissSavePasswordSheet(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            for host in [app, springboard] {
                let notNow = host.buttons["Not Now"].firstMatch
                if notNow.exists { notNow.tap(); usleep(800_000); return }
            }
            usleep(500_000)
        }
    }

    private func clearSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            guard springboard.alerts.firstMatch.waitForExistence(timeout: 1) else { return }
            let alert = springboard.alerts.firstMatch
            var tapped = false
            for label in ["Allow", "Allow While Using App", "OK", "Don’t Allow", "Don't Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); tapped = true; break
            }
            if !tapped { alert.buttons.firstMatch.tap() }
            usleep(800_000)
        }
    }
}
