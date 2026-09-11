import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Return completion (2026-09): ONE leg-aware effective evaluator decides
/// which requirements apply to the leg being completed and whether each is
/// effectively satisfied (server-confirmed ∨ durable local evidence). These
/// tests pin the two defects it corrects:
///
///   1. work durably on the phone counted as "missing" while the server feed
///      was stale (false Return override);
///   2. historical Delivery-leg requirements (license, T&C, delivery media,
///      delivery checklist) blocking Return completion.
final class LegCompletionEvaluatorTests: XCTestCase {

    private let order = "O1"
    private let product = "P1"
    private let sibling = "P2"

    // MARK: Builders

    private func op(_ type: String,
                    order: String? = "O1",
                    product: String? = "P1",
                    execution: String? = nil,
                    state: SyncState = .pending,
                    queuedAt: Date = Date(),
                    payload: JSONValue = .object([:]),
                    assets: [SyncAsset] = []) -> SyncOperation {
        var op = SyncOperation(type: type,
                               capturedAt: queuedAt,
                               queuedAt: queuedAt,
                               identity: SyncBusinessIdentity(orderUniqueId: order,
                                                              orderProductUniqueId: product,
                                                              checklistExecutionId: execution),
                               payload: payload,
                               assets: assets)
        op.state = state
        return op
    }

    private func returnVideo(product: String = "P1", execution: String? = nil, state: SyncState = .pending, queuedAt: Date = Date()) -> SyncOperation {
        op(EffectiveFieldState.returnMediaType, product: product, execution: execution, state: state, queuedAt: queuedAt,
           assets: [SyncAsset(clientMediaId: "m-\(product)", relativePath: "\(product)/return.mov", mimeType: "video/quicktime", fieldName: "media")])
    }

    private func returnPhoto(product: String = "P1") -> SyncOperation {
        op(EffectiveFieldState.returnMediaType, product: product,
           assets: [SyncAsset(clientMediaId: "p-\(product)", relativePath: "\(product)/return.jpg", mimeType: "image/jpeg", fieldName: "media")])
    }

    private func returnComplete(product: String = "P1", execution: String? = "RX-1", state: SyncState = .pending, queuedAt: Date = Date()) -> SyncOperation {
        op(EffectiveFieldState.returnCompleteType, product: product, execution: execution, state: state, queuedAt: queuedAt)
    }

    private func returnRestart(product: String = "P1", execution: String, queuedAt: Date = Date()) -> SyncOperation {
        op(EffectiveFieldState.returnRestartType, product: product, execution: execution, queuedAt: queuedAt)
    }

    private func inputs(product: String = "P1",
                        products: [String] = ["P1", "P2"],
                        license: Bool = false, terms: Bool = false,
                        deliveryMedia: Bool = false, deliveryChecklist: Bool = false,
                        returnMedia: Bool = false, returnChecklist: Bool = false,
                        activeReturnExecutionId: String = "") -> LegCompletionInputs {
        LegCompletionInputs(orderUniqueId: order,
                            orderProductUniqueId: product,
                            orderProductUniqueIds: products,
                            licenseConfirmed: license,
                            termsConfirmed: terms,
                            deliveryMediaConfirmed: deliveryMedia,
                            deliveryChecklistConfirmed: deliveryChecklist,
                            returnMediaConfirmed: returnMedia,
                            returnChecklistConfirmed: returnChecklist,
                            activeReturnExecutionId: activeReturnExecutionId)
    }

    private func evaluateReturn(_ inputs: LegCompletionInputs, _ ops: [SyncOperation]) -> LegCompletionDecision {
        LegCompletionEvaluator.evaluate(leg: .return, inputs: inputs, operations: ops)
    }

    private func evaluateDelivery(_ inputs: LegCompletionInputs, _ ops: [SyncOperation]) -> LegCompletionDecision {
        LegCompletionEvaluator.evaluate(leg: .delivery, inputs: inputs, operations: ops)
    }

    // MARK: - Requirement matrix

