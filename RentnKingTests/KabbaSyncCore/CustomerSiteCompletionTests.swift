import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Customer-site bounce (2026-11-13): after the driver films first and then submits
/// the checklist, the app must never send them back to Video, and vice versa — each
/// activity once, recognised immediately.
///
/// Two defects produced the bounce:
///   1. The upload screen navigated before the video export + durable enqueue finished
///      (fixed in ImageUploadViewController: route only from the save's completion).
///   2. A video recorded first from Main Order on a phone that never loaded this line's
///      checklist (another employee prepared the unit) carries NO cycle id. Once the
///      checklist loaded its cycle, the strict "same cycle" rule rejected it, and Laravel
///      files cycle-less media outside every cycle, so `delivery_video_present` never
///      reported it either.
/// These tests pin the evidence rule (2) and the full routing sequence on top of it.
final class CustomerSiteCompletionTests: XCTestCase {

    private let product = "OP-1"
    private let cycle = "CX-ACTIVE"
    private let unit = "EQ-7"

    private func video(product: String? = nil, execution: String? = nil, unit: String? = nil,
                       state: SyncState = .pending, queuedAt: Date = Date(), type: String = EffectiveFieldState.deliveryMediaType,
                       mime: String = "video/quicktime", order: String = "O1") -> SyncOperation {
        var op = SyncOperation(type: type, capturedAt: queuedAt, queuedAt: queuedAt,
                               identity: SyncBusinessIdentity(orderUniqueId: order, orderProductUniqueId: product ?? self.product,
                                                              equipmentUniqueId: unit, checklistExecutionId: execution),
                               payload: .object([:]),
                               assets: [SyncAsset(clientMediaId: UUID().uuidString, relativePath: "m", mimeType: mime, fieldName: "media")])
        op.state = state
        return op
    }

    private func photo(execution: String? = nil, state: SyncState = .pending) -> SyncOperation {
        video(execution: execution, state: state, mime: "image/jpeg")
    }

    private func discard(_ type: String, execution: String? = nil, at: Date) -> SyncOperation {
        SyncOperation(type: type, capturedAt: at, queuedAt: at,
                      identity: SyncBusinessIdentity(orderUniqueId: "O1", orderProductUniqueId: product, checklistExecutionId: execution),
                      payload: .object([:]))
    }

    /// The checklist Submit's question: is the video requirement met for the active cycle?
    private func met(_ ops: [SyncOperation], server: Bool = false, activeCycle: String? = "CX-ACTIVE",
                     activeUnit: String? = "EQ-7") -> Bool {
        MediaRequirementPolicy.deliveryVideoSatisfied(serverHasVideoForCycle: server, operations: ops,
                                                      orderProductUniqueId: product, activeExecutionId: activeCycle,
                                                      activeEquipmentUniqueId: activeUnit, orderHasVideo: false)
    }

    // MARK: - The cycle-less video (defect 2)

    func testAVideoFilmedBeforeThisPhoneKnewTheCycleSatisfiesTheActiveCycle() {
        for state in [SyncState.pending, .syncing, .synced, .needsAttention] {
            XCTAssertTrue(met([video(execution: nil, unit: unit, state: state)]),
                          "\(state): the driver filmed THIS unit for THIS line — never ask again")
        }
        XCTAssertTrue(met([video(execution: nil, unit: nil)]), "an older build's record carries no unit — it still stands")
        XCTAssertTrue(met([video(execution: nil, unit: unit)], activeUnit: nil), "active unit unknown — nothing contradicts it")
    }

    func testACycleLessVideoOfAnotherMachineNeverSatisfies() {
        XCTAssertFalse(met([video(execution: nil, unit: "EQ-OLD")]),
                       "filmed before a substitution made on another phone: the replacement needs its own video")
    }

