import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// terms.accept — durable local evidence of a signed Terms & Conditions.
/// The signing page already recorded the acceptance server-side; these tests
/// pin the phone-side contract: builder round-trip, identity, optional native
/// signature asset, force-quit persistence, and the recording-only request.
final class TermsOperationsTests: XCTestCase {

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

    private func capture(order: String = "ORD-0001", product: String = "ORD-SCH-A",
                         leg: ChecklistLeg = .delivery, employee: Int = 7) -> TermsAcceptCapture {
        var c = TermsAcceptCapture(orderUniqueId: order, orderProductUniqueId: product, leg: leg)
        c.employeeUserId = employee
        c.orderNumber = "7701"
        c.capturedAt = Date(timeIntervalSince1970: 1_787_685_243)
        return c
    }

    // MARK: Payload + identity

    func testPayloadCarriesOrderProductLegStatusAndRecordingOnlyFlag() {
        let payload = TermsOperationBuilder.payload(capture())
        XCTAssertEqual(payload["order_unique_id"]?.stringValue, "ORD-0001")
        XCTAssertEqual(payload["order_product_unique_id"]?.stringValue, "ORD-SCH-A")
        XCTAssertEqual(payload["type"]?.stringValue, "delivery")
        XCTAssertEqual(payload["tnc_status"]?.stringValue, "accepted")
        XCTAssertEqual(payload["complete_leg"]?.boolValue, false, "recording only — never a completion claim")
        XCTAssertEqual(payload["user_id"]?.intValue, 7)
        XCTAssertNil(payload["signature_client_media_id"], "no native signature in the webview flow")

        let returnLeg = TermsOperationBuilder.payload(capture(leg: .return))
        XCTAssertEqual(returnLeg["type"]?.stringValue, "pickup")
    }

    func testIdentityMatchesTheOrderAndProduct() {
        let identity = TermsOperationBuilder.identity(capture())
        XCTAssertEqual(identity.orderUniqueId, "ORD-0001")
        XCTAssertEqual(identity.orderProductUniqueId, "ORD-SCH-A")
        XCTAssertEqual(identity.employeeId, "7")
    }

    func testLocalValidationRequiresOrderAndProduct() {
        XCTAssertEqual(capture().localValidationProblems(), [])
        XCTAssertFalse(capture(order: "").localValidationProblems().isEmpty)
        XCTAssertFalse(capture(product: "").localValidationProblems().isEmpty)
    }

    // MARK: Builder round-trip (force-quit persistence is the op store itself)

    func testEnqueuedAcceptanceSurvivesRelaunchAndImmediatelySatisfiesTerms() throws {
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let engine = makeEngine(store: store, client: client)   // offline: stays pending

        let op = try TermsOperationBuilder.enqueueAccept(capture(), into: engine)
        XCTAssertEqual(op.type, TermsOperationBuilder.operationType)
        XCTAssertEqual(op.state, .pending)
        XCTAssertTrue(op.assets.isEmpty)
        XCTAssertEqual(op.capturedAt.timeIntervalSince1970, 1_787_685_243, accuracy: 1)

        // The judgment flips the moment the record is durable — while still .pending
        // (no false exception during the Pending Sync window).
        XCTAssertTrue(EffectiveFieldState.termsSatisfied(serverAccepted: false,
                                                         operations: engine.snapshot(),
                                                         orderUniqueId: "ORD-0001"))

        // Force-quit: a fresh store on the same directory still has the evidence.
        let relaunched = try FileSyncOperationStore(rootDirectory: dir)
        let reloaded = try relaunched.loadAll()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded[0].id, op.id)
        XCTAssertEqual(reloaded[0].identity.orderUniqueId, "ORD-0001")
        XCTAssertTrue(EffectiveFieldState.termsSatisfied(serverAccepted: false,
                                                         operations: reloaded,
                                                         orderUniqueId: "ORD-0001"))
    }

    func testNativeSignatureBecomesAProtectedAssetReferencedByThePayload() throws {
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let engine = makeEngine(store: store, client: client)

        let op = try TermsOperationBuilder.enqueueAccept(capture(), signatureJPEG: Data("SIG-T".utf8), into: engine)
        XCTAssertEqual(op.assets.count, 1)
        XCTAssertEqual(op.assets[0].fieldName, "signature_media")
        XCTAssertEqual(op.payload["signature_client_media_id"]?.stringValue, op.assets[0].clientMediaId)
        XCTAssertEqual(try Data(contentsOf: store.assetsDirectory.appendingPathComponent(op.assets[0].relativePath)),
                       Data("SIG-T".utf8))
    }

    // MARK: Request (recording-only, idempotent, never the deprecated completing branch)

    func testRequestPostsTheCanonicalInputsRecorderWithOperationIdAndCapturedAt() throws {
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let engine = makeEngine(store: store, client: client)
        let op = try TermsOperationBuilder.enqueueAccept(capture(), into: engine)

        let request = try TermsAcceptRequestFactory.request(for: op)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "orders/schedules/update-delivery-pickup-inputs")
        XCTAssertEqual(request.headers["X-Operation-Id"], op.id)
        XCTAssertEqual(request.jsonBody?["operation_id"]?.stringValue, op.id)
        XCTAssertEqual(request.jsonBody?["tnc_status"]?.stringValue, "accepted")
        XCTAssertEqual(request.jsonBody?["complete_leg"]?.boolValue, false)
        XCTAssertNotNil(request.jsonBody?["captured_at"]?.stringValue)

        // complete_leg=false is the ONLY allowed use of this path (P0-3 door stays shut).
        XCTAssertFalse(DeprecatedMobileEndpoints.isDeprecated(request))
    }

    func testRequestRefusesAPayloadMissingItsProduct() throws {
        var op = SyncOperation(type: TermsOperationBuilder.operationType,
                               capturedAt: Date(),
                               identity: SyncBusinessIdentity(orderUniqueId: "ORD-0001"),
                               payload: .object(["order_unique_id": .string("ORD-0001")]))
        op.state = .pending
        XCTAssertThrowsError(try TermsAcceptRequestFactory.request(for: op))
    }

    func testGenuinelySkippedTermsProduceNoOperation() throws {
        // Nothing enqueued and the server never accepted → still unsatisfied:
        // the exception screen keeps asking, exactly as before this feature.
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let engine = makeEngine(store: store, client: client)
        XCTAssertFalse(EffectiveFieldState.termsSatisfied(serverAccepted: false,
                                                          operations: engine.snapshot(),
                                                          orderUniqueId: "ORD-0001"))
    }
}