    func testLegRequirementMatrixIsExplicit() {
        XCTAssertEqual(ChecklistLeg.delivery.completionRequirements,
                       [.termsAndConditions, .driverLicense, .deliveryMedia, .deliveryChecklist])
        XCTAssertEqual(ChecklistLeg.return.completionRequirements, [.returnMedia, .returnChecklist])
        // A decision never carries a status for a requirement that does not apply to its leg.
        let decision = evaluateReturn(inputs(), [])
        XCTAssertEqual(Set(decision.statuses.keys), [.returnMedia, .returnChecklist])
        XCTAssertNil(decision.status(.driverLicense))
        XCTAssertNil(decision.status(.termsAndConditions))
        XCTAssertNil(decision.status(.deliveryMedia))
        XCTAssertNil(decision.status(.deliveryChecklist))
    }

    // MARK: - 1–6 Effective-state combinations (no override)

    func test1_serverChecklistAndServerMedia_noOverride() {
        let decision = evaluateReturn(inputs(returnMedia: true, returnChecklist: true), [])
        XCTAssertTrue(decision.canProceed)
        XCTAssertEqual(decision.missing, [])
        XCTAssertFalse(decision.shouldPresentOverride)
    }

    func test2_localPendingChecklistAndLocalPendingMedia_noOverride() {
        let decision = evaluateReturn(inputs(), [returnComplete(state: .pending), returnVideo(state: .pending)])
        XCTAssertTrue(decision.canProceed)
        XCTAssertEqual(decision.missing, [])
        XCTAssertFalse(decision.shouldPresentOverride)
    }

    func test3_serverChecklistAndLocalPendingMedia_noOverride() {
        let decision = evaluateReturn(inputs(returnChecklist: true), [returnVideo(state: .pending)])
        XCTAssertTrue(decision.canProceed)
        XCTAssertEqual(decision.missing, [])
    }

    func test4_localPendingChecklistAndServerMedia_noOverride() {
        let decision = evaluateReturn(inputs(returnMedia: true), [returnComplete(state: .pending)])
        XCTAssertTrue(decision.canProceed)
        XCTAssertEqual(decision.missing, [])
    }

    func test5_checklistCountsImmediatelyAfterLocalCompletion_beforeServerRefresh() {
        // Server feed still says not returned; the durable completion op alone satisfies.
        let decision = evaluateReturn(inputs(returnChecklist: false), [returnComplete(state: .pending)])
        XCTAssertEqual(decision.status(.returnChecklist), .satisfied)
    }

    func test6_mediaCountsImmediatelyAfterLocalCaptureEnqueue_beforeServerRefresh() {
        let decision = evaluateReturn(inputs(returnMedia: false), [returnVideo(state: .pending)])
        XCTAssertEqual(decision.status(.returnMedia), .satisfied)
        // A return PHOTO is media too (the requirement is Photo/Video, as today).
        XCTAssertEqual(evaluateReturn(inputs(), [returnPhoto()]).status(.returnMedia), .satisfied)
    }

    // MARK: - 7–9 Missing requirements

    func test7_checklistTrulyMissing_checklistExceptionOnly() {
        let decision = evaluateReturn(inputs(returnMedia: true), [])
        XCTAssertFalse(decision.canProceed)
        XCTAssertEqual(decision.missing, [.returnChecklist])
        XCTAssertEqual(decision.overrideSections, OverrideSections(terms: false, license: false, video: false, checklist: true))
    }

    func test8_mediaTrulyMissing_mediaExceptionOnly() {
        let decision = evaluateReturn(inputs(returnChecklist: true), [])
        XCTAssertFalse(decision.canProceed)
        XCTAssertEqual(decision.missing, [.returnMedia])
        XCTAssertEqual(decision.overrideSections, OverrideSections(terms: false, license: false, video: true, checklist: false))
    }

    func test9_bothTrulyMissing_bothExceptions() {
        let decision = evaluateReturn(inputs(), [])
        XCTAssertFalse(decision.canProceed)
        XCTAssertEqual(decision.missing, [.returnMedia, .returnChecklist])
        XCTAssertEqual(decision.overrideSections, OverrideSections(terms: false, license: false, video: true, checklist: true))
    }

