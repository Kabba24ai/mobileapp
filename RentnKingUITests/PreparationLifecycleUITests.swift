//
//  PreparationLifecycleUITests.swift
//  RentnKingUITests — Pre-departure preparation lifecycle (equipment
//  substitution + Delete Checklist / Start Over) physical acceptance A–H.
//
//  Drives the REAL app against a controlled staging backend through the
//  DEBUG-only StagingTestHarness (same pattern as DispatchParityUITests).
//  Each scenario is its own test method, run individually via -only-testing;
//  the runner verifies canonical server state (executions, cycles, soft
//  assigns, staged latch) out of band between runs.
//
//  Env (forwarded by xcodebuild as TEST_RUNNER_*):
//    KABBA_BASE_URL / KABBA_EMAIL / KABBA_PASSWORD   staging harness login
//

import XCTest

final class PreparationLifecycleUITests: XCTestCase {

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

        addUIInterruptionMonitor(withDescription: "system-permission") { alert in
            for label in ["Allow", "Allow While Using App", "OK", "Don’t Allow", "Don't Allow", "Allow Full Access"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
    }

    // ── Plumbing ─────────────────────────────────────────────────────────────

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

    private func textElement(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func dump(_ app: XCUIApplication, _ tag: String) {
        print("┏━━ DUMP[\(tag)] ━━━━━━━━━━━━━━━━━━━━━━━━")
        print(app.debugDescription)
        print("┗━━ END DUMP[\(tag)] ━━━━━━━━━━━━━━━━━━━━")
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        att.name = "shot-\(tag)"
        att.lifetime = .keepAlways
        add(att)
    }

    /// Screenshot-only evidence (no hierarchy dump).
    private func shoot(_ tag: String) {
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        att.name = "shot-\(tag)"
        att.lifetime = .keepAlways
        add(att)
    }

    /// Dismisses springboard-owned system permission alerts (fresh-install
    /// notification prompt etc.) that the in-app interruption monitor cannot
    /// always reach.
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

    @discardableResult
    private func login(_ app: XCUIApplication) -> XCUIApplication {
        app.launch()
        let loginButton = app.buttons["login.button"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 40), "staging Login screen did not appear")
        loginButton.tap()
        clearSystemAlerts()
        let deadline = Date().addingTimeInterval(60)
        var lastTap = Date()
        while Date() < deadline, loginButton.exists {
            usleep(400_000)
            clearSystemAlerts()
            // A system alert can swallow the tap — re-submit periodically.
            if loginButton.exists, Date().timeIntervalSince(lastTap) > 6 {
                loginButton.tap()
                lastTap = Date()
            }
        }
        XCTAssertFalse(loginButton.exists, "still on the Login screen after sign-in")
        return app
    }

    private func openQueueLine(_ app: XCUIApplication) {
        let entry = textElement(app, "Queue Line")
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "Home screen offered no Queue Line entry")
        entry.tap()
        usleep(1_500_000)
    }

