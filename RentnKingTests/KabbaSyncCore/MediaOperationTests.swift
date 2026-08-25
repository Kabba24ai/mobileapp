import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Phase 4 — media + driver's-license operations: durable file, stable client_media_id,
/// offline → relaunch → reconnect, lost-response replay, Needs Attention preservation,
/// cleanup ONLY after acknowledgment, discard.
final class MediaOperationTests: XCTestCase {

    private var dir: URL!
    private var client: FakeSyncHTTPClient!
    private var store: FileSyncOperationStore!

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
        client = FakeSyncHTTPClient()
        store = try! FileSyncOperationStore(rootDirectory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func engine() -> SyncEngine {
        SyncEngine(store: store, httpClient: client,
                   handlers: [MediaUploadTestHandler(kind: .delivery), MediaUploadTestHandler(kind: .pickup), MediaUploadTestHandler(kind: .license)],
                   policy: SyncRetryPolicy(backoffSchedule: [0.05]))
    }

    /// A "camera output" file in a temp location, like the compressed JPEG the screen writes.
    private func cameraFile(_ name: String = "photo.jpg", bytes: Int = 4096) throws -> URL {
        let url = dir.appendingPathComponent("camera-\(UUID().uuidString)-\(name)")
        try Data(repeating: 0xAB, count: bytes).write(to: url)
        return url
    }

    private func capture(kind: MediaKind = .delivery, asset: SyncAsset, product: String? = "ORD-SCH-A", execution: String? = "ORD-CHK-0001") -> MediaCapture {
        MediaCapture(kind: kind, orderUniqueId: "ORD-0001", orderProductUniqueId: product, checklistExecutionId: execution,
                     equipmentUniqueId: "EQP-A", side: kind == .license ? "front" : nil, label: "Skid Steer",
                     capturedAt: Date(timeIntervalSince1970: 1_787_685_243), asset: asset)
    }

    private func ackBody(clientId: String, replayed: Bool = false) -> SyncHTTPResult {
        Fixtures.ok(["success": true, "message": "ok", "request_id": "srv-m",
                     "data": ["order_media_unique_id": "ORD-MED-0001", "client_media_id": clientId, "already_uploaded": replayed]],
                    headers: ["X-Request-Id": "srv-m"] .merging(replayed ? ["X-Idempotent-Replay": "true"] : [:]) { a, _ in a })
    }

    // MARK: Durable file + identity

    func testImportMovesTheFileIntoProtectedStorageWithAStableClientMediaId() throws {
        let source = try cameraFile()
        let asset = try SyncAssetWriter.importFile(at: source, in: store.assetsDirectory, scope: "ORD-SCH-A", fieldName: "media", mimeType: "image/jpeg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "the temp camera file is not the durable copy")
        XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory))
        XCTAssertEqual(asset.byteCount, 4096)
        XCTAssertEqual(asset.relativePath, "ORD-SCH-A/\(asset.clientMediaId).jpg")
        XCTAssertEqual(asset.clientMediaId.count, 36)
    }

    func testPayloadIdentityAndTitleCarryExplicitAssociationAndNoCustomerData() throws {
        let asset = try SyncAssetWriter.importFile(at: cameraFile(), in: store.assetsDirectory, scope: "ORD-SCH-A", fieldName: "media", mimeType: "image/jpeg")
        let c = capture(asset: asset)
        let payload = MediaOperationBuilder.payload(c)
        XCTAssertEqual(payload["client_media_id"]?.stringValue, asset.clientMediaId)
        XCTAssertEqual(payload["order_unique_id"]?.stringValue, "ORD-0001")
        XCTAssertEqual(payload["order_product_unique_id"]?.stringValue, "ORD-SCH-A")
        XCTAssertEqual(payload["checklist_execution_id"]?.stringValue, "ORD-CHK-0001")
        XCTAssertEqual(payload["type"]?.stringValue, "delivery")
        XCTAssertNil(payload["side"])
        let identity = MediaOperationBuilder.identity(c)
        XCTAssertEqual(identity.checklistExecutionId, "ORD-CHK-0001")
        XCTAssertEqual(identity.equipmentUniqueId, "EQP-A")
        XCTAssertEqual(MediaOperationBuilder.displayTitle(c), "Delivery photo · Skid Steer")

        let license = try SyncAssetWriter.store(Data(repeating: 1, count: 10), in: store.assetsDirectory, scope: "license-ORD-0001", fieldName: "media", mimeType: "image/jpeg", fileExtension: "jpg")
        let lc = capture(kind: .license, asset: license, product: nil, execution: nil)
        XCTAssertEqual(MediaOperationBuilder.displayTitle(lc), "Driver's license · front")
        XCTAssertEqual(MediaOperationBuilder.payload(lc)["side"]?.stringValue, "front")
        XCTAssertNil(MediaOperationBuilder.payload(lc)["order_product_unique_id"])
        XCTAssertTrue(lc.localValidationProblems().isEmpty)
    }

