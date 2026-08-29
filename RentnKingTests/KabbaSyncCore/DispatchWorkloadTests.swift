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
}
