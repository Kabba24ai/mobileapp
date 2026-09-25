//
//  DispatchOfflineFieldBridgeTests.swift
//  Dispatch offline Phase 4 — the bridge that preloads the caches the existing
//  screens already read (checklist contexts, Order Details, Assembly Review)
//  from each mission package, its freshness / identity / company rules, the
//  per-leg readiness and same-revision section repair (Amendment A), the
//  tenant boundary (Amendment B), and the key physical scenario automated:
//  reconcile online, never open the mission, go offline, and still run
//  Dispatch → Driver Checklist → Order Details → equipment checklist.
//

import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class DispatchOfflineFieldBridgeTests: XCTestCase {

    private typealias F = DispatchOfflineFixtures
    private typealias M = DispatchOfflineFixtures.Mission

    private let tenantA = URL(string: "https://api.kabba.ai/api/admin/v1/")!
    private let tenantB = URL(string: "https://api.rentnking.com/api/admin/v1/")!

    private var root: URL!
    private var server: FakeDispatchServer!
    private var store: DispatchOfflineMissionStore!
    private var contexts: ChecklistContextStore!
    private var writer: RecordingOrderCacheWriter!
    private var signedInTenant: String?
    private var operations: [SyncOperation] = []
    private var employee: ChecklistContext.Employee? = nil
    private var clock = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        root = Fixtures.tempDirectory(name)
        server = FakeDispatchServer()
        store = try! DispatchOfflineMissionStore(rootDirectory: root, baseURL: tenantA)
        signedInTenant = store.tenantKey
        contexts = try! ChecklistContextStore(rootDirectory: root, tenantKey: { [unowned self] in self.signedInTenant })
        writer = RecordingOrderCacheWriter()
        operations = []
        employee = nil
    }

    private func makeBridge(_ s: DispatchOfflineMissionStore? = nil) -> DispatchOfflineFieldBridge {
        DispatchOfflineFieldBridge(store: s ?? store, contexts: contexts, writer: writer,
                                   operations: { [unowned self] in self.operations },
                                   currentEmployee: { [unowned self] in self.employee })
    }

    private func makeReconciler(_ s: DispatchOfflineMissionStore? = nil, client: SyncHTTPClient? = nil) -> DispatchOfflineReconciler {
        let s = s ?? store!
        let r = DispatchOfflineReconciler(httpClient: client ?? server, store: s,
                                          session: { [unowned self] in self.signedInTenant == s.tenantKey ? .of(s) : nil },
                                          retainedOrderProducts: { [] }, now: { [unowned self] in self.clock })
        r.fieldBridge = makeBridge(s)
        return r
    }

    private lazy var reconciler: DispatchOfflineReconciler = makeReconciler()

    @discardableResult
    private func reconcile(_ trigger: DispatchOfflineTrigger = .manualRefresh, on r: DispatchOfflineReconciler? = nil) -> DispatchOfflineReconcileResult {
        let done = expectation(description: "reconcile")
        var out: DispatchOfflineReconcileResult!
        (r ?? reconciler).request(trigger) { out = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return out
    }

    private func m(_ id: String, _ rev: String, leg: ChecklistLeg = .delivery) -> M {
        M(opuid: "ORD-SCH-\(id)", leg: leg, revision: F.revision(rev), orderUid: "ORD-\(id)", executionId: "ORD-CHK-\(id)")
    }

    private var index: DispatchOfflineIndex { store.loadIndex() }
    private func entry(_ mission: M) -> DispatchOfflineIndex.Entry { index.entry(mission.key)! }
    private func context(_ mission: M) -> ChecklistContext? {
        contexts.load(orderProductUniqueId: mission.opuid, leg: mission.leg, tenantKey: store.tenantKey)
    }

    private func failed(_ section: String, _ mission: M) -> JSONValue {
        F.package(mission).setting([section], .null).setting(["sections", section], .string("failed"))
    }

    // MARK: - Contract (M0)

    func testTheSharedFixtureCarriesTheCanonicalContextAndThePhase4Sections() throws {
        let raw = F.packageTemplate
        let sections = try XCTUnwrap(DispatchOfflinePackageSections.from(raw))
        XCTAssertEqual(sections.orderDetails, .ok)
        XCTAssertEqual(sections.assembly, .ok)
        XCTAssertNotNil(DispatchOfflinePackageContent.orderDetails(raw)?["order_products"])
        XCTAssertNotNil(DispatchOfflinePackageContent.assembly(raw)?["data"]?["assemblies"])
        XCTAssertEqual(DispatchOfflinePackageContent.orderUniqueId(raw), raw["order_details"]?["unique_id"]?.stringValue)

        // The §0.2 gap: the package's checklist_context IS the canonical ChecklistContext.
        let context = try XCTUnwrap(DispatchOfflinePackageContent.checklistContext(raw))
        XCTAssertEqual(context.identity.orderProductUniqueId, raw["order_product_unique_id"]?.stringValue)
        XCTAssertEqual(context.leg, .delivery)
        XCTAssertFalse(context.questions.isEmpty)
        XCTAssertEqual(context.template.revision, raw["checklist_context"]?["template"]?["revision"]?.stringValue)

        XCTAssertNil(DispatchOfflinePackageSections.from(raw.setting(["sections"], .null)), "a pre-Phase-4 server")
    }

    // MARK: - Checklist-context bridge rules (§4.2)

    func testANeverOpenedMissionsContextIsBridgedIntoTheCompanysStore() {
        let a = m("A", "a1")
        server.missions = [a]

        reconcile(.launch)

        let bridged = context(a)
        XCTAssertEqual(bridged?.executionId, "ORD-CHK-A")
        XCTAssertEqual(bridged?.identity.orderProductUniqueId, a.opuid)
        XCTAssertEqual(contexts.load(orderProductUniqueId: a.opuid, leg: .delivery)?.executionId, "ORD-CHK-A",
                       "the screens' own read (current company) finds it")
        XCTAssertTrue(makeBridge().isFieldReady(entry(a)))
    }

    func testAnUndecodableContextIsNotBridgedButTheCardStillShows() {
        let a = m("A", "a1")
        server.missions = [a]
        server.packageOverrides[a.key] = F.package(a).setting(["checklist_context", "questions"], .string("unexpected shape"))

        reconcile(.launch)

        XCTAssertNil(context(a), "P4-D10: validated when bridging only")
        guard case .ready(let rows, _) = DispatchOfflineWorkingSet.present(store: store, query: DispatchOfflineQuery(dates: .all),
                                                                         operations: [], today: "2026-09-22") else { return XCTFail() }
        XCTAssertEqual(rows.map(\.orderProductUniqueId), [a.opuid], "the Dispatch card is never hidden by a checklist problem")
        XCTAssertFalse(makeBridge().isFieldReady(entry(a)))
    }

    private func savedOnline(_ mission: M, serverTime: String, cycle: Int, execution: String) throws {
        let json = F.package(mission)
            .setting(["checklist_context", "server_time"], .string(serverTime))
            .setting(["checklist_context", "identity", "cycle"], .number(Double(cycle)))
            .setting(["checklist_context", "identity", "checklist_execution_id"], .string(execution))["checklist_context"]!
        try contexts.save(try ChecklistContext.decode(envelopeData: try json.serialized()), tenantKey: store.tenantKey)
    }

    func testAFresherContextFromAnOnlineOpenIsNeverOverwritten() throws {
        var a = m("A", "a1"), b = m("B", "b1")
        a.serverTime = "2026-09-24T10:00:00+00:00"
        b.serverTime = "2026-09-24T10:00:00+00:00"
        server.missions = [a, b]
        // A was opened online later that day (a newer server snapshot, same cycle) …
        try savedOnline(a, serverTime: "2026-09-24T15:00:00+00:00", cycle: 1, execution: "ORD-CHK-ONLINE")
        // … B's online copy is older by time but a HIGHER cycle (the server minted a new one).
        try savedOnline(b, serverTime: "2026-09-01T00:00:00+00:00", cycle: 3, execution: "ORD-CHK-CYCLE3")

        reconcile(.launch)

        XCTAssertEqual(context(a)?.executionId, "ORD-CHK-ONLINE", "a later server_time wins")
        XCTAssertEqual(context(b)?.executionId, "ORD-CHK-CYCLE3", "a higher cycle is never replaced by a lower one")
        XCTAssertTrue(makeBridge().isFieldReady(entry(a)), "a kept fresher context satisfies the section")
        XCTAssertTrue(makeBridge().isFieldReady(entry(b)))
    }

    func testANewerPackageRevisionReBridgesAndTheSameRevisionIsANoOp() {
        var a = m("A", "a1")
        server.missions = [a]
        reconcile(.launch)
        let writes = writer.writes

        makeBridge().bridge(index: index)                 // relaunch: bridge again from disk
        XCTAssertEqual(writer.writes, writes, "the same revision is never bridged twice")

        a.revision = F.revision("a2")
        a.executionId = "ORD-CHK-A2"
        a.serverTime = "2026-09-30T10:00:00+00:00"
        server.missions = [a]
        clock = clock.addingTimeInterval(60)
        reconcile()

        XCTAssertEqual(context(a)?.executionId, "ORD-CHK-A2")
        XCTAssertGreaterThan(writer.writes, writes)
    }

    func testASupersededExecutionOrANewerLocalDiscardIsNeverBridged() {
        let a = m("A", "a1")
        server.missions = [a]
        // A substitution recorded on this phone names the package's execution as superseded.
        operations = [SyncOperation(type: EffectiveFieldState.equipmentSubstitutionType, capturedAt: clock, queuedAt: clock,
                                    identity: SyncBusinessIdentity(orderProductUniqueId: a.opuid, checklistExecutionId: "ORD-CHK-A"),
                                    payload: .object(["x": .string("y")]))]

        reconcile(.launch)
        XCTAssertNil(context(a), "the replaced cycle is never written back")

        // A restart recorded after the package was asked for also wins, whatever execution it names.
        let b = m("B", "b1")
        server.missions = [a, b]
        operations = [SyncOperation(type: EffectiveFieldState.deliveryRestartType, capturedAt: clock, queuedAt: clock.addingTimeInterval(600),
                                    identity: SyncBusinessIdentity(orderProductUniqueId: b.opuid), payload: .object(["x": .string("y")]))]
        reconcile()
        XCTAssertNil(context(b))
        XCTAssertFalse(makeBridge().isFieldReady(entry(b)))
        XCTAssertFalse(makeBridge().needsSectionRepair(entry(b)), "waits for the server's new cycle, never re-downloads for it")
    }

    func testTheBridgedEmployeeIsTheSignedInUser() {
        let a = m("A", "a1")
        server.missions = [a]
        employee = ChecklistContext.Employee(userId: 42, uniqueId: "PER-NOW", fullName: "Now Signed In")

        reconcile(.launch)

        XCTAssertEqual(context(a)?.employee, employee, "P4-D5: not whoever downloaded the package")
    }

    // MARK: - Order Details + Assembly Review (§4.3)

    func testOrderDetailsAndAssemblyAreHandedToTheScreensCachesForTheCompany() {
        let a = m("A", "a1")
        server.missions = [a]

        reconcile(.launch)

        let details = writer.orderDetails("ORD-A", tenant: store.tenantKey)
        XCTAssertEqual(details?["unique_id"]?.stringValue, "ORD-A")
        XCTAssertNotNil(details?["order_products"]?.arrayValue, "the whole POST orders/details `order`")
        let assembly = writer.assembly("ORD-A", tenant: store.tenantKey)
        XCTAssertNotNil(assembly?["data"]?["assemblies"])
        XCTAssertNotNil(assembly?["meta"]?["employee"])
        XCTAssertEqual(writer.everything(tenant: "not-a-tenant"), 0)
    }

    func testAFresherLiveOrderDetailsWriteIsNotOverwrittenByAnOlderPackage() {
        let a = m("A", "a1")
        server.missions = [a]
        // Order Details was opened online AFTER this package's request time.
        XCTAssertTrue(store.saveLiveCopy(.orderDetails, orderUniqueId: "ORD-A", askedAt: clock.addingTimeInterval(3600)) { true })

        reconcile(.launch)

        XCTAssertNil(writer.orderDetails("ORD-A", tenant: store.tenantKey), "the fresher live copy stays")
        XCTAssertNotNil(writer.checklistOrder("ORD-A", tenant: store.tenantKey),
                        "a live Order Details open never stops the checklist screens' copy from being written")
        XCTAssertTrue(makeBridge().isFieldReady(entry(a)), "and it satisfies the section")
    }

    func testOrderDetailsIsSatisfiedOnlyWhenBothScreensCachesHoldIt() {
        let a = m("A", "a1")
        server.missions = [a]
        writer.failing = [.checklistOrder]

        reconcile(.launch)
        XCTAssertNotNil(writer.orderDetails("ORD-A", tenant: store.tenantKey))
        XCTAssertFalse(makeBridge().isFieldReady(entry(a)), "the checklist screens have no order yet")
        XCTAssertEqual(store.loadFieldLedger().missions[a.key]?.orderDetails, .pending)

        writer.failing = []
        makeBridge().bridge(index: index) // relaunch: re-bridged from disk, no download
        XCTAssertNotNil(writer.checklistOrder("ORD-A", tenant: store.tenantKey))
        XCTAssertTrue(makeBridge().isFieldReady(entry(a)))
    }

    func testALiveCopyAskedBeforeANewerBridgedPackageIsNotSaved() {
        let a = m("A", "a1")
        server.missions = [a]
        reconcile(.launch) // the package was asked at `clock`

        var saved = 0
        // The screen's request went out an hour BEFORE the package's: its answer is older.
        let older = store.saveLiveCopy(.orderDetails, orderUniqueId: "ORD-A", askedAt: clock.addingTimeInterval(-3600)) { saved += 1; return true }
        let olderAssembly = store.saveLiveCopy(.assembly, orderUniqueId: "ORD-A", askedAt: clock.addingTimeInterval(-3600)) { saved += 1; return true }

        XCTAssertFalse(older)
        XCTAssertFalse(olderAssembly)
        XCTAssertEqual(saved, 0, "an older live answer never replaces the newer bridged copy")

        let newer = store.saveLiveCopy(.assembly, orderUniqueId: "ORD-A", askedAt: clock.addingTimeInterval(60)) { saved += 1; return true }
        XCTAssertTrue(newer)
        XCTAssertEqual(saved, 1)
        XCTAssertEqual(store.loadFieldLedger().observed(.assembly, "ORD-A"), clock.addingTimeInterval(60))
    }

    func testALiveSaveThatFailsRecordsNothing() {
        XCTAssertFalse(store.saveLiveCopy(.orderDetails, orderUniqueId: "ORD-A", askedAt: clock) { false })
        XCTAssertNil(store.loadFieldLedger().observed(.orderDetails, "ORD-A"),
                     "a copy that was not written must not stop the bridge from writing one")
    }

    func testALiveSaveAndABridgeNeverInterleave() {
        // The bridge writes inside the ledger lock; a live save waits for it (and vice versa), so the
        // newer copy is always the one left on disk.
        let a = m("A", "a1")
        server.missions = [a]
        let started = expectation(description: "live save running")
        let release = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            self.store.saveLiveCopy(.orderDetails, orderUniqueId: "ORD-A", askedAt: self.clock.addingTimeInterval(3600)) {
                started.fulfill()
                release.wait()
                return true
            }
        }
        wait(for: [started], timeout: 5)
        let bridged = expectation(description: "bridge finished")
        reconciler.request(.launch) { _ in bridged.fulfill() }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertNil(writer.orderDetails("ORD-A", tenant: store.tenantKey), "the bridge waits for the live save")
        release.signal()
        wait(for: [bridged], timeout: 5)
        XCTAssertNil(writer.orderDetails("ORD-A", tenant: store.tenantKey), "and then keeps the fresher live copy")
    }

    func testAReturnMissionNeedsNoAssembly() {
        let r = m("R", "r1", leg: .return)
        server.missions = [r]

        reconcile(.launch)

        XCTAssertNotNil(writer.orderDetails("ORD-R", tenant: store.tenantKey))
        XCTAssertNil(writer.assembly("ORD-R", tenant: store.tenantKey))
        XCTAssertTrue(makeBridge().isFieldReady(entry(r)), "Return readiness = base + order_details + checklist_context")
    }

    // MARK: - Amendment A: incomplete sections stay retryable at the same revision

    private func assertRepairsAtTheSameRevision(_ mission: M, section: String, file: StaticString = #filePath, line: UInt = #line) {
        server.missions = [mission]
        server.packageOverrides[mission.key] = failed(section, mission)

        let first = reconcile(.launch)
        XCTAssertEqual(first.status, .completed, "a failed SECTION never makes the Dispatch run partial", file: file, line: line)
        XCTAssertEqual(first.incompleteMissionKeys, [mission.key], file: file, line: line)
        XCTAssertFalse(makeBridge().isFieldReady(entry(mission)), file: file, line: line)
        XCTAssertTrue(makeBridge().needsSectionRepair(entry(mission)), file: file, line: line)
        let requestsBefore = server.packageRequests.count

        server.packageOverrides = [:]                         // the server builds it this time
        clock = clock.addingTimeInterval(30)
        let second = reconcile()

        XCTAssertEqual(server.manifestRequests, 2, file: file, line: line)
        XCTAssertEqual(server.packageRequests.count, requestsBefore + 1, "re-requested with an UNCHANGED manifest revision", file: file, line: line)
        XCTAssertEqual(entry(mission).readyRevision, mission.revision, "the same revision", file: file, line: line)
        XCTAssertTrue(makeBridge().isFieldReady(entry(mission)), file: file, line: line)
        XCTAssertEqual(second.incompleteMissionKeys, [], file: file, line: line)

        let third = reconcile()
        XCTAssertEqual(server.packageRequests.count, requestsBefore + 1, "a complete mission is not downloaded again", file: file, line: line)
        XCTAssertEqual(third.status, .completed, file: file, line: line)
    }

    func testAFailedOrderDetailsSectionRepairsAtTheSameRevision() {
        assertRepairsAtTheSameRevision(m("A", "a1"), section: "order_details")
        XCTAssertNotNil(writer.orderDetails("ORD-A", tenant: store.tenantKey))
    }

    func testAFailedAssemblyRepairsAtTheSameRevision() {
        assertRepairsAtTheSameRevision(m("A", "a1"), section: "assembly")
        XCTAssertNotNil(writer.assembly("ORD-A", tenant: store.tenantKey))
    }

    func testAReturnsFailedOrderDetailsRepairsAtTheSameRevision() {
        assertRepairsAtTheSameRevision(m("R", "r1", leg: .return), section: "order_details")
    }

    func testAPriorValidSectionIsPreservedWhenTheNewRevisionsSectionFails() {
        var a = m("A", "a1")
        server.missions = [a]
        reconcile(.launch)
        let prior = writer.orderDetails("ORD-A", tenant: store.tenantKey)
        XCTAssertNotNil(prior)

        a.revision = F.revision("a2")
        server.missions = [a]
        server.packageOverrides[a.key] = failed("order_details", a)
        clock = clock.addingTimeInterval(60)
        reconcile()

        XCTAssertEqual(writer.orderDetails("ORD-A", tenant: store.tenantKey), prior, "a missing section never overwrites the earlier valid copy")
        XCTAssertFalse(makeBridge().isFieldReady(entry(a)), "but the mission is not marked ready at the new revision")
        XCTAssertTrue(makeBridge().needsSectionRepair(entry(a)))
    }

    func testAnOldServerWithoutSectionsIsNeverRetried() {
        let a = m("A", "a1")
        server.missions = [a]
        server.packageOverrides[a.key] = F.package(a).setting(["sections"], .null).setting(["order_details"], .null).setting(["assembly"], .null)

        reconcile(.launch)
        let requests = server.packageRequests.count
        clock = clock.addingTimeInterval(30)
        reconcile()

        XCTAssertEqual(server.packageRequests.count, requests, "no endless re-downloads against a pre-Phase-4 server")
        XCTAssertFalse(makeBridge().isFieldReady(entry(a)))
        XCTAssertFalse(makeBridge().needsSectionRepair(entry(a)))
        XCTAssertNotNil(context(a), "the canonical checklist context is still bridged")
    }

    func testAWakeForTheAppliedRevisionStillRunsWhileAMissionIsRetryable() {
        let a = m("A", "a1")
        server.missions = [a]
        server.packageOverrides[a.key] = failed("order_details", a)
        reconcile(.launch)
        server.packageOverrides = [:]

        let wake = reconcile(.wake(revision: F.manifestRevision([a])))

        XCTAssertNotEqual(wake.status, .skipped(.alreadyCurrent), "an incomplete mission is repaired by the next wake")
        XCTAssertTrue(makeBridge().isFieldReady(entry(a)))
        XCTAssertEqual(reconcile(.wake(revision: F.manifestRevision([a]))).status, .skipped(.alreadyCurrent), "and then it is current")
    }

    func testAnUndecodableContextIsRetryableAndRepairs() {
        let a = m("A", "a1")
        server.missions = [a]
        server.packageOverrides[a.key] = F.package(a).setting(["checklist_context", "questions"], .string("broken"))
        reconcile(.launch)
        XCTAssertTrue(makeBridge().needsSectionRepair(entry(a)))

        server.packageOverrides = [:]
        clock = clock.addingTimeInterval(30)
        reconcile()

        XCTAssertEqual(context(a)?.executionId, "ORD-CHK-A")
        XCTAssertTrue(makeBridge().isFieldReady(entry(a)))
    }

    func testADeliveryIsNotReadyUntilEverySectionIsPresent() {
        let a = m("A", "a1")
        server.missions = [a]
        server.packageOverrides[a.key] = failed("assembly", a)

        reconcile(.launch)

        XCTAssertNotNil(context(a))
        XCTAssertNotNil(writer.orderDetails("ORD-A", tenant: store.tenantKey))
        XCTAssertFalse(makeBridge().isFieldReady(entry(a)), "Delivery = base + order_details + assembly + checklist_context")
    }

    // MARK: - Amendment B: the tenant boundary

    func testCompanyBNeverSeesCompanyAsBridgedDataAndAKeepsIt() throws {
        let a = m("A", "a1")
        server.missions = [a]
        reconcile(.launch)                                  // Company A: everything bridged
        XCTAssertNotNil(context(a))
        let aKey = store.tenantKey

        // Logout → login to Company B → offline.
        let storeB = try DispatchOfflineMissionStore(rootDirectory: root, baseURL: tenantB)
        signedInTenant = storeB.tenantKey
        let serverB = FakeDispatchServer()
        serverB.setOffline(true)
        let reconcilerB = makeReconciler(storeB, client: serverB)
        reconcile(.loginCompleted, on: reconcilerB)

        XCTAssertNil(contexts.load(orderProductUniqueId: a.opuid, leg: .delivery), "no A checklist context under B")
        XCTAssertEqual(contexts.all(), [])
        XCTAssertEqual(writer.everything(tenant: storeB.tenantKey), 0, "no A Order Details / assembly written under B")
        XCTAssertEqual(DispatchOfflineWorkingSet.present(store: storeB, query: DispatchOfflineQuery(dates: .all), operations: [], today: "2026-09-22"),
                       .notDownloaded, "no A Dispatch under B")
        XCTAssertEqual(storeB.loadFieldLedger(), DispatchOfflineFieldLedger(), "B's ledger is its own")

        // Back to Company A (still offline): all of A's data is usable.
        signedInTenant = aKey
        XCTAssertEqual(contexts.load(orderProductUniqueId: a.opuid, leg: .delivery)?.executionId, "ORD-CHK-A")
        XCTAssertNotNil(writer.orderDetails("ORD-A", tenant: aKey))
        XCTAssertTrue(makeBridge().isFieldReady(entry(a)))
    }

    func testTheBridgeNeverWritesForAnotherCompanysSession() {
        let a = m("A", "a1")
        server.missions = [a]
        let gate = DispatchSemaphore(value: 0)
        server.holdNextPackages = gate
        let done = expectation(description: "run")
        reconciler.request(.launch) { _ in done.fulfill() }
        waitUntil { self.server.packageRequests.count == 1 }
        signedInTenant = "cccccccccccccccc"                // switched company mid-run
        gate.signal()
        wait(for: [done], timeout: 5)

        XCTAssertNil(context(a))
        XCTAssertEqual(writer.writes, 0, "an aborted run bridges nothing")
    }

    // MARK: - Removal never deletes bridged caches (test 16)

    func testRemovalNeverDeletesBridgedContexts() {
        let a = m("A", "a1"), b = m("B", "b1")
        server.missions = [a, b]
        reconcile(.launch)
        XCTAssertNotNil(context(b))

        server.missions = [a]                                // B leaves the working set
        reconcile()
        clock = clock.addingTimeInterval(30 * 86_400)
        reconcile()                                          // well past the grace period

        XCTAssertNil(index.entry(b.key))
        XCTAssertNotNil(context(b), "unsynced field work can still open it")
        XCTAssertNotNil(writer.orderDetails("ORD-B", tenant: store.tenantKey))
    }

    // MARK: - The key physical scenario, automated (§7.1)

    private struct ChecklistTestHandler: SyncOperationHandler {
        let operationType: String
        func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
            try ChecklistRequestFactory.prepareRequest(for: operation)
        }
    }

    private func offlineEngine(_ dir: URL) throws -> SyncEngine {
        SyncEngine(store: try FileSyncOperationStore(rootDirectory: dir), httpClient: FakeSyncHTTPClient(),
                   handlers: [ChecklistTestHandler(operationType: ChecklistOperationBuilder.prepareType(.delivery)),
                              ChecklistTestHandler(operationType: ChecklistOperationBuilder.prepareType(.return))],
                   policy: SyncRetryPolicy(backoffSchedule: [600]))
    }

    private func runTheNeverOpenedMissionOffline(_ mission: M) throws {
        server.missions = [mission]

        // 1. Online: the phone reconciles and bridges. Nobody opens the mission.
        reconcile(.launch)
        let requestsOnline = server.requestCount

        // 2. The network disappears.
        server.setOffline(true)

        // 3. Cached Dispatch → Driver Checklist (the row + the durable stage overlay).
        guard case .ready(let rows, _) = DispatchOfflineWorkingSet.present(store: store, query: DispatchOfflineQuery(dates: .all),
                                                                         operations: [], today: "2026-09-22"),
              let row = rows.first(where: { $0.orderProductUniqueId == mission.opuid }) else { return XCTFail("cached card") }
        XCTAssertEqual(DriverStageOverlay.from([]).effective(orderProductUniqueId: row.orderProductUniqueId,
                                                             leg: mission.leg == .delivery ? "delivery" : "pickup",
                                                             server: DriverStageServerState(readyToGoAt: nil, arrivedAt: nil, isArrived: false),
                                                             serverObservedAt: row.serverObservedAt).stage, .notStarted)

        // 4. Order Details: the canonical payload is in the screen's cache, with this mission's line.
        let details = try XCTUnwrap(writer.orderDetails(mission.orderUid!, tenant: store.tenantKey))
        XCTAssertFalse((details["order_products"]?.arrayValue ?? []).isEmpty)
        if mission.leg == .delivery {
            XCTAssertNotNil(writer.assembly(mission.orderUid!, tenant: store.tenantKey), "Delivery goes through Assembly Review")
        }

        // 5. Equipment checklist: the canonical context — questions, unit, cycle — may be served offline.
        let ctx = try XCTUnwrap(contexts.load(orderProductUniqueId: mission.opuid, leg: mission.leg))
        XCTAssertEqual(ctx.executionId, mission.executionId)
        XCTAssertEqual(ctx.identity.cycle, 1)
        XCTAssertEqual(ctx.equipment.equipmentUniqueId, F.package(mission)["checklist_context"]?["equipment"]?["equipment_unique_id"]?.stringValue)
        XCTAssertEqual(ctx.questions.map(\.questionId), F.package(mission)["checklist_context"]?["questions"]?.arrayValue?.compactMap { $0["question_id"]?.stringValue })
        XCTAssertTrue(ChecklistContextFallbackPolicy.canServeOffline(ctx, equipmentHint: ctx.equipment.equipmentUniqueId, strictUnit: false, operations: []))

        // 6. Answers are saved locally (durable, before anything syncs).
        let engineDir = root.appendingPathComponent("engine", isDirectory: true)
        var engine: SyncEngine? = try offlineEngine(engineDir)
        let question = try XCTUnwrap(ctx.questions.first)
        let capture = ChecklistCapture(context: ctx, answers: [question.questionId: question.answers[0].answerId],
                                       employeeUserId: 2, equipmentUniqueId: ctx.equipment.equipmentUniqueId)
        let prepare = try ChecklistOperationBuilder.enqueuePrepare(capture, into: engine!)
        XCTAssertEqual(prepare.payload["checklist_execution_id"]?.stringValue, mission.executionId)
        XCTAssertEqual(prepare.payload["context_revision"]?.stringValue, ctx.template.revision)

        // 7. Force-quit and relaunch, still offline: everything is still there, and nothing is re-bridged.
        engine = nil
        let writes = writer.writes
        let relaunchedStore = try DispatchOfflineMissionStore(rootDirectory: root, baseURL: tenantA)
        let relaunchedContexts = try ChecklistContextStore(rootDirectory: root, tenantKey: { [unowned self] in self.signedInTenant })
        DispatchOfflineFieldBridge(store: relaunchedStore, contexts: relaunchedContexts, writer: writer,
                                   operations: { [] }, currentEmployee: { nil }).bridge(index: relaunchedStore.loadIndex())
        XCTAssertEqual(writer.writes, writes, "an interrupted or repeated bridge is a no-op")
        XCTAssertEqual(relaunchedContexts.load(orderProductUniqueId: mission.opuid, leg: mission.leg)?.executionId, mission.executionId)
        let relaunchedEngine = try offlineEngine(engineDir)
        XCTAssertEqual(relaunchedEngine.snapshot().map(\.id), [prepare.id], "the saved answers survive the relaunch")
        XCTAssertEqual(server.requestCount, requestsOnline, "nothing after going offline needed the network")
    }

    func testANeverOpenedDeliveryWorksFullyOfflineThroughRelaunch() throws {
        try runTheNeverOpenedMissionOffline(m("D", "d1"))
    }

    func testANeverOpenedReturnWorksFullyOfflineThroughRelaunch() throws {
        try runTheNeverOpenedMissionOffline(m("R", "r1", leg: .return))
    }

    // MARK: - Substitution: an old unit's context never satisfies the replacement

    func testAServerSideSubstitutionBridgesTheNewUnitsContext() {
        var a = m("A", "a1")
        a.unit = "EQP-OLD"
        server.missions = [a]
        reconcile(.launch)
        XCTAssertEqual(context(a)?.equipment.equipmentUniqueId, "EQP-OLD")

        // The office swaps the unit: the server supersedes the cycle → new revision, unit and execution.
        a.revision = F.revision("a2")
        a.unit = "EQP-NEW"
        a.executionId = "ORD-CHK-A-C2"
        a.cycle = 2
        a.serverTime = "2026-09-30T09:00:00+00:00"
        server.missions = [a]
        clock = clock.addingTimeInterval(60)
        reconcile()

        XCTAssertEqual(context(a)?.equipment.equipmentUniqueId, "EQP-NEW")
        XCTAssertEqual(context(a)?.executionId, "ORD-CHK-A-C2")
        XCTAssertEqual(context(a)?.identity.cycle, 2)
    }

    func testAnOfflineSubstitutionNeverLetsTheOldUnitsContextSatisfyTheReplacement() throws {
        var a = m("A", "a1")
        a.unit = "EQP-OLD"
        server.missions = [a]
        reconcile(.launch)
        server.setOffline(true)
        let old = try XCTUnwrap(context(a))

        // Offline, the employee substitutes EQP-NEW (durable, local-first).
        operations = [SyncOperation(type: EffectiveFieldState.equipmentSubstitutionType, capturedAt: clock, queuedAt: clock.addingTimeInterval(120),
                                    identity: SyncBusinessIdentity(orderProductUniqueId: a.opuid, equipmentUniqueId: "EQP-NEW",
                                                                   checklistExecutionId: old.executionId),
                                    payload: .object(["x": .string("y")]))]

        XCTAssertFalse(ChecklistContextFallbackPolicy.canServeOffline(old, equipmentHint: "EQP-NEW", strictUnit: true, operations: operations),
                       "the replacement never gets the old unit's questions, unit or execution")
        makeBridge().bridge(index: index)
        XCTAssertFalse(makeBridge().isFieldReady(entry(a)), "the replacement's checklist needs a connection (P4-D4)")
        XCTAssertFalse(makeBridge().needsSectionRepair(entry(a)))
    }

    // MARK: - Helpers

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), "condition not reached")
    }
}