    func testRequestIsAMultipartBackgroundUploadWithTheFileUnderTheMediaField() throws {
        let asset = try SyncAssetWriter.importFile(at: cameraFile("clip.mov", bytes: 100_000), in: store.assetsDirectory, scope: "ORD-SCH-A", fieldName: "media", mimeType: "video/quicktime")
        let e = engine()
        client.defaultResult = .failure(APIError.transport(.offline))
        let op = try MediaOperationBuilder.enqueue(capture(asset: asset), into: e, operationId: "MEDIA-OP-0001")
        let request = try MediaRequestFactory.uploadRequest(for: op)
        XCTAssertEqual(request.path, "orders/media")
        XCTAssertTrue(request.prefersBackgroundTransfer)
        XCTAssertEqual(request.attachments.count, 1)
        XCTAssertEqual(request.attachments.first?.fieldName, "media")
        XCTAssertEqual(request.attachments.first?.clientMediaId, asset.clientMediaId)
        XCTAssertEqual(request.jsonBody?["operation_id"]?.stringValue, "MEDIA-OP-0001")
        XCTAssertEqual(request.jsonBody?["captured_at"]?.stringValue, KabbaISO8601.string(from: Date(timeIntervalSince1970: 1_787_685_243)))

        let body = try SyncMultipartBuilder.build(fields: request.jsonBody, assets: request.attachments, assetsDirectory: store.assetsDirectory, directory: dir)
        defer { try? FileManager.default.removeItem(at: body.fileURL) }
        XCTAssertGreaterThan(body.byteCount, 100_000, "the file bytes are streamed into the body")
    }

    // MARK: Offline → relaunch → reconnect → cleanup

