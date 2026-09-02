import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Checklist-driven Queue Line (2026-09): the Delivery Checklist is the ONE
/// preparation controller. These tests pin the Sync-Core side of that rule —
/// the staging Save is a durable checklist prepare with `mark_staged`, the
/// board's lanes are an overlay over those SAME operations, and the retired
/// queue_line.mark_staged path no longer exists.
final class QueueLineOperationTests: XCTestCase {

    private var dir: URL!
    private var client: FakeSyncHTTPClient!

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
        client = FakeSyncHTTPClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: Fixtures

    private func context(product: String, leg: ChecklistLeg = .delivery, execution: String = "ORD-CHK-QL-0001", inTransit: Bool = false) -> ChecklistContext {
        let json: [String: Any] = [
            "identity": ["checklist_execution_id": execution, "cycle": 1, "status": "open", "leg": leg.rawValue,
                         "order_unique_id": "ORD-0001", "order_number": "7701", "order_product_unique_id": product, "product_name": "Skid Steer"],
            "equipment": ["assignment": "soft", "equipment_unique_id": "EQP-UNIT-0001", "equipment_code": "EQP-1", "equipment_name": "Skid",
                          "current_status": "available", "power_source_type": "diesel", "has_def": "No", "hour_tracking": "Yes"],
            "template": ["template_id": "CATQS-0001", "template_name": "T", "revision": "abcdef0123456789", "question_source": "equipment_template"],
            "requirements": ["signature_required": true, "employee_required": true, "store_required": leg == .return, "equipment_required": leg == .delivery,
                             "required_question_ids": ["CAQST-Q1"]],
            "questions": [
                ["question_id": "CAQST-Q1", "question_name": "Damage", "text": "Any damage?", "delivery_text": "Any damage?", "return_text": "Any damage now?",
                 "category": NSNull(), "required": true, "answer_type": "single_choice", "index": 1,
                 "answers": [["answer_id": "CAANS-A1", "text": "No", "delivery_text": "No", "return_text": "No", "amount": 0, "delivery_amount": 0, "return_amount": 0, "is_damaged": false, "sync_texts": false, "index": 1]],
                 "previous_answer_id": NSNull(), "previous_return_answer_id": NSNull(), "prepared_answer_id": NSNull()],
                ["question_id": "CAQST-Q2", "question_name": "Keys", "text": "Keys?", "delivery_text": "Keys?", "return_text": "Keys back?",
                 "category": NSNull(), "required": false, "answer_type": "single_choice", "index": 2,
                 "answers": [["answer_id": "CAANS-B1", "text": "Yes", "delivery_text": "Yes", "return_text": "Yes", "amount": 0, "delivery_amount": 0, "return_amount": 0, "is_damaged": false, "sync_texts": false, "index": 1]],
                 "previous_answer_id": NSNull(), "previous_return_answer_id": NSNull(), "prepared_answer_id": NSNull()],
            ],
            "operational": ["hour_tracking": true, "is_product_clean": false, "rental_prepaid_cleaning": 0, "start_hours": 0, "end_hours": 0,
                            "fuel_initial_reading": "", "fuel_final_reading": "", "delivery_clean_id": "", "return_clean_id": "", "delivery_notes": "", "pickup_notes": "",
                            "delivery_by": NSNull(), "pickup_by": NSNull(), "pickup_store_id": NSNull()],
            "server_state": ["is_delivered": false, "is_returned": false, "delivery_status": "Pending", "pickup_status": "Pending",
                             "delivery_signature_present": false, "return_signature_present": false, "execution_status": "open",
                             "prepared_at": NSNull(), "completed_at": NSNull(), "captured_at": NSNull(), "can_complete": true, "blocked_reason": NSNull(),
                             "queue_staged": inTransit, "in_transit": inTransit],
            "employee": ["user_id": 7, "unique_id": "PER-0007", "full_name": "Field Employee"],
            "server_time": "2026-08-25T12:00:00+00:00",
        ]
        return try! ChecklistContext.decode(envelopeData: Fixtures.json(["success": true, "data": json]))
    }

