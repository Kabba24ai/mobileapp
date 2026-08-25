import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Phase 5 — authentication and version failures PAUSE the Sync Engine; they never destroy
/// queued work. Re-authentication (or a compatible build) resumes the SAME operation ids.
final class AuthRecoveryTests: XCTestCase {

    /// Like the app's MediaUploadSyncHandler: no session → pause, never a failed operation.
    private struct SessionGatedMediaHandler: SyncOperationHandler {
        let kind: MediaKind
        let authenticated: () -> Bool
        var operationType: String { kind.operationType }
        var removesAssetsAfterAcknowledgment: Bool { true }
        func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
            guard authenticated() else { throw SyncHandlerError.notAuthenticated("no session") }
            return try MediaRequestFactory.uploadRequest(for: operation)
        }
    }

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

    private func engine(authenticated: @escaping () -> Bool = { true }) -> SyncEngine {
        var handler = TestOperationHandler()
        handler.authenticated = authenticated
        return SyncEngine(store: store, httpClient: client,
                          handlers: [handler, MediaUploadTestHandler(kind: .license), MediaUploadTestHandler(kind: .delivery)],
                          policy: SyncRetryPolicy(backoffSchedule: [0.05]))
    }

    /// A checklist-shaped operation, a delivery photo and a licence image — the three kinds of field work.
    private func enqueueFieldWork(into e: SyncEngine) throws -> (ops: [SyncOperation], assets: [SyncAsset]) {
        let checklist = try e.enqueue(type: TestOperationHandler.type, payload: Fixtures.payload,
                                      identity: SyncBusinessIdentity(orderUniqueId: "ORD-1", orderProductUniqueId: "ORD-SCH-A"), capturedAt: Date())
        let photo = try SyncAssetWriter.store(Data(repeating: 0xAB, count: 4_000), in: store.assetsDirectory, scope: "ORD-SCH-A", fieldName: "media", mimeType: "image/jpeg", fileExtension: "jpg")
        let media = try MediaOperationBuilder.enqueue(MediaCapture(kind: .delivery, orderUniqueId: "ORD-1", orderProductUniqueId: "ORD-SCH-A", checklistExecutionId: "ORD-CHK-1", label: "Skid Steer", asset: photo), into: e)
        let licenceJPEG = try SyncAssetWriter.store(Data(repeating: 0xCD, count: 2_000), in: store.assetsDirectory, scope: "license-ORD-1", fieldName: "media", mimeType: "image/jpeg", fileExtension: "jpg")
        let licence = try MediaOperationBuilder.enqueue(MediaCapture(kind: .license, orderUniqueId: "ORD-1", orderProductUniqueId: nil, side: "front", asset: licenceJPEG), into: e)
        return ([checklist, media, licence], [photo, licenceJPEG])
    }

    private func unauthenticated() -> SyncHTTPResult {
        .response(SyncHTTPResponse(statusCode: 401, headers: ["X-Request-Id": "srv-401"],
                                   body: Fixtures.json(["success": false, "message": "Unauthenticated.",
                                                        "error": ["code": "UNAUTHENTICATED", "message": "Unauthenticated.", "retryable": false, "reason": "expired"],
                                                        "errors": [String: Any](), "request_id": "srv-401"])))
    }

    private func updateRequired() -> SyncHTTPResult {
        .response(SyncHTTPResponse(statusCode: 426, headers: ["X-Request-Id": "srv-426", "X-Mobile-Update": "required", "X-Mobile-Minimum-Build": "1001"],
                                   body: Fixtures.json(["success": false, "message": "Please update.",
                                                        "error": ["code": "APP_UPDATE_REQUIRED", "message": "Please update.", "retryable": false],
                                                        "errors": [String: Any](), "data": ["platform": "ios", "state": "update_required", "minimum_supported_build": "1001", "update_required": true],
                                                        "request_id": "srv-426"])))
    }

    func testA401PausesEverythingKeepsEveryOperationAndFileAndReLoginResumesTheSameOperationIds() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = engine()
        let (ops, assets) = try enqueueFieldWork(into: e)
        waitUntil("first attempt") { self.client.requestCount >= 1 }

        // Reconnect with a dead token: the very first answer is 401.
        client.enqueue(unauthenticated())
        client.defaultResult = Fixtures.ok()
        e.kick(reason: "reconnect", ignoreBackoff: true)
        waitUntil("paused") { e.pause == .authentication }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        // Paused means paused: nothing else was sent, every operation is still pending, every file still on disk.
        let sentBeforeLogin = client.requestCount
        for op in ops { XCTAssertEqual(e.operation(id: op.id)?.state, .pending, op.type) }
        let refused = ops.first { e.operation(id: $0.id)?.attempts.lastStatusCode == 401 }
        XCTAssertNotNil(refused, "one operation met the 401")
        XCTAssertEqual(refused.flatMap { e.operation(id: $0.id)?.attempts.lastDisposition }, .waitForAuthentication)
        for asset in assets { XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory)) }
        e.kick(reason: "should be ignored while paused", ignoreBackoff: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(client.requestCount, sentBeforeLogin, "kicks are no-ops while paused for authentication")

        // The employee signs back in → the queue drains with the SAME operation ids.
        e.authenticationRestored()
        waitUntil(timeout: 5, "all synced") { ops.allSatisfy { e.operation(id: $0.id)?.state == .synced } }
        XCTAssertEqual(e.pause, .none)
        let sentIds = Set(client.recorded.map { $0.operationId })
        XCTAssertEqual(sentIds, Set(ops.map { $0.id }), "no operation was recreated or renamed across the re-auth boundary")
        XCTAssertGreaterThanOrEqual(client.recorded.filter { $0.operationId == refused?.id }.count, 2, "the refused operation was re-sent with its original id")
        // Media files are gone only now — after acknowledgment.
        for asset in assets { XCTAssertFalse(SyncAssetWriter.exists(asset, in: store.assetsDirectory)) }
    }

    func testARelaunchWithoutASessionPausesBeforeSendingAndKeepsTheQueue() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        var first: SyncEngine? = engine()
        let (ops, assets) = try enqueueFieldWork(into: first!)
        waitUntil("attempted") { self.client.requestCount >= 1 }
        first = nil   // the process that queued the work is gone
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        // Relaunch after the session was ended (logout / 401 → Login screen): no token → pause, no traffic.
        let sentBefore = client.requestCount
        var signedIn = false
        let relaunched = SyncEngine(store: try FileSyncOperationStore(rootDirectory: dir), httpClient: client,
                                    handlers: [{ var h = TestOperationHandler(); h.authenticated = { signedIn }; return h }(),
                                               SessionGatedMediaHandler(kind: .license, authenticated: { signedIn }),
                                               SessionGatedMediaHandler(kind: .delivery, authenticated: { signedIn })],
                                    policy: SyncRetryPolicy(backoffSchedule: [0.05]))
        relaunched.kick(reason: "launch", ignoreBackoff: true)
        waitUntil("paused") { relaunched.pause == .authentication }
        XCTAssertEqual(client.requestCount, sentBefore)
        XCTAssertEqual(relaunched.snapshot().count, 3)
        for asset in assets { XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory)) }

        signedIn = true
        client.defaultResult = Fixtures.ok()
        relaunched.authenticationRestored()
        waitUntil(timeout: 5, "synced") { ops.allSatisfy { relaunched.operation(id: $0.id)?.state == .synced } }
    }

    func testA426PausesIncompatibleSyncKeepsEverythingAndACompatibleBuildResumes() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = engine()
        let (ops, assets) = try enqueueFieldWork(into: e)
        waitUntil("attempt") { self.client.requestCount >= 1 }

        client.enqueue(updateRequired())
        client.defaultResult = Fixtures.ok()
        e.kick(reason: "reconnect", ignoreBackoff: true)
        waitUntil("paused for update") { e.pause == .appUpdate }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let sent = client.requestCount
        for op in ops { XCTAssertEqual(e.operation(id: op.id)?.state, .pending) }
        let refused = ops.first { e.operation(id: $0.id)?.attempts.lastStatusCode == 426 }
        XCTAssertEqual(refused.flatMap { e.operation(id: $0.id)?.attempts.lastDisposition }, .waitForAppUpdate)
        XCTAssertEqual(refused.flatMap { e.operation(id: $0.id)?.attempts.lastErrorCode }, "APP_UPDATE_REQUIRED")
        for asset in assets { XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory)) }
        e.kick(reason: "ignored", ignoreBackoff: true)
        e.authenticationRestored()   // signing in does NOT lift an update pause
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(client.requestCount, sent)
        XCTAssertEqual(e.pause, .appUpdate)

        // A compatible build launched (KabbaUpdateGate resolved the verdict) → resume.
        e.appUpdated()
        waitUntil(timeout: 5, "synced") { ops.allSatisfy { e.operation(id: $0.id)?.state == .synced } }
        XCTAssertEqual(Set(client.recorded.map { $0.operationId }), Set(ops.map { $0.id }))
    }

    func testAPersistedUpdateVerdictPausesAtLaunchBeforeTheFirstDrain() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        var first: SyncEngine? = engine()
        let (ops, _) = try enqueueFieldWork(into: first!)
        waitUntil("attempted") { self.client.requestCount >= 1 }
        first = nil   // the process that queued the work is gone
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let sent = client.requestCount

        // Launch with the verdict still applying: the gate pauses before kicking.
        client.defaultResult = Fixtures.ok()
        let relaunched = SyncEngine(store: try FileSyncOperationStore(rootDirectory: dir), httpClient: client,
                                    handlers: [TestOperationHandler(), MediaUploadTestHandler(kind: .license), MediaUploadTestHandler(kind: .delivery)],
                                    policy: SyncRetryPolicy(backoffSchedule: [0.05]))
        relaunched.appUpdateRequired()
        relaunched.kick(reason: "launch", ignoreBackoff: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(relaunched.pause, .appUpdate)
        XCTAssertEqual(client.requestCount, sent, "nothing incompatible is sent")
        XCTAssertEqual(relaunched.snapshot().filter { $0.state == .pending }.count, 3)

        relaunched.appUpdated()
        waitUntil(timeout: 5, "synced") { ops.allSatisfy { relaunched.operation(id: $0.id)?.state == .synced } }
    }

    func testAnExplicitLogoutPausesWithoutTouchingTheQueue() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = engine()
        let (ops, assets) = try enqueueFieldWork(into: e)
        waitUntil("attempt") { self.client.requestCount >= 1 }

        e.authenticationLost()
        waitUntil("paused") { e.pause == .authentication }
        XCTAssertEqual(e.snapshot().count, ops.count)
        for asset in assets { XCTAssertTrue(SyncAssetWriter.exists(asset, in: store.assetsDirectory)) }
        XCTAssertEqual(e.summary().outstanding, 3, "quoted to the employee as 'saved on this phone'")
    }
}