    // MARK: - 10–14 Leg isolation: Delivery history never blocks Return

    func test10_licenseMissing_returnStillProceeds() {
        let decision = evaluateReturn(inputs(license: false, terms: true, deliveryMedia: true, deliveryChecklist: true,
                                             returnMedia: true, returnChecklist: true), [])
        XCTAssertTrue(decision.canProceed)
        XCTAssertFalse(decision.overrideSections.license)
    }

    func test11_termsMissing_returnStillProceeds() {
        let decision = evaluateReturn(inputs(license: true, terms: false, deliveryMedia: true, deliveryChecklist: true,
                                             returnMedia: true, returnChecklist: true), [])
        XCTAssertTrue(decision.canProceed)
        XCTAssertFalse(decision.overrideSections.terms)
    }

    func test12_deliveryVideoMissing_returnStillProceeds() {
        let decision = evaluateReturn(inputs(license: true, terms: true, deliveryMedia: false, deliveryChecklist: true,
                                             returnMedia: true, returnChecklist: true), [])
        XCTAssertTrue(decision.canProceed)
        XCTAssertEqual(decision.missing, [])
    }

    func test13_deliveryChecklistMissing_returnStillProceeds() {
        let decision = evaluateReturn(inputs(license: true, terms: true, deliveryMedia: true, deliveryChecklist: false,
                                             returnMedia: true, returnChecklist: true), [])
        XCTAssertTrue(decision.canProceed)
        XCTAssertEqual(decision.missing, [])
    }

    func test14_allFourDeliveryRequirementsMissing_returnMayProceed() {
        // Nothing historical is even known; the Return work itself is durably on the phone.
        let decision = evaluateReturn(inputs(), [returnComplete(), returnVideo()])
        XCTAssertTrue(decision.canProceed)
        XCTAssertEqual(decision.overrideSections, OverrideSections(terms: false, license: false, video: false, checklist: false))
    }

    // MARK: - 15 Delivery regression (its rules are unchanged)

    func test15_deliveryCompletionStillAppliesItsOwnFourRules() {
        let allGood = inputs(license: true, terms: true, deliveryMedia: true, deliveryChecklist: true)
        XCTAssertTrue(evaluateDelivery(allGood, []).canProceed)

        var noLicense = allGood; noLicense.licenseConfirmed = false
        XCTAssertEqual(evaluateDelivery(noLicense, []).missing, [.driverLicense])
        XCTAssertEqual(evaluateDelivery(noLicense, []).overrideSections, OverrideSections(terms: false, license: true, video: false, checklist: false))

        var noTerms = allGood; noTerms.termsConfirmed = false
        XCTAssertEqual(evaluateDelivery(noTerms, []).missing, [.termsAndConditions])

        var noMedia = allGood; noMedia.deliveryMediaConfirmed = false
        XCTAssertEqual(evaluateDelivery(noMedia, []).missing, [.deliveryMedia])

        var noChecklist = allGood; noChecklist.deliveryChecklistConfirmed = false
        XCTAssertEqual(evaluateDelivery(noChecklist, []).missing, [.deliveryChecklist])

        // Durable local delivery evidence satisfies delivery, exactly as before.
        XCTAssertTrue(evaluateDelivery(inputs(), [
            op(EffectiveFieldState.licenseMediaType, product: nil),
            op(EffectiveFieldState.termsAcceptedType),
            op(EffectiveFieldState.deliveryMediaType),
            op(EffectiveFieldState.deliveryCompleteType),
        ]).canProceed)

        // Return work never satisfies a Delivery requirement.
        let returnOnly = evaluateDelivery(inputs(), [returnComplete(), returnVideo()])
        XCTAssertEqual(returnOnly.missing, [.termsAndConditions, .driverLicense, .deliveryMedia, .deliveryChecklist])
    }

