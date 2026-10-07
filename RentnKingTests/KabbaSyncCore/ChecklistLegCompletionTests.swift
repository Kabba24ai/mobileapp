import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// The order-wide checklist entry (Order Details, Orders list) opens the completed report
/// only when EVERY eligible line is complete for the current leg and cycle; otherwise the
/// unfinished equipment must stay reachable. Completion is per product: Laravel's leg flag,
/// or a durable local completion operation for that product, leg and cycle.
final class ChecklistLegCompletionTests: XCTestCase {

    private typealias C = ChecklistLegCompletion

    private func line(_ id: String, delivered: Bool = false, returned: Bool = false, checklist: Bool = true,
                      deliveryExecution: String = "", returnExecution: String = "") -> C.Line {
        C.Line(orderProductUniqueId: id, requiresChecklist: checklist, deliveredOnServer: delivered, returnedOnServer: returned,
               activeDeliveryExecutionId: deliveryExecution, activeReturnExecutionId: returnExecution)
    }

    private func op(_ type: String, product: String, execution: String? = nil, state: SyncState = .pending,
                    queued: Date = Date()) -> SyncOperation {
        var op = SyncOperation(type: type, capturedAt: queued, queuedAt: queued,
                               identity: SyncBusinessIdentity(orderUniqueId: "O1", orderProductUniqueId: product,
                                                              checklistExecutionId: execution),
                               payload: .object([:]))
        op.state = state
        return op
    }

    private let deliveryDone = EffectiveFieldState.deliveryCompleteType
    private let returnDone = EffectiveFieldState.returnCompleteType

    // MARK: One line done never stands for the order

    func testEveryPermutationOfPartlyDeliveredLinesKeepsTheRestReachable() {
        let ids = ["A", "B", "C"]
        for mask in 0..<8 {   // which of A/B/C Laravel reports delivered
            let lines = ids.enumerated().map { line($1, delivered: mask & (1 << $0) != 0) }
            let done = ids.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            XCTAssertEqual(C.unfinished(lines, leg: .delivery, operations: []), ids.filter { !done.contains($0) }, "mask \(mask)")
            XCTAssertEqual(C.everyEligibleLineComplete(lines, leg: .delivery, operations: []), mask == 7,
                           "the report only when A, B and C are all delivered (mask \(mask))")
        }
    }

    func testOnlyTheThirdLineCompletedLeavesTheFirstTwoOwed() {
        let lines = [line("A"), line("B"), line("C", delivered: true)]
        XCTAssertEqual(C.unfinished(lines, leg: .delivery, operations: []), ["A", "B"])
        XCTAssertFalse(C.everyEligibleLineComplete(lines, leg: .delivery, operations: []))
    }

    func testReturnPermutationsOverDeliveredEquipment() {
        let lines = [line("A", delivered: true, returned: true), line("B", delivered: true), line("C", delivered: true, returned: true)]
        XCTAssertEqual(C.unfinished(lines, leg: .return, operations: []), ["B"])
        XCTAssertFalse(C.everyEligibleLineComplete(lines, leg: .return, operations: []))
        let all = lines.map { line($0.orderProductUniqueId, delivered: true, returned: true) }
        XCTAssertTrue(C.everyEligibleLineComplete(all, leg: .return, operations: []))
    }

    // MARK: Eligibility

    func testEquipmentWithoutAChecklistIsNotOwedAndNotCounted() {
        let lines = [line("A", delivered: true), line("RETAIL", checklist: false)]
        XCTAssertEqual(C.unfinished(lines, leg: .delivery, operations: []), [])
        XCTAssertTrue(C.everyEligibleLineComplete(lines, leg: .delivery, operations: []), "Retail never holds the report back")
        XCTAssertFalse(C.everyEligibleLineComplete([line("RETAIL", checklist: false)], leg: .delivery, operations: []),
                       "nothing eligible is not 'complete' — the entry keeps its checklist flow")
    }

    func testAReturnIsOwedOnlyForDeliveredEquipment() {
        let lines = [line("A", delivered: true, returned: true), line("B")]
        XCTAssertEqual(C.unfinished(lines, leg: .return, operations: []), [], "B was never delivered: nothing to return")
        XCTAssertTrue(C.everyEligibleLineComplete(lines, leg: .return, operations: []))
        XCTAssertTrue(C.anyEligibleLine(lines, leg: .return, operations: []))
        XCTAssertFalse(C.anyEligibleLine([line("A"), line("B")], leg: .return, operations: []), "Return stays closed until something is out")
    }

    // MARK: Durable local completion (offline)

    func testALineCompletedOnlyOfflineCountsButItsSiblingsStayOwed() {
        let lines = [line("A"), line("B"), line("C")]
        for state in [SyncState.pending, .syncing, .synced, .needsAttention] {
            let ops = [op(deliveryDone, product: "A", execution: "EXEC-A1", state: state)]
            XCTAssertEqual(C.unfinished(lines, leg: .delivery, operations: ops), ["B", "C"], "\(state)")
            XCTAssertFalse(C.everyEligibleLineComplete(lines, leg: .delivery, operations: ops))
        }
        let all = ["A", "B", "C"].map { op(deliveryDone, product: $0) }
        XCTAssertTrue(C.everyEligibleLineComplete(lines, leg: .delivery, operations: all))
        XCTAssertFalse(C.everyEligibleLineComplete(lines, leg: .delivery,
                                                   operations: [op(deliveryDone, product: "A", state: .superseded)] + all.dropFirst()),
                       "a superseded operation is not evidence")
    }

