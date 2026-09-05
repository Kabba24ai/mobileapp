import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Pre-departure preparation lifecycle (2026-09).
///
/// The office-assigned Equipment ID is a DEFAULT, not a lock: while the machine
/// is in the yard the operator may substitute another eligible unit or restart a
/// saved-but-not-delivered checklist, straight from the Delivery Checklist.
/// Both discard a preparation CYCLE — which is what stops the outgoing unit's
/// answers, its staged lane and its walk-around video from following the
/// replacement machine out of the gate.
final class PreparationLifecycleTests: XCTestCase {

    // MARK: - Context builders (wire-shaped, so decoding is covered too)

    private func contextJSON(
        executionId: String = "ORD-CHK-AAAA-0001",
        status: String = "open",
        product: String = "ORD-PRD-0001",
        order: String = "ORD-0001",
        assignment: String = "soft",
        equipmentUniqueId: String = "EQP-A",
        equipmentCode: String = "101",
        preparedAnswerId: String? = nil,
        queueStaged: Bool = false,
        inTransit: Bool = false,
        isDelivered: Bool = false,
        executionStatus: String = "open",
        deliveryVideoPresent: Bool = false,
        leg: String = "delivery"
    ) -> Data {
        let body: [String: Any] = [
            "success": true,
            "data": [
                "identity": [
                    "checklist_execution_id": executionId,
                    "cycle": 1,
                    "status": status,
                    "leg": leg,
                    "order_unique_id": order,
                    "order_number": "7701",
                    "order_product_unique_id": product,
                    "product_name": "Skid Steer Rental",
                ],
                "equipment": [
                    "assignment": assignment,
                    "equipment_unique_id": equipmentUniqueId,
                    "equipment_code": equipmentCode,
                    "equipment_name": "Skid Steer",
                    "current_status": "available",
                ],
                "template": [
                    "template_id": "CAT-1", "template_name": "Skid Steer Checklist",
                    "revision": "rev-1", "question_source": "equipment_template",
                ],
                "requirements": [
                    "signature_required": true, "employee_required": true,
                    "store_required": false, "equipment_required": true,
                    "required_question_ids": ["CAQST-1"],
                ],
                "questions": [[
                    "question_id": "CAQST-1", "question_name": "Body damage", "text": "Any body damage?",
                    "delivery_text": "Any body damage?", "return_text": "Any body damage?",
                    "category": NSNull(), "required": true, "answer_type": "single_choice", "index": 1,
                    "answers": [[
                        "answer_id": "CAANS-1", "text": "No damage", "delivery_text": "No damage",
                        "return_text": "No damage", "amount": 0, "delivery_amount": 0, "return_amount": 0,
                        "is_damaged": false, "sync_texts": false, "index": 1,
                    ]],
                    "previous_answer_id": NSNull(), "previous_return_answer_id": NSNull(),
                    "prepared_answer_id": preparedAnswerId as Any? ?? NSNull(),
                ]],
                "operational": [
                    "hour_tracking": true, "is_product_clean": true, "rental_prepaid_cleaning": 0,
                    "start_hours": 0, "end_hours": 0, "fuel_initial_reading": "", "fuel_final_reading": "",
                    "delivery_clean_id": "", "return_clean_id": "", "delivery_notes": "", "pickup_notes": "",
                    "delivery_by": NSNull(), "pickup_by": NSNull(), "pickup_store_id": NSNull(),
                ],
                "server_state": [
                    "is_delivered": isDelivered, "is_returned": false,
                    "delivery_status": isDelivered ? "Delivered" : "Pending", "pickup_status": "Pending",
                    "queue_staged": queueStaged, "in_transit": inTransit,
                    "delivery_signature_present": false, "return_signature_present": false,
                    "execution_status": executionStatus,
                    "prepared_at": NSNull(), "completed_at": NSNull(), "captured_at": NSNull(),
                    "can_complete": true, "blocked_reason": NSNull(),
                    "delivery_video_present": deliveryVideoPresent,
                    "delivery_media_present": deliveryVideoPresent,
                ],
                "employee": NSNull(),
                "server_time": "2026-09-05T12:00:00+00:00",
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private func context(_ overrides: (inout [String: Any]) -> Void = { _ in }) throws -> ChecklistContext {
        try ChecklistContext.decode(envelopeData: contextJSON())
    }

    private func op(_ type: String,
                    order: String? = "ORD-0001",
                    product: String? = "ORD-PRD-0001",
                    execution: String? = nil,
                    state: SyncState = .pending,
                    payload: JSONValue = .object([:]),
                    assets: [SyncAsset] = [],
                    queuedAt: Date = Date()) -> SyncOperation {
        var op = SyncOperation(type: type, capturedAt: queuedAt, queuedAt: queuedAt,
                               identity: SyncBusinessIdentity(orderUniqueId: order,
                                                              orderProductUniqueId: product,
                                                              checklistExecutionId: execution),
                               payload: payload, assets: assets)
        op.state = state
        return op
    }

    private func videoAsset() -> SyncAsset {
        SyncAsset(relativePath: "video.mp4", mimeType: "video/mp4", fieldName: "media")
    }

    private func stageOp(product: String = "ORD-PRD-0001", state: SyncState = .pending, at: Date) -> SyncOperation {
        op(EffectiveFieldState.deliveryPrepareType, product: product, state: state,
           payload: .object(["mark_staged": .bool(true)]), queuedAt: at)
    }

    /// Core-only stand-ins for the app-layer handlers: they are literally
    /// `PreparationRequestFactory` / `ChecklistRequestFactory` calls, so the
    /// request shape and the engine's ordering are exercised for real.
    private struct SubstitutionHandler: SyncOperationHandler {
        var operationType: String { PreparationOperationBuilder.substitutionType }
        func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
            try PreparationRequestFactory.substitutionRequest(for: operation)
        }
    }

    private struct PrepareHandler: SyncOperationHandler {
        var operationType: String { EffectiveFieldState.deliveryPrepareType }
        func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
            try ChecklistRequestFactory.prepareRequest(for: operation)
        }
    }

    // ── 1–2. The office assignment is a DEFAULT, not a lock ──────────────

    func testAnOfficeAssignedUnitIsStillSubstitutableBeforeDeparture() throws {
        for assignment in ["hard", "soft", "selected", "none"] {
            let context = try ChecklistContext.decode(envelopeData: contextJSON(assignment: assignment))
            XCTAssertTrue(PreparationPolicy.maySubstituteEquipment(context),
                          "A \(assignment)-assigned unit must remain substitutable in the yard.")
            XCTAssertNil(PreparationPolicy.block(for: context))
        }
    }

    func testTheCurrentlyAssignedUnitIsTheOneToPreselect() throws {
        let context = try ChecklistContext.decode(envelopeData: contextJSON(equipmentUniqueId: "EQP-A"))
        XCTAssertEqual(context.equipment.equipmentUniqueId, "EQP-A")
        XCTAssertTrue(context.equipment.hasUnit)
        XCTAssertTrue(PreparationPolicy.isSameUnit(context, replacementUniqueId: "EQP-A"))
        XCTAssertFalse(PreparationPolicy.isSameUnit(context, replacementUniqueId: "EQP-B"))
    }

    // ── 3. Choosing the same unit changes nothing ────────────────────────

    func testChoosingTheAlreadyAssignedUnitEnqueuesNothing() throws {
        let store = try FileSyncOperationStore(rootDirectory: Fixtures.tempDirectory())
        let engine = makeEngine(store: store, client: FakeSyncHTTPClient())

        let capture = EquipmentSubstitutionCapture(
            orderUniqueId: "ORD-0001", orderProductUniqueId: "ORD-PRD-0001",
            supersededExecutionId: "ORD-CHK-AAAA-0001",
            previousEquipmentUniqueId: "EQP-A", replacementEquipmentUniqueId: "EQP-A",
            performedByUniqueId: "USR-1")

        XCTAssertNil(try PreparationOperationBuilder.enqueueSubstitution(capture, into: engine))
        XCTAssertTrue(engine.snapshot().isEmpty, "A no-op selection must never discard a checklist.")
    }

    // ── 4. Substitution is a canonical reassignment request ──────────────

    func testSubstitutionTargetsTheCanonicalQueueLineEndpoint() throws {
        let capture = EquipmentSubstitutionCapture(
            orderUniqueId: "ORD-0001", orderProductUniqueId: "ORD-PRD-0001",
            supersededExecutionId: "ORD-CHK-AAAA-0001",
            previousEquipmentUniqueId: "EQP-A", replacementEquipmentUniqueId: "EQP-B",
            performedByUniqueId: "USR-1", reason: "Reserved unit unavailable")

        let operation = SyncOperation(type: PreparationOperationBuilder.substitutionType,
                                      capturedAt: Date(),
                                      identity: PreparationOperationBuilder.identity(capture),
                                      payload: PreparationOperationBuilder.substitutionPayload(capture))
        let request = try PreparationRequestFactory.substitutionRequest(for: operation)

        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "queue-line/ORD-PRD-0001/switch-equipment",
                       "The checklist must reuse the canonical reassignment endpoint, never edit locally.")
        let body = request.jsonBody?.objectValue ?? [:]
        XCTAssertEqual(body["equipment_unique_id"]?.stringValue, "EQP-B")
        XCTAssertEqual(body["performed_by"]?.stringValue, "USR-1")
        XCTAssertEqual(body["reason"]?.stringValue, "Reserved unit unavailable")
        // The ordering key is the order product — the dependency this flow needs.
        XCTAssertEqual(operation.orderingKey, "ORD-PRD-0001")
    }

