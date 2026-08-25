import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Phase 4 — Queue Line item-level orchestration on the Sync Engine.
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

    private func command(product: String = "ORD-SCH-A", unit: String = "EQP-A", fuel: Bool? = true, key: Bool? = true) -> QueueLineStageCommand {
        QueueLineStageCommand(orderProductUniqueId: product, orderUniqueId: "ORD-0001", orderNumber: "7701", productName: "Skid Steer",
                              equipmentUniqueId: unit, equipmentName: "Bobcat S650", performedByUniqueId: "PER-0007", performedByName: "Yard Tech",
                              fuelFull: fuel, keyWithMachine: key, capturedAt: Date(timeIntervalSince1970: 1_787_685_243))
    }

    private func engine(handler: SyncOperationHandler = QueueLineStageSyncTestHandler()) -> SyncEngine {
        makeEngine(store: try! FileSyncOperationStore(rootDirectory: dir), client: client, handler: handler)
    }

    // MARK: Command → operation

    func testPayloadCarriesTheExactItemUnitAndEmployeeAndOmitsNotApplicableChecks() throws {
        let payload = QueueLineOperationBuilder.payload(command(fuel: nil, key: true))
        XCTAssertEqual(payload["order_product_unique_id"]?.stringValue, "ORD-SCH-A")
        XCTAssertEqual(payload["order_unique_id"]?.stringValue, "ORD-0001")
        XCTAssertEqual(payload["equipment_unique_id"]?.stringValue, "EQP-A")
        XCTAssertEqual(payload["performed_by"]?.stringValue, "PER-0007")
        XCTAssertNil(payload["fuel_full"], "a not-applicable check is omitted, exactly like the online form")
        XCTAssertEqual(payload["key_with_machine"]?.boolValue, true)
    }

    func testIdentityAndTitleRetainTheItemWithoutCustomerData() {
        let identity = QueueLineOperationBuilder.identity(command())
        XCTAssertEqual(identity.orderProductUniqueId, "ORD-SCH-A")
        XCTAssertEqual(identity.orderUniqueId, "ORD-0001")
        XCTAssertEqual(identity.equipmentUniqueId, "EQP-A")
        XCTAssertEqual(identity.employeeId, "PER-0007")
        let title = QueueLineOperationBuilder.displayTitle(command())
        XCTAssertTrue(title.contains("#7701") && title.contains("Skid Steer") && title.contains("Bobcat S650"))
        XCTAssertFalse(title.contains("Customer"))
    }

    func testLocalValidationMirrorsTheServerReadinessRules() {
        XCTAssertTrue(command().localValidationProblems().isEmpty)
        XCTAssertFalse(command(fuel: false).localValidationProblems().isEmpty)
        XCTAssertFalse(command(key: false).localValidationProblems().isEmpty)
        XCTAssertTrue(command(fuel: nil, key: nil).localValidationProblems().isEmpty, "trait-less units stage on the sign-off alone")
        XCTAssertFalse(command(unit: "").localValidationProblems().isEmpty)
    }

    func testRequestTargetsTheItemAndCarriesTheOperationIdAsTheLedgerToken() throws {
        let e = engine()
        let op = try QueueLineOperationBuilder.enqueueMarkStaged(command(), into: e, operationId: "QL-OP-0001")
        let request = try QueueLineRequestFactory.markStagedRequest(for: op)
        XCTAssertEqual(request.path, "queue-line/ORD-SCH-A/mark-staged")
        XCTAssertEqual(request.headers["X-Operation-Id"], "QL-OP-0001")
        XCTAssertEqual(request.jsonBody?["idempotency_token"]?.stringValue, "QL-OP-0001")
        XCTAssertEqual(request.jsonBody?["operation_id"]?.stringValue, "QL-OP-0001")
        XCTAssertEqual(request.jsonBody?["captured_at"]?.stringValue, KabbaISO8601.string(from: Date(timeIntervalSince1970: 1_787_685_243)))
        XCTAssertNil(request.jsonBody?["order_product_unique_id"], "the item is in the path, not duplicated in the body")
        XCTAssertTrue(request.attachments.isEmpty)
    }

    // MARK: Offline → relaunch → reconnect

    func testOfflineStagingIsDurableSurvivesRelaunchAndSyncsOnReconnect() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let first = engine()
        let op = try QueueLineOperationBuilder.enqueueMarkStaged(command(), into: first)
        waitUntil("first attempt") { self.client.requestCount >= 1 }
        XCTAssertEqual(first.operation(id: op.id)?.state, .pending, "offline keeps the command pending, never drops it")

        // "Force quit": a brand-new engine over the same directory.
        let second = engine()
        XCTAssertEqual(second.operation(id: op.id)?.state, .pending)
        XCTAssertEqual(second.operation(id: op.id)?.identity.orderProductUniqueId, "ORD-SCH-A")

        // Reconnect: Kabba accepts.
        client.defaultResult = Fixtures.ok(["success": true, "data": ["order_product_unique_id": "ORD-SCH-A", "fully_staged": true, "replayed": false, "status": "staged"], "request_id": "srv-1"])
        second.kick(reason: "reconnect", ignoreBackoff: true)
        waitUntil("synced") { second.operation(id: op.id)?.state == .synced }
        XCTAssertEqual(second.operation(id: op.id)?.acknowledgment?.replayed, false)
        XCTAssertEqual(client.recorded.last?.headers["X-Operation-Id"], op.id, "the SAME operation id after relaunch")
    }

    func testAReplayedAcknowledgmentConverges() throws {
        client.defaultResult = Fixtures.ok(["success": true, "replayed": true, "data": ["order_product_unique_id": "ORD-SCH-A", "fully_staged": true, "replayed": true], "request_id": "srv-2"],
                                           headers: ["X-Request-Id": "srv-2", "X-Idempotent-Replay": "true"])
        let e = engine()
        let op = try QueueLineOperationBuilder.enqueueMarkStaged(command(), into: e)
        waitUntil("synced") { e.operation(id: op.id)?.state == .synced }
        XCTAssertEqual(e.operation(id: op.id)?.acknowledgment?.replayed, true)
    }

    func testAConflictWithNewerServerTruthParksTheCommandAndKeepsIt() throws {
        client.defaultResult = Fixtures.failure(409, code: "QUEUE_ASSIGNMENT_CHANGED", retryable: false,
                                                message: "The assignment changed — this item is now Unit B, not Unit A.")
        let e = engine()
        let op = try QueueLineOperationBuilder.enqueueMarkStaged(command(), into: e)
        waitUntil("needs attention") { e.operation(id: op.id)?.state == .needsAttention }
        let parked = e.operation(id: op.id)!
        XCTAssertEqual(parked.attempts.lastErrorCode, "QUEUE_ASSIGNMENT_CHANGED")
        XCTAssertTrue(parked.attentionReason?.contains("Unit B") == true)
        XCTAssertEqual(parked.payload["equipment_unique_id"]?.stringValue, "EQP-A", "the original command is preserved, not re-pointed")
        XCTAssertEqual(client.requestCount, 1, "a permanent conflict is not hammered")
    }

    func testMultiLineOrderCommandsStayIsolated() throws {
        client.defaultResult = Fixtures.ok(["success": true, "data": ["fully_staged": true, "replayed": false], "request_id": "srv-3"])
        let e = engine()
        let a = try QueueLineOperationBuilder.enqueueMarkStaged(command(product: "ORD-SCH-A", unit: "EQP-A"), into: e)
        let b = try QueueLineOperationBuilder.enqueueMarkStaged(command(product: "ORD-SCH-B", unit: "EQP-B"), into: e)
        waitUntil("both synced") { e.operation(id: a.id)?.state == .synced && e.operation(id: b.id)?.state == .synced }
        let paths = Set(client.recorded.map { $0.path })
        XCTAssertEqual(paths, ["queue-line/ORD-SCH-A/mark-staged", "queue-line/ORD-SCH-B/mark-staged"])
        let unitsByPath = Dictionary(uniqueKeysWithValues: client.recorded.map { ($0.path, $0.jsonBody?["equipment_unique_id"]?.stringValue ?? "") })
        XCTAssertEqual(unitsByPath["queue-line/ORD-SCH-A/mark-staged"], "EQP-A")
        XCTAssertEqual(unitsByPath["queue-line/ORD-SCH-B/mark-staged"], "EQP-B")
    }

    // MARK: Board overlay + freshness

    func testOverlayMarksPendingAndAttentionPerProductAndLetsANewerCommandSupersedeARejection() throws {
        var pending = SyncOperation(type: QueueLineOperationBuilder.markStagedType, capturedAt: Date(),
                                    identity: SyncBusinessIdentity(orderProductUniqueId: "P1"), payload: .object([:]))
        var rejected = SyncOperation(type: QueueLineOperationBuilder.markStagedType, capturedAt: Date(),
                                     identity: SyncBusinessIdentity(orderProductUniqueId: "P2"), payload: .object([:]))
        rejected.state = .needsAttention
        rejected.attentionReason = "Assignment changed (QUEUE_ASSIGNMENT_CHANGED)"
        var synced = SyncOperation(type: QueueLineOperationBuilder.markStagedType, capturedAt: Date(),
                                   identity: SyncBusinessIdentity(orderProductUniqueId: "P3"), payload: .object([:]))
        synced.state = .synced
        var retried = SyncOperation(type: QueueLineOperationBuilder.markStagedType, capturedAt: Date(),
                                    identity: SyncBusinessIdentity(orderProductUniqueId: "P2"), payload: .object([:]))
        retried.state = .pending
        let other = SyncOperation(type: "delivery_media.upload", capturedAt: Date(),
                                  identity: SyncBusinessIdentity(orderProductUniqueId: "P1"), payload: .object([:]))
        pending.state = .syncing

        let overlay = QueueLineLocalOverlay.from([pending, rejected, synced, retried, other])
        XCTAssertTrue(overlay.isPendingStage("P1"))
        XCTAssertTrue(overlay.isPendingStage("P2"), "the retried command is pending again")
        XCTAssertNil(overlay.attentionReason("P2"), "a newer pending command supersedes the rejection")
        XCTAssertFalse(overlay.isPendingStage("P3"))
        XCTAssertNil(overlay.attentionReason("P3"))
    }

    func testFreshnessLineDistinguishesFreshCachedAndPendingStates() {
        let now = Date(timeIntervalSince1970: 1_787_685_243)
        XCTAssertEqual(QueueLineFreshness.line(lastServerSyncAt: now.addingTimeInterval(-10), lastRefreshFailed: false, pendingCount: 0, now: now), "Updated just now")
        XCTAssertEqual(QueueLineFreshness.line(lastServerSyncAt: now.addingTimeInterval(-300), lastRefreshFailed: false, pendingCount: 2, now: now), "Updated 5 min ago · 2 changes pending sync")
        XCTAssertTrue(QueueLineFreshness.line(lastServerSyncAt: now.addingTimeInterval(-300), lastRefreshFailed: true, pendingCount: 1, now: now).hasPrefix("Offline · showing the list saved at "))
        XCTAssertEqual(QueueLineFreshness.line(lastServerSyncAt: nil, lastRefreshFailed: true, pendingCount: 0, now: now), "Offline · no saved list yet")
    }
}

/// Core-only stand-in for the app's QueueLineStageSyncHandler (same request factory, session always present).
struct QueueLineStageSyncTestHandler: SyncOperationHandler {
    var operationType: String { QueueLineOperationBuilder.markStagedType }
    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        try QueueLineRequestFactory.markStagedRequest(for: operation)
    }
}