    func testACycleLessVideoCapturedBeforeThisPhoneDiscardedThePreparationNeverSatisfies() {
        let t0 = Date(timeIntervalSinceNow: -600)
        let filmed = video(execution: nil, unit: unit, queuedAt: t0)
        for type in [EffectiveFieldState.deliveryRestartType, PreparationOperationBuilder.substitutionType] {
            XCTAssertFalse(met([filmed, discard(type, execution: "CX-OLD", at: t0.addingTimeInterval(60))]), type)
        }
        // …while one filmed AFTER the discard stands.
        let after = video(execution: nil, unit: unit, queuedAt: Date())
        XCTAssertTrue(met([filmed, discard(EffectiveFieldState.deliveryRestartType, execution: "CX-OLD", at: t0.addingTimeInterval(60)), after]))
    }

    func testTheStrictRulesStillHold() {
        XCTAssertFalse(met([video(execution: "CX-OLD", unit: unit)]), "a video that NAMES another cycle never counts")
        XCTAssertFalse(met([photo(execution: nil), photo(execution: cycle)]), "a photograph never substitutes for the video")
        XCTAssertFalse(met([video(product: "OP-2", execution: nil, unit: unit)]), "another equipment line's video never counts")
        XCTAssertFalse(met([video(execution: nil, unit: unit, type: EffectiveFieldState.returnMediaType)]), "a Return video never counts")
        var retired = video(execution: nil, unit: unit)
        retired.state = .superseded
        XCTAssertFalse(met([retired]), "retired history is not evidence")
        XCTAssertTrue(met([video(execution: cycle, unit: unit)]), "the active cycle's own video")
        XCTAssertTrue(met([], server: true), "server truth for the cycle")
    }

    func testMainOrdersTileAndCompleteGateAgreeWithTheChecklist() {
        // The same cycle-less video, seen through LegCompletionEvaluator (Main Order's tiles and
        // the Complete gate) once the checklist cached its context.
        let inputs = LegCompletionInputs(orderUniqueId: "O1", orderProductUniqueId: product, orderProductUniqueIds: [product],
                                         activeDeliveryExecutionId: cycle, activeDeliveryEquipmentUniqueId: unit)
        let ok = LegCompletionEvaluator.evaluate(leg: .delivery, inputs: inputs, operations: [video(execution: nil, unit: unit)])
        XCTAssertEqual(ok.status(.deliveryMedia), .satisfied)
        let other = LegCompletionEvaluator.evaluate(leg: .delivery, inputs: inputs, operations: [video(execution: nil, unit: "EQ-OLD")])
        XCTAssertEqual(other.status(.deliveryMedia), .incomplete)
    }

    // MARK: - The sequences (routing on top of the evidence)

    func testScenarioA_VideoFirstThenChecklistReturnsToMainOrder() {
        // 1. Video saved durably from Main Order on a phone with no cached context → no cycle id.
        let ops = [video(execution: nil, unit: unit, state: .pending)]
        // 2. The checklist is incomplete → Checklist.
        XCTAssertEqual(CustomerSiteRouter.afterStep(.video, stage: .arrived, isDeliveryLeg: true,
                                                    videoRequirementMet: true, checklistComplete: false), .checklist)
        // 3. The checklist loads its cycle; Submit asks for the video — offline, still pending.
        XCTAssertEqual(CustomerSiteRouter.afterStep(.checklistCompleted, stage: .arrived, isDeliveryLeg: true,
                                                    videoRequirementMet: met(ops), checklistComplete: true), .mainOrder,
                       "the saved video is recognised: straight back to Main Order, never Video")
    }

    func testScenarioB_ChecklistFirstThenVideoReturnsToMainOrder() {
        XCTAssertEqual(CustomerSiteRouter.afterStep(.checklistCompleted, stage: .arrived, isDeliveryLeg: true,
                                                    videoRequirementMet: met([]), checklistComplete: true), .video)
        // The upload opened from the checklist carries the cycle.
        let ops = [video(execution: cycle, unit: unit)]
        XCTAssertTrue(met(ops))
        XCTAssertEqual(CustomerSiteRouter.afterStep(.video, stage: .arrived, isDeliveryLeg: true,
                                                    videoRequirementMet: met(ops), checklistComplete: true), .mainOrder)
    }

