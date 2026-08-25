import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class ChecklistOperationTests: XCTestCase {

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

    private func context(product: String, leg: ChecklistLeg = .delivery, execution: String = "ORD-CHK-TEST-0001", assignment: String = "soft", unit: String? = "EQP-UNIT-0001") -> ChecklistContext {
        let json: [String: Any] = [
            "identity": ["checklist_execution_id": execution, "cycle": 1, "status": "open", "leg": leg.rawValue,
                         "order_unique_id": "ORD-0001", "order_number": "7701", "order_product_unique_id": product, "product_name": "Skid Steer"],
            "equipment": ["assignment": assignment, "equipment_unique_id": unit as Any, "equipment_code": "EQP-1", "equipment_name": "Skid",
                          "current_status": "available", "power_source_type": "diesel", "has_def": "No", "hour_tracking": "Yes"],
            "template": ["template_id": "CATQS-0001", "template_name": "T", "revision": "abcdef0123456789", "question_source": "equipment_template"],
            "requirements": ["signature_required": true, "employee_required": true, "store_required": leg == .return, "equipment_required": leg == .delivery,
                             "required_question_ids": ["CAQST-Q1"]],
            "questions": [
                ["question_id": "CAQST-Q1", "question_name": "Damage", "text": "Any damage?", "delivery_text": "Any damage?", "return_text": "Any damage now?",
                 "category": NSNull(), "required": true, "answer_type": "single_choice", "index": 1,
                 "answers": [["answer_id": "CAANS-A1", "text": "No", "delivery_text": "No", "return_text": "No", "amount": 0, "delivery_amount": 0, "return_amount": 0, "is_damaged": false, "sync_texts": false, "index": 1],
                             ["answer_id": "CAANS-A2", "text": "Yes", "delivery_text": "Yes", "return_text": "Yes", "amount": 150, "delivery_amount": 0, "return_amount": 150, "is_damaged": true, "sync_texts": false, "index": 2]],
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
                             "prepared_at": NSNull(), "completed_at": NSNull(), "captured_at": NSNull(), "can_complete": true, "blocked_reason": NSNull()],
            "employee": ["user_id": 7, "unique_id": "PER-0007", "full_name": "Field Employee"],
            "server_time": "2026-08-25T12:00:00+00:00",
        ]
        return try! ChecklistContext.decode(envelopeData: Fixtures.json(["success": true, "data": json]))
    }

    private func capture(_ ctx: ChecklistContext, answers: [String: String] = ["CAQST-Q1": "CAANS-A1", "CAQST-Q2": "CAANS-B1"], employee: Int = 7) -> ChecklistCapture {
        var c = ChecklistCapture(context: ctx, answers: answers, employeeUserId: employee, equipmentUniqueId: ctx.equipment.equipmentUniqueId)
        c.note = "north gate"
        c.startHours = "120.5"
        c.capturedAt = Date(timeIntervalSince1970: 1_787_685_243)
        return c
    }

    // MARK: Payload

    func testCompletionPayloadCarriesIdentityCanonicalAnswersAndSignatureIdButNoBytes() throws {
        let ctx = context(product: "ORD-SCH-A")
        let payload = ChecklistOperationBuilder.completionPayload(capture(ctx), signatureClientMediaId: "sig-1")

        XCTAssertEqual(payload["checklist_execution_id"]?.stringValue, "ORD-CHK-TEST-0001")
        XCTAssertEqual(payload["order_product_unique_id"]?.stringValue, "ORD-SCH-A")
        XCTAssertEqual(payload["leg"]?.stringValue, "delivery")
        XCTAssertEqual(payload["user_id"]?.intValue, 7)
        XCTAssertEqual(payload["equipment_unique_id"]?.stringValue, "EQP-UNIT-0001")
        XCTAssertEqual(payload["context_revision"]?.stringValue, "abcdef0123456789")
        XCTAssertEqual(payload["signature_client_media_id"]?.stringValue, "sig-1")
        XCTAssertEqual(payload["start_hours"]?.stringValue, "120.5")
        XCTAssertNil(payload["end_hours"], "return-only fields stay out of a delivery payload")
        let answers = payload["answers"]?.arrayValue ?? []
        XCTAssertEqual(answers.count, 2)
        XCTAssertEqual(answers[0]["question_id"]?.stringValue, "CAQST-Q1")
        XCTAssertEqual(answers[0]["answer_id"]?.stringValue, "CAANS-A1")
        XCTAssertNil(payload["signature_media"], "the signature is an asset, never an inline blob")
    }

    func testLocalValidationMirrorsTheServerRules() {
        let ctx = context(product: "ORD-SCH-A")
        XCTAssertEqual(capture(ctx).localValidationProblems(), [])
        XCTAssertFalse(capture(ctx, answers: ["CAQST-Q2": "CAANS-B1"]).localValidationProblems().isEmpty, "required Q1 missing")
        XCTAssertFalse(capture(ctx, answers: ["CAQST-Q1": "CAANS-B1"]).localValidationProblems().isEmpty, "answer belongs to another question")
        XCTAssertFalse(capture(ctx, employee: 0).localValidationProblems().isEmpty, "employee required")
        var noUnit = capture(context(product: "ORD-SCH-A", assignment: "none", unit: nil))
        noUnit.equipmentUniqueId = nil
        XCTAssertTrue(noUnit.localValidationProblems().contains("Equipment not selected"))
    }

    // MARK: One operation per product

    func testTwoProductsProduceTwoOperationsEachWithItsOwnSignatureAndExecution() throws {
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let engine = makeEngine(store: store, client: client)   // offline: operations stay pending

        let a = try ChecklistOperationBuilder.enqueueCompletion(capture(context(product: "ORD-SCH-A", execution: "ORD-CHK-A")), signatureJPEG: Data("SIG-A".utf8), into: engine)
        let b = try ChecklistOperationBuilder.enqueueCompletion(capture(context(product: "ORD-SCH-B", execution: "ORD-CHK-B")), signatureJPEG: Data("SIG-B".utf8), into: engine)

        XCTAssertEqual(engine.snapshot().count, 2, "exactly one operation per product — never product × otherData")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.identity.checklistExecutionId, "ORD-CHK-A")
        XCTAssertEqual(b.identity.checklistExecutionId, "ORD-CHK-B")
        XCTAssertEqual(a.assets.count, 1)
        XCTAssertEqual(b.assets.count, 1)
        XCTAssertNotEqual(a.assets[0].relativePath, b.assets[0].relativePath)
        XCTAssertEqual(try Data(contentsOf: store.assetsDirectory.appendingPathComponent(a.assets[0].relativePath)), Data("SIG-A".utf8))
        XCTAssertEqual(try Data(contentsOf: store.assetsDirectory.appendingPathComponent(b.assets[0].relativePath)), Data("SIG-B".utf8))
        XCTAssertEqual(a.payload["signature_client_media_id"]?.stringValue, a.assets[0].clientMediaId)
        XCTAssertEqual(a.capturedAt.timeIntervalSince1970, 1_787_685_243, accuracy: 1)

        // Survives relaunch with the signature file still present.
        let relaunched = try FileSyncOperationStore(rootDirectory: dir)
        XCTAssertEqual(try relaunched.loadAll().map(\.id).sorted(), [a.id, b.id].sorted())
    }

    // MARK: Request + multipart

    func testCompleteRequestTargetsTheExecutionAndCarriesOperationIdCapturedAtAndSignature() throws {
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let engine = makeEngine(store: store, client: client)
        let op = try ChecklistOperationBuilder.enqueueCompletion(capture(context(product: "ORD-SCH-A")), signatureJPEG: Data("SIG".utf8), into: engine)

        let request = try ChecklistRequestFactory.completeRequest(for: op)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "orders/checklists/ORD-CHK-TEST-0001/complete")
        XCTAssertEqual(request.headers["X-Operation-Id"], op.id)
        XCTAssertEqual(request.jsonBody?["operation_id"]?.stringValue, op.id)
        XCTAssertEqual(request.jsonBody?["captured_at"]?.stringValue, KabbaISO8601.string(from: op.capturedAt))
        XCTAssertEqual(request.attachments.count, 1)

        let body = try SyncMultipartBuilder.build(fields: request.jsonBody, assets: request.attachments, assetsDirectory: store.assetsDirectory, directory: dir)
        defer { try? FileManager.default.removeItem(at: body.fileURL) }
        let text = String(decoding: try Data(contentsOf: body.fileURL), as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"answers[0][question_id]\"\r\n\r\nCAQST-Q1"), "bracket notation, not a JSON string")
        XCTAssertTrue(text.contains("name=\"answers[1][answer_id]\"\r\n\r\nCAANS-B1"))
        XCTAssertTrue(text.contains("name=\"operation_id\"\r\n\r\n\(op.id)"))
        XCTAssertTrue(text.contains("name=\"signature_media\"; filename=\""))
        XCTAssertTrue(text.contains("Content-Type: image/jpeg\r\n\r\nSIG\r\n"))
        XCTAssertTrue(text.hasSuffix("--\(body.boundary)--\r\n"))
        XCTAssertTrue(body.contentType.hasPrefix("multipart/form-data; boundary="))
    }

    func testMultipartBuilderRefusesAMissingAssetInsteadOfSendingAnIncompleteChecklist() throws {
        let asset = SyncAsset(clientMediaId: "x", relativePath: "missing/sig.jpg", mimeType: "image/jpeg", fieldName: "signature_media")
        XCTAssertThrowsError(try SyncMultipartBuilder.build(fields: .object(["a": .string("1")]), assets: [asset], assetsDirectory: dir, directory: dir)) { error in
            XCTAssertEqual(error as? SyncMultipartError, .assetMissing("missing/sig.jpg"))
        }
    }

    func testFormFieldFlatteningHandlesNestingBooleansAndNulls() {
        let fields = SyncMultipartBuilder.formFields(from: .object([
            "complete_leg": .bool(false), "n": .number(3), "skip": .null,
            "answers": .array([.object(["question_id": .string("Q"), "amount": .string("1.50")])]),
        ]))
        XCTAssertEqual(fields.map { "\($0.name)=\($0.value)" }, ["answers[0][amount]=1.50", "answers[0][question_id]=Q", "complete_leg=0", "n=3"])
    }

    // MARK: Prepare

    func testPreparePayloadOmitsAnUnknownEmployeeAndAllowsPartialAnswers() {
        let payload = ChecklistOperationBuilder.preparePayload(capture(context(product: "ORD-SCH-A"), answers: ["CAQST-Q1": "CAANS-A1"], employee: 0))
        XCTAssertNil(payload["user_id"])
        XCTAssertEqual(payload["answers"]?.arrayValue?.count, 1)
        XCTAssertEqual(ChecklistOperationBuilder.prepareType(.delivery), "delivery_checklist.prepare")
        XCTAssertEqual(ChecklistOperationBuilder.completeType(.return), "return_checklist.complete")
    }

    // MARK: Engine round trip with the canonical envelope

    func testACompletionSyncsAndAReplayedRetryConverges() throws {
        client.enqueue(.failure(APIError.transport(.connectionLost)),
                       Fixtures.ok(["success": true, "replayed": true, "data": ["status": "completed", "leg": "delivery"], "request_id": "srv-2"],
                                   headers: ["X-Idempotent-Replay": "true", "X-Request-Id": "srv-2"]))
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let handler = TestChecklistHandler()
        let engine = SyncEngine(store: store, httpClient: client, handlers: [handler], policy: SyncRetryPolicy(backoffSchedule: [0.05]))
        let op = try ChecklistOperationBuilder.enqueueCompletion(capture(context(product: "ORD-SCH-A")), signatureJPEG: Data("SIG".utf8), into: engine)

        waitUntil(timeout: 5) { engine.operation(id: op.id)?.state == .synced }
        XCTAssertEqual(client.recorded.map(\.operationId), [op.id, op.id])
        XCTAssertEqual(engine.operation(id: op.id)?.acknowledgment?.replayed, true)
    }

    func testAnAssignmentConflictParksTheChecklistWithSignatureIntact() throws {
        client.enqueue(Fixtures.failure(409, code: "EQUIPMENT_ASSIGNMENT_CONFLICT", retryable: false))
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let engine = SyncEngine(store: store, httpClient: client, handlers: [TestChecklistHandler()])
        let op = try ChecklistOperationBuilder.enqueueCompletion(capture(context(product: "ORD-SCH-A")), signatureJPEG: Data("SIG".utf8), into: engine)

        waitUntil { engine.operation(id: op.id)?.state == .needsAttention }
        let parked = engine.operation(id: op.id)!
        XCTAssertEqual(parked.attempts.lastErrorCode, "EQUIPMENT_ASSIGNMENT_CONFLICT")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetsDirectory.appendingPathComponent(parked.assets[0].relativePath).path), "signature preserved")
        XCTAssertEqual(parked.payload["answers"]?.arrayValue?.count, 2)
    }
}

/// Core-only stand-in for ChecklistCompleteSyncHandler (the app-layer handler adds the session check).
struct TestChecklistHandler: SyncOperationHandler {
    var operationType: String { ChecklistOperationBuilder.completeType(.delivery) }
    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        try ChecklistRequestFactory.completeRequest(for: operation)
    }
}
