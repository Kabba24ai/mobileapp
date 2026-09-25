//
//  ChecklistContextTenancyTests.swift
//  Dispatch offline Phase 4 — Amendment B: the checklist context store is
//  tenant-scoped on write and on read, and the offline fallback never serves a
//  context that a local substitution or restart has replaced (review G-A–G-D).
//

import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class ChecklistContextTenancyTests: XCTestCase {

    private typealias F = DispatchOfflineFixtures

    private var root: URL!
    private var tenant: String? = "aaaaaaaaaaaaaaaa"

    override func setUp() {
        super.setUp()
        root = Fixtures.tempDirectory(name)
        tenant = "aaaaaaaaaaaaaaaa"
    }

    private func makeStore() throws -> ChecklistContextStore {
        try ChecklistContextStore(rootDirectory: root, tenantKey: { [unowned self] in self.tenant })
    }

    private func context(_ fixture: String = "delivery_checklist_context") throws -> ChecklistContext {
        try ChecklistContext.decode(envelopeData: F.data(fixture))
    }

    func testCompanyBNeverReadsCompanyAsContextsAndAKeepsItsOwn() throws {
        let store = try makeStore()
        let ctx = try context()
        try store.save(ctx)                                      // signed in to A
        let opuid = ctx.identity.orderProductUniqueId

        tenant = "bbbbbbbbbbbbbbbb"                              // logout, login to B
        XCTAssertNil(store.load(orderProductUniqueId: opuid, leg: .delivery), "B never sees A's context")
        XCTAssertEqual(store.all(), [])

        tenant = "aaaaaaaaaaaaaaaa"                              // back to A
        XCTAssertEqual(store.load(orderProductUniqueId: opuid, leg: .delivery)?.executionId, ctx.executionId)
        let relaunched = try makeStore()
        XCTAssertEqual(relaunched.load(orderProductUniqueId: opuid, leg: .delivery)?.executionId, ctx.executionId,
                       "durable per company across relaunch")
    }

    func testSignedOutReadsAndWritesNothing() throws {
        let store = try makeStore()
        tenant = nil
        XCTAssertThrowsError(try store.save(try context()))
        XCTAssertNil(store.load(orderProductUniqueId: try context().identity.orderProductUniqueId, leg: .delivery))
    }

    func testExplicitTenantWritesLandInThatCompanyOnly() throws {
        let store = try makeStore()
        let ctx = try context()
        try store.save(ctx, tenantKey: "bbbbbbbbbbbbbbbb")       // e.g. a response that belongs to B

        XCTAssertNil(store.load(orderProductUniqueId: ctx.identity.orderProductUniqueId, leg: .delivery), "not visible to A")
        XCTAssertEqual(store.load(orderProductUniqueId: ctx.identity.orderProductUniqueId, leg: .delivery, tenantKey: "bbbbbbbbbbbbbbbb")?.executionId,
                       ctx.executionId)
    }

    func testLegacyUnscopedContextsAreIgnoredNotDeleted() throws {
        let ctx = try context()
        // A pre-Phase-4 build wrote contexts straight into checklist-contexts/ — no company recorded.
        let legacyDir = root.appendingPathComponent("checklist-contexts", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyFile = legacyDir.appendingPathComponent(
            ChecklistContextStore.key(orderProductUniqueId: ctx.identity.orderProductUniqueId, leg: .delivery) + ".json")
        try KabbaISO8601.makeEncoder().encode(ctx).write(to: legacyFile)

        let store = try makeStore()

        XCTAssertNil(store.load(orderProductUniqueId: ctx.identity.orderProductUniqueId, leg: .delivery),
                     "ownership cannot be proven — never served")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyFile.path), "and never deleted")
    }
}

// MARK: - Offline fallback correctness (review G-A–G-D, P4-D4)

final class ChecklistContextFallbackPolicyTests: XCTestCase {

