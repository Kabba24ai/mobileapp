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

    func testTermsAcceptedLocallyImmediatelySatisfiesTermsRequirement() {
        // Signed T&C saved on the phone (Pending Sync window) — no exception.
        let ops = [op(EffectiveFieldState.termsAcceptedType, order: "O1", product: "P1")]
        XCTAssertTrue(EffectiveFieldState.termsSatisfied(serverAccepted: false, operations: ops, orderUniqueId: "O1"))
        // Terms are ORDER-level: another order's acceptance never leaks in.
        XCTAssertFalse(EffectiveFieldState.termsSatisfied(serverAccepted: false, operations: ops, orderUniqueId: "O2"))
        // Server truth alone (Accepted or Exempt) still satisfies.
        XCTAssertTrue(EffectiveFieldState.termsSatisfied(serverAccepted: true, operations: [], orderUniqueId: "O1"))
        // Genuinely skipped (no op, server not accepted) → the exception IS asked.
        XCTAssertFalse(EffectiveFieldState.termsSatisfied(serverAccepted: false, operations: [], orderUniqueId: "O1"))
    }

    func testTermsEvidenceSurvivesEveryRetainedState() {
        // pending/syncing/synced/needsAttention — the signing already happened
        // server-side; the phone's judgment must never regress on sync trouble.
        for state in [SyncState.pending, .syncing, .synced, .needsAttention] {
            let ops = [op(EffectiveFieldState.termsAcceptedType, order: "O1", state: state)]
            XCTAssertTrue(EffectiveFieldState.termsSatisfied(serverAccepted: false, operations: ops, orderUniqueId: "O1"),
                          "\(state) must satisfy")
        }
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

    // MARK: - Delivery VIDEO evidence (post-Save smart routing, 2026-09)

    private func mediaOp(_ type: String, product: String, state: SyncState, mimeType: String) -> SyncOperation {
        var op = SyncOperation(type: type, capturedAt: Date(),
                               identity: SyncBusinessIdentity(orderUniqueId: "O1", orderProductUniqueId: product),
                               payload: .object([:]),
                               assets: [SyncAsset(clientMediaId: "m-\(product)", relativePath: "\(product)/clip.mp4", mimeType: mimeType, fieldName: "media")])
        op.state = state
        return op
    }

    func testDeliveryVideoSatisfiedByServerTruthAlone() {
        XCTAssertTrue(EffectiveFieldState.deliveryVideoSatisfied(serverHasVideo: true, operations: [], orderProductUniqueId: "P1"))
        XCTAssertFalse(EffectiveFieldState.deliveryVideoSatisfied(serverHasVideo: false, operations: [], orderProductUniqueId: "P1"))
    }

    func testDeliveryVideoSatisfiedByEveryRetainedLocalState() {
        // Pending Sync, currently syncing, server-confirmed, and retained
        // Needs Attention all count — the operator never re-captures durable work.
        for state in [SyncState.pending, .syncing, .synced, .needsAttention] {
            XCTAssertTrue(EffectiveFieldState.deliveryVideoSatisfied(
                serverHasVideo: false,
                operations: [mediaOp(EffectiveFieldState.deliveryMediaType, product: "P1", state: state, mimeType: "video/mp4")],
                orderProductUniqueId: "P1"), "state \(state) must satisfy")
        }
    }

    func testDeliveryVideoIdentityIsStrict() {
        let ops = [
            // Sibling product's video — never satisfies P1.
            mediaOp(EffectiveFieldState.deliveryMediaType, product: "P2", state: .pending, mimeType: "video/mp4"),
            // Return-leg video for the right product — wrong leg.
            mediaOp(EffectiveFieldState.returnMediaType, product: "P1", state: .pending, mimeType: "video/mp4"),
            // Delivery PHOTO for the right product — not a video.
            mediaOp(EffectiveFieldState.deliveryMediaType, product: "P1", state: .pending, mimeType: "image/jpeg"),
        ]
        XCTAssertFalse(EffectiveFieldState.deliveryVideoSatisfied(serverHasVideo: false, operations: ops, orderProductUniqueId: "P1"))
        XCTAssertTrue(EffectiveFieldState.deliveryVideoSatisfied(serverHasVideo: false, operations: ops, orderProductUniqueId: "P2"),
                      "the sibling's own video satisfies the sibling")
        XCTAssertFalse(EffectiveFieldState.deliveryVideoSatisfied(serverHasVideo: false, operations: ops, orderProductUniqueId: ""),
                       "an empty identity never matches")
    }
}

