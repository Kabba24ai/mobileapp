//
//  DriverDeliveryFlowHostedTests.swift
//  RentnKingHostedTests — Driver Delivery Process Flow (2026-09-27), Task 10
//
//  Runs inside the app (TEST_HOST) so the real screens are exercised:
//  Dispatch's Start Delivery / Start Return routes by the effective workflow
//  stage (spec §5); the Driver Checklist starts with nothing preselected,
//  enforces the explicit departure gate (§7, D2/D3/D11), shows the effective
//  unit and offers Review Assembly (§6), binds the answers to the unit (D5)
//  and records On My Way BEFORE deciding how to navigate (§8).
//
//  Rows, the review and the ids come from the shared Laravel fixture
//  (dispatch_offline_packages.json) — the server's own shape, never hardcoded.
//

import XCTest
import ObjectMapper
@testable import RentnKing

final class DriverDeliveryFlowHostedTests: XCTestCase {

    // MARK: - Fixture

    private var package: JSONValue!
    private var productId = ""
    private var orderUid = ""
    private var unitA = ""
    private var unitAName = ""
    private var unitATag = ""
    private var savedBaseURL: String?

    private func fixturePackage() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KabbaSyncCore/Fixtures/dispatch_offline_packages.json")
        let root = try XCTUnwrap(JSONValue.parse(try Data(contentsOf: url)))
        return try XCTUnwrap(root["data"]?["packages"]?.arrayValue?.first)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        package = try fixturePackage()
        productId = try XCTUnwrap(package["order_product_unique_id"]?.stringValue)
        orderUid = try XCTUnwrap(package["dispatch"]?["order"]?["unique_id"]?.stringValue)
        let equipment = try XCTUnwrap(package["dispatch"]?["row"]?["equipment"])
        unitA = try XCTUnwrap(equipment["unique_id"]?.stringValue)
        unitAName = try XCTUnwrap(equipment["equipment_name"]?.stringValue)
        unitATag = try XCTUnwrap(equipment["equipment_id"]?.stringValue)
        // The routing tests rely on the fixture row carrying a server mini-checklist copy
        // (evidence) — say so if a regeneration ever nulls it.
        XCTAssertNotNil(try XCTUnwrap(DispatchOfflineRowAdapter.schedulesModel(from: try XCTUnwrap(package["dispatch"]?["row"]))).delivery_checklist?.serverCopy,
                        "fixture precondition: dispatch.row.delivery_checklist holds server progress")
        savedBaseURL = UserDefaults.standard.baseURL
        // No real server: the engine's drain fails fast and the operations stay pending.
        UserDefaults.standard.baseURL = "https://driver-flow.invalid/api/admin/v1/"
        forgetLocalRecords()
        discardTestOperations()
    }

    override func tearDown() {
        forgetLocalRecords()
        discardTestOperations()
        UserDefaults.standard.baseURL = savedBaseURL
        super.tearDown()
    }

    private func forgetLocalRecords() {
        for leg in [DriverChecklistLocalState.legDelivery, DriverChecklistLocalState.legPickup] {
            UserDefaults.standard.removeObject(forKey: DriverChecklistLocalState.key(orderProductUniqueId: productId, leg: leg))
        }
    }

    private func discardTestOperations() {
        guard let engine = KabbaSync.engine else { return }
        for op in engine.snapshot() where op.payload["order_product_unique_id"]?.stringValue == productId {
            try? engine.discard(operationId: op.id)
        }
    }

    // MARK: - Builders

    /// Sets `value` at `path` (String keys / Int indexes) inside a JSONValue tree.
    private func setting(_ root: JSONValue, _ path: [Any], _ value: JSONValue) -> JSONValue {
        guard let head = path.first else { return value }
        let rest = Array(path.dropFirst())
        if let key = head as? String, case .object(var object) = root {
            object[key] = setting(object[key] ?? .null, rest, value)
            return .object(object)
        }
        if let index = head as? Int, case .array(var array) = root, index < array.count {
            array[index] = setting(array[index], rest, value)
            return .array(array)
        }
        return root
    }

    private let emptyChecklistBlock: JSONValue = .object([
        "equipment_fuel": .null, "equipment_key_location": .null, "equipment_driver_status": .null,
        "ready_to_go_at": .null, "arrived_at": .null, "is_delivered": .bool(false), "is_arrived": .bool(false),
        "call_customer": .null, "driver_checks": .null, "equipment_unique_id": .null,
    ])

    private struct Unit { let id: String; let name: String; let tag: String }
    private let unitB = Unit(id: "EQP-UNIT-B", name: "Skid Steer 9", tag: "EQP-9")

    /// The fixture's mission row, adjusted: `evidence` false strips the server's
    /// mini-checklist copy; `pickup` makes it the Return leg; `requires*` set the
    /// yard's fuel / key predicates; `unit` swaps the assigned machine.
    private func row(evidence: Bool = true, pickup: Bool = false, requiresFuel: Bool = true, requiresKeys: Bool = true,
                     unit: Unit? = nil) throws -> SchedulesModel {
        var json = try XCTUnwrap(package["dispatch"]?["row"])
        if !evidence { json = setting(json, ["delivery_checklist"], emptyChecklistBlock) }
        json = setting(json, ["is_delivered"], .bool(pickup))
        json = setting(json, ["equipment", "requires_fuel_check"], .bool(requiresFuel))
        json = setting(json, ["equipment", "requires_key_check"], .bool(requiresKeys))
        if let unit {
            json = setting(json, ["equipment", "unique_id"], .string(unit.id))
            json = setting(json, ["equipment", "equipment_name"], .string(unit.name))
            json = setting(json, ["equipment", "equipment_id"], .string(unit.tag))
        }
        return try XCTUnwrap(DispatchOfflineRowAdapter.schedulesModel(from: json))
    }

    /// The fixture's cached Assembly Review for the order, at GO (unit confirmed
    /// Available — the fixture member has no options) or STOP (unconfirmed).
    private func review(go: Bool) throws -> AssemblyReviewEnvelope {
        var envelope = try XCTUnwrap(package["assembly"])
        envelope = setting(envelope, ["success"], .bool(true))   // the package stores the body; the wire envelope carries success
        envelope = setting(envelope, ["data", "assemblies", 0, "members", 0, "availability", "unit", "state"], go ? .string("available") : .null)
        return try AssemblyReviewEnvelope.decode(try envelope.serialized())
    }

    private func driverOp(status: String, leg: String = "delivery", state: SyncState = .pending, minutesAgo: Double = 5) -> SyncOperation {
        var op = SyncOperation(type: EffectiveFieldState.driverChecklistType, capturedAt: Date().addingTimeInterval(-60 * minutesAgo),
                               identity: SyncBusinessIdentity(orderProductUniqueId: productId),
                               payload: .object(["order_product_unique_id": .string(productId), "checklist_type": .string(leg),
                                                 "equipment_driver_status": .string(status)]))
        op.state = state
        return op
    }

    private func switchOp(to unit: Unit) -> SyncOperation {
        SyncOperation(type: EffectiveFieldState.equipmentSubstitutionType, capturedAt: Date(),
                      identity: SyncBusinessIdentity(orderProductUniqueId: productId, equipmentUniqueId: unit.id),
                      payload: .object(["order_product_unique_id": .string(productId), "equipment_unique_id": .string(unit.id),
                                        "equipment_name": .string(unit.name), "equipment_display_id": .string(unit.tag)]))
    }

    private func dispatch(_ row: SchedulesModel, ops: [SyncOperation] = [], review: AssemblyReviewEnvelope? = nil)
        -> (list: DispatchListViewController, nav: UINavigationController) {
        let vc = DispatchListViewController()
        vc.arrDispatchList = [row]
        vc.operationsSnapshot = { ops }
        vc.cachedAssemblyReview = { _ in review }
        return (vc, UINavigationController(rootViewController: vc))
    }

    private func start(_ list: DispatchListViewController) {
        let button = UIButton()
        button.tag = 0
        list.btnStatusCallClicked(button)
    }

    private func screen2(_ row: SchedulesModel, ops: [SyncOperation] = [], review: AssemblyReviewEnvelope? = nil) throws -> DriverChecklistViewController {
        let storyboard = UIStoryboard(name: GlobalMainConstants.SCHEDULE_MODEL, bundle: nil)
        let vc = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "DriverChecklistViewController") as? DriverChecklistViewController)
        vc.objDispatch = row
        vc.productUniqueId = row.unique_id ?? ""
        vc.strOrderUniqueId = row.order?.unique_id ?? ""
        vc.strOrderID = "\(row.order?.order_number ?? "")"
        vc.checklistType = row.is_delivered == false ? "delivery" : "pickup"
        vc.operationsSnapshot = { ops }
        vc.cachedAssemblyReview = { _ in review }
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.view.layoutIfNeeded()
        return vc
    }

    private func select(_ segment: UISegmentedControl, _ index: Int) {
        segment.selectedSegmentIndex = index
        segment.sendActions(for: .valueChanged)
    }

    private func tickEveryCallCheck(_ vc: DriverChecklistViewController) {
        for button in vc.callCustomerCheckboxButtons where !button.isSelected {
            button.sendActions(for: .touchUpInside)
        }
    }

    private func driverOrigin(_ vc: UIViewController?) -> (product: String, enteredFrom: DeliveryWorkflowStage, isRevisit: Bool)? {
        guard let review = vc as? AssemblyReviewViewController,
              case let .driver(product, enteredFrom, isRevisit) = review.origin.kind else { return nil }
        return (product, enteredFrom, isRevisit)
    }

    // MARK: - Dispatch: Start Delivery / Start Return by stage (§5)

    func testStartDeliveryWithNoEvidenceAndAGoReviewOpensTheAssemblyReviewWithTheDriverOrigin() throws {
        let (list, nav) = dispatch(try row(evidence: false), review: try review(go: true))
        start(list)

        let review = try XCTUnwrap(nav.topViewController as? AssemblyReviewViewController, "first Start Delivery → the yard gate")
        let origin = try XCTUnwrap(driverOrigin(review))
        XCTAssertEqual(origin.product, productId)
        XCTAssertEqual(origin.enteredFrom, .assemblyReview)
        XCTAssertFalse(origin.isRevisit)
        XCTAssertEqual(review.origin.selectIndex, 0)
        XCTAssertEqual(review.focusOrderProductUniqueId, productId, "focused on the mission line")
        XCTAssertEqual(review.orderUniqueId, orderUid)
    }

    func testStartDeliveryWithAStopReviewOpensTheReviewEvenWithEvidence() throws {
        let (stopList, stopNav) = dispatch(try row(evidence: true), review: try review(go: false))
        start(stopList)
        XCTAssertNotNil(driverOrigin(stopNav.topViewController), "STOP never skips the gate")

        let (noReviewList, noReviewNav) = dispatch(try row(evidence: true), review: nil)
        start(noReviewList)
        XCTAssertNotNil(driverOrigin(noReviewNav.topViewController), "no review on this phone is honestly STOP (§6.4)")
    }

    func testStartDeliveryWithEvidenceAndGoOpensTheDriverChecklistNotStarted() throws {
        let (list, nav) = dispatch(try row(evidence: true), review: try review(go: true))
        start(list)

        let screen = try XCTUnwrap(nav.topViewController as? DriverChecklistViewController)
        XCTAssertEqual(screen.checklistType, "delivery")
        XCTAssertEqual(screen.productUniqueId, productId)
        XCTAssertTrue(screen.delegate_Data is DispatchListViewController)
        screen.loadViewIfNeeded()
        XCTAssertFalse(screen.viewDriverCheckList.isHidden, "the checklist controls, not the On My Way state")
        XCTAssertTrue(screen.viewArrivedMain.isHidden)
    }

    func testStartDeliveryWithAnOnMyWayOperationOpensTheDriverChecklistOnMyWayWhateverTheGateSays() throws {
        let (list, nav) = dispatch(try row(evidence: true), ops: [driverOp(status: "On My Way")], review: try review(go: false))
        start(list)

        let screen = try XCTUnwrap(nav.topViewController as? DriverChecklistViewController, "a departed truck is never sent back to the yard gate")
        screen.operationsSnapshot = { [self.driverOp(status: "On My Way")] }
        screen.loadViewIfNeeded()
        XCTAssertFalse(screen.viewArrivedMain.isHidden, "On My Way state")
        XCTAssertTrue(screen.viewDriverCheckList.isHidden)
        XCTAssertEqual(screen.lblArrived.text, "Arrived")
    }

    func testStartDeliveryWithAnArrivedOperationOpensOrderDetails() throws {
        let (list, nav) = dispatch(try row(evidence: true), ops: [driverOp(status: "On My Way", minutesAgo: 10), driverOp(status: "Arrived")], review: try review(go: false))
        start(list)

        let details = try XCTUnwrap(nav.topViewController as? OrderDetailsViewController, "Arrived resumes at Main Order (D4)")
        XCTAssertTrue(details.fromCheckListScreen)
        XCTAssertTrue(details.isOrderScreen)
        XCTAssertEqual(details.completionLeg, .delivery)
        XCTAssertEqual(details.strProductID, productId)
        XCTAssertEqual(details.strOrderUniqueId, orderUid)
    }

    func testStartDeliveryOnASyncedArrivedRowStillOpensOrderDetails() throws {
        // The Arrived op synced and the feed refreshed: the row's checklist block now carries
        // is_delivered (the server's Arrived latch, delivery_is_delivered), is_arrived and the
        // stamps, no local op remains standing — the line is NOT complete; it resumes at Main Order.
        var json = try XCTUnwrap(package["dispatch"]?["row"])
        json = setting(json, ["delivery_checklist", "is_delivered"], .bool(true))
        json = setting(json, ["delivery_checklist", "is_arrived"], .bool(true))
        json = setting(json, ["delivery_checklist", "arrived_at"], .string("2026-09-27 10:05:00"))
        json = setting(json, ["delivery_checklist", "ready_to_go_at"], .string("2026-09-27 09:40:00"))
        json = setting(json, ["delivery_checklist", "equipment_driver_status"], .string("Arrived"))
        let synced = try XCTUnwrap(DispatchOfflineRowAdapter.schedulesModel(from: json))
        XCTAssertEqual(synced.is_delivered, false, "row-level: still the delivery leg")

        let (list, nav) = dispatch(synced, ops: [], review: try review(go: true))
        start(list)
        let details = try XCTUnwrap(nav.topViewController as? OrderDetailsViewController, "Arrived per the server → Main Order, never a dead Start button")
        XCTAssertEqual(details.completionLeg, .delivery)
    }

    func testStartReturnNeverOpensTheReview() throws {
        let (list, nav) = dispatch(try row(evidence: false, pickup: true), review: nil)
        start(list)
        let screen = try XCTUnwrap(nav.topViewController as? DriverChecklistViewController, "Return has no Assembly Review (§13)")
        XCTAssertEqual(screen.checklistType, "pickup")

        let arrived = [driverOp(status: "On My Way", leg: "pickup", minutesAgo: 10), driverOp(status: "Arrived", leg: "pickup")]
        let (arrivedList, arrivedNav) = dispatch(try row(evidence: false, pickup: true), ops: arrived, review: nil)
        start(arrivedList)
        let details = try XCTUnwrap(arrivedNav.topViewController as? OrderDetailsViewController)
        XCTAssertEqual(details.completionLeg, .return)
    }

    // MARK: - Driver Checklist: the explicit gate (§7)

    func testTheDeliveryGateStartsUnansweredAndNamesEachBlockerInOrder() throws {
        let vc = try screen2(try row(evidence: false), review: try review(go: true))

        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, UISegmentedControl.noSegment, "nothing is preselected (§7.1)")
        XCTAssertEqual(vc.fuelSegment.selectedSegmentIndex, UISegmentedControl.noSegment)
        XCTAssertEqual(vc.keysSegment.selectedSegmentIndex, UISegmentedControl.noSegment)
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerCall, "GO, so the call is the first unmet term")

        select(vc.callCustomerSegment, 1)                      // No Answer — a complete call
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerFuel)

        select(vc.fuelSegment, 0)                              // Not Full — recorded, still blocks (D2)
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerFuel)

        select(vc.fuelSegment, 1)                              // Full
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerKeys)

        select(vc.keysSegment, 0)                              // Missing — recorded, still blocks (D11)
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerKeys)

        select(vc.keysSegment, 1)                              // With Machine
        XCTAssertTrue(vc.btnReadytoGo.isEnabled, "GO + No Answer + Full + With Machine")
        XCTAssertTrue(vc.gateBlockerLabel.isHidden)

        select(vc.callCustomerSegment, 0)                      // Confirmed, no ticks yet
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerCall)

        tickEveryCallCheck(vc)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled, "Confirmed with every check")
    }

    func testTheAssemblyTermBlocksUntilGo() throws {
        for envelope in [try review(go: false), nil] {
            let vc = try screen2(try row(evidence: false), review: envelope)
            select(vc.callCustomerSegment, 1)
            select(vc.fuelSegment, 1)
            select(vc.keysSegment, 1)
            XCTAssertFalse(vc.btnReadytoGo.isEnabled, "STOP (or no review) never departs — \(envelope == nil ? "no review" : "STOP")")
            XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerAssembly)
        }
    }

    func testAUnitRequiringNeitherFuelNorKeysAsksOnlyTheCall() throws {
        let vc = try screen2(try row(evidence: false, requiresFuel: false, requiresKeys: false), review: try review(go: true))
        XCTAssertNil(vc.fuelSegment.superview, "no fuel column for a unit the yard says needs none")
        XCTAssertNil(vc.keysSegment.superview)
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        select(vc.callCustomerSegment, 1)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled, "the call alone, with GO")
    }

    func testReturnHasNoFuelKeysAssemblyTermOrReviewAssembly() throws {
        let vc = try screen2(try row(evidence: false, pickup: true), review: nil)
        XCTAssertNil(vc.fuelSegment.superview)
        XCTAssertNil(vc.keysSegment.superview)
        XCTAssertNil(vc.reviewAssemblyButton.superview, "Return has no Assembly Review")
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, UISegmentedControl.noSegment)
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerCall, "no assembly term on Return, even with no review")
        select(vc.callCustomerSegment, 1)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled)
    }

    // MARK: - The unit header and Review Assembly (§6)

    func testTheHeaderShowsTheEffectiveUnitIncludingAPendingLocalSwitch() throws {
        let vc = try screen2(try row(evidence: false), review: try review(go: true))
        XCTAssertEqual(vc.unitIdentityLabel.text, "\(unitAName) · #\(unitATag)")

        let switched = try screen2(try row(evidence: false), ops: [switchOp(to: unitB)], review: try review(go: true))
        XCTAssertEqual(switched.unitIdentityLabel.text, "\(unitB.name) · #\(unitB.tag)", "a switch this phone made shows before the feed catches up")
    }

    func testReviewAssemblyIsOfferedBeforeAndAfterDepartureAndOpensTheReviewAsARevisit() throws {
        let vc = try screen2(try row(evidence: false), review: try review(go: true))
        let nav = UINavigationController(rootViewController: vc)
        XCTAssertNotNil(vc.reviewAssemblyButton.superview)
        vc.reviewAssemblyButton.sendActions(for: .touchUpInside)
        let before = try XCTUnwrap(driverOrigin(nav.topViewController))
        XCTAssertEqual(before.product, productId)
        XCTAssertEqual(before.enteredFrom, .driverChecklist)
        XCTAssertTrue(before.isRevisit)

        let onMyWay = try screen2(try row(evidence: true), ops: [driverOp(status: "On My Way")], review: try review(go: true))
        let onMyWayNav = UINavigationController(rootViewController: onMyWay)
        XCTAssertNotNil(onMyWay.reviewAssemblyButton.superview, "still reachable On My Way — read-only there")
        XCTAssertFalse(onMyWay.reviewAssemblyButton.isHidden)
        onMyWay.reviewAssemblyButton.sendActions(for: .touchUpInside)
        let after = try XCTUnwrap(driverOrigin(onMyWayNav.topViewController))
        XCTAssertEqual(after.enteredFrom, .onMyWay)
        XCTAssertTrue(after.isRevisit)
        XCTAssertTrue(AssemblyPolicy.driverReadOnly(stage: onMyWay.effectiveStage, memberStage: .pending))
    }

    // MARK: - Load Map & Go (§8, D5)

    func testLoadMapAndGoRecordsOnMyWayBoundToTheUnitBeforeDecidingHowToNavigate() throws {
        let engine = try XCTUnwrap(KabbaSync.engine, "the hosted app bootstraps the Sync Engine")
        let vc = try screen2(try row(evidence: false), review: try review(go: true))
        vc.operationsSnapshot = { engine.snapshot() }
        select(vc.callCustomerSegment, 1)
        select(vc.fuelSegment, 1)
        select(vc.keysSegment, 1)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled)

        var openedMaps: [String] = []
        var notices: [UIAlertController] = []
        vc.isReachable = { false }
        vc.openMaps = { address, _ in openedMaps.append(address) }
        vc.presentNoticeOverride = { notices.append($0) }

        let before = engine.snapshot().count
        vc.btnReadytoGo_Action(UIButton())

        let departure = try XCTUnwrap(engine.snapshot().first {
            $0.payload["order_product_unique_id"]?.stringValue == productId
                && $0.payload["equipment_driver_status"]?.stringValue == "On My Way"
        }, "On My Way is a durable driver_checklist.update")
        XCTAssertEqual(departure.payload["equipment_unique_id"]?.stringValue, unitA, "D5: the answers are bound to the unit")
        XCTAssertEqual(departure.payload["equipment_fuel"]?.stringValue, "Full")
        XCTAssertEqual(departure.payload["equipment_key_location"]?.stringValue, "With Machine")
        XCTAssertEqual(departure.payload["call_customer"]?.stringValue, "no_answer")
        XCTAssertEqual(departure.payload["checklist_type"]?.stringValue, "delivery")

        XCTAssertTrue(openedMaps.isEmpty, "no service: Maps is not opened")
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices.first?.title, LoadMapAndGoDecision.serviceOfflineTitle)
        XCTAssertEqual(notices.first?.message, LoadMapAndGoDecision.serviceOfflineMessage)

        XCTAssertFalse(vc.viewArrivedMain.isHidden, "the screen is in the On My Way state")
        XCTAssertTrue(vc.viewDriverCheckList.isHidden)
        XCTAssertEqual(vc.effectiveStage, .onMyWay)
        XCTAssertTrue(AssemblyPolicy.driverReadOnly(stage: vc.effectiveStage, memberStage: .pending), "its review is read-only from now on")

        vc.btnReadytoGo_Action(UIButton())
        XCTAssertEqual(engine.snapshot().count, before + 1, "a second tap records nothing")

        // With service, Maps opens and no notice is shown.
        forgetLocalRecords()
        let online = try screen2(try row(evidence: false), review: try review(go: true))
        online.operationsSnapshot = { engine.snapshot().filter { $0.payload["order_product_unique_id"]?.stringValue != self.productId } }
        select(online.callCustomerSegment, 1)
        select(online.fuelSegment, 1)
        select(online.keysSegment, 1)
        var onlineMaps: [String] = []
        var onlineNotices: [UIAlertController] = []
        online.isReachable = { true }
        online.openMaps = { address, done in onlineMaps.append(address); done(true) }
        online.presentNoticeOverride = { onlineNotices.append($0) }
        online.btnReadytoGo_Action(UIButton())
        XCTAssertEqual(onlineMaps, [try XCTUnwrap(try row().order?.objDeliveryAddress?.full_address)])
        XCTAssertTrue(onlineNotices.isEmpty)

        // A geocode failure with service is the same Service Offline notice — the map button stays for a retry.
        forgetLocalRecords()
        let unroutable = try screen2(try row(evidence: false), review: try review(go: true))
        unroutable.operationsSnapshot = { engine.snapshot().filter { $0.payload["order_product_unique_id"]?.stringValue != self.productId } }
        select(unroutable.callCustomerSegment, 1)
        select(unroutable.fuelSegment, 1)
        select(unroutable.keysSegment, 1)
        var failedNotices: [UIAlertController] = []
        unroutable.isReachable = { true }
        unroutable.openMaps = { _, done in done(false) }
        unroutable.presentNoticeOverride = { failedNotices.append($0) }
        unroutable.btnReadytoGo_Action(UIButton())
        XCTAssertEqual(failedNotices.first?.title, LoadMapAndGoDecision.serviceOfflineTitle)
    }

    // MARK: - Restore (§7.3, D5)

    func testRestoreDropsFuelAndKeysRecordedForAnotherUnitAndKeepsTheCall() throws {
        let forUnitA = DriverChecklistLocalState(checks: [true, false, false, false], callCustomer: "no_answer",
                                                 fuel: "Full", keys: "With Machine", equipmentUniqueId: unitA)
        UserDefaults.standard.set(forUnitA.dictionary(), forKey: DriverChecklistLocalState.key(orderProductUniqueId: productId, leg: DriverChecklistLocalState.legDelivery))

        let vc = try screen2(try row(evidence: false, unit: unitB), review: try review(go: true))
        XCTAssertEqual(vc.fuelSegment.selectedSegmentIndex, UISegmentedControl.noSegment, "unit A's fuel never speaks for unit B")
        XCTAssertEqual(vc.keysSegment.selectedSegmentIndex, UISegmentedControl.noSegment)
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, 1, "the call belongs to the mission")
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerFuel)

        let stored = DriverChecklistLocalState(dictionary: UserDefaults.standard.dictionary(forKey: DriverChecklistLocalState.key(orderProductUniqueId: productId, leg: DriverChecklistLocalState.legDelivery)))
        XCTAssertEqual(stored?.equipmentUniqueId, unitB.id, "the record now belongs to the effective unit")
        XCTAssertEqual(stored?.fuel, "")
        XCTAssertEqual(stored?.keys, "")

        // The same unit restores everything.
        forgetLocalRecords()
        UserDefaults.standard.set(forUnitA.dictionary(), forKey: DriverChecklistLocalState.key(orderProductUniqueId: productId, leg: DriverChecklistLocalState.legDelivery))
        let same = try screen2(try row(evidence: false), review: try review(go: true))
        XCTAssertEqual(same.fuelSegment.selectedSegmentIndex, 1)
        XCTAssertEqual(same.keysSegment.selectedSegmentIndex, 1)
        XCTAssertTrue(same.btnReadytoGo.isEnabled)
    }

    // MARK: - The Dispatch row copy carries answers, never stage

    func testTheDispatchRowCopyTakesOnlyTheAnswersFromScreenTwo() throws {
        let (list, _) = dispatch(try row(evidence: true))
        var block = try XCTUnwrap(list.arrDispatchList[0].delivery_checklist)
        block.is_delivered = true
        block.is_arrived = true
        block.arrived_at = "2026-09-27 10:00:00"
        block.ready_to_go_at = "2026-09-27 09:30:00"
        block.equipment_driver_status = "Arrived"
        block.equipment_fuel = "Not Full"
        block.equipment_key_location = "Missing"
        block.call_customer = "no_answer"
        block.driver_checks = [1, 1, 1, 1]
        block.equipment_unique_id = unitB.id

        list.data_updateInCurrentDic(index: 0, dicCheckList: block)

        let copy = try XCTUnwrap(list.arrDispatchList[0].delivery_checklist)
        XCTAssertEqual(copy.is_delivered, false, "stage is derived from the Sync Engine, never written onto the row")
        XCTAssertEqual(copy.is_arrived, false)
        XCTAssertNil(copy.arrived_at)
        XCTAssertNil(copy.ready_to_go_at)
        XCTAssertNil(copy.equipment_driver_status)
        XCTAssertEqual(copy.equipment_fuel, "Not Full", "the answers do travel — they feed the green band and the next restore")
        XCTAssertEqual(copy.equipment_key_location, "Missing")
        XCTAssertEqual(copy.call_customer, "no_answer")
        XCTAssertEqual(copy.driver_checks, [1, 1, 1, 1])
        XCTAssertEqual(copy.equipment_unique_id, unitB.id)
    }
}