    private typealias F = DispatchOfflineFixtures
    private typealias P = ChecklistContextFallbackPolicy

    private func context() throws -> ChecklistContext {
        var ctx = try ChecklistContext.decode(envelopeData: F.data("delivery_checklist_context"))
        ctx.cachedAt = Date(timeIntervalSince1970: 1_790_000_000)
        return ctx
    }

    private func discard(_ type: String, product: String, execution: String?, at: Date) -> SyncOperation {
        SyncOperation(type: type, capturedAt: at, queuedAt: at,
                      identity: SyncBusinessIdentity(orderProductUniqueId: product, checklistExecutionId: execution),
                      payload: .object(["x": .string("y")]))
    }

    func testAnUntouchedCachedContextIsServedOffline() throws {
        let ctx = try context()
        XCTAssertTrue(P.canServeOffline(ctx, equipmentHint: nil, strictUnit: false, operations: []))
        XCTAssertTrue(P.canServeOffline(ctx, equipmentHint: ctx.equipment.equipmentUniqueId, strictUnit: true, operations: []))
    }

    func testAnOfflineSubstitutionNeverServesTheReplacedUnitsContext() throws {
        let ctx = try context()
        let swap = discard(EffectiveFieldState.equipmentSubstitutionType, product: ctx.identity.orderProductUniqueId,
                           execution: ctx.executionId, at: ctx.cachedAt!.addingTimeInterval(60))

        XCTAssertFalse(P.canServeOffline(ctx, equipmentHint: "EQP-REPLACEMENT", strictUnit: true, operations: [swap]),
                       "G-A: the superseded context (old unit) is never handed back")
        XCTAssertFalse(P.canServeOffline(ctx, equipmentHint: nil, strictUnit: false, operations: [swap]))
    }

    func testAnOfflineRestartNeverReusesTheSupersededExecution() throws {
        let ctx = try context()
        let restart = discard(EffectiveFieldState.deliveryRestartType, product: ctx.identity.orderProductUniqueId,
                              execution: ctx.executionId, at: ctx.cachedAt!.addingTimeInterval(60))
        XCTAssertFalse(P.canServeOffline(ctx, equipmentHint: ctx.equipment.equipmentUniqueId, strictUnit: true, operations: [restart]),
                       "G-B")
    }

    func testAStrictUnitHintMustMatch() throws {
        let ctx = try context()
        XCTAssertFalse(P.canServeOffline(ctx, equipmentHint: "EQP-OTHER", strictUnit: true, operations: []), "G-C")
        XCTAssertTrue(P.canServeOffline(ctx, equipmentHint: "EQP-OTHER", strictUnit: false, operations: []),
                      "a non-strict hint keeps today's behavior (the context's unit is authoritative)")
    }

    func testADiscardNewerThanTheCachedCopyInvalidatesIt() throws {
        let ctx = try context()
        let older = discard(EffectiveFieldState.deliveryRestartType, product: ctx.identity.orderProductUniqueId,
                            execution: "ORD-CHK-SOMETHING-ELSE", at: ctx.cachedAt!.addingTimeInterval(-60))
        let newer = discard(EffectiveFieldState.deliveryRestartType, product: ctx.identity.orderProductUniqueId,
                            execution: nil, at: ctx.cachedAt!.addingTimeInterval(60))
        XCTAssertTrue(P.canServeOffline(ctx, equipmentHint: nil, strictUnit: false, operations: [older]))
        XCTAssertFalse(P.canServeOffline(ctx, equipmentHint: nil, strictUnit: false, operations: [newer]))
        let sibling = discard(EffectiveFieldState.deliveryRestartType, product: "ORD-SCH-SIBLING", execution: nil,
                              at: ctx.cachedAt!.addingTimeInterval(60))
        XCTAssertTrue(P.canServeOffline(ctx, equipmentHint: nil, strictUnit: false, operations: [sibling]), "another product's discard")
    }
}