    func testScenarioC_BothDoneGoesToMainOrderFromEitherStep() {
        let ops = [video(execution: nil, unit: unit, state: .synced)]
        XCTAssertEqual(CustomerSiteRouter.afterStep(.video, stage: .arrived, isDeliveryLeg: true,
                                                    videoRequirementMet: true, checklistComplete: true), .mainOrder)
        XCTAssertEqual(CustomerSiteRouter.afterStep(.checklistCompleted, stage: .arrived, isDeliveryLeg: true,
                                                    videoRequirementMet: met(ops), checklistComplete: true), .mainOrder)
    }

    func testBeforeDepartureTheYardReviewRuleIsUntouched() {
        for stage in [DeliveryWorkflowStage.assemblyReview, .driverChecklist] {
            XCTAssertEqual(CustomerSiteRouter.afterStep(.video, stage: stage, isDeliveryLeg: true,
                                                        videoRequirementMet: true, checklistComplete: false), .assemblyReview)
            XCTAssertEqual(CustomerSiteRouter.afterStep(.checklistCompleted, stage: stage, isDeliveryLeg: true,
                                                        videoRequirementMet: false, checklistComplete: true), .assemblyReview)
        }
    }

    // MARK: - The video screen never implies saved media is missing

    private func notice(_ ops: [SyncOperation], kind: MediaKind = .delivery, copyVideo: Bool = false, copyMedia: Bool = false) -> CapturedMediaNotice? {
        CapturedMediaNotice.notice(operations: ops, orderUniqueId: "O1", orderProductUniqueId: product, kind: kind,
                                   serverCopyHasVideo: copyVideo, serverCopyHasMedia: copyMedia)
    }

    func testTheNoticeSaysWhereTheCapturedVideoStands() {
        XCTAssertNil(notice([]), "nothing captured, nothing to say")
        XCTAssertEqual(notice([video(state: .pending)])?.text, "Video saved on this phone · uploads automatically")
        XCTAssertEqual(notice([video(state: .syncing)])?.stage, .savedOnPhone)
        XCTAssertEqual(notice([video(state: .needsAttention)])?.text, "Video saved on this phone · office review needed")
        XCTAssertEqual(notice([video(state: .synced)])?.text, "Video received by Kabba",
                       "acknowledged and removed from the phone — the screen's copy predates it")
        XCTAssertNil(notice([video(state: .synced)], copyVideo: true, copyMedia: true), "the copy already shows it")
    }

    func testTheNoticePrefersTheVideoAndHealthyWork() {
        XCTAssertEqual(notice([photo(state: .pending), video(state: .synced)]), CapturedMediaNotice(stage: .receivedByKabba, isVideo: true))
        XCTAssertEqual(notice([video(state: .needsAttention), video(state: .pending)])?.stage, .savedOnPhone)
        XCTAssertNil(notice([photo(state: .pending), video(state: .synced)], copyVideo: true, copyMedia: true),
                     "the video is on screen; a photo beside it adds nothing to say")
        XCTAssertEqual(notice([photo(state: .pending)]), CapturedMediaNotice(stage: .savedOnPhone, isVideo: false))
    }

    func testTheNoticeStaysOnItsOwnLineAndLeg() {
        XCTAssertNil(notice([video(product: "OP-2")]), "another line")
        XCTAssertNil(notice([video(order: "O2")]), "another order")
        XCTAssertNil(notice([video()], kind: .pickup), "the Delivery video on the Return screen")
        XCTAssertEqual(notice([video(type: EffectiveFieldState.returnMediaType)], kind: .pickup)?.stage, .savedOnPhone)
        var retired = video()
        retired.state = .superseded
        XCTAssertNil(notice([retired]))
    }
}
