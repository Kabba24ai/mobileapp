//
//  NextStopRouteEventsSyncReviewTests.swift
//  KabbaSyncCoreTests — MOBILE-QUALITY-01 item 05: the Next Stop answers built on the
//  route-events branch (9b768e2) keep their guarantees under the new sync review and
//  Sync Now: every answer is durable offline and across a relaunch, carries the driver's
//  own tap time and employee, is sent once (same operation id), a refusal parks only that
//  answer, is explained and removable, and never touches mission work.
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

private struct RouteEventHandler: SyncOperationHandler {
    var operationType: String { NextStopRouteEventOperation.operationType }
    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        try NextStopRouteEventOperation.request(for: operation)
    }
}

/// Answers by path; records every request. `refuse` = (status, code) for the Next Stop route.
private final class RouteClient: SyncHTTPClient {
    private let lock = NSLock()
    var offline = false
    var refuse: (Int, String)?
    private(set) var requests: [SyncHTTPRequest] = []

    func perform(_ request: SyncHTTPRequest, completion: @escaping (SyncHTTPResult) -> Void) {
        let (offline, refuse) = lock.withLock { () -> (Bool, (Int, String)?) in
            requests.append(request)
            return (self.offline, self.refuse)
        }
        if offline {
            completion(.failure(APIError.transport(.offline, description: "route test: offline")))
        } else if let (status, code) = refuse, request.path == NextStopRouteEventOperation.path {
            completion(Fixtures.failure(status, code: code, retryable: false, message: "Refused."))
        } else {
            completion(Fixtures.ok())
        }
    }

    var nextStopRequests: [SyncHTTPRequest] { lock.withLock { requests.filter { $0.path == NextStopRouteEventOperation.path } } }
}

final class NextStopRouteEventsSyncReviewTests: XCTestCase {

    private var dir: URL!
    private let tapped = Date(timeIntervalSince1970: 1_792_000_000)

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func engine(_ client: RouteClient) -> SyncEngine {
        SyncEngine(store: try! FileSyncOperationStore(rootDirectory: dir), httpClient: client,
                   handlers: [RouteEventHandler(), TestOperationHandler()],
                   policy: SyncRetryPolicy(backoffSchedule: [60]))
    }

    private func syncNow(_ engine: SyncEngine) -> SyncPassReport? {
        var report: SyncPassReport?
        engine.syncNow(reason: "test") { report = $0 }
        waitUntil("report") { report != nil }
        return report
    }

    func testOfflineAnswersSurviveARelaunchAndSyncNowSendsEachOnceWithItsOwnTapAndDriver() throws {
        let client = RouteClient()
        client.offline = true
        let first = engine(client)
        let answers = [
            try XCTUnwrap(NextStopRouteEvent.nextMission(from: .orderLeg(orderProductUniqueId: "ORD-SCH-A", isReturn: false),
                                                          to: .orderLeg(orderProductUniqueId: "ORD-SCH-B", isReturn: false),
                                                          headingToShop: false, at: tapped)),
            try XCTUnwrap(NextStopRouteEvent.returnToShop(from: .orderLeg(orderProductUniqueId: "ORD-SCH-B", isReturn: false),
                                                           shopUniqueId: "STO-1", at: tapped.addingTimeInterval(1800))),
            try XCTUnwrap(NextStopRouteEvent.arrivedAtShop(shopUniqueId: "STO-1", at: tapped.addingTimeInterval(3600))),
        ]
        let ops = try answers.map { try NextStopRouteEventOperation.enqueue(into: first, event: $0, employeeId: 7) }
        waitUntil("all attempted offline") { ops.allSatisfy { (first.operation(id: $0.id)?.attempts.attemptCount ?? 0) >= 1 } }
        XCTAssertEqual(syncNow(first)?.headline, "Couldn't reach Kabba.")

        // Relaunch: the answers are still there, and Sync Now sends them once each.
        client.offline = false
        let relaunched = engine(client)
        let report = try XCTUnwrap(syncNow(relaunched))
        XCTAssertEqual(report.sent, 3)
        XCTAssertEqual(report.needsAttention, 0)

        let sent = client.nextStopRequests.suffix(3)
        XCTAssertEqual(sent.map(\.operationId), ops.map(\.id), "the same operation ids — idempotent replays, never new answers")
        XCTAssertEqual(sent.map { $0.jsonBody?["captured_at"]?.stringValue }, [
            KabbaISO8601.string(from: tapped),
            KabbaISO8601.string(from: tapped.addingTimeInterval(1800)),
            KabbaISO8601.string(from: tapped.addingTimeInterval(3600)),
        ], "each answer keeps the moment the driver tapped")
        XCTAssertTrue(sent.allSatisfy { $0.jsonBody?["employee_id"] == .number(7) }, "the driver who tapped travels with every answer")

        let before = client.nextStopRequests.count
        XCTAssertTrue(try XCTUnwrap(syncNow(relaunched)).nothingToSend)
        XCTAssertEqual(client.nextStopRequests.count, before, "nothing is sent twice")
    }

    func testARefusedAnswerIsExplainedRemovableAndNeverHoldsUpMissionWork() throws {
        let client = RouteClient()
        client.refuse = (403, "FORBIDDEN")
        let e = engine(client)
        let answer = try NextStopRouteEventOperation.enqueue(into: e, event: XCTUnwrap(NextStopRouteEvent.arrivedAtShop(shopUniqueId: "STO-1", at: tapped)), employeeId: 7)
        let mission = try e.enqueue(type: TestOperationHandler.type, payload: Fixtures.payload,
                                    identity: SyncBusinessIdentity(orderProductUniqueId: "ORD-SCH-A"), capturedAt: tapped)
        waitUntil("answer parked, mission synced") {
            e.operation(id: answer.id)?.state == .needsAttention && e.operation(id: mission.id)?.state == .synced
        }

        let review = SyncRecordReview.of(try XCTUnwrap(e.operation(id: answer.id)))
        XCTAssertEqual(review.explanation?.headline, "Your account isn't allowed to do this")
        XCTAssertEqual(review.removalConsequence, "This Next Stop answer will not be counted in Driver Efficiency.")
        XCTAssertFalse(review.contents.holdsCapturedWork, "an answer is a tap, not captured inspection work")
        XCTAssertFalse(review.officeSees, "Next Stop answers are not on the office's Mobile Sync Issues list")

        let report = try XCTUnwrap(syncNow(e))
        XCTAssertEqual(report.needsAttention, 1)
        XCTAssertEqual(client.nextStopRequests.count, 1, "Sync Now never resends a refused answer")

        try e.remove(operationId: answer.id)
        XCTAssertNil(e.operation(id: answer.id))
        XCTAssertEqual(e.operation(id: mission.id)?.state, .synced, "the mission's own record is untouched")
        XCTAssertEqual(try XCTUnwrap(syncNow(e)).headline, "Nothing waiting to send — everything is synced.")
    }
}
