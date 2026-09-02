import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Local-first workflow (2026-09): durably saved local state drives immediate
/// workflow progression; Laravel reconciles afterward. These tests pin the ONE
/// rule everything consumes: effective = server state ∨ durable local evidence.
final class EffectiveFieldStateTests: XCTestCase {

    private func op(_ type: String, order: String? = nil, product: String? = nil,
                    state: SyncState = .pending) -> SyncOperation {
        var op = SyncOperation(type: type, capturedAt: Date(),
                               identity: SyncBusinessIdentity(orderUniqueId: order, orderProductUniqueId: product),
                               payload: .object([:]))
        op.state = state
        return op
    }

    // MARK: - Every retained state is durable evidence

    func testAllRetainedStatesCountAsDurableEvidence() {
        // pending/syncing: saved on this phone. synced: confirmed (retained).
        // needsAttention: the DRIVER's work stands — reconciliation is an
        // office problem, never an instruction to repeat the physical job.
        for state in [SyncState.pending, .syncing, .synced, .needsAttention] {
            XCTAssertTrue(EffectiveFieldState.countsAsDurableEvidence(state), "\(state) must count")
            XCTAssertTrue(EffectiveFieldState.hasDurableEvidence(
                in: [op(EffectiveFieldState.deliveryMediaType, order: "O1", state: state)],
                types: [EffectiveFieldState.deliveryMediaType], orderUniqueId: "O1"))
        }
    }

    // MARK: - Requirement satisfaction (exception screen / chips)

    func testVideoSavedLocallyImmediatelySatisfiesMediaRequirement() {
        let ops = [op(EffectiveFieldState.deliveryMediaType, order: "O1")]
        // Server has NOT seen the video yet (Pending Sync window) — no exception.
        XCTAssertTrue(EffectiveFieldState.mediaSatisfied(serverHasMedia: false, operations: ops,
                                                         orderUniqueId: "O1", isDeliveryLeg: true))
        // Return media op does not satisfy the delivery requirement (leg isolation).
        XCTAssertFalse(EffectiveFieldState.mediaSatisfied(serverHasMedia: false, operations: ops,
                                                          orderUniqueId: "O1", isDeliveryLeg: false))
        // Another order's media never leaks in.
        XCTAssertFalse(EffectiveFieldState.mediaSatisfied(serverHasMedia: false, operations: ops,
                                                          orderUniqueId: "O2", isDeliveryLeg: true))
    }

    func testLicenseSavedLocallyImmediatelySatisfiesLicenseRequirement() {
        let ops = [op(EffectiveFieldState.licenseMediaType, order: "O1")]
        XCTAssertTrue(EffectiveFieldState.licenseSatisfied(serverHasLicense: false, operations: ops, orderUniqueId: "O1"))
        XCTAssertFalse(EffectiveFieldState.licenseSatisfied(serverHasLicense: false, operations: [], orderUniqueId: "O1"))
        // Server truth alone still satisfies (no local op needed).
        XCTAssertTrue(EffectiveFieldState.licenseSatisfied(serverHasLicense: true, operations: [], orderUniqueId: "O1"))
    }

    func testGenuinelyUnsatisfiedRequirementStillAsksForException() {
        // Neither server-complete nor locally durable → the exception IS asked.
        XCTAssertFalse(EffectiveFieldState.mediaSatisfied(serverHasMedia: false, operations: [],
                                                          orderUniqueId: "O1", isDeliveryLeg: true))
    }

    func testServerConfirmationCausesNoSecondTransition() {
        // pending → synced: satisfied before AND after — same answer, no UI jump.
        let before = [op(EffectiveFieldState.deliveryMediaType, order: "O1", state: .pending)]
        let after = [op(EffectiveFieldState.deliveryMediaType, order: "O1", state: .synced)]
        XCTAssertEqual(
            EffectiveFieldState.mediaSatisfied(serverHasMedia: false, operations: before, orderUniqueId: "O1", isDeliveryLeg: true),
            EffectiveFieldState.mediaSatisfied(serverHasMedia: true, operations: after, orderUniqueId: "O1", isDeliveryLeg: true)
        )
    }

    // MARK: - Leg completion (checklist routing + completion gating)

    func testLocallyCompletedChecklistImmediatelySatisfiesLeg() {
        let ops = [op(EffectiveFieldState.deliveryCompleteType, product: "P1")]
        XCTAssertTrue(EffectiveFieldState.legSatisfied(serverCompleted: false, operations: ops,
                                                       orderProductUniqueId: "P1", isDeliveryLeg: true))
        // Delivery completion does NOT satisfy the return leg.
        XCTAssertFalse(EffectiveFieldState.legSatisfied(serverCompleted: false, operations: ops,
                                                        orderProductUniqueId: "P1", isDeliveryLeg: false))
        // Multi-line isolation: sibling product unaffected.
        XCTAssertFalse(EffectiveFieldState.legSatisfied(serverCompleted: false, operations: ops,
                                                        orderProductUniqueId: "P2", isDeliveryLeg: true))
    }

    // MARK: - Dispatch working-queue overlay

    func testDispatchDisappearsAfterDurableLocalCompletion() {
        let overlay = EffectiveFieldState.CompletionOverlay.from([
            op(EffectiveFieldState.deliveryCompleteType, product: "P1"),
            op(EffectiveFieldState.returnCompleteType, product: "P2"),
        ])
        XCTAssertTrue(overlay.isLegLocallyCompleted(orderProductUniqueId: "P1", isDeliveryLeg: true))
        XCTAssertTrue(overlay.isLegLocallyCompleted(orderProductUniqueId: "P2", isDeliveryLeg: false))
        // The SAME product's other leg stays active (delivery done ≠ return done).
        XCTAssertFalse(overlay.isLegLocallyCompleted(orderProductUniqueId: "P1", isDeliveryLeg: false))
        XCTAssertFalse(overlay.isLegLocallyCompleted(orderProductUniqueId: "P2", isDeliveryLeg: true))
    }

    func testDispatchNeverReinsertedAfterTerminalRejection() {
        // Sync failed permanently → op parked as needsAttention. The dispatch
        // STAYS removed: the driver is never told to repeat the physical job.
        let overlay = EffectiveFieldState.CompletionOverlay.from([
            op(EffectiveFieldState.deliveryCompleteType, product: "P1", state: .needsAttention),
        ])
        XCTAssertTrue(overlay.isLegLocallyCompleted(orderProductUniqueId: "P1", isDeliveryLeg: true))
    }

    func testOverlayEmptyWhenNoCompletionOps() {
        // Media/driver-checklist ops do NOT remove dispatch rows.
        let overlay = EffectiveFieldState.CompletionOverlay.from([
            op(EffectiveFieldState.deliveryMediaType, order: "O1"),
            op("driver_checklist.update", product: "P1"),
        ])
        XCTAssertTrue(overlay.isEmpty)
        XCTAssertFalse(overlay.isLegLocallyCompleted(orderProductUniqueId: "P1", isDeliveryLeg: true))
    }
}