    // MARK: - 16–21 Identity / safety

    func test16_deliveryMediaCannotSatisfyReturnMedia() {
        let deliveryVideo = op(EffectiveFieldState.deliveryMediaType,
                               assets: [SyncAsset(clientMediaId: "d", relativePath: "P1/d.mov", mimeType: "video/quicktime", fieldName: "media")])
        XCTAssertEqual(evaluateReturn(inputs(), [deliveryVideo]).status(.returnMedia), .incomplete)
    }

    func test17_deliveryChecklistCannotSatisfyReturnChecklist() {
        XCTAssertEqual(evaluateReturn(inputs(), [op(EffectiveFieldState.deliveryCompleteType, execution: "DX-1")]).status(.returnChecklist), .incomplete)
    }

    func test18_staleSupersededReturnCycleMediaCannotSatisfyCurrentReturn() {
        // The phone knows the current cycle is RX-2; a video shot for RX-1 does not count.
        let stale = returnVideo(execution: "RX-1")
        XCTAssertEqual(evaluateReturn(inputs(activeReturnExecutionId: "RX-2"), [stale]).status(.returnMedia), .incomplete)
        // Even when no active cycle is known, a cycle this phone durably discarded never counts.
        XCTAssertEqual(evaluateReturn(inputs(), [stale, returnRestart(execution: "RX-1")]).status(.returnMedia), .incomplete)
        // Cycle-less media (captured from Order Details) captured BEFORE a restart is discarded too…
        let before = Date(timeIntervalSinceNow: -600)
        let cycleless = returnVideo(execution: nil, queuedAt: before)
        XCTAssertEqual(evaluateReturn(inputs(), [cycleless, returnRestart(execution: "RX-1", queuedAt: Date(timeIntervalSinceNow: -300))]).status(.returnMedia), .incomplete)
        // …while cycle-less media captured AFTER the restart stands.
        let after = returnVideo(execution: nil, queuedAt: Date())
        XCTAssertEqual(evaluateReturn(inputs(activeReturnExecutionId: "RX-2"), [after, returnRestart(execution: "RX-1", queuedAt: before)]).status(.returnMedia), .satisfied)
    }

    func test19_staleSupersededReturnChecklistCannotSatisfyCurrentReturn() {
        let stale = returnComplete(execution: "RX-1")
        XCTAssertEqual(evaluateReturn(inputs(activeReturnExecutionId: "RX-2"), [stale]).status(.returnChecklist), .incomplete)
        XCTAssertEqual(evaluateReturn(inputs(), [stale, returnRestart(execution: "RX-1")]).status(.returnChecklist), .incomplete)
    }

    func test20_siblingProductEvidenceCannotSatisfyCurrentLine() {
        let siblingWork = [returnComplete(product: sibling), returnVideo(product: sibling)]
        let line1 = evaluateReturn(inputs(product: product), siblingWork)
        XCTAssertEqual(line1.missing, [.returnMedia, .returnChecklist], "line 2's return work must never satisfy line 1")
        // The sibling's own evidence satisfies the sibling.
        XCTAssertTrue(evaluateReturn(inputs(product: sibling), siblingWork).canProceed)
        // An empty identity never matches anything.
        XCTAssertEqual(evaluateReturn(inputs(product: "", products: []), siblingWork).missing, [.returnMedia, .returnChecklist])
    }

    func test21_sameCurrentReturnCycleEvidenceSatisfies() {
        let decision = evaluateReturn(inputs(activeReturnExecutionId: "RX-2"),
                                      [returnComplete(execution: "RX-2"), returnVideo(execution: "RX-2")])
        XCTAssertTrue(decision.canProceed)
        XCTAssertEqual(decision.status(.returnMedia), .satisfied)
        XCTAssertEqual(decision.status(.returnChecklist), .satisfied)
    }