    func testOfflineCaptureSurvivesRelaunchKeepsItsFileAndTheFileIsDeletedOnlyAfterAcknowledgment() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let asset = try SyncAssetWriter.importFile(at: cameraFile(), in: store.assetsDirectory, scope: "ORD-SCH-A", fieldName: "media", mimeType: "image/jpeg")
        let first = engine()
        let op = try MediaOperationBuilder.enqueue(capture(asset: asset), into: first)
        waitUntil("attempt") { self.client.requestCount >= 1 }
        XCTAssertEqual(first.operation(id: op.id)?.state, .pending)
        XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory), "never deleted on a failed attempt")

        // Relaunch.
        let second = engine()
        let reloaded = second.operation(id: op.id)
        XCTAssertEqual(reloaded?.state, .pending)
        XCTAssertEqual(reloaded?.assets.first?.clientMediaId, asset.clientMediaId, "the client media id is persisted with the operation")
        XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory))

        // Reconnect → accepted → local file removed (MediaCleanupPolicy).
        client.defaultResult = ackBody(clientId: asset.clientMediaId)
        second.kick(reason: "reconnect", ignoreBackoff: true)
        waitUntil("synced") { second.operation(id: op.id)?.state == .synced }
        XCTAssertFalse(SyncAssetWriter.exists(asset, in: store.assetsDirectory), "cleanup follows the acknowledgment")
        XCTAssertNotNil(second.operation(id: op.id)?.assets.first?.acknowledgedAt)
        XCTAssertEqual(client.recorded.last?.jsonBody?["client_media_id"]?.stringValue, asset.clientMediaId, "the SAME client id after relaunch")
    }

    func testALostResponseRetriesWithTheSameClientMediaIdAndConvergesOnTheReplay() throws {
        let asset = try SyncAssetWriter.importFile(at: cameraFile(), in: store.assetsDirectory, scope: "ORD-SCH-A", fieldName: "media", mimeType: "image/jpeg")
        // First attempt: the server stored it but the answer never arrived (connection lost).
        client.enqueue(.failure(APIError.transport(.connectionLost)))
        client.defaultResult = ackBody(clientId: asset.clientMediaId, replayed: true)
        let e = engine()
        let op = try MediaOperationBuilder.enqueue(capture(asset: asset), into: e)
        waitUntil("synced") { e.operation(id: op.id)?.state == .synced }
        XCTAssertEqual(client.requestCount, 2)
        XCTAssertEqual(client.recorded[0].jsonBody?["client_media_id"]?.stringValue, client.recorded[1].jsonBody?["client_media_id"]?.stringValue)
        XCTAssertEqual(client.recorded[0].headers["X-Operation-Id"], client.recorded[1].headers["X-Operation-Id"])
        XCTAssertEqual(e.operation(id: op.id)?.acknowledgment?.replayed, true)
        XCTAssertFalse(SyncAssetWriter.exists(asset, in: store.assetsDirectory))
    }

    func testAPermanentRejectionKeepsTheFileAndTheOperation() throws {
        client.defaultResult = Fixtures.failure(422, code: "MEDIA_ASSOCIATION_INVALID", retryable: false, message: "The checklist does not belong to the order item.")
        let asset = try SyncAssetWriter.importFile(at: cameraFile(), in: store.assetsDirectory, scope: "ORD-SCH-A", fieldName: "media", mimeType: "image/jpeg")
        let e = engine()
        let op = try MediaOperationBuilder.enqueue(capture(asset: asset), into: e)
        waitUntil("needs attention") { e.operation(id: op.id)?.state == .needsAttention }
        XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory), "evidence is never purged on rejection")
        XCTAssertEqual(e.operation(id: op.id)?.attempts.lastErrorCode, "MEDIA_ASSOCIATION_INVALID")
        XCTAssertEqual(client.requestCount, 1)

        // A 409 client-id conflict is permanent too — the file stays, nothing re-associates.
        client.defaultResult = Fixtures.failure(409, code: "MEDIA_CLIENT_ID_CONFLICT", retryable: false)
        e.retryNow(operationId: op.id)
        waitUntil("needs attention again") { e.operation(id: op.id)?.state == .needsAttention && self.client.requestCount == 2 }
        XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory))
    }

    func testTemporaryFailuresKeepRetryingAndNeverDeleteTheFile() throws {
        client.enqueue(Fixtures.failure(500, code: "MEDIA_UPLOAD_FAILED", retryable: true),
                       .failure(APIError.transport(.timeout)),
                       Fixtures.failure(429, code: "RATE_LIMITED", retryable: true))
        let asset = try SyncAssetWriter.importFile(at: cameraFile(), in: store.assetsDirectory, scope: "ORD-SCH-A", fieldName: "media", mimeType: "image/jpeg")
        client.defaultResult = ackBody(clientId: asset.clientMediaId)
        let e = engine()
        let op = try MediaOperationBuilder.enqueue(capture(asset: asset), into: e)
        waitUntil(timeout: 5, "eventually synced") { e.operation(id: op.id)?.state == .synced }
        XCTAssertEqual(client.requestCount, 4)
        XCTAssertFalse(SyncAssetWriter.exists(asset, in: store.assetsDirectory))
    }

    func testDiscardRemovesTheOperationAndItsFile() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let asset = try SyncAssetWriter.importFile(at: cameraFile(), in: store.assetsDirectory, scope: "ORD-SCH-A", fieldName: "media", mimeType: "image/jpeg")
        let e = engine()
        let op = try MediaOperationBuilder.enqueue(capture(asset: asset), into: e)
        waitUntil("attempt") { self.client.requestCount >= 1 }
        try e.discard(operationId: op.id)
        XCTAssertNil(e.operation(id: op.id))
        XCTAssertFalse(SyncAssetWriter.exists(asset, in: store.assetsDirectory))
    }

    func testAMissingLocalFileParksTheOperationInsteadOfSendingAnEmptyUpload() throws {
        let asset = try SyncAssetWriter.importFile(at: cameraFile(), in: store.assetsDirectory, scope: "ORD-SCH-A", fieldName: "media", mimeType: "image/jpeg")
        SyncAssetWriter.remove(asset, in: store.assetsDirectory)   // simulate external loss
        let e = engine()
        let op = try MediaOperationBuilder.enqueue(capture(asset: asset), into: e)
        let request = try MediaRequestFactory.uploadRequest(for: op)
        XCTAssertThrowsError(try SyncMultipartBuilder.build(fields: request.jsonBody, assets: request.attachments, assetsDirectory: store.assetsDirectory, directory: dir)) { error in
            XCTAssertEqual(error as? SyncMultipartError, .assetMissing(asset.relativePath))
        }
    }

    func testNonMediaHandlersNeverDeleteAssetsOnAcknowledgment() throws {
        // The Phase 3 signature stays on disk after a checklist completion (its handler keeps files).
        let asset = try SyncAssetWriter.store(Data(repeating: 7, count: 32), in: store.assetsDirectory, scope: "ORD-CHK-1", fieldName: "signature_media", mimeType: "image/jpeg", fileExtension: "jpg")
        client.defaultResult = Fixtures.ok()
        let e = makeEngine(store: store, client: client)
        let op = try e.enqueue(type: TestOperationHandler.type, payload: Fixtures.payload, capturedAt: Date(), assets: [asset])
        waitUntil("synced") { e.operation(id: op.id)?.state == .synced }
        XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory))
        XCTAssertNotNil(e.operation(id: op.id)?.assets.first?.acknowledgedAt, "acknowledgedAt is still recorded")
    }
}

/// Core-only stand-in for the app's MediaUploadSyncHandler (same request factory + cleanup rule).
struct MediaUploadTestHandler: SyncOperationHandler {
    let kind: MediaKind
    var operationType: String { kind.operationType }
    var removesAssetsAfterAcknowledgment: Bool { MediaCleanupPolicy.deleteAssetsAfterAcknowledgment }
    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        try MediaRequestFactory.uploadRequest(for: operation)
    }
}
