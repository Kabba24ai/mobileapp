//
//  SyncCaptureOrderTests.swift
//  KabbaSyncCoreTests — 1.0.28 release gate: work captured close together keeps its
//  capture order through offline capture, relaunch, retry and an intermittent network.
//
//  Stored records used to keep queue times to the whole second, so records queued in the
//  same second tied after a relaunch and one order line's steps could leave out of order.
//  Every test here freezes the clock (the worst case: a whole driver's day captured in one
//  instant) and checks that one line's steps reach Kabba in capture order, that a Next Stop
//  answer or another line is never held up by a line that is waiting, and that each record
//  is sent once (a retry reuses its operation id).
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Sends a record to a path named after its type; Next Stop answers use their real request.
private struct PathHandler: SyncOperationHandler {
    let operationType: String
    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        if operationType == NextStopRouteEventOperation.operationType {
            return try NextStopRouteEventOperation.request(for: operation)
        }
        var body = operation.payload.objectValue ?? [:]
        body["operation_id"] = .string(operation.id)
        return SyncHTTPRequest(method: "POST", path: operation.type, headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body), operationId: operation.id)
    }
}

final class SyncCaptureOrderTests: XCTestCase {

    private var dir: URL!
    private let instant = Date(timeIntervalSince1970: 1_792_000_000.4)

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private static let types = [
        EffectiveFieldState.driverChecklistType,
        EffectiveFieldState.deliveryPrepareType,
        EffectiveFieldState.deliveryCompleteType,
        EffectiveFieldState.returnPrepareType,
        EffectiveFieldState.returnCompleteType,
        NextStopRouteEventOperation.operationType,
    ]

    private func engine(_ client: FakeSyncHTTPClient, clock: Date? = nil) throws -> SyncEngine {
        let frozen = clock ?? instant
        return SyncEngine(store: try FileSyncOperationStore(rootDirectory: dir), httpClient: client,
                          handlers: Self.types.map(PathHandler.init(operationType:)),
                          policy: SyncRetryPolicy(backoffSchedule: [60]),
                          clock: { frozen })
    }

    private func offline() -> FakeSyncHTTPClient { FakeSyncHTTPClient() }   // default result = offline

    private func online() -> FakeSyncHTTPClient {
        let client = FakeSyncHTTPClient()
        client.defaultResult = Fixtures.ok()
        return client
    }

    @discardableResult
    private func step(_ engine: SyncEngine, _ type: String, line: String, captured: Date) throws -> SyncOperation {
        try engine.enqueue(type: type,
                           payload: .object(["order_product_unique_id": .string(line)]),
                           identity: SyncBusinessIdentity(orderProductUniqueId: line),
                           capturedAt: captured)
    }

    /// One delivery: On My Way, the checklist's preparation, then its completion.
    private func delivery(_ engine: SyncEngine, line: String, at start: Date) throws -> [SyncOperation] {
        [try step(engine, EffectiveFieldState.driverChecklistType, line: line, captured: start),
         try step(engine, EffectiveFieldState.deliveryPrepareType, line: line, captured: start.addingTimeInterval(600)),
         try step(engine, EffectiveFieldState.deliveryCompleteType, line: line, captured: start.addingTimeInterval(900))]
    }

    private func answer(_ engine: SyncEngine, _ event: NextStopRouteEvent?) throws -> SyncOperation {
        try NextStopRouteEventOperation.enqueue(into: engine, event: XCTUnwrap(event), employeeId: 7)
    }

    private func sent(_ client: FakeSyncHTTPClient, line: String) -> [String] {
        client.recorded.filter { $0.jsonBody?["order_product_unique_id"]?.stringValue == line }.map(\.operationId)
    }

    // MARK: - Offline capture → relaunch → connection back

