import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// The App handler is a thin session check around the Core request factory.
private struct RouteEventTestHandler: SyncOperationHandler {
    var operationType: String { NextStopRouteEventOperation.operationType }
    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        try NextStopRouteEventOperation.request(for: operation)
    }
    func interpret(_ response: SyncHTTPResponse, for operation: SyncOperation, now: Date) -> SyncOutcome {
        NextStopRouteEventOperation.interpret(response, now: now)
    }
}

/// Next Stop route events (2026-10-20): each answer on the Next Stop screen is
/// one durable, idempotent Sync Engine operation carrying the moment the
/// driver tapped — so an offline stretch delivers every answer once, late, on
/// the driver's own clock.
final class NextStopRouteEventsTests: XCTestCase {

    private var dir: URL!
    private var client: FakeSyncHTTPClient!
    private let tapped = Date(timeIntervalSince1970: 1_792_000_000)

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
        client = FakeSyncHTTPClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func engine() -> SyncEngine {
        makeEngine(store: try! FileSyncOperationStore(rootDirectory: dir), client: client, handler: RouteEventTestHandler())
    }

    private func body(_ request: SyncHTTPRequest?) -> [String: JSONValue] {
        request?.jsonBody?.objectValue ?? [:]
    }

    // MARK: The answers

    func testCustomerAToCustomerBNamesTheLegJustFinishedAndTheMissionChosen() throws {
        let event = try XCTUnwrap(NextStopRouteEvent.nextMission(
            from: .orderLeg(orderProductUniqueId: "ORD-SCH-A", isReturn: false),
            to: .orderLeg(orderProductUniqueId: "ORD-SCH-B", isReturn: true),
            headingToShop: false, at: tapped))

        XCTAssertEqual(event.payload, [
            "event": .string("next_mission"),
            "from_type": .string("order_product"), "from_unique_id": .string("ORD-SCH-A"), "from_leg": .string("delivery"),
            "to_type": .string("order_product"), "to_unique_id": .string("ORD-SCH-B"), "to_leg": .string("return"),
            "heading_to_shop": .bool(false),
        ])
    }

    func testAManualTaskAndAShopAreNamedByTheirOwnIds() throws {
        let fromShop = try XCTUnwrap(NextStopRouteEvent.nextMission(from: .shop(storeUniqueId: "STO-1"), to: .manualTask(uniqueId: "MDT-9"), headingToShop: false, at: tapped))
        XCTAssertEqual(fromShop.payload["from_type"], .string("store"))
        XCTAssertEqual(fromShop.payload["from_unique_id"], .string("STO-1"))
        XCTAssertNil(fromShop.payload["from_leg"])
        XCTAssertEqual(fromShop.payload["to_type"], .string("manual_task"))
        XCTAssertNil(fromShop.payload["to_leg"])

        let back = try XCTUnwrap(NextStopRouteEvent.returnToShop(from: .manualTask(uniqueId: "MDT-9"), shopUniqueId: "STO-2", at: tapped))
        XCTAssertEqual(back.payload["event"], .string("return_to_shop"))
        XCTAssertEqual(back.payload["to_type"], .string("store"))
        XCTAssertEqual(back.payload["to_unique_id"], .string("STO-2"))
        XCTAssertEqual(back.payload["from_unique_id"], .string("MDT-9"))

        let arrived = try XCTUnwrap(NextStopRouteEvent.arrivedAtShop(shopUniqueId: "STO-2", at: tapped))
        XCTAssertEqual(arrived.payload["event"], .string("arrived_at_shop"))
        XCTAssertNil(arrived.payload["from_type"], "an arrival names only the shop")
    }

    func testAMissionChosenOnTheWayToAShopSaysSo() throws {
        let event = try XCTUnwrap(NextStopRouteEvent.nextMission(from: .manualTask(uniqueId: "MDT-1"), to: .manualTask(uniqueId: "MDT-2"), headingToShop: true, at: tapped))
        XCTAssertEqual(event.payload["heading_to_shop"], .bool(true))
    }

    func testShapesTheServerWouldRefuseAreNeverBuilt() {
        XCTAssertNil(NextStopRouteEvent.nextMission(from: nil, to: .shop(storeUniqueId: "STO-1"), headingToShop: false, at: tapped),
                     "a shop is Return to Shop, not a mission")
        XCTAssertNil(NextStopRouteEvent.nextMission(from: nil, to: .manualTask(uniqueId: ""), headingToShop: false, at: tapped))
        XCTAssertNil(NextStopRouteEvent.returnToShop(from: nil, shopUniqueId: "", at: tapped))
        XCTAssertNil(NextStopRouteEvent.arrivedAtShop(shopUniqueId: "", at: tapped))
    }

    // MARK: The operation

