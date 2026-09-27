import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Driver Delivery Process Flow (2026-09-27), spec §10.3 / D7 — ONE delivery
/// media requirement: Delivery requires a VIDEO for THIS product in the CURRENT
/// cycle. Photos never satisfy it on their own; another product's, the Return
/// leg's or a superseded cycle's video never does; order-scoped legacy evidence
/// counts only when no cycle is known for the product.
final class MediaRequirementPolicyTests: XCTestCase {

    private func op(_ type: String, product: String = "P1", execution: String? = "CX-1",
                    state: SyncState = .pending, mime: String) -> SyncOperation {
        var op = SyncOperation(type: type, capturedAt: Date(),
                               identity: SyncBusinessIdentity(orderUniqueId: "O1", orderProductUniqueId: product, checklistExecutionId: execution),
                               payload: .object([:]),
                               assets: [SyncAsset(clientMediaId: UUID().uuidString, relativePath: "m", mimeType: mime, fieldName: "media[]")])
        op.state = state
        return op
    }

    private func video(product: String = "P1", execution: String? = "CX-1", state: SyncState = .pending) -> SyncOperation {
        op(EffectiveFieldState.deliveryMediaType, product: product, execution: execution, state: state, mime: "video/quicktime")
    }

    private func photo(product: String = "P1", execution: String? = "CX-1") -> SyncOperation {
        op(EffectiveFieldState.deliveryMediaType, product: product, execution: execution, mime: "image/jpeg")
    }

    private func satisfied(_ ops: [SyncOperation], server: Bool = false, active: String? = "CX-1", legacy: Bool = false) -> Bool {
        MediaRequirementPolicy.deliveryVideoSatisfied(serverHasVideoForCycle: server, operations: ops,
                                                      orderProductUniqueId: "P1", activeExecutionId: active, legacyOrderEvidence: legacy)
    }

    func testPhotosNeverSatisfyTheDeliveryRequirement() {
        XCTAssertFalse(satisfied([photo()]))
        XCTAssertFalse(satisfied([photo(), photo()]))
    }

    func testAVideoForThisProductInTheActiveCycleSatisfies() {
        XCTAssertTrue(satisfied([video()]))
        for state in [SyncState.pending, .syncing, .synced, .needsAttention] {
            XCTAssertTrue(satisfied([video(state: state)]), "every retained state counts — the driver never re-films durable work")
        }
        XCTAssertTrue(satisfied([photo(), video()]), "a photo beside the video changes nothing")
    }

    func testAnotherProductTheReturnLegOrASupersededCycleNeverSatisfies() {
        XCTAssertFalse(satisfied([video(product: "P2")]), "sibling product")
        XCTAssertFalse(satisfied([op(EffectiveFieldState.returnMediaType, mime: "video/quicktime")]), "Return leg")
        XCTAssertFalse(satisfied([video(execution: "CX-0")]), "a video shot for the cycle a substitution replaced")
    }

    func testServerCycleTruthSatisfiesAlone() {
        XCTAssertTrue(satisfied([], server: true))
    }

    func testLegacyOrderEvidenceCountsOnlyWhenNoCycleIsKnown() {
        XCTAssertTrue(satisfied([], active: nil, legacy: true), "no cycle known: the order-scoped evidence stands")
        XCTAssertFalse(satisfied([], active: "CX-1", legacy: true), "a known cycle demands its own video")
        XCTAssertTrue(satisfied([video(execution: nil)], active: nil), "a cycle-less video stands when no cycle is known")
    }

    func testTheEvidenceListFeedsTheNeedsAttentionTreatment() {
        let parked = video(state: .needsAttention)
        let evidence = MediaRequirementPolicy.deliveryVideoEvidence(operations: [photo(), parked, video(product: "P2")],
                                                                    orderProductUniqueId: "P1", activeExecutionId: "CX-1")
        XCTAssertEqual(evidence.map(\.id), [parked.id], "only THIS product's video in the active cycle — the photo and the sibling are not evidence")
    }
}
