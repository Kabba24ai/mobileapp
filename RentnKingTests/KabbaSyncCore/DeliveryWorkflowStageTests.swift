import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Driver Delivery Process Flow (2026-09-27), spec §3.3 and §5: ONE pure
/// derivation of the delivery workflow stage from the durable stores the phone
/// already has, and routing that reads it. Physical truth first (delivered >
/// arrived > on my way), then the yard gate, then the driver's own progress.
/// A stage at or beyond On My Way is NEVER routed back to the yard gate.
final class DeliveryWorkflowStageTests: XCTestCase {

    private let go = AssemblyPolicy.LocalGate(ready: true, requiredCount: 1, confirmedCount: 1, blockers: [])
    private let stop = AssemblyPolicy.LocalGate(ready: false, requiredCount: 1, confirmedCount: 0,
                                                blockers: ["Unit 1 has not been confirmed Available."])

    private func resolve(legCompleted: Bool = false, trip: DriverTripStage = .notStarted,
                         gate: AssemblyPolicy.LocalGate? = nil, evidence: Bool = false) -> DeliveryWorkflowStage {
        DeliveryWorkflowStage.resolve(DeliveryWorkflowInputs(legCompleted: legCompleted, trip: trip,
                                                             assemblyGate: gate, hasDriverChecklistEvidence: evidence))
    }

    private var gates: [(String, AssemblyPolicy.LocalGate?)] { [("nil", nil), ("STOP", stop), ("GO", go)] }

    // MARK: - §3.3 the matrix (2 × 3 × 3 × 2 = 36 combinations, every one pinned)

    func testACompletedLegIsDeliveredWhateverElseSays() {
        for trip in [DriverTripStage.notStarted, .onMyWay, .arrived] {
            for (name, gate) in gates {
                for evidence in [false, true] {
                    XCTAssertEqual(resolve(legCompleted: true, trip: trip, gate: gate, evidence: evidence), .delivered,
                                   "trip=\(trip) gate=\(name) evidence=\(evidence)")
                }
            }
        }
    }

    func testArrivedIsArrivedEvenWhenTheAssemblyGateIsStopOrMissing() {
        for (name, gate) in gates {
            for evidence in [false, true] {
                XCTAssertEqual(resolve(trip: .arrived, gate: gate, evidence: evidence), .arrived,
                               "a STOP or missing gate must never rewind an arrived driver (gate=\(name) evidence=\(evidence))")
            }
        }
    }

    func testOnMyWayIsOnMyWayEvenWhenTheAssemblyGateIsStopOrMissing() {
        for (name, gate) in gates {
            for evidence in [false, true] {
                XCTAssertEqual(resolve(trip: .onMyWay, gate: gate, evidence: evidence), .onMyWay,
                               "a STOP or missing gate must never rewind a departed driver (gate=\(name) evidence=\(evidence))")
            }
        }
    }

    func testBeforeDepartureTheYardGateComesFirstThenTheDriversOwnProgress() {
        // No review on this phone (§6.4) — honestly STOP, never a bypass.
        XCTAssertEqual(resolve(gate: nil, evidence: false), .assemblyReview)
        XCTAssertEqual(resolve(gate: nil, evidence: true), .assemblyReview)
        // STOP: the driver must confirm the assembly whatever Screen 2 holds.
        XCTAssertEqual(resolve(gate: stop, evidence: false), .assemblyReview)
        XCTAssertEqual(resolve(gate: stop, evidence: true), .assemblyReview)
        // GO: the first start goes through the review; later starts resume at Screen 2.
        XCTAssertEqual(resolve(gate: go, evidence: false), .assemblyReview)
        XCTAssertEqual(resolve(gate: go, evidence: true), .driverChecklist)
    }

    func testStagesAreOrderedByPhysicalProgress() {
        XCTAssertLessThan(DeliveryWorkflowStage.assemblyReview, .driverChecklist)
        XCTAssertLessThan(DeliveryWorkflowStage.driverChecklist, .onMyWay)
        XCTAssertLessThan(DeliveryWorkflowStage.onMyWay, .arrived)
        XCTAssertLessThan(DeliveryWorkflowStage.arrived, .delivered)
    }

    // MARK: - §5 routing (total over the enum)

    func testEveryStageHasExactlyOneDeliveryDestination() {
        XCTAssertEqual(DeliveryWorkflowRouting.destination(for: .assemblyReview, isDeliveryLeg: true), .assemblyReview)
        XCTAssertEqual(DeliveryWorkflowRouting.destination(for: .driverChecklist, isDeliveryLeg: true), .driverChecklist)
        XCTAssertEqual(DeliveryWorkflowRouting.destination(for: .onMyWay, isDeliveryLeg: true), .driverChecklist)
        XCTAssertEqual(DeliveryWorkflowRouting.destination(for: .arrived, isDeliveryLeg: true), .mainOrder, "D4: Arrived resumes at Main Order")
        XCTAssertEqual(DeliveryWorkflowRouting.destination(for: .delivered, isDeliveryLeg: true), .none)
    }

