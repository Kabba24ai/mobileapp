//
//  StaleAvailabilityReconcilerHostedTests.swift
//  RentnKingHostedTests — P10 (2026-09-29, order #6024): the app-layer reconciler
//  judges a parked Available refused with QUEUE_ASSIGNMENT_CHANGED against the
//  unit this phone holds for the line — the cached Assembly Review — and retires
//  it only when that unit is the one the server named. Runs inside the app so the
//  real cache (tenant-scoped UserDefaults) and the real Core rule are exercised.
//

import XCTest
@testable import RentnKing

/// The hosted target has no Core test support: a scripted client and a poll helper of its own.
private final class ScriptedClient: SyncHTTPClient {
    var defaultResult: SyncHTTPResult = .failure(APIError.transport(.offline, description: "scripted: offline"))
    private(set) var requestCount = 0
    func perform(_ request: SyncHTTPRequest, completion: @escaping (SyncHTTPResult) -> Void) {
        requestCount += 1
        completion(defaultResult)
    }
}

final class StaleAvailabilityReconcilerHostedTests: XCTestCase {

    private var dir: URL!
    private var client: ScriptedClient!
    private var savedBaseURL: String?
    private let order = "ORD-P10-6024"
    private let product = "ORD-SCH-HRQ6-WQVH"
    private let unitA = "EQP-Z2TB-EBAL"
    private let unitB = "EQP-XUC3-POKU"
    private let unitBName = "P6 Skid Steer U31"

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("StaleAvailabilityReconcilerHostedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        client = ScriptedClient()
        savedBaseURL = UserDefaults.standard.baseURL
        UserDefaults.standard.baseURL = "https://stale-availability.invalid/api/admin/v1/"   // a tenant, no server
        KabbaAssemblySync.clearCache(orderUniqueId: order)
    }

    override func tearDown() {
        KabbaAssemblySync.clearCache(orderUniqueId: order)
        UserDefaults.standard.baseURL = savedBaseURL
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private struct AvailabilityHandler: SyncOperationHandler {
        let operationType = AssemblyOperationBuilder.availabilityType
        func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest { try AssemblyRequestFactory.availabilityRequest(for: operation) }
    }

    private func engine() -> SyncEngine {
        SyncEngine(store: try! FileSyncOperationStore(rootDirectory: dir), httpClient: client,
                   handlers: [AvailabilityHandler()], policy: SyncRetryPolicy(backoffSchedule: [0.05]))
    }

    private func assignmentChanged(current: (id: String, name: String)) -> SyncHTTPResult {
        let error: [String: Any] = ["code": "QUEUE_ASSIGNMENT_CHANGED",
                                    "message": "The assigned machine changed — this item now has \(current.name) assigned.",
                                    "retryable": false,
                                    "current_equipment": ["name": current.name, "unique_id": current.id, "display_id": "P6-U31"]]
        let body: [String: Any] = ["success": false, "message": error["message"]!, "error": error, "request_id": "ios-p10-409"]
        return .response(SyncHTTPResponse(statusCode: 409, headers: ["X-Request-Id": "ios-p10-409"], body: try! JSONSerialization.data(withJSONObject: body)))
    }

    private func refused(_ status: Int, code: String, message: String) -> SyncHTTPResult {
        let body: [String: Any] = ["success": false, "message": message, "error": ["code": code, "message": message, "retryable": false], "request_id": "ios-p10-4xx"]
        return .response(SyncHTTPResponse(statusCode: status, headers: [:], body: try! JSONSerialization.data(withJSONObject: body)))
    }

    private func poll(_ description: String, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }

    /// The fixture review with its first member as THIS line, assigned to `unit`, unconfirmed.
    private func cacheReview(unit: String, name: String) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KabbaSyncCore/Fixtures/queue_line_assembly.json")
        var envelope = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as! [String: Any]
        var data = envelope["data"] as! [String: Any]
        var orderObject = data["order"] as! [String: Any]; orderObject["unique_id"] = order; data["order"] = orderObject
        var groups = data["assemblies"] as! [[String: Any]]
        var members = groups[0]["members"] as! [[String: Any]]
        var m = members[0]
        m["order_product_unique_id"] = product; m["order_unique_id"] = order
        var identity = m["identity"] as! [String: Any]
        identity["order_product_unique_id"] = product; identity["order_unique_id"] = order; identity["equipment_unique_id"] = unit; m["identity"] = identity
        var equipment = m["equipment"] as! [String: Any]
        equipment["unique_id"] = unit; equipment["name"] = name; m["equipment"] = equipment
        var availability = m["availability"] as! [String: Any]
        availability["unit"] = ["equipment_unique_id": unit, "state": NSNull(), "acknowledged_by": NSNull(), "acknowledged_at": NSNull(), "note": NSNull()]
        m["availability"] = availability
        members[0] = m; groups[0]["members"] = members; data["assemblies"] = groups; envelope["data"] = data
        let bytes = try JSONSerialization.data(withJSONObject: envelope)
        XCTAssertNotNil(try? AssemblyReviewEnvelope.decode(bytes))
        XCTAssertTrue(KabbaAssemblySync.cache(bytes, orderUniqueId: order, tenantKey: try XCTUnwrap(KabbaTenantScope.currentKey)))
    }

