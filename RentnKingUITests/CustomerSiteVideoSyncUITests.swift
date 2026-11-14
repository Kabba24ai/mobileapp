//
//  CustomerSiteVideoSyncUITests.swift
//  RentnKingUITests — a video filmed before opening a colleague's prepared checklist
//  keeps counting everywhere (2026-11-14), against a STAGING backend.
//
//  Seed: RentnKingUITests/CustomerSiteVideoSyncStagingSeed.php — one-line orders BASE+1…+3
//  (KABBA_VIDEO_BASE, default 9600), each PREPARED by Employee A through the API, assigned to B
//  and set On My Way → Arrived, so Dispatch's Start Delivery opens Main Order at the customer
//  site (an upload opened from the Orders list follows the yard rule instead). Run in order:
//
//    V0  as B (fresh install), legs still UNASSIGNED: films every order's walk-around from Main
//        Order (Orders list), before opening its checklist, so each upload names no cycle. The
//        runner then confirms Kabba anchored each video to A's cycle and reports it to C, and
//        assigns BASE+1/+2 to B and BASE+3 to C.
//    V2  as B, same install, after a relaunch: Dispatch → Start Delivery → checklist → Submit
//        lands on Main Order.
//    V1  as B, after the runner DELETED B's sync record for BASE+1: Submit lands on Main Order.
//    V3  as C (fresh install = another phone): Submit lands on Main Order.
//
//  Env (forwarded by xcodebuild as TEST_RUNNER_*):
//    KABBA_BASE_URL / KABBA_EMAIL / KABBA_PASSWORD   staging harness login
//    KABBA_VIDEO_BASE                                the seed's base (default 9600)
//    KABBA_VIDEO_CARDS                               the orders' Dispatch card numbers (BASE+1…),
//                                                    comma-separated (cards show "#<order id>")
//    KABBA_VIDEO_CAPTURE=camera                      film with the camera (a physical phone)
//                                                    instead of the simulator's library
//

import XCTest

final class CustomerSiteVideoSyncUITests: XCTestCase {

    private var base = ""
    private var email = ""
    private var password = ""
    private var videoBase = 9600
    private var useCamera = false
    private var cards: [String] = []