    func testADriversDayCapturedOfflineInOneInstantIsSentInCaptureOrderAfterRelaunches() throws {
        let t0 = instant.addingTimeInterval(-7200)
        let first = try engine(offline())
        var captured: [SyncOperation] = []
        captured += try delivery(first, line: "ORD-SCH-A", at: t0)
        captured.append(try answer(first, .nextMission(from: .orderLeg(orderProductUniqueId: "ORD-SCH-A", isReturn: false),
                                                       to: .orderLeg(orderProductUniqueId: "ORD-SCH-B", isReturn: false),
                                                       headingToShop: false, at: t0.addingTimeInterval(960))))
        captured += try delivery(first, line: "ORD-SCH-B", at: t0.addingTimeInterval(1800))
        captured.append(try answer(first, .returnToShop(from: .orderLeg(orderProductUniqueId: "ORD-SCH-B", isReturn: false),
                                                        shopUniqueId: "STO-1", at: t0.addingTimeInterval(2760))))
        captured.append(try answer(first, .arrivedAtShop(shopUniqueId: "STO-1", at: t0.addingTimeInterval(4560))))
        waitUntil("first attempt failed offline") { first.operation(id: captured[0].id)?.attempts.attemptCount == 1 }

        // Queue times are strictly increasing and never format alike once stored.
        let queued = first.snapshot().map(\.queuedAt)
        XCTAssertEqual(first.snapshot().map(\.id), captured.map(\.id))
        for (a, b) in zip(queued, queued.dropFirst()) { XCTAssertGreaterThanOrEqual(b.timeIntervalSince(a), 0.002 - 1e-6) }
        XCTAssertEqual(captured.map(\.capturedAt), first.snapshot().map(\.capturedAt), "the moment of the work is never touched")

        // Relaunch while still offline, then again with the connection back.
        let stillOffline = try engine(offline())
        XCTAssertEqual(stillOffline.snapshot().map(\.id), captured.map(\.id), "a relaunch reads the same order")
        let client = online()
        let relaunched = try engine(client)
        relaunched.kick(reason: "connection back", ignoreBackoff: true)
        waitUntil("everything synced") { captured.allSatisfy { relaunched.operation(id: $0.id)?.state == .synced } }

        XCTAssertEqual(client.recorded.map(\.operationId), captured.map(\.id), "sent exactly in capture order, each once")
        XCTAssertEqual(sent(client, line: "ORD-SCH-A"), captured[0...2].map(\.id))
        XCTAssertEqual(sent(client, line: "ORD-SCH-B"), captured[4...6].map(\.id))
        XCTAssertEqual(client.recorded.filter { $0.path == NextStopRouteEventOperation.path }.map { $0.jsonBody?["captured_at"]?.stringValue },
                       [captured[3], captured[7], captured[8]].map { KabbaISO8601.string(from: $0.capturedAt) },
                       "each answer keeps the driver's own tap time on the wire (whole seconds, as before)")
    }

    // MARK: - Retry

    func testAWaitingLineKeepsItsOrderAndHoldsUpNoOtherLineAndNoNextStopAnswer() throws {
        let client = online()
        client.enqueue(Fixtures.failure(503, code: "SERVER_ERROR"))      // the first record of line A
        let e = try engine(client)
        let lineA = try delivery(e, line: "ORD-SCH-A", at: instant.addingTimeInterval(-3600))
        let next = try answer(e, .arrivedAtShop(shopUniqueId: "STO-1", at: instant.addingTimeInterval(-60)))
        let lineB = try delivery(e, line: "ORD-SCH-B", at: instant.addingTimeInterval(-1800))
        waitUntil("line A's first record waits for its retry") { e.operation(id: lineA[0].id)?.attempts.attemptCount == 1 }

        // The next trigger (a new capture, the app coming forward) sends everything that is not
        // behind line A's waiting record.
        e.kick(reason: "app became active")
        waitUntil("the other line and the answer are sent") {
            ([next] + lineB).allSatisfy { e.operation(id: $0.id)?.state == .synced }
        }
        XCTAssertEqual(lineA.map { e.operation(id: $0.id)?.state }, [.pending, .pending, .pending],
                       "line A's later steps never overtake its waiting first step")
        XCTAssertEqual(sent(client, line: "ORD-SCH-A"), [lineA[0].id])

        // A relaunch before the retry time, then the connection is fine: line A in order.
        let relaunchedClient = online()
        let relaunched = try engine(relaunchedClient)
        relaunched.kick(reason: "connection back", ignoreBackoff: true)
        waitUntil("line A synced") { lineA.allSatisfy { relaunched.operation(id: $0.id)?.state == .synced } }
        XCTAssertEqual(relaunchedClient.recorded.map(\.operationId), lineA.map(\.id))
        XCTAssertEqual(sent(client, line: "ORD-SCH-B") + sent(relaunchedClient, line: "ORD-SCH-B"), lineB.map(\.id), "never sent twice")
    }

    // MARK: - Intermittent network

    func testAnIntermittentConnectionNeverReordersALineAndReusesEachOperationId() throws {
        let client = online()
        client.enqueue(Fixtures.ok(),
                       .failure(APIError.transport(.offline, description: "dropped")),
                       Fixtures.ok(),
                       .failure(APIError.transport(.connectionLost)))
        let e = try engine(client)
        let returnLeg = [
            try step(e, EffectiveFieldState.driverChecklistType, line: "ORD-SCH-R", captured: instant.addingTimeInterval(-900)),
            try step(e, EffectiveFieldState.returnPrepareType, line: "ORD-SCH-R", captured: instant.addingTimeInterval(-600)),
            try step(e, EffectiveFieldState.returnCompleteType, line: "ORD-SCH-R", captured: instant.addingTimeInterval(-300)),
        ]
        waitUntil("the second record dropped") { e.operation(id: returnLeg[1].id)?.attempts.attemptCount == 1 }
        e.kick(reason: "connection back", ignoreBackoff: true)
        waitUntil("the third record dropped") { e.operation(id: returnLeg[2].id)?.attempts.attemptCount == 1 }

        let relaunched = try engine(client)
        relaunched.kick(reason: "connection back", ignoreBackoff: true)
        waitUntil("all synced") { returnLeg.allSatisfy { relaunched.operation(id: $0.id)?.state == .synced } }

        let ids = returnLeg.map(\.id)
        XCTAssertEqual(client.recorded.map(\.operationId), [ids[0], ids[1], ids[1], ids[2], ids[2]],
                       "each step goes after the one before it; a resend reuses the step's own operation id")
    }