    private func parkedAvailabilityOfA(in e: SyncEngine) throws -> SyncOperation {
        client.defaultResult = assignmentChanged(current: (unitB, unitBName))
        let capture = AvailabilityCapture(orderUniqueId: order, orderProductUniqueId: product, equipmentUniqueId: unitA,
                                          subject: .unit, subjectKey: unitA, state: .available, performedByUniqueId: "PER-5XNN-JURK")
        let op = try AssemblyOperationBuilder.enqueueAvailability(capture, into: e)
        poll("parked") { e.operation(id: op.id)?.state == .needsAttention }
        return op
    }

    func testTheReconcilerReadsTheCachedReviewAndRetiresOnlyWhenItHoldsTheUnitTheServerNamed() throws {
        let e = engine()
        let op = try parkedAvailabilityOfA(in: e)

        // No review cached for the order: the phone has not established the new unit — nothing moves.
        XCTAssertNil(StaleAvailabilityReconciler.canonicalUnit(orderUniqueId: order, orderProductUniqueId: product))
        XCTAssertEqual(StaleAvailabilityReconciler.run(engine: e), [])
        XCTAssertEqual(e.operation(id: op.id)?.state, .needsAttention)

        // The cached review still names A (the package has not refreshed): still nothing.
        try cacheReview(unit: unitA, name: "P6 Skid Steer U27")
        XCTAssertEqual(StaleAvailabilityReconciler.canonicalUnit(orderUniqueId: order, orderProductUniqueId: product)?.id, unitA)
        XCTAssertEqual(StaleAvailabilityReconciler.run(engine: e), [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(e.operation(id: op.id)?.state, .needsAttention)

        // The review now holds the unit the server named: the stale decision is retired, as history.
        try cacheReview(unit: unitB, name: unitBName)
        let canonical = StaleAvailabilityReconciler.canonicalUnit(orderUniqueId: order, orderProductUniqueId: product)
        XCTAssertEqual(canonical?.id, unitB)
        XCTAssertEqual(canonical?.name, unitBName)
        XCTAssertEqual(StaleAvailabilityReconciler.run(engine: e), [op.id])
        poll("superseded") { e.operation(id: op.id)?.state == .superseded }
        let retired = try XCTUnwrap(e.operation(id: op.id))
        XCTAssertEqual(retired.supersession?.supersededByEquipmentUniqueId, unitB)
        XCTAssertEqual(retired.supersession?.supersededByEquipmentName, unitBName)
        XCTAssertEqual(retired.supersession?.proof, .serverVerdict)
        XCTAssertEqual(retired.payload["subject_key"]?.stringValue, unitA, "history keeps the original decision")
        XCTAssertEqual(e.summary().needsAttention, 0)

        // A second pass finds nothing left to do; the record is not touched again.
        XCTAssertEqual(StaleAvailabilityReconciler.run(engine: e), [])
        XCTAssertEqual(AssemblyLocalOverlay.from(e.snapshot()).attentionReason(product), nil, "no Sync Issue for the line")
    }

    func testOnlyAParkedAvailabilityRefusedForAnAssignmentChangeConcernsTheReconciler() {
        var op = SyncOperation(type: AssemblyOperationBuilder.availabilityType, capturedAt: Date(),
                               identity: SyncBusinessIdentity(orderUniqueId: order, orderProductUniqueId: product, equipmentUniqueId: unitA),
                               payload: .object(["subject_type": .string("unit"), "subject_key": .string(unitA), "state": .string("available")]))
        op.state = .needsAttention
        op.attempts.lastErrorCode = "QUEUE_ASSIGNMENT_CHANGED"
        XCTAssertTrue(StaleAvailabilityReconciler.concerns(op))
        var other = op; other.attempts.lastErrorCode = "QUEUE_OPTION_UNKNOWN"
        XCTAssertFalse(StaleAvailabilityReconciler.concerns(other), "another rejection")
        var pending = op; pending.state = .pending
        XCTAssertFalse(StaleAvailabilityReconciler.concerns(pending), "not parked")
        var retired = op; retired.state = .superseded
        XCTAssertFalse(StaleAvailabilityReconciler.concerns(retired), "already retired — no loop")
        var switchOp = SyncOperation(type: PreparationOperationBuilder.substitutionType, capturedAt: Date(),
                                     identity: op.identity, payload: op.payload)
        switchOp.state = .needsAttention; switchOp.attempts.lastErrorCode = "QUEUE_ASSIGNMENT_CHANGED"
        XCTAssertFalse(StaleAvailabilityReconciler.concerns(switchOp), "a switch is never the reconciler's business")
    }

    func testAnUnrelatedParkedOperationOnTheSameLineIsLeftAlone() throws {
        let e = engine()
        client.defaultResult = refused(422, code: "QUEUE_OPTION_UNKNOWN", message: "That option is not part of this order line.")
        let capture = AvailabilityCapture(orderUniqueId: order, orderProductUniqueId: product, equipmentUniqueId: unitB,
                                          subject: .option, subjectKey: "POPT-GONE", state: .available, performedByUniqueId: "PER-5XNN-JURK")
        let op = try AssemblyOperationBuilder.enqueueAvailability(capture, into: e)
        poll("parked") { e.operation(id: op.id)?.state == .needsAttention }
        try cacheReview(unit: unitB, name: unitBName)
        XCTAssertEqual(StaleAvailabilityReconciler.run(engine: e), [])
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(e.operation(id: op.id)?.state, .needsAttention, "only the proven-obsolete unit Available is retired")
        XCTAssertNotNil(AssemblyLocalOverlay.from(e.snapshot()).attentionReason(product))
    }
}