// MARK: - Driver trip stage (review F2): Load Map & Go / On My Way / Arrived
//
// durable local action → immediate effective state → later server confirmation.
// The stage Screen 2 and the Dispatch card show is derived from the SAME durable
// driver_checklist.update operations the Sync Engine already keeps — never from a
// view controller or a row instance that a reopen or relaunch throws away.

final class DriverTripStageTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let noServerStage = DriverStageServerState(readyToGoAt: nil, arrivedAt: nil, isArrived: false)

    private func stageOp(_ status: String, product: String = "P1", leg: String = "delivery",
                         state: SyncState = .pending, captured: Date? = nil, ackedAt: Date? = nil) -> SyncOperation {
        var op = SyncOperation(type: EffectiveFieldState.driverChecklistType, capturedAt: captured ?? t0,
                               identity: SyncBusinessIdentity(orderProductUniqueId: product),
                               payload: .object(["order_product_unique_id": .string(product),
                                                 "checklist_type": .string(leg),
                                                 "equipment_driver_status": .string(status)]))
        op.state = state
        if let ackedAt {
            op.acknowledgment = SyncAcknowledgment(acknowledgedAt: ackedAt, statusCode: 200, requestId: nil,
                                                   replayed: false, serverReceivedAt: nil, data: nil)
        }
        return op
    }

    private func stage(_ ops: [SyncOperation], product: String = "P1", leg: String = "delivery",
                       server: DriverStageServerState? = nil, observedAt: Date? = nil) -> DriverStageEffective {
        DriverStageOverlay.from(ops).effective(orderProductUniqueId: product, leg: leg,
                                               server: server ?? noServerStage, serverObservedAt: observedAt)
    }

    // Driver Delivery Process Flow (2026-09-27) §3.3.2: the server's Arrived is trusted
    // only when it is WHOLE — is_arrived AND arrived_at. A row written before every recall
    // cleared both (RC10) can carry a stale is_arrived with no stamp; that is not an arrival.
    func testServerArrivedIsTrustedOnlyWhenWhole() {
        XCTAssertTrue(DriverStageServerState(isArrivedFlag: true, arrivedAt: "2026-09-27 16:51:00", readyToGoAt: "2026-09-27 15:10:00").isArrived)
        XCTAssertFalse(DriverStageServerState(isArrivedFlag: true, arrivedAt: nil, readyToGoAt: "2026-09-27 15:10:00").isArrived,
                       "a stale is_arrived with no arrived_at is not an arrival")
        XCTAssertFalse(DriverStageServerState(isArrivedFlag: true, arrivedAt: "", readyToGoAt: nil).isArrived)
        XCTAssertFalse(DriverStageServerState(isArrivedFlag: false, arrivedAt: "2026-09-27 16:51:00", readyToGoAt: nil).isArrived,
                       "the flag is still required — arrived_at alone is not enough either")

        let stale = DriverStageServerState(isArrivedFlag: true, arrivedAt: nil, readyToGoAt: "2026-09-27 15:10:00")
        XCTAssertEqual(stage([], server: stale).stage, .onMyWay, "the departure stamp still counts")
        XCTAssertEqual(stage([], server: DriverStageServerState(isArrivedFlag: true, arrivedAt: nil, readyToGoAt: nil)).stage, .notStarted)
        XCTAssertEqual(stage([], server: DriverStageServerState(isArrivedFlag: true, arrivedAt: "2026-09-27 16:51:00", readyToGoAt: nil)).stage, .arrived)
    }

    func testLoadMapAndGoSavedOnThisPhoneIsOnMyWayImmediately() {
        let ops = [stageOp("On My Way", captured: t0)]
        let effective = stage(ops)

        XCTAssertEqual(effective.stage, .onMyWay)
        XCTAssertEqual(effective.readyToGoAt, DriverStageOverlay.stamp(t0))
        XCTAssertNil(effective.arrivedAt)
        XCTAssertFalse(effective.recordsDeparture, "Load Map & Go is never recorded twice")
        XCTAssertTrue(effective.recordsArrival)
        // Scoped to order product + leg, like every other driver-checklist state.
        XCTAssertEqual(stage(ops, leg: "pickup").stage, .notStarted)
        XCTAssertEqual(stage(ops, product: "P2").stage, .notStarted)
    }

    func testArrivedSavedOnThisPhoneIsArrived() {
        let arrived = t0.addingTimeInterval(600)
        let effective = stage([stageOp("On My Way", captured: t0), stageOp("Arrived", captured: arrived)])

        XCTAssertEqual(effective.stage, .arrived)
        XCTAssertEqual(effective.readyToGoAt, DriverStageOverlay.stamp(t0))
        XCTAssertEqual(effective.arrivedAt, DriverStageOverlay.stamp(arrived))
        XCTAssertFalse(effective.recordsDeparture)
        XCTAssertFalse(effective.recordsArrival, "Arrived is never recorded twice — the button only continues")
    }

    func testAPartialSaveIsNotAStageButALegacyReadyToGoIs() {
        XCTAssertEqual(stage([stageOp("")]).stage, .notStarted, "answers without a transition")
        XCTAssertTrue(stage([stageOp("")]).recordsDeparture)
        // The server stamps ready_to_go_at for Ready to Go too — Screen 2 treats both alike.
        XCTAssertEqual(stage([stageOp("Ready to Go")]).stage, .onMyWay)
    }

    func testEveryRetainedStateCountsUntilTheServerIsSeenAfterConfirmation() {
        let acked = t0.addingTimeInterval(100)
        for state in [SyncState.pending, .syncing, .needsAttention] {
            XCTAssertEqual(stage([stageOp("On My Way", state: state)], observedAt: acked.addingTimeInterval(3600)).stage, .onMyWay,
                           "\(state): the server has not confirmed it, so no server row can supersede it")
        }
        let synced = stageOp("On My Way", state: .synced, ackedAt: acked)
        XCTAssertEqual(stage([synced]).stage, .onMyWay, "server truth for the row never observed")
        XCTAssertEqual(stage([synced], observedAt: acked.addingTimeInterval(-1)).stage, .onMyWay,
                       "the shown row was asked for before the server confirmed")
        XCTAssertEqual(stage([synced], observedAt: acked.addingTimeInterval(1)).stage, .notStarted,
                       "server truth asked for AFTER it confirmed wins — e.g. the office recalled the trip")
        let serverDeparted = DriverStageServerState(readyToGoAt: "2026-09-22 08:00:00", arrivedAt: nil, isArrived: false)
        XCTAssertEqual(stage([synced], server: serverDeparted, observedAt: acked.addingTimeInterval(1)).stage, .onMyWay)
    }

    func testServerTruthIsKeptAndNeverDowngraded() {
        let serverArrived = DriverStageServerState(readyToGoAt: "2026-09-22 08:00:00", arrivedAt: "2026-09-22 09:00:00", isArrived: true)
        let arrivedOnServer = stage([stageOp("On My Way")], server: serverArrived)
        XCTAssertEqual(arrivedOnServer.stage, .arrived)
        XCTAssertEqual(arrivedOnServer.readyToGoAt, "2026-09-22 08:00:00")
        XCTAssertEqual(arrivedOnServer.arrivedAt, "2026-09-22 09:00:00")

        let serverDeparted = DriverStageServerState(readyToGoAt: "2026-09-22 08:00:00", arrivedAt: nil, isArrived: false)
        let arrivedHere = stage([stageOp("Arrived", captured: t0)], server: serverDeparted)
        XCTAssertEqual(arrivedHere.stage, .arrived)
        XCTAssertEqual(arrivedHere.readyToGoAt, "2026-09-22 08:00:00")
        XCTAssertEqual(arrivedHere.arrivedAt, DriverStageOverlay.stamp(t0))

        XCTAssertEqual(stage([], server: serverDeparted).stage, .onMyWay)
        XCTAssertEqual(stage([]).stage, .notStarted)
    }
}