    func testLegacyMigratedReturnSubmissionCountsForItsProductOnly() {
        // A pre-Phase-3 queue item migrated into the engine carries type=Return in its payload.
        let legacy = op(LegacyChecklistQueueMigration.operationType, payload: .object(["type": .string("Return")]))
        XCTAssertEqual(evaluateReturn(inputs(), [legacy]).status(.returnChecklist), .satisfied)
        let legacyDelivery = op(LegacyChecklistQueueMigration.operationType, payload: .object(["type": .string("Delivery")]))
        XCTAssertEqual(evaluateReturn(inputs(), [legacyDelivery]).status(.returnChecklist), .incomplete)
    }

    // MARK: - 22–25 Sync states

    func test22_queuedPendingOperationCountsAsEffectiveCompletion() {
        XCTAssertTrue(evaluateReturn(inputs(), [returnComplete(state: .pending), returnVideo(state: .pending)]).canProceed)
    }

    func test23_syncingOperationCounts() {
        XCTAssertTrue(evaluateReturn(inputs(), [returnComplete(state: .syncing), returnVideo(state: .syncing)]).canProceed)
    }

    func test24_syncedEvidenceCounts() {
        let decision = evaluateReturn(inputs(), [returnComplete(state: .synced), returnVideo(state: .synced)])
        XCTAssertTrue(decision.canProceed)
        XCTAssertEqual(decision.status(.returnMedia), .satisfied)
        XCTAssertEqual(decision.status(.returnChecklist), .satisfied)
    }

    func test25_needsAttentionRoutesToSyncAttention_notFalseMissingWork() {
        let parkedChecklist = returnComplete(state: .needsAttention)
        let decision = evaluateReturn(inputs(), [parkedChecklist, returnVideo(state: .pending)])
        // The driver DID the work: no override, no "Not Completed".
        XCTAssertTrue(decision.canProceed)
        XCTAssertEqual(decision.missing, [])
        XCTAssertFalse(decision.shouldPresentOverride)
        // …but the decision does not pretend the server accepted it.
        XCTAssertEqual(decision.status(.returnChecklist), .satisfiedNeedsAttention(operationId: parkedChecklist.id))
        XCTAssertEqual(decision.needsAttentionOperationIds, [parkedChecklist.id])
        XCTAssertTrue(decision.requiresSyncAttention)
        // A later healthy record for the same requirement outranks the parked one.
        let recovered = evaluateReturn(inputs(), [parkedChecklist, returnComplete(state: .pending), returnVideo()])
        XCTAssertEqual(recovered.status(.returnChecklist), .satisfied)
        XCTAssertFalse(recovered.requiresSyncAttention)
    }

    // MARK: - 26–27 UI decision

    func test26_bothEffectiveRequirementsSatisfied_warningIsNeverPresented() {
        for ops in [[returnComplete(), returnVideo()], [returnComplete(state: .synced), returnVideo(state: .synced)]] {
            XCTAssertFalse(evaluateReturn(inputs(), ops).shouldPresentOverride)
        }
        XCTAssertFalse(evaluateReturn(inputs(returnMedia: true, returnChecklist: true), []).shouldPresentOverride)
    }

    func test27_onlyOneMissing_onlyItsSectionAppears() {
        let mediaOnly = evaluateReturn(inputs(), [returnComplete()])
        XCTAssertTrue(mediaOnly.shouldPresentOverride)
        XCTAssertEqual(mediaOnly.overrideSections, OverrideSections(terms: false, license: false, video: true, checklist: false))

        let checklistOnly = evaluateReturn(inputs(), [returnVideo()])
        XCTAssertTrue(checklistOnly.shouldPresentOverride)
        XCTAssertEqual(checklistOnly.overrideSections, OverrideSections(terms: false, license: false, video: false, checklist: true))
    }

    // MARK: - Order-wide fallback (no focus product): the pre-existing any-line semantics

    func testNoFocusProductFallsBackToAnyReturnLegProductAsBefore() {
        let decision = evaluateReturn(inputs(product: "", products: ["P1", "P2"]),
                                      [returnComplete(product: "P2"), returnVideo(product: "P2")])
        XCTAssertTrue(decision.canProceed)
    }
}
