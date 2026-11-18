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
///
/// 2026-11-14: Kabba now anchors such a file to the item's live cycle itself (Laravel
/// CycleLessMediaAnchor) and says so in the upload acknowledgment
/// (`checklist_execution_resolved`). Once acknowledged, Kabba's anchor is the file's
/// cycle on this phone too, so every phone and `delivery_video_present` agree after
/// this phone's upload record is long gone.
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

    // MARK: - Kabba decides the cycle of a cycle-less file (2026-11-14)

    /// The upload acknowledged by Laravel. `resolved: nil` = an older Kabba that does not decide.
    private func acknowledged(_ op: SyncOperation, resolved: Bool?, anchor: String?) -> SyncOperation {
        var data: [String: JSONValue] = ["checklist_execution_id": anchor.map { .string($0) } ?? .null]
        if let resolved { data["checklist_execution_resolved"] = .bool(resolved) }
        var acked = op
        acked.state = .synced
        acked.acknowledgment = SyncAcknowledgment(acknowledgedAt: Date(), statusCode: 200, requestId: nil, replayed: false,
                                                  serverReceivedAt: nil, data: .object(data))
        return acked
    }

    private func capture(_ kind: MediaKind, unit: String?) -> MediaCapture {
        MediaCapture(kind: kind, orderUniqueId: "O1", orderProductUniqueId: kind == .license ? nil : product,
                     equipmentUniqueId: unit, side: kind == .license ? "front" : nil,
                     asset: SyncAsset(clientMediaId: "cm-1", relativePath: "m", mimeType: "video/quicktime", fieldName: "media"))
    }

    func testTheUploadNamesTheFilmedUnitSoKabbaCanRefuseAnotherMachine() {
        XCTAssertEqual(MediaOperationBuilder.payload(capture(.delivery, unit: unit))["equipment_unique_id"], .string(unit))
        XCTAssertEqual(MediaOperationBuilder.payload(capture(.pickup, unit: unit))["equipment_unique_id"], .string(unit))
        XCTAssertNil(MediaOperationBuilder.payload(capture(.delivery, unit: nil))["equipment_unique_id"], "unknown unit: say nothing")
        XCTAssertNil(MediaOperationBuilder.payload(capture(.delivery, unit: ""))["equipment_unique_id"])
        XCTAssertNil(MediaOperationBuilder.payload(capture(.license, unit: unit))["equipment_unique_id"], "a license shows no machine")
        XCTAssertNil(MediaOperationBuilder.payload(capture(.delivery, unit: unit))["checklist_execution_id"], "still cycle-less")
    }

    func testOnceKabbaDecidesTheCycleThePhoneFollowsIt() {
        let filmed = video(execution: nil, unit: unit)
        XCTAssertTrue(met([acknowledged(filmed, resolved: true, anchor: cycle)]), "Kabba put it in the active cycle")
        XCTAssertFalse(met([acknowledged(filmed, resolved: true, anchor: "CX-OLD")]),
                       "Kabba put it in an earlier cycle (filmed before a restart): this cycle still needs its own")
        XCTAssertFalse(met([acknowledged(filmed, resolved: true, anchor: nil)]),
                       "Kabba anchored it to no cycle (another unit, a delivered leg): the phone agrees")
        XCTAssertTrue(met([acknowledged(filmed, resolved: nil, anchor: nil)]),
                      "an older Kabba decides nothing: the phone's own estimate stands, as before")
        XCTAssertTrue(met([acknowledged(filmed, resolved: false, anchor: nil)]),
                      "Kabba failed to decide: the phone's own estimate stands")
        XCTAssertTrue(met([acknowledged(filmed, resolved: true, anchor: cycle)], activeCycle: nil),
                      "no cycle cached on this phone: Kabba's anchor still counts")
        XCTAssertFalse(met([acknowledged(video(execution: nil, unit: unit, mime: "image/jpeg"), resolved: true, anchor: cycle)]),
                       "an anchored photo is still not the video")
    }

    /// The reported case end to end: Employee A prepared the unit; Employee B, who never
    /// opened that checklist, films first, the upload syncs, and the video must keep counting
    /// after B's record is pruned, after a restart, on another phone and after a refresh.
    func testAVideoFilmedBeforeOpeningAColleaguesChecklistKeepsCountingEverywhere() throws {
        let filmed = video(execution: nil, unit: unit, state: .pending)
        XCTAssertTrue(met([filmed]), "B, offline: the saved video counts at once")

        let synced = acknowledged(filmed, resolved: true, anchor: cycle)
        XCTAssertTrue(met([synced], server: true), "B, online: Kabba anchored it and reports it for the cycle")

        // Restart: the record is reloaded from disk with Kabba's decision intact.
        let reloaded = try JSONDecoder().decode(SyncOperation.self, from: JSONEncoder().encode(synced))
        XCTAssertEqual(EffectiveFieldState.serverCycleAnchor(of: reloaded), .some(cycle))
        XCTAssertTrue(met([reloaded]), "after a restart, even before a fresh context arrives")

        // B's record pruned after the retention window, a refreshed context, or another phone
        // (Employee C) that never had the record: Kabba's flag is the evidence.
        XCTAssertTrue(met([], server: true), "no local record: delivery_video_present says yes")
        XCTAssertEqual(CustomerSiteRouter.afterStep(.checklistCompleted, stage: .arrived, isDeliveryLeg: true,
                                                    videoRequirementMet: met([], server: true), checklistComplete: true), .mainOrder,
                       "Submit lands on Main Order on any phone, never back on Video")
    }

    func testMainOrdersTileFollowsKabbasDecisionToo() {
        let inputs = LegCompletionInputs(orderUniqueId: "O1", orderProductUniqueId: product, orderProductUniqueIds: [product],
                                         activeDeliveryExecutionId: cycle, activeDeliveryEquipmentUniqueId: unit)
        let anchored = acknowledged(video(execution: nil, unit: unit), resolved: true, anchor: cycle)
        XCTAssertEqual(LegCompletionEvaluator.evaluate(leg: .delivery, inputs: inputs, operations: [anchored]).status(.deliveryMedia), .satisfied)
        let refused = acknowledged(video(execution: nil, unit: unit), resolved: true, anchor: nil)
        XCTAssertEqual(LegCompletionEvaluator.evaluate(leg: .delivery, inputs: inputs, operations: [refused]).status(.deliveryMedia), .incomplete)
    }
}
