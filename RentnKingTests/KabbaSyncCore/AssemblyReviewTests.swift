//
//  AssemblyReviewTests.swift
//  KabbaSyncCoreTests — Queue Line Assembly Review (dependent-assembly model, 2026-09-14)
//
//  Contract decode of the shared fixtures (a dependent assembly derived from
//  a persisted related-product edge), the ONE durable operation (payload /
//  identity / request / FIFO with the line's own checklist ops), the local
//  overlay (latest confirmation wins, Not Available demotes a Staged member
//  until a later Save), and the pure policy: least-advanced aggregation,
//  effective availability, the derived STOP/GO gate, refusal wording — the
//  mirrors of the Laravel rules the phone renders from. No grouping
//  operation exists: true dependencies cannot be unbundled.
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class AssemblyReviewTests: XCTestCase {

    private var dir: URL!
    private var client: FakeSyncHTTPClient!

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
        client = FakeSyncHTTPClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: Fixtures

    private func fixture(_ name: String) throws -> Data {
        let candidates = [
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).json"),
            Bundle(for: AssemblyReviewTests.self).url(forResource: name, withExtension: "json"),
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }
        throw XCTSkip("Fixture \(name).json not synced — run Scripts/sync-contract-fixtures.sh")
    }

    private func review() throws -> AssemblyReviewEnvelope { try AssemblyReviewEnvelope.decode(fixture("queue_line_assembly")) }

    /// The fixture review with one member rewritten (equipment removed, or a stage changed).
    private func reviewVariant(_ mutate: (inout [String: Any], Int) -> Void) throws -> AssemblyReview {
        var envelope = try JSONSerialization.jsonObject(with: fixture("queue_line_assembly")) as! [String: Any]
        var data = envelope["data"] as! [String: Any]
        var groups = data["assemblies"] as! [[String: Any]]
        var members = groups[0]["members"] as! [[String: Any]]
        for i in members.indices { mutate(&members[i], i) }
        groups[0]["members"] = members
        data["assemblies"] = groups
        envelope["data"] = data
        return try AssemblyReviewEnvelope.decode(JSONSerialization.data(withJSONObject: envelope)).data
    }

    private struct AllHandlers: SyncOperationHandler {
        let operationType: String
        func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
            switch operation.type {
            case AssemblyOperationBuilder.availabilityType: return try AssemblyRequestFactory.availabilityRequest(for: operation)
            default:
                var body = operation.payload.objectValue ?? [:]
                body["operation_id"] = .string(operation.id)
                return SyncHTTPRequest(method: "POST", path: "orders/checklists/X/prepare", headers: [:], jsonBody: .object(body), operationId: operation.id)
            }
        }
    }

    private func engine() -> SyncEngine {
        SyncEngine(store: try! FileSyncOperationStore(rootDirectory: dir), httpClient: client,
                   handlers: [AllHandlers(operationType: AssemblyOperationBuilder.availabilityType),
                              AllHandlers(operationType: EffectiveFieldState.deliveryPrepareType)],
                   policy: SyncRetryPolicy(backoffSchedule: [0.05]))
    }

    private func availability(_ product: String, _ subject: AvailabilitySubject, _ key: String, _ state: AvailabilityState) -> AvailabilityCapture {
        AvailabilityCapture(orderUniqueId: "ORD-0001", orderProductUniqueId: product, equipmentUniqueId: "EQP-0001",
                            subject: subject, subjectKey: key, state: state, performedByUniqueId: "PER-0007")
    }

    /// A durable staging Save for the same line (the operation the board reads as Staged).
    private func stagingSave(_ product: String, into engine: SyncEngine, at: Date) throws -> SyncOperation {
        try engine.enqueue(type: EffectiveFieldState.deliveryPrepareType,
                           payload: .object(["order_product_unique_id": .string(product), "mark_staged": .bool(true), "answers": .array([])]),
                           identity: SyncBusinessIdentity(orderUniqueId: "ORD-0001", orderProductUniqueId: product, checklistExecutionId: "ORD-CHK-1"),
                           capturedAt: at, displayTitle: "Save", operationId: UUID().uuidString)
    }

    // MARK: Contract

    func testTheAssemblyReviewFixtureDecodesADependentAssemblyDerivedFromPersistedEdges() throws {
        let envelope = try review()
        XCTAssertTrue(envelope.success)
        XCTAssertEqual(envelope.meta?.employee?.uniqueId.isEmpty, false, "the phone learns who is acting from meta.employee")

        let data = envelope.data
        XCTAssertFalse(data.order.uniqueId.isEmpty)
        XCTAssertEqual(data.assemblies.count, 1, "the fixture order is ONE dependent assembly: a base line + its related child")
        let group = data.assemblies[0]
        XCTAssertEqual(group.kind, .dependent)
        XCTAssertEqual(group.memberCount, 2)
        XCTAssertEqual(data.memberCount, 2)
        XCTAssertTrue(group.key.hasPrefix("QLA-"))

        let base = group.members[0]
        let child = group.members[1]
        XCTAssertTrue(base.assembly.dependency.isBase, "the base product leads")
        XCTAssertEqual(child.assembly.dependency.role, "related_child")
        XCTAssertEqual(child.assembly.dependency.dependsOn, base.orderProductUniqueId, "the child names the exact parent ROW")
        XCTAssertEqual(child.assembly.dependency.dependsOnName, base.product.name)
        XCTAssertEqual(base.assembly.key, group.key)
        XCTAssertEqual(child.assembly.key, group.key)

        XCTAssertEqual(base.lifecycleStage, .pending)
        XCTAssertEqual(base.productOptions.count, 1)
        XCTAssertEqual(base.productOptions[0].name, "Tooth Bucket", "the stored label, verbatim")
        XCTAssertEqual(base.productOptions[0].availability.state, .notAvailable)
        XCTAssertEqual(base.availability.unit.state, .available)
        XCTAssertEqual(base.availability.effectiveState, .notAvailable, "one Not Available decides the parent")
        XCTAssertEqual(base.availability.requiredCount, 2)
        XCTAssertTrue(child.productOptions.isEmpty, "a line without Product Options projects an empty list — nothing invented")
        XCTAssertNotNil(child.equipment?.uniqueId)
        XCTAssertNil(child.availability.unit.state, "unconfirmed")

        // The derived gate: STOP, with every unmet requirement of BOTH members.
        XCTAssertFalse(group.gate.ready)
        XCTAssertEqual(group.gate.requiredCount, 3, "base unit + Tooth Bucket + child unit")
        XCTAssertEqual(group.gate.confirmedCount, 1)
        XCTAssertEqual(group.gate.blockers.map(\.code), ["option_not_available", "unit_unconfirmed"])
        XCTAssertEqual(group.gate.blockers[0].label, "Tooth Bucket is acknowledged Not Available.")
        XCTAssertEqual(group.gate.blockers[1].orderProductUniqueId, child.orderProductUniqueId)
        XCTAssertEqual(group.gate.blockers[1].productName, child.product.name)
        XCTAssertEqual(base.stageBlockers, group.gate.blockers, "every member carries its assembly's gate")
        XCTAssertEqual(base.assembly.gate, group.gate)
        XCTAssertEqual(base.checklist.delivery.status, .notPrepared)
    }

    func testTheAcknowledgementResponseDecodes() throws {
        let ack = try KabbaISO8601.makeDecoder().decode(AckResponse.self, from: fixture("queue_line_availability_acknowledged"))
        XCTAssertEqual(ack.data.acknowledgement.state, "available")
        XCTAssertEqual(ack.data.acknowledgement.unstaged, false, "an Available never changes lifecycle")
        XCTAssertEqual(ack.data.lifecycleStage, "pending")
        XCTAssertFalse(ack.data.assembly.gate.ready, "one confirmation does not make the assembly GO")
    }

    func testTheChecklistContextCarriesTheAssemblyGateBlockers() throws {
        let context = try ChecklistContext.decode(envelopeData: fixture("delivery_checklist_context"))
        let blockers = try XCTUnwrap(context.serverState.stageBlockers, "the delivery context lists what holds the assembly at STOP")
        XCTAssertFalse(blockers.isEmpty)
        XCTAssertTrue(blockers.contains { $0.code == "unit_unconfirmed" && $0.productName?.isEmpty == false }, "a dependent sibling's unmet requirement gates this line too")
    }

    func testAnOldGroupingVocabularyNeverBreaksTheDecode() throws {
        let data = try reviewVariant { member, _ in
            var assembly = member["assembly"] as! [String: Any]
            assembly["kind"] = "unbundled"          // the retired model
            assembly["can_unbundle"] = true
            assembly.removeValue(forKey: "gate")
            assembly.removeValue(forKey: "dependency")
            member["assembly"] = assembly
        }
        XCTAssertEqual(data.members[0].assembly.kind, .single, "an unknown kind reads as a line on its own")
        XCTAssertEqual(data.members[0].assembly.gate, .unknown)
        XCTAssertTrue(data.members[0].assembly.dependency.isBase)
    }

    private struct AckResponse: Decodable {
        struct Data: Decodable {
            struct Ack: Decodable { let state: String; let unstaged: Bool }
            let acknowledgement: Ack
            let lifecycleStage: String
            let assembly: AssemblyInfo
            enum CodingKeys: String, CodingKey { case acknowledgement, lifecycleStage = "lifecycle_stage", assembly }
        }
        let data: Data
    }

    // MARK: The operation

    func testTheAvailabilityOperationCarriesTheExactBodyIdentityAndRoute() throws {
        let e = engine()
        client.defaultResult = .failure(APIError.transport(.offline))

        let ack = try AssemblyOperationBuilder.enqueueAvailability(
            availability("ORD-SCH-A", .option, "POPT-ITM-TOOTH", .available), into: e, operationId: "QLA-OP-0001")
        XCTAssertEqual(ack.type, "queue_line.availability")
        XCTAssertEqual(ack.identity.orderProductUniqueId, "ORD-SCH-A")
        XCTAssertEqual(ack.identity.orderUniqueId, "ORD-0001")
        XCTAssertEqual(ack.payload["subject_type"]?.stringValue, "option")
        XCTAssertEqual(ack.payload["subject_key"]?.stringValue, "POPT-ITM-TOOTH")
        XCTAssertEqual(ack.payload["state"]?.stringValue, "available")
        XCTAssertEqual(ack.payload["performed_by"]?.stringValue, "PER-0007")
        XCTAssertNil(ack.payload["note"], "an empty note is not sent")

        let unitAck = try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-A", .unit, "EQP-0001", .available), into: e)
        XCTAssertEqual(unitAck.identity.equipmentUniqueId, "EQP-0001", "a unit decision names the unit it was about")

        let request = try AssemblyRequestFactory.availabilityRequest(for: ack)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "queue-line/ORD-SCH-A/availability")
        XCTAssertEqual(request.headers["X-Operation-Id"], "QLA-OP-0001")
        XCTAssertEqual(request.jsonBody?["operation_id"]?.stringValue, "QLA-OP-0001")

        // A reversal is the same operation with the canonical Not Available state — never a second control.
        let reversal = try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-A", .option, "POPT-ITM-TOOTH", .notAvailable), into: e)
        XCTAssertEqual(reversal.payload["state"]?.stringValue, "not_available")
        XCTAssertEqual(try AssemblyRequestFactory.availabilityRequest(for: reversal).path, "queue-line/ORD-SCH-A/availability")
    }

    func testAnOfflineConfirmationIsDurableSurvivesRelaunchAndReplaysUnderTheSameOperationId() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let first = engine()
        let op = try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-A", .option, "POPT-ITM-TOOTH", .available), into: first, operationId: "QLA-OP-0010")
        waitUntil("first attempt") { self.client.requestCount >= 1 }
        XCTAssertEqual(first.operation(id: op.id)?.state, .pending)

        // "Force quit": a new engine over the same directory still holds the decision …
        let second = engine()
        XCTAssertEqual(second.operation(id: op.id)?.state, .pending)
        XCTAssertEqual(AssemblyLocalOverlay.from(second.snapshot()).optionDecision(product: "ORD-SCH-A", frozenOptionKey: "POPT-ITM-TOOTH")?.state, .available)

        // … and every retry carries the SAME operation id (server-side replay).
        client.defaultResult = Fixtures.ok(["success": true, "data": ["acknowledgement": ["state": "available", "replayed": false, "unstaged": false]], "request_id": "srv-1"])
        second.kick(reason: "test reconnect")
        waitUntil("synced") { second.operation(id: op.id)?.state == .synced }
        XCTAssertTrue(client.recorded.allSatisfy { $0.headers["X-Operation-Id"] == "QLA-OP-0010" })
    }

    func testATerminalRefusalParksAsNeedsAttentionAndKeepsTheDecision() throws {
        client.defaultResult = Fixtures.failure(422, code: "QUEUE_OPTION_UNKNOWN", retryable: false, message: "That option is not part of this order line.")
        let e = engine()
        let op = try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-A", .option, "POPT-ITM-GONE", .available), into: e)
        waitUntil("parked") { e.operation(id: op.id)?.state == .needsAttention }

        let overlay = AssemblyLocalOverlay.from(e.snapshot())
        XCTAssertNotNil(overlay.optionDecision(product: "ORD-SCH-A", frozenOptionKey: "POPT-ITM-GONE"), "the work stands — never silently dropped")
        XCTAssertTrue(overlay.attentionReason("ORD-SCH-A")?.hasPrefix("That option is not part of this order line.") == true,
                      "the server's employee-facing message is what the screen shows (the engine appends the code)")
        XCTAssertFalse(overlay.isPendingSync("ORD-SCH-A"))
    }

    func testOperationsOnTheSameLineStayFifoWithItsChecklistSave() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = engine()
        let ack = try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-A", .option, "POPT-ITM-TOOTH", .available), into: e)
        let save = try stagingSave("ORD-SCH-A", into: e, at: Date())
        XCTAssertEqual(ack.orderingKey, save.orderingKey, "same order product → same FIFO lane, so the confirmation lands before the Save")
    }

    // MARK: Overlay

    func testTheLatestDecisionPerSubjectWinsAndSubjectsAreIndependent() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = engine()
        try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-A", .unit, "EQP-0001", .available), into: e)
        try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-A", .option, "POPT-ITM-TOOTH", .available), into: e)
        try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-A", .option, "POPT-ITM-TOOTH", .notAvailable), into: e)
        try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-B", .unit, "EQP-0002", .available), into: e)

        let overlay = AssemblyLocalOverlay.from(e.snapshot())
        XCTAssertEqual(overlay.unitDecision(product: "ORD-SCH-A", equipmentUniqueId: "EQP-0001")?.state, .available)
        XCTAssertNil(overlay.unitDecision(product: "ORD-SCH-A", equipmentUniqueId: "EQP-9999"), "a decision is about the unit it named — never about a replacement")
        XCTAssertEqual(overlay.optionDecision(product: "ORD-SCH-A", frozenOptionKey: "POPT-ITM-TOOTH")?.state, .notAvailable, "the later decision (a reversal) wins")
        XCTAssertNil(overlay.optionDecision(product: "ORD-SCH-A", frozenOptionKey: "POPT-ITM-OTHER"))
        XCTAssertEqual(overlay.unitDecision(product: "ORD-SCH-B", equipmentUniqueId: "EQP-0002")?.state, .available)
        XCTAssertTrue(overlay.isPendingSync("ORD-SCH-A"))
        XCTAssertEqual(overlay.pendingCount, 3, "pending DECISIONS — two operations on the same subject collapse into its latest state")
    }

    func testAReversalDemotesAStagedMemberUntilALaterStagingSave() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = engine()
        let queue = { QueueLineLocalOverlay.from(e.snapshot()) }
        let assembly = { AssemblyLocalOverlay.from(e.snapshot()) }

        // Server says Staged; the technician reverses the bucket to Not Available.
        try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-A", .option, "POPT-ITM-TOOTH", .notAvailable), into: e)
        XCTAssertTrue(assembly().isUnstagedLocally("ORD-SCH-A"))
        XCTAssertEqual(AssemblyPolicy.memberStage(serverStage: .staged, product: "ORD-SCH-A", queue: queue(), assembly: assembly()), .pending,
                       "Staged + Not Available reads as Pending, exactly as the server will answer")

        // Confirming it again does NOT restage …
        try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-A", .option, "POPT-ITM-TOOTH", .available), into: e)
        XCTAssertTrue(assembly().isUnstagedLocally("ORD-SCH-A"))
        XCTAssertEqual(AssemblyPolicy.memberStage(serverStage: .staged, product: "ORD-SCH-A", queue: queue(), assembly: assembly()), .pending)

        // … only the explicit checklist Save does.
        try stagingSave("ORD-SCH-A", into: e, at: Date())
        XCTAssertFalse(assembly().isUnstagedLocally("ORD-SCH-A"))
        XCTAssertEqual(AssemblyPolicy.memberStage(serverStage: .pending, product: "ORD-SCH-A", queue: queue(), assembly: assembly()), .staged)
    }

    func testDeliveredAndInTransitMembersAreNeverDemotedByAvailability() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = engine()
        try AssemblyOperationBuilder.enqueueAvailability(availability("ORD-SCH-A", .unit, "EQP-0001", .notAvailable), into: e)
        let queue = QueueLineLocalOverlay.from(e.snapshot())
        let assembly = AssemblyLocalOverlay.from(e.snapshot())
        XCTAssertEqual(AssemblyPolicy.memberStage(serverStage: .equipmentDelivered, product: "ORD-SCH-A", queue: queue, assembly: assembly), .equipmentDelivered)
        XCTAssertEqual(AssemblyPolicy.memberStage(serverStage: .inTransit, product: "ORD-SCH-A", queue: queue, assembly: assembly), .inTransit)
    }

    // MARK: Policy — lifecycle

    func testTheAssemblyStageIsTheLeastAdvancedMember() {
        XCTAssertEqual(AssemblyPolicy.stage(forMemberStages: [.pending, .pending]), .pending)
        XCTAssertEqual(AssemblyPolicy.stage(forMemberStages: [.staged, .pending]), .pending)
        XCTAssertEqual(AssemblyPolicy.stage(forMemberStages: [.staged, .staged]), .staged)
        XCTAssertEqual(AssemblyPolicy.stage(forMemberStages: [.staged, .inTransit]), .staged)
        XCTAssertEqual(AssemblyPolicy.stage(forMemberStages: [.inTransit, .equipmentDelivered]), .inTransit)
        XCTAssertEqual(AssemblyPolicy.stage(forMemberStages: [.equipmentDelivered, .equipmentDelivered]), .equipmentDelivered)
        XCTAssertEqual(AssemblyPolicy.stage(forMemberStages: [.equipmentDelivered, .pending]), .pending, "one delivered member never makes a partially Pending assembly read Delivered")
        XCTAssertEqual(AssemblyPolicy.stage(forMemberStages: []), .pending)
        XCTAssertEqual(AssemblyPolicy.stageCounts([.staged, .pending, .inTransit]), AssemblyStageCounts(pending: 1, staged: 1, inTransit: 1, equipmentDelivered: 0))
    }

    func testTheLaneMappingKeepsThreeLanes() {
        XCTAssertEqual(AssemblyStage.pending.lane, "pending")
        XCTAssertEqual(AssemblyStage.staged.lane, "staged")
        XCTAssertEqual(AssemblyStage.inTransit.lane, "staged")
        XCTAssertEqual(AssemblyStage.equipmentDelivered.lane, "completed")
    }

    func testGroupsAreTheServersAndOnlyTheirStagesAreOverlaid() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = engine()
        let data = try review().data
        let child = data.assemblies[0].members[1]

        try stagingSave(child.orderProductUniqueId, into: e, at: Date())
        let groups = AssemblyPolicy.groups(data, queue: QueueLineLocalOverlay.from(e.snapshot()), overlay: AssemblyLocalOverlay.from(e.snapshot()))

        XCTAssertEqual(groups.map(\.key), data.assemblies.map(\.key), "membership never changes on the phone")
        XCTAssertEqual(groups[0].memberCount, 2)
        XCTAssertEqual(groups[0].stageCounts, AssemblyStageCounts(pending: 1, staged: 1, inTransit: 0, equipmentDelivered: 0))
        XCTAssertEqual(groups[0].stage, .pending, "the base line is still Pending, so the assembly is")
    }

    // MARK: Policy — availability + STOP / GO

    func testEffectiveAvailabilityRequiresTheUnitAndEveryOptionAndKeepsUnconfirmedDistinct() {
        XCTAssertNil(AssemblyPolicy.effectiveState(unit: nil, options: []), "nothing confirmed yet")
        XCTAssertNil(AssemblyPolicy.effectiveState(unit: .available, options: [nil]), "an unconfirmed option is not a confirmed one")
        XCTAssertEqual(AssemblyPolicy.effectiveState(unit: .available, options: [.available, .available]), .available)
        XCTAssertEqual(AssemblyPolicy.effectiveState(unit: .available, options: [.notAvailable, nil]), .notAvailable)
        XCTAssertEqual(AssemblyPolicy.effectiveState(unit: .notAvailable, options: []), .notAvailable)
        XCTAssertEqual(AssemblyPolicy.effectiveState(unit: nil, options: [.available]), nil, "no unit confirmation → still unconfirmed")
    }

    func testTheGateIsStopUntilEveryRequirementOfEveryMemberIsConfirmedAndGoAfter() throws {
        client.defaultResult = .failure(APIError.transport(.offline))
        let e = engine()
        let data = try review().data
        let group = data.assemblies[0]
        let base = group.members[0], child = group.members[1]
        let gate = { AssemblyPolicy.gate(for: group, queue: QueueLineLocalOverlay.from(e.snapshot()), overlay: AssemblyLocalOverlay.from(e.snapshot())) }

        // Server state: base unit Available, Tooth Bucket Not Available, child unit unconfirmed.
        var g = gate()
        XCTAssertFalse(g.ready)
        XCTAssertEqual(g.title, "STOP")
        XCTAssertEqual(g.requiredCount, 3)
        XCTAssertEqual(g.confirmedCount, 1)
        XCTAssertEqual(g.detail, "1 of 3 confirmed")
        XCTAssertEqual(g.blockers, ["Tooth Bucket is acknowledged Not Available.", "\(child.equipment!.name!) has not been confirmed Available."])

        // The bucket turns up and is confirmed on this phone: still STOP — the child's unit is unconfirmed.
        try AssemblyOperationBuilder.enqueueAvailability(
            AvailabilityCapture(orderUniqueId: base.orderUniqueId, orderProductUniqueId: base.orderProductUniqueId, equipmentUniqueId: nil,
                                subject: .option, subjectKey: base.productOptions[0].uniqueId, state: .available, performedByUniqueId: "PER-0007"), into: e)
        g = gate()
        XCTAssertFalse(g.ready)
        XCTAssertEqual(g.confirmedCount, 2)
        XCTAssertEqual(g.blockers, ["\(child.equipment!.name!) has not been confirmed Available."])
        XCTAssertEqual(AssemblyPolicy.gate(forMember: base.orderProductUniqueId, in: data, queue: QueueLineLocalOverlay(), overlay: AssemblyLocalOverlay.from(e.snapshot()))?.blockers, g.blockers,
                       "the same gate for every member of the assembly")

        // The child's unit is confirmed: GO.
        try AssemblyOperationBuilder.enqueueAvailability(
            AvailabilityCapture(orderUniqueId: child.orderUniqueId, orderProductUniqueId: child.orderProductUniqueId, equipmentUniqueId: child.equipment?.uniqueId,
                                subject: .unit, subjectKey: child.equipment!.uniqueId!, state: .available, performedByUniqueId: "PER-0007"), into: e)
        g = gate()
        XCTAssertTrue(g.ready)
        XCTAssertEqual(g.title, "GO")
        XCTAssertEqual(g.detail, "All 3 confirmed")
        XCTAssertEqual(g.blockers, [])
        XCTAssertEqual(AssemblyPolicy.gate(forMember: "ORD-SCH-NOPE", in: data, queue: QueueLineLocalOverlay(), overlay: AssemblyLocalOverlay()), nil, "a line not on the review has no gate here")
    }

    func testAnUnassignedMemberHoldsTheGateAtStopWithoutAnythingToConfirm() throws {
        let data = try reviewVariant { member, index in
            if index == 1 { member["equipment"] = NSNull() }
        }
        let g = AssemblyPolicy.gate(for: data.assemblies[0], queue: QueueLineLocalOverlay(), overlay: AssemblyLocalOverlay())
        XCTAssertFalse(g.ready)
        XCTAssertEqual(g.blockers.last, "\(data.assemblies[0].members[1].product.name!) needs a machine assigned.")
        XCTAssertEqual(g.requiredCount, 3)
    }

    func testMembersThatLeftTheYardImposeNothingOnTheGate() throws {
        let data = try reviewVariant { member, index in
            if index == 1 { member["lifecycle_stage"] = "in_transit"; member["in_transit"] = true }
        }
        let g = AssemblyPolicy.gate(for: data.assemblies[0], queue: QueueLineLocalOverlay(), overlay: AssemblyLocalOverlay())
        XCTAssertEqual(g.requiredCount, 2, "the child on the truck is physically settled")
        XCTAssertEqual(g.blockers, ["Tooth Bucket is acknowledged Not Available."])
        XCTAssertTrue(AssemblyStage.inTransit.hasLeftTheYard)
        XCTAssertTrue(AssemblyStage.equipmentDelivered.hasLeftTheYard)
        XCTAssertFalse(AssemblyStage.staged.hasLeftTheYard)
    }

    func testTheRefusalMessageUsesTheServersSubjectLabelsVerbatim() {
        XCTAssertNil(AssemblyPolicy.stagingRefusalMessage(productName: "Skid Steer", blockerLabels: []))
        XCTAssertEqual(
            AssemblyPolicy.stagingRefusalMessage(productName: "Skid Steer", blockerLabels: ["Toothed Bucket has not been confirmed Available."]),
            "Cannot stage Skid Steer because Toothed Bucket has not been confirmed Available.")
        XCTAssertEqual(
            AssemblyPolicy.stagingRefusalMessage(productName: "Skid Steer", blockerLabels: ["Brush Cutter needs a machine assigned.", "XL Smooth Bucket - 48 inch is acknowledged Not Available."]),
            "Cannot stage Skid Steer because Brush Cutter needs a machine assigned and XL Smooth Bucket - 48 inch is acknowledged Not Available.")
    }

    // MARK: Assignment on this phone (2026-09-14) — a machine is never confirmed by being assigned

    private func switchOp(product: String, to unit: String, name: String, tag: String, state: SyncState = .pending) -> SyncOperation {
        var op = SyncOperation(type: PreparationOperationBuilder.substitutionType, capturedAt: Date(), queuedAt: Date(),
                               identity: SyncBusinessIdentity(orderUniqueId: "ORD-0001", orderProductUniqueId: product, equipmentUniqueId: unit),
                               payload: .object(["order_product_unique_id": .string(product), "equipment_unique_id": .string(unit),
                                                 "equipment_name": .string(name), "equipment_display_id": .string(tag)]),
                               assets: [])
        op.state = state
        return op
    }

    private func decision(_ state: AvailabilityState, syncState: SyncState = .pending) -> AssemblyLocalOverlay.Decision {
        AssemblyLocalOverlay.Decision(state: state, queuedAt: Date(), syncState: syncState, operationId: UUID().uuidString,
                                      attentionReason: nil, performedBy: nil, note: nil)
    }

    func testAMachineSwitchedOnThisPhoneShowsByNameAndTagStartsUnconfirmedAndHoldsStop() throws {
        let data = try review().data
        let member = data.assemblies[0].members[0]          // the feed: its unit confirmed Available
        XCTAssertEqual(member.availability.unit.state, .available)
        let queue = QueueLineLocalOverlay.from([switchOp(product: member.orderProductUniqueId, to: "EQP-NEW", name: "SANY SW405K", tag: "5678")])
        let none = AssemblyLocalOverlay()

        let unit = try XCTUnwrap(AssemblyPolicy.effectiveEquipment(member: member, queue: queue))
        XCTAssertEqual(unit.uniqueId, "EQP-NEW")
        XCTAssertEqual(unit.identityLine, "SANY SW405K · #5678", "the yard reads the machine by name AND tag")
        XCTAssertTrue(unit.fromLocalSwitch)
        XCTAssertTrue(unit.pendingSync)
        XCTAssertNil(AssemblyPolicy.unitState(member: member, queue: queue, overlay: none), "the old unit's Available never carries onto the replacement")

        let gate = AssemblyPolicy.gate(for: data.assemblies[0], queue: queue, overlay: none)
        XCTAssertFalse(gate.ready, "assignment alone is STOP")
        XCTAssertTrue(gate.blockers.contains("SANY SW405K has not been confirmed Available."), "\(gate.blockers)")

        // A confirmation ABOUT the new unit counts; one about the old unit never did.
        var confirmed = AssemblyLocalOverlay()
        confirmed.availability[member.orderProductUniqueId] = [AssemblyLocalOverlay.unitKey("EQP-NEW"): decision(.available)]
        XCTAssertEqual(AssemblyPolicy.unitState(member: member, queue: queue, overlay: confirmed), .available)
        var stale = AssemblyLocalOverlay()
        stale.availability[member.orderProductUniqueId] = [AssemblyLocalOverlay.unitKey("EQP-SVSW-VGDH"): decision(.available, syncState: .synced)]
        XCTAssertNil(AssemblyPolicy.unitState(member: member, queue: queue, overlay: stale))
    }

    func testARejectedSwitchLeavesTheServersUnitAndItsConfirmation() throws {
        let data = try review().data
        let member = data.assemblies[0].members[0]
        let queue = QueueLineLocalOverlay.from([switchOp(product: member.orderProductUniqueId, to: "EQP-NEW", name: "X", tag: "1", state: .needsAttention)])
        let unit = try XCTUnwrap(AssemblyPolicy.effectiveEquipment(member: member, queue: queue))
        XCTAssertEqual(unit.uniqueId, "EQP-SVSW-VGDH")
        XCTAssertFalse(unit.fromLocalSwitch)
        XCTAssertEqual(unit.identityLine, "Skid Steer 6aa7d9ba6bd7e · #EQP-P3-6AA7D9BA6BD7F")
        XCTAssertEqual(AssemblyPolicy.unitState(member: member, queue: queue, overlay: AssemblyLocalOverlay()), .available)
    }

    func testAssigningAMachineToAnUnassignedMemberIsNotConfirmingIt() throws {
        let data = try reviewVariant { member, index in if index == 1 { member["equipment"] = NSNull() } }
        let member = data.assemblies[0].members[1]
        XCTAssertNil(AssemblyPolicy.effectiveEquipment(member: member, queue: QueueLineLocalOverlay()))
        let queue = QueueLineLocalOverlay.from([switchOp(product: member.orderProductUniqueId, to: "EQP-FIRST", name: "Harley Rake Spare", tag: "HR1")])
        let unit = try XCTUnwrap(AssemblyPolicy.effectiveEquipment(member: member, queue: queue))
        XCTAssertEqual(unit.identityLine, "Harley Rake Spare · #HR1")
        XCTAssertNil(AssemblyPolicy.unitState(member: member, queue: queue, overlay: AssemblyLocalOverlay()))
        let gate = AssemblyPolicy.gate(for: data.assemblies[0], queue: queue, overlay: AssemblyLocalOverlay())
        XCTAssertFalse(gate.ready)
        XCTAssertTrue(gate.blockers.contains("Harley Rake Spare has not been confirmed Available."), "\(gate.blockers)")
        XCTAssertFalse(gate.blockers.contains { $0.hasSuffix("needs a machine assigned.") }, "assigned now — the blocker is the missing confirmation")
    }
}
