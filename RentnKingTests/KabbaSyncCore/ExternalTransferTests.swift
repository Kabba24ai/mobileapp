import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Phase 4 — the engine ↔ background-URLSession hand-off: an operation whose transfer is
/// still alive after a relaunch is HELD (not re-sent) and converges when the transfer's
/// result is delivered later; a lost transfer is released back to the drain loop.
final class ExternalTransferTests: XCTestCase {

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

    private func mediaEngine() -> SyncEngine {
        SyncEngine(store: store, httpClient: client, handlers: [MediaUploadTestHandler(kind: .delivery)],
                   policy: SyncRetryPolicy(backoffSchedule: [0.05]))
    }

    private func enqueueVideo(into engine: SyncEngine) throws -> (SyncOperation, SyncAsset) {
        let source = dir.appendingPathComponent("clip-\(UUID().uuidString).mov")
        try Data(repeating: 0x11, count: 50_000).write(to: source)
        let asset = try SyncAssetWriter.importFile(at: source, in: store.assetsDirectory, scope: "ORD-SCH-A", fieldName: "media", mimeType: "video/quicktime")
        let capture = MediaCapture(kind: .delivery, orderUniqueId: "ORD-0001", orderProductUniqueId: "ORD-SCH-A", checklistExecutionId: "ORD-CHK-1",
                                   label: "Skid Steer", capturedAt: Date(), asset: asset)
        return (try MediaOperationBuilder.enqueue(capture, into: engine), asset)
    }

    func testAHeldOperationIsNotReSentAndConvergesWhenTheBackgroundResultArrives() throws {
        // First process: the request went out through a background session; the app died before the answer.
        client.defaultResult = .failure(APIError.transport(.offline))
        var first: SyncEngine? = mediaEngine()
        let (op, asset) = try enqueueVideo(into: first!)
        waitUntil("first attempt") { self.client.requestCount >= 1 }
        first = nil   // the process that owned the first attempt is gone

        // Second process: launch finds the task still alive → hold before the launch kick.
        let second = mediaEngine()
        XCTAssertEqual(second.operation(id: op.id)?.state, .pending, "load reset it; the hold comes from the uploader")
        second.holdForExternalTransfer(operationId: op.id)
        waitUntil("held") { second.operation(id: op.id)?.state == .syncing }

        client.defaultResult = Fixtures.ok()
        second.kick(reason: "launch", ignoreBackoff: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(client.requestCount, 1, "a held operation is never re-sent by the drain loop")
        XCTAssertEqual(second.operation(id: op.id)?.state, .syncing)
        XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory))

        // The background session delivers the (successful) result.
        let ack = SyncHTTPResponse(statusCode: 200, headers: ["X-Request-Id": "bg-1"],
                                   body: Fixtures.json(["success": true, "request_id": "bg-1", "data": ["client_media_id": asset.clientMediaId, "already_uploaded": false]]))
        second.completeExternalTransfer(operationId: op.id, result: .response(ack))
        waitUntil("synced") { second.operation(id: op.id)?.state == .synced }
        XCTAssertEqual(second.operation(id: op.id)?.acknowledgment?.requestId, "bg-1")
        XCTAssertFalse(SyncAssetWriter.exists(asset, in: store.assetsDirectory), "cleanup follows the external acknowledgment too")
        XCTAssertEqual(client.requestCount, 1)
    }

    func testAnExternalFailureIsRetriedThroughTheNormalLoop() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = mediaEngine()
        let (op, asset) = try enqueueVideo(into: e)
        waitUntil("attempt") { self.client.requestCount >= 1 }
        e.holdForExternalTransfer(operationId: op.id)
        waitUntil("held") { e.operation(id: op.id)?.state == .syncing }

        client.defaultResult = Fixtures.ok(["success": true, "request_id": "r2", "data": ["client_media_id": asset.clientMediaId]])
        e.completeExternalTransfer(operationId: op.id, result: .failure(APIError.transport(.connectionLost)))
        waitUntil(timeout: 5, "retried and synced") { e.operation(id: op.id)?.state == .synced }
        XCTAssertGreaterThanOrEqual(client.requestCount, 2)
    }

    func testAnExternalConflictParksTheOperationWithItsFile() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = mediaEngine()
        let (op, asset) = try enqueueVideo(into: e)
        waitUntil("attempt") { self.client.requestCount >= 1 }
        e.holdForExternalTransfer(operationId: op.id)
        waitUntil("held") { e.operation(id: op.id)?.state == .syncing }

        if case .response(let conflict) = Fixtures.failure(409, code: "MEDIA_CLIENT_ID_CONFLICT", retryable: false) {
            e.completeExternalTransfer(operationId: op.id, result: .response(conflict))
        }
        waitUntil("needs attention") { e.operation(id: op.id)?.state == .needsAttention }
        XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory))
        XCTAssertEqual(e.operation(id: op.id)?.attempts.lastErrorCode, "MEDIA_CLIENT_ID_CONFLICT")
    }

    func testReleasingALostHoldPutsTheOperationBackOnTheDrainLoop() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = mediaEngine()
        let (op, asset) = try enqueueVideo(into: e)
        waitUntil("attempt") { self.client.requestCount >= 1 }
        e.holdForExternalTransfer(operationId: op.id)
        waitUntil("held") { e.operation(id: op.id)?.state == .syncing }

        client.defaultResult = Fixtures.ok(["success": true, "request_id": "r3", "data": ["client_media_id": asset.clientMediaId]])
        e.releaseExternalHold(operationId: op.id)
        waitUntil("synced") { e.operation(id: op.id)?.state == .synced }
        XCTAssertEqual(client.requestCount, 2)
    }
}
