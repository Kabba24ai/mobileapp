import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Dispatch offline Phase 5 — terms.sign, a signature captured on this phone:
/// durable before anything advances, one PNG asset, the multipart request
/// Laravel's POST orders/terms/{order}/accept expects, idempotent retries, and
/// the satisfaction rule (healthy only, bound to the order and the verified
/// identity; a refused signature is kept but never counts).
final class TermsSignOperationsTests: XCTestCase {

    private let identityA = "v1:" + String(repeating: "a", count: 64)
    private let identityB = "v1:" + String(repeating: "b", count: 64)
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])

    private var dir: URL!
    private var client: FakeSyncHTTPClient!

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory(name)
        client = FakeSyncHTTPClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private struct Handler: SyncOperationHandler {
        var operationType: String { TermsSignOperationBuilder.operationType }
        func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
            try TermsSignRequestFactory.request(for: operation)
        }
    }

    private func capture(order: String = "ORD-A", identity: String? = nil) -> TermsSignCapture {
        var c = TermsSignCapture(orderUniqueId: order, termsIdentity: identity ?? identityA, approvalsConfirmed: 1)
        c.orderProductUniqueId = "ORD-SCH-A"
        c.employeeUserId = 7
        c.orderNumber = "1650"
        c.capturedAt = Date(timeIntervalSince1970: 1_790_000_000)
        return c
    }

    private func engine() throws -> SyncEngine {
        SyncEngine(store: try FileSyncOperationStore(rootDirectory: dir), httpClient: client, handlers: [Handler()],
                   policy: SyncRetryPolicy(backoffSchedule: [0.05]))
    }

    // MARK: - Durable capture

    func testASigningIsDurableWithOnePNGAssetBeforeEnqueueReturns() throws {
        let engine = try engine()
        let op = try TermsSignOperationBuilder.enqueue(capture(), signaturePNG: png, into: engine)

        XCTAssertEqual(op.type, "terms.sign")
        XCTAssertEqual(op.state, .pending)
        XCTAssertEqual(op.identity.orderUniqueId, "ORD-A")
        XCTAssertEqual(op.identity.orderProductUniqueId, "ORD-SCH-A")
        XCTAssertEqual(op.identity.employeeId, "7")
        XCTAssertEqual(op.capturedAt, Date(timeIntervalSince1970: 1_790_000_000), "device signing time")
        XCTAssertEqual(op.assets.count, 1)
        XCTAssertEqual(op.assets[0].fieldName, "signature_media")
        XCTAssertEqual(op.assets[0].mimeType, "image/png")
        XCTAssertEqual(op.payload["terms_identity"]?.stringValue, identityA)
        XCTAssertEqual(op.payload["approvals_confirmed"]?.intValue, 1)
        XCTAssertEqual(op.payload["signature_client_media_id"]?.stringValue, op.assets[0].clientMediaId)
        XCTAssertEqual(try Data(contentsOf: engine.store.assetsDirectory.appendingPathComponent(op.assets[0].relativePath)), png)

        // Force-quit / restart: a fresh store on the same folder still has it.
        let reloaded = try FileSyncOperationStore(rootDirectory: dir).loadAll()
        XCTAssertEqual(reloaded.map(\.id), [op.id])
        XCTAssertTrue(EffectiveFieldState.termsSatisfied(serverAccepted: false, operations: reloaded, orderUniqueId: "ORD-A", termsIdentity: identityA))
    }

    func testLocalValidationRequiresAnOrderAndAnIdentity() {
        XCTAssertEqual(capture().localValidationProblems(), [])
        XCTAssertFalse(capture(order: "").localValidationProblems().isEmpty)
        XCTAssertFalse(capture(identity: "sha256:nope").localValidationProblems().isEmpty)
    }

    // MARK: - The request

    func testTheRequestIsTheMultipartAcceptWithTheIdempotencyKey() throws {
        let engine = try engine()
        let op = try TermsSignOperationBuilder.enqueue(capture(), signaturePNG: png, into: engine)
        let request = try TermsSignRequestFactory.request(for: op)

        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "orders/terms/ORD-A/accept")
        XCTAssertEqual(request.headers["X-Operation-Id"], op.id)
        XCTAssertEqual(request.jsonBody?["operation_id"]?.stringValue, op.id)
        XCTAssertEqual(request.jsonBody?["terms_identity"]?.stringValue, identityA)
        XCTAssertEqual(request.jsonBody?["approvals_confirmed"]?.intValue, 1)
        XCTAssertEqual(request.jsonBody?["order_product_unique_id"]?.stringValue, "ORD-SCH-A")
        XCTAssertEqual(request.jsonBody?["leg"]?.stringValue, "delivery")
        XCTAssertNotNil(request.jsonBody?["captured_at"]?.stringValue)
        XCTAssertNil(request.jsonBody?["order_unique_id"], "the order is the URL")
        XCTAssertEqual(request.attachments.map(\.fieldName), ["signature_media"])
    }

    func testARequestWithoutIdentityOrSignatureIsRefused() throws {
        let engine = try engine()
        let op = try TermsSignOperationBuilder.enqueue(capture(), signaturePNG: png, into: engine)
        var noIdentity = op; noIdentity.payload = op.payload.setting(["terms_identity"], .string("x"))
        var noAsset = op; noAsset.assets = []

        XCTAssertThrowsError(try TermsSignRequestFactory.request(for: noIdentity))
        XCTAssertThrowsError(try TermsSignRequestFactory.request(for: noAsset))
    }

    // MARK: - Sync outcomes

    func testAnAcceptedSigningSyncsOnceAndALostAcknowledgmentReplays() throws {
        let engine = try engine()
        client.enqueue(.failure(APIError.transport(.connectionLost, description: "response lost")),
                       Fixtures.ok(["success": true, "message": "Terms and conditions accepted.",
                                    "data": ["outcome": "accepted", "terms_status": "Accepted", "terms_identity": identityA]],
                                   headers: ["X-Idempotent-Replay": "true", "X-Request-Id": "srv-2"]))
        let op = try TermsSignOperationBuilder.enqueue(capture(), signaturePNG: png, into: engine)

        engine.kick(reason: "online", ignoreBackoff: true)
        waitUntil("first attempt") { self.client.requestCount >= 1 }
        waitUntil("retry") {
            engine.kick(reason: "retry", ignoreBackoff: true)
            return engine.operation(id: op.id)?.state == .synced
        }

        XCTAssertEqual(client.recorded.count, 2)
        XCTAssertEqual(Set(client.recorded.map { $0.headers["X-Operation-Id"] }), [op.id], "one idempotency key")
        XCTAssertEqual(engine.snapshot().filter { $0.type == "terms.sign" }.count, 1, "never duplicated")
    }

    func testAnIdentityMismatchParksTheSignatureAndItNeverCounts() throws {
        let engine = try engine()
        client.enqueue(Fixtures.failure(409, code: "TERMS_IDENTITY_MISMATCH", retryable: false,
                                        message: "Unable to Verify Order Terms — Refresh the Order Before Signing"))
        let op = try TermsSignOperationBuilder.enqueue(capture(), signaturePNG: png, into: engine)

        engine.kick(reason: "online", ignoreBackoff: true)
        waitUntil("parked") { engine.operation(id: op.id)?.state == .needsAttention }

        let parked = try XCTUnwrap(engine.operation(id: op.id))
        XCTAssertEqual(parked.attempts.lastErrorCode, "TERMS_IDENTITY_MISMATCH")
        XCTAssertTrue(FileManager.default.fileExists(atPath: engine.store.assetsDirectory.appendingPathComponent(parked.assets[0].relativePath).path),
                      "the signature is kept for troubleshooting")
        XCTAssertFalse(EffectiveFieldState.termsSatisfied(serverAccepted: false, operations: engine.snapshot(), orderUniqueId: "ORD-A", termsIdentity: identityA))
        XCTAssertEqual(LegCompletionEvaluator.evaluate(leg: .delivery, inputs: inputs(identity: identityA), operations: engine.snapshot())
            .status(.termsAndConditions), .incomplete, "never relabelled as accepted")
    }

    // MARK: - Satisfaction

    private func inputs(order: String = "ORD-A", identity: String = "", confirmed: Bool = false) -> LegCompletionInputs {
        LegCompletionInputs(orderUniqueId: order, orderProductUniqueId: "ORD-SCH-A", orderProductUniqueIds: ["ORD-SCH-A"],
                            termsConfirmed: confirmed, termsIdentity: identity)
    }

    private func op(_ state: SyncState, type: String = "terms.sign", order: String = "ORD-A", identity: String? = nil) -> SyncOperation {
        var o = SyncOperation(type: type, capturedAt: Date(),
                              identity: SyncBusinessIdentity(orderUniqueId: order, orderProductUniqueId: "ORD-SCH-A"),
                              payload: .object(["terms_identity": .string(identity ?? identityA)]))
        o.state = state
        return o
    }

    private func terms(_ ops: [SyncOperation], _ inputs: LegCompletionInputs) -> RequirementStatus? {
        LegCompletionEvaluator.evaluate(leg: .delivery, inputs: inputs, operations: ops).status(.termsAndConditions)
    }

    func testAHealthySignatureAtTheVerifiedIdentitySatisfiesTheWholeOrder() {
        for state in [SyncState.pending, .syncing, .synced] {
            XCTAssertEqual(terms([op(state)], inputs(identity: identityA)), .satisfied, "\(state)")
        }
        XCTAssertEqual(terms([op(.pending)], inputs(identity: "")), .satisfied, "no agreement held: nothing contradicts it")
        var sibling = inputs(identity: identityA); sibling.orderProductUniqueId = "ORD-SCH-B"
        XCTAssertEqual(terms([op(.pending)], sibling), .satisfied, "one signature covers every line of the order")
    }

    func testASignatureNeverCountsForAnotherOrderOrAnotherDocument() {
        XCTAssertEqual(terms([op(.pending, order: "ORD-B")], inputs(identity: identityA)), .incomplete, "another order (or a related order)")
        XCTAssertEqual(terms([op(.pending)], inputs(identity: identityB)), .incomplete, "not the verified document")
        XCTAssertEqual(terms([op(.needsAttention)], inputs(identity: identityA)), .incomplete, "a refused signature")
    }

    func testTheLegacyHostedPageEvidenceAndServerTruthAreUnchanged() {
        XCTAssertEqual(terms([op(.pending, type: "terms.accept")], inputs(identity: identityB)), .satisfied)
        if case .satisfiedNeedsAttention = terms([op(.needsAttention, type: "terms.accept")], inputs()) {} else {
            XCTFail("a parked legacy terms.accept keeps its Phase 4 treatment")
        }
        XCTAssertEqual(terms([], inputs(confirmed: true)), .satisfied)
        XCTAssertNil(LegCompletionEvaluator.evaluate(leg: .return, inputs: inputs(), operations: []).status(.termsAndConditions),
                     "T&C is never judged for a Return")
    }
}