    func testReturnNeverOpensTheYardGate() {
        XCTAssertEqual(DeliveryWorkflowRouting.destination(for: .assemblyReview, isDeliveryLeg: false), .driverChecklist,
                       "Return has no Assembly Review — the gate stage maps to Screen 2")
        XCTAssertEqual(DeliveryWorkflowRouting.destination(for: .driverChecklist, isDeliveryLeg: false), .driverChecklist)
        XCTAssertEqual(DeliveryWorkflowRouting.destination(for: .onMyWay, isDeliveryLeg: false), .driverChecklist)
        XCTAssertEqual(DeliveryWorkflowRouting.destination(for: .arrived, isDeliveryLeg: false), .mainOrder)
        XCTAssertEqual(DeliveryWorkflowRouting.destination(for: .delivered, isDeliveryLeg: false), .none)
    }

    func testNoStageAtOrBeyondOnMyWayIsEverRoutedToTheReview() {
        for stage in [DeliveryWorkflowStage.onMyWay, .arrived, .delivered] {
            for isDelivery in [true, false] {
                XCTAssertNotEqual(DeliveryWorkflowRouting.destination(for: stage, isDeliveryLeg: isDelivery), .assemblyReview,
                                  "stage=\(stage) delivery=\(isDelivery)")
            }
        }
    }

    // MARK: - §3.3.1 driver checklist evidence

    private func driverOp(product: String = "P1", leg: String = "delivery", state: SyncState = .pending,
                          status: String? = nil) -> SyncOperation {
        var payload: [String: JSONValue] = ["order_product_unique_id": .string(product), "checklist_type": .string(leg)]
        if let status { payload["equipment_driver_status"] = .string(status) }
        var op = SyncOperation(type: EffectiveFieldState.driverChecklistType, capturedAt: Date(),
                               identity: SyncBusinessIdentity(orderProductUniqueId: product), payload: .object(payload))
        op.state = state
        return op
    }

    private func exists(local: DriverChecklistLocalState? = nil, server: DriverChecklistServerCopy? = nil,
                        ops: [SyncOperation] = [], product: String = "P1", leg: String = "delivery") -> Bool {
        DriverChecklistEvidence.exists(localRecord: local, serverChecklist: server, operations: ops,
                                       orderProductUniqueId: product, leg: leg)
    }

    func testNothingDurableMeansNoEvidence() {
        XCTAssertFalse(exists())
        XCTAssertFalse(exists(server: DriverChecklistServerCopy()))
        XCTAssertFalse(exists(server: DriverChecklistServerCopy(callCustomer: nil, fuel: nil, keys: nil, checks: nil, equipmentUniqueId: nil)))
    }

    func testALocalRecordWithOnlyDefaultsIsEvidence() {
        // Screen 2 writes its record on first appearance through the driver road (§4 step 5):
        // the next Start Delivery resumes there even though nothing was answered.
        XCTAssertTrue(exists(local: DriverChecklistLocalState()))
    }

    func testARetainedDriverChecklistOperationIsEvidenceInEveryRetainedState() {
        for state in [SyncState.pending, .syncing, .synced, .needsAttention] {
            XCTAssertTrue(exists(ops: [driverOp(state: state)]), "state=\(state)")
        }
        XCTAssertTrue(exists(ops: [driverOp(status: "On My Way")]), "a transition is evidence too")
    }

    func testOperationsForAnotherProductOrLegAreNotEvidence() {
        XCTAssertFalse(exists(ops: [driverOp(product: "P2")]))
        XCTAssertFalse(exists(ops: [driverOp(leg: "pickup")]))
        XCTAssertTrue(exists(ops: [driverOp(leg: "pickup")], leg: "pickup"))
    }

    func testAnyServerMiniChecklistFieldIsEvidence() {
        XCTAssertTrue(exists(server: DriverChecklistServerCopy(callCustomer: "confirmed")))
        XCTAssertTrue(exists(server: DriverChecklistServerCopy(fuel: "Not Full")), "present, not merely non-default")
        XCTAssertTrue(exists(server: DriverChecklistServerCopy(keys: "Missing")))
        XCTAssertTrue(exists(server: DriverChecklistServerCopy(checks: [0, 0, 0, 0])))
        XCTAssertTrue(exists(server: DriverChecklistServerCopy(equipmentUniqueId: "EQP-A")))
        // Call Customer wizard (2026-09-29): a verified step is evidence; the feed's
        // false-for-missing on an untouched row is NOT (it would route every fresh
        // Start Delivery past the review).
        XCTAssertTrue(exists(server: DriverChecklistServerCopy(addressVerified: true)))
        XCTAssertTrue(exists(server: DriverChecklistServerCopy(unloadingSituation: "other", unloadingNote: "")))
        XCTAssertFalse(exists(server: DriverChecklistServerCopy(addressVerified: false, equipmentVerified: false)))
    }
}