    private func order(_ n: Int) -> String { String(videoBase + n) }
    /// The Dispatch card's "#<id>" for order BASE+n.
    private func card(_ n: Int) -> String { n <= cards.count ? "#" + cards[n - 1] : order(n) }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        base = env["KABBA_BASE_URL"] ?? ""
        email = env["KABBA_EMAIL"] ?? ""
        password = env["KABBA_PASSWORD"] ?? ""
        videoBase = Int(env["KABBA_VIDEO_BASE"] ?? "") ?? 9600
        useCamera = env["KABBA_VIDEO_CAPTURE"] == "camera"
        cards = (env["KABBA_VIDEO_CARDS"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        addUIInterruptionMonitor(withDescription: "system-permission") { alert in
            for label in ["Allow", "Allow While Using App", "OK", "Allow Full Access", "Allow Access to All Photos"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
    }

    // MARK: - The scenario

    /// Employee B films each order from Main Order before opening its checklist.
    func testV0_bFilmsFromMainOrderBeforeOpeningTheChecklist() {
        XCTAssertFalse(base.isEmpty, "set KABBA_BASE_URL")
        let app = signedIn()
        for n in 1...3 {
            openOrderDetailsFromOrders(app, order: order(n))
            shoot("V0-\(n)-main-order-before")
            filmDeliveryVideo(app, n: n)
            // Opened from the Orders list, a saved upload returns to the order (yard rule).
            XCTAssertTrue(element(app, "orderDetails.checklist.delivery").waitForExistence(timeout: 40),
                          "order \(order(n)): the video save did not return to the order")
            XCTAssertFalse(onUploadScreen(app), "order \(order(n)): still on the video screen")
            shoot("V0-\(n)-back-on-the-order")
            goBack(app)
        }
        sleep(15)   // let the Sync Engine upload the three videos
        shoot("V0-done")
    }

    /// Same phone, after a relaunch (B's records intact): Submit lands on Main Order.
    func testV2_afterARelaunchBSubmitsAndLandsOnMainOrder() {
        let app = relaunchKeepingSession()
        submitExpectingMainOrder(app, n: 2, tag: "V2")
    }

    /// Same phone after the runner deleted B's sync record for BASE+1: Kabba's flag is the evidence.
    func testV1_withBsRecordGoneBSubmitsAndLandsOnMainOrder() {
        let app = relaunchKeepingSession()
        submitExpectingMainOrder(app, n: 1, tag: "V1")
    }

    /// Another employee's phone (fresh install, signed in as C), which never held the record.
    func testV3_anotherEmployeesPhoneSubmitsAndLandsOnMainOrder() {
        let app = signedIn()
        submitExpectingMainOrder(app, n: 3, tag: "V3")
    }


    /// PR #6 scenario A at the customer site: Video first → Checklist → Main Order, never Video again.
    func testW1_videoFirstThenChecklistLandsOnMainOrder() {
        let app = launchForWorkflow()
        openMainOrderFromDispatch(app, card: card(4))
        openUploadFromMainOrder(app)
        addVideoAndSubmit(app, n: 4)
        XCTAssertTrue(app.staticTexts["Preview"].firstMatch.waitForExistence(timeout: 40), "W1: video first must move on to the checklist")
        XCTAssertFalse(onUploadScreen(app), "W1: sent back to the video screen")
        shoot("W1-checklist-after-video")
        completeOpenChecklist(app, tag: "W1")
        expectMainOrder(app, tag: "W1")
    }

    /// PR #6 scenario B at the customer site: Checklist first → Video → Main Order.
    func testW2_checklistFirstThenVideoLandsOnMainOrder() {
        let app = launchForWorkflow()
        openMainOrderFromDispatch(app, card: card(5))
        openChecklistFromMainOrder(app, order: order(5))
        completeOpenChecklist(app, tag: "W2")
        // The checklist is done and no video yet: the upload screen, once.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, !onUploadScreen(app) { usleep(500_000) }
        if !onUploadScreen(app) { dump(app, "W2-after-checklist") }
        XCTAssertTrue(onUploadScreen(app), "W2: checklist first must move on to Video")
        shoot("W2-video-after-checklist")
        addVideoAndSubmit(app, n: 5)
        expectMainOrder(app, tag: "W2")
    }

    /// B signed in: the existing session when the previous test left one, else the harness login.
    private func launchForWorkflow() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        dismissSaveSheets(app)
        if text(app, "Dispatch").waitForExistence(timeout: 25), !app.buttons["login.button"].exists { return app }
        app.terminate()
        return signedIn()
    }

    private func completeOpenChecklist(_ app: XCUIApplication, tag: String) {
        answer(app, line: 0, question: "Any body damage at delivery?", value: "No damage")
        answer(app, line: 0, question: "Keys handed over?", value: "Yes")
        chooseEmployee(app, line: 0)
        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "\(tag): Preview did not open")
        sign(app)
        submit(app)
    }

    private func expectMainOrder(_ app: XCUIApplication, tag: String) {
        let mainOrder = element(app, "orderDetails.checklist.delivery")
        if !mainOrder.waitForExistence(timeout: 40) { dump(app, "\(tag)-end") }
        XCTAssertFalse(onUploadScreen(app), "\(tag): sent back to Video")
        XCTAssertTrue(mainOrder.exists, "\(tag): did not land on Main Order")
        shoot("\(tag)-landed-on-main-order")
    }

    // MARK: - Steps

    private func submitExpectingMainOrder(_ app: XCUIApplication, n: Int, tag: String) {
        let order = order(n)
        openMainOrderFromDispatch(app, card: card(n))
        openChecklistFromMainOrder(app, order: order)
        shoot("\(tag)-checklist-opened")
        answer(app, line: 0, question: "Any body damage at delivery?", value: "No damage")
        answer(app, line: 0, question: "Keys handed over?", value: "Yes")
        chooseEmployee(app, line: 0)
        tapPreview(app)
        XCTAssertTrue(element(app, "checklist.submit").waitForExistence(timeout: 20), "\(tag): Preview did not open")
        sign(app)
        submit(app)
        // Both activities done: Main Order (Order Details), never the video screen.
        let mainOrder = element(app, "orderDetails.checklist.delivery")
        if !mainOrder.waitForExistence(timeout: 30) { dump(app, "\(tag)-after-submit") }
        XCTAssertFalse(onUploadScreen(app), "\(tag): the saved video was not recognised — sent back to Video")
        XCTAssertTrue(mainOrder.exists, "\(tag): Submit did not land on Main Order")
        shoot("\(tag)-landed-on-main-order")
    }

    /// Photo/Video Deliv → the line's tile → Select Video → Choose (library) or Take (camera) → Submit.
    private func filmDeliveryVideo(_ app: XCUIApplication, n: Int) {
        openUploadFromMainOrder(app)
        addVideoAndSubmit(app, n: n)
    }

    private func openUploadFromMainOrder(_ app: XCUIApplication) {
        let tileLabel = text(app, "Photo/Video Deliv")
        XCTAssertTrue(tileLabel.waitForExistence(timeout: 15), "no Photo/Video Deliv tile")
        for _ in 0..<8 where tileLabel.frame.maxY > 780 { drag(app, by: -250); usleep(400_000) }
        tileLabel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()   // an untitled button covers the label
        XCTAssertTrue(app.staticTexts["Video Sync Alpha"].waitForExistence(timeout: 15), "the upload screen has no Video Sync Alpha section")
    }

    private func addVideoAndSubmit(_ app: XCUIApplication, n: Int) {
        XCTAssertTrue(app.staticTexts["Video Sync Alpha"].waitForExistence(timeout: 15), "the upload screen has no Video Sync Alpha section")
        let header = app.staticTexts["Video Sync Alpha"].firstMatch
        let tile = app.buttons.allElementsBoundByIndex
            .filter { ($0.value as? String ?? "").hasPrefix("ORD-") && $0.frame.minY > header.frame.maxY - 2 }
            .min { $0.frame.minY < $1.frame.minY }
        if tile == nil { dump(app, "V0-\(n)-upload-screen") }
        guard let tile else { XCTFail("no media tile under Video Sync Alpha"); return }
        tile.tap()
        let selectVideo = app.buttons["Select Video"].firstMatch
        XCTAssertTrue(selectVideo.waitForExistence(timeout: 8), "no Select Video choice")
        selectVideo.tap()

        if useCamera {
            let take = app.buttons["Take Video"].firstMatch
            XCTAssertTrue(take.waitForExistence(timeout: 8), "no Take Video choice")
            take.tap()
            sleep(3)
            clearSystemAlerts()
            let shutter = app.buttons["VideoCapture"].firstMatch
            if !shutter.waitForExistence(timeout: 12) { dump(app, "V0-\(n)-camera") }
            XCTAssertTrue(shutter.exists, "no VideoCapture shutter")
            shutter.tap(); sleep(4); app.buttons["VideoCapture"].firstMatch.tap(); sleep(2)
            for label in ["Use Video", "Use", "Done", "Choose"] where app.buttons[label].firstMatch.exists {
                app.buttons[label].firstMatch.tap(); break
            }
        } else {
            let choose = app.buttons["Choose Video"].firstMatch
            XCTAssertTrue(choose.waitForExistence(timeout: 8), "no Choose Video choice")
            choose.tap()
            sleep(4)
            let clip = app.images.matching(NSPredicate(format: "label BEGINSWITH[c] 'Video' OR label BEGINSWITH[c] 'Photo'")).firstMatch
            let cell = clip.exists ? clip : app.cells.firstMatch
            if !cell.waitForExistence(timeout: 15) { dump(app, "V0-\(n)-video-picker") }
            XCTAssertTrue(cell.exists, "the library shows no video")
            cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()   // the picker is a remote view
            sleep(3)
            for label in ["Choose", "Use", "Done"] where app.buttons[label].firstMatch.waitForExistence(timeout: 6) {
                app.buttons[label].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); break
            }
        }
        sleep(4)
        shoot("V0-\(n)-video-selected")
        let submit = app.staticTexts["Submit"].firstMatch       // a label over an untitled button
        XCTAssertTrue(submit.waitForExistence(timeout: 15), "no upload Submit")
        submit.tap()
    }