    // ── 5. Confirmations match what would actually be lost ───────────────

    func testConfirmationIsSkippedWhenThereIsNothingMeaningfulToDiscard() throws {
        let context = try self.context()
        XCTAssertEqual(PreparationPolicy.confirmation(for: context, hasLocalAnswers: false), .none)
        XCTAssertFalse(PreparationPolicy.hasPreparationToDiscard(context, hasLocalAnswers: false))
    }

    func testPartiallyEnteredAnswersRequireTheStartOverConfirmation() throws {
        let context = try self.context()
        XCTAssertEqual(PreparationPolicy.confirmation(for: context, hasLocalAnswers: true), .discardPartial)
        XCTAssertTrue(PreparationPolicy.hasPreparationToDiscard(context, hasLocalAnswers: true))
        XCTAssertTrue(PreparationPolicy.substitutionMessage(currentCode: "101", replacementCode: "205", confirmation: .discardPartial)
            .contains("Equipment 101"))
    }

    func testASavedChecklistRequiresThePreparedConfirmation() throws {
        let prepared = try ChecklistContext.decode(envelopeData: contextJSON(
            status: "prepared", preparedAnswerId: "CAANS-1", queueStaged: true, executionStatus: "prepared"))

        XCTAssertEqual(PreparationPolicy.confirmation(for: prepared, hasLocalAnswers: false), .discardPrepared)
        XCTAssertTrue(PreparationPolicy.mayRestartChecklist(prepared, hasLocalAnswers: false),
                      "A saved, non-final checklist is exactly what Delete / Start Over is for.")
        XCTAssertTrue(PreparationPolicy.substitutionMessage(currentCode: "101", replacementCode: "205", confirmation: .discardPrepared)
            .contains("saved checklist"))
    }