    // MARK: - Relaunch details

    func testWorkCapturedAfterARelaunchQueuesBehindWhatIsWaitingEvenIfTheClockMovedBack() throws {
        let before = try engine(offline())
        let waiting = try delivery(before, line: "ORD-SCH-A", at: instant.addingTimeInterval(-600))
        waitUntil { before.operation(id: waiting[0].id)?.attempts.attemptCount == 1 }

        let client = online()
        let after = try engine(client, clock: instant.addingTimeInterval(-30))     // the phone's clock was set back
        let later = try step(after, EffectiveFieldState.driverChecklistType, line: "ORD-SCH-A", captured: instant.addingTimeInterval(-29))
        XCTAssertGreaterThan(later.queuedAt, waiting[2].queuedAt)
        after.kick(reason: "connection back", ignoreBackoff: true)
        waitUntil { after.operation(id: later.id)?.state == .synced }
        XCTAssertEqual(client.recorded.map(\.operationId), (waiting + [later]).map(\.id))
    }

    func testRecordsStoredByAnEarlierBuildLoadAndKeepAStableOrder() throws {
        // 1.0.27 stored whole seconds: rewrite three stored records that way, all in one second.
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let second = Date(timeIntervalSince1970: 1_792_000_000)
        let records = [
            SyncOperation(id: "C-LAST", type: EffectiveFieldState.deliveryCompleteType, capturedAt: second.addingTimeInterval(2),
                          queuedAt: second.addingTimeInterval(0.9), identity: SyncBusinessIdentity(orderProductUniqueId: "ORD-SCH-OLD"),
                          payload: .object(["order_product_unique_id": .string("ORD-SCH-OLD")])),
            SyncOperation(id: "B-MIDDLE", type: EffectiveFieldState.deliveryPrepareType, capturedAt: second.addingTimeInterval(1),
                          queuedAt: second.addingTimeInterval(0.5), identity: SyncBusinessIdentity(orderProductUniqueId: "ORD-SCH-OLD"),
                          payload: .object(["order_product_unique_id": .string("ORD-SCH-OLD")])),
            SyncOperation(id: "A-FIRST", type: EffectiveFieldState.driverChecklistType, capturedAt: second,
                          queuedAt: second.addingTimeInterval(0.1), identity: SyncBusinessIdentity(orderProductUniqueId: "ORD-SCH-OLD"),
                          payload: .object(["order_product_unique_id": .string("ORD-SCH-OLD")])),
        ]
        for record in records { try store.save(record) }
        let files = try FileManager.default.contentsOfDirectory(at: store.operationsDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3)
        for file in files {
            let stored = try String(contentsOf: file, encoding: .utf8)
            XCTAssertTrue(stored.range(of: #"T\d\d:\d\d:\d\d\.\d{3}"#, options: .regularExpression) != nil, "this build stores milliseconds")
            let legacy = stored.replacingOccurrences(of: #"(T\d\d:\d\d:\d\d)\.\d{3}"#, with: "$1", options: .regularExpression)
            try Data(legacy.utf8).write(to: file)
        }

        let client = online()
        let e = try engine(client)
        XCTAssertEqual(e.snapshot().map(\.id), ["A-FIRST", "B-MIDDLE", "C-LAST"], "tied queue times fall back to capture time")
        XCTAssertTrue(e.snapshot().allSatisfy { $0.queuedAt == second }, "the earlier build's times load as they were stored")
        e.kick(reason: "launch", ignoreBackoff: true)
        waitUntil { e.operation(id: "C-LAST")?.state == .synced }
        XCTAssertEqual(client.recorded.map(\.operationId), ["A-FIRST", "B-MIDDLE", "C-LAST"])
    }

    func testTheQueueOrderIsTotal() {
        let t = Date(timeIntervalSince1970: 1_792_000_000)
        func op(_ id: String, queued: Date, captured: Date) -> SyncOperation {
            SyncOperation(id: id, type: TestOperationHandler.type, capturedAt: captured, queuedAt: queued, payload: Fixtures.payload)
        }
        let ops = [op("b", queued: t, captured: t), op("a", queued: t, captured: t),
                   op("c", queued: t, captured: t.addingTimeInterval(-1)), op("d", queued: t.addingTimeInterval(-0.002), captured: t)]
        for _ in 0..<20 {
            XCTAssertEqual(ops.shuffled().sorted(by: SyncEngine.queueOrder).map(\.id), ["d", "c", "a", "b"])
        }
    }
}