    private func onUploadScreen(_ app: XCUIApplication) -> Bool {
        app.buttons.allElementsBoundByIndex.contains { ($0.value as? String ?? "").hasPrefix("ORD-SCH") }
            && app.staticTexts["Submit"].firstMatch.exists
            && !app.staticTexts["Preview"].firstMatch.exists
    }

    private func clearSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            var tapped = false
            for label in ["Allow", "OK", "Allow While Using App"] where springboard.buttons[label].firstMatch.exists {
                springboard.buttons[label].firstMatch.tap(); tapped = true; break
            }
            if !tapped { break }
            usleep(800_000)
        }
    }

    // MARK: - Shared helpers (ChecklistBatchIsolationUITests' proven gestures)

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
        dismissSaveSheets(app)
        return app
    }

    /// A plain launch (no harness arguments) keeps the signed-in session and every local record.
    private func relaunchKeepingSession() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        dismissSaveSheets(app)
        XCTAssertTrue(text(app, "Dispatch").waitForExistence(timeout: 40), "relaunch did not land on Home (session lost?)")
        return app
    }

    private func openOrderDetailsFromOrders(_ app: XCUIApplication, order: String) {
        let entry = text(app, "Orders")
        if entry.waitForExistence(timeout: 10) { entry.tap(); usleep(2_500_000) }
        let row = app.staticTexts.matching(NSPredicate(format: "label == %@", order)).firstMatch
        for _ in 0..<10 where !(row.exists && row.isHittable) { app.swipeUp(); usleep(600_000) }
        if !row.exists { dump(app, "no-order-\(order)") }
        XCTAssertTrue(row.exists, "no Orders row for \(order)")
        row.tap()
        XCTAssertTrue(element(app, "orderDetails.checklist.delivery").waitForExistence(timeout: 20), "Order Details for \(order) did not open")
        usleep(1_500_000)
    }

    /// Home → Dispatch → the stop's card → Start Delivery: at Arrived it opens Main Order.
    private func openMainOrderFromDispatch(_ app: XCUIApplication, card order: String) {
        let entry = text(app, "Dispatch")
        if !element(app, "orderDetails.checklist.delivery").exists, entry.waitForExistence(timeout: 15) { entry.tap(); sleep(4) }
        let card = app.cells.containing(NSPredicate(format: "label == %@", order)).firstMatch
        for _ in 0..<10 where !(card.exists && card.isHittable) { app.swipeUp(); usleep(600_000) }
        if !card.exists { dump(app, "no-dispatch-card-\(order)") }
        XCTAssertTrue(card.exists, "no Dispatch card for \(order)")
        let start = card.staticTexts["Start Delivery"].firstMatch
        (start.exists ? start : card).tap()
        if !element(app, "orderDetails.checklist.delivery").waitForExistence(timeout: 20) { dump(app, "start-delivery-\(order)") }
        XCTAssertTrue(element(app, "orderDetails.checklist.delivery").exists, "Start Delivery for \(order) did not open Main Order")
        usleep(1_500_000)
    }

    private func openChecklistFromMainOrder(_ app: XCUIApplication, order: String) {
        element(app, "orderDetails.checklist.delivery").tap()
        usleep(2_500_000)
        if element(app, "assemblyReview.order").waitForExistence(timeout: 6) {
            confirmEverything(app)
            let go = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.continue' AND enabled == true")).firstMatch
            XCTAssertTrue(reveal(app, go), "no Continue to Checklist on the review")
            go.tap()
            usleep(2_500_000)
        }
        if !app.staticTexts["Preview"].firstMatch.waitForExistence(timeout: 30) { dump(app, "open-checklist-\(order)") }
        XCTAssertTrue(app.staticTexts["Preview"].firstMatch.exists, "the checklist for \(order) did not open")
    }

    private func questionCells(_ app: XCUIApplication, _ question: String) -> [XCUIElement] {
        app.tables.firstMatch.cells.allElementsBoundByIndex
            .filter { $0.staticTexts[question].exists }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    private func bring(_ app: XCUIApplication, _ question: String, line: Int, top: CGFloat = 170, bottom: CGFloat = 560) -> XCUIElement {
        for _ in 0..<14 {
            let cells = questionCells(app, question)
            guard line < cells.count else { app.tables.firstMatch.swipeUp(); usleep(600_000); continue }
            let cell = cells[line]
            if cell.frame.minY < top { drag(app, by: min(300, top - cell.frame.minY + 40)) }
            else if cell.frame.minY > bottom { drag(app, by: -min(300, cell.frame.minY - bottom + 40)) }
            else { return cell }
            usleep(600_000)
        }
        let cells = questionCells(app, question)
        XCTAssertTrue(line < cells.count, "no '\(question)' cell for line \(line)")
        return cells[min(line, max(0, cells.count - 1))]
    }

    private func drag(_ app: XCUIApplication, by dy: CGFloat) {
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)), withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    private func answer(_ app: XCUIApplication, line: Int, question: String, value: String) {
        let cell = bring(app, question, line: line)
        let control = cell.buttons.allElementsBoundByIndex.max { $0.frame.minX < $1.frame.minX } ?? cell.buttons.firstMatch
        XCTAssertTrue(control.exists, "no answer control in line \(line)'s '\(question)'")
        control.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 8), "answer picker did not open")
        wheel.adjust(toPickerWheelValue: value)
        usleep(400_000)
        app.buttons["Select"].firstMatch.tap()
        usleep(900_000)
    }

    /// "Delivered By": the signed-in employee is pre-selected; pick one only when it is empty.
    private func chooseEmployee(_ app: XCUIApplication, line: Int) {
        _ = line
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Select Employee'")).firstMatch
        for _ in 0..<4 where !(field.exists && field.isHittable) { app.tables.firstMatch.swipeUp(); usleep(500_000) }
        XCTAssertTrue(field.exists, "no Delivered By field")
        let current = (field.value as? String ?? "").trimmingCharacters(in: .whitespaces)
        if !current.isEmpty && current != "Select Employee" { return }
        field.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 8), "employee picker did not open")
        usleep(400_000)
        app.buttons["Select"].firstMatch.tap()
        usleep(800_000)
    }

    private func tapPreview(_ app: XCUIApplication) {
        let preview = app.staticTexts["Preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "no Preview button")
        preview.tap()
        usleep(1_500_000)
    }

    private func sign(_ app: XCUIApplication) {
        let button = element(app, "checklist.customerSignature")
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no customer signature control")
        button.tap()
        usleep(2_000_000)
        let pad = app.windows.firstMatch
        let a = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45))
        a.press(forDuration: 0.1, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.55)))
        usleep(500_000)
        let done = app.staticTexts["Submit"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "signature pad has no Submit")
        done.tap()
        usleep(2_500_000)
    }

    private func submit(_ app: XCUIApplication) {
        let submit = element(app, "checklist.submit")
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        XCTAssertTrue(submit.isEnabled, "Submit must be enabled once the line is signed")
        submit.tap()
        let yes = app.alerts.buttons["Yes"].firstMatch
        XCTAssertTrue(yes.waitForExistence(timeout: 10), "no 'ready to submit?' confirmation")
        yes.tap()
        sleep(10)
        shoot("after-submit")
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.buttons["icon back"].firstMatch
        if back.waitForExistence(timeout: 5) { back.tap(); usleep(1_500_000) }
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

    @discardableResult
    private func reveal(_ app: XCUIApplication, _ el: XCUIElement) -> Bool {
        for _ in 0..<8 where !(el.exists && el.isHittable) { app.swipeUp(); usleep(500_000) }
        for _ in 0..<8 where !(el.exists && el.isHittable) { app.swipeDown(); usleep(500_000) }
        return el.exists
    }

    private func dismissSaveSheets(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
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