    /// Switches the Queue Line board tab ("Pending" / "Staged" / "Completed").
    private func selectTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.buttons[name].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "no '\(name)' tab on the board")
        tab.tap()
        usleep(1_200_000)
    }

    /// Taps the 'checklist' icon on the card whose text contains `anchor`
    /// (e.g. "#EXC-A" or a product name — the card's unit line).
    private func openCard(_ app: XCUIApplication, anchor: String) {
        let anchorEl = textElement(app, anchor)
        if !anchorEl.waitForExistence(timeout: 30) { dump(app, "no-card-\(anchor)") }
        XCTAssertTrue(anchorEl.exists, "no Queue Line card containing '\(anchor)'")
        let y = anchorEl.frame.midY

        let icons = app.buttons.matching(identifier: "checklist").allElementsBoundByIndex
        XCTAssertFalse(icons.isEmpty, "no checklist icons on the board")
        let nearest = icons.min(by: { abs($0.frame.midY - y) < abs($1.frame.midY - y) })!
        nearest.tap()
        usleep(2_000_000)
    }

    private func expectOnChecklist(_ app: XCUIApplication, unit code: String, timeout: TimeInterval = 30) {
        let row = textElement(app, "\(code)    ||    \(code)")
        if row.waitForExistence(timeout: timeout / 2) { return }
        // The Equipment ID header may be scrolled off-screen — scroll to top.
        for _ in 0..<4 where !row.exists {
            app.tables.firstMatch.swipeDown()
            usleep(700_000)
        }
        if !row.waitForExistence(timeout: timeout / 2) { dump(app, "unit-row-missing-\(code)") }
        XCTAssertTrue(row.exists, "checklist Equipment ID row does not show '\(code)'")
    }

    /// True when the EQUIPMENT picker (header pill "Select Equipment ID") is up.
    private func equipmentPickerIsOpen(_ app: XCUIApplication) -> Bool {
        app.pickerWheels.firstMatch.exists && textElement(app, "Select Equipment ID").exists
    }

    /// Opens the Equipment ID picker: taps the unit row text (the picker button
    /// covers it); falls back to the other stacked buttons over that row. A tap
    /// can land on the CATEGORY picker instead — detect via the header title,
    /// cancel, and try the next candidate.
    private func openEquipmentPicker(_ app: XCUIApplication, currentCode: String) {
        let unitRow = textElement(app, "\(currentCode)    ||    \(currentCode)")
        XCTAssertTrue(unitRow.waitForExistence(timeout: 20), "no Equipment ID row for '\(currentCode)'")
        let center = CGPoint(x: unitRow.frame.midX, y: unitRow.frame.midY)

        func settled() -> Bool {
            guard app.pickerWheels.firstMatch.waitForExistence(timeout: 6) else { return false }
            usleep(500_000)
            if equipmentPickerIsOpen(app) { return true }
            // Wrong picker (e.g. Category) — close it and keep trying.
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists { cancel.tap(); usleep(700_000) }
            return false
        }

        _ = center // documented: frames go stale after the mode flip below

        // ASSIGNED mode shows the unit with a full-width "Change" overlay
        // (btnMachineUpdate) on top of the row; tapping it re-renders the
        // header into UPDATE mode (Category ID appears, row moves down) where
        // btnMachineId is on top. So: flip modes first, then re-locate the
        // row and tap again for the picker.
        if !textElement(app, "Category ID").exists {
            unitRow.tap()
            _ = textElement(app, "Category ID").waitForExistence(timeout: 8)
            usleep(800_000)
        }

        let unitText = "\(currentCode)    ||    \(currentCode)"
        for _ in 0..<3 {
            let row = textElement(app, unitText)
            guard row.waitForExistence(timeout: 8) else { break }
            row.tap()
            if settled() { return }
            if app.alerts.firstMatch.exists {
                dump(app, "equipment-picker-alert")
                XCTFail("alert while opening equipment picker: \(app.alerts.firstMatch.label)")
                return
            }
        }
        dump(app, "equipment-picker-failed")
        XCTFail("could not open the Select Equipment ID picker")
    }

    /// Full substitution gesture. `expectConfirmation` = the destructive alert
    /// must appear and is confirmed; false = it must NOT appear (nothing to
    /// discard). The wheel rows read "<name>    ||    <code>".
    private func substitute(_ app: XCUIApplication, from currentCode: String, to replacementCode: String,
                            replacementName: String, expectConfirmation: Bool) {
        openEquipmentPicker(app, currentCode: currentCode)

        let wheel = app.pickerWheels.firstMatch
        wheel.adjust(toPickerWheelValue: "\(replacementName)    ||    \(replacementCode)")
        usleep(500_000)
        let select = app.buttons["Select"].firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 5), "picker Select pill missing")
        select.tap()

        let confirm = app.alerts.buttons["Change Equipment & Start Over"]
        if expectConfirmation {
            XCTAssertTrue(confirm.waitForExistence(timeout: 10),
                          "expected the 'Change equipment and start over?' confirmation")
            confirm.tap()
        } else {
            usleep(2_000_000)
            XCTAssertFalse(confirm.exists, "no confirmation expected for a substitution with nothing to discard")
            XCTAssertFalse(app.alerts.firstMatch.exists,
                           "no alert of any kind expected — got: \(app.alerts.firstMatch.label)")
        }
        usleep(2_500_000)
    }

    /// Answers every VISIBLE unanswered picker row matching the question label.
    /// Returns how many it answered.
    @discardableResult
    private func answerVisible(_ app: XCUIApplication, question: String, answer: String, seek: Bool = false) -> Int {
        var answered = 0
        let q = NSPredicate(format: "label CONTAINS[c] %@", question)

        func visibleCandidate() -> XCUIElement? {
            app.tables.cells.allElementsBoundByIndex.first(where: { cell in
                cell.staticTexts.matching(q).count > 0 && cell.staticTexts["Select"].exists
                    && cell.frame.minY > 100 && cell.frame.maxY < app.windows.firstMatch.frame.maxY
            })
        }

        for _ in 0..<3 {
            var found = visibleCandidate()
            if found == nil && seek {
                // Scroll from the top of the sheet looking for the row.
                for _ in 0..<3 where visibleCandidate() == nil { app.tables.firstMatch.swipeDown(); usleep(600_000) }
                var hops = 0
                while visibleCandidate() == nil, hops < 6 { app.tables.firstMatch.swipeUp(); usleep(600_000); hops += 1 }
                found = visibleCandidate()
            }
            guard let cell = found else { break }

            cell.staticTexts["Select"].firstMatch.tap()
            let wheel = app.pickerWheels.firstMatch
            XCTAssertTrue(wheel.waitForExistence(timeout: 8), "answer picker did not open for '\(question)'")
            wheel.adjust(toPickerWheelValue: answer)
            usleep(400_000)
            app.buttons["Select"].firstMatch.tap()
            usleep(900_000)
            answered += 1
        }
        return answered
    }

    /// Types hours into at most `max` visible text fields under a "Start Hours"
    /// label, committing each with the keyboard toolbar's Done. NOTE: the app
    /// repurposes the field's accessibilityValue as a section index, so the
    /// field's XCUITest value can never reveal whether it was already filled —
    /// the caller caps the total fills instead.
    /// Sections whose hours field this run already typed into. The app stores
    /// the SECTION INDEX in the field's accessibilityValue, so the value can
    /// never reveal filled-vs-empty — but it is a perfect per-section dedupe.
    private var hoursSectionsFilled = Set<String>()

    @discardableResult
    private func enterVisibleHours(_ app: XCUIApplication, hours: String, max maxFills: Int) -> Int {
        guard maxFills > 0 else { return 0 }
        var filled = 0
        let q = NSPredicate(format: "label CONTAINS[c] 'hours'")
        let windowMaxY = app.windows.firstMatch.frame.maxY
        for i in 0..<app.staticTexts.matching(q).count {
            guard filled < maxFills else { break }
            let label = app.staticTexts.matching(q).element(boundBy: i)
            // Scroll the hours row into the interactable band.
            var attempts = 0
            while label.exists, label.frame.minY < 130, attempts < 6 {
                app.tables.firstMatch.swipeDown(); usleep(700_000); attempts += 1
            }
            while label.exists, label.frame.maxY > windowMaxY - 180, attempts < 12 {
                app.tables.firstMatch.swipeUp(); usleep(700_000); attempts += 1
            }
            guard label.exists, label.frame.minY > 120 else { continue }
            let fields = app.textFields.allElementsBoundByIndex.filter { f in
                f.frame.minY > label.frame.maxY - 6 && f.frame.minY < label.frame.maxY + 80
            }
            for field in fields where filled < maxFills {
                guard field.isHittable else { continue }
                let section = String(describing: field.value ?? "")
                guard !hoursSectionsFilled.contains(section) else { continue }
                field.tap()
                usleep(500_000)
                field.typeText(hours)
                let done = app.toolbars.buttons["Done"].firstMatch
                if done.waitForExistence(timeout: 3) {
                    done.tap()
                } else {
                    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09)).tap()
                }
                usleep(800_000)
                hoursSectionsFilled.insert(section)
                filled += 1
            }
        }
        return filled
    }

    /// Fills the whole visible checklist for one or more product sections by
    /// scrolling top-to-bottom: fuel, both template questions, hours.
    /// `hourFields` = how many hour-meter fields the screen holds (one per
    /// hour-tracked product section).
    private func fillChecklist(_ app: XCUIApplication, hours: String = "200", hourFields: Int = 1, expectSelects: Int = 3) {
        _ = expectSelects   // superseded by the walk-to-bottom strategy
        for _ in 0..<3 { app.tables.firstMatch.swipeDown() }
        usleep(600_000)
        hoursSectionsFilled.removeAll()

        func visibleSignature() -> String {
            app.tables.firstMatch.cells.allElementsBoundByIndex.prefix(6)
                .map { String(format: "%.0f", $0.frame.minY) }.joined(separator: ",")
        }

        var idleSweeps = 0
        for _ in 0..<24 {
            var acted = 0
            acted += answerVisible(app, question: "Fuel (", answer: "Full")
            acted += answerVisible(app, question: "body damage", answer: "No damage")
            acted += answerVisible(app, question: "Keys handed", answer: "Yes")
            acted += enterVisibleHours(app, hours: hours, max: max(0, hourFields - hoursSectionsFilled.count))
            acted += fillVisibleEmployees(app)

            if acted > 0 { idleSweeps = 0; continue }

            let before = visibleSignature()
            app.tables.firstMatch.swipeUp()
            usleep(800_000)
            if visibleSignature() == before {
                idleSweeps += 1              // the table no longer moves: bottom
                if idleSweeps >= 2 { break }
            } else {
                idleSweeps = 0
            }
        }
    }

    /// Sets every visible EMPTY "Delivered By" employee field (each product
    /// section has its own) the way an operator does: tap → picker → Select.
    @discardableResult
    private func fillVisibleEmployees(_ app: XCUIApplication) -> Int {
        var filled = 0
        let q = NSPredicate(format: "label CONTAINS[c] 'Delivered By'")
        for label in app.staticTexts.matching(q).allElementsBoundByIndex {
            guard label.frame.minY > 120 else { continue }
            let fields = app.textFields.allElementsBoundByIndex.filter { f in
                f.frame.minY > label.frame.maxY - 6 && f.frame.minY < label.frame.maxY + 70
            }
            for field in fields {
                let value = String(describing: field.value ?? "")
                // Empty shows the placeholder ("Select Employee").
                guard value.isEmpty || value == "0" || value.localizedCaseInsensitiveContains("select") else { continue }
                guard field.isHittable else { continue }
                field.tap()
                let wheel = app.pickerWheels.firstMatch
                guard wheel.waitForExistence(timeout: 8) else { continue }
                // Accept the picker's current row — any employee satisfies the
                // "who delivered it" requirement for the acceptance run.
                usleep(400_000)
                app.buttons["Select"].firstMatch.tap()
                usleep(800_000)
                filled += 1
            }
        }
        return filled
    }

    private func tapSave(_ app: XCUIApplication) {
        let save = textElement(app, "Save")
        XCTAssertTrue(save.waitForExistence(timeout: 15), "Save control missing")
        save.tap()
    }

    /// Save that must STAGE: confirmation toast, then the smart-router opens
    /// Delivery Video Upload when the active cycle still needs a video.
    private func saveExpectStaged(_ app: XCUIApplication, expectVideoRouting: Bool) {
        tapSave(app)

        // The partial-progress alert means the checklist was NOT complete.
        let progressAlert = textElement(app, "Progress saved")
        usleep(1_500_000)
        if progressAlert.exists {
            dump(app, "save-was-partial")
            XCTFail("Save hit the partial-progress path — checklist was not complete")
            return
        }

        if expectVideoRouting {
            // Router waits ~1.2s after the toast, then pushes the upload screen.
            let marker = textElement(app, "Upload")
            if !marker.waitForExistence(timeout: 15) { dump(app, "no-video-routing") }
            XCTAssertTrue(marker.exists,
                          "expected the Delivery Video Upload routing after a staging Save")
            dump(app, "video-upload-screen")
        } else {
            sleep(4)
            XCTAssertFalse(textElement(app, "Upload").exists,
                           "video upload must NOT be requested when the active cycle already has a video")
        }
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["icon back"].firstMatch
        if back.waitForExistence(timeout: 5) { back.tap(); usleep(1_200_000); return }
        if let btn = app.buttons.allElementsBoundByIndex.first(where: { $0.frame.minY < 110 && $0.frame.minX < 70 }) {
            btn.tap(); usleep(1_200_000)
        }
    }

    /// Leaves the board and re-enters it so the Queue Line re-FETCHES from the
    /// server (tab taps only re-render already-loaded data; the engine may
    /// still be flushing a queued staging op when we first come back).
    private func refreshBoard(_ app: XCUIApplication) {
        backToBoard(app)
        sleep(6)                      // engine flush window
        goBack(app)                   // board → Home
        openQueueLine(app)
    }

    /// Pops screens until the Queue Line board (its Staged tab) is visible.
    private func backToBoard(_ app: XCUIApplication) {
        for _ in 0..<4 {
            if app.buttons["Staged"].firstMatch.exists { return }
            goBack(app)
        }
        XCTAssertTrue(app.buttons["Staged"].firstMatch.waitForExistence(timeout: 10),
                      "never returned to the Queue Line board")
    }

    /// Asserts a board card shows the given unit under the given tab.
    private func expectCard(_ app: XCUIApplication, tab: String, anchor: String) {
        selectTab(app, tab)
        XCTAssertTrue(textElement(app, anchor).waitForExistence(timeout: 20),
                      "expected a card containing '\(anchor)' under the \(tab) tab")
    }

    private func expectNoCard(_ app: XCUIApplication, tab: String, anchor: String) {
        selectTab(app, tab)
        usleep(1_500_000)
        XCTAssertFalse(textElement(app, anchor).exists,
                       "did NOT expect a card containing '\(anchor)' under the \(tab) tab")
    }

    // ── Explorer (read-only walk; produces hierarchy dumps) ─────────────────

    func test00_explore() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        let app = login(makeApp())
        dump(app, "home")

        openQueueLine(app)
        dump(app, "queue-line")

        openCard(app, anchor: "#EXC-A")
        _ = textElement(app, "EXC-").waitForExistence(timeout: 30)
        sleep(3)
        dump(app, "checklist")

        app.tables.firstMatch.swipeUp()
        usleep(800_000)
        dump(app, "checklist-mid")
        app.tables.firstMatch.swipeUp()
        usleep(800_000)
        dump(app, "checklist-bottom")

        // Open the equipment picker read-only, dump, cancel.
        for _ in 0..<3 { app.tables.firstMatch.swipeDown() }
        usleep(600_000)
        openEquipmentPicker(app, currentCode: "EXC-A")
        dump(app, "equipment-picker")
        app.buttons["Cancel"].firstMatch.tap()
    }

    // ── Probe: what appears after tapping each machine-cell overlay button ──

    func test01_probeEquipmentPicker() {
        let app = login(makeApp())
        openQueueLine(app)
        openCard(app, anchor: "#EXC-")
        let unitRow = textElement(app, "    ||    EXC-")
        XCTAssertTrue(unitRow.waitForExistence(timeout: 30))
        let center = CGPoint(x: unitRow.frame.midX, y: unitRow.frame.midY)
        let band = CGRect(x: 0, y: center.y - 130, width: app.windows.firstMatch.frame.width, height: 190)
        let overlapping = app.buttons.allElementsBoundByIndex.filter { $0.frame.intersects(band) && $0.frame.height < 60 }
        for (i, candidate) in overlapping.enumerated() {
            print("PROBE tapping button #\(i) at \(candidate.frame)")
            candidate.tap()
            sleep(3)
            dump(app, "probe-after-button-\(i)")
            if app.buttons["Cancel"].firstMatch.exists { app.buttons["Cancel"].firstMatch.tap(); sleep(1) }
        }
    }

    // ── Sim sanity: fill + save + staging + restart, no equipment picker ────

    func test02_simSanity() {
        let app = login(makeApp())
        openQueueLine(app)
        expectCard(app, tab: "Pending", anchor: "#EXC-A")
        openCard(app, anchor: "#EXC-A")
        expectOnChecklist(app, unit: "EXC-A")

        fillChecklist(app)
        saveExpectStaged(app, expectVideoRouting: true)
        backToBoard(app)
        expectCard(app, tab: "Staged", anchor: "#EXC-A")

        // Restart footer on the staged item.
        openCard(app, anchor: "#EXC-A")
        expectOnChecklist(app, unit: "EXC-A")
        var restart = textElement(app, "Delete Checklist / Start Over")
        for _ in 0..<8 where !(restart.exists && restart.isHittable) {
            app.tables.firstMatch.swipeUp()
            usleep(700_000)
            restart = textElement(app, "Delete Checklist / Start Over")
        }
        XCTAssertTrue(restart.exists, "no restart control on a staged checklist")
        restart.tap()
        let confirm = app.alerts.buttons["Delete & Start Over"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "restart confirmation missing")
        confirm.tap()
        sleep(4)
        shoot("sanity-inplace-after-restart")   // records the in-place refresh
        XCTAssertFalse(textElement(app, "No damage").exists, "answers survived the restart")
        goBack(app)
        expectCard(app, tab: "Pending", anchor: "#EXC-A")
        // Reopen: the fresh cycle must present the SAME unit with a blank sheet.
        openCard(app, anchor: "#EXC-A")
        expectOnChecklist(app, unit: "EXC-A")
        XCTAssertFalse(textElement(app, "No damage").exists, "answers survived the restart on reopen")
    }

    // ── Acceptance A — Pending substitution, nothing to discard ─────────────

    func testA_pendingSubstitution() {
        let app = login(makeApp())
        openQueueLine(app)
        expectCard(app, tab: "Pending", anchor: "#EXC-A")

        openCard(app, anchor: "#EXC-A")
        expectOnChecklist(app, unit: "EXC-A")

        substitute(app, from: "EXC-A", to: "EXC-B",
                   replacementName: "Mini Excavator EXC-B", expectConfirmation: false)
        expectOnChecklist(app, unit: "EXC-B")
        dump(app, "A-after-substitution")

        backToBoard(app)
        expectCard(app, tab: "Pending", anchor: "#EXC-B")
        expectNoCard(app, tab: "Staged", anchor: "Cody Cash")
    }

    // ── Acceptance B — partial answers, substitution discards them ──────────

    func testB_partialThenSubstitute() {
        let app = login(makeApp())
        openQueueLine(app)
        openCard(app, anchor: "#EXC-B")
        expectOnChecklist(app, unit: "EXC-B")

        // Machine-specific partial work: one answer + hours.
        answerVisible(app, question: "body damage", answer: "No damage", seek: true)
        XCTAssertTrue(textElement(app, "No damage").waitForExistence(timeout: 10), "answer was not applied")
        enterVisibleHours(app, hours: "123", max: 1)

        substitute(app, from: "EXC-B", to: "EXC-C",
                   replacementName: "Mini Excavator EXC-C", expectConfirmation: true)
        expectOnChecklist(app, unit: "EXC-C")
        sleep(2)

        // The partial work must NOT survive onto the replacement unit.
        XCTAssertFalse(textElement(app, "No damage").exists, "Unit B's answer survived onto Unit C")
        // The hours field's text is not readable over accessibility (its value
        // carries a section index), so use the Save path as the oracle: a
        // TRULY blank checklist takes the "nothing answered" path — any
        // surviving answer/hours would surface the "Progress saved" alert.
        tapSave(app)
        usleep(2_500_000)
        XCTAssertFalse(textElement(app, "Progress saved").exists,
                       "Unit B's partial work survived onto Unit C (Save found something to keep)")
        if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons.firstMatch.tap() }
        dump(app, "B-after-substitution")

        backToBoard(app)
        expectCard(app, tab: "Pending", anchor: "#EXC-C")
    }

    // ── Acceptance C — Save→Staged, then substitution discards the prep ─────

    func testC_stageThenSubstitute() {
        let app = login(makeApp())
        openQueueLine(app)
        openCard(app, anchor: "#EXC-C")
        expectOnChecklist(app, unit: "EXC-C")

        fillChecklist(app)
        saveExpectStaged(app, expectVideoRouting: true)

        // Leave the upload screen, verify the board shows Staged.
        backToBoard(app)
        expectCard(app, tab: "Staged", anchor: "#EXC-C")

        // Reopen the STAGED item and substitute — this must warn about
        // discarding the saved preparation, then de-stage.
        openCard(app, anchor: "#EXC-C")
        expectOnChecklist(app, unit: "EXC-C")
        substitute(app, from: "EXC-C", to: "EXC-A",
                   replacementName: "Mini Excavator EXC-A", expectConfirmation: true)
        expectOnChecklist(app, unit: "EXC-A")
        sleep(2)
        XCTAssertFalse(textElement(app, "No damage").exists, "the staged answers were restored after substitution")
        dump(app, "C-after-substitution")

        backToBoard(app)
        expectCard(app, tab: "Pending", anchor: "#EXC-A")
        expectNoCard(app, tab: "Staged", anchor: "Cody Cash")
    }

    // ── Acceptance E — fresh replacement preparation stages cleanly ─────────

    func testE_freshReplacementPreparation() {
        let app = login(makeApp())
        openQueueLine(app)
        openCard(app, anchor: "#EXC-A")
        expectOnChecklist(app, unit: "EXC-A")

        // Nothing from the discarded cycles may be pre-filled.
        XCTAssertFalse(textElement(app, "No damage").exists, "discarded answers were restored")

        fillChecklist(app)
        saveExpectStaged(app, expectVideoRouting: true)
        backToBoard(app)
        expectCard(app, tab: "Staged", anchor: "#EXC-A")
    }

    // ── Acceptance D — Delete Checklist / Start Over keeps the unit ─────────

    func testD_restartKeepsUnit() {
        let app = login(makeApp())
        openQueueLine(app)
        expectCard(app, tab: "Staged", anchor: "#EXC-A")
        openCard(app, anchor: "#EXC-A")
        expectOnChecklist(app, unit: "EXC-A")

        // The restart control lives in the table footer — scroll to it.
        var restart = textElement(app, "Delete Checklist / Start Over")
        for _ in 0..<8 where !(restart.exists && restart.isHittable) {
            app.tables.firstMatch.swipeUp()
            usleep(700_000)
            restart = textElement(app, "Delete Checklist / Start Over")
        }
        XCTAssertTrue(restart.exists, "no 'Delete Checklist / Start Over' control on a restartable checklist")
        dump(app, "D-restart-footer")
        restart.tap()

        let confirm = app.alerts.buttons["Delete & Start Over"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "restart confirmation did not appear")
        confirm.tap()
        sleep(4)
        shoot("D-inplace-after-restart")
        XCTAssertFalse(textElement(app, "No damage").exists, "prepared answers survived the restart")

        backToBoard(app)
        expectNoCard(app, tab: "Staged", anchor: "Cody Cash")
        expectCard(app, tab: "Pending", anchor: "#EXC-A")

        // Assignment kept, preparation gone — verified on the fresh open.
        openCard(app, anchor: "#EXC-A")
        expectOnChecklist(app, unit: "EXC-A")
        XCTAssertFalse(textElement(app, "No damage").exists, "prepared answers survived the restart on reopen")
        dump(app, "D-after-restart")
        goBack(app)
    }

    // ── Acceptance F — media isolation across a substitution ────────────────

    /// Phase 1: prepare + stage the current unit, land on the video upload
    /// screen, dump it (the runner uses the dump to drive/verify the capture).
    func testF1_stageAndOpenVideoUpload() {
        let app = login(makeApp())
        openQueueLine(app)
        openCard(app, anchor: "#EXC-A")
        expectOnChecklist(app, unit: "EXC-A")
        fillChecklist(app)
        saveExpectStaged(app, expectVideoRouting: true)
        sleep(2)
        dump(app, "F-video-upload")

        // Recon the capture affordances: tap the add-media tile, record what
        // appears (sheet / camera), then back out without capturing.
        if let tile = app.buttons.allElementsBoundByIndex.first(where: { ($0.value as? String)?.hasPrefix("ORD-SCH") == true }) {
            tile.tap()
            sleep(2)
            clearSystemAlerts()
            dump(app, "F-after-tile")
            for label in ["Cancel", "Dismiss"] where app.buttons[label].firstMatch.exists {
                app.buttons[label].firstMatch.tap(); break
            }
        }
    }

    /// Phase 1b: the REAL capture — reopen the staged item, Save re-routes to
    /// the upload screen, record a walk-around video with the device camera,
    /// Submit, and leave it syncing to Laravel.
    func testF1b_captureDeliveryVideo() {
        let app = login(makeApp())
        openQueueLine(app)
        selectTab(app, "Staged")
        openCard(app, anchor: "#EXC-A")
        expectOnChecklist(app, unit: "EXC-A")
        fillChecklist(app)                       // server-prefilled: usually a no-op
        saveExpectStaged(app, expectVideoRouting: true)
        sleep(2)

        guard let tile = app.buttons.allElementsBoundByIndex.first(where: { ($0.value as? String)?.hasPrefix("ORD-SCH") == true }) else {
            XCTFail("no add-media tile on the upload screen"); return
        }
        tile.tap()
        let selectVideo = app.buttons["Select Video"].firstMatch
        XCTAssertTrue(selectVideo.waitForExistence(timeout: 10), "no 'Select Video' choice")
        selectVideo.tap()

        // Second sheet: Take Video (camera) / Choose Video (library).
        let takeVideo = app.buttons["Take Video"].firstMatch
        XCTAssertTrue(takeVideo.waitForExistence(timeout: 10), "no 'Take Video' choice")
        takeVideo.tap()
        sleep(2)
        clearSystemAlerts()                      // camera + microphone permission
        sleep(1)
        clearSystemAlerts()
        sleep(2)
        dump(app, "F-camera")

        // The system camera: the shutter is the VideoCapture control.
        let shutter = app.buttons["VideoCapture"].firstMatch
        XCTAssertTrue(shutter.waitForExistence(timeout: 12), "no VideoCapture shutter — see F-camera dump")
        shutter.tap()                            // start recording
        sleep(4)
        app.buttons["VideoCapture"].firstMatch.tap()   // stop recording
        sleep(2)
        dump(app, "F-after-record")

        for label in ["Use Video", "Use", "Done", "Choose"] where app.buttons[label].firstMatch.exists {
            app.buttons[label].firstMatch.tap(); break
        }
        sleep(2)
        dump(app, "F-after-use")

        // Back on the upload screen: submit the capture.
        let submit = textElement(app, "Submit")
        XCTAssertTrue(submit.waitForExistence(timeout: 15), "did not return to the upload screen")
        submit.tap()
        sleep(6)                                 // give the engine a moment to sync
        dump(app, "F-after-submit")
    }

    /// Phase 2 (after Unit A's cycle has a delivery video): a Save on the SAME
    /// cycle must NOT re-route to video upload — the requirement is satisfied.
    func testF2_videoSatisfiesOwnCycle() {
        let app = login(makeApp())
        openQueueLine(app)
        expectCard(app, tab: "Staged", anchor: "#EXC-A")
        openCard(app, anchor: "#EXC-A")
        expectOnChecklist(app, unit: "EXC-A")
        // Already staged; Save again re-runs the router with the video present.
        fillChecklist(app)
        saveExpectStaged(app, expectVideoRouting: false)
    }

    /// Phase 3: after the A→B substitution (server-verified: the fresh cycle
    /// reports delivery_video_present=false while Unit A's video stays on the
    /// superseded cycle), preparing the replacement unit MUST route to the
    /// video upload again — Unit A's video cannot satisfy Unit B's cycle.
    func testF3_videoDoesNotCarryToReplacement() {
        let app = login(makeApp())
        openQueueLine(app)
        openCard(app, anchor: "#EXC-B")
        expectOnChecklist(app, unit: "EXC-B")

        // Give the fresh cycle's context a moment to land (a local draft may
        // legitimately pre-fill part of the sheet; the fill tops up the rest).
        _ = app.tables.cells.staticTexts["Select"].firstMatch.waitForExistence(timeout: 10)
        sleep(2)

        fillChecklist(app)
        saveExpectStaged(app, expectVideoRouting: true)   // ← the isolation proof
        dump(app, "F-unitB-needs-own-video")
    }

    // ── Acceptance G — In Transit refuses substitution AND restart ──────────

    func testG_inTransitRefusals() {
        let app = login(makeApp())
        openQueueLine(app)

        // The runner advanced the staged item to On My Way out of band.
        expectCard(app, tab: "Staged", anchor: "#EXC-B")
        XCTAssertTrue(textElement(app, "In Transit").waitForExistence(timeout: 15),
                      "board does not show the In Transit badge")

        openCard(app, anchor: "#EXC-B")
        expectOnChecklist(app, unit: "EXC-B")

        // Substitution refused. (First tap may only flip the header into
        // update mode — the picker tap itself is the guarded action.)
        var unitRow = textElement(app, "EXC-B    ||    EXC-B")
        XCTAssertTrue(unitRow.waitForExistence(timeout: 20))
        unitRow.tap()
        var refusal = textElement(app, "already on its way to the customer")
        if !refusal.waitForExistence(timeout: 6) {
            unitRow = textElement(app, "EXC-B    ||    EXC-B")
            XCTAssertTrue(unitRow.waitForExistence(timeout: 10))
            unitRow.tap()
            refusal = textElement(app, "already on its way to the customer")
        }
        XCTAssertTrue(refusal.waitForExistence(timeout: 10),
                      "expected the In Transit refusal for equipment substitution")
        XCTAssertFalse(app.pickerWheels.firstMatch.exists, "the equipment picker must not open In Transit")
        dump(app, "G-substitution-refused")
        if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons.firstMatch.tap() }

        // Restart control absent.
        for _ in 0..<8 { app.tables.firstMatch.swipeUp(); usleep(500_000) }
        XCTAssertFalse(textElement(app, "Delete Checklist / Start Over").exists,
                       "the restart control must be hidden while In Transit")

        backToBoard(app)
        expectCard(app, tab: "Staged", anchor: "#EXC-B")   // never reverted to Pending
    }

    // ── Acceptance H — multi-line isolation ─────────────────────────────────

    /// Units for the multi-line scenarios come from the runner (world state).
    private var hLine1: String { ProcessInfo.processInfo.environment["KABBA_H_LINE1"] ?? "EXC-H1" }
    private var hLine2: String { ProcessInfo.processInfo.environment["KABBA_H_LINE2"] ?? "EXC-X" }
    private var hSub: String   { ProcessInfo.processInfo.environment["KABBA_H_SUB"] ?? "EXC-C" }

    /// Stage BOTH lines of order 1650 in one visit (both sections filled).
    func testH1_stageBothLines() {
        let app = login(makeApp())
        openQueueLine(app)
        openCard(app, anchor: "#\(hLine1)")
        expectOnChecklist(app, unit: hLine1)

        fillChecklist(app, hourFields: 2, expectSelects: 6)   // both sections
        saveExpectStaged(app, expectVideoRouting: true)
        refreshBoard(app)
        expectCard(app, tab: "Staged", anchor: "#\(hLine1)")
        expectCard(app, tab: "Staged", anchor: "#\(hLine2)")
    }

    /// Substitute Line 1 only — Line 2 must remain staged and untouched.
    func testH2_substituteLine1() {
        let app = login(makeApp())
        openQueueLine(app)
        selectTab(app, "Staged")
        openCard(app, anchor: "#\(hLine1)")
        expectOnChecklist(app, unit: hLine1)

        substitute(app, from: hLine1, to: hSub,
                   replacementName: "Mini Excavator \(hSub)", expectConfirmation: true)
        expectOnChecklist(app, unit: hSub)
        dump(app, "H-after-line1-substitution")

        refreshBoard(app)
        expectCard(app, tab: "Pending", anchor: "#\(hSub)")
        expectCard(app, tab: "Staged", anchor: "#\(hLine2)")   // sibling untouched
    }

    /// Restart Line 2 only (footer acts on the focused line) — Line 1 keeps its
    /// fresh state; Line 2 goes back to Pending with the same unit.
    func testH3_restartLine2() {
        let app = login(makeApp())
        openQueueLine(app)
        selectTab(app, "Staged")
        openCard(app, anchor: "#\(hLine2)")
        expectOnChecklist(app, unit: hLine2)

        var restart = textElement(app, "Delete Checklist / Start Over")
        for _ in 0..<10 where !(restart.exists && restart.isHittable) {
            app.tables.firstMatch.swipeUp()
            usleep(700_000)
            restart = textElement(app, "Delete Checklist / Start Over")
        }
        XCTAssertTrue(restart.exists, "no restart control for the staged line")
        dump(app, "H-restart-footer-multiline")
        restart.tap()
        let confirm = app.alerts.buttons["Delete & Start Over"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        sleep(4)
        shoot("H-inplace-after-restart")

        refreshBoard(app)
        expectCard(app, tab: "Pending", anchor: "#\(hLine2)")
        // Reopen: unit kept, sheet blank.
        openCard(app, anchor: "#\(hLine2)")
        expectOnChecklist(app, unit: hLine2)
        XCTAssertFalse(textElement(app, "No damage").exists, "line 2's answers survived its restart")
        goBack(app)
    }

    // ── Risk 2 — out-of-band office reassignment reconciled by the GET ──────

    func testR2_outOfBandReassignment() {
        // The runner changed the line's equipment OUT OF BAND (raw office/auto
        // path, no supersession) while a prepared cycle existed. The board
        // still shows the stale Staged state; OPENING the checklist re-requests
        // the context, and openExecution()'s backstop must supersede the stale
        // preparation rather than silently repoint it: new unit, blank
        // checklist, and the board drops back to Pending.
        let r2New = ProcessInfo.processInfo.environment["KABBA_R2_NEW"] ?? "EXC-A"
        let app = login(makeApp())
        openQueueLine(app)
        expectCard(app, tab: "Staged", anchor: "#\(r2New)")

        openCard(app, anchor: "#\(r2New)")
        expectOnChecklist(app, unit: r2New)
        sleep(3)   // context GET → supersession → fresh cycle
        XCTAssertFalse(textElement(app, "No damage").exists, "stale prepared answers survived the out-of-band reassignment")
        dump(app, "R2-after-oob-reassign")

        refreshBoard(app)
        expectCard(app, tab: "Pending", anchor: "#\(r2New)")
        expectNoCard(app, tab: "Staged", anchor: "#\(r2New)")
    }
}