    func testTheRequestCarriesTheOperationIdAndTheTapNotTheSync() throws {
        let event = try XCTUnwrap(NextStopRouteEvent.arrivedAtShop(shopUniqueId: "STO-1", at: tapped))
        client.defaultResult = Fixtures.ok()
        let e = engine()

        let op = try NextStopRouteEventOperation.enqueue(into: e, event: event, operationId: "NSE-0001")
        waitUntil("synced") { e.operation(id: op.id)?.state == .synced }

        let request = client.recorded.last
        XCTAssertEqual(request?.method, "POST")
        XCTAssertEqual(request?.path, "dispatch/next-stop/events")
        XCTAssertEqual(request?.headers["X-Operation-Id"], "NSE-0001")
        XCTAssertEqual(body(request)["operation_id"], .string("NSE-0001"))
        XCTAssertEqual(body(request)["captured_at"], .string(KabbaISO8601.string(from: tapped)))
        XCTAssertEqual(op.type, "next_stop.event")
        XCTAssertEqual(op.displayTitle, "Next Stop · Arrived at shop")
    }

    func testAnOfflineAnswerIsDurableSurvivesRelaunchAndIsSentOnceWithItsOriginalTime() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let first = engine()
        let event = try XCTUnwrap(NextStopRouteEvent.returnToShop(from: .orderLeg(orderProductUniqueId: "ORD-SCH-A", isReturn: true), shopUniqueId: "STO-1", at: tapped))
        let op = try NextStopRouteEventOperation.enqueue(into: first, event: event, operationId: "NSE-OFFLINE-1")
        waitUntil("first attempt") { self.client.requestCount >= 1 }
        XCTAssertEqual(first.operation(id: op.id)?.state, .pending, "offline keeps the answer, never drops it")

        // Relaunch, then signal returns hours later.
        let second = engine()
        client.defaultResult = Fixtures.ok()
        second.kick(reason: "reconnect", ignoreBackoff: true)
        waitUntil("synced") { second.operation(id: op.id)?.state == .synced }

        let sent = client.recorded.filter { $0.path == "dispatch/next-stop/events" }
        XCTAssertTrue(sent.allSatisfy { $0.headers["X-Operation-Id"] == "NSE-OFFLINE-1" }, "every attempt is the SAME operation — the server records it once")
        XCTAssertEqual(body(sent.last)["captured_at"], .string(KabbaISO8601.string(from: tapped)), "the driver's tap, not the reconnect")
    }

    func testAnAnswerHasItsOwnOrderingKeySoItNeverHoldsUpAMissionsOperations() throws {
        let event = try XCTUnwrap(NextStopRouteEvent.nextMission(from: .orderLeg(orderProductUniqueId: "ORD-SCH-A", isReturn: false),
                                                                to: .orderLeg(orderProductUniqueId: "ORD-SCH-B", isReturn: false),
                                                                headingToShop: false, at: tapped))
        client.defaultResult = .failure(APIError.transport(.offline))
        let op = try NextStopRouteEventOperation.enqueue(into: engine(), event: event)

        XCTAssertEqual(op.identity, SyncBusinessIdentity())
        XCTAssertEqual(op.orderingKey, op.id)
    }

    func testAServerWithoutTheEndpointYetMakesTheAnswerWaitNotNeedAttention() throws {
        let event = try XCTUnwrap(NextStopRouteEvent.arrivedAtShop(shopUniqueId: "STO-1", at: tapped))
        client.enqueue(.response(SyncHTTPResponse(statusCode: 404, body: Fixtures.json(["message": "The route api/admin/v1/dispatch/next-stop/events could not be found."]))))
        let e = engine()

        let op = try NextStopRouteEventOperation.enqueue(into: e, event: event, operationId: "NSE-EARLY-1")
        waitUntil("first attempt") { self.client.requestCount >= 1 }
        waitUntil("back to pending") { e.operation(id: op.id)?.state == .pending }
        XCTAssertNotEqual(e.operation(id: op.id)?.state, .needsAttention, "nothing for the driver to deal with")

        // The backend is deployed: the same answer is delivered.
        client.defaultResult = Fixtures.ok()
        e.kick(reason: "later", ignoreBackoff: true)
        waitUntil("synced") { e.operation(id: op.id)?.state == .synced }
    }

    func testAValidationRefusalStillNeedsAttention() throws {
        let event = try XCTUnwrap(NextStopRouteEvent.arrivedAtShop(shopUniqueId: "STO-1", at: tapped))
        client.defaultResult = .response(SyncHTTPResponse(statusCode: 422, body: Fixtures.json([
            "success": false, "message": "Validation failed.", "error": ["code": "VALIDATION_FAILED", "message": "Validation failed.", "retryable": false],
        ])))
        let e = engine()

        let op = try NextStopRouteEventOperation.enqueue(into: e, event: event)
        waitUntil("parked") { e.operation(id: op.id)?.state == .needsAttention }
    }

    func testAStoredOperationMissingItsDestinationNeedsAttentionInsteadOfSendingGarbage() {
        let op = SyncOperation(id: "NSE-BAD", type: "next_stop.event", capturedAt: tapped, queuedAt: tapped,
                               identity: SyncBusinessIdentity(), payload: .object(["event": .string("next_mission")]))

        XCTAssertThrowsError(try NextStopRouteEventOperation.request(for: op)) { error in
            guard case SyncHandlerError.invalidPayload = error else { return XCTFail("expected invalidPayload, got \(error)") }
        }
    }
}
