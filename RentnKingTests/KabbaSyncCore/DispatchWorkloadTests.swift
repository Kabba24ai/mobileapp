import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Dispatch parity (Phase 6A) — the mixed Dispatch contract on the Swift side:
/// the Manual Dispatch DTO decodes the SAME fixtures Laravel asserts it
/// produces (dispatch_list_mixed / dispatch_assignment_conflict /
/// manual_dispatch_status_updated, copied by Scripts/sync-contract-fixtures.sh),
/// the sort_key weave reproduces the web board's workday order, refresh
/// reconciliation is replace-not-merge, and the manual status-transition
/// operation carries the idempotency contract.
final class DispatchWorkloadTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let candidates = [
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).json"),
            Bundle(for: DispatchWorkloadTests.self).url(forResource: name, withExtension: "json"),
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }
        throw XCTSkip("Fixture \(name).json not synced — run Scripts/sync-contract-fixtures.sh")
    }

    private func fixtureJSON(_ name: String) throws -> [String: Any] {
        let data = try fixture(name)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // ── Mixed feed decoding ─────────────────────────────────────────────────

    func testMixedFeedFixtureCarriesOrdersAndManualJobs() throws {
        let body = try fixtureJSON("dispatch_list_mixed")

        let orders = try XCTUnwrap(body["orders"] as? [[String: Any]])
        XCTAssertFalse(orders.isEmpty)

        // Order rows carry the additive mixed-feed identity keys.
        let firstOrder = try XCTUnwrap(orders.first)
        XCTAssertEqual(firstOrder["dispatch_source"] as? String, "order")
        XCTAssertEqual(firstOrder["fulfillment_leg"] as? String, "delivery")
        let orderItemId = try XCTUnwrap(firstOrder["dispatch_item_id"] as? String)
        XCTAssertTrue(orderItemId.hasPrefix("order:"))
        XCTAssertTrue(orderItemId.hasSuffix(":delivery"))
        XCTAssertNotNil(firstOrder["sort_key"] as? String)

        // The manual job — no order, no product — decodes into the DTO with
        // its identity, driver and content intact.
        let manualArray = try XCTUnwrap(body["manual_jobs"] as? [[String: Any]])
        let manuals = DispatchManualJob.decodeList(fromJSONArray: manualArray)
        XCTAssertEqual(manuals.count, manualArray.count)

        let job = try XCTUnwrap(manuals.first)
        XCTAssertEqual(job.is_manual, true)
        XCTAssertEqual(job.dispatch_source, "manual")
        XCTAssertEqual(job.type, "Equipment Drop-Off")
        XCTAssertEqual(job.description, "Pick up repaired equipment")
        XCTAssertEqual(job.location_name, "Acme")
        XCTAssertTrue(job.dispatch_item_id?.hasPrefix("manual:") == true)
        XCTAssertNotNil(job.sort_key)
        XCTAssertNotNil(job.driver?.id)
    }

    func testManualJobWithoutOrderFieldsIsRetainedNotDropped() {
        // The bare minimum a manual task may carry — no order number, no
        // product, no customer, no checklist. It must decode, not vanish.
        let minimal: [[String: Any]] = [[
            "unique_id": "MDT-TEST-0001",
            "is_manual": true,
            "type": "Generic Errand",
            "status": "Assigned",
        ]]

        let jobs = DispatchManualJob.decodeList(fromJSONArray: minimal)
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.unique_id, "MDT-TEST-0001")
        XCTAssertNil(jobs.first?.sort_key)
    }

    func testAssignmentConflictFixtureIsTheCanonical409() throws {
        let body = try fixtureJSON("dispatch_assignment_conflict")
        let error = try XCTUnwrap(body["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "DISPATCH_ASSIGNMENT_CHANGED")
        XCTAssertEqual(error["retryable"] as? Bool, false)
        XCTAssertEqual(body["success"] as? Bool, false)
    }

    func testAssignmentConflictParksAsNeedsAttention() throws {
        // The REAL 409 body from Laravel, through the engine's classifier:
        // non-retryable → needsAttention — the captured work is kept, nothing
        // is retried automatically, and the card clears on the next refresh.
        let classified = APIErrorClassifier.classify(statusCode: 409,
                                                     body: try fixture("dispatch_assignment_conflict"),
                                                     headers: [:])
        XCTAssertEqual(classified.code, "DISPATCH_ASSIGNMENT_CHANGED")
        XCTAssertEqual(classified.serverRetryable, false)
        XCTAssertEqual(classified.disposition, .needsAttention)
    }

    func testManualStatusUpdatedFixtureAcknowledgesTheTransition() throws {
        let body = try fixtureJSON("manual_dispatch_status_updated")
        XCTAssertEqual(body["success"] as? Bool, true)
        XCTAssertEqual(body["status"] as? String, "On My Way")
    }

    // ── Workday weave (the web board's order) ───────────────────────────────

    func testWeaveOrdersTheMixedWorkdayBySortKey() {
        // Order legs: today prio 2, tomorrow prio 1. Manual: today prio 1.
        let rows = DispatchWorkload.weave(
            orderSortKeys: ["2026-08-29|00002", "2026-08-30|00001"],
            manualSortKeys: ["2026-08-29|00001"]
        )
        XCTAssertEqual(rows, [.manual(0), .order(0), .order(1)])
    }

    func testWeaveIsStableAndOrderLegsWinTies() {
        let rows = DispatchWorkload.weave(
            orderSortKeys: ["2026-08-29|00001", "2026-08-29|00001"],
            manualSortKeys: ["2026-08-29|00001", "2026-08-29|09999"]
        )
        // Equal keys: order legs first (web board concat order), sources stable.
        XCTAssertEqual(rows, [.order(0), .order(1), .manual(0), .manual(1)])
    }

    func testWeaveTreatsMissingSortKeysAsOpenEnded() {
        // A legacy row without a sort_key (or an undated pending return)
        // sorts after every dated item — the web board's NULLs-last rule.
        let rows = DispatchWorkload.weave(
            orderSortKeys: [nil],
            manualSortKeys: ["2026-08-29|00001"]
        )
        XCTAssertEqual(rows, [.manual(0), .order(0)])
    }

    func testManualTasksBelongToTheDeliveriesColumn() {
        XCTAssertTrue(DispatchWorkload.manualBelongs(inScheduleType: "All"))
        XCTAssertTrue(DispatchWorkload.manualBelongs(inScheduleType: "Delivery"))
        XCTAssertFalse(DispatchWorkload.manualBelongs(inScheduleType: "Return"))
    }

    // ── Refresh reconciliation: server truth replaces the cache ─────────────

    func testServerSnapshotReplacesTheCachedManualList() {
        var kept = DispatchManualJob(); kept.unique_id = "MDT-KEPT"
        var gone = DispatchManualJob(); gone.unique_id = "MDT-REASSIGNED-AWAY"
        var new_ = DispatchManualJob(); new_.unique_id = "MDT-NEWLY-ASSIGNED"

        let reconciled = DispatchWorkload.reconciledManualList(
            cached: [kept, gone],
            serverSnapshot: [kept, new_]
        )

        XCTAssertEqual(reconciled.map(\.unique_id), ["MDT-KEPT", "MDT-NEWLY-ASSIGNED"])
    }

    func testAnAbsentManualBlockClearsRatherThanResurrects() {
        var stale = DispatchManualJob(); stale.unique_id = "MDT-STALE"
        XCTAssertEqual(DispatchWorkload.reconciledManualList(cached: [stale], serverSnapshot: nil), [])
    }

    // ── Status lifecycle ────────────────────────────────────────────────────

    func testManualStatusLifecycle() {
        XCTAssertEqual(DispatchManualStatus.next(after: "Assigned"), "On My Way")
        XCTAssertEqual(DispatchManualStatus.next(after: "On My Way"), "Arrived")
        XCTAssertEqual(DispatchManualStatus.next(after: "Arrived"), "Completed")
        XCTAssertNil(DispatchManualStatus.next(after: "Completed"))
        XCTAssertNil(DispatchManualStatus.next(after: "Pending"))
        XCTAssertTrue(DispatchManualStatus.isTerminal("Completed"))
        XCTAssertTrue(DispatchManualStatus.isTerminal("Cancelled"))
        XCTAssertFalse(DispatchManualStatus.isTerminal("Arrived"))
    }

    // ── Business identity: the manual task key is durable + additive ────────

    func testBusinessIdentityCarriesTheManualTaskAndDecodesLegacyRecords() throws {
        let identity = SyncBusinessIdentity(manualTaskUniqueId: "MDT-0001")
        XCTAssertTrue(identity.summary.contains("manual task MDT-0001"))

        // A record persisted BEFORE the field existed still decodes.
        let legacy = #"{"orderUniqueId":"ORD-1"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SyncBusinessIdentity.self, from: legacy)
        XCTAssertEqual(decoded.orderUniqueId, "ORD-1")
        XCTAssertNil(decoded.manualTaskUniqueId)
    }

    // MARK: - Render-time driver membership (driver-filter reconciliation, 2026-09)

    func testAllDriversAlwaysBelongs() {
        XCTAssertTrue(DispatchWorkload.orderRowBelongs(selectedDriverId: nil, isDelivered: false,
                                                       deliveryEmployeeId: 7, pickupEmployeeId: 9))
    }

    func testPendingDeliveryBelongsToItsCurrentDeliveryDriverOnly() {
        // The reproduced defect: delivery reassigned Gary(7) → Jerome(9) while
        // the return leg still names Gary. The ACTIVE leg (pending delivery)
        // decides — the card leaves Gary's rendered workload on the same
        // rebuild, and appears under Jerome.
        XCTAssertFalse(DispatchWorkload.orderRowBelongs(selectedDriverId: 7, isDelivered: false,
                                                        deliveryEmployeeId: 9, pickupEmployeeId: 7),
                       "the old driver keeps the card only via the stale return leg — must be hidden")
        XCTAssertTrue(DispatchWorkload.orderRowBelongs(selectedDriverId: 9, isDelivered: false,
                                                       deliveryEmployeeId: 9, pickupEmployeeId: 7))
    }

    func testDeliveredRowBelongsToItsReturnDriver() {
        XCTAssertTrue(DispatchWorkload.orderRowBelongs(selectedDriverId: 7, isDelivered: true,
                                                       deliveryEmployeeId: 9, pickupEmployeeId: 7))
        XCTAssertFalse(DispatchWorkload.orderRowBelongs(selectedDriverId: 9, isDelivered: true,
                                                        deliveryEmployeeId: 9, pickupEmployeeId: 7),
                       "a completed delivery no longer keeps the row under the delivery driver")
    }

    func testMissingActiveLegEmployeeNeverHidesTheRow() {
        // The server scoped the row in; hiding on missing serialized data
        // would drop legitimate work.
        XCTAssertTrue(DispatchWorkload.orderRowBelongs(selectedDriverId: 7, isDelivered: false,
                                                       deliveryEmployeeId: nil, pickupEmployeeId: 9))
    }

    // MARK: - One-tap On My Way – Navigate (2026-09)

    private func statusOp(_ status: String, task: String, state: SyncState = .pending) -> SyncOperation {
        var op = SyncOperation(type: DispatchManualStatus.statusOperationType,
                               capturedAt: Date(),
                               identity: SyncBusinessIdentity(manualTaskUniqueId: task),
                               payload: .object(["status": .string(status)]))
        op.state = state
        return op
    }

    func testEffectiveStatusIsServerTruthWithoutLocalEvidence() {
        XCTAssertEqual(DispatchManualStatus.effectiveStatus(serverStatus: "Assigned", operations: [],
                                                            manualTaskUniqueId: "MDT-1"), "Assigned")
        XCTAssertEqual(DispatchManualStatus.effectiveStatus(serverStatus: "On My Way", operations: [],
                                                            manualTaskUniqueId: "MDT-1"), "On My Way")
    }

    func testDurableLocalOnMyWayUpgradesInEveryRetainedState() {
        // Pending Sync, currently syncing, server-confirmed, and retained
        // Needs Attention all mean the trip WAS recorded on this phone.
        for state in [SyncState.pending, .syncing, .synced, .needsAttention] {
            XCTAssertEqual(DispatchManualStatus.effectiveStatus(
                serverStatus: "Assigned",
                operations: [statusOp("On My Way", task: "MDT-1", state: state)],
                manualTaskUniqueId: "MDT-1"), "On My Way", "state \(state) must upgrade")
        }
    }

    func testEffectiveStatusIdentityIsStrict() {
        let ops = [statusOp("On My Way", task: "MDT-OTHER")]
        // Another task's transition never leaks in; a missing/empty id never matches.
        XCTAssertEqual(DispatchManualStatus.effectiveStatus(serverStatus: "Assigned", operations: ops,
                                                            manualTaskUniqueId: "MDT-1"), "Assigned")
        XCTAssertEqual(DispatchManualStatus.effectiveStatus(serverStatus: "Assigned", operations: ops,
                                                            manualTaskUniqueId: ""), "Assigned")
        XCTAssertEqual(DispatchManualStatus.effectiveStatus(serverStatus: "Assigned", operations: ops,
                                                            manualTaskUniqueId: nil), "Assigned")
    }

    func testEffectiveStatusNeverDowngradedByAStaleLocalOp() {
        // The server already advanced past the local record (op synced long
        // ago, feed is fresher) — the furthest transition wins.
        XCTAssertEqual(DispatchManualStatus.effectiveStatus(
            serverStatus: "Arrived",
            operations: [statusOp("On My Way", task: "MDT-1", state: .synced)],
            manualTaskUniqueId: "MDT-1"), "Arrived")
    }

    func testLocalCancelIsEffectivelyTerminal() {
        let effective = DispatchManualStatus.effectiveStatus(
            serverStatus: "Assigned",
            operations: [statusOp("Cancelled", task: "MDT-1")],
            manualTaskUniqueId: "MDT-1")
        XCTAssertEqual(effective, "Cancelled")
        XCTAssertTrue(DispatchManualStatus.isTerminal(effective))
    }

    func testDestinationActionFollowsEffectiveStatus() {
        // Pre-trip with an address: ONE tap records On My Way and navigates.
        XCTAssertEqual(DispatchManualStatus.destinationAction(effectiveStatus: "Assigned", hasAddress: true), .onMyWayNavigate)
        // No address: nothing to navigate to.
        XCTAssertEqual(DispatchManualStatus.destinationAction(effectiveStatus: "Assigned", hasAddress: false), .none)
        // Already On My Way (server-confirmed): reopen Maps only.
        XCTAssertEqual(DispatchManualStatus.destinationAction(effectiveStatus: "On My Way", hasAddress: true), .navigate)
        XCTAssertEqual(DispatchManualStatus.destinationAction(effectiveStatus: "Arrived", hasAddress: true), .navigate)
    }

    func testPendingSyncOnMyWayDisplaysNavigateAndNeverEnqueuesAgain() {
        // The tap-time guard: with a durable Pending Sync On My Way already on
        // disk, the derived action is .navigate — the enqueue path is
        // unreachable, so a second tap (or a return from Maps) can never
        // duplicate the status transition.
        let effective = DispatchManualStatus.effectiveStatus(
            serverStatus: "Assigned",
            operations: [statusOp("On My Way", task: "MDT-1", state: .pending)],
            manualTaskUniqueId: "MDT-1")
        XCTAssertEqual(effective, "On My Way")
        XCTAssertEqual(DispatchManualStatus.destinationAction(effectiveStatus: effective, hasAddress: true), .navigate)
    }

    func testBottomAdvanceOwnership() {
        // The Destination button owns the On My Way step when an address exists…
        XCTAssertNil(DispatchManualStatus.bottomAdvance(effectiveStatus: "Assigned", hasAddress: true))
        // …but an address-less task keeps its plain advance button.
        XCTAssertEqual(DispatchManualStatus.bottomAdvance(effectiveStatus: "Assigned", hasAddress: false), "On My Way")
        // Later lifecycle steps are untouched: Arrived is never skipped.
        XCTAssertEqual(DispatchManualStatus.bottomAdvance(effectiveStatus: "On My Way", hasAddress: true), "Arrived")
        XCTAssertEqual(DispatchManualStatus.bottomAdvance(effectiveStatus: "Arrived", hasAddress: true), "Completed")
        XCTAssertNil(DispatchManualStatus.bottomAdvance(effectiveStatus: "Completed", hasAddress: true))
        XCTAssertNil(DispatchManualStatus.bottomAdvance(effectiveStatus: "Cancelled", hasAddress: true))
    }
}
