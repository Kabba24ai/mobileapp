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
                     unit: Unit? = nil, options: [String]? = nil) throws -> SchedulesModel {
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
        if let options {
            // The checkout-frozen Product Options the row carries (product_data.product_option_items).
            json = setting(json, ["product_data", "product_option_items"],
                           .array(options.map { .object(["name": .string($0), "price": .number(0), "included": .bool(true)]) }))
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

    private func switchOp(to unit: Unit, at: Date = Date(), state: SyncState = .pending) -> SyncOperation {
        var op = SyncOperation(type: EffectiveFieldState.equipmentSubstitutionType, capturedAt: at, queuedAt: at,
                               identity: SyncBusinessIdentity(orderProductUniqueId: productId, equipmentUniqueId: unit.id),
                               payload: .object(["order_product_unique_id": .string(productId), "equipment_unique_id": .string(unit.id),
                                                 "equipment_name": .string(unit.name), "equipment_display_id": .string(unit.tag)]))
        op.state = state
        return op
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

    /// This phone's durable Available acknowledgement for a unit on the mission line.
    private func availabilityOp(unit: Unit, at: Date = Date(), state: SyncState = .pending) -> SyncOperation {
        var op = SyncOperation(type: AssemblyOperationBuilder.availabilityType, capturedAt: at, queuedAt: at,
                               identity: SyncBusinessIdentity(orderProductUniqueId: productId, equipmentUniqueId: unit.id),
                               payload: .object(["order_product_unique_id": .string(productId),
                                                 "subject_type": .string(AvailabilitySubject.unit.rawValue),
                                                 "subject_key": .string(unit.id),
                                                 "state": .string(AvailabilityState.available.rawValue)]))
        op.state = state
        return op
    }

    /// A unit as the warmed equipment list (the fleet the review offers offline) knows it.
    private func machine(_ unit: Unit, requiresFuel: Bool, requiresKeys: Bool) throws -> MachineModel {
        try XCTUnwrap(MachineModel(JSON: ["unique_id": unit.id, "equipment_name": unit.name, "equipment_id": unit.tag,
                                          "requires_fuel_check": requiresFuel, "requires_key_check": requiresKeys]))
    }

    private func screen2(_ row: SchedulesModel, ops: [SyncOperation] = [], review: AssemblyReviewEnvelope? = nil,
                         observedAt: Date? = nil, fleet: [MachineModel] = []) throws -> DriverChecklistViewController {
        let storyboard = UIStoryboard(name: GlobalMainConstants.SCHEDULE_MODEL, bundle: nil)
        let vc = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "DriverChecklistViewController") as? DriverChecklistViewController)
        vc.objDispatch = row
        vc.serverObservedAt = observedAt          // Dispatch sets it before the push — before the view loads
        vc.productUniqueId = row.unique_id ?? ""
        vc.strOrderUniqueId = row.order?.unique_id ?? ""
        vc.strOrderID = "\(row.order?.order_number ?? "")"
        vc.checklistType = row.is_delivered == false ? "delivery" : "pickup"
        vc.operationsSnapshot = { ops }
        vc.cachedAssemblyReview = { _ in review }
        vc.warmedEquipment = { fleet }            // never the device's own equipment list
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
        XCTAssertEqual(details.missionServerTrip?.isArrived, true)
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
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerCallWizard, "GO, so the call is the first unmet term")

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

        // "Confirmed" cannot be tapped into existence: the segment falls back to the
        // derived state and the wizard opens (from Delivery Address); the gate blocks.
        let nav = UINavigationController(rootViewController: vc)
        select(vc.callCustomerSegment, 0)
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, 1, "still No Answer — nothing was verified")
        XCTAssertTrue(nav.topViewController is CustomerCallWizardViewController)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled, "No Answer still stands until a step is verified")

        completeCall(vc, nav: nav)
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, 0, "Confirmed — derived from the three verified steps")
        XCTAssertTrue(vc.btnReadytoGo.isEnabled, "the verified call with Full + With Machine")
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

    // MARK: - Fuel / keys apply to the EFFECTIVE unit (D2 / D5 / D11; closing review I-1)

    func testASwitchToAUnitNeedingFuelAndKeysAsksThemEvenWhenTheRowsUnitNeededNeither() throws {
        // The row's unit is electric with a keypad (the yard asks nothing); on this phone the
        // driver switched to a keyed diesel unit of the same category and acknowledged it
        // Available. Screen 2 asks fuel and keys for THAT unit, and binds the answers to it.
        let vc = try screen2(try row(evidence: false, requiresFuel: false, requiresKeys: false),
                             ops: [switchOp(to: unitB), availabilityOp(unit: unitB)], review: try review(go: true),
                             fleet: [try machine(unitB, requiresFuel: true, requiresKeys: true)])
        XCTAssertNotNil(vc.fuelSegment.superview, "the replacement's fuel sign-off applies, not the row's")
        XCTAssertNotNil(vc.keysSegment.superview, "the replacement's key sign-off applies, not the row's")
        select(vc.callCustomerSegment, 1)
        XCTAssertFalse(vc.btnReadytoGo.isEnabled, "the call alone must not pass for a unit that needs fuel and keys")
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerFuel)
        select(vc.fuelSegment, 1)
        select(vc.keysSegment, 1)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled)

        let stored = DriverChecklistLocalState(dictionary: UserDefaults.standard.dictionary(forKey: DriverChecklistLocalState.key(orderProductUniqueId: productId, leg: DriverChecklistLocalState.legDelivery)))
        XCTAssertEqual(stored?.equipmentUniqueId, unitB.id, "the answers bind to the replacement (D5)")
        XCTAssertEqual(stored?.fuel, FuelAnswer.full.rawValue)
        XCTAssertEqual(stored?.keys, KeysAnswer.withMachine.rawValue)
    }

    func testASwitchToAUnitThePhoneKnowsNothingAboutAsksBothSignOffs() throws {
        // The replacement is not in the warmed list: unknown = ask; a silent skip is never safe.
        let vc = try screen2(try row(evidence: false, requiresFuel: false, requiresKeys: false),
                             ops: [switchOp(to: unitB), availabilityOp(unit: unitB)], review: try review(go: true), fleet: [])
        XCTAssertNotNil(vc.fuelSegment.superview)
        XCTAssertNotNil(vc.keysSegment.superview)
        select(vc.callCustomerSegment, 1)
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerFuel)
    }

    func testTheColumnsAndTheGateFollowASwitchMadeWhileTheScreenIsOpen() throws {
        // The row's unit needs both. The driver goes to Review Assembly and switches to an
        // electric keypad unit; back on Screen 2 the columns are gone and the call alone passes.
        let vc = try screen2(try row(evidence: false), review: try review(go: true),
                             fleet: [try machine(unitB, requiresFuel: false, requiresKeys: false)])
        XCTAssertNotNil(vc.fuelSegment.superview)
        select(vc.fuelSegment, 0)                       // Not Full — recorded for the row's unit
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)

        vc.operationsSnapshot = { [self.switchOp(to: self.unitB), self.availabilityOp(unit: self.unitB)] }
        vc.refreshDerivedState()                        // viewWillAppear / the engine's change notice
        XCTAssertNil(vc.fuelSegment.superview, "the electric replacement asks no fuel question")
        XCTAssertNil(vc.keysSegment.superview)
        XCTAssertEqual(vc.unitIdentityLabel.text, "\(unitB.name) · #\(unitB.tag)")
        select(vc.callCustomerSegment, 1)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled, "the call alone, with GO, for a unit needing neither")

        // The switch is rejected and retired (no durable local op): the row's unit asks again,
        // and unit A's earlier Not Full never comes back pre-filled (D5).
        vc.operationsSnapshot = { [] }
        vc.refreshDerivedState()
        XCTAssertNotNil(vc.fuelSegment.superview)
        XCTAssertNotNil(vc.keysSegment.superview)
        XCTAssertEqual(vc.fuelSegment.selectedSegmentIndex, UISegmentedControl.noSegment, "a replaced unit starts unanswered")
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerFuel)
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

    // MARK: - Call Customer wizard (2026-09-29): Delivery's three-step customer call

    private func wizard(_ nav: UINavigationController, file: StaticString = #filePath, line: UInt = #line) throws -> CustomerCallWizardViewController {
        let wizard = try XCTUnwrap(nav.topViewController as? CustomerCallWizardViewController, "the wizard is open", file: file, line: line)
        wizard.loadViewIfNeeded()
        return wizard
    }

    private func choose(_ wizard: CustomerCallWizardViewController, _ code: String, note: String? = nil) throws {
        let index = try XCTUnwrap(UnloadingSituation.codes.firstIndex(of: code))
        wizard.choiceButtons[index].sendActions(for: .touchUpInside)
        if let note {
            wizard.noteField.text = note
            wizard.textViewDidChange(wizard.noteField)
        }
    }

    /// Runs the whole call from wherever the screen is: opens the wizard through the
    /// first control, verifies the address and the equipment, records the situation.
    private func completeCall(_ vc: DriverChecklistViewController, nav: UINavigationController,
                              situation: String = "easy_access", note: String? = nil) {
        if !(nav.topViewController is CustomerCallWizardViewController) {
            vc.callCustomerCheckboxButtons[0].sendActions(for: .touchUpInside)
        }
        guard let wizard = try? wizard(nav) else { return }
        XCTAssertEqual(wizard.step, .address, "an unfinished call always starts at Delivery Address")
        wizard.primaryTapped()                               // Verify Address
        wizard.primaryTapped()                               // Verify Equipment
        try? choose(wizard, situation, note: note)
        wizard.primaryTapped()                               // Confirm Call
    }

    private var localRecord: DriverChecklistLocalState? {
        DriverChecklistLocalState(dictionary: UserDefaults.standard.dictionary(forKey:
            DriverChecklistLocalState.key(orderProductUniqueId: productId, leg: DriverChecklistLocalState.legDelivery)))
    }

    func testAFreshDeliveryShowsThreeUnverifiedStepsAndNoAttachmentsRow() throws {
        let vc = try screen2(try row(evidence: false), review: try review(go: true))
        let titles = vc.viewCallCustomerStackChecklist.arrangedSubviews.compactMap { row in
            row.subviews.compactMap { $0 as? UILabel }.first?.text
        }
        XCTAssertEqual(titles, ["Delivery Address", "Equipment Order", "Unloading Situation"])
        XCTAssertEqual(vc.callCustomerCheckboxButtons.count, 3)
        XCTAssertTrue(vc.callCustomerCheckboxButtons.allSatisfy { !$0.isSelected })
        XCTAssertFalse(titles.contains { $0.localizedCaseInsensitiveContains("attachment") }, "attachments are Product Options inside Equipment Order")
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, UISegmentedControl.noSegment)
        XCTAssertEqual(vc.callStatusLabel.text, DriverChecklistViewController.callStatusStart)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerCallWizard)
    }

    func testConfirmedCannotBeAssertedAndAnyUnfinishedStepOpensTheWizardAtTheAddress() throws {
        let vc = try screen2(try row(evidence: false), review: try review(go: true))
        let nav = UINavigationController(rootViewController: vc)

        select(vc.callCustomerSegment, 0)
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, UISegmentedControl.noSegment, "Confirmed is derived, never tapped")
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(try wizard(nav).step, .address)
        nav.popViewController(animated: false)

        // The third control, untouched call: still Delivery Address (all-or-nothing, sequential).
        vc.callCustomerCheckboxButtons[2].sendActions(for: .touchUpInside)
        let opened = try wizard(nav)
        XCTAssertEqual(opened.step, .address)
        XCTAssertEqual(opened.mode, .call)
        XCTAssertEqual(opened.addressLabel.text, try XCTUnwrap(try row().order?.objDeliveryAddress?.full_address), "the actual cached address")
        XCTAssertEqual(opened.primaryButton.currentTitle, CustomerCallWizardViewController.verifyAddressTitle)
    }

    func testEachVerifiedStepAdvancesPersistsAndOnlyTheThirdDerivesConfirmed() throws {
        let engine = try XCTUnwrap(KabbaSync.engine)
        let options = ["Bucket 72\"", "Pallet forks"]
        let vc = try screen2(try row(evidence: false, options: options), review: try review(go: true))
        vc.operationsSnapshot = { engine.snapshot() }
        vc.isReachable = { false }                            // zero service: nothing here needs a response
        let nav = UINavigationController(rootViewController: vc)
        select(vc.fuelSegment, 1)
        select(vc.keysSegment, 1)

        vc.callCustomerCheckboxButtons[1].sendActions(for: .touchUpInside)
        let wizard = try wizard(nav)
        XCTAssertEqual(wizard.stepLabel.text, "Step 1 of 3")

        wizard.primaryTapped()                                // Verify Address
        XCTAssertEqual(wizard.step, .equipment, "advances directly to Equipment Order")
        XCTAssertEqual(vc.callVerification, CustomerCallVerification(addressVerified: true))
        XCTAssertEqual(localRecord?.addressVerified, true, "persisted locally at once")
        XCTAssertEqual(localRecord?.callCustomer, "")
        XCTAssertTrue(vc.callCustomerCheckboxButtons[0].isSelected)
        XCTAssertEqual(vc.callStatusLabel.text, DriverChecklistViewController.callStatusPartial(1))
        XCTAssertFalse(vc.btnReadytoGo.isEnabled, "address only → blocked")
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerCallWizard)
        XCTAssertEqual(wizard.productLabel.text, try row().product_name, "the primary product")
        for option in options { XCTAssertTrue(wizard.optionsLabel.text?.contains(option) == true, "every Product Option: \(option)") }
        XCTAssertEqual(wizard.primaryButton.currentTitle, CustomerCallWizardViewController.verifyEquipmentTitle)

        wizard.primaryTapped()                                // Verify Equipment
        XCTAssertEqual(wizard.step, .unloading)
        XCTAssertEqual(vc.callVerification, CustomerCallVerification(addressVerified: true, equipmentVerified: true))
        XCTAssertEqual(localRecord?.equipmentVerified, true)
        XCTAssertFalse(vc.btnReadytoGo.isEnabled, "address + equipment → blocked")
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, UISegmentedControl.noSegment)
        XCTAssertEqual(wizard.choiceButtons.count, 5)
        XCTAssertFalse(wizard.primaryButton.isEnabled, "exactly one situation is required")

        try choose(wizard, "other")
        XCTAssertFalse(wizard.primaryButton.isEnabled, "Other needs a note")
        wizard.primaryTapped()
        XCTAssertEqual(nav.topViewController, wizard, "an empty Other note never completes the step")
        XCTAssertFalse(vc.callVerification.isComplete)

        try choose(wizard, "other", note: "Back lot, gate code 4411")
        XCTAssertTrue(wizard.primaryButton.isEnabled)
        wizard.primaryTapped()                                // Confirm Call
        XCTAssertEqual(nav.topViewController, vc, "the wizard closes on the third step")
        XCTAssertTrue(vc.callVerification.isComplete)
        XCTAssertEqual(vc.callVerification.unloading, .other(note: "Back lot, gate code 4411"))
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, 0, "Confirmed — automatically")
        XCTAssertEqual(vc.callStatusLabel.text, DriverChecklistViewController.callStatusConfirmed)
        XCTAssertTrue(vc.callCustomerCheckboxButtons.allSatisfy(\.isSelected))
        XCTAssertEqual(localRecord?.callCustomer, "confirmed")
        XCTAssertEqual(localRecord?.unloadingSituation, "other")
        XCTAssertEqual(localRecord?.unloadingNote, "Back lot, gate code 4411")
        XCTAssertTrue(vc.btnReadytoGo.isEnabled, "GO + verified call + Full + With Machine — with no network at all")

        // Each step queued a durable partial save through the existing engine; the last carries everything.
        let saves = engine.snapshot().filter {
            $0.type == EffectiveFieldState.driverChecklistType && $0.payload["order_product_unique_id"]?.stringValue == productId
        }
        XCTAssertEqual(saves.count, 3)
        let first = try XCTUnwrap(saves.min { $0.capturedAt < $1.capturedAt })
        XCTAssertEqual(first.payload["address_verified"]?.boolValue, true)
        XCTAssertNil(first.payload["equipment_verified"], "a step not yet verified is absent — never an explicit false that could un-verify the server's copy")
        XCTAssertNil(first.payload["unloading_situation"])
        let last = try XCTUnwrap(saves.max { $0.capturedAt < $1.capturedAt })
        XCTAssertEqual(last.payload["address_verified"]?.boolValue, true)
        XCTAssertEqual(last.payload["equipment_verified"]?.boolValue, true)
        XCTAssertEqual(last.payload["unloading_situation"]?.stringValue, "other")
        XCTAssertEqual(last.payload["unloading_note"]?.stringValue, "Back lot, gate code 4411")
        XCTAssertEqual(last.payload["call_customer"]?.stringValue, "confirmed")
        XCTAssertNil(last.payload["driver_checks"], "the delivery leg sends the steps, not ticks")
        XCTAssertNil(last.payload["equipment_driver_status"], "a partial save is not a transition")
        XCTAssertEqual(last.state, .pending, "it waits in the durable queue for service")
    }

    func testFuelAndKeysStillBlockAfterTheVerifiedCall() throws {
        let vc = try screen2(try row(evidence: false), review: try review(go: true))
        let nav = UINavigationController(rootViewController: vc)
        completeCall(vc, nav: nav)
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerFuel)
        select(vc.fuelSegment, 0)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerFuel, "Not Full still blocks")
        select(vc.fuelSegment, 1)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerKeys)
        select(vc.keysSegment, 0)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerKeys, "Missing still blocks")
        select(vc.keysSegment, 1)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled)
    }

    func testPartialWizardProgressSurvivesLeavingTheScreenAndARelaunch() throws {
        let vc = try screen2(try row(evidence: false), review: try review(go: true))
        let nav = UINavigationController(rootViewController: vc)
        vc.callCustomerCheckboxButtons[0].sendActions(for: .touchUpInside)
        try wizard(nav).primaryTapped()                       // address only
        nav.popViewController(animated: false)                // backs out mid-call

        // Re-entry (a new screen instance = a relaunch): the step is still verified and
        // the call still starts at the address (all-or-nothing until complete).
        let again = try screen2(try row(evidence: false), review: try review(go: true))
        XCTAssertEqual(again.callVerification, CustomerCallVerification(addressVerified: true))
        XCTAssertTrue(again.callCustomerCheckboxButtons[0].isSelected)
        XCTAssertEqual(again.callStatusLabel.text, DriverChecklistViewController.callStatusPartial(1))
        XCTAssertFalse(again.btnReadytoGo.isEnabled)
        let againNav = UINavigationController(rootViewController: again)
        again.callCustomerCheckboxButtons[2].sendActions(for: .touchUpInside)
        let reopened = try wizard(againNav)
        XCTAssertEqual(reopened.step, .address)
        reopened.primaryTapped(); reopened.primaryTapped()    // two steps now
        againNav.popViewController(animated: false)

        let third = try screen2(try row(evidence: false), review: try review(go: true))
        XCTAssertEqual(third.callVerification, CustomerCallVerification(addressVerified: true, equipmentVerified: true))
        XCTAssertEqual(third.callStatusLabel.text, DriverChecklistViewController.callStatusPartial(2))
        XCTAssertFalse(third.btnReadytoGo.isEnabled)
    }

    func testNoAnswerSatisfiesTheCallOfflineWithoutPretendingTheStepsWereVerified() throws {
        let vc = try screen2(try row(evidence: false, requiresFuel: false, requiresKeys: false), review: try review(go: true))
        vc.isReachable = { false }
        select(vc.callCustomerSegment, 1)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled, "No Answer alone, with GO and a unit needing neither")
        XCTAssertEqual(vc.callStatusLabel.text, DriverChecklistViewController.callStatusNoAnswer)
        XCTAssertTrue(vc.callCustomerCheckboxButtons.allSatisfy { !$0.isSelected }, "no step is marked verified")
        XCTAssertEqual(vc.callVerification, .notStarted)
        XCTAssertEqual(localRecord?.callCustomer, "no_answer")
        XCTAssertEqual(localRecord?.addressVerified, false)

        // Later the customer answers: the wizard starts at the address and No Answer is dropped
        // the moment a step is verified; the whole call is then required again.
        let nav = UINavigationController(rootViewController: vc)
        let engine = try XCTUnwrap(KabbaSync.engine)
        vc.callCustomerCheckboxButtons[1].sendActions(for: .touchUpInside)
        let wizard = try wizard(nav)
        XCTAssertEqual(wizard.step, .address)
        // Opening the wizard hides the checklist (viewWillDisappear) — that push must NOT
        // flush the transient No Answer to the server: it would text the customer the
        // driver is now talking to. A real exit still syncs.
        vc.viewWillDisappear(false)
        XCTAssertFalse(engine.snapshot().contains {
            $0.payload["order_product_unique_id"]?.stringValue == productId && $0.payload["call_customer"]?.stringValue == "no_answer"
        }, "no No Answer save is queued by opening the wizard")
        wizard.primaryTapped()
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, UISegmentedControl.noSegment, "No Answer no longer stands")
        XCTAssertEqual(localRecord?.callCustomer, "")
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerCallWizard)

        // And No Answer after partial progress clears the steps again.
        nav.popViewController(animated: false)
        select(vc.callCustomerSegment, 1)
        XCTAssertEqual(vc.callVerification, .notStarted)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled)
    }

    func testTheCallSurvivesAnEquipmentSwitchWhileFuelAndKeysFollowTheReplacement() throws {
        let vc = try screen2(try row(evidence: false), review: try review(go: true),
                             fleet: [try machine(unitB, requiresFuel: true, requiresKeys: true)])
        let nav = UINavigationController(rootViewController: vc)
        completeCall(vc, nav: nav, situation: "unload_on_street")
        select(vc.fuelSegment, 1)
        select(vc.keysSegment, 1)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled)

        // The driver switches to unit B on Review Assembly (durable local switch + Available).
        let at = Date()
        vc.operationsSnapshot = { [self.switchOp(to: self.unitB, at: at), self.availabilityOp(unit: self.unitB, at: at.addingTimeInterval(1))] }
        DriverMissionStage.retireFuelAndKeys(orderProductUniqueId: productId, replacementUnit: unitB.id, episode: "SW-1")
        vc.refreshDerivedState()

        XCTAssertTrue(vc.callVerification.isComplete, "the call belongs to the mission, not the unit")
        XCTAssertEqual(vc.callVerification.unloading, .unloadOnStreet)
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, 0, "still Confirmed")
        XCTAssertEqual(vc.fuelSegment.selectedSegmentIndex, UISegmentedControl.noSegment, "fuel follows the replacement")
        XCTAssertEqual(vc.keysSegment.selectedSegmentIndex, UISegmentedControl.noSegment)
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerFuel, "the call term is satisfied; fuel is the next")

        // Partial progress survives a switch the same way.
        forgetLocalRecords()
        let partial = try screen2(try row(evidence: false), review: try review(go: true), fleet: [try machine(unitB, requiresFuel: true, requiresKeys: true)])
        let partialNav = UINavigationController(rootViewController: partial)
        partial.callCustomerCheckboxButtons[0].sendActions(for: .touchUpInside)
        try wizard(partialNav).primaryTapped()
        partialNav.popViewController(animated: false)
        partial.operationsSnapshot = { [self.switchOp(to: self.unitB, at: at), self.availabilityOp(unit: self.unitB, at: at.addingTimeInterval(1))] }
        partial.refreshDerivedState()
        XCTAssertEqual(partial.callVerification, CustomerCallVerification(addressVerified: true))
        XCTAssertEqual(partial.callStatusLabel.text, DriverChecklistViewController.callStatusPartial(1))
    }

    func testAfterConfirmedEachControlOpensItsOwnPageForReviewWithoutClearingTheCall() throws {
        let options = ["Bucket 72\""]
        let vc = try screen2(try row(evidence: false, options: options), review: try review(go: true))
        let nav = UINavigationController(rootViewController: vc)
        completeCall(vc, nav: nav, situation: "alternate_location")
        XCTAssertTrue(vc.callVerification.isComplete)

        vc.callCustomerCheckboxButtons[0].sendActions(for: .touchUpInside)
        let address = try wizard(nav)
        XCTAssertEqual(address.mode, .review(.address))
        XCTAssertEqual(address.step, .address)
        XCTAssertEqual(address.addressLabel.text, try XCTUnwrap(try row().order?.objDeliveryAddress?.full_address))
        XCTAssertEqual(address.primaryButton.currentTitle, CustomerCallWizardViewController.doneTitle)
        address.primaryTapped()
        XCTAssertEqual(nav.topViewController, vc)
        XCTAssertTrue(vc.callVerification.isComplete, "a review never clears Confirmed")
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, 0)

        vc.callCustomerCheckboxButtons[1].sendActions(for: .touchUpInside)
        let equipment = try wizard(nav)
        XCTAssertEqual(equipment.mode, .review(.equipment))
        XCTAssertTrue(equipment.optionsLabel.text?.contains("Bucket 72\"") == true)
        equipment.primaryTapped()
        XCTAssertTrue(vc.callVerification.isComplete)

        vc.callCustomerCheckboxButtons[2].sendActions(for: .touchUpInside)
        let unloading = try wizard(nav)
        XCTAssertEqual(unloading.mode, .review(.unloading))
        XCTAssertEqual(unloading.draftUnloading, .alternateLocation, "the saved choice is shown")
        XCTAssertEqual(unloading.primaryButton.currentTitle, CustomerCallWizardViewController.saveChoiceTitle)
        try choose(unloading, "easy_access")
        unloading.primaryTapped()
        XCTAssertEqual(nav.topViewController, vc)
        XCTAssertEqual(vc.callVerification.unloading, .easyAccess, "the new valid choice is persisted")
        XCTAssertEqual(localRecord?.unloadingSituation, "easy_access")
        XCTAssertTrue(vc.callVerification.isComplete, "and the call stays confirmed")
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, 0)
    }

    func testADoubleTapOpensOneWizardAndAStaleSnapshotNeverRegressesTheRecord() throws {
        let vc = try screen2(try row(evidence: false), review: try review(go: true))
        let nav = UINavigationController(rootViewController: vc)

        vc.callCustomerCheckboxButtons[0].sendActions(for: .touchUpInside)
        vc.callCustomerCheckboxButtons[1].sendActions(for: .touchUpInside)   // the classic double-tap
        XCTAssertEqual(nav.viewControllers.count, 2, "one wizard, never two")

        // Even a wizard holding an older snapshot can only add: the record is monotonic.
        completeCall(vc, nav: nav, situation: "easy_access")
        XCTAssertTrue(vc.callVerification.isComplete)
        vc.applyCallVerification(CustomerCallVerification(addressVerified: true))   // a stale hand-back
        XCTAssertTrue(vc.callVerification.isComplete, "a stale snapshot never un-verifies a step")
        XCTAssertEqual(vc.callVerification.unloading, .easyAccess)
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, 0)
    }

    func testACallRestartedAfterNoAnswerTravelsWithoutTheEarlierSteps() throws {
        // The call was completed (and synced); the driver then taps No Answer — local only —
        // and, the customer calling back, starts again. The first save of the new call must
        // carry ONLY what is verified now, so the server (which replaces the stored steps
        // with what a payload carries) never confirms it from the call before.
        let engine = try XCTUnwrap(KabbaSync.engine)
        let vc = try screen2(try row(evidence: false), review: try review(go: true))
        vc.operationsSnapshot = { engine.snapshot() }
        let nav = UINavigationController(rootViewController: vc)
        completeCall(vc, nav: nav, situation: "other", note: "Back lot")
        XCTAssertTrue(vc.callVerification.isComplete)

        select(vc.callCustomerSegment, 1)                     // No Answer: the steps are cleared locally
        XCTAssertEqual(vc.callVerification, .notStarted)
        discardTestOperations()                               // (the earlier saves are not under test)

        vc.callCustomerCheckboxButtons[0].sendActions(for: .touchUpInside)
        let wizard = try wizard(nav)
        XCTAssertEqual(wizard.mode, .call)
        XCTAssertEqual(wizard.step, .address)
        wizard.primaryTapped()                                // Verify Address

        XCTAssertEqual(vc.callVerification, CustomerCallVerification(addressVerified: true))
        XCTAssertEqual(vc.callStatusLabel.text, DriverChecklistViewController.callStatusPartial(1))
        let saves = engine.snapshot().filter { $0.payload["order_product_unique_id"]?.stringValue == productId }
        XCTAssertEqual(saves.count, 1)
        let save = try XCTUnwrap(saves.first)
        XCTAssertEqual(save.payload["address_verified"]?.boolValue, true)
        XCTAssertNil(save.payload["equipment_verified"], "not verified in THIS call")
        XCTAssertNil(save.payload["unloading_situation"], "no situation in THIS call")
        XCTAssertNil(save.payload["unloading_note"])
        XCTAssertNil(save.payload["call_customer"], "neither confirmed nor No Answer")
    }

    func testThePrimaryButtonIgnoresTouchesRightAfterAPageChange() throws {
        // The same button verifies the next page: a double-tap must not verify a page unread.
        let vc = try screen2(try row(evidence: false), review: try review(go: true))
        let nav = UINavigationController(rootViewController: vc)
        vc.callCustomerCheckboxButtons[0].sendActions(for: .touchUpInside)
        let wizard = try wizard(nav)
        XCTAssertTrue(wizard.primaryButton.isUserInteractionEnabled)
        wizard.primaryTapped()                                // Verify Address → Equipment Order
        XCTAssertEqual(wizard.step, .equipment)
        XCTAssertFalse(wizard.primaryButton.isUserInteractionEnabled, "locked for a moment after the page change")
        RunLoop.current.run(until: Date().addingTimeInterval(CustomerCallWizardViewController.pageChangeTouchLockout + 0.2))
        XCTAssertTrue(wizard.primaryButton.isUserInteractionEnabled)
    }

    func testOnlyARealExitSyncsWhileTheWizardIsUpAndBack() throws {
        // A window, so UIKit drives the appearance callbacks for real.
        let engine = try XCTUnwrap(KabbaSync.engine)
        let vc = try screen2(try row(evidence: false, requiresFuel: false, requiresKeys: false), review: try review(go: true))
        vc.operationsSnapshot = { engine.snapshot() }
        let nav = UINavigationController(rootViewController: vc)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = nav
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let ops = { engine.snapshot().filter { $0.payload["order_product_unique_id"]?.stringValue == self.productId } }

        select(vc.callCustomerSegment, 1)                     // No Answer — local only for now
        vc.callCustomerCheckboxButtons[0].sendActions(for: .touchUpInside)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertTrue(nav.topViewController is CustomerCallWizardViewController)
        XCTAssertTrue(ops().isEmpty, "opening the wizard flushes nothing")

        nav.popViewController(animated: false)                // the driver backs out, No Answer still standing
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(nav.topViewController, vc)
        XCTAssertTrue(ops().isEmpty, "coming back flushes nothing either")

        nav.pushViewController(UIViewController(), animated: false)   // a real exit (Order Details, Dispatch…)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let saves = ops()
        XCTAssertEqual(saves.count, 1, "exactly one partial save on a real exit")
        XCTAssertEqual(saves.first?.payload["call_customer"]?.stringValue, "no_answer")
        XCTAssertNil(saves.first?.payload["address_verified"])
    }

    func testLoadMapAndGoCarriesTheVerifiedCallWithTheDeparture() throws {
        let engine = try XCTUnwrap(KabbaSync.engine)
        let vc = try screen2(try row(evidence: false), review: try review(go: true))
        vc.operationsSnapshot = { engine.snapshot() }
        vc.isReachable = { false }
        vc.presentNoticeOverride = { _ in }
        let nav = UINavigationController(rootViewController: vc)
        completeCall(vc, nav: nav, situation: "other", note: "Back lot")
        select(vc.fuelSegment, 1)
        select(vc.keysSegment, 1)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled)

        vc.btnReadytoGo_Action(UIButton())
        let departure = try XCTUnwrap(engine.snapshot().first {
            $0.payload["order_product_unique_id"]?.stringValue == productId && $0.payload["equipment_driver_status"]?.stringValue == "On My Way"
        })
        XCTAssertEqual(departure.payload["call_customer"]?.stringValue, "confirmed")
        XCTAssertEqual(departure.payload["address_verified"]?.boolValue, true)
        XCTAssertEqual(departure.payload["equipment_verified"]?.boolValue, true)
        XCTAssertEqual(departure.payload["unloading_situation"]?.stringValue, "other")
        XCTAssertEqual(departure.payload["unloading_note"]?.stringValue, "Back lot")
        XCTAssertEqual(departure.payload["equipment_unique_id"]?.stringValue, unitA)
        XCTAssertNil(departure.payload["driver_checks"])
    }

    func testARowFromBeforeTheWizardIsNotConfirmedUntilTheStepsAreVerified() throws {
        // The retired four-tick claim on the server row (Confirmed + every tick) carries no verification.
        var json = try XCTUnwrap(package["dispatch"]?["row"])
        json = setting(json, ["delivery_checklist", "call_customer"], .string("confirmed"))
        json = setting(json, ["delivery_checklist", "driver_checks"], .array([.number(1), .number(1), .number(1), .number(1)]))
        json = setting(json, ["delivery_checklist", "address_verified"], .bool(false))
        json = setting(json, ["delivery_checklist", "equipment_verified"], .bool(false))
        json = setting(json, ["delivery_checklist", "unloading_situation"], .null)
        let legacy = try XCTUnwrap(DispatchOfflineRowAdapter.schedulesModel(from: json))
        let vc = try screen2(legacy, review: try review(go: true))
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, UISegmentedControl.noSegment, "a bare 'confirmed' is not a verified call")
        XCTAssertEqual(vc.callVerification, .notStarted)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerCallWizard)
    }

    func testReturnKeepsItsOwnCallTicksAndSendsThem() throws {
        let engine = try XCTUnwrap(KabbaSync.engine)
        let vc = try screen2(try row(evidence: false, pickup: true), review: nil)
        vc.operationsSnapshot = { engine.snapshot() }
        let titles = vc.viewCallCustomerStackChecklist.arrangedSubviews.compactMap { row in
            row.subviews.compactMap { $0 as? UILabel }.first?.text
        }
        XCTAssertEqual(titles, ["Pickup ready; no extension", "Equipment is accessible", "Key is in the unit"], "Return's ticks are pickup questions — untouched")
        XCTAssertNil(vc.callStatusLabel.superview, "no wizard status line on Return")
        select(vc.callCustomerSegment, 0)
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, 0, "Return's Confirmed is explicit")
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)
        XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerCall)
        tickEveryCallCheck(vc)
        XCTAssertTrue(vc.btnReadytoGo.isEnabled)

        vc.isReachable = { false }
        vc.presentNoticeOverride = { _ in }
        vc.btnReadytoGo_Action(UIButton())
        let departure = try XCTUnwrap(engine.snapshot().first {
            $0.payload["order_product_unique_id"]?.stringValue == productId && $0.payload["checklist_type"]?.stringValue == "pickup"
        })
        XCTAssertEqual(departure.payload["driver_checks"]?.arrayValue?.compactMap { $0.intValue }, [1, 1, 1])
        XCTAssertEqual(departure.payload["call_customer"]?.stringValue, "confirmed")
        XCTAssertNil(departure.payload["address_verified"], "the wizard's keys never travel on Return")
    }

    // MARK: - Task 12 — Main Order hub, post-departure checklist entry, customer-site exits

    private func jsonObject(_ value: JSONValue) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: try value.serialized()) as? [String: Any])
    }

    /// Order Details' model, from the package's order_details section (the bridge's own shape).
    private func orderDetailsModel(deliveryMedia: [[String: Any]] = []) throws -> OrdersListModel {
        var order = try jsonObject(try XCTUnwrap(package["order_details"]))
        var products = try XCTUnwrap(order["order_products"] as? [[String: Any]])
        products[0]["delivery_media"] = deliveryMedia
        order["order_products"] = products
        return try XCTUnwrap(OrdersListModel(JSON: order))
    }

    /// The checklist screens' model (a different type over the same section).
    private func checklistOrderModel() throws -> OrdersModel {
        try XCTUnwrap(OrdersModel(JSON: try jsonObject(try XCTUnwrap(package["order_details"]))))
    }

    /// The mission's cached checklist context, from the package: `videoPresent` = the server
    /// holds a video for the active cycle; `hasUnit` false = an unassigned line; `inTransit` =
    /// the server's (possibly stale) departure flag.
    private func context(videoPresent: Bool = false, hasUnit: Bool = true, inTransit: Bool = false) throws -> ChecklistContext {
        var json = try XCTUnwrap(package["checklist_context"])
        json = setting(json, ["server_state", "delivery_video_present"], .bool(videoPresent))
        json = setting(json, ["server_state", "in_transit"], .bool(inTransit))
        if !hasUnit {
            json = setting(json, ["equipment", "assignment"], .string("none"))
            json = setting(json, ["equipment", "equipment_unique_id"], .null)
        }
        return try ChecklistContext.decode(envelopeData: try json.serialized())
    }

    private func deliveryCompleteOp() -> SyncOperation {
        SyncOperation(type: EffectiveFieldState.deliveryCompleteType, capturedAt: Date(),
                      identity: SyncBusinessIdentity(orderProductUniqueId: productId),
                      payload: .object(["order_product_unique_id": .string(productId)]))
    }

    private var arrivedOps: [SyncOperation] { [driverOp(status: "On My Way", minutesAgo: 10), driverOp(status: "Arrived")] }

    /// Main Order as Dispatch / Screen 2 open it for the mission line.
    private func orderDetails(ops: [SyncOperation], review: AssemblyReviewEnvelope? = nil, context: ChecklistContext? = nil,
                              deliveryMedia: [[String: Any]] = []) throws -> OrderDetailsViewController {
        let vc = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController)
        vc.objOrderData = try orderDetailsModel(deliveryMedia: deliveryMedia)
        vc.strOrderUniqueId = orderUid
        vc.strOrderID = "1650"
        vc.strProductID = productId
        vc.isOrderScreen = true
        vc.fromCheckListScreen = true
        vc.completionLeg = .delivery
        vc.missionServerTrip = DriverStagePresentation.serverState(try row().delivery_checklist)   // as makeOrderDetails sets it
        vc.operationsSnapshot = { ops }
        vc.cachedAssemblyReview = { _ in review }
        vc.cachedChecklistContext = { _ in context }
        return vc
    }

    /// The equipment checklist as Main Order opens it after departure (focused on the mission line).
    private func checklist(floor: DeliveryWorkflowStage?, ops: [SyncOperation], context: ChecklistContext?) throws -> CheckListViewController {
        let vc = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "CheckListViewController") as? CheckListViewController)
        vc.objOrderData = try checklistOrderModel()
        vc.isDeliveryType = true
        vc.isOrderDetailsView = true
        vc.fromCheckListScreen = true
        vc.strOrderUniqueId = orderUid
        vc.strOrderID = "1650"
        vc.focusOrderProductUniqueId = productId
        vc.queueLineFocusedStaging = true
        vc.selectProductIndex = 0
        if let context { vc.checklistContexts[productId] = context }
        vc.driverStageFloor = floor
        vc.operationsSnapshot = { ops }
        vc.cachedAssemblyReview = { _ in nil }
        return vc
    }

    func testMainOrderAfterArrivalOpensTheChecklistDirectlyAndBeforeDepartureTheReview() throws {
        let arrived = try orderDetails(ops: arrivedOps)
        let nav = UINavigationController(rootViewController: DispatchListViewController())
        nav.pushViewController(arrived, animated: false)
        XCTAssertEqual(arrived.missionStage, .arrived)

        arrived.btnCheckListDelivClicked(UIButton())
        let checklist = try XCTUnwrap(nav.topViewController as? CheckListViewController, "after departure CheckList Deliv opens the checklist itself — never the review (RC6)")
        XCTAssertEqual(checklist.focusOrderProductUniqueId, productId)
        XCTAssertTrue(checklist.queueLineFocusedStaging)
        XCTAssertTrue(checklist.isDeliveryType)
        XCTAssertTrue(checklist.isOrderDetailsView)
        XCTAssertTrue(checklist.fromCheckListScreen)
        XCTAssertEqual(checklist.queueLineEquipmentUniqueId, unitA, "the locked unit")
        XCTAssertEqual(checklist.driverStageFloor, .arrived, "the stage travels with the screen")

        // Before departure (a yard entry) the review sequencing is untouched.
        let yard = try orderDetails(ops: [], review: try review(go: false))
        yard.fromCheckListScreen = false
        yard.completionLeg = nil
        let yardNav = UINavigationController(rootViewController: yard)
        yard.btnCheckListDelivClicked(UIButton())
        let review = try XCTUnwrap(yardNav.topViewController as? AssemblyReviewViewController)
        XCTAssertEqual(review.origin.kind, .orderDetails)
    }

    func testMainOrderShowsTheMissionAndOffersReviewAssemblyReadOnly() throws {
        let vc = try orderDetails(ops: arrivedOps, review: try review(go: true))
        let nav = UINavigationController(rootViewController: DispatchListViewController())
        nav.pushViewController(vc, animated: false)
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.setTheView()
        vc.view.layoutIfNeeded()

        XCTAssertFalse(vc.missionBar.isHidden)
        let text = vc.missionStatusLabel.text ?? ""
        XCTAssertTrue(text.contains("Arrived"), text)
        XCTAssertTrue(text.contains("\(unitAName) · #\(unitATag)"), text)

        vc.reviewAssemblyButton.sendActions(for: .touchUpInside)
        let origin = try XCTUnwrap(driverOrigin(nav.topViewController))
        XCTAssertEqual(origin.product, productId)
        XCTAssertEqual(origin.enteredFrom, .arrived, "read-only: the review learns the stage")
        XCTAssertTrue(origin.isRevisit)

        // A yard entry shows no mission bar.
        let yard = try orderDetails(ops: [])
        yard.fromCheckListScreen = false
        yard.completionLeg = nil
        yard.loadViewIfNeeded()
        yard.setTheView()
        XCTAssertTrue(yard.missionBar.isHidden)
    }

    func testMainOrderMediaCarriesTheActiveCycleAndTheTilesUseTheVideoPolicy() throws {
        let context = try context(videoPresent: false)
        let photoOnly: [[String: Any]] = [["id": 1, "media_type": "image", "media_url": "https://example.invalid/p.jpg"]]
        let vc = try orderDetails(ops: arrivedOps, context: context, deliveryMedia: photoOnly)
        let nav = UINavigationController(rootViewController: DispatchListViewController())
        nav.pushViewController(vc, animated: false)

        vc.btnDeliveryImageVideoUploadClicked(UIButton())
        let upload = try XCTUnwrap(nav.topViewController as? ImageUploadViewController)
        XCTAssertEqual(upload.checklistExecutionIds[productId], context.executionId, "media lands in the active cycle")
        XCTAssertEqual(upload.focusOrderProductUniqueId, productId)
        XCTAssertEqual(upload.driverStageFloor, .arrived)

        let inputs = vc.legCompletionInputs(for: .delivery)
        XCTAssertEqual(inputs.activeDeliveryExecutionId, context.executionId)
        XCTAssertFalse(inputs.deliveryVideoConfirmed)
        XCTAssertFalse(inputs.orderHasDeliveryVideo, "a photo is not a video (D7)")
        XCTAssertFalse(inputs.deliveryChecklistConfirmed, "product-scoped: this line's checklist is not complete")
        let decision = vc.legCompletionDecision(for: .delivery)
        XCTAssertEqual(decision.status(.deliveryMedia), .incomplete, "a photo-only order shows the video tile incomplete")
        XCTAssertTrue(decision.overrideSections.video, "the override screen lists Video")

        let withVideo = try orderDetails(ops: arrivedOps, context: try self.context(videoPresent: true), deliveryMedia: photoOnly)
        XCTAssertEqual(withVideo.legCompletionDecision(for: .delivery).status(.deliveryMedia), .satisfied, "the server's cycle truth satisfies")
        let completed = try orderDetails(ops: arrivedOps + [deliveryCompleteOp()], context: context)
        XCTAssertEqual(completed.legCompletionDecision(for: .delivery).status(.deliveryChecklist), .satisfied, "a durable completion for THIS line")
    }

    func testTheChecklistAfterDepartureRefusesReassignmentAndRestartExceptForAnUnassignedLine() throws {
        let stale = try context(hasUnit: true, inTransit: false)          // the cache still says "in the yard"
        XCTAssertEqual(CheckListViewController.preparationBlock(for: stale, missionStage: .onMyWay), .inTransit, "the phone's own departure wins over a stale cached context")
        XCTAssertEqual(CheckListViewController.preparationBlock(for: stale, missionStage: .arrived), .inTransit)
        XCTAssertNil(CheckListViewController.preparationBlock(for: stale, missionStage: .driverChecklist), "before departure the cached rule decides (in the yard: no block)")
        XCTAssertNil(CheckListViewController.preparationBlock(for: try context(hasUnit: false), missionStage: .onMyWay), "a departed line with no unit still picks one (§10.2)")
        XCTAssertFalse(CheckListViewController.restartAllowed(stale, hasLocalAnswers: true, missionStage: .onMyWay), "no Start Over after departure")
        XCTAssertEqual(CheckListViewController.tripStage(for: .onMyWay), .onMyWay)
        XCTAssertEqual(CheckListViewController.tripStage(for: .arrived), .arrived)
        XCTAssertEqual(CheckListViewController.tripStage(for: .driverChecklist), .notStarted)

        // The screen itself: the target it hands the shared flow carries the block.
        let vc = try checklist(floor: .onMyWay, ops: [], context: stale)
        XCTAssertEqual(vc.missionStage, .onMyWay)
        XCTAssertEqual(vc.assignmentTarget(for: stale, productIndex: 0).block, .inTransit)
        XCTAssertFalse(vc.restartIsAllowed(atProductIndex: 0))
    }

    func testCustomerSiteExitsGoToMainOrderVideoOrChecklist() throws {
        // Main Order = the nearest Order Details beneath; an Orders list further down is not the target.
        let list = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "OrderListViewController") as? OrderListViewController)
        let details = try orderDetails(ops: arrivedOps)
        let nav = UINavigationController(rootViewController: list)
        nav.pushViewController(details, animated: false)

        // License and Terms → Main Order.
        let license = LicenseTypeViewController()
        nav.pushViewController(license, animated: false)
        license.routeAfterSave()
        XCTAssertTrue(nav.topViewController === details, "License → the pushing Order Details, not the Orders list beneath")
        let terms = TermsAndConditionViewController()
        nav.pushViewController(terms, animated: false)
        terms.routeAfterSigning()
        XCTAssertTrue(nav.topViewController === details)
        let upload = LicenseUploadViewController()
        nav.pushViewController(upload, animated: false)
        upload.routeAfterSave()
        XCTAssertTrue(nav.topViewController === details)

        // Checklist Save: Video while unmet, else Main Order.
        let cl = try checklist(floor: .arrived, ops: arrivedOps, context: try context(videoPresent: false))
        nav.pushViewController(cl, animated: false)
        cl.routeAfterSave(mediaUnmet: true)
        let video = try XCTUnwrap(nav.topViewController as? ImageUploadViewController, "Save → Video while the delivery video is missing")
        XCTAssertEqual(video.focusOrderProductUniqueId, productId)
        XCTAssertEqual(video.driverStageFloor, .arrived)

        // Video done with the checklist still incomplete → back to the existing checklist; complete → Main Order.
        video.operationsSnapshot = { self.arrivedOps }
        XCTAssertTrue(video.routeAfterUpload())
        XCTAssertTrue(nav.topViewController === cl, "the checklist is not complete: back to it, not a new one")
        nav.pushViewController(video, animated: false)
        video.operationsSnapshot = { self.arrivedOps + [self.deliveryCompleteOp()] }
        XCTAssertTrue(video.routeAfterUpload())
        XCTAssertTrue(nav.topViewController === details, "complete: Main Order")

        // Save with the video met → Main Order.
        nav.pushViewController(cl, animated: false)
        cl.routeAfterSave(mediaUnmet: false)
        XCTAssertTrue(nav.topViewController === details)

        // Submit: Video when unmet, else Main Order — never the review after departure.
        let review = AssemblyReviewViewController()
        nav.pushViewController(review, animated: false)
        let cu = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "CheckListUpdateViewController") as? CheckListUpdateViewController)
        cu.objOrderData = try checklistOrderModel()
        cu.isDeliveryType = true
        cu.isOrderDetailsView = true
        cu.strOrderUniqueId = orderUid
        cu.focusOrderProductUniqueId = productId
        cu.driverStageFloor = .arrived
        cu.operationsSnapshot = { self.arrivedOps }
        cu.cachedAssemblyReview = { _ in nil }
        cu.checklistContexts[productId] = try context(videoPresent: false)
        nav.pushViewController(cu, animated: false)
        cu.routeAfterSubmit()
        let afterSubmit = try XCTUnwrap(nav.topViewController as? ImageUploadViewController, "Submit → Video while unmet")
        XCTAssertFalse(nav.topViewController === review, "never back to the review after departure")
        afterSubmit.operationsSnapshot = { self.arrivedOps + [self.deliveryCompleteOp()] }
        XCTAssertTrue(afterSubmit.routeAfterUpload())
        XCTAssertTrue(nav.topViewController === details, "…and the video done with the checklist complete lands on Main Order, past the review")

        nav.setViewControllers([list, details, review, cu], animated: false)
        cu.checklistContexts[productId] = try context(videoPresent: true)
        cu.routeAfterSubmit()
        XCTAssertTrue(nav.topViewController === details, "Submit with the video met → Main Order")

        // The yard band is untouched: before departure the checklist Save still returns to the review beneath.
        let yardReview = AssemblyReviewViewController()
        let yardChecklist = try checklist(floor: nil, ops: [], context: try context())
        nav.setViewControllers([list, details, yardReview, yardChecklist], animated: false)
        yardChecklist.routeAfterSave(mediaUnmet: false)
        XCTAssertTrue(nav.topViewController === yardReview, "yard: today's returnToReview rule")
    }

    // MARK: - Task 13 — the Return band (§13): same screens, its own rules, never the review

    private func returnRow(pickupMedia: [[String: Any]] = []) throws -> SchedulesModel { try row(evidence: false, pickup: true) }

    private func returnOp(status: String, minutesAgo: Double = 5) -> SyncOperation { driverOp(status: status, leg: "pickup", minutesAgo: minutesAgo) }

    private func returnMediaOp() -> SyncOperation {
        SyncOperation(type: EffectiveFieldState.returnMediaType, capturedAt: Date(),
                      identity: SyncBusinessIdentity(orderProductUniqueId: productId),
                      payload: .object(["order_product_unique_id": .string(productId)]))
    }

    private func returnCompleteOp() -> SyncOperation {
        SyncOperation(type: EffectiveFieldState.returnCompleteType, capturedAt: Date(),
                      identity: SyncBusinessIdentity(orderProductUniqueId: productId),
                      payload: .object(["order_product_unique_id": .string(productId)]))
    }

    func testStartReturnResumesByStageAndNeverOpensTheReview() throws {
        // Not started → Screen 2, the checklist controls (no review even with none cached).
        let (fresh, freshNav) = dispatch(try returnRow(), review: nil)
        start(fresh)
        let screen = try XCTUnwrap(freshNav.topViewController as? DriverChecklistViewController)
        XCTAssertEqual(screen.checklistType, "pickup")
        screen.loadViewIfNeeded()
        XCTAssertFalse(screen.viewDriverCheckList.isHidden)
        XCTAssertNil(screen.reviewAssemblyButton.superview, "no Review Assembly on Return")

        // On My Way → Screen 2 in the On My Way state.
        let (onMyWayList, onMyWayNav) = dispatch(try returnRow(), ops: [returnOp(status: "On My Way")], review: try review(go: false))
        start(onMyWayList)
        let enRoute = try XCTUnwrap(onMyWayNav.topViewController as? DriverChecklistViewController)
        enRoute.operationsSnapshot = { [self.returnOp(status: "On My Way")] }
        enRoute.loadViewIfNeeded()
        XCTAssertFalse(enRoute.viewArrivedMain.isHidden)
        XCTAssertTrue(enRoute.viewDriverCheckList.isHidden)

        // Arrived → Main Order for the Return leg.
        let (arrivedList, arrivedNav) = dispatch(try returnRow(), ops: [returnOp(status: "On My Way", minutesAgo: 10), returnOp(status: "Arrived")], review: nil)
        start(arrivedList)
        let details = try XCTUnwrap(arrivedNav.topViewController as? OrderDetailsViewController)
        XCTAssertEqual(details.completionLeg, .return)
        // Main Order derives the Return stage from the same steps (no assembly gate on Return).
        details.objOrderData = try orderDetailsModel()
        details.operationsSnapshot = { [self.returnOp(status: "On My Way", minutesAgo: 10), self.returnOp(status: "Arrived")] }
        XCTAssertEqual(details.missionStage, .arrived, "Return resumes at Arrived")
    }

    func testTheReturnMediaRuleIsItsOwnAndTheReturnExitsFollowIt() throws {
        var product = try XCTUnwrap(try orderDetailsModel().arrProduct.first { $0.unique_id == productId })
        XCTAssertFalse(CustomerSiteNavigation.mediaRequirementMet(product: product, isDeliveryLeg: false, context: nil, orderUniqueId: orderUid, operations: []),
                       "no pickup media yet")
        XCTAssertTrue(CustomerSiteNavigation.mediaRequirementMet(product: product, isDeliveryLeg: false, context: nil, orderUniqueId: orderUid, operations: [returnMediaOp()]),
                      "a durable return media upload for THIS line")
        product.arrPickupMedia = [try XCTUnwrap(LicenseModel(JSON: ["id": 9, "media_type": "image", "media_url": "https://example.invalid/r.jpg"]))]
        XCTAssertTrue(CustomerSiteNavigation.mediaRequirementMet(product: product, isDeliveryLeg: false, context: nil, orderUniqueId: orderUid, operations: []),
                      "Return keeps today's rule: any pickup media, photo included (D7 is Delivery-only)")
        XCTAssertFalse(CustomerSiteNavigation.mediaRequirementMet(product: product, isDeliveryLeg: true, context: try context(videoPresent: false), orderUniqueId: orderUid, operations: []),
                       "…while Delivery still demands its video")

        // Return exits: Save / Submit → Video while pickup media is missing, else Main Order; never the review.
        let details = try orderDetails(ops: [returnOp(status: "On My Way", minutesAgo: 10), returnOp(status: "Arrived")])
        details.completionLeg = .return
        let review = AssemblyReviewViewController()
        let nav = UINavigationController(rootViewController: DispatchListViewController())
        nav.pushViewController(details, animated: false)
        nav.pushViewController(review, animated: false)

        let cl = try checklist(floor: .arrived, ops: [], context: nil)
        cl.isDeliveryType = false
        nav.pushViewController(cl, animated: false)
        cl.routeAfterSave(mediaUnmet: true)
        let video = try XCTUnwrap(nav.topViewController as? ImageUploadViewController, "Return Save → Video while pickup media is missing")
        XCTAssertEqual(video.strType, "pickup")
        XCTAssertEqual(video.focusOrderProductUniqueId, productId)

        // Video done, Return checklist not complete → back to the existing (Return) checklist; complete → Main Order.
        video.operationsSnapshot = { [] }
        XCTAssertTrue(video.routeAfterUpload())
        XCTAssertTrue(nav.topViewController === cl)
        nav.pushViewController(video, animated: false)
        video.operationsSnapshot = { [self.returnCompleteOp()] }
        XCTAssertTrue(video.routeAfterUpload())
        XCTAssertTrue(nav.topViewController === details, "past the review, to Main Order")

        // With no checklist beneath, the fallback is a RETURN checklist for the line.
        nav.setViewControllers([nav.viewControllers[0], details, video], animated: false)
        video.operationsSnapshot = { [] }
        XCTAssertTrue(video.routeAfterUpload())
        let pushed = try XCTUnwrap(nav.topViewController as? CheckListViewController)
        XCTAssertFalse(pushed.isDeliveryType, "a Return upload never pushes a Delivery checklist")
        XCTAssertEqual(pushed.focusOrderProductUniqueId, productId)

        // Submit: pickup media missing → Video; present → Main Order.
        let cu = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "CheckListUpdateViewController") as? CheckListUpdateViewController)
        cu.objOrderData = try checklistOrderModel()
        cu.isDeliveryType = false
        cu.isOrderDetailsView = true
        cu.strOrderUniqueId = orderUid
        cu.focusOrderProductUniqueId = productId
        cu.driverStageFloor = .arrived
        cu.operationsSnapshot = { [] }
        cu.cachedAssemblyReview = { _ in nil }
        nav.setViewControllers([nav.viewControllers[0], details, review, cu], animated: false)
        cu.routeAfterSubmit()
        XCTAssertEqual((nav.topViewController as? ImageUploadViewController)?.strType, "pickup", "Return Submit → Video while pickup media is missing")

        nav.setViewControllers([nav.viewControllers[0], details, review, cu], animated: false)
        cu.operationsSnapshot = { [self.returnMediaOp()] }
        cu.routeAfterSubmit()
        XCTAssertTrue(nav.topViewController === details, "Return Submit with pickup media → Main Order, never the review")
    }

    // MARK: - Review of 009dbf4 / db13d96: the recalled departure and the multi-line order

    /// C1: a recalled local departure (observed by the opener) must not exclude the mission line
    /// from its own assembly gate — Dispatch must route an unconfirmed replacement to the review,
    /// and Screen 2's assembly term must block.
    func testARecalledDepartureNeverHollowsOutTheAssemblyGate() throws {
        var departed = driverOp(status: "On My Way", minutesAgo: 30)
        departed.state = .synced
        departed.acknowledgment = SyncAcknowledgment(acknowledgedAt: Date().addingTimeInterval(-25 * 60), statusCode: 200,
                                                     requestId: nil, replayed: false, serverReceivedAt: nil, data: nil)
        let observedAfterRecall = Date().addingTimeInterval(-5 * 60)

        // Dispatch: the recalled row (not departed on the server), the retained step, STOP review → the review, not Screen 2.
        let (list, nav) = dispatch(try row(evidence: true), ops: [departed], review: try review(go: false))
        list.feedObservedAt = observedAfterRecall
        list.offlineObservedAt[productId] = observedAfterRecall
        start(list)
        XCTAssertNotNil(driverOrigin(nav.topViewController), "an unconfirmed replacement is STOP → the yard gate, never Screen 2")

        // Screen 2 (reached anyway): the assembly term blocks even with call / fuel / keys answered.
        let screen = try screen2(try row(evidence: true), ops: [departed], review: try review(go: false), observedAt: observedAfterRecall)
        select(screen.callCustomerSegment, 1)
        select(screen.fuelSegment, 1)
        select(screen.keysSegment, 1)
        XCTAssertFalse(screen.btnReadytoGo.isEnabled)
        XCTAssertEqual(screen.gateBlockerLabel.text, DriverChecklistGate.blockerAssembly)
        XCTAssertFalse(screen.viewDriverCheckList.isHidden, "not in the On My Way state — the step was recalled")
    }

    /// I2: CheckList Deliv is judged for the MISSION line — a sibling line delivered earlier
    /// must not send the driver to the view-mode checklist (or the review) for this line.
    func testMainOrderChecklistEntryIsJudgedForTheMissionLineNotTheOrder() throws {
        var order = try jsonObject(try XCTUnwrap(package["order_details"]))
        var products = try XCTUnwrap(order["order_products"] as? [[String: Any]])
        var sibling = products[0]
        sibling["unique_id"] = "ORD-SCH-SIBLING"
        sibling["is_delivered"] = true
        sibling["delivery_status"] = "Completed"
        products.insert(sibling, at: 0)                       // the delivered sibling comes FIRST in the order
        order["order_products"] = products

        let vc = try orderDetails(ops: arrivedOps)
        vc.objOrderData = try XCTUnwrap(OrdersListModel(JSON: order))
        let nav = UINavigationController(rootViewController: DispatchListViewController())
        nav.pushViewController(vc, animated: false)
        vc.btnCheckListDelivClicked(UIButton())
        let checklist = try XCTUnwrap(nav.topViewController as? CheckListViewController, "the mission line is not complete: its checklist opens directly")
        XCTAssertEqual(checklist.focusOrderProductUniqueId, productId)

        // The mission line itself complete → the view-mode checklist as before.
        let done = try orderDetails(ops: arrivedOps + [deliveryCompleteOp()])
        done.objOrderData = try XCTUnwrap(OrdersListModel(JSON: order))
        let doneNav = UINavigationController(rootViewController: DispatchListViewController())
        doneNav.pushViewController(done, animated: false)
        done.btnCheckListDelivClicked(UIButton())
        XCTAssertNotNil(doneNav.topViewController as? CheckListUpdateViewController)
    }

    // MARK: - Assignment episodes (2026-09-29) — the departure gate and fuel / keys never revive across a switch

    /// The order #6009 sequence on the row's unit A: A Available → switch B → B Available → switch back A.
    private func backToA(state: SyncState) -> [SyncOperation] {
        let a = Unit(id: unitA, name: unitAName, tag: unitATag)
        let base = Date().addingTimeInterval(-600)
        let t = { (i: Int) in base.addingTimeInterval(Double(i) * 60) }
        return [availabilityOp(unit: a, at: t(0), state: state), switchOp(to: unitB, at: t(1), state: state),
                availabilityOp(unit: unitB, at: t(2), state: state), switchOp(to: a, at: t(3), state: state)]
    }

    func testLoadMapAndGoStaysBlockedWhenTheUnitComesBackAfterASwitchUntilItIsConfirmedAgain() throws {
        for state in [SyncState.pending, .synced] {
            // The cached review says the server confirmed A — before the switches.
            let vc = try screen2(try row(evidence: false, requiresFuel: false, requiresKeys: false),
                                 ops: backToA(state: state), review: try review(go: true))
            select(vc.callCustomerSegment, 1)
            XCTAssertFalse(vc.btnReadytoGo.isEnabled, "\(state): A came back as a new assignment — its old confirmation is gone")
            XCTAssertEqual(vc.gateBlockerLabel.text, DriverChecklistGate.blockerAssembly, "\(state)")

            let a = Unit(id: unitA, name: unitAName, tag: unitATag)
            vc.operationsSnapshot = { self.backToA(state: state) + [self.availabilityOp(unit: a, at: Date(), state: state)] }
            vc.refreshDerivedState()
            select(vc.callCustomerSegment, 1)
            XCTAssertTrue(vc.btnReadytoGo.isEnabled, "\(state): a fresh Available on the new episode reopens the gate")
        }
    }

    func testFuelAndKeysAnsweredForAUnitDoNotReviveWhenThatUnitComesBackAfterASwitch() throws {
        // Screen 2 answered fuel and keys for A. On the review the driver switched A → B → A without
        // returning to Screen 2 in between; back on Screen 2 both start unanswered (call kept).
        let vc = try screen2(try row(evidence: false), review: try review(go: true),
                             fleet: [try machine(unitB, requiresFuel: true, requiresKeys: true)])
        select(vc.callCustomerSegment, 1)
        select(vc.fuelSegment, 1)
        select(vc.keysSegment, 1)
        XCTAssertEqual(vc.fuelSegment.selectedSegmentIndex, 1)
        let a = Unit(id: unitA, name: unitAName, tag: unitATag)
        let base = Date().addingTimeInterval(-600)
        vc.operationsSnapshot = { [self.switchOp(to: self.unitB, at: base), self.switchOp(to: a, at: base.addingTimeInterval(60))] }
        vc.refreshDerivedState()
        XCTAssertEqual(vc.unitIdentityLabel.text, "\(unitAName) · #\(unitATag)", "the same unit, a new assignment")
        XCTAssertEqual(vc.fuelSegment.selectedSegmentIndex, UISegmentedControl.noSegment, "A's earlier fuel answer never speaks for A's new episode")
        XCTAssertEqual(vc.keysSegment.selectedSegmentIndex, UISegmentedControl.noSegment)
        XCTAssertEqual(vc.callCustomerSegment.selectedSegmentIndex, 1, "the call belongs to the mission and stays")
        XCTAssertFalse(vc.btnReadytoGo.isEnabled)

        let stored = DriverChecklistLocalState(dictionary: UserDefaults.standard.dictionary(forKey: DriverChecklistLocalState.key(orderProductUniqueId: productId, leg: DriverChecklistLocalState.legDelivery)))
        XCTAssertEqual(stored?.equipmentUniqueId, unitA)
        XCTAssertEqual(stored?.fuel, "")
        XCTAssertFalse((stored?.assignmentEpisode ?? "").isEmpty, "the record is bound to the episode the last switch started")
    }
}
