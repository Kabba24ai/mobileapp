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

    /// Like `shoot`, and also writes `<tag>.png` into $KABBA_SHOT_DIR when that is set
    /// (forwarded as TEST_RUNNER_KABBA_SHOT_DIR) so a review can look at the PNGs directly.
    private func shootToDisk(_ tag: String) {
        let shot = XCUIScreen.main.screenshot()
        if let dir = ProcessInfo.processInfo.environment["KABBA_SHOT_DIR"], !dir.isEmpty {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(tag).png"))
        }
        let att = XCTAttachment(screenshot: shot)
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

    /// Taps the Update button (the card's ONE action → Delivery Checklist) on the
    /// card whose text contains `anchor` (e.g. "#EXC-A" or a product name — the
    /// card's unit line).
    /// Taps Update on the card containing `anchor`. Since Assembly Review (2026-09-14)
    /// every card opens the review first, and its checklist may only open once the
    /// assembly is GO — so this confirms every requirement and taps the anchored
    /// member's Continue, landing on the checklist exactly as before.
    private func openCard(_ app: XCUIApplication, anchor: String, memberUid: String? = nil) {
        tapUpdate(app, anchor: anchor)
        guard element(app, id: "assemblyReview.order").waitForExistence(timeout: 20) else { return }
        confirmEverything(app)
        continueFromReview(app, memberUid: memberUid)
    }

    /// Update on the card containing `anchor`, nothing more (lands on the Assembly Review).
    private func tapUpdate(_ app: XCUIApplication, anchor: String) {
        let anchorEl = textElement(app, anchor)
        if !anchorEl.waitForExistence(timeout: 30) { dump(app, "no-card-\(anchor)") }
        XCTAssertTrue(anchorEl.exists, "no Queue Line card containing '\(anchor)'")
        let y = anchorEl.frame.midY

        let buttons = app.buttons.matching(identifier: "queueLineUpdate").allElementsBoundByIndex
        XCTAssertFalse(buttons.isEmpty, "no Update buttons on the board")
        // A card's Update sits in ITS header row: level with a header anchor (the order
        // number) and ABOVE a body anchor (the unit line, the assembly line). So the card's
        // own button is the lowest Update whose bottom is not below the anchor's bottom —
        // the next card's header is always further down.
        let ownOrAbove = buttons.filter { $0.frame.maxY <= anchorEl.frame.maxY + 24 }   // level: the pill is taller than the label
        let nearest = ownOrAbove.max(by: { $0.frame.maxY < $1.frame.maxY })
            ?? buttons.min(by: { abs($0.frame.midY - y) < abs($1.frame.midY - y) })!
        nearest.tap()
        usleep(2_000_000)
    }

    /// Confirms every enabled, still-unconfirmed requirement on the review (the
    /// affirmative control: hollow Available → filled). Scrolls as needed.
    private func confirmEverything(_ app: XCUIApplication) {
        let unconfirmed = NSPredicate(format: "identifier ENDSWITH '.available' AND value == 'not confirmed'")
        for _ in 0..<12 {
            let candidates = app.buttons.matching(unconfirmed).allElementsBoundByIndex.filter { $0.isEnabled }
            guard let next = candidates.first else { break }
            if !next.isHittable { _ = reveal(app, next, tag: "confirm") }
            next.tap()
            usleep(700_000)
        }
        for _ in 0..<6 { app.swipeDown(); usleep(200_000) }
    }

    /// Taps Continue for the given member (or the first enabled one).
    private func continueFromReview(_ app: XCUIApplication, memberUid: String? = nil) {
        let id = memberUid.map { "assembly.\($0).continue" }
        let button = id.map { element(app, id: $0) }
            ?? app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.continue' AND enabled == true")).firstMatch
        XCTAssertTrue(reveal(app, button, tag: "continue"), "no Continue to Checklist on the review")
        XCTAssertTrue(button.isEnabled, "Continue must be enabled once the assembly is GO")
        button.tap()
        usleep(2_000_000)
    }

    /// Scrolls the checklist table back to its first row. A plain swipe at the table's
    /// centre can land on a section's Delivery Note text view (a scroll view of its own)
    /// and move nothing — so drag from just under the header instead, where question
    /// cells live, and keep going until `target` is back in the hierarchy.
    private func scrollChecklistToTop(_ app: XCUIApplication, until target: XCUIElement) {
        let table = app.tables.firstMatch
        for _ in 0..<6 where !target.exists {
            table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                .press(forDuration: 0.05, thenDragTo: table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            usleep(700_000)
        }
    }

    private func expectOnChecklist(_ app: XCUIApplication, unit code: String, name: String? = nil, timeout: TimeInterval = 30) {
        let row = textElement(app, "\(name ?? code)    ||    \(code)")
        if row.waitForExistence(timeout: timeout / 2) { return }
        // The Equipment ID header may be scrolled off-screen — scroll to top.
        scrollChecklistToTop(app, until: row)
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
    private func openEquipmentPicker(_ app: XCUIApplication, currentCode: String, currentName: String? = nil) {
        let unitRow = textElement(app, "\(currentName ?? currentCode)    ||    \(currentCode)")
        // The Equipment ID header is the first row: after answering / typing hours further
        // down, a shorter screen has scrolled (and recycled) it — come back to the top.
        if !unitRow.exists { shootToDisk("picker-row-missing-before-\(currentCode)") }
        scrollChecklistToTop(app, until: unitRow)
        if !unitRow.exists { shootToDisk("picker-row-missing-after-\(currentCode)"); dump(app, "picker-row-missing-\(currentCode)") }
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

        let unitText = "\(currentName ?? currentCode)    ||    \(currentCode)"
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
    private func substitute(_ app: XCUIApplication, from currentCode: String, currentName: String? = nil, to replacementCode: String,
                            replacementName: String, expectConfirmation: Bool, reason: String? = nil) {
        openEquipmentPicker(app, currentCode: currentCode, currentName: currentName)

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

        // Reason (2026-09-13): Laravel requires one unless the replacement is a
        // DIRECT match, so the checklist asks — canonical picklist + Other. A
        // caller that passes `reason` expects the sheet; one that passes nil
        // gets the first standard reason if it appears anyway (fixture units
        // may lack an assigned product), so older scenarios keep running.
        let reasonSheet = app.sheets.firstMatch
        if let reason = reason {
            XCTAssertTrue(reasonSheet.waitForExistence(timeout: 10), "expected the 'Why this unit?' reason sheet")
            let choice = app.sheets.buttons[reason].firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 5), "reason '\(reason)' not offered")
            choice.tap()
        } else if reasonSheet.waitForExistence(timeout: 3) {
            app.sheets.buttons["Better-suited unit available"].firstMatch.tap()
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

    // ── Queue Line filter helpers ─────────────────────────────────────────────

    private func element(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tapId(_ app: XCUIApplication, _ id: String) {
        let el = element(app, id: id)
        XCTAssertTrue(el.waitForExistence(timeout: 10), "no element '\(id)'")
        el.tap()
        usleep(400_000)
    }

    /// Opens the Queue Line filter sheet from the header's filter icon.
    private func openFilterSheet(_ app: XCUIApplication) {
        let icon = app.buttons["icon Filter"].firstMatch
        if icon.waitForExistence(timeout: 8) {
            icon.tap()
        } else if let btn = app.buttons.allElementsBoundByIndex.first(where: { $0.frame.minY < 110 && $0.frame.maxX > app.frame.width - 70 }) {
            btn.tap()
        } else {
            XCTFail("no filter icon in the Queue Line header")
        }
        XCTAssertTrue(element(app, id: "queueLineFilter.apply").waitForExistence(timeout: 10), "filter sheet did not open")
        usleep(800_000)                       // let the store list settle
    }

    private func storeLine(_ app: XCUIApplication) -> XCUIElement { app.staticTexts.matching(identifier: "queueLineFilter.storeLine").firstMatch }
    private func typeLine(_ app: XCUIApplication) -> XCUIElement { app.staticTexts.matching(identifier: "queueLineFilter.typeLine").firstMatch }

    private func expectFilterLine(_ app: XCUIApplication, store: String, type: String, timeout: TimeInterval = 15) {
        let want = NSPredicate(format: "label == %@", "Delivery Store: \(store)")
        let ok = XCTNSPredicateExpectation(predicate: want, object: storeLine(app))
        XCTWaiter().wait(for: [ok], timeout: timeout)
        XCTAssertEqual(storeLine(app).label, "Delivery Store: \(store)")
        XCTAssertEqual(typeLine(app).label, "Type: \(type)")
    }

    private func expectCards(_ app: XCUIApplication, present: [String], absent: [String]) {
        for n in present { XCTAssertTrue(textElement(app, n).waitForExistence(timeout: 15), "card \(n) should be visible") }
        usleep(500_000)
        for n in absent { XCTAssertFalse(textElement(app, n).exists, "card \(n) should be hidden by the filter") }
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
        backToBoard(app)                          // checklist → Assembly Review → board
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
        dump(app, "B-before-substitute")

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
    /// Store unique ids of the two stores the filter scenarios scope to — the staging clone's by
    /// default; a run against another backend (production smoke) passes its own via
    /// TEST_RUNNER_KABBA_STORE_BON_AQUA / TEST_RUNNER_KABBA_STORE_WAVERLY.
    private var bonAquaStoreId: String { ProcessInfo.processInfo.environment["KABBA_STORE_BON_AQUA"] ?? "STO-VBHK-QDZY" }
    private var waverlyStoreId: String { ProcessInfo.processInfo.environment["KABBA_STORE_WAVERLY"] ?? "STO-WAMV-UTA2" }
    private var hLine1: String { ProcessInfo.processInfo.environment["KABBA_H_LINE1"] ?? "EXC-H1" }
    private var hLine2: String { ProcessInfo.processInfo.environment["KABBA_H_LINE2"] ?? "EXC-X" }
    private var hSub: String   { ProcessInfo.processInfo.environment["KABBA_H_SUB"] ?? "EXC-C" }

    /// Stage BOTH lines of order 1650 in one visit (both sections filled).
    func testH1_stageBothLines() {
        let app = login(makeApp())
        openQueueLine(app)
        openCard(app, anchor: "#\(hLine1)")
        expectOnChecklist(app, unit: hLine1)

        // Focused Save (2026-09-14): entering from the review for line 1 stages line 1 only.
        fillChecklist(app, hourFields: 2, expectSelects: 6)   // both sections
        saveExpectStaged(app, expectVideoRouting: true)
        backToBoard(app)
        expectCard(app, tab: "Staged", anchor: "#\(hLine1)")
        expectNoCard(app, tab: "Staged", anchor: "#\(hLine2)")
        // Line 2 stages from its own Continue (it is still on the Pending tab). Its section is
        // topped up first: the first visit's Save was line 1's, and only line 1 had to be complete.
        selectTab(app, "Pending")
        openCard(app, anchor: "#\(hLine2)")
        expectOnChecklist(app, unit: hLine2)
        fillChecklist(app, hourFields: 2, expectSelects: 6)
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

    // ── Queue Line board presentation (mobile UI cleanup, 2026-09-13) ─────────
    //
    // ONE solid Update button per Pending/Staged card (no checklist icon, no
    // three-dot menu), no "Checklist Prepared" badge; a rapid double tap opens
    // the Delivery Checklist exactly once (one Back lands on the board and the
    // button is solid + enabled again); the three tabs still switch. XCUI cannot
    // read image names, so the truck/store icon rule is asserted by
    // QueueLinePresentationTests (hosted) and SHOWN by the PNGs this test saves
    // to $KABBA_SHOT_DIR.
    func testQueueLineBoardPresentation() {
        let app = makeApp()
        login(app)
        openQueueLine(app)
        XCTAssertTrue(app.buttons["Pending"].firstMatch.waitForExistence(timeout: 20), "no Pending tab")

        let updates = app.buttons.matching(identifier: "queueLineUpdate")
        XCTAssertTrue(updates.firstMatch.waitForExistence(timeout: 30), "no Update button on a Pending card")
        usleep(1_500_000)                         // let the feed refresh settle before the shot
        shootToDisk("board-pending")

        // Retired controls and badge are gone.
        XCTAssertFalse(textElement(app, "Checklist Prepared").exists, "'Checklist Prepared' badge still shown")
        XCTAssertEqual(app.buttons.matching(identifier: "checklist").count, 0, "checklist icon still shown")
        XCTAssertEqual(app.buttons.matching(identifier: "ellipsis").count, 0, "three-dot menu still shown")
        XCTAssertEqual(updates.firstMatch.label, "Update")
        XCTAssertTrue(updates.firstMatch.isEnabled)

        // Rapid double tap → exactly ONE Assembly Review (since 2026-09-14 every card opens
        // the review first; the checklist follows from its Continue). The shot right after
        // the gesture catches the acknowledged (hollow, disabled) button before the push lands.
        updates.firstMatch.doubleTap()
        shootToDisk("update-tapped")
        let reviewTitle = element(app, id: "assemblyReview.order")
        XCTAssertTrue(reviewTitle.waitForExistence(timeout: 30), "Update did not open the Assembly Review")
        usleep(1_500_000)
        shootToDisk("review-opened")

        // ONE Back → the board (a duplicate push would need two).
        goBack(app)
        XCTAssertTrue(app.buttons["Staged"].firstMatch.waitForExistence(timeout: 15),
                      "one Back did not return to the Queue Line board — was the review pushed twice?")
        XCTAssertFalse(reviewTitle.exists, "an Assembly Review is still on screen after Back")
        XCTAssertTrue(updates.firstMatch.waitForExistence(timeout: 15), "Update button not restored after Back")
        XCTAssertTrue(updates.firstMatch.isEnabled, "Update button still disabled after Back")
        shootToDisk("board-after-back")

        // Tabs still work.
        selectTab(app, "Staged");    shootToDisk("board-staged")
        selectTab(app, "Completed"); shootToDisk("board-completed")
        selectTab(app, "Pending")
        XCTAssertTrue(updates.firstMatch.waitForExistence(timeout: 15), "Pending tab lost its Update button")
    }

    // ── Queue Line filters: Delivery Store (sticky) AND Type ─────────────────
    //
    // Staging board: 9202 Bon Aqua · In Store, 9203 Bon Aqua · Truck, 9204
    // Waverly · Truck (all Pending) and 9201 Bon Aqua · Truck (Staged).
    func testQueueLineFilters() {
        let app = makeApp()
        login(app)
        openQueueLine(app)
        XCTAssertTrue(storeLine(app).waitForExistence(timeout: 30), "no active-filter line under the header")

        // Clean slate: Reset + Apply → All / All (All is itself remembered).
        openFilterSheet(app)
        tapId(app, "queueLineFilter.reset")
        tapId(app, "queueLineFilter.apply")
        expectFilterLine(app, store: "All", type: "All")
        expectCards(app, present: ["9202", "9203", "9204"], absent: [])
        shootToDisk("filters-all")

        // Bon Aqua + Truck → only the Bon Aqua truck delivery.
        openFilterSheet(app)
        tapId(app, "queueLineFilter.store.\(bonAquaStoreId)")
        tapId(app, "queueLineFilter.type.truck")
        shootToDisk("filters-sheet")
        tapId(app, "queueLineFilter.apply")
        expectFilterLine(app, store: "Bon Aqua", type: "Truck")
        expectCards(app, present: ["9203"], absent: ["9202", "9204"])
        shootToDisk("filters-bonaqua-truck")

        // A tab change keeps the scope: Staged shows the Bon Aqua truck that is staged.
        selectTab(app, "Staged")
        expectFilterLine(app, store: "Bon Aqua", type: "Truck")
        expectCards(app, present: ["9201"], absent: ["9202", "9204"])
        selectTab(app, "Pending")
        expectCards(app, present: ["9203"], absent: ["9202"])

        // Bon Aqua + In Store → only the customer pickup.
        openFilterSheet(app)
        tapId(app, "queueLineFilter.type.store")
        tapId(app, "queueLineFilter.apply")
        expectFilterLine(app, store: "Bon Aqua", type: "In Store")
        expectCards(app, present: ["9202"], absent: ["9203", "9204"])
        shootToDisk("filters-bonaqua-instore")

        // Waverly + Truck → only the Waverly truck delivery (a dynamically listed store).
        openFilterSheet(app)
        tapId(app, "queueLineFilter.store.\(waverlyStoreId)")
        tapId(app, "queueLineFilter.type.truck")
        tapId(app, "queueLineFilter.apply")
        expectFilterLine(app, store: "Waverly", type: "Truck")
        expectCards(app, present: ["9204"], absent: ["9202", "9203"])
        shootToDisk("filters-waverly-truck")

        // Waverly + In Store → nothing, and the empty state says why.
        openFilterSheet(app)
        tapId(app, "queueLineFilter.type.store")
        tapId(app, "queueLineFilter.apply")
        expectFilterLine(app, store: "Waverly", type: "In Store")
        XCTAssertTrue(textElement(app, "Nothing pending for Waverly · In Store").waitForExistence(timeout: 15), "empty scope should be explained")
        shootToDisk("filters-empty-scope")

        // Leave and come back: the Store is remembered, the Type is not.
        goBack(app)
        openQueueLine(app)
        expectFilterLine(app, store: "Waverly", type: "All")
        expectCards(app, present: ["9204"], absent: ["9202", "9203"])
        shootToDisk("filters-remembered-after-reopen")

        // Relaunch the app: still Waverly, Type back to All.
        app.terminate()
        login(app)
        openQueueLine(app)
        expectFilterLine(app, store: "Waverly", type: "All", timeout: 30)
        expectCards(app, present: ["9204"], absent: ["9202", "9203"])
        shootToDisk("filters-remembered-after-relaunch")

        // Reset → All, and All survives leaving the board too.
        openFilterSheet(app)
        tapId(app, "queueLineFilter.reset")
        tapId(app, "queueLineFilter.apply")
        expectFilterLine(app, store: "All", type: "All")
        goBack(app)
        openQueueLine(app)
        expectFilterLine(app, store: "All", type: "All")
        expectCards(app, present: ["9202", "9203", "9204"], absent: [])
    }

    /// A remembered store that no longer exists (or is inactive) falls back to All
    /// once the live store list is known. The launch argument plays the stale memory.
    func testARememberedStoreThatNoLongerExistsFallsBackToAll() {
        let app = makeApp()
        app.launchArguments += ["-queue_line_store_filter", "STO-GONE-0000", "-queue_line_store_filter_name", "Closed Store"]
        login(app)
        openQueueLine(app)
        XCTAssertTrue(storeLine(app).waitForExistence(timeout: 30))
        expectFilterLine(app, store: "All", type: "All", timeout: 30)
        expectCards(app, present: ["9202", "9203", "9204"], absent: [])
        shootToDisk("filters-stale-store-fallback")
    }
    // ── Reason for a non-direct substitution ─────────────────────────────────
    //
    // 9202's unit QL-S1 and the spare QL-X1 have no assigned product, which
    // Laravel classifies as non-direct: the switch needs a reason. The checklist
    // asks with the canonical picklist, sends it through the Sync Engine, and
    // the board then shows the replacement.
    func testASubstitutionAsksForAReasonWhenTheUnitIsNotADirectMatch() {
        let app = makeApp()
        login(app)
        openQueueLine(app)
        // Scope to Bon Aqua · In Store so 9202 is the first card.
        openFilterSheet(app)
        tapId(app, "queueLineFilter.store.\(bonAquaStoreId)")
        tapId(app, "queueLineFilter.type.store")
        tapId(app, "queueLineFilter.apply")
        expectCards(app, present: ["9202"], absent: ["9203"])

        openCard(app, anchor: "9202")
        expectOnChecklist(app, unit: "QL-S1", name: "QL Store Mini Excavator Unit")

        substitute(app, from: "QL-S1", currentName: "QL Store Mini Excavator Unit",
                   to: "QL-X1", replacementName: "QL Spare Mini Excavator Unit",
                   expectConfirmation: false, reason: "Customer request")
        shootToDisk("reason-after-substitution")
        expectOnChecklist(app, unit: "QL-X1", name: "QL Spare Mini Excavator Unit")

        backToBoard(app)
        XCTAssertTrue(textElement(app, "#QL-X1").waitForExistence(timeout: 30), "board should show the replacement unit")
        shootToDisk("reason-board-after")

        // Leave the board as it was found.
        openFilterSheet(app)
        tapId(app, "queueLineFilter.reset")
        tapId(app, "queueLineFilter.apply")
    }

    // ── Assembly Review (Slices D + E, 2026-09-13) ────────────────────────────
    //
    // Staging seed (scratchpad/seed_assembly.php), dependencies PERSISTED as checkout
    // writes them: 9301 Skid Steer (Toothed Bucket + prepaid fuel/waiver) + RELATED
    // Brush Cutter → one dependent assembly, plus an unrelated Boom Lift; 9302 Mini
    // Excavator with "No Bucket"; 9303 Skid Steer (Smooth Bucket) + RELATED Harley Rake
    // with NO unit; 9304 BUNDLE Mini Skid (MASTER, 3 options) + Trencher (CHILD), long
    // customer name. Line unique ids arrive as TEST_RUNNER_KABBA_QLA_* env.

    private func qla(_ key: String) -> String { ProcessInfo.processInfo.environment["KABBA_QLA_\(key)"] ?? "" }
    private var qlaSkid: String { qla("SKID") }
    private var qlaCutter: String { qla("CUTTER") }
    private var qlaBoom: String { qla("BOOM") }
    private var qlaExc: String { qla("EXC") }
    private var qlaRake: String { qla("RAKE") }
    private var qlaSkid2: String { qla("SKID2") }
    private var qlaMS: String { qla("MS") }
    private var qlaTR: String { qla("TR") }
    private var qlaPC: String { qla("PC") }

    private func reviewIsOpen(_ app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        element(app, id: "assemblyReview.order").waitForExistence(timeout: timeout)
    }

    /// Scrolls the Assembly Review until the element exists (or gives up).
    @discardableResult
    private func reveal(_ app: XCUIApplication, _ el: XCUIElement, tag: String) -> Bool {
        for _ in 0..<8 {
            if el.exists && el.isHittable { return true }
            app.swipeUp()
            usleep(500_000)
        }
        for _ in 0..<8 where !(el.exists && el.isHittable) {
            app.swipeDown()
            usleep(500_000)
        }
        if !el.exists { dump(app, "reveal-\(tag)") }
        return el.exists
    }

    private func tapReview(_ app: XCUIApplication, _ id: String) {
        let el = element(app, id: id)
        XCTAssertTrue(reveal(app, el, tag: id), "no element '\(id)' on the Assembly Review")
        el.tap()
        usleep(700_000)
    }

    private func reviewLabel(_ app: XCUIApplication, _ id: String) -> String {
        let el = element(app, id: id)
        _ = reveal(app, el, tag: id)
        return el.label
    }

    private func reviewValue(_ app: XCUIApplication, _ id: String) -> String {
        let el = element(app, id: id)
        _ = reveal(app, el, tag: id)
        return (el.value as? String) ?? ""
    }

    /// Pops screens until the Assembly Review is visible.
    private func backToReview(_ app: XCUIApplication) {
        for _ in 0..<5 {
            if element(app, id: "assemblyReview.order").exists { return }
            goBack(app)
        }
        XCTAssertTrue(reviewIsOpen(app, timeout: 10), "never returned to the Assembly Review")
    }

    private func progressLine(_ app: XCUIApplication) -> String {
        let q = NSPredicate(format: "identifier BEGINSWITH 'assemblyReview.group.' AND identifier ENDSWITH '.progress'")
        return app.staticTexts.matching(q).firstMatch.label
    }

    private func groupStage(_ app: XCUIApplication) -> String {
        let q = NSPredicate(format: "identifier BEGINSWITH 'assemblyReview.group.' AND identifier ENDSWITH '.stage'")
        return app.staticTexts.matching(q).firstMatch.label
    }

    /// The derived STOP / GO badge of the (single) visible entity, e.g. "STOP · 1 of 3 confirmed".
    private func gateLabel(_ app: XCUIApplication) -> String {
        let q = NSPredicate(format: "identifier BEGINSWITH 'assemblyReview.group.' AND identifier ENDSWITH '.gate'")
        let el = app.descendants(matching: .any).matching(q).firstMatch
        for _ in 0..<6 where !el.exists { app.swipeDown(); usleep(300_000) }
        return el.label
    }

    private func confirm(_ app: XCUIApplication, _ subjectId: String) {
        XCTAssertEqual(reviewValue(app, "\(subjectId).available"), "not confirmed", "\(subjectId) should start unconfirmed")
        tapReview(app, "\(subjectId).available")
        XCTAssertEqual(reviewValue(app, "\(subjectId).available"), "confirmed", "\(subjectId) shows confirmed the moment it is tapped")
    }

    private func continueIsBlocked(_ app: XCUIApplication, _ uid: String) -> Bool {
        let el = element(app, id: "assembly.\(uid).continue")
        _ = reveal(app, el, tag: "continue-\(uid)")
        return !el.isEnabled && (el.value as? String) == "blocked"
    }

    // MARK: 1 · A dependent assembly is STOP until every requirement is confirmed, then GO

    func testDependentAssemblyIsStopUntilEveryRequirementIsConfirmedThenGo() {
        XCTAssertFalse(qlaSkid.isEmpty, "set KABBA_QLA_SKID")
        let app = makeApp()
        login(app)
        openQueueLine(app)

        // Board: the Skid Steer + related Brush Cutter are ONE card; the unrelated Boom Lift
        // on the same order is its own card; Product Options stay off the board.
        XCTAssertTrue(textElement(app, "2 items · 0 of 2 staged").waitForExistence(timeout: 30), "the 9301 dependent assembly card should say 2 items · 0 of 2 staged")
        XCTAssertTrue(textElement(app, "with Brush Cutter").exists, "the dependent member is named on the one card")
        XCTAssertTrue(textElement(app, "QLA-BL1").exists, "the unrelated Boom Lift has its own card")
        XCTAssertFalse(textElement(app, "with Boom Lift").exists, "same order id alone never groups")
        XCTAssertFalse(textElement(app, "Toothed Bucket").exists, "Product Options belong on Assembly Review, not the board card")
        shootToDisk("d-board-entities")

        tapUpdate(app, anchor: "QLA-SK1")
        XCTAssertTrue(reviewIsOpen(app), "Update did not open the Assembly Review")
        XCTAssertEqual(element(app, id: "assemblyReview.order").label, "Order #9301")
        usleep(2_500_000)                                   // server read replaces the cache

        // Only the tapped entity; the quiet header; every frozen option by its stored label.
        XCTAssertFalse(textElement(app, "Queue Assembly Customer").exists, "no repeated customer header")
        XCTAssertFalse(textElement(app, "Everything ordered has to be physically present before the assembly can be staged. Confirm each item, then open its checklist.").exists)
        for text in ["Skid Steer", "Toothed Bucket", "Brush Cutter", "Goes with Skid Steer", "No Product Options on this line"] {
            XCTAssertTrue(reveal(app, textElement(app, text), tag: text), "Assembly Review must show '\(text)'")
        }
        XCTAssertFalse(element(app, id: "assembly.\(qlaBoom)").exists, "the independent Boom Lift is not part of this assembly")
        for text in ["Prepaid", "Damage Waiver", "Thrown Track", "Fuel level", "Unit status", "Item availability", "Checklist:", "Cannot be staged", "Not Available", "Unbundle"] {
            XCTAssertFalse(textElement(app, text).exists, "'\(text)' must not appear")
        }
        XCTAssertEqual(gateLabel(app), "STOP · 0 of 3 confirmed")
        XCTAssertTrue(continueIsBlocked(app, qlaSkid), "STOP: the Skid Steer checklist may not open")
        XCTAssertTrue(continueIsBlocked(app, qlaCutter), "STOP: the Brush Cutter checklist may not open either")
        shootToDisk("d-review-stop")

        // Partial: the Skid Steer and its bucket confirmed — the dependent cutter still holds STOP.
        confirm(app, "assembly.\(qlaSkid).unit")
        XCTAssertEqual(gateLabel(app), "STOP · 1 of 3 confirmed")
        confirm(app, "assembly.\(qlaSkid).option.POPT-ITM-ST-TOOTH")
        XCTAssertEqual(gateLabel(app), "STOP · 2 of 3 confirmed")
        XCTAssertTrue(continueIsBlocked(app, qlaSkid), "a dependent member left unconfirmed blocks the whole assembly")
        shootToDisk("d-review-partial")

        // GO: the cutter's unit confirmed — every checklist in the assembly may open.
        confirm(app, "assembly.\(qlaCutter).unit")
        XCTAssertEqual(gateLabel(app), "GO · All 3 confirmed")
        XCTAssertFalse(continueIsBlocked(app, qlaSkid))
        XCTAssertEqual(reviewValue(app, "assembly.\(qlaSkid).continue"), "enabled")
        XCTAssertEqual(reviewValue(app, "assembly.\(qlaCutter).continue"), "enabled")
        shootToDisk("d-review-go")

        // Continue → the checklist; Back → the review (refreshed), still GO.
        continueFromReview(app, memberUid: qlaSkid)
        expectOnChecklist(app, unit: "QLA-SK1", name: "Skid Steer Unit")
        shootToDisk("d-checklist-enabled")
        backToReview(app)
        usleep(2_500_000)
        XCTAssertEqual(gateLabel(app), "GO · All 3 confirmed", "the server agrees after the round trip")
        XCTAssertEqual(element(app, id: "assemblyReview.order").label, "Order #9301")
        shootToDisk("d-review-return")

        // ONE Back → the board.
        goBack(app)
        XCTAssertTrue(app.buttons["Staged"].firstMatch.waitForExistence(timeout: 15), "one Back did not return to the board")
    }

    // MARK: 2 · An independent line on the same order proceeds on its own; a focused Save stages only it

    func testIndependentLineProceedsAndItsFocusedSaveStagesOnlyItself() {
        XCTAssertFalse(qlaBoom.isEmpty, "set KABBA_QLA_BOOM")
        let app = makeApp()
        login(app)
        openQueueLine(app)

        tapUpdate(app, anchor: "QLA-BL1")
        XCTAssertTrue(reviewIsOpen(app))
        usleep(2_500_000)
        XCTAssertTrue(element(app, id: "assembly.\(qlaBoom)").waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, id: "assembly.\(qlaSkid)").exists, "the Skid Steer assembly is a different entity")
        XCTAssertEqual(gateLabel(app), "STOP · 0 of 1 confirmed")
        confirm(app, "assembly.\(qlaBoom).unit")
        XCTAssertEqual(gateLabel(app), "GO · Confirmed", "GO on its own — whatever state the Skid Steer assembly is in")
        shootToDisk("d-review-independent-go")

        // The checklist screen still lists every line of the order. Fill ALL of them and Save
        // from the Boom Lift's focused entry: only the Boom Lift may stage.
        continueFromReview(app, memberUid: qlaBoom)
        expectOnChecklist(app, unit: "QLA-BL1", name: "Boom Lift Unit")
        fillChecklist(app, hourFields: 3, expectSelects: 9)
        saveExpectStaged(app, expectVideoRouting: true)
        backToReview(app)
        usleep(2_500_000)
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaBoom).stage"), "Staged")

        backToBoard(app)
        sleep(3)
        expectCard(app, tab: "Staged", anchor: "QLA-BL1")
        expectNoCard(app, tab: "Staged", anchor: "QLA-SK1")
        expectNoCard(app, tab: "Staged", anchor: "QLA-BC1")
        expectCard(app, tab: "Pending", anchor: "0 of 2 staged")   // the dependent assembly: nothing staged by the Boom Lift's Save
        shootToDisk("d-board-focused-save")
    }

    // MARK: 3 · No Bucket, and an unassigned dependent member

    func testNoBucketIsConfirmedLikeAnyOptionAndAnUnassignedDependentMemberHoldsStop() {
        XCTAssertFalse(qlaExc.isEmpty, "set KABBA_QLA_EXC")
        let app = makeApp()
        login(app)
        openQueueLine(app)

        tapUpdate(app, anchor: "QLA-EX1")
        XCTAssertTrue(reviewIsOpen(app), "a single-line order still goes through Assembly Review")
        XCTAssertEqual(element(app, id: "assemblyReview.order").label, "Order #9302")
        usleep(2_000_000)
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaExc).option.POPT-ITM-EX-NOBKT.title"), "No Bucket", "No Bucket is shown explicitly")
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaExc).option.POPT-ITM-EX-NOBKT.state"), "Not yet confirmed")
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaExc).option.POPT-ITM-EX-NOBKT.icon"), "Not confirmed")
        XCTAssertFalse(textElement(app, "Prepaid Cleaning").exists)
        XCTAssertFalse(textElement(app, "Unbundle").exists)
        XCTAssertEqual(gateLabel(app), "STOP · 0 of 2 confirmed")
        confirm(app, "assembly.\(qlaExc).unit")
        confirm(app, "assembly.\(qlaExc).option.POPT-ITM-EX-NOBKT")
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaExc).option.POPT-ITM-EX-NOBKT.icon"), "Confirmed")
        XCTAssertEqual(gateLabel(app), "GO · All 2 confirmed", "No Bucket counts like any other requirement")
        XCTAssertEqual(reviewValue(app, "assembly.\(qlaExc).continue"), "enabled")
        shootToDisk("d-review-no-bucket")

        // 9303: the related Harley Rake has no unit — nothing to confirm, and the assembly cannot be GO.
        goBack(app)
        tapUpdate(app, anchor: "QLA-SK2")
        XCTAssertTrue(reviewIsOpen(app))
        XCTAssertEqual(element(app, id: "assemblyReview.order").label, "Order #9303")
        usleep(2_000_000)
        XCTAssertTrue(reveal(app, textElement(app, "Harley Rake"), tag: "rake"))
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaRake).unit.title"), "No equipment selected")
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaRake).unit.state"), "Assign a machine first")
        XCTAssertFalse(element(app, id: "assembly.\(qlaRake).unit.available").exists, "no Available control for a machine that does not exist")
        XCTAssertTrue(element(app, id: "assembly.\(qlaRake).unit.assign").isEnabled, "the ONE action is Assign")
        confirm(app, "assembly.\(qlaSkid2).unit")
        confirm(app, "assembly.\(qlaSkid2).option.POPT-ITM-ST-SMOOTH")
        XCTAssertEqual(gateLabel(app), "STOP · 2 of 3 confirmed", "the unassigned dependent member holds the assembly at STOP")
        XCTAssertTrue(continueIsBlocked(app, qlaSkid2), "the fully confirmed Skid Steer still may not open its checklist")
        shootToDisk("d-review-unassigned-stop")
    }

    // MARK: 4 · Bundle: focused Save stages one member; a reversal unstages it; confirming never restages

    func testBundleFocusedSaveThenReversalUnstagesAndConfirmingNeverRestages() {
        XCTAssertFalse(qlaMS.isEmpty, "set KABBA_QLA_MS")
        let app = makeApp()
        login(app)
        openQueueLine(app)
        if !textElement(app, "QLA-MS1").waitForExistence(timeout: 20) { selectTab(app, "Pending") }
        XCTAssertTrue(textElement(app, "with Mini Skid - Trencher").waitForExistence(timeout: 20), "the bundle MASTER + CHILD are one card")

        tapUpdate(app, anchor: "QLA-MS1")
        XCTAssertTrue(reviewIsOpen(app))
        XCTAssertEqual(element(app, id: "assemblyReview.order").label, "Order #9304")
        usleep(2_500_000)
        XCTAssertTrue(reveal(app, textElement(app, "Goes with Mini Skid Steer"), tag: "bundle-child"))
        XCTAssertTrue(reveal(app, textElement(app, "XL Smooth Bucket - 48 inch"), tag: "long-option"))
        XCTAssertEqual(gateLabel(app), "STOP · 0 of 5 confirmed", "master unit + 3 options + child unit")
        confirmEverything(app)
        XCTAssertEqual(gateLabel(app), "GO · All 5 confirmed")
        shootToDisk("d-review-bundle-go")

        // Focused Save for the MASTER: the CHILD stays Pending even though its section is filled.
        continueFromReview(app, memberUid: qlaMS)
        expectOnChecklist(app, unit: "QLA-MS1", name: "Mini Skid Steer Unit")
        fillChecklist(app, hourFields: 2, expectSelects: 6)
        saveExpectStaged(app, expectVideoRouting: true)
        backToReview(app)
        usleep(2_500_000)
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaMS).stage"), "Staged")
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaTR).stage"), "Pending", "the bundle child was not staged by the master's Save")
        XCTAssertEqual(progressLine(app), "1 of 2 items staged")
        XCTAssertEqual(groupStage(app), "Pending")
        shootToDisk("d-review-partial-staged")

        // Reversal: the XL bucket turns out to be missing → the master returns to Pending (locally NOW, then server).
        tapReview(app, "assembly.\(qlaMS).option.POPT-ITM-MS-XL48.available")
        let reverse = app.alerts.buttons["Not Available"]
        XCTAssertTrue(reverse.waitForExistence(timeout: 8), "reversing a confirmation asks first")
        reverse.tap()
        usleep(1_000_000)
        XCTAssertEqual(reviewValue(app, "assembly.\(qlaMS).option.POPT-ITM-MS-XL48.available"), "not confirmed")
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaMS).stage"), "Pending")
        XCTAssertEqual(gateLabel(app), "STOP · 4 of 5 confirmed")
        XCTAssertEqual(progressLine(app), "0 of 2 items staged")
        shootToDisk("d-review-reversed")
        sleep(5)                                            // let the engine deliver it
        goBack(app)
        tapUpdate(app, anchor: "9304")                      // fresh server read
        XCTAssertTrue(reviewIsOpen(app))
        usleep(3_000_000)
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaMS).stage"), "Pending", "the server unstaged it too")
        XCTAssertTrue(reviewLabel(app, "assembly.\(qlaMS).option.POPT-ITM-MS-XL48.state").hasPrefix("Not Available"), "the reversal stands after the server round trip")

        // Confirmed again: still Pending — only the explicit Save restages.
        confirm(app, "assembly.\(qlaMS).option.POPT-ITM-MS-XL48")
        XCTAssertEqual(gateLabel(app), "GO · All 5 confirmed")
        sleep(4)
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaMS).stage"), "Pending", "confirming is a prerequisite, never a staging trigger")
        continueFromReview(app, memberUid: qlaMS)
        expectOnChecklist(app, unit: "QLA-MS1", name: "Mini Skid Steer Unit")
        fillChecklist(app, hourFields: 2, expectSelects: 6)   // server-prefilled: usually a no-op
        saveExpectStaged(app, expectVideoRouting: true)
        backToReview(app)
        usleep(2_500_000)
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaMS).stage"), "Staged")
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaTR).stage"), "Pending")
        shootToDisk("d-review-restaged")
    }

    // ── Universal Assembly Review sequencing (2026-09-14) ─────────────────────
    //
    // Every road into the outbound checklist passes through Assembly Review first
    // — not only the Queue Line card. Order Details and the Orders list are the
    // other two launch sites in the app (Schedule, Dispatch's driver flow and the
    // notification deep link all arrive at Order Details). The seed's 9305 is the
    // simplest order there is: one Plate Compactor, no options.

    private func openOrders(_ app: XCUIApplication) {
        let entry = textElement(app, "Orders")
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "Home screen offered no Orders entry")
        entry.tap()
        usleep(2_500_000)
    }

    /// Scrolls the Orders list until the row whose order number is `number` is visible.
    private func revealOrderRow(_ app: XCUIApplication, _ number: String) -> XCUIElement {
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", number)).firstMatch
        for _ in 0..<8 where !(row.exists && row.isHittable) {
            app.swipeUp()
            usleep(600_000)
        }
        if !row.exists { dump(app, "no-order-row-\(number)") }
        XCTAssertTrue(row.exists, "no Orders row for order \(number)")
        return row
    }

    private func onOrderDetails(_ app: XCUIApplication, _ number: String, timeout: TimeInterval = 20) -> Bool {
        element(app, id: "orderDetails.checklist.delivery").waitForExistence(timeout: timeout)
            && app.staticTexts.matching(NSPredicate(format: "label == %@", number)).firstMatch.exists
    }

    // MARK: 5 · Order Details → Assembly Review → Checklist → Assembly Review → Order Details (single item, no options)

    func testOrderDetailsEntersTheDeliveryChecklistThroughAssemblyReviewAndReturnsToOrderDetails() {
        XCTAssertFalse(qlaPC.isEmpty, "set KABBA_QLA_PC")
        let app = makeApp()
        login(app)
        openOrders(app)
        revealOrderRow(app, "9305").tap()
        XCTAssertTrue(onOrderDetails(app, "9305"), "the Orders row did not open Order Details for 9305")
        shootToDisk("u-order-details")

        // The Delivery checklist tile opens the Assembly Review — even for the simplest order.
        tapId(app, "orderDetails.checklist.delivery")
        XCTAssertTrue(reviewIsOpen(app), "Order Details must enter the checklist through Assembly Review")
        XCTAssertEqual(element(app, id: "assemblyReview.order").label, "Order #9305")
        usleep(2_500_000)
        XCTAssertTrue(element(app, id: "assembly.\(qlaPC)").waitForExistence(timeout: 10))
        XCTAssertTrue(reveal(app, textElement(app, "Plate Compactor"), tag: "compactor"))
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaPC).options.none"), "No Product Options on this line")
        XCTAssertFalse(textElement(app, "Goes with").exists, "a single line depends on nothing")
        XCTAssertEqual(gateLabel(app), "STOP · 0 of 1 confirmed", "unconfirmed means STOP, options or not")
        XCTAssertTrue(continueIsBlocked(app, qlaPC))
        shootToDisk("u-simple-review-stop")

        // A double tap on the origin's tile could not have stacked a second review:
        // ONE Back from here must land on Order Details. Proven at the end.
        confirm(app, "assembly.\(qlaPC).unit")
        XCTAssertEqual(gateLabel(app), "GO · Confirmed")
        XCTAssertEqual(reviewValue(app, "assembly.\(qlaPC).continue"), "enabled")
        shootToDisk("u-simple-review-go")

        // Continue → the same Delivery Checklist, focused on this member.
        continueFromReview(app, memberUid: qlaPC)
        expectOnChecklist(app, unit: "QLA-PC1", name: "Plate Compactor Unit")
        shootToDisk("u-order-details-checklist")
        fillChecklist(app, hourFields: 1, expectSelects: 3)
        saveExpectStaged(app, expectVideoRouting: true)

        // Save → (video routing) → Back → the Assembly Review FIRST, refreshed: Staged.
        backToReview(app)
        usleep(2_500_000)
        XCTAssertEqual(element(app, id: "assemblyReview.order").label, "Order #9305")
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaPC).stage"), "Staged", "the explicit Save staged it; the review shows it on return")
        XCTAssertEqual(gateLabel(app), "GO · Confirmed")
        shootToDisk("u-review-after-checklist")

        // ONE Back → Order Details (the origin), never the Queue Line.
        goBack(app)
        XCTAssertTrue(onOrderDetails(app, "9305", timeout: 15), "Back from the Assembly Review must return to Order Details")
        XCTAssertFalse(element(app, id: "assemblyReview.order").exists)
        XCTAssertFalse(app.buttons["Staged"].firstMatch.exists, "Order Details origin is preserved — not the Queue Line board")
        shootToDisk("u-order-details-return")
    }

    // MARK: 6 · Orders list → Assembly Review (every entity of the order, separately) → back to the list

    func testTheOrdersListEntersThroughAssemblyReviewShowingEachEntityOfTheOrderAndReturnsToTheList() {
        XCTAssertFalse(qlaSkid.isEmpty && qlaBoom.isEmpty, "set KABBA_QLA_SKID / KABBA_QLA_BOOM")
        let app = makeApp()
        login(app)
        openOrders(app)

        // The row's own Delivery checklist tile opens the review. The order number sits at the
        // top of its cell and the tiles at the bottom, so the row's OWN tile is the first one
        // below the number — and it may still be below the fold: nudge the list until it is
        // hittable, re-reading frames after every nudge.
        var tapped = false
        for _ in 0..<8 {
            let row = revealOrderRow(app, "9301")
            let tiles = app.buttons.matching(identifier: "orderList.checklist.delivery").allElementsBoundByIndex
            XCTAssertFalse(tiles.isEmpty, "no Delivery checklist tiles on the Orders list")
            let below = tiles.filter { $0.frame.minY >= row.frame.minY }
            guard let tile = below.min(by: { $0.frame.minY < $1.frame.minY }), tile.isHittable else {
                let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
                usleep(700_000)
                continue
            }
            tile.tap()
            tapped = true
            break
        }
        XCTAssertTrue(tapped, "could not bring 9301's Delivery checklist tile on screen")
        XCTAssertTrue(reviewIsOpen(app), "the Orders list must enter the checklist through Assembly Review")
        XCTAssertEqual(element(app, id: "assemblyReview.order").label, "Order #9301")
        usleep(2_500_000)

        // Unfocused: every entity of the order, each its own group with its own gate —
        // the dependent Skid Steer + Brush Cutter, and the independent Boom Lift.
        XCTAssertTrue(reveal(app, element(app, id: "assembly.\(qlaSkid)"), tag: "skid"))
        XCTAssertTrue(reveal(app, element(app, id: "assembly.\(qlaCutter)"), tag: "cutter"))
        XCTAssertTrue(reveal(app, element(app, id: "assembly.\(qlaBoom)"), tag: "boom"))
        let groups = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'assemblyReview.group.' AND identifier ENDSWITH '.gate'"))
        XCTAssertEqual(groups.count, 2, "two entities on the order → two STOP / GO gates, never one order-wide gate")
        XCTAssertTrue(textElement(app, "Goes with Skid Steer").exists)
        XCTAssertFalse(textElement(app, "Goes with Boom Lift").exists, "same order id alone never groups")
        shootToDisk("u-order-list-review")

        // Back → the Orders list, not the Queue Line.
        goBack(app)
        XCTAssertTrue(revealOrderRow(app, "9301").waitForExistence(timeout: 15), "Back from the review must return to the Orders list")
        XCTAssertFalse(element(app, id: "assemblyReview.order").exists)
        shootToDisk("u-order-list-return")
    }

    // ── Assign / reassign from the review — the checklist's own canonical flow (2026-09-14) ─────
    //
    // Seed spares (unassigned, Available): QLA-HR1 (direct for the Harley Rake), QLA-SK3 (direct)
    // and QLA-ALT1 (non-direct, "Other Machine Spare") for 9303's Skid Steer, QLA-EX2 (direct)
    // for 9302's Mini Excavator.

    /// Picks `row` ("<name>    ||    <code>") on the review's equipment wheel and taps Select.
    /// The picker's "Search" pill → the search alert → a term → the wheel reloads with the
    /// server's matches for the whole eligible fleet (name / Equipment ID).
    private func searchOnPicker(_ app: XCUIApplication, _ term: String) {
        let search = element(app, id: "equipmentPicker.search")
        XCTAssertTrue(search.waitForExistence(timeout: 10), "the picker offers no search")
        search.tap()
        let field = element(app, id: "equipmentPicker.searchField")
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field")
        field.tap()
        field.typeText(term)
        app.alerts.buttons["Search"].firstMatch.tap()
        usleep(2_500_000)
    }

    /// The picker's Category pill → the category sheet → `title` → the wheel reloads with the
    /// server's list for that category (search term cleared).
    private func chooseCategory(_ app: XCUIApplication, _ title: String) {
        let pill = element(app, id: "equipmentPicker.category")
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "the picker offers no Category pill")
        pill.tap()
        let choice = app.sheets.buttons[title].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 10), "no category “\(title)” on the sheet")
        choice.tap()
        usleep(2_500_000)
    }

    /// What the Category pill names right now ("Category: <title>").
    private func categoryPill(_ app: XCUIApplication) -> String {
        let pill = element(app, id: "equipmentPicker.category")
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "the picker offers no Category pill")
        return pill.label
    }

    private func pickOnWheel(_ app: XCUIApplication, _ row: String) {
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 10), "the equipment picker did not open")
        // The checklist's own picker: its header pill reads "Select Equipment ID" (checklist host)
        // or offers "Search name or Equipment ID" + the Category pill (review host) — same component.
        XCTAssertTrue(element(app, id: "equipmentPicker.search").exists || element(app, id: "equipmentPicker.category").exists
                      || textElement(app, "Select Equipment ID").exists,
                      "it is the checklist's own Select Equipment ID picker")
        wheel.adjust(toPickerWheelValue: row)
        usleep(500_000)
        app.buttons["Select"].firstMatch.tap()
        usleep(1_500_000)
    }

    // MARK: 7 · Assign an unassigned member, then reassign an assigned one — each new unit starts unconfirmed

    func testUnassignedMemberIsAssignedFromTheReviewThenReassignedAndEachNewUnitStartsUnconfirmed() {
        XCTAssertFalse(qlaRake.isEmpty && qlaSkid2.isEmpty, "set KABBA_QLA_RAKE / KABBA_QLA_SKID2")
        let app = makeApp()
        login(app)
        openQueueLine(app)
        tapUpdate(app, anchor: "QLA-SK2")
        XCTAssertTrue(reviewIsOpen(app))
        XCTAssertEqual(element(app, id: "assemblyReview.order").label, "Order #9303")
        usleep(2_500_000)

        // Unassigned: no Available control, a clear Assign — and the assembly is STOP.
        XCTAssertTrue(reveal(app, element(app, id: "assembly.\(qlaRake).unit.assign"), tag: "assign"))
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaRake).unit.title"), "No equipment selected")
        XCTAssertFalse(element(app, id: "assembly.\(qlaRake).unit.available").exists)
        XCTAssertTrue(gateLabel(app).hasPrefix("STOP"))
        shootToDisk("a-review-unassigned-assign")

        // Assign → the checklist's own picker, opened in the ORDERED product's canonical category
        // (no unit yet) → a direct spare: no reason asked, no confirmation to discard.
        tapReview(app, "assembly.\(qlaRake).unit.assign")
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 10), "the equipment picker did not open")
        XCTAssertEqual(categoryPill(app), "Category: Landscaping", "an unassigned line starts in its ordered product's category")
        shootToDisk("a-picker-unassigned-default-category")
        pickOnWheel(app, "Harley Rake Spare    ||    QLA-HR1")
        XCTAssertFalse(app.sheets.firstMatch.exists, "a direct match never asks for a reason")
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaRake).unit.title"), "Harley Rake Spare · #QLA-HR1", "named the way the yard names it: name, then tag")
        XCTAssertEqual(reviewValue(app, "assembly.\(qlaRake).unit.available"), "not confirmed", "assignment is not availability")
        XCTAssertFalse(element(app, id: "assembly.\(qlaRake).unit.assign").exists)
        XCTAssertTrue(gateLabel(app).hasPrefix("STOP"), "assigned, not yet confirmed → still STOP")
        shootToDisk("a-review-assigned-unconfirmed")

        // Confirm everything → GO.
        confirm(app, "assembly.\(qlaRake).unit")
        if reviewValue(app, "assembly.\(qlaSkid2).unit.available") == "not confirmed" { confirm(app, "assembly.\(qlaSkid2).unit") }
        if reviewValue(app, "assembly.\(qlaSkid2).option.POPT-ITM-ST-SMOOTH.available") == "not confirmed" { confirm(app, "assembly.\(qlaSkid2).option.POPT-ITM-ST-SMOOTH") }
        XCTAssertEqual(gateLabel(app), "GO · All 3 confirmed")
        shootToDisk("a-review-assigned-go")

        // Reassign by tapping the identity → the picker opens in the CURRENT unit's canonical
        // category (Skid Steer), listed whole: the 30 filler units that pushed past the former
        // first page are all on the wheel, and a search stays within the category. The
        // NON-direct spare lives in another category (Landscaping): one category change away,
        // then the canonical reason sheet.
        tapReview(app, "assembly.\(qlaSkid2).unit.reassign")
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 10), "the equipment picker did not open")
        XCTAssertEqual(categoryPill(app), "Category: Skid Steer", "the current unit's category, resolved by the server")
        shootToDisk("a-picker-current-unit-category")
        XCTAssertFalse((wheel.value as? String ?? "").contains("QLA-ALT1"), "another category's unit is not in this list")
        wheel.adjust(toPickerWheelValue: "A Filler 30    ||    QLA-F30")          // beyond the former 25 — the category is listed whole
        XCTAssertTrue((wheel.value as? String ?? "").contains("QLA-F30"), "the whole category is on the wheel, no 25-row cut")
        searchOnPicker(app, "Spare")
        XCTAssertTrue((wheel.value as? String ?? "").contains("QLA-SK3"), "search within Skid Steer finds its spare")
        XCTAssertFalse((wheel.value as? String ?? "").contains("QLA-ALT1"), "…and never leaves the category")
        element(app, id: "equipmentPicker.category").tap()
        XCTAssertTrue(app.sheets.buttons["Landscaping"].firstMatch.waitForExistence(timeout: 10), "the category sheet did not open")
        shootToDisk("a-picker-category-sheet")
        app.sheets.buttons["Landscaping"].firstMatch.tap()
        usleep(2_500_000)
        XCTAssertEqual(categoryPill(app), "Category: Landscaping")
        shootToDisk("a-picker-other-category")
        pickOnWheel(app, "Other Machine Spare    ||    QLA-ALT1")
        let reason = app.sheets.buttons["Customer request"].firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 10), "a non-direct unit needs Laravel's reason — the same picklist as the checklist")
        reason.tap()
        usleep(1_500_000)
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaSkid2).unit.title"), "Other Machine Spare · #QLA-ALT1")
        XCTAssertEqual(reviewValue(app, "assembly.\(qlaSkid2).unit.available"), "not confirmed", "the old unit's Available never carries onto the replacement")
        XCTAssertEqual(reviewValue(app, "assembly.\(qlaSkid2).option.POPT-ITM-ST-SMOOTH.available"), "confirmed", "Product Option confirmations stand — the order still asks for the same bucket")
        XCTAssertEqual(gateLabel(app), "STOP · 2 of 3 confirmed")
        XCTAssertTrue(continueIsBlocked(app, qlaSkid2))
        shootToDisk("a-review-reassigned-stop")

        // Confirm the replacement → GO → its checklist opens on the replacement.
        sleep(4)                                            // let the switch reach Kabba first (FIFO)
        confirm(app, "assembly.\(qlaSkid2).unit")
        XCTAssertEqual(gateLabel(app), "GO · All 3 confirmed")
        continueFromReview(app, memberUid: qlaSkid2)
        expectOnChecklist(app, unit: "QLA-ALT1", name: "Other Machine Spare")
        shootToDisk("a-checklist-on-replacement")
        backToReview(app)
        usleep(3_000_000)                                   // server read replaces the cache
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaSkid2).unit.title"), "Other Machine Spare · #QLA-ALT1", "the server agrees: one canonical assignment")
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaRake).unit.title"), "Harley Rake Spare · #QLA-HR1")

        // The board reads the same assignment.
        backToBoard(app)
        expectCard(app, tab: "Pending", anchor: "QLA-ALT1")
        shootToDisk("a-board-reassigned")
    }

    // MARK: 8 · Reassigning INSIDE the focused checklist returns the review to STOP with the new unit

    func testVReassigningInsideTheChecklistReturnsTheReviewToStopWithTheNewUnit() {
        XCTAssertFalse(qlaExc.isEmpty, "set KABBA_QLA_EXC")
        let app = makeApp()
        login(app)
        openQueueLine(app)
        tapUpdate(app, anchor: "QLA-EX1")
        XCTAssertTrue(reviewIsOpen(app))
        XCTAssertEqual(element(app, id: "assemblyReview.order").label, "Order #9302")
        usleep(2_500_000)
        confirmEverything(app)
        XCTAssertEqual(gateLabel(app), "GO · All 2 confirmed")
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaExc).unit.title"), "Mini Excavator Unit · #QLA-EX1")

        // GO → the focused checklist → the checklist's own substitution (direct spare, nothing prepared to discard).
        continueFromReview(app, memberUid: qlaExc)
        expectOnChecklist(app, unit: "QLA-EX1", name: "Mini Excavator Unit")
        substitute(app, from: "QLA-EX1", currentName: "Mini Excavator Unit", to: "QLA-EX2",
                   replacementName: "Mini Excavator Spare", expectConfirmation: false)
        expectOnChecklist(app, unit: "QLA-EX2", name: "Mini Excavator Spare")
        shootToDisk("c-checklist-reassigned")

        // Back on the review: the new unit, unconfirmed; No Bucket still confirmed; STOP.
        backToReview(app)
        usleep(3_000_000)
        XCTAssertEqual(reviewLabel(app, "assembly.\(qlaExc).unit.title"), "Mini Excavator Spare · #QLA-EX2", "the review shows the unit the checklist switched to")
        XCTAssertEqual(reviewValue(app, "assembly.\(qlaExc).unit.available"), "not confirmed", "Equipment A's confirmation did not transfer to Equipment B")
        XCTAssertEqual(reviewValue(app, "assembly.\(qlaExc).option.POPT-ITM-EX-NOBKT.available"), "confirmed")
        XCTAssertEqual(gateLabel(app), "STOP · 1 of 2 confirmed")
        XCTAssertTrue(continueIsBlocked(app, qlaExc))
        shootToDisk("c-review-after-checklist-reassign")

        // Physically confirm the replacement → GO again.
        confirm(app, "assembly.\(qlaExc).unit")
        XCTAssertEqual(gateLabel(app), "GO · All 2 confirmed")
        shootToDisk("c-review-replacement-confirmed")
    }
}
