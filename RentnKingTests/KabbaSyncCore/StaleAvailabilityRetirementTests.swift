//
//  StaleAvailabilityRetirementTests.swift
//  RentnKingTests — P10 (2026-09-29, order #6024): an Available recorded for
//  unit A while the office reassigned the line to unit B comes back from the
//  server as 409 QUEUE_ASSIGNMENT_CHANGED (retryable false, current_equipment
//  = B). Once this phone holds B as the canonical unit that operation is
//  demonstrably obsolete: it is RETIRED (state `superseded`) — kept as history,
//  never replayed, never Needs Attention, never a "Sync Issue", never a
//  confirmation of B. Every other rejection stays parked exactly as before.
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class StaleAvailabilityRetirementTests: XCTestCase {

    private var dir: URL!
    private var client: FakeSyncHTTPClient!
    private let product = "ORD-SCH-HRQ6-WQVH"
    private let order = "ORD-OA8D-GQCR"
    private let unitA = "EQP-Z2TB-EBAL"          // P6 Skid Steer U27
    private let unitB = "EQP-XUC3-POKU"          // P6 Skid Steer U31
    private let unitBName = "P6 Skid Steer U31"

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
        client = FakeSyncHTTPClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: - Builders

    private struct AvailabilityHandler: SyncOperationHandler {
        let operationType = AssemblyOperationBuilder.availabilityType
        func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
            try AssemblyRequestFactory.availabilityRequest(for: operation)
        }
    }

    private func engine() -> SyncEngine {
        SyncEngine(store: try! FileSyncOperationStore(rootDirectory: dir), httpClient: client,
                   handlers: [AvailabilityHandler()], policy: SyncRetryPolicy(backoffSchedule: [0.05]))
    }

    /// The server's answer of 21:57:30 on 2026-09-29, verbatim in shape.
    private func assignmentChanged(current: (id: String, name: String)? = ("EQP-XUC3-POKU", "P6 Skid Steer U31")) -> SyncHTTPResult {
        var error: [String: Any] = ["code": "QUEUE_ASSIGNMENT_CHANGED",
                                    "message": "The assigned machine changed — this item now has \(current?.name ?? "another machine") assigned.",
                                    "retryable": false,
                                    "corrective_action": "Refresh the item and act on the machine currently assigned."]
        if let current {
            error["current_equipment"] = ["name": current.name, "unique_id": current.id, "display_id": "P6-U31",
                                          "is_key": false, "is_fuel": true, "power_source_type": "diesel"]
        }
        let body: [String: Any] = ["success": false, "message": error["message"]!, "error": error, "request_id": "ios-p10-409"]
        return .response(SyncHTTPResponse(statusCode: 409, headers: ["X-Request-Id": "ios-p10-409"], body: Fixtures.json(body)))
    }

    private func capture(_ subject: AvailabilitySubject = .unit, key: String? = nil) -> AvailabilityCapture {
        AvailabilityCapture(orderUniqueId: order, orderProductUniqueId: product, equipmentUniqueId: key ?? unitA,
                            subject: subject, subjectKey: key ?? unitA, state: .available, performedByUniqueId: "PER-5XNN-JURK")
    }

    /// A parked Available for `key`, as the engine would leave it after a 409 QUEUE_ASSIGNMENT_CHANGED.
    private func parked(key: String? = nil, subject: AvailabilitySubject = .unit, code: String = "QUEUE_ASSIGNMENT_CHANGED",
                        verdict: SyncAssignmentChange?, message: String? = nil, state: SyncState = .needsAttention,
                        type: String = AssemblyOperationBuilder.availabilityType, at: Date = Date()) -> SyncOperation {
        let c = capture(subject, key: key)
        var op = SyncOperation(type: type, capturedAt: at, queuedAt: at,
                               identity: AssemblyOperationBuilder.identity(c),
                               payload: AssemblyOperationBuilder.availabilityPayload(c),
                               displayTitle: "Available · unit \(c.subjectKey)")
        op.state = state
        op.attempts.attemptCount = 3
        op.attempts.lastStatusCode = 409
        op.attempts.lastErrorCode = code
        op.attempts.lastErrorMessage = message ?? "The assigned machine changed — this item now has \(unitBName) assigned."
        op.attempts.lastDisposition = .needsAttention
        op.attentionReason = op.attempts.lastErrorMessage
        op.assignmentChange = verdict
        return op
    }

    private func verdictB(at: Date = Date()) -> SyncAssignmentChange {
        SyncAssignmentChange(currentEquipmentUniqueId: unitB, currentEquipmentName: unitBName, receivedAt: at)
    }

    private func fixture(_ name: String) throws -> Data {
        let candidates = [
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).json"),
            Bundle(for: StaleAvailabilityRetirementTests.self).url(forResource: name, withExtension: "json"),
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) { return try Data(contentsOf: url) }
        throw XCTSkip("Fixture \(name).json not synced — run Scripts/sync-contract-fixtures.sh")
    }

    /// The fixture review with its first member reassigned by the office to unit B, unconfirmed —
    /// what the package carried at 21:58 on 2026-09-29.
    private func reviewReassignedToB() throws -> (member: AssemblyMember, group: AssemblyGroup) {
        var envelope = try JSONSerialization.jsonObject(with: fixture("queue_line_assembly")) as! [String: Any]
        var data = envelope["data"] as! [String: Any]
        var groups = data["assemblies"] as! [[String: Any]]
        var members = groups[0]["members"] as! [[String: Any]]
        var m = members[0]
        m["order_product_unique_id"] = product
        var identity = m["identity"] as! [String: Any]
        identity["order_product_unique_id"] = product; identity["equipment_unique_id"] = unitB; m["identity"] = identity
        var equipment = m["equipment"] as! [String: Any]
        equipment["unique_id"] = unitB; equipment["name"] = unitBName; equipment["display_id"] = "P6-U31"; m["equipment"] = equipment
        var availability = m["availability"] as! [String: Any]
        availability["unit"] = ["equipment_unique_id": unitB, "state": NSNull(), "acknowledged_by": NSNull(), "acknowledged_at": NSNull(), "note": NSNull()]
        m["availability"] = availability
        members[0] = m
        groups[0]["members"] = members
        data["assemblies"] = groups
        envelope["data"] = data
        let review = try AssemblyReviewEnvelope.decode(JSONSerialization.data(withJSONObject: envelope)).data
        return (review.assemblies[0].members[0], review.assemblies[0])
    }

    private func judged(_ ops: [SyncOperation], _ f: (member: AssemblyMember, group: AssemblyGroup))
        -> (state: AvailabilityState?, gate: AssemblyPolicy.LocalGate, overlay: AssemblyLocalOverlay) {
        let overlay = AssemblyLocalOverlay.from(ops)
        let queue = QueueLineLocalOverlay.from(ops)
        return (AssemblyPolicy.unitState(member: f.member, queue: queue, overlay: overlay),
                AssemblyPolicy.gate(for: f.group, queue: queue, overlay: overlay), overlay)
    }

    // MARK: - 1. The server's verdict is recorded on the parked operation

    func testARejectionNamingTheMachineNowAssignedIsRecordedOnTheParkedOperation() throws {
        client.defaultResult = assignmentChanged()
        let e = engine()
        let op = try AssemblyOperationBuilder.enqueueAvailability(capture(), into: e)
        waitUntil("parked") { e.operation(id: op.id)?.state == .needsAttention }

        let parked = try XCTUnwrap(e.operation(id: op.id))
        XCTAssertEqual(parked.attempts.lastErrorCode, "QUEUE_ASSIGNMENT_CHANGED")
        XCTAssertEqual(parked.assignmentChange?.currentEquipmentUniqueId, unitB, "the machine the server says is assigned now")
        XCTAssertEqual(parked.assignmentChange?.currentEquipmentName, unitBName)
        XCTAssertNil(parked.supersession, "recording the verdict is not yet retiring the decision")
        XCTAssertEqual(e.summary().needsAttention, 1)

        // Any other terminal rejection records no verdict.
        client.defaultResult = Fixtures.failure(422, code: "QUEUE_OPTION_UNKNOWN", retryable: false, message: "That option is not part of this order line.")
        let other = try AssemblyOperationBuilder.enqueueAvailability(capture(.option, key: "POPT-GONE"), into: e)
        waitUntil("parked too") { e.operation(id: other.id)?.state == .needsAttention }
        XCTAssertNil(e.operation(id: other.id)?.assignmentChange)

        // And a QUEUE_ASSIGNMENT_CHANGED that does not name the current machine records none either.
        client.defaultResult = assignmentChanged(current: nil)
        let nameless = try AssemblyOperationBuilder.enqueueAvailability(capture(key: "EQP-OTHER"), into: e)
        waitUntil("parked three") { e.operation(id: nameless.id)?.state == .needsAttention }
        XCTAssertNil(e.operation(id: nameless.id)?.assignmentChange)

        // A retry clears the verdict, and the NEXT answer decides what is recorded: a nameless
        // rejection after a named one leaves no verdict behind — the rule then has nothing to prove with.
        e.retryNow(operationId: op.id)
        waitUntil("parked again") { e.operation(id: op.id)?.attempts.attemptCount == 2 && e.operation(id: op.id)?.state == .needsAttention }
        XCTAssertNil(e.operation(id: op.id)?.assignmentChange, "the stale verdict did not survive the retry")
        XCTAssertNil(StaleAvailabilityRetirement.supersession(for: e.operation(id: op.id)!, canonicalEquipmentUniqueId: unitB, canonicalEquipmentName: nil, now: Date()))
    }

    // MARK: - 2. The rule retires ONLY when every proof holds

    func testTheRuleRetiresOnlyWhenEveryProofHolds() {
        let now = Date()
        let retire = StaleAvailabilityRetirement.supersession(for: parked(verdict: verdictB()), canonicalEquipmentUniqueId: unitB,
                                                              canonicalEquipmentName: unitBName, now: now)
        XCTAssertEqual(retire?.reason, "QUEUE_ASSIGNMENT_CHANGED")
        XCTAssertEqual(retire?.retiredSubjectKey, unitA)
        XCTAssertEqual(retire?.supersededByEquipmentUniqueId, unitB)
        XCTAssertEqual(retire?.resolvedAt, now)
        XCTAssertEqual(retire?.proof, .serverVerdict)

        let cases: [(String, SyncOperation, String?, String?)] = [
            ("phone has not established the canonical unit yet", parked(verdict: verdictB()), nil, nil),
            ("phone still holds A as canonical (package not refreshed)", parked(verdict: verdictB()), unitA, "P6 Skid Steer U27"),
            ("phone holds a THIRD unit — the verdict and the package disagree", parked(verdict: verdictB()), "EQP-C", "Unit C"),
            ("the verdict names A itself — nothing moved", parked(verdict: SyncAssignmentChange(currentEquipmentUniqueId: unitA, currentEquipmentName: "U27", receivedAt: now)), unitA, "U27"),
            ("an option decision, not a unit", parked(key: "POPT-ITM-TOOTH", subject: .option, verdict: verdictB()), unitB, unitBName),
            ("a different rejection code", parked(code: "QUEUE_ITEM_LOCKED", verdict: verdictB(), message: "Locked."), unitB, unitBName),
            ("a switch, not an availability", parked(verdict: verdictB(), type: PreparationOperationBuilder.substitutionType), unitB, unitBName),
            ("not parked: pending", parked(verdict: verdictB(), state: .pending), unitB, unitBName),
            ("not parked: synced", parked(verdict: verdictB(), state: .synced), unitB, unitBName),
            ("already superseded", parked(verdict: verdictB(), state: .superseded), unitB, unitBName),
        ]
        for (name, op, canonical, canonicalName) in cases {
            XCTAssertNil(StaleAvailabilityRetirement.supersession(for: op, canonicalEquipmentUniqueId: canonical, canonicalEquipmentName: canonicalName, now: now), name)
        }
    }

    // MARK: - 3. Superseding keeps the history and never replays it

    func testSupersedingParksTheHistoryAndNeverReplaysIt() throws {
        client.defaultResult = assignmentChanged()
        let e = engine()
        let op = try AssemblyOperationBuilder.enqueueAvailability(capture(), into: e)
        waitUntil("parked") { e.operation(id: op.id)?.state == .needsAttention }
        let requestsBefore = client.requestCount

        let parked = try XCTUnwrap(e.operation(id: op.id))
        let supersession = try XCTUnwrap(StaleAvailabilityRetirement.supersession(for: parked, canonicalEquipmentUniqueId: unitB, canonicalEquipmentName: unitBName, now: Date()))
        e.supersede(operationId: op.id, with: supersession)
        waitUntil("superseded") { e.operation(id: op.id)?.state == .superseded }

        let retired = try XCTUnwrap(e.operation(id: op.id))
        XCTAssertEqual(retired.supersession, supersession)
        XCTAssertEqual(retired.payload["subject_key"]?.stringValue, unitA, "the original decision is still readable")
        XCTAssertEqual(retired.attempts.lastErrorCode, "QUEUE_ASSIGNMENT_CHANGED", "and so is what the server said")
        XCTAssertEqual(retired.assignmentChange?.currentEquipmentUniqueId, unitB)
        XCTAssertNil(retired.attentionReason, "no longer asks a person for anything")
        XCTAssertTrue(retired.isTerminal)
        XCTAssertFalse(retired.isEligibleForSync)
        XCTAssertEqual(e.summary().needsAttention, 0)
        XCTAssertEqual(e.summary().superseded, 1)

        // Inspectable in diagnostics, ranked with history.
        let entry = try XCTUnwrap(e.diagnostics().first { $0.operationId == op.id })
        XCTAssertEqual(entry.state, .superseded)
        XCTAssertEqual(entry.stateLabel, "Superseded")
        XCTAssertTrue(entry.errorSummary?.contains(unitBName) == true, "the record still says why: \(entry.errorSummary ?? "nil")")

        // Never sent again: kicks and a person's retry leave it alone.
        e.kick(reason: "later", ignoreBackoff: true)
        e.retryNow(operationId: op.id)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(client.requestCount, requestsBefore)
        XCTAssertEqual(e.operation(id: op.id)?.state, .superseded)

        // Survives a relaunch as history, with one lifetime for history on the phone: kept inside
        // the acknowledged-record retention window, pruned with the acknowledged ones after it.
        let relaunched = SyncEngine(store: try FileSyncOperationStore(rootDirectory: dir), httpClient: FakeSyncHTTPClient(),
                                    handlers: [AvailabilityHandler()], policy: SyncRetryPolicy(backoffSchedule: [0.05]))
        XCTAssertEqual(relaunched.operation(id: op.id)?.state, .superseded)
        let stored = try XCTUnwrap(relaunched.operation(id: op.id)?.supersession)
        XCTAssertEqual(stored.reason, supersession.reason)
        XCTAssertEqual(stored.retiredSubjectKey, unitA)
        XCTAssertEqual(stored.supersededByEquipmentUniqueId, unitB)
        XCTAssertEqual(stored.supersededByEquipmentName, unitBName)
        XCTAssertEqual(stored.proof, .serverVerdict)
        XCTAssertEqual(stored.resolvedAt.timeIntervalSince1970, supersession.resolvedAt.timeIntervalSince1970, accuracy: 1)
        relaunched.pruneSynced(now: Date().addingTimeInterval(6 * 86_400))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNotNil(relaunched.operation(id: op.id), "inside the retention window the history stays")
        relaunched.pruneSynced(now: Date().addingTimeInterval(8 * 86_400))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(relaunched.operation(id: op.id), "after it, retired history goes the way acknowledged history does")

        // Only a parked operation can be superseded: a pending or synced one is refused.
        client.defaultResult = Fixtures.ok(["success": true, "data": ["acknowledgement": ["state": "available"]], "request_id": "srv-ok"])
        let fresh = try AssemblyOperationBuilder.enqueueAvailability(capture(key: unitB), into: e)
        waitUntil("synced") { e.operation(id: fresh.id)?.state == .synced }
        e.supersede(operationId: fresh.id, with: supersession)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(e.operation(id: fresh.id)?.state, .synced, "a synced decision is never rewritten")
        XCTAssertNil(e.operation(id: fresh.id)?.supersession)
    }

    // MARK: - 4. A superseded decision is neither evidence nor an issue, and never confirms B

    func testASupersededDecisionIsNeitherEvidenceNorAnIssueAndNeverConfirmsTheNewUnit() throws {
        let f = try reviewReassignedToB()
        let base = Date().addingTimeInterval(-600)
        var stale = parked(verdict: verdictB(at: base.addingTimeInterval(60)), at: base)

        // Before retirement: the phone shows B, STOP, and the stale A carries a Sync Issue.
        let before = judged([stale], f)
        XCTAssertNil(before.overlay.unitDecision(product: product, equipmentUniqueId: unitB), "A's decision never reads as a decision about B")
        XCTAssertNil(before.state)
        XCTAssertFalse(before.gate.ready)
        XCTAssertTrue(before.gate.blockers.contains("\(unitBName) has not been confirmed Available."), "\(before.gate.blockers)")
        XCTAssertNotNil(before.overlay.attentionReason(product), "this is the P10 defect: a Sync Issue that can never be acted on")

        // After retirement: same B, same STOP — and no Sync Issue, no pending, no decision at all.
        stale.state = .superseded
        stale.attentionReason = nil
        stale.supersession = SyncSupersession(reason: "QUEUE_ASSIGNMENT_CHANGED", retiredSubjectKey: unitA, supersededByEquipmentUniqueId: unitB,
                                              supersededByEquipmentName: unitBName, resolvedAt: base.addingTimeInterval(120), proof: .serverVerdict)
        let after = judged([stale], f)
        XCTAssertNil(after.overlay.attentionReason(product), "no Sync Issue")
        XCTAssertFalse(after.overlay.isPendingSync(product))
        XCTAssertNil(after.overlay.unitDecision(product: product, equipmentUniqueId: unitA), "not evidence any more")
        XCTAssertNil(after.overlay.unitDecision(product: product, equipmentUniqueId: unitB), "and never a confirmation of B")
        XCTAssertNil(after.state)
        XCTAssertFalse(after.gate.ready)
        XCTAssertTrue(after.gate.blockers.contains("\(unitBName) has not been confirmed Available."), "\(after.gate.blockers)")
        XCTAssertFalse(EffectiveFieldState.countsAsDurableEvidence(.superseded))

        // A fresh Available on B is an ordinary new decision: it confirms B and the assembly can reach GO.
        var freshB = parked(key: unitB, verdict: nil, state: .pending, at: base.addingTimeInterval(180))
        freshB.attempts = SyncAttemptRecord(); freshB.attentionReason = nil
        let confirmed = judged([stale, freshB], f)
        XCTAssertEqual(confirmed.overlay.unitDecision(product: product, equipmentUniqueId: unitB)?.state, .available)
        XCTAssertEqual(confirmed.state, .available)
        XCTAssertFalse(confirmed.gate.blockers.contains("\(unitBName) has not been confirmed Available."), "\(confirmed.gate.blockers)")
        XCTAssertTrue(confirmed.overlay.isPendingSync(product), "Pending Sync while the new decision travels")
        XCTAssertNil(confirmed.overlay.attentionReason(product), "still no Sync Issue")
        freshB.state = .synced
        let synced = judged([stale, freshB], f)
        XCTAssertEqual(synced.state, .available)
        XCTAssertFalse(synced.overlay.isPendingSync(product))
        XCTAssertNil(synced.overlay.attentionReason(product))
    }

    // MARK: - 5/6/7. What stays parked

    func testARejectedSwitchAndOtherTerminalFailuresAreUntouched() throws {
        let f = try reviewReassignedToB()
        let now = Date()
        // A rejected switch (A→B→A fix, 2026-09-29): still parked, still not an episode boundary.
        let rejectedSwitch = parked(verdict: verdictB(), type: PreparationOperationBuilder.substitutionType)
        XCTAssertNil(StaleAvailabilityRetirement.supersession(for: rejectedSwitch, canonicalEquipmentUniqueId: unitB, canonicalEquipmentName: unitBName, now: now))
        var confirmedA = parked(verdict: nil, state: .synced, at: now.addingTimeInterval(-300))
        confirmedA.attempts = SyncAttemptRecord(); confirmedA.attentionReason = nil
        let overlay = AssemblyLocalOverlay.from([confirmedA, rejectedSwitch])
        XCTAssertEqual(overlay.unitDecision(product: product, equipmentUniqueId: unitA)?.state, .available,
                       "a rejected switch retires nothing (unchanged behaviour)")

        // Other terminal failures on an availability stay Needs Attention with their reason.
        let optionRefused = parked(key: "POPT-GONE", subject: .option, code: "QUEUE_OPTION_UNKNOWN", verdict: nil, message: "That option is not part of this order line.")
        XCTAssertNil(StaleAvailabilityRetirement.supersession(for: optionRefused, canonicalEquipmentUniqueId: unitB, canonicalEquipmentName: unitBName, now: now))
        XCTAssertNotNil(AssemblyLocalOverlay.from([optionRefused]).attentionReason(product))
        _ = f
    }

    // MARK: - Records parked before this build (order #6024 on the phone, 21:57:30)

    func testARecordParkedBeforeThisBuildIsRetiredOnlyWhenTheMessageNamesTheCanonicalUnit() {
        let now = Date()
        let legacy = parked(verdict: nil)   // no recorded verdict — only the server's sentence
        let retired = StaleAvailabilityRetirement.supersession(for: legacy, canonicalEquipmentUniqueId: unitB, canonicalEquipmentName: unitBName, now: now)
        XCTAssertEqual(retired?.supersededByEquipmentUniqueId, unitB)
        XCTAssertEqual(retired?.proof, .serverMessage)

        XCTAssertNil(StaleAvailabilityRetirement.supersession(for: legacy, canonicalEquipmentUniqueId: unitB, canonicalEquipmentName: nil, now: now), "no name to match")
        XCTAssertNil(StaleAvailabilityRetirement.supersession(for: legacy, canonicalEquipmentUniqueId: "EQP-C", canonicalEquipmentName: "P6 Skid Steer U3", now: now),
                     "a unit whose name is a prefix of the one in the sentence is not the one in the sentence")
        XCTAssertNil(StaleAvailabilityRetirement.supersession(for: legacy, canonicalEquipmentUniqueId: nil, canonicalEquipmentName: nil, now: now))
        XCTAssertNil(StaleAvailabilityRetirement.supersession(for: parked(verdict: nil, message: "Something else."), canonicalEquipmentUniqueId: unitB, canonicalEquipmentName: unitBName, now: now))
    }
}
