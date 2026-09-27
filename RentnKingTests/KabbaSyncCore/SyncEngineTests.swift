import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class SyncEngineTests: XCTestCase {

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

    private func store() throws -> FileSyncOperationStore {
        try FileSyncOperationStore(rootDirectory: dir)
    }

    private func enqueue(_ engine: SyncEngine, product: String = "ORD-SCH-1", captured: Date = Date()) throws -> SyncOperation {
        try engine.enqueue(type: TestOperationHandler.type,
                           payload: Fixtures.payload,
                           identity: SyncBusinessIdentity(orderProductUniqueId: product),
                           capturedAt: captured,
                           displayTitle: "Driver checklist · Ready to Go")
    }

    private func state(_ engine: SyncEngine, _ id: String) -> SyncState? {
        engine.operation(id: id)?.state
    }

    // MARK: Scenario A — totally offline

    func testEnqueueIsDurableBeforeItReturnsAndAnOfflineFailureKeepsItPending() throws {
        let engine = makeEngine(store: try store(), client: client)   // client default = offline
        let op = try enqueue(engine)

        // Durable BEFORE the caller may say "Saved": a fresh store instance already sees it.
        let independent = try FileSyncOperationStore(rootDirectory: dir)
        XCTAssertNotNil(try independent.load(id: op.id))

        waitUntil("first attempt recorded") { engine.operation(id: op.id)?.attempts.attemptCount == 1 }
        let after = engine.operation(id: op.id)!
        XCTAssertEqual(after.state, .pending)
        XCTAssertEqual(after.attempts.lastTransportFailure, .offline)
        XCTAssertEqual(after.attempts.lastDisposition, .retry)
        XCTAssertNotNil(after.attempts.nextAttemptAt)
        XCTAssertEqual(after.payload, Fixtures.payload, "payload untouched")
        XCTAssertEqual(engine.summary().pending, 1)
    }

    // MARK: Scenario B — force quit / relaunch

    func testAPendingOperationSurvivesRelaunchAndSyncsWhenConnectivityReturns() throws {
        let first = makeEngine(store: try store(), client: client)
        let op = try enqueue(first)
        waitUntil { first.operation(id: op.id)?.attempts.attemptCount == 1 }

        // Relaunch: new engine over the same directory, network now available.
        let online = FakeSyncHTTPClient()
        online.defaultResult = Fixtures.ok()
        let second = makeEngine(store: try FileSyncOperationStore(rootDirectory: dir), client: online)

        XCTAssertEqual(state(second, op.id), .pending, "restored from disk")
        second.kick(reason: "network restored", ignoreBackoff: true)

        waitUntil("synced after relaunch") { second.operation(id: op.id)?.state == .synced }
        let synced = second.operation(id: op.id)!
        XCTAssertEqual(synced.id, op.id, "same operation id across relaunch")
        XCTAssertEqual(online.recorded.first?.operationId, op.id)
        XCTAssertEqual(synced.acknowledgment?.requestId, "srv-req-0001")
        XCTAssertEqual(synced.attempts.attemptCount, 2)
    }

    func testAnOperationLeftInSyncingByAKilledProcessIsResetToPendingOnLoad() throws {
        let s = try store()
        var op = SyncOperation(id: "KILLED-MID-FLIGHT-0001", type: TestOperationHandler.type, capturedAt: Date(), payload: Fixtures.payload)
        op.state = .syncing
        op.attempts.attemptCount = 1
        op.attempts.lastAttemptedAt = Date().addingTimeInterval(-600)
        try s.save(op)

        let engine = makeEngine(store: s, client: client)
        XCTAssertEqual(state(engine, op.id), .pending)
        XCTAssertEqual(try s.load(id: op.id)?.state, .pending, "the reset is persisted")
    }

    // MARK: Scenario C — restore connectivity

    func testRetriesReuseTheSameOperationIdUntilAcknowledged() throws {
        client.enqueue(.failure(APIError.transport(.timeout)), Fixtures.failure(503, code: "SERVER_ERROR"), Fixtures.ok())
        let engine = makeEngine(store: try store(), client: client, backoff: [0.05])
        let op = try enqueue(engine)

        waitUntil(timeout: 5, "synced after two retries") { engine.operation(id: op.id)?.state == .synced }

        XCTAssertEqual(client.requestCount, 3)
        XCTAssertEqual(Set(client.recorded.map(\.operationId)), [op.id])
        XCTAssertEqual(Set(client.recorded.compactMap { $0.headers["X-Operation-Id"] }), [op.id])
        XCTAssertEqual(Set(client.recorded.compactMap { $0.jsonBody?["operation_id"]?.stringValue }), [op.id])
        XCTAssertEqual(engine.operation(id: op.id)?.attempts.attemptCount, 3)
    }

    func testStateTransitionsAreEmittedPendingSyncingSynced() throws {
        client.defaultResult = Fixtures.ok()
        let engine = makeEngine(store: try store(), client: client)
        let lock = NSLock()
        var states: [SyncState] = []
        engine.eventHandler = { event in
            if case .operationChanged(let op) = event { lock.withLock { states.append(op.state) } }
        }
        let op = try enqueue(engine)
        waitUntil { engine.operation(id: op.id)?.state == .synced }
        XCTAssertEqual(lock.withLock { states }, [.pending, .syncing, .synced])
    }

    // MARK: Scenario D — lost response / duplicate retry

    func testAReplayedAcknowledgmentConvergesToSynced() throws {
        client.enqueue(.failure(APIError.transport(.connectionLost, description: "response lost")),
                       Fixtures.ok(["success": true, "replayed": true, "original_request_id": "srv-req-0001", "request_id": "srv-req-0002", "data": [:]],
                                   headers: ["X-Idempotent-Replay": "true", "X-Request-Id": "srv-req-0002"]))
        let engine = makeEngine(store: try store(), client: client, backoff: [0.05])
        let op = try enqueue(engine)

        waitUntil(timeout: 5) { engine.operation(id: op.id)?.state == .synced }
        let ack = engine.operation(id: op.id)!.acknowledgment!
        XCTAssertTrue(ack.replayed)
        XCTAssertEqual(ack.requestId, "srv-req-0002")
        XCTAssertEqual(client.recorded.map(\.operationId), [op.id, op.id])
    }

    func testSyncedOperationsAreNeverSentAgain() throws {
        client.defaultResult = Fixtures.ok()
        let engine = makeEngine(store: try store(), client: client)
        let op = try enqueue(engine)
        waitUntil { engine.operation(id: op.id)?.state == .synced }
        for i in 0..<5 { engine.kick(reason: "kick \(i)", ignoreBackoff: true) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(client.requestCount, 1)
    }

    // MARK: Scenario E — permanent rejection

    func testAPermanentRejectionBecomesNeedsAttentionWithEverythingPreserved() throws {
        client.enqueue(Fixtures.failure(422, code: "VALIDATION_FAILED", retryable: false, message: "Validation failed."))
        let engine = makeEngine(store: try store(), client: client)
        let op = try enqueue(engine)

        waitUntil { engine.operation(id: op.id)?.state == .needsAttention }
        let parked = engine.operation(id: op.id)!
        XCTAssertEqual(parked.payload, Fixtures.payload)
        XCTAssertEqual(parked.capturedAt.timeIntervalSince1970, op.capturedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(parked.attempts.lastStatusCode, 422)
        XCTAssertEqual(parked.attempts.lastErrorCode, "VALIDATION_FAILED")
        XCTAssertEqual(parked.attempts.lastRequestId, "srv-req-fail")
        XCTAssertTrue(parked.attentionReason?.contains("VALIDATION_FAILED") == true)
        XCTAssertEqual(engine.summary().needsAttention, 1)

        // Relaunch: still there, still needs attention, nothing deleted.
        let relaunched = makeEngine(store: try FileSyncOperationStore(rootDirectory: dir), client: FakeSyncHTTPClient())
        XCTAssertEqual(state(relaunched, op.id), .needsAttention)

        // No automatic retries: kicks do not touch a parked operation.
        engine.kick(reason: "later", ignoreBackoff: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(client.requestCount, 1)
    }

    func testAPersonCanRetryANeedsAttentionOperation() throws {
        client.enqueue(Fixtures.failure(409, code: "CHECKLIST_CONFLICT", retryable: false))
        let engine = makeEngine(store: try store(), client: client)
        let op = try enqueue(engine)
        waitUntil { engine.operation(id: op.id)?.state == .needsAttention }

        client.enqueue(Fixtures.ok())
        engine.retryNow(operationId: op.id)
        waitUntil { engine.operation(id: op.id)?.state == .synced }
        XCTAssertEqual(client.recorded.map(\.operationId), [op.id, op.id])
        XCTAssertNil(engine.operation(id: op.id)?.attentionReason)
    }

    func testTwoHundredWithDeclaredFailureIsParkedNotCelebrated() throws {
        client.enqueue(Fixtures.ok(["success": "0", "message": "Checklist already exists for this order product"]))
        let engine = makeEngine(store: try store(), client: client)
        let op = try enqueue(engine)
        waitUntil { engine.operation(id: op.id)?.state == .needsAttention }
        XCTAssertEqual(engine.operation(id: op.id)?.attempts.lastErrorCode, "DECLARED_FAILURE")
    }

    // MARK: Authentication gate

    func testA401PausesTheEngineUntilAuthenticationIsRestored() throws {
        client.enqueue(Fixtures.failure(401, code: "UNAUTHENTICATED", retryable: false, message: "Unauthenticated."))
        let engine = makeEngine(store: try store(), client: client)
        let op = try enqueue(engine)

        waitUntil("paused") { engine.pause == .authentication }
        XCTAssertEqual(state(engine, op.id), .pending, "operation is kept")

        engine.kick(reason: "should be ignored while paused", ignoreBackoff: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(client.requestCount, 1, "no blind retries while paused")

        client.defaultResult = Fixtures.ok()
        engine.authenticationRestored()
        waitUntil { engine.operation(id: op.id)?.state == .synced }
        XCTAssertEqual(engine.pause, .none)
    }

    func testAHandlerWithoutASessionPausesInsteadOfFailingTheOperation() throws {
        var loggedIn = false
        let handler = TestOperationHandler(authenticated: { loggedIn })
        client.defaultResult = Fixtures.ok()
        let engine = makeEngine(store: try store(), client: client, handler: handler)
        let op = try enqueue(engine)

        waitUntil { engine.pause == .authentication }
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertEqual(state(engine, op.id), .pending)

        loggedIn = true
        engine.authenticationRestored()
        waitUntil { engine.operation(id: op.id)?.state == .synced }
    }

    // MARK: Ordering and non-blocking

    func testATemporaryFailureStopsThePassAndPreservesOrderWithinAnIdentity() throws {
        client.enqueue(Fixtures.failure(500, code: "SERVER_ERROR"))
        let engine = makeEngine(store: try store(), client: client, backoff: [60])
        let first = try enqueue(engine, product: "ORD-SCH-1", captured: Date().addingTimeInterval(-120))
        let second = try enqueue(engine, product: "ORD-SCH-1", captured: Date())

        waitUntil { engine.operation(id: first.id)?.attempts.attemptCount == 1 }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(client.requestCount, 1, "the later step for the same product is not sent ahead of the failed one")
        XCTAssertEqual(state(engine, second.id), .pending)

        client.defaultResult = Fixtures.ok()
        engine.kick(reason: "network restored", ignoreBackoff: true)
        waitUntil { engine.operation(id: second.id)?.state == .synced }
        XCTAssertEqual(client.recorded.map(\.operationId), [first.id, first.id, second.id])
    }

    // Driver Delivery Process Flow (2026-09-27) §3.4.6: one order product's operations drain in
    // ENQUEUE order (queuedAt — the screens enqueue each step as the driver takes it, so this is
    // the capture order in practice), so the server sees switch → availability → On My Way and
    // the departure lock cannot refuse the legitimate pre-departure work; a parked op never
    // blocks the rest.
    private struct DepartureHandler: SyncOperationHandler {
        let operationType: String
        func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
            var body = operation.payload.objectValue ?? [:]
            body["operation_id"] = .string(operation.id)
            return SyncHTTPRequest(method: "POST", path: operation.type, headers: ["X-Operation-Id": operation.id],
                                   jsonBody: .object(body), operationId: operation.id)
        }
    }

    private func departureEngine() throws -> SyncEngine {
        SyncEngine(store: try store(), httpClient: client,
                   handlers: [DepartureHandler(operationType: PreparationOperationBuilder.substitutionType),
                              DepartureHandler(operationType: AssemblyOperationBuilder.availabilityType),
                              DepartureHandler(operationType: EffectiveFieldState.driverChecklistType)],
                   policy: SyncRetryPolicy(backoffSchedule: [0.05]))
    }

    private func departureSequence(_ engine: SyncEngine, product: String = "ORD-SCH-1") throws -> [SyncOperation] {
        let t0 = Date().addingTimeInterval(-600)
        let switchOp = try engine.enqueue(type: PreparationOperationBuilder.substitutionType,
                                          payload: .object(["order_product_unique_id": .string(product), "equipment_unique_id": .string("EQP-B"), "performed_by": .string("PER-1")]),
                                          identity: SyncBusinessIdentity(orderProductUniqueId: product, equipmentUniqueId: "EQP-B"),
                                          capturedAt: t0, displayTitle: "switch")
        let availability = try engine.enqueue(type: AssemblyOperationBuilder.availabilityType,
                                              payload: .object(["order_product_unique_id": .string(product), "subject_type": .string("unit"), "subject_key": .string("EQP-B"), "state": .string("available"), "performed_by": .string("PER-1")]),
                                              identity: SyncBusinessIdentity(orderProductUniqueId: product, equipmentUniqueId: "EQP-B"),
                                              capturedAt: t0.addingTimeInterval(60), displayTitle: "available")
        let onMyWay = try engine.enqueue(type: EffectiveFieldState.driverChecklistType,
                                         payload: .object(["order_product_unique_id": .string(product), "checklist_type": .string("delivery"), "equipment_driver_status": .string("On My Way"), "equipment_unique_id": .string("EQP-B")]),
                                         identity: SyncBusinessIdentity(orderProductUniqueId: product),
                                         capturedAt: t0.addingTimeInterval(120), displayTitle: "On My Way")
        return [switchOp, availability, onMyWay]
    }

    func testSwitchThenAvailabilityThenOnMyWayDrainInCaptureOrder() throws {
        client.defaultResult = Fixtures.ok()
        let engine = try departureEngine()
        let ops = try departureSequence(engine)

        waitUntil { ops.allSatisfy { engine.operation(id: $0.id)?.state == .synced } }
        XCTAssertEqual(client.recorded.map(\.operationId), ops.map(\.id), "the server sees switch → availability → On My Way")
        XCTAssertEqual(client.recorded.map(\.path), [PreparationOperationBuilder.substitutionType, AssemblyOperationBuilder.availabilityType, EffectiveFieldState.driverChecklistType])
    }

    func testAParkedSwitchNeverHoldsBackTheDeparture() throws {
        // The office reassigned meanwhile: the switch is refused (409, terminal) and parks;
        // the availability and the On My Way behind it are still sent (D1 — never a lost departure).
        client.enqueue(Fixtures.failure(409, code: "QUEUE_ASSIGNMENT_CHANGED"), Fixtures.failure(409, code: "QUEUE_ASSIGNMENT_CHANGED"), Fixtures.ok())
        let engine = try departureEngine()
        let ops = try departureSequence(engine)

        waitUntil { engine.operation(id: ops[2].id)?.state == .synced }
        XCTAssertEqual(state(engine, ops[0].id), .needsAttention)
        XCTAssertEqual(state(engine, ops[1].id), .needsAttention)
        XCTAssertEqual(state(engine, ops[2].id), .synced, "the departure is recorded whatever happened to the switch")
        XCTAssertEqual(client.recorded.map(\.operationId), ops.map(\.id), "still strictly in enqueue order")
    }

    func testANeedsAttentionOperationDoesNotBlockTheQueue() throws {
        client.enqueue(Fixtures.failure(422, code: "VALIDATION_FAILED"), Fixtures.ok())
        let engine = makeEngine(store: try store(), client: client)
        let bad = try enqueue(engine, product: "ORD-SCH-1")
        let good = try enqueue(engine, product: "ORD-SCH-2")

        waitUntil { engine.operation(id: good.id)?.state == .synced }
        XCTAssertEqual(state(engine, bad.id), .needsAttention)
        XCTAssertEqual(engine.summary().needsAttention, 1)
        XCTAssertEqual(engine.summary().synced, 1)
    }

    // MARK: Housekeeping

    func testDiscardIsExplicitAndRemovesTheRecord() throws {
        let engine = makeEngine(store: try store(), client: client)
        let op = try enqueue(engine)
        waitUntil { engine.operation(id: op.id)?.attempts.attemptCount == 1 }
        try engine.discard(operationId: op.id)
        XCTAssertNil(engine.operation(id: op.id))
        XCTAssertNil(try FileSyncOperationStore(rootDirectory: dir).load(id: op.id))
        XCTAssertThrowsError(try engine.discard(operationId: op.id))
    }

    func testPruneRemovesOnlyOldSyncedRecords() throws {
        client.defaultResult = Fixtures.ok()
        let engine = makeEngine(store: try store(), client: client)
        let synced = try enqueue(engine)
        waitUntil { engine.operation(id: synced.id)?.state == .synced }

        client.defaultResult = .failure(APIError.transport(.offline))
        let pending = try enqueue(engine, product: "ORD-SCH-9")
        waitUntil { engine.operation(id: pending.id)?.attempts.attemptCount == 1 }

        engine.pruneSynced(now: Date().addingTimeInterval(30 * 24 * 3600))
        waitUntil { engine.operation(id: synced.id) == nil }
        XCTAssertNotNil(engine.operation(id: pending.id), "un-synced work is never pruned")
    }

    func testEnqueueRejectsNonObjectPayloads() throws {
        let engine = makeEngine(store: try store(), client: client)
        XCTAssertThrowsError(try engine.enqueue(type: TestOperationHandler.type, payload: .string("x"), capturedAt: Date()))
    }

    func testBackoffScheduleIsCappedNotExhausted() {
        let policy = SyncRetryPolicy(backoffSchedule: [30, 60, 120, 300, 900])
        XCTAssertEqual(policy.delay(afterAttempt: 1), 30)
        XCTAssertEqual(policy.delay(afterAttempt: 5), 900)
        XCTAssertEqual(policy.delay(afterAttempt: 500), 900, "attempt 500 still retries — nothing is ever dropped")
    }

    func testDiagnosticsAreSanitisedAndOrdered() throws {
        client.enqueue(Fixtures.failure(422, code: "VALIDATION_FAILED", message: "token Bearer abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJ for a@b.com"), Fixtures.ok())
        let engine = makeEngine(store: try store(), client: client)
        let bad = try enqueue(engine, product: "ORD-SCH-1")
        let good = try enqueue(engine, product: "ORD-SCH-2")
        waitUntil { engine.operation(id: good.id)?.state == .synced && engine.operation(id: bad.id)?.state == .needsAttention }

        let entries = engine.diagnostics()
        XCTAssertEqual(entries.map(\.operationId), [bad.id, good.id], "needs attention first")
        XCTAssertEqual(entries[0].stateLabel, "Needs Attention")
        XCTAssertEqual(entries[1].stateLabel, "Synced")
        let summary = try XCTUnwrap(entries[0].errorSummary)
        XCTAssertFalse(summary.contains("abcdefghijklmnopqrstuvwxyz0123456789"))
        XCTAssertFalse(summary.contains("a@b.com"))
        XCTAssertTrue(summary.contains("[redacted]"))
        XCTAssertEqual(engine.summary().line, "1 needs attention")
    }
}