    // ── 6. Restart is offered only when there is something to restart ────

    func testRestartIsNotOfferedForAnUntouchedChecklist() throws {
        XCTAssertFalse(PreparationPolicy.mayRestartChecklist(try context(), hasLocalAnswers: false))
        XCTAssertTrue(PreparationPolicy.mayRestartChecklist(try context(), hasLocalAnswers: true))
    }

    // ── 7–8. The board returns to Pending on a discard ───────────────────

    func testASubstitutionRemovesTheLocalStagedEvidenceItWasBasedOn() {
        let t0 = Date()
        let ops = [
            stageOp(at: t0),
            op(PreparationOperationBuilder.substitutionType, execution: "ORD-CHK-AAAA-0001",
               queuedAt: t0.addingTimeInterval(10)),
        ]
        let overlay = QueueLineLocalOverlay.from(ops)

        XCTAssertFalse(overlay.isStagedLocally("ORD-PRD-0001"), "Staged Unit A → substitute → Pending.")
        XCTAssertFalse(overlay.isPendingStage("ORD-PRD-0001"))
        XCTAssertNil(overlay.attentionReason("ORD-PRD-0001"))
    }

    func testARestartRemovesTheLocalStagedEvidenceWithoutTouchingTheAssignment() {
        let t0 = Date()
        let restart = op(EffectiveFieldState.deliveryRestartType, execution: "ORD-CHK-AAAA-0001",
                         queuedAt: t0.addingTimeInterval(10))
        let overlay = QueueLineLocalOverlay.from([stageOp(at: t0), restart])

        XCTAssertFalse(overlay.isStagedLocally("ORD-PRD-0001"))
        // A restart carries no replacement unit — the assignment is untouched.
        XCTAssertNil(restart.payload["equipment_unique_id"]?.stringValue)
    }