    /// The explicit checklist Save for one product: complete answers + staging intent.
    private func saveCapture(_ ctx: ChecklistContext, complete: Bool = true, markStaged: Bool = true) -> ChecklistCapture {
        var c = ChecklistCapture(context: ctx,
                                 answers: complete ? ["CAQST-Q1": "CAANS-A1", "CAQST-Q2": "CAANS-B1"] : ["CAQST-Q2": "CAANS-B1"],
                                 employeeUserId: 7,
                                 equipmentUniqueId: ctx.equipment.equipmentUniqueId)
        c.markStaged = markStaged
        c.capturedAt = Date(timeIntervalSince1970: 1_787_685_243)
        return c
    }

    private func engine() -> SyncEngine {
        makeEngine(store: try! FileSyncOperationStore(rootDirectory: dir), client: client, handler: QueueLinePrepareTestHandler())
    }

    // MARK: Save = prepare + staging intent (delivery leg only)

    func testTheExplicitSaveCarriesTheStagingIntentOnTheDeliveryLegOnly() {
        let delivery = ChecklistOperationBuilder.preparePayload(saveCapture(context(product: "ORD-SCH-A")))
        XCTAssertEqual(delivery["mark_staged"]?.boolValue, true, "the Save IS the Pending → Staged request")
        XCTAssertEqual(delivery["checklist_execution_id"]?.stringValue, "ORD-CHK-QL-0001")

        let progress = ChecklistOperationBuilder.preparePayload(saveCapture(context(product: "ORD-SCH-A"), markStaged: false))
        XCTAssertNil(progress["mark_staged"], "a background progress sync never stages")

        let returnLeg = ChecklistOperationBuilder.preparePayload(saveCapture(context(product: "ORD-SCH-A", leg: .return), markStaged: true))
        XCTAssertNil(returnLeg["mark_staged"], "the return leg has no queue semantics")
    }

    func testChecklistCompletenessMirrorsTheRequiredQuestions() {
        XCTAssertTrue(saveCapture(context(product: "ORD-SCH-A"), complete: true).isChecklistComplete)
        XCTAssertFalse(saveCapture(context(product: "ORD-SCH-A"), complete: false).isChecklistComplete,
                       "the required question is unanswered — the phone must not request staging")
    }

    func testTheContextCarriesTheInTransitGuard() {
        XCTAssertEqual(context(product: "ORD-SCH-A", inTransit: true).serverState.inTransit, true)
        XCTAssertEqual(context(product: "ORD-SCH-A").serverState.inTransit, false)
    }

    // MARK: Offline → relaunch → reconnect (the staging Save is durable)

    func testAnOfflineStagingSaveIsDurableSurvivesRelaunchAndSyncsOnReconnect() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let first = engine()
        let op = try ChecklistOperationBuilder.enqueuePrepare(saveCapture(context(product: "ORD-SCH-A")), into: first, operationId: "QL-SAVE-0001")
        waitUntil("first attempt") { self.client.requestCount >= 1 }
        XCTAssertEqual(first.operation(id: op.id)?.state, .pending, "offline keeps the Save pending, never drops it")

        // "Force quit": a brand-new engine over the same directory.
        let second = engine()
        XCTAssertEqual(second.operation(id: op.id)?.state, .pending)
        XCTAssertEqual(second.operation(id: op.id)?.payload["mark_staged"]?.boolValue, true)
        XCTAssertTrue(QueueLineLocalOverlay.from(second.snapshot()).isStagedLocally("ORD-SCH-A"),
                      "the board shows Staged from the durable evidence, before any server contact")