    func testAnotherLegNeverSatisfiesThisOne() {
        let delivered = [line("A", delivered: true), line("B", delivered: true)]
        XCTAssertEqual(C.unfinished(delivered, leg: .return, operations: []), ["A", "B"], "delivered is not returned")
        let ops = [op(deliveryDone, product: "A"), op(deliveryDone, product: "B")]
        XCTAssertEqual(C.unfinished([line("A"), line("B")], leg: .return, operations: ops), ["A", "B"],
                       "a delivery completion makes the return OWED, never done")
        XCTAssertFalse(C.isComplete(line("A", returned: true), leg: .delivery, operations: []), "returned flag says nothing about delivery")
    }

    func testAPriorCycleCompletionNeverSatisfiesTheCurrentCycle() {
        // The phone completed cycle 1 (EXEC-1); Laravel reopened the leg and minted EXEC-2.
        let reopened = line("A", deliveryExecution: "EXEC-2")
        let ops = [op(deliveryDone, product: "A", execution: "EXEC-1", state: .synced)]
        XCTAssertFalse(C.isComplete(reopened, leg: .delivery, operations: ops))
        XCTAssertTrue(C.isComplete(line("A", deliveryExecution: "EXEC-1"), leg: .delivery, operations: ops), "its own cycle")
        // Unknown current cycle: a cycle this phone discarded (substitution / restart) never counts.
        let discard = op(EffectiveFieldState.deliveryRestartType, product: "A", execution: "EXEC-1")
        XCTAssertFalse(C.isComplete(line("A"), leg: .delivery, operations: ops + [discard]))
        let earlier = op(deliveryDone, product: "A", queued: Date(timeIntervalSinceNow: -60))
        let laterDiscard = op(EffectiveFieldState.equipmentSubstitutionType, product: "A", queued: Date())
        XCTAssertFalse(C.isComplete(line("A"), leg: .delivery, operations: [earlier, laterDiscard]),
                       "a completion captured before a later discard of that product is not the current cycle's")
    }

    /// A completion this phone already synced, then a leg Laravel REOPENED: an order copy
    /// received after the acknowledgment still reports the leg open — the new cycle is owed.
    /// A copy received before the acknowledgment (or of unknown age) keeps the bridge.
    func testASyncedCompletionYieldsToAnOrderCopyReceivedAfterIt() {
        var synced = op(deliveryDone, product: "A", execution: "EXEC-1", state: .synced)
        let acknowledged = Date(timeIntervalSinceNow: -120)
        synced.acknowledgment = SyncAcknowledgment(acknowledgedAt: acknowledged, statusCode: 200, requestId: nil,
                                                   replayed: false, serverReceivedAt: nil, data: nil)
        var fresh = line("A", deliveryExecution: "EXEC-1")
        fresh.serverStateAsOf = Date()                                   // received after the ack
        XCTAssertFalse(C.isComplete(fresh, leg: .delivery, operations: [synced]), "reopened since: owed again")
        var stale = line("A", deliveryExecution: "EXEC-1")
        stale.serverStateAsOf = Date(timeIntervalSinceNow: -600)         // fetched before the ack
        XCTAssertTrue(C.isComplete(stale, leg: .delivery, operations: [synced]), "the copy predates it: the bridge stands")
        XCTAssertTrue(C.isComplete(line("A", deliveryExecution: "EXEC-1"), leg: .delivery, operations: [synced]), "age unknown")
        var pending = op(deliveryDone, product: "A", execution: "EXEC-1")
        pending.acknowledgment = nil
        XCTAssertTrue(C.isComplete(fresh, leg: .delivery, operations: [pending]), "not yet on the server: it counts")
    }

    /// Assembly Review's lane: a line this phone delivered (synced) that Laravel — in an answer asked
    /// after acknowledging it — reports undelivered was reopened: owed again. Pending ops, unknown
    /// age and lines Laravel reports delivered keep the local completion.
    func testTheReviewOwesALineReopenedAfterThisPhoneSyncedIt() {
        var synced = op(deliveryDone, product: "A", execution: "EXEC-1", state: .synced)
        synced.acknowledgment = SyncAcknowledgment(acknowledgedAt: Date(timeIntervalSinceNow: -60), statusCode: 200, requestId: nil,
                                                   replayed: false, serverReceivedAt: nil, data: nil)
        let ops = [synced, op(deliveryDone, product: "B")]
        let overlay = QueueLineLocalOverlay.from(ops)
        XCTAssertEqual(overlay.completedLocally, ["A", "B"])
        let reviewed = overlay.owingLinesReopenedOnServer(["A": false, "B": false], asOf: Date(), operations: ops)
        XCTAssertEqual(reviewed.completedLocally, ["B"], "A reopened since; B's completion has not reached Laravel yet")
        XCTAssertEqual(overlay.owingLinesReopenedOnServer(["A": false], asOf: nil, operations: ops), overlay, "age unknown")
        XCTAssertEqual(overlay.owingLinesReopenedOnServer(["A": true, "B": true], asOf: Date(), operations: ops), overlay)
        XCTAssertEqual(overlay.owingLinesReopenedOnServer(["A": false], asOf: Date(timeIntervalSinceNow: -600), operations: ops), overlay,
                       "an answer asked before the acknowledgment predates the completion")
    }

    func testAnOperationForAnotherProductNeverCounts() {
        let ops = [op(deliveryDone, product: "B")]
        XCTAssertFalse(C.isComplete(line("A"), leg: .delivery, operations: ops))
        XCTAssertFalse(C.isComplete(line(""), leg: .delivery, operations: [op(deliveryDone, product: "")]))
    }
}