    func testTheRestartRequestTargetsItsOwnExecution() throws {
        let capture = ChecklistRestartCapture(
            orderUniqueId: "ORD-0001", orderProductUniqueId: "ORD-PRD-0001",
            executionId: "ORD-CHK-AAAA-0001", leg: .delivery,
            equipmentUniqueId: "EQP-A", employeeUserId: 42)

        let operation = SyncOperation(type: PreparationOperationBuilder.restartType(.delivery),
                                      capturedAt: Date(),
                                      identity: PreparationOperationBuilder.identity(capture),
                                      payload: PreparationOperationBuilder.restartPayload(capture))
        let request = try PreparationRequestFactory.restartRequest(for: operation)

        XCTAssertEqual(request.path, "orders/checklists/ORD-CHK-AAAA-0001/reset")
        XCTAssertEqual(request.jsonBody?.objectValue?["order_product_unique_id"]?.stringValue, "ORD-PRD-0001")
        XCTAssertEqual(operation.orderingKey, "ORD-PRD-0001")
    }

    // ── 9–10. Physical cutoffs ───────────────────────────────────────────

    func testInTransitBlocksBothSubstitutionAndRestart() throws {
        let inTransit = try ChecklistContext.decode(envelopeData: contextJSON(
            status: "prepared", preparedAnswerId: "CAANS-1",
            queueStaged: true, inTransit: true, executionStatus: "prepared"))

        XCTAssertEqual(PreparationPolicy.block(for: inTransit), .inTransit)
        XCTAssertFalse(PreparationPolicy.maySubstituteEquipment(inTransit))
        XCTAssertFalse(PreparationPolicy.mayRestartChecklist(inTransit, hasLocalAnswers: true))
        XCTAssertTrue(PreparationLifecycle.Block.inTransit.message.contains("on its way"))
    }

    func testADeliveredChecklistIsPermanentAndBlocksBoth() throws {
        let delivered = try ChecklistContext.decode(envelopeData: contextJSON(
            status: "completed", isDelivered: true, executionStatus: "completed"))

        XCTAssertEqual(PreparationPolicy.block(for: delivered), .delivered)
        XCTAssertFalse(PreparationPolicy.maySubstituteEquipment(delivered))
        XCTAssertFalse(PreparationPolicy.mayRestartChecklist(delivered, hasLocalAnswers: true))
    }