        // Reconnect: Kabba accepts and stages.
        client.defaultResult = Fixtures.ok(["success": true, "data": ["checklist_execution_id": "ORD-CHK-QL-0001", "status": "prepared",
                                                                       "queue": ["governs": true, "status": "staged", "staged": true, "complete": true, "unstaged": false]], "request_id": "srv-1"])
        second.kick(reason: "reconnect", ignoreBackoff: true)
        waitUntil("synced") { second.operation(id: op.id)?.state == .synced }
        XCTAssertEqual(client.recorded.last?.headers["X-Operation-Id"], op.id, "the SAME operation id after relaunch")
        XCTAssertEqual(client.recorded.last?.path, "orders/checklists/ORD-CHK-QL-0001/prepare")
        XCTAssertTrue(QueueLineLocalOverlay.from(second.snapshot()).isStagedLocally("ORD-SCH-A"),
                      "acknowledged evidence is retained — a stale feed can never un-stage the card")
    }

    func testMultiLineOrderSavesStayIsolatedPerProduct() throws {
        client.defaultResult = Fixtures.ok(["success": true, "data": ["status": "prepared"], "request_id": "srv-3"])
        let e = engine()
        let a = try ChecklistOperationBuilder.enqueuePrepare(saveCapture(context(product: "ORD-SCH-A", execution: "ORD-CHK-QL-000A")), into: e)
        let b = try ChecklistOperationBuilder.enqueuePrepare(saveCapture(context(product: "ORD-SCH-B", execution: "ORD-CHK-QL-000B"), markStaged: false), into: e)
        waitUntil("both synced") { e.operation(id: a.id)?.state == .synced && e.operation(id: b.id)?.state == .synced }

        let overlay = QueueLineLocalOverlay.from(e.snapshot())
        XCTAssertTrue(overlay.isStagedLocally("ORD-SCH-A"))
        XCTAssertFalse(overlay.isStagedLocally("ORD-SCH-B"), "B's partial progress never stages B")
        let paths = Set(client.recorded.map { $0.path })
        XCTAssertEqual(paths, ["orders/checklists/ORD-CHK-QL-000A/prepare", "orders/checklists/ORD-CHK-QL-000B/prepare"])
    }

    func testATerminallyRejectedSaveParksWithTheWorkPreserved() throws {
        client.defaultResult = Fixtures.failure(422, code: "CHECKLIST_INCOMPLETE_FOR_STAGING", retryable: false,
                                                message: "Every required Delivery Checklist question must be answered before this equipment can be marked as Staged.")
        let e = engine()
        let op = try ChecklistOperationBuilder.enqueuePrepare(saveCapture(context(product: "ORD-SCH-A")), into: e)
        waitUntil("needs attention") { e.operation(id: op.id)?.state == .needsAttention }
        XCTAssertEqual(e.operation(id: op.id)?.attempts.lastErrorCode, "CHECKLIST_INCOMPLETE_FOR_STAGING")
        XCTAssertEqual(client.requestCount, 1, "a permanent rejection is not hammered")

        let overlay = QueueLineLocalOverlay.from(e.snapshot())
        XCTAssertNotNil(overlay.attentionReason("ORD-SCH-A"), "the board shows the Sync Issue")
        XCTAssertTrue(overlay.isStagedLocally("ORD-SCH-A"), "the employee's work stands until the office/board resolves it")
    }

    // MARK: Board overlay (lanes + chips from checklist evidence)

    private func op(_ type: String, product: String, state: SyncState, payload: JSONValue = .object([:])) -> SyncOperation {
        var operation = SyncOperation(type: type, capturedAt: Date(),
                                      identity: SyncBusinessIdentity(orderProductUniqueId: product), payload: payload)
        operation.state = state
        if state == .needsAttention { operation.attentionReason = "Rejected by Kabba" }
        return operation
    }

    func testOverlayLanesComeFromChecklistEvidenceOnly() {
        let stagedPayload: JSONValue = .object(["mark_staged": .bool(true)])
        let operations = [
            op(EffectiveFieldState.deliveryPrepareType, product: "P1", state: .pending, payload: stagedPayload),       // Save on its way
            op(EffectiveFieldState.deliveryPrepareType, product: "P2", state: .synced, payload: stagedPayload),        // Save confirmed
            op(EffectiveFieldState.deliveryPrepareType, product: "P3", state: .pending),                                // partial progress — invisible
            op(EffectiveFieldState.deliveryCompleteType, product: "P4", state: .pending),                               // signed completion
            op(EffectiveFieldState.returnCompleteType, product: "P5", state: .pending),                                 // return leg — not this board's lane
            op(EffectiveFieldState.driverChecklistType, product: "P6", state: .synced,
               payload: .object(["checklist_type": .string("delivery"), "equipment_driver_status": .string("On My Way")])),
        ]

        let overlay = QueueLineLocalOverlay.from(operations)
        XCTAssertTrue(overlay.isStagedLocally("P1"))
        XCTAssertTrue(overlay.isPendingStage("P1"))
        XCTAssertTrue(overlay.isStagedLocally("P2"))
        XCTAssertFalse(overlay.isPendingStage("P2"), "confirmed — no Pending Sync chip")
        XCTAssertFalse(overlay.isStagedLocally("P3"), "partial progress never moves a lane")
        XCTAssertTrue(overlay.isCompletedLocally("P4"))
        XCTAssertFalse(overlay.isCompletedLocally("P5"))
        XCTAssertTrue(overlay.isInTransitLocally("P6"), "this phone durably recorded the departure")
    }

    func testANewerSaveSupersedesARejectionAndCompletionEndsStagingChatter() {
        let stagedPayload: JSONValue = .object(["mark_staged": .bool(true)])
        let overlay = QueueLineLocalOverlay.from([
            op(EffectiveFieldState.deliveryPrepareType, product: "P1", state: .needsAttention, payload: stagedPayload),
            op(EffectiveFieldState.deliveryPrepareType, product: "P1", state: .pending, payload: stagedPayload),
            op(EffectiveFieldState.deliveryPrepareType, product: "P2", state: .needsAttention, payload: stagedPayload),
            op(EffectiveFieldState.deliveryCompleteType, product: "P2", state: .pending),
            op(EffectiveFieldState.driverChecklistType, product: "P2", state: .synced,
               payload: .object(["checklist_type": .string("delivery"), "equipment_driver_status": .string("On My Way")])),
        ])
        XCTAssertNil(overlay.attentionReason("P1"), "a newer pending Save supersedes the rejection")
        XCTAssertTrue(overlay.isPendingStage("P1"))
        XCTAssertTrue(overlay.isCompletedLocally("P2"))
        XCTAssertNil(overlay.attentionReason("P2"), "a completed item is past staging chatter")
        XCTAssertFalse(overlay.isPendingStage("P2"))
        XCTAssertFalse(overlay.isInTransitLocally("P2"), "never Delivered + In Transit")
    }

    // MARK: Freshness line (unchanged behavior)

    func testFreshnessLineDistinguishesFreshCachedAndPendingStates() {
        let now = Date(timeIntervalSince1970: 1_787_685_243)
        XCTAssertEqual(QueueLineFreshness.line(lastServerSyncAt: now.addingTimeInterval(-10), lastRefreshFailed: false, pendingCount: 0, now: now), "Updated just now")
        XCTAssertEqual(QueueLineFreshness.line(lastServerSyncAt: now.addingTimeInterval(-300), lastRefreshFailed: false, pendingCount: 2, now: now), "Updated 5 min ago · 2 changes pending sync")
        XCTAssertTrue(QueueLineFreshness.line(lastServerSyncAt: now.addingTimeInterval(-300), lastRefreshFailed: true, pendingCount: 1, now: now).hasPrefix("Offline · showing the list saved at "))
        XCTAssertEqual(QueueLineFreshness.line(lastServerSyncAt: nil, lastRefreshFailed: true, pendingCount: 0, now: now), "Offline · no saved list yet")
    }
}

/// Core-only stand-in for the app's ChecklistPrepareSyncHandler (same request factory, session always present).
struct QueueLinePrepareTestHandler: SyncOperationHandler {
    var operationType: String { EffectiveFieldState.deliveryPrepareType }
    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        try ChecklistRequestFactory.prepareRequest(for: operation)
    }
}
