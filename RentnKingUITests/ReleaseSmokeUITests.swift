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
        // 1.0.21 (1007): exactly one hash whatever the stored order number carries.
        XCTAssertTrue(review.label.hasPrefix("Order #"), "heading '\(review.label)' should read 'Order #<number>'")
        XCTAssertFalse(review.label.contains("##"), "heading '\(review.label)' doubles the hash")
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

    /// Read-only production verification of the category picker (2026-09-19, build 1008).
    ///
    /// Signs in exactly like the smoke above, opens the first Pending card's Assembly Review and
    /// drives the equipment picker WITHOUT ever changing an assignment: the picker opens in the
    /// canonical category of the machine already assigned, the category sheet scrolls the whole
    /// list, a category that started off-screen is chosen and the wheel reloads for it, and search
    /// by name and by Equipment ID stays inside that category. Nothing is selected — the picker is
    /// cancelled — so a live customer order is only ever read.
    func testTheCategoryPickerOpensInTheUnitsCategoryScrollsAndSearchesWithoutChangingAnything() {
        let app = XCUIApplication()
        app.launch()
        clearSystemAlerts()
        signIn(app)

        let queueLine = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Queue Line'")).firstMatch
        XCTAssertTrue(queueLine.waitForExistence(timeout: 30), "Home did not show the Queue Line entry")
        queueLine.tap()
        XCTAssertTrue(app.buttons["Pending"].firstMatch.waitForExistence(timeout: 30), "Queue Line board did not appear")
        let update = app.buttons.matching(identifier: "queueLineUpdate").firstMatch
        XCTAssertTrue(update.waitForExistence(timeout: 30), "no Update button on a Pending card")
        usleep(1_500_000)
        update.tap()
        let review = app.descendants(matching: .any).matching(identifier: "assemblyReview.order").firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 30), "Update did not open the Assembly Review")
        usleep(2_500_000)
        shoot("prod-review")

        // Tap the identity of a machine that is already assigned — the picker, not an assignment.
        let reassign = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier ENDSWITH '.unit.reassign'")).firstMatch
        if !reassign.exists { app.swipeUp(); usleep(600_000) }
        XCTAssertTrue(reassign.waitForExistence(timeout: 20), "no assigned machine to open the picker with")
        reassign.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 20), "the equipment picker did not open")
        usleep(1_500_000)

        // 1 · it opened in the canonical category of the CURRENT machine, resolved by the server.
        let pill = app.descendants(matching: .any).matching(identifier: "equipmentPicker.category").firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "the picker offers no Category pill")
        let opening = pill.label
        XCTAssertTrue(opening.hasPrefix("Category: "), "pill reads '\(opening)'")
        XCTAssertNotEqual(opening, "Category: All categories", "the server did not resolve the unit's category")
        let wheel = app.pickerWheels.firstMatch
        let openingWheel = wheel.value as? String ?? ""
        shoot("prod-picker-default-category")

        // 2 · the sheet carries the whole canonical list and scrolls through it.
        pill.tap()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "the category sheet did not open")
        XCTAssertTrue(sheet.buttons["All categories"].waitForExistence(timeout: 10))
        let currentTitle = String(opening.dropFirst("Category: ".count))
        XCTAssertTrue(sheet.buttons["✓ \(currentTitle)"].exists, "the sheet does not tick the current category")
        shoot("prod-category-sheet-top")

        // Every row on the sheet, and the ones that start out of reach.
        let rows = sheet.buttons.allElementsBoundByIndex.map { $0.label }
            .filter { $0 != "Cancel" && $0 != "All categories" && !$0.hasPrefix("✓") }
        XCTAssertGreaterThan(rows.count, 5, "production should offer many categories, saw \(rows.count)")
        let offScreen = sheet.buttons.allElementsBoundByIndex.first { !$0.isHittable && $0.label != "Cancel"
            && $0.label != "All categories" && !$0.label.hasPrefix("✓") && !$0.label.isEmpty }
        XCTAssertNotNil(offScreen, "no category started below the fold — the list fits one screen")
        let target = offScreen!.label

        // 3 · scroll to it and choose it.
        XCTAssertTrue(scrollSheetTo(app, sheet.buttons[target]), "'\(target)' could not be reached by scrolling")
        shoot("prod-category-sheet-scrolled")
        sheet.buttons[target].tap()
        usleep(3_000_000)

        // 4 · the picker reloaded for the chosen category.
        XCTAssertEqual(pill.label, "Category: \(target)", "the pill did not follow the choice")
        let reloaded = wheel.value as? String ?? ""
        XCTAssertNotEqual(reloaded, openingWheel, "the wheel did not reload for '\(target)'")
        shoot("prod-picker-other-category")

        // 5 · search by name and by Equipment ID, scoped to the category on screen.
        //     "<name>    ||    <code>" — skipped when the chosen category holds no equipment.
        let parts = reloaded.components(separatedBy: "||").map { $0.trimmingCharacters(in: .whitespaces) }
        // A real machine name can open with a size ("12\" Morbark - Gas"), so search the longest
        // WORD in it rather than a blind prefix.
        let word = parts.first?
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && $0.rangeOfCharacter(from: .letters) != nil }
            .max(by: { $0.count < $1.count })
        if parts.count == 2, let name = word, let code = parts.last, !code.isEmpty {
            searchOnPicker(app, name)
            XCTAssertTrue((wheelValue(app) ?? "").lowercased().contains(name.lowercased()),
                          "search by name '\(name)' → '\(wheelValue(app) ?? "no wheel")'")
            shoot("prod-picker-search-name")
            searchOnPicker(app, code)
            XCTAssertTrue((wheelValue(app) ?? "").contains(code),
                          "search by Equipment ID '\(code)' → '\(wheelValue(app) ?? "no wheel")'")
            XCTAssertEqual(pill.label, "Category: \(target)", "search never leaves the selected category")
            shoot("prod-picker-search-id")
        }

        // 6 · nothing is selected: Cancel, and the review still shows the machine it had.
        app.buttons["Cancel"].firstMatch.tap()
        usleep(1_500_000)
        XCTAssertTrue(review.waitForExistence(timeout: 15), "Cancel did not return to the review")
        shoot("prod-review-unchanged")

        // 7 · the installed version.
        goBack(app)
        _ = app.buttons["Pending"].firstMatch.waitForExistence(timeout: 20)
        goBack(app)
        let settingsTab = app.tabBars.buttons.element(boundBy: max(0, app.tabBars.buttons.count - 1))
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 20), "tab bar not visible")
        settingsTab.tap()
        let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Version:'")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 15), "Version row not found")
        shoot("prod-about")
        if let expect = env["KABBA_EXPECT_VERSION"], !expect.isEmpty {
            XCTAssertTrue(version.label.contains(expect), "Version row '\(version.label)' should contain \(expect)")
        }
    }

    /// The Login screen when the session is fresh; a kept session goes straight to Home.
    private func signIn(_ app: XCUIApplication) {
        let loginButton = app.buttons["login.button"]
        let queueLine = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'Queue Line'")).firstMatch
        var deadline = Date().addingTimeInterval(45)
        while Date() < deadline, !loginButton.exists, !queueLine.exists { usleep(500_000); clearSystemAlerts() }
        guard loginButton.exists else { return }
        typeInto(app, "login.companyCode", env["KABBA_COMPANY_CODE"] ?? "")
        typeInto(app, "login.email", env["KABBA_EMAIL"] ?? "")
        typeInto(app, "login.password", env["KABBA_PASSWORD"] ?? "")
        loginButton.tap()
        deadline = Date().addingTimeInterval(90)
        var lastTap = Date()
        while Date() < deadline, loginButton.exists, !queueLine.exists {
            usleep(500_000); clearSystemAlerts()
            if loginButton.exists, Date().timeIntervalSince(lastTap) > 20 { loginButton.tap(); lastTap = Date() }
        }
        dismissSavePasswordSheet(app)
        clearSystemAlerts()
    }

    /// The wheel's current row once it is back on screen, or nil if it never returns.
    private func wheelValue(_ app: XCUIApplication, timeout: TimeInterval = 8) -> String? {
        let wheel = app.pickerWheels.firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if wheel.exists, let v = wheel.value as? String, !v.isEmpty { return v }
            usleep(400_000)
        }
        return nil
    }

    /// The picker's Search pill → the term alert → the server's matches for the category on screen.
    /// A "no match" answer is reported as such rather than left to fail as a missing wheel.
    private func searchOnPicker(_ app: XCUIApplication, _ term: String) {
        let search = app.descendants(matching: .any).matching(identifier: "equipmentPicker.search").firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "the picker offers no search")
        search.tap()
        let field = app.descendants(matching: .any).matching(identifier: "equipmentPicker.searchField").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field")
        field.tap()
        // The field opens pre-filled with the term in force — clear it, or the new term is appended.
        if let existing = field.value as? String, !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(term)
        app.alerts.buttons["Search"].firstMatch.tap()
        usleep(2_500_000)
        // "No eligible equipment matches …" — acknowledge whatever the alert offers so the wheel comes back.
        if app.alerts.firstMatch.exists {
            let alert = app.alerts.firstMatch
            let message = alert.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " / ")
            alert.buttons.allElementsBoundByIndex.last?.tap()
            usleep(1_500_000)
            XCTFail("search '\(term)' returned nothing: \(message)")
        }
    }

    /// Drags inside the category sheet until `target` is hittable (or gives up).
    @discardableResult
    private func scrollSheetTo(_ app: XCUIApplication, _ target: XCUIElement) -> Bool {
        let sheet = app.sheets.firstMatch
        for _ in 0..<12 {
            if target.exists && target.isHittable { return true }
            sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
                .press(forDuration: 0.05,
                       thenDragTo: sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)))
            usleep(400_000)
        }
        return target.exists && target.isHittable
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