    func testTheReturnLegHasNoPreDepartureCutoff() throws {
        let returnLeg = try ChecklistContext.decode(envelopeData: contextJSON(leg: "return"))
        XCTAssertNil(PreparationPolicy.block(for: returnLeg))
    }

    // ── 11. Multi-line isolation ─────────────────────────────────────────

    func testDiscardingOneProductsPreparationLeavesSiblingsStaged() {
        let t0 = Date()
        let ops = [
            stageOp(product: "ORD-PRD-A", at: t0),
            stageOp(product: "ORD-PRD-B", at: t0),
            op(PreparationOperationBuilder.substitutionType, product: "ORD-PRD-A",
               execution: "ORD-CHK-A", queuedAt: t0.addingTimeInterval(10)),
        ]
        let overlay = QueueLineLocalOverlay.from(ops)

        XCTAssertFalse(overlay.isStagedLocally("ORD-PRD-A"))
        XCTAssertTrue(overlay.isStagedLocally("ORD-PRD-B"), "A sibling line must keep its own preparation.")
    }

    // ── 12–13. Media follows the preparation cycle ───────────────────────

    func testTheOldCyclesLocalVideoDoesNotSatisfyTheReplacementUnit() {
        let t0 = Date()
        let videoForA = op(EffectiveFieldState.deliveryMediaType, execution: "ORD-CHK-A",
                           assets: [videoAsset()], queuedAt: t0)
        let substitution = op(PreparationOperationBuilder.substitutionType, execution: "ORD-CHK-A",
                              queuedAt: t0.addingTimeInterval(10))
        let ops = [videoForA, substitution]

        // While Unit A's cycle was active, its video satisfied.
        XCTAssertTrue(EffectiveFieldState.deliveryVideoSatisfied(
            serverHasVideo: false, operations: [videoForA],
            orderProductUniqueId: "ORD-PRD-0001", activeExecutionId: "ORD-CHK-A"))

        // After the substitution the active cycle is a NEW one — it has no video.
        XCTAssertFalse(EffectiveFieldState.deliveryVideoSatisfied(
            serverHasVideo: false, operations: ops,
            orderProductUniqueId: "ORD-PRD-0001", activeExecutionId: "ORD-CHK-B"),
            "Unit A's walk-around video must never let Unit B skip its own.")

        // And even without knowing the active cycle, a locally discarded cycle
        // cannot keep satisfying.
        XCTAssertFalse(EffectiveFieldState.deliveryVideoSatisfied(
            serverHasVideo: false, operations: ops, orderProductUniqueId: "ORD-PRD-0001"))
        XCTAssertTrue(EffectiveFieldState.supersededExecutionIds(in: ops).contains("ORD-CHK-A"))
    }

    func testAVideoCapturedForTheNewCycleSatisfiesItAgain() {
        let t0 = Date()
        let ops = [
            op(EffectiveFieldState.deliveryMediaType, execution: "ORD-CHK-A", assets: [videoAsset()], queuedAt: t0),
            op(PreparationOperationBuilder.substitutionType, execution: "ORD-CHK-A", queuedAt: t0.addingTimeInterval(10)),
            op(EffectiveFieldState.deliveryMediaType, execution: "ORD-CHK-B", assets: [videoAsset()], queuedAt: t0.addingTimeInterval(20)),
        ]
        XCTAssertTrue(EffectiveFieldState.deliveryVideoSatisfied(
            serverHasVideo: false, operations: ops,
            orderProductUniqueId: "ORD-PRD-0001", activeExecutionId: "ORD-CHK-B"))
    }