/// The same rule end to end over a REAL durable queue: reopen, force-quit/relaunch
/// offline, and replayed taps — the stage holds and nothing is enqueued twice.
final class DriverTripStageDurabilityTests: XCTestCase {

    private struct DriverChecklistTestHandler: SyncOperationHandler {
        var operationType: String { EffectiveFieldState.driverChecklistType }
        func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
            SyncHTTPRequest(method: "POST", path: "orders/schedules/driver-checklist",
                            headers: ["X-Operation-Id": operation.id], jsonBody: operation.payload, operationId: operation.id)
        }
    }

    private var dir: URL!
    private let product = "ORD-SCH-1"
    /// The cached row was downloaded before any of this happened (and never since — offline).
    private let rowObservedAt = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// A new app process with no network: a new engine over the same durable queue.
    private func launchOffline() throws -> SyncEngine {
        makeEngine(store: try FileSyncOperationStore(rootDirectory: dir), client: FakeSyncHTTPClient(),
                   handler: DriverChecklistTestHandler())
    }

    /// What Screen 2 derives when it opens for the cached row (no stage on the server copy).
    private func screen2(_ engine: SyncEngine) -> DriverStageEffective {
        DriverStageOverlay.from(engine.snapshot()).effective(
            orderProductUniqueId: product, leg: "delivery",
            server: DriverStageServerState(readyToGoAt: nil, arrivedAt: nil, isArrived: false),
            serverObservedAt: rowObservedAt)
    }

    /// Screen 2's two buttons, gated exactly as the screen gates them.
    private func tapLoadMapAndGo(_ engine: SyncEngine) throws {
        guard screen2(engine).recordsDeparture else { return }
        try record("On My Way", on: engine)
    }

    private func tapArrived(_ engine: SyncEngine) throws {
        guard screen2(engine).recordsArrival else { return } // "Continue": navigates only
        try record("Arrived", on: engine)
    }

    private func record(_ status: String, on engine: SyncEngine) throws {
        _ = try engine.enqueue(type: EffectiveFieldState.driverChecklistType,
                               payload: .object(["order_product_unique_id": .string(product),
                                                 "checklist_type": .string("delivery"),
                                                 "equipment_driver_status": .string(status)]),
                               identity: SyncBusinessIdentity(orderProductUniqueId: product),
                               capturedAt: Date())
    }

    func testTheStageSurvivesReopenAndRelaunchOfflineWithoutDuplicates() throws {
        var app = try launchOffline()
        XCTAssertEqual(screen2(app).stage, .notStarted)

        try tapLoadMapAndGo(app)                                  // offline Load Map & Go
        XCTAssertEqual(screen2(app).stage, .onMyWay, "leave Dispatch and reopen: still On My Way")
        try tapLoadMapAndGo(app)                                  // navigation back into Screen 2

        app = try launchOffline()                                 // force-quit, relaunch offline
        XCTAssertEqual(screen2(app).stage, .onMyWay, "after relaunch: still On My Way")
        try tapLoadMapAndGo(app)

        try tapArrived(app)                                       // Arrived offline
        XCTAssertEqual(screen2(app).stage, .arrived, "reopen: still Arrived")

        app = try launchOffline()
        XCTAssertEqual(screen2(app).stage, .arrived, "after relaunch: still Arrived")
        try tapArrived(app)
        try tapLoadMapAndGo(app)

        let statuses = app.snapshot().compactMap { $0.payload["equipment_driver_status"]?.stringValue }
        XCTAssertEqual(statuses.sorted(), ["Arrived", "On My Way"], "exactly one On My Way and one Arrived were ever queued")
    }
}