    func testSiblingProductsVideoStillNeverSatisfies() {
        let ops = [op(EffectiveFieldState.deliveryMediaType, product: "ORD-PRD-OTHER",
                      execution: "ORD-CHK-B", assets: [videoAsset()])]
        XCTAssertFalse(EffectiveFieldState.deliveryVideoSatisfied(
            serverHasVideo: false, operations: ops,
            orderProductUniqueId: "ORD-PRD-0001", activeExecutionId: "ORD-CHK-B"))
    }

    // ── 14. Server media presence is reported per cycle ──────────────────

    func testTheContextReportsServerVideoPresenceForTheActiveCycleOnly() throws {
        let withVideo = try ChecklistContext.decode(envelopeData: contextJSON(deliveryVideoPresent: true))
        XCTAssertEqual(withVideo.serverState.deliveryVideoPresent, true)

        let freshCycle = try ChecklistContext.decode(envelopeData: contextJSON(
            executionId: "ORD-CHK-BBBB-0002", deliveryVideoPresent: false))
        XCTAssertEqual(freshCycle.serverState.deliveryVideoPresent, false,
                       "A fresh cycle must report no video even though the order product has one.")
    }

    func testACachedPreUpgradeContextStillDecodes() throws {
        // Older cached snapshots have no delivery_video_present key at all.
        var json = try JSONSerialization.jsonObject(with: contextJSON()) as! [String: Any]
        var data = json["data"] as! [String: Any]
        var serverState = data["server_state"] as! [String: Any]
        serverState.removeValue(forKey: "delivery_video_present")
        serverState.removeValue(forKey: "delivery_media_present")
        data["server_state"] = serverState
        json["data"] = data

        let context = try ChecklistContext.decode(envelopeData: try JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(context.serverState.deliveryVideoPresent)
    }

    // ── 15–16. Re-staging the replacement, and stale evidence ────────────

    func testTheReplacementUnitReStagesOnlyAfterItsOwnSave() {
        let t0 = Date()
        let ops = [
            stageOp(at: t0),                                                                    // Unit A staged
            op(PreparationOperationBuilder.substitutionType, execution: "ORD-CHK-A",
               queuedAt: t0.addingTimeInterval(10)),                                            // → Pending
            stageOp(at: t0.addingTimeInterval(20)),                                             // Unit B Save
        ]
        let overlay = QueueLineLocalOverlay.from(ops)

        XCTAssertTrue(overlay.isStagedLocally("ORD-PRD-0001"), "A fresh complete Save stages the replacement.")
        XCTAssertTrue(overlay.isPendingStage("ORD-PRD-0001"))
    }

    func testAnOlderStagingRecordCannotResurrectStagedAfterADiscard() {
        let t0 = Date()
        // Even a SYNCED (server-confirmed) staging record from the old cycle
        // must not out-vote the later discard.
        let ops = [
            stageOp(state: .synced, at: t0),
            op(EffectiveFieldState.deliveryRestartType, execution: "ORD-CHK-A", state: .synced,
               queuedAt: t0.addingTimeInterval(10)),
        ]
        XCTAssertFalse(QueueLineLocalOverlay.from(ops).isStagedLocally("ORD-PRD-0001"))
    }

    func testADiscardDoesNotClearACompletedDelivery() {
        let t0 = Date()
        let ops = [
            op(EffectiveFieldState.deliveryCompleteType, queuedAt: t0),
            op(EffectiveFieldState.deliveryRestartType, execution: "ORD-CHK-A", queuedAt: t0.addingTimeInterval(10)),
        ]
        XCTAssertTrue(QueueLineLocalOverlay.from(ops).isCompletedLocally("ORD-PRD-0001"),
                      "A signed completion is permanent — a restart never erases it locally.")
    }

    // ── 17. Dependent ordering through the engine ────────────────────────

    func testASubstitutionAlwaysReachesLaravelBeforeThePrepareThatFollowsIt() throws {
        let store = try FileSyncOperationStore(rootDirectory: Fixtures.tempDirectory())
        let client = FakeSyncHTTPClient()
        client.defaultResult = Fixtures.ok()

        // Latency keeps the substitution IN FLIGHT while the prepare is queued,
        // so the ordering gate (not luck) is what decides the send order.
        client.latency = 0.05

        let engine = SyncEngine(store: store, httpClient: client,
                                handlers: [SubstitutionHandler(), PrepareHandler()],
                                policy: SyncRetryPolicy(backoffSchedule: [0.05]))

        let substitution = EquipmentSubstitutionCapture(
            orderUniqueId: "ORD-0001", orderProductUniqueId: "ORD-PRD-0001",
            supersededExecutionId: "ORD-CHK-A",
            previousEquipmentUniqueId: "EQP-A", replacementEquipmentUniqueId: "EQP-B",
            performedByUniqueId: "USR-1")
        _ = try PreparationOperationBuilder.enqueueSubstitution(substitution, into: engine)

        // The Save for the REPLACEMENT unit's fresh cycle, queued straight after.
        _ = try engine.enqueue(type: EffectiveFieldState.deliveryPrepareType,
                           payload: .object([
                               "checklist_execution_id": .string("ORD-CHK-B"),
                               "order_product_unique_id": .string("ORD-PRD-0001"),
                               "leg": .string("delivery"),
                               "answers": .array([]),
                               "mark_staged": .bool(true),
                           ]),
                           identity: SyncBusinessIdentity(orderUniqueId: "ORD-0001",
                                                          orderProductUniqueId: "ORD-PRD-0001",
                                                          checklistExecutionId: "ORD-CHK-B"),
                           capturedAt: Date())

        waitUntil("both operations sync") { client.requestCount >= 2 }

        let paths = client.recorded.map(\.path)
        XCTAssertEqual(paths.first, "queue-line/ORD-PRD-0001/switch-equipment",
                       "A prepare for the new cycle must never overtake the substitution that created it.")
        XCTAssertEqual(paths.dropFirst().first, "orders/checklists/ORD-CHK-B/prepare")
    }

    // ── 18. Terminal rejection preserves the operator's work ─────────────

    func testATerminallyRejectedSubstitutionParksAsNeedsAttentionAndKeepsEvidence() throws {
        let store = try FileSyncOperationStore(rootDirectory: Fixtures.tempDirectory())
        let client = FakeSyncHTTPClient()
        client.defaultResult = Fixtures.failure(422, code: "QUEUE_ITEM_IN_TRANSIT", retryable: false,
                                                message: "This equipment is already on its way to the customer.")

        let engine = SyncEngine(store: store, httpClient: client,
                                handlers: [SubstitutionHandler()],
                                policy: SyncRetryPolicy(backoffSchedule: [0.05]))

        let capture = EquipmentSubstitutionCapture(
            orderUniqueId: "ORD-0001", orderProductUniqueId: "ORD-PRD-0001",
            supersededExecutionId: "ORD-CHK-A",
            previousEquipmentUniqueId: "EQP-A", replacementEquipmentUniqueId: "EQP-B",
            performedByUniqueId: "USR-1")
        let queued = try PreparationOperationBuilder.enqueueSubstitution(capture, into: engine)
        XCTAssertNotNil(queued)

        waitUntil("operation parks") {
            engine.snapshot().first?.state == .needsAttention
        }

        let parked = engine.snapshot().first
        XCTAssertEqual(parked?.state, .needsAttention)
        XCTAssertNotNil(parked?.attentionReason, "The operator must be told, never silently dropped.")
        XCTAssertEqual(parked?.payload["equipment_unique_id"]?.stringValue, "EQP-B",
                       "The operator's decision is preserved intact for the office to reconcile.")
        // Still durable evidence — the board reflects what the operator did.
        XCTAssertTrue(EffectiveFieldState.countsAsDurableEvidence(.needsAttention))
    }
}
