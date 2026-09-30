//
//  DispatchOfflineReconcilerTests.swift
//  Dispatch offline Phase 3 — the ONE reconciliation coordinator: selective
//  download by revision, per-mission atomic apply, failure retention, and the
//  coalescing / trigger policy every wake and repair path goes through.
//

import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class DispatchOfflineReconcilerTests: XCTestCase {

    private typealias F = DispatchOfflineFixtures
    private typealias M = DispatchOfflineFixtures.Mission

    private var root: URL!
    private var server: FakeDispatchServer!
    private var store: DispatchOfflineMissionStore!
    private var session = true
    private var clock = Date(timeIntervalSince1970: 1_790_000_000)
    private var engineStore: FileSyncOperationStore!

    override func setUp() {
        super.setUp()
        root = Fixtures.tempDirectory(name)
        server = FakeDispatchServer()
        store = try! DispatchOfflineMissionStore(rootDirectory: root, baseURL: URL(string: "https://api.kabba.ai/api/admin/v1/")!)
        engineStore = try! FileSyncOperationStore(rootDirectory: root)
        session = true
    }

    private func makeReconciler() -> DispatchOfflineReconciler {
        DispatchOfflineReconciler(
            httpClient: server, store: store,
            session: { [unowned self] in self.session ? .of(self.store) : nil },
            retainedOrderProducts: { [unowned self] in
                Set(((try? self.engineStore.loadAll()) ?? []).compactMap { $0.identity.orderProductUniqueId })
            },
            now: { [unowned self] in self.clock }
        )
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

    private func m(_ id: String, _ rev: String, leg: ChecklistLeg = .delivery, driver: Int? = 4) -> M {
        M(opuid: "ORD-SCH-\(id)", leg: leg, revision: F.revision(rev), deliveryDriverId: driver)
    }

    private var index: DispatchOfflineIndex { store.loadIndex() }
    private func ready(_ key: String) -> String? { index.entry(key)?.readyRevision }
    private var indexBytes: Data? { try? Data(contentsOf: store.indexURL) }

    // MARK: - Selective download (tests 1–5)

    func testEmptyStorePopulatedManifestStoresEveryPackage() {
        let missions = [m("A", "a1"), m("B", "b1", leg: .return), m("C", "c1", driver: 7)]
        server.missions = missions

        let result = reconcile()

        XCTAssertEqual(result.status, .completed)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(server.manifestRequests, 1)
        XCTAssertEqual(server.packageRequests.count, 1)
        XCTAssertEqual(Set(server.requestedKeys), Set(missions.map(\.key)))
        XCTAssertEqual(result.downloaded, 3)
        for mission in missions {
            XCTAssertEqual(ready(mission.key), mission.revision)
            XCTAssertNotNil(store.readyPackage(for: index.entry(mission.key)!))
        }
        XCTAssertTrue(index.everCommitted)
        XCTAssertEqual(index.throughDate, "2026-09-24")
    }

    func testIdenticalManifestDownloadsNothing() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        reconcile()
        let before = indexBytesWithoutTimestamps()

        let second = reconcile()

        XCTAssertEqual(second.status, .completed)
        XCTAssertFalse(second.changed)
        XCTAssertEqual(second.backgroundResult, .noData)
        XCTAssertEqual(server.manifestRequests, 2)
        XCTAssertEqual(server.packageRequests.count, 1, "no package is downloaded again")
        XCTAssertEqual(indexBytesWithoutTimestamps(), before)
    }

    func testOneChangedRevisionDownloadsExactlyThatMission() {
        server.missions = [m("A", "a1"), m("B", "b1"), m("C", "c1")]
        reconcile()
        server.missions = [m("A", "a1"), m("B", "b2"), m("C", "c1")]

        let result = reconcile()

        XCTAssertEqual(server.requestedKeys.suffix(1), ["ORD-SCH-B:delivery"])
        XCTAssertEqual(server.packageRequests.count, 2)
        XCTAssertEqual(result.downloaded, 1)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(ready("ORD-SCH-B:delivery"), F.revision("b2"))
    }

    func testNewMissionIsAdded() {
        server.missions = [m("A", "a1")]
        reconcile()
        server.missions = [m("A", "a1"), m("D", "d1")]

        let result = reconcile()

        XCTAssertEqual(server.requestedKeys.suffix(1), ["ORD-SCH-D:delivery"])
        XCTAssertEqual(ready("ORD-SCH-D:delivery"), F.revision("d1"))
        XCTAssertTrue(result.changed)
    }

    func testAbsentMissionLeavesTheActiveIndex() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        reconcile()
        server.missions = [m("A", "a1")]

        let result = reconcile()

        XCTAssertNil(index.entry("ORD-SCH-B:delivery"))
        XCTAssertEqual(result.removed, 1)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(server.packageRequests.count, 1, "removal needs no download")
    }

    // MARK: - Field work is never touched (test 6)

    func testRemovalNeverTouchesSyncEngineWorkOrChecklistContexts() throws {
        server.missions = [m("A", "a1"), m("B", "b1")]
        reconcile()
        let fileB = index.entry("ORD-SCH-B:delivery")!.packageFile!

        let contexts = try ChecklistContextStore(rootDirectory: root, tenantKey: { "aaaaaaaaaaaaaaaa" })
        try contexts.save(try ChecklistContext.decode(envelopeData: F.data("delivery_checklist_context")))
        for state in [SyncState.pending, .needsAttention, .synced] {
            var op = SyncOperation(type: "delivery_checklist.complete", capturedAt: clock,
                                   identity: SyncBusinessIdentity(orderProductUniqueId: "ORD-SCH-B"),
                                   payload: .object(["state": .string(state.rawValue)]))
            op.state = state
            try engineStore.save(op)
        }
        try Data("signature".utf8).write(to: engineStore.assetsDirectory.appendingPathComponent("sig-B.png"))
        let fieldWork = try snapshot(excluding: "dispatch-offline")

        server.missions = [m("A", "a1")] // B completed / cancelled / rescheduled out
        reconcile()
        clock = clock.addingTimeInterval(30 * 86_400)
        reconcile() // well past the grace period

        XCTAssertNil(index.entry("ORD-SCH-B:delivery"), "B leaves the active Dispatch set")
        XCTAssertEqual(try snapshot(excluding: "dispatch-offline"), fieldWork, "operations, assets and contexts are byte-identical")
        XCTAssertNotNil(store.loadPackage(file: fileB), "B's package is retained while Sync Engine work references it")
    }

    // MARK: - Failures keep the last valid data (tests 8, 9, 15)

    func testOneBadPackageDoesNotBlockTheOthers() {
        server.missions = [m("A", "a1"), m("B", "b1"), m("C", "c1")]
        reconcile()
        server.missions = [m("A", "a2"), m("B", "b2"), m("C", "c2")]
        server.packageOverrides["ORD-SCH-B:delivery"] = F.package(m("B", "b2")).setting(["dispatch", "row"], .null)

        let result = reconcile()

        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.failedMissionKeys, ["ORD-SCH-B:delivery"])
        XCTAssertTrue(result.changed)
        XCTAssertEqual(ready("ORD-SCH-A:delivery"), F.revision("a2"))
        XCTAssertEqual(ready("ORD-SCH-C:delivery"), F.revision("c2"))
        XCTAssertEqual(ready("ORD-SCH-B:delivery"), F.revision("b1"), "B keeps its previous valid package")
        XCTAssertTrue(index.entry("ORD-SCH-B:delivery")!.isStale)
    }

    func testFailedReplacementKeepsPriorPackage() {
        server.missions = [m("A", "a1")]
        reconcile()
        server.missions = [m("A", "a2")]
        server.goOfflineAfterManifests = 2 // the network drops right after the second manifest

        let result = reconcile()

        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.packageFailure, .offline)
        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.backgroundResult, .failed)
        let entry = index.entry("ORD-SCH-A:delivery")!
        XCTAssertEqual(entry.readyRevision, F.revision("a1"), "the new revision is not marked ready")
        XCTAssertEqual(entry.serverRevision, F.revision("a2"))
        XCTAssertNotNil(store.readyPackage(for: entry), "the previous package is still presentable")
    }

    func testAPackagesResponseThatCannotBeDecodedKeepsPriorPackages() {
        server.missions = [m("A", "a1")]
        reconcile()
        server.missions = [m("A", "a2")]
        server.packagesBodyOverride = Data("<html>gateway</html>".utf8)

        let result = reconcile()

        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.failedMissionKeys, ["ORD-SCH-A:delivery"])
        XCTAssertEqual(ready("ORD-SCH-A:delivery"), F.revision("a1"))
    }

    func testManifestFailuresLeaveTheStoreByteIdentical() {
        server.missions = [m("A", "a1")]
        reconcile()
        let before = indexBytes

        server.offline = true
        XCTAssertEqual(reconcile().status, .failed(.offline))
        server.offline = false
        server.manifestStatus = 503
        XCTAssertEqual(reconcile().status, .failed(.server(503)))
        server.manifestStatus = 200
        server.manifestBodyOverride = Data("{\"success\":true,\"data\":{\"revision\":\"x\"}}".utf8)
        XCTAssertEqual(reconcile().status, .failed(.invalidManifest))

        XCTAssertEqual(indexBytes, before)
        XCTAssertEqual(server.packageRequests.count, 1)
    }

    func testUnauthorizedLeavesStoreByteIdentical() {
        server.missions = [m("A", "a1")]
        reconcile()
        let before = indexBytes

        server.manifestStatus = 401
        let result = reconcile()

        XCTAssertEqual(result.status, .failed(.unauthenticated))
        XCTAssertEqual(result.backgroundResult, .failed)
        XCTAssertEqual(indexBytes, before, "a 401 never clears Dispatch data")
        XCTAssertNotNil(store.readyPackage(for: index.entry("ORD-SCH-A:delivery")!))
    }

    func testUnauthorizedOnPackagesKeepsPriorPackages() {
        server.missions = [m("A", "a1")]
        reconcile()
        server.missions = [m("A", "a2")]
        server.packagesStatus = 401

        let result = reconcile()

        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.packageFailure, .unauthenticated)
        XCTAssertEqual(ready("ORD-SCH-A:delivery"), F.revision("a1"))
    }

    func testUpdateRequiredIsReportedAndChangesNothing() {
        server.missions = [m("A", "a1")]
        reconcile()
        let before = indexBytes
        server.manifestStatus = 426

        XCTAssertEqual(reconcile().status, .failed(.updateRequired))
        XCTAssertEqual(indexBytes, before)
    }

    func testAStorageFailureReportsAndKeepsThePreviousIndex() {
        server.missions = [m("A", "a1")]
        reconcile()
        let before = indexBytes
        server.missions = [m("A", "a1"), m("B", "b1")]
        store.failNextIndexCommit = true

        XCTAssertEqual(reconcile().status, .failed(.storage))
        XCTAssertEqual(indexBytes, before)
    }

    // MARK: - Interruption, races, edge manifests

    func testNetworkLostAfterManifestAppliesRemovalsAndRepairsNextRun() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        reconcile()
        server.missions = [m("B", "b2"), m("C", "c1")]
        server.goOfflineAfterManifests = 2

        let partial = reconcile()

        XCTAssertEqual(partial.status, .partial)
        XCTAssertNil(index.entry("ORD-SCH-A:delivery"), "the manifest is the complete truth: A is removed")
        XCTAssertEqual(ready("ORD-SCH-B:delivery"), F.revision("b1"), "B stays presentable, stale")
        XCTAssertNil(ready("ORD-SCH-C:delivery"), "C is known but not downloaded yet")
        XCTAssertTrue(partial.changed)

        server.goOfflineAfterManifests = nil
        server.setOffline(false)
        let repaired = reconcile(.networkRestored)

        XCTAssertEqual(repaired.status, .completed)
        XCTAssertEqual(ready("ORD-SCH-B:delivery"), F.revision("b2"))
        XCTAssertEqual(ready("ORD-SCH-C:delivery"), F.revision("c1"))
        XCTAssertTrue(index.isFullyCurrent)
    }

    func testNotActiveMissionsAreRemoved() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        reconcile()
        server.missions = [m("A", "a1"), m("B", "b2")]
        server.notActive = ["ORD-SCH-B:delivery"] // became inactive between the manifest and the package request

        let result = reconcile()

        XCTAssertNil(index.entry("ORD-SCH-B:delivery"))
        XCTAssertEqual(result.status, .completed)
    }

    func testAPackageNewerThanTheManifestConverges() {
        server.missions = [m("A", "a1")]
        server.packageOverrides["ORD-SCH-A:delivery"] = F.package(m("A", "a2")) // changed again after the manifest was built

        reconcile()
        XCTAssertEqual(ready("ORD-SCH-A:delivery"), F.revision("a2"))
        XCTAssertTrue(index.isFullyCurrent, "the newer package is the newest known truth")

        server.packageOverrides = [:]
        server.missions = [m("A", "a2")]
        reconcile()
        XCTAssertEqual(server.packageRequests.count, 1, "the next manifest reports that revision — nothing to download")
    }

    func testAnInterruptedRunIsAdoptedFromDiskWithoutDownloading() throws {
        let a = m("A", "a1")
        server.missions = [a]
        // A previous run wrote the package, then iOS killed the app before the index commit.
        let package = try DispatchOfflinePackagesResponse.decode(envelope: F.packagesBody([F.package(a)]), requested: [a.key]).packages[0]
        try store.writePackage(package, cachedAt: clock)

        let result = reconcile()

        XCTAssertEqual(server.packageRequests.count, 0)
        XCTAssertEqual(result.adopted, 1)
        XCTAssertEqual(ready(a.key), a.revision)
    }

    func testAnEmptyManifestClearsTheActiveSet() {
        server.missions = [m("A", "a1")]
        reconcile()
        server.missions = []

        let result = reconcile()

        XCTAssertEqual(index.entries, [])
        XCTAssertTrue(index.everCommitted, "an empty Dispatch is a real, downloaded state")
        XCTAssertTrue(result.changed)
    }

    func testAPreviousDaysCacheReconcilesNormally() {
        server.missions = [m("A", "a1")]
        reconcile()
        XCTAssertEqual(index.throughDate, "2026-09-24")
        clock = clock.addingTimeInterval(86_400)
        server.manifestBodyOverride = F.manifestBody([m("A", "a1"), m("E", "e1")], throughDate: "2026-09-25")
        server.missions = [m("A", "a1"), m("E", "e1")]

        reconcile(.launch)

        XCTAssertEqual(index.throughDate, "2026-09-25")
        XCTAssertEqual(ready("ORD-SCH-E:delivery"), F.revision("e1"))
    }

    func testAFreshInstallationStartsNotDownloadedEvenWhenOffline() {
        server.offline = true
        reconcile(.launch)
        XCTAssertFalse(index.everCommitted)
    }

    // MARK: - Coalescing (test 11)

    func testConcurrentTriggersCoalesceIntoOneRun() {
        server.missions = [m("A", "a1")]
        let gate = DispatchSemaphore(value: 0)
        server.holdNextManifest = gate

        let first = expectation(description: "foreground")
        let second = expectation(description: "wake")
        var results: [DispatchOfflineReconcileResult] = []
        let lock = NSLock()
        reconciler.request(.foreground) { r in lock.withLock { results.append(r) }; first.fulfill() }
        waitUntil { self.server.manifestRequests == 1 }
        reconciler.request(.wake(revision: F.manifestRevision([m("A", "a1")]))) { r in lock.withLock { results.append(r) }; second.fulfill() }
        reconciler.request(.dispatchScreenOpened) { r in lock.withLock { results.append(r) } }
        gate.signal()
        wait(for: [first, second], timeout: 5)
        waitUntil { lock.withLock { results.count } == 3 }

        XCTAssertEqual(server.manifestRequests, 1, "one reconciliation, not three")
        XCTAssertEqual(server.packageRequests.count, 1)
        XCTAssertTrue(results.allSatisfy { $0.status == .completed })
    }

    func testAWakeForANewerRevisionMidRunCausesExactlyOneFollowUp() {
        server.missions = [m("A", "a1")]
        let gate = DispatchSemaphore(value: 0)
        server.holdNextManifest = gate
        let done = expectation(description: "all")
        done.expectedFulfillmentCount = 4

        reconciler.request(.launch) { _ in done.fulfill() }
        waitUntil { self.server.manifestRequests == 1 }
        server.setMissions([m("A", "a2")]) // the office edits again; Laravel wakes the phone
        reconciler.request(.wake(revision: F.manifestRevision([m("A", "a2")]))) { _ in done.fulfill() }
        reconciler.request(.wake(revision: "")) { _ in done.fulfill() }
        reconciler.request(.foreground) { _ in done.fulfill() }
        gate.signal()
        wait(for: [done], timeout: 5)

        XCTAssertEqual(server.manifestRequests, 2, "exactly one follow-up for the coalesced wakes")
        XCTAssertEqual(ready("ORD-SCH-A:delivery"), F.revision("a2"))
    }

    func testATriggerDuringAFailedRunGetsOneFollowUp() {
        server.missions = [m("A", "a1")]
        server.offline = true
        let gate = DispatchSemaphore(value: 0)
        server.holdNextManifest = gate
        let done = expectation(description: "both")
        done.expectedFulfillmentCount = 2
        var last: DispatchOfflineReconcileResult?

        reconciler.request(.launch) { _ in done.fulfill() }
        waitUntil { self.server.manifestRequests == 1 }
        reconciler.request(.networkRestored) { last = $0; done.fulfill() }
        server.setOffline(false) // connectivity came back while the first attempt was failing
        gate.signal()             // …the first attempt still answers "offline"
        wait(for: [done], timeout: 5)

        XCTAssertEqual(server.manifestRequests, 2)
        XCTAssertEqual(last?.status, .completed)
    }

    // MARK: - Trigger policy (D6, 16)

    func testNoSessionMakesNoRequestAndCompletesAsNoData() {
        server.missions = [m("A", "a1")]
        reconcile()
        let before = indexBytes
        session = false

        let result = reconcile(.wake(revision: F.revision("anything")))

        XCTAssertEqual(result.status, .skipped(.noSession))
        XCTAssertEqual(result.backgroundResult, .noData)
        XCTAssertEqual(server.requestCount, 2, "no request without a session")
        XCTAssertEqual(indexBytes, before, "the cache is preserved")
    }

    func testAWakeForTheAppliedRevisionMakesNoRequest() {
        let missions = [m("A", "a1")]
        server.missions = missions
        reconcile()

        let result = reconcile(.wake(revision: F.manifestRevision(missions)))

        XCTAssertEqual(result.status, .skipped(.alreadyCurrent))
        XCTAssertEqual(result.backgroundResult, .noData)
        XCTAssertEqual(server.manifestRequests, 1)
    }

    func testTheFreshnessWindowAbsorbsForegroundButNotManualRefresh() {
        server.missions = [m("A", "a1")]
        reconcile()
        clock = clock.addingTimeInterval(5)

        XCTAssertEqual(reconcile(.foreground).status, .skipped(.fresh))
        XCTAssertEqual(reconcile(.dispatchScreenOpened).status, .skipped(.fresh))
        XCTAssertEqual(server.manifestRequests, 1)
        XCTAssertEqual(reconcile(.manualRefresh).status, .completed)
        XCTAssertEqual(server.manifestRequests, 2)

        clock = clock.addingTimeInterval(DispatchOfflineReconciler.freshnessWindow + 1)
        XCTAssertEqual(reconcile(.foreground).status, .completed)
    }

    func testTheFailureCooldownDoublesAndRepairTriggersBypassIt() {
        server.offline = true
        XCTAssertEqual(reconcile(.launch).status, .failed(.offline))            // failure #1 at t
        clock = clock.addingTimeInterval(10)
        XCTAssertEqual(reconcile(.foreground).status, .skipped(.coolingDown))   // inside 30 s
        clock = clock.addingTimeInterval(21)
        XCTAssertEqual(reconcile(.foreground).status, .failed(.offline))        // t+31: runs, failure #2
        clock = clock.addingTimeInterval(50)
        XCTAssertEqual(reconcile(.dispatchScreenOpened).status, .skipped(.coolingDown)) // inside 60 s
        XCTAssertEqual(server.manifestRequests, 2)

        for trigger: DispatchOfflineTrigger in [.networkRestored, .manualRefresh, .loginCompleted, .wake(revision: nil)] {
            XCTAssertEqual(reconcile(trigger).status, .failed(.offline), "\(trigger) bypasses the cooldown")
        }
        XCTAssertEqual(server.manifestRequests, 6)
        XCTAssertEqual(DispatchOfflineReconciler.cooldown(afterFailures: 1), 30)
        XCTAssertEqual(DispatchOfflineReconciler.cooldown(afterFailures: 2), 60)
        XCTAssertEqual(DispatchOfflineReconciler.cooldown(afterFailures: 5), 300)
        XCTAssertEqual(DispatchOfflineReconciler.cooldown(afterFailures: 12), 300)
    }

    func testNetworkRestoredRunsImmediatelyAfterOffline() {
        server.missions = [m("A", "a1")]
        server.offline = true
        XCTAssertEqual(reconcile(.foreground).status, .failed(.offline))
        server.offline = false

        let result = reconcile(.networkRestored)

        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(ready("ORD-SCH-A:delivery"), F.revision("a1"))
    }

    func testLoginCompletedRepairsAfterUnauthorized() {
        server.missions = [m("A", "a1")]
        reconcile()
        server.missions = [m("A", "a2")]
        server.manifestStatus = 401
        XCTAssertEqual(reconcile(.wake(revision: nil)).status, .failed(.unauthenticated))

        // The employee signs back in.
        server.manifestStatus = 200
        let result = reconcile(.loginCompleted)

        XCTAssertEqual(result.status, .completed)
        XCTAssertEqual(ready("ORD-SCH-A:delivery"), F.revision("a2"))
    }

    // MARK: - Session binding (review I-1)

    private func twoTenants() -> (a: DispatchOfflineMissionStore, b: DispatchOfflineMissionStore,
                                  serverA: FakeDispatchServer, serverB: FakeDispatchServer, client: TenantRoutingClient) {
        let a = try! DispatchOfflineMissionStore(rootDirectory: root, baseURL: URL(string: "https://api.kabba.ai/api/admin/v1/")!)
        let b = try! DispatchOfflineMissionStore(rootDirectory: root, baseURL: URL(string: "https://api.rentnking.com/api/admin/v1/")!)
        let serverA = FakeDispatchServer(), serverB = FakeDispatchServer()
        serverA.missions = [m("A1", "a1")]
        serverB.missions = [m("B1", "b1")]
        return (a, b, serverA, serverB, TenantRoutingClient(servers: ["A": serverA, "B": serverB], signedIn: "A"))
    }

    func testATenantSwitchWhileTheManifestIsInFlightWritesNothing() {
        let t = twoTenants()
        let reconcilerA = DispatchOfflineReconciler(httpClient: t.client, store: t.a,
                                                    session: { t.client.tenant == "A" ? .of(t.a) : .of(t.b) },
                                                    retainedOrderProducts: { [] })
        let gate = DispatchSemaphore(value: 0)
        t.serverA.holdNextManifest = gate
        let done = expectation(description: "both")
        done.expectedFulfillmentCount = 2
        var results: [DispatchOfflineReconcileResult] = []
        let lock = NSLock()

        reconcilerA.request(.launch) { r in lock.withLock { results.append(r) }; done.fulfill() }
        waitUntil { t.serverA.manifestRequests == 1 }
        reconcilerA.request(.wake(revision: "queued-behind-the-run")) { r in lock.withLock { results.append(r) }; done.fulfill() }
        t.client.tenant = "B" // logout of A, login to B before A's answer lands
        gate.signal()
        wait(for: [done], timeout: 5)

        // The run itself stops as sessionChanged; the queued wake either joins it (same result) or,
        // if it reaches the reconciler after the switch, is refused as no session. Never a request.
        XCTAssertTrue(results.contains { $0.status == .failed(.sessionChanged) })
        XCTAssertTrue(results.allSatisfy { $0.status == .failed(.sessionChanged) || $0.status == .skipped(.noSession) })
        XCTAssertEqual(t.serverA.manifestRequests, 1, "no follow-up run for the old session")
        XCTAssertEqual(t.serverB.requestCount, 0, "nothing of A's run (or its follow-up) reaches B")
        XCTAssertFalse(t.a.loadIndex().everCommitted, "A's answer is discarded — nothing written")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: t.a.packagesDirectory.path), [])
    }

    func testATenantSwitchWhilePackagesAreInFlightStopsBeforeAnyForeignWrite() {
        let t = twoTenants()
        let reconcilerA = DispatchOfflineReconciler(httpClient: t.client, store: t.a,
                                                    session: { t.client.tenant == "A" ? .of(t.a) : .of(t.b) },
                                                    retainedOrderProducts: { [] })
        t.serverA.missions = (1...150).map { m("A\($0)", "a\($0)") } // two package batches
        let gate = DispatchSemaphore(value: 0)
        t.serverA.holdNextPackages = gate
        let done = expectation(description: "run")
        var result: DispatchOfflineReconcileResult?

        reconcilerA.request(.launch) { result = $0; done.fulfill() }
        waitUntil { t.serverA.packageRequests.count == 1 }
        t.client.tenant = "B"
        gate.signal()
        wait(for: [done], timeout: 5)

        XCTAssertEqual(result?.packageFailure, .sessionChanged)
        XCTAssertEqual(t.serverA.packageRequests.count, 1, "the second batch is never sent")
        XCTAssertEqual(t.serverB.requestCount, 0)
        XCTAssertTrue(t.a.loadIndex().entries.allSatisfy { $0.readyRevision == nil }, "the in-flight answer is discarded")
        XCTAssertFalse(t.b.loadIndex().everCommitted)
    }

    // MARK: - Same-company session change (review F3)

    /// A reconciler whose session is `credential` for this store's company, recording the
    /// manifest revision of every commit it makes.
    private func sameCompanyReconciler(_ credential: @escaping () -> String) -> (DispatchOfflineReconciler, () -> [String?]) {
        let r = DispatchOfflineReconciler(httpClient: server, store: store,
                                          session: { [unowned self] in .of(self.store, credential: credential()) },
                                          retainedOrderProducts: { [] }, now: { [unowned self] in self.clock })
        let lock = NSLock()
        var commits: [String?] = []
        r.onCommit = { index in lock.withLock { commits.append(index.manifestRevision) } }
        return (r, { lock.withLock { commits } })
    }

    func testASameCompanySignInMidRunDiscardsTheOldAnswerAndRepairsUnderTheNewSession() {
        var credential = "cred-1"
        let (reconciler, commits) = sameCompanyReconciler { credential }
        let old = [m("A", "a1")]
        server.missions = old
        let gate = DispatchSemaphore(value: 0)
        server.holdNextManifest = gate
        let done = expectation(description: "run")
        var result: DispatchOfflineReconcileResult?

        reconciler.request(.launch) { result = $0; done.fulfill() }
        waitUntil { self.server.manifestRequests == 1 }
        credential = "cred-2"                 // another employee of the SAME company signs in
        server.setMissions([m("A", "a2")])    // what the server says for the new session
        gate.signal()                         // the old session's answer (a1) lands after the change
        wait(for: [done], timeout: 5)

        XCTAssertFalse(commits().contains(F.manifestRevision(old)), "the old credential's answer is never written")
        XCTAssertEqual(server.manifestRequests, 2, "one follow-up under the new session, with no other trigger")
        XCTAssertEqual(result?.status, .completed, "the waiter is served by the new session's run")
        XCTAssertEqual(ready("ORD-SCH-A:delivery"), F.revision("a2"))
        XCTAssertEqual(index.manifestRevision, F.manifestRevision([m("A", "a2")]))
    }

    func testASameCompanyLoginDuringTheRunCoalescesIntoExactlyOneFollowUp() {
        var credential = "cred-1"
        let (reconciler, _) = sameCompanyReconciler { credential }
        server.missions = (1...150).map { m("A\($0)", "a\($0)") } // two package batches
        let gate = DispatchSemaphore(value: 0)
        server.holdNextPackages = gate
        let done = expectation(description: "both")
        done.expectedFulfillmentCount = 2
        let lock = NSLock()
        var results: [DispatchOfflineReconcileResult] = []

        reconciler.request(.launch) { r in lock.withLock { results.append(r) }; done.fulfill() }
        waitUntil { self.server.packageRequests.count == 1 }
        credential = "cred-2"
        reconciler.request(.loginCompleted) { r in lock.withLock { results.append(r) }; done.fulfill() }
        gate.signal()
        wait(for: [done], timeout: 5)

        XCTAssertEqual(server.manifestRequests, 2, "the login trigger and the aborted run share ONE follow-up")
        XCTAssertTrue(results.allSatisfy { $0.status == .completed }, "\(results.map(\.status))")
        XCTAssertTrue(index.isFullyCurrent)
        XCTAssertEqual(index.entries.count, 150)
    }

    func testASignOutMidRunStillStopsWithoutAFollowUp() {
        var signedIn = true
        let reconciler = DispatchOfflineReconciler(httpClient: server, store: store,
                                                   session: { [unowned self] in signedIn ? .of(self.store) : nil },
                                                   retainedOrderProducts: { [] })
        server.missions = [m("A", "a1")]
        let gate = DispatchSemaphore(value: 0)
        server.holdNextManifest = gate
        let done = expectation(description: "run")
        var result: DispatchOfflineReconcileResult?

        reconciler.request(.launch) { result = $0; done.fulfill() }
        waitUntil { self.server.manifestRequests == 1 }
        signedIn = false
        gate.signal()
        wait(for: [done], timeout: 5)

        XCTAssertEqual(result?.status, .failed(.sessionChanged))
        XCTAssertEqual(server.manifestRequests, 1, "nobody is signed in: nothing to repair, no request (D6)")
        XCTAssertFalse(index.everCommitted)
        XCTAssertFalse(DispatchOfflineScreenPolicy.postsReconcileOutcome(result!), "an aborted run is no outcome for any screen")
    }

    func testACrossCompanySwitchLeavesTheOldStoreAloneWhileTheNewCompanyReconcilesItsOwn() {
        let t = twoTenants()
        let session: () -> DispatchOfflineSession = { t.client.tenant == "A" ? .of(t.a) : .of(t.b) }
        let reconcilerA = DispatchOfflineReconciler(httpClient: t.client, store: t.a, session: session, retainedOrderProducts: { [] })
        let reconcilerB = DispatchOfflineReconciler(httpClient: t.client, store: t.b, session: session, retainedOrderProducts: { [] })
        let gate = DispatchSemaphore(value: 0)
        t.serverA.holdNextManifest = gate
        let aDone = expectation(description: "A")
        var aResult: DispatchOfflineReconcileResult?

        reconcilerA.request(.launch) { aResult = $0; aDone.fulfill() }
        waitUntil { t.serverA.manifestRequests == 1 }
        t.client.tenant = "B"                                  // sign out of A, sign in to B
        let bResult = reconcile(.loginCompleted, on: reconcilerB) // B's own reconciler, promptly
        gate.signal()
        wait(for: [aDone], timeout: 5)

        XCTAssertEqual(bResult.status, .completed)
        XCTAssertEqual(t.b.loadIndex().entries.map(\.missionKey), ["ORD-SCH-B1:delivery"])
        XCTAssertEqual(aResult?.status, .failed(.sessionChanged))
        XCTAssertEqual(t.serverA.manifestRequests, 1, "A's run is never followed up under B")
        XCTAssertFalse(t.a.loadIndex().everCommitted, "zero writes to A")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: t.a.packagesDirectory.path), [])
        XCTAssertFalse(DispatchOfflineScreenPolicy.postsReconcileOutcome(aResult!), "A's abort never settles B's screen")
        XCTAssertTrue(DispatchOfflineScreenPolicy.postsReconcileOutcome(bResult))
    }

    func testAnotherTenantsSessionIsNoSessionForThisStore() {
        let other = try! DispatchOfflineMissionStore(rootDirectory: root, baseURL: URL(string: "https://api.rentnking.com/api/admin/v1/")!)
        let reconciler = DispatchOfflineReconciler(httpClient: server, store: store, session: { .of(other) },
                                                   retainedOrderProducts: { [] })
        XCTAssertEqual(reconcile(.launch, on: reconciler).status, .skipped(.noSession))
        XCTAssertEqual(server.requestCount, 0)
    }

    // MARK: - Partial runs back off (review M-4)

    func testAPartialRunCoolsDownAndOnlyRepairTriggersFollowUp() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        server.packageOverrides["ORD-SCH-B:delivery"] = F.package(m("B", "b1")).setting(["dispatch", "row"], .null) // B never validates
        XCTAssertEqual(reconcile(.launch).status, .partial)
        XCTAssertEqual(server.manifestRequests, 1)

        clock = clock.addingTimeInterval(DispatchOfflineReconciler.freshnessWindow + 1)
        XCTAssertEqual(reconcile(.foreground).status, .skipped(.coolingDown), "a permanently bad package is not re-requested on every foreground")

        // During a partial run: a foreground joins it without a follow-up; a network restoration gets one.
        let gate = DispatchSemaphore(value: 0)
        server.holdNextManifest = gate
        let done = expectation(description: "coalesced")
        done.expectedFulfillmentCount = 2
        reconciler.request(.manualRefresh) { _ in done.fulfill() }
        waitUntil { self.server.manifestRequests == 2 }
        reconciler.request(.foreground) { _ in done.fulfill() }
        gate.signal()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(server.manifestRequests, 2, "a throttled trigger does not re-run a partial reconciliation")

        let gate2 = DispatchSemaphore(value: 0)
        server.holdNextManifest = gate2
        let done2 = expectation(description: "repair")
        done2.expectedFulfillmentCount = 2
        reconciler.request(.manualRefresh) { _ in done2.fulfill() }
        waitUntil { self.server.manifestRequests == 3 }
        reconciler.request(.networkRestored) { _ in done2.fulfill() }
        gate2.signal()
        wait(for: [done2], timeout: 5)
        XCTAssertEqual(server.manifestRequests, 4, "a repair trigger gets one follow-up")
    }

    // MARK: - Partial runs stay visibly not current (review F1)

    /// What the Dispatch screen would show for the store right now (online).
    private func screenOutcome(after result: DispatchOfflineReconcileResult) -> DispatchOfflineScreenPolicy.Outcome {
        let presentation = DispatchOfflineWorkingSet.present(store: store, query: DispatchOfflineQuery(dates: .all),
                                                            operations: [], today: "2026-09-22")
        return DispatchOfflineScreenPolicy.outcome(presentation: presentation,
                                                   failed: DispatchOfflineScreenPolicy.indicatesFailure(result),
                                                   online: true)
    }

    private func invalid(_ mission: M) -> JSONValue {
        F.package(mission).setting(["dispatch", "row"], .null) // never validates
    }

    func testAPartialLaunchIsNeverFreshForTheNextDispatchOpen() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        XCTAssertEqual(reconcile(.launch).status, .completed)
        clock = clock.addingTimeInterval(120)
        server.missions = [m("A", "a2"), m("B", "b2")]
        server.packageOverrides["ORD-SCH-B:delivery"] = invalid(m("B", "b2"))

        XCTAssertEqual(reconcile(.launch).status, .partial)       // one package fails
        clock = clock.addingTimeInterval(5)                        // the driver opens Dispatch ~5 s later
        let open = reconcile(.dispatchScreenOpened)

        XCTAssertNotEqual(open.status, .skipped(.fresh), "a partial run never counts as fresh")
        XCTAssertEqual(screenOutcome(after: open), .flagNotCurrent, "the saved-list indication stays visible")
        let noFailureReported = DispatchOfflineReconcileResult(status: .skipped(.fresh))
        XCTAssertEqual(screenOutcome(after: noFailureReported), .flagNotCurrent,
                       "while any mission is stale or missing, nothing can present the cache as current")

        // A later fully successful reconciliation clears it.
        server.packageOverrides = [:]
        let repair = reconcile(.manualRefresh)
        XCTAssertEqual(repair.status, .completed)
        XCTAssertEqual(screenOutcome(after: repair), .current)
        clock = clock.addingTimeInterval(5)
        XCTAssertEqual(reconcile(.dispatchScreenOpened).status, .skipped(.fresh), "fully current again → fresh again")
    }

    func testADispatchOpenCoalescedIntoAPartialLaunchIsNotCurrent() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        server.packageOverrides["ORD-SCH-B:delivery"] = invalid(m("B", "b1"))
        let gate = DispatchSemaphore(value: 0)
        server.holdNextPackages = gate
        let done = expectation(description: "both")
        done.expectedFulfillmentCount = 2
        let lock = NSLock()
        var results: [DispatchOfflineReconcileResult] = []

        reconciler.request(.launch) { r in lock.withLock { results.append(r) }; done.fulfill() }
        waitUntil { self.server.packageRequests.count == 1 }
        reconciler.request(.dispatchScreenOpened) { r in lock.withLock { results.append(r) }; done.fulfill() }
        gate.signal()
        wait(for: [done], timeout: 5)

        XCTAssertEqual(results.map(\.status), [.partial, .partial], "the open joins the launch run")
        XCTAssertEqual(server.manifestRequests, 1)
        XCTAssertTrue(results.allSatisfy { screenOutcome(after: $0) == .flagNotCurrent })
    }

    func testAPartialRunNeverAdvancesTheDurableFreshMarker() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        XCTAssertEqual(reconcile(.launch).status, .completed)
        let currentAt = index.lastCurrentAt
        XCTAssertNotNil(currentAt, "a fully current run records when it was current")

        clock = clock.addingTimeInterval(2)
        server.missions = [m("A", "a2"), m("B", "b2")]
        server.packageOverrides["ORD-SCH-B:delivery"] = invalid(m("B", "b2"))
        XCTAssertEqual(reconcile(.manualRefresh).status, .partial)
        XCTAssertEqual(index.lastCurrentAt, currentAt, "a partial run never advances the fresh marker")

        // Relaunch inside the window: no in-memory failure count, only the durable index.
        clock = clock.addingTimeInterval(5)
        let relaunched = makeReconciler()
        XCTAssertNotEqual(reconcile(.dispatchScreenOpened, on: relaunched).status, .skipped(.fresh))
        XCTAssertEqual(server.manifestRequests, 3, "the incomplete cache is reconciled, not suppressed")
    }

    func testAFailedRunAfterASuccessIsNotFreshEither() {
        server.missions = [m("A", "a1")]
        XCTAssertEqual(reconcile(.launch).status, .completed)
        clock = clock.addingTimeInterval(3)
        server.manifestStatus = 500
        XCTAssertEqual(reconcile(.manualRefresh).status, .failed(.server(500)))
        clock = clock.addingTimeInterval(3)

        let open = reconcile(.dispatchScreenOpened)

        XCTAssertEqual(open.status, .skipped(.coolingDown), "the last run failed: back off, never 'fresh'")
        XCTAssertTrue(DispatchOfflineScreenPolicy.indicatesFailure(open))
        XCTAssertEqual(screenOutcome(after: open), .flagNotCurrent)
    }

    // MARK: - A manifest alone is not downloaded Dispatch (review 3, Important)

    private var presentation: DispatchOfflinePresentation {
        DispatchOfflineWorkingSet.present(store: store, query: DispatchOfflineQuery(dates: .all), operations: [], today: "2026-09-22")
    }

    private func outcome(_ result: DispatchOfflineReconcileResult, online: Bool) -> DispatchOfflineScreenPolicy.Outcome {
        DispatchOfflineScreenPolicy.outcome(presentation: presentation,
                                            failed: DispatchOfflineScreenPolicy.indicatesFailure(result), online: online)
    }

    func testAFirstDownloadWhosePackagesFailFallsBackToTheLiveFeedOnline() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        server.packagesStatus = 500

        let first = reconcile(.launch)

        XCTAssertEqual(first.status, .partial)
        XCTAssertTrue(index.everCommitted, "the manifest itself was applied")
        XCTAssertEqual(presentation, .notDownloaded, "missions but no usable package: NOT an empty downloaded Dispatch")
        XCTAssertEqual(outcome(first, online: true), .fallBackToFeed, "never 'No results found.' — the live feed")
        XCTAssertTrue(DispatchOfflineScreenPolicy.filterChangeNeedsFirstDownload(notDownloaded: presentation == .notDownloaded, online: true),
                      "the committed manifest does not suppress the next attempt")

        // The next Dispatch open is cooling down — it still lands on the live feed.
        clock = clock.addingTimeInterval(5)
        let open = reconcile(.dispatchScreenOpened)
        XCTAssertEqual(open.status, .skipped(.coolingDown))
        XCTAssertEqual(outcome(open, online: true), .fallBackToFeed)
    }

    func testTheSameFailedFirstDownloadOfflineSaysDispatchIsNotDownloaded() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        server.packagesStatus = 500
        let first = reconcile(.launch)

        XCTAssertEqual(outcome(first, online: false), .showNotDownloaded)
        XCTAssertFalse(DispatchOfflineScreenPolicy.filterChangeNeedsFirstDownload(notDownloaded: true, online: false), "offline: zero requests")
    }

    // MARK: - Release 2026-09-30: a server without the offline endpoints, a phone without signal

    /// The app ships before the backend that serves the offline manifest: until then nothing is
    /// ever downloaded. Offline, the last live Dispatch list this phone saw (the feed snapshot —
    /// what 1.0.22 showed) beats an empty "not downloaded" screen that connecting cannot fix.
    func testWithNothingDownloadedAndNoSignalTheLastLiveListBeatsAnEmptyScreen() {
        server.missions = [m("A", "a1")]
        server.manifestStatus = 404                                   // today's production backend
        let first = reconcile(.launch)
        XCTAssertEqual(first.status, .failed(.server(404)))
        XCTAssertEqual(presentation, .notDownloaded)
        let failed = DispatchOfflineScreenPolicy.indicatesFailure(first)

        XCTAssertEqual(DispatchOfflineScreenPolicy.outcome(presentation: presentation, failed: failed, online: false, hasFeedSnapshot: true),
                       .fallBackToFeed, "offline with a feed snapshot: show it")
        XCTAssertEqual(DispatchOfflineScreenPolicy.outcome(presentation: presentation, failed: failed, online: false, hasFeedSnapshot: false),
                       .showNotDownloaded, "nothing at all on the phone: say so")
        XCTAssertEqual(DispatchOfflineScreenPolicy.outcome(presentation: presentation, failed: failed, online: true, hasFeedSnapshot: true),
                       .fallBackToFeed, "online: the live feed, as before")

        XCTAssertTrue(DispatchOfflineScreenPolicy.offlineShowsFeedSnapshot(presentation: presentation, online: false, hasFeedSnapshot: true))
        XCTAssertFalse(DispatchOfflineScreenPolicy.offlineShowsFeedSnapshot(presentation: presentation, online: true, hasFeedSnapshot: true),
                       "online the screen asks the server")
        XCTAssertFalse(DispatchOfflineScreenPolicy.offlineShowsFeedSnapshot(presentation: presentation, online: false, hasFeedSnapshot: false))
    }

    func testADownloadedDispatchStillWinsOverTheFeedSnapshotOffline() {
        server.missions = [m("A", "a1")]
        let first = reconcile(.launch)
        guard case .ready = presentation else { return XCTFail("downloaded") }
        XCTAssertEqual(DispatchOfflineScreenPolicy.outcome(presentation: presentation, failed: DispatchOfflineScreenPolicy.indicatesFailure(first),
                                                           online: false, hasFeedSnapshot: true), .flagOffline)
        XCTAssertFalse(DispatchOfflineScreenPolicy.offlineShowsFeedSnapshot(presentation: presentation, online: false, hasFeedSnapshot: true))
    }

    func testAGenuinelyEmptyManifestIsANormalEmptyDispatch() {
        server.missions = []

        let result = reconcile(.launch)

        XCTAssertEqual(result.status, .completed)
        guard case .ready(let rows, let freshness) = presentation else { return XCTFail("an empty manifest is downloaded, empty Dispatch") }
        XCTAssertEqual(rows, [])
        XCTAssertTrue(freshness.isComplete)
        XCTAssertEqual(outcome(result, online: true), .current, "not a failed download")
        XCTAssertFalse(DispatchOfflineScreenPolicy.filterChangeNeedsFirstDownload(notDownloaded: presentation == .notDownloaded, online: true))
    }

    func testAFirstDownloadInProgressNeverRendersAFalseEmptyList() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        let gate = DispatchSemaphore(value: 0)
        server.holdNextPackages = gate
        let done = expectation(description: "first download")

        reconciler.request(.launch) { _ in done.fulfill() }
        waitUntil { self.server.packageRequests.count == 1 }

        XCTAssertTrue(index.everCommitted, "the manifest is committed while its packages are in flight")
        XCTAssertEqual(presentation, .notDownloaded, "still the first download — loading, never an empty list")

        gate.signal()
        wait(for: [done], timeout: 5)
        guard case .ready(let rows, _) = presentation else { return XCTFail() }
        XCTAssertEqual(rows.count, 2)
    }

    func testALaterSuccessfulPackageRunTurnsTheFallbackIntoTheNormalCache() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        server.packagesStatus = 500
        XCTAssertEqual(reconcile(.launch).status, .partial)
        XCTAssertFalse(DispatchOfflineScreenPolicy.leavesFeedFallback(presentation: presentation))

        server.packagesStatus = 200
        let repair = reconcile(.manualRefresh)

        XCTAssertEqual(repair.status, .completed)
        guard case .ready(let rows, _) = presentation else { return XCTFail() }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(outcome(repair, online: true), .current)
        XCTAssertTrue(DispatchOfflineScreenPolicy.leavesFeedFallback(presentation: presentation),
                      "the screen leaves the live-feed fallback for the normal cached working set")
    }

    func testOnlyAStaleButShowableWorkingSetIsStillDownloaded() {
        server.missions = [m("A", "a1"), m("B", "b1")]
        XCTAssertEqual(reconcile(.launch).status, .completed)
        server.missions = [m("A", "a2"), m("B", "b2")]
        server.packagesStatus = 500
        let failed = reconcile(.manualRefresh)

        guard case .ready(let rows, let freshness) = presentation else { return XCTFail("the previous packages are still usable") }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(freshness.staleCount, 2)
        XCTAssertEqual(outcome(failed, online: true), .flagNotCurrent)
    }

    // MARK: - Exact revision round trip (review 3, Minor #2)

    func testARevisionConfirmedAgainByANewManifestIsServerTruthAsOfThatManifest() {
        let t0 = clock
        let revisionA = m("A", "content-a")
        let revisionB = m("A", "content-b")
        server.missions = [revisionA]
        XCTAssertEqual(reconcile(.launch).status, .completed)          // A (not started) downloaded at t0

        // Offline Load Map & Go → a durable On My Way; it syncs later (acknowledged at t0+100).
        var departure = SyncOperation(type: EffectiveFieldState.driverChecklistType, capturedAt: t0.addingTimeInterval(60),
                                      identity: SyncBusinessIdentity(orderProductUniqueId: revisionA.opuid),
                                      payload: .object(["order_product_unique_id": .string(revisionA.opuid),
                                                        "checklist_type": .string("delivery"),
                                                        "equipment_driver_status": .string("On My Way")]))
        departure.state = .synced
        departure.acknowledgment = SyncAcknowledgment(acknowledgedAt: t0.addingTimeInterval(100), statusCode: 200, requestId: nil,
                                                      replayed: false, serverReceivedAt: nil, data: nil)

        // The server records it: revision B carries the stage.
        clock = t0.addingTimeInterval(200)
        server.missions = [revisionB]
        server.packageOverrides[revisionA.key] = F.package(revisionB)
            .setting(["dispatch", "row", "delivery_checklist", "ready_to_go_at"], .string("2026-09-22 08:01:00"))
        XCTAssertEqual(reconcile(.manualRefresh).status, .completed)
        XCTAssertEqual(ready(revisionA.key), revisionB.revision)

        // The office recalls the trip: the content returns EXACTLY to revision A, whose file is still on disk.
        clock = t0.addingTimeInterval(1200)
        server.packageOverrides = [:]
        server.missions = [revisionA]
        let back = reconcile(.manualRefresh)
        XCTAssertEqual(back.adopted, 1)
        XCTAssertEqual(server.packageRequests.count, 2, "A is reused from disk, not downloaded again")

        guard case .ready(let rows, _) = presentation, let row = rows.first else { return XCTFail() }
        XCTAssertEqual(row.revision, revisionA.revision)
        XCTAssertGreaterThanOrEqual(row.serverObservedAt ?? .distantPast, t0.addingTimeInterval(1200),
                                    "confirmed current by the new manifest — not the file's old download time")
        let serverStage = DriverStageServerState(readyToGoAt: row.row["delivery_checklist"]?["ready_to_go_at"]?.stringValue,
                                                 arrivedAt: row.row["delivery_checklist"]?["arrived_at"]?.stringValue,
                                                 isArrived: row.row["delivery_checklist"]?["is_arrived"]?.boolValue ?? false)
        XCTAssertNil(serverStage.readyToGoAt, "revision A has no stage")
        XCTAssertEqual(DriverStageOverlay.from([departure]).effective(orderProductUniqueId: revisionA.opuid, leg: "delivery",
                                                                      server: serverStage, serverObservedAt: row.serverObservedAt).stage,
                       .notStarted, "the recalled trip (server truth) wins over the already-confirmed local step")

        // An UNCONFIRMED local step still stands — only confirmed steps yield to later server truth.
        var pending = departure
        pending.state = .pending
        pending.acknowledgment = nil
        XCTAssertEqual(DriverStageOverlay.from([pending]).effective(orderProductUniqueId: revisionA.opuid, leg: "delivery",
                                                                    server: serverStage, serverObservedAt: row.serverObservedAt).stage,
                       .onMyWay)
    }

    // MARK: - One package that cannot be built (review 3, Minor #3)

    func testOneMissionWhosePackageCannotBeBuiltNeverFailsItsSiblings() {
        let missions = [m("A", "a1"), m("B", "b1"), m("C", "c1")]
        server.missions = missions
        XCTAssertEqual(reconcile(.launch).status, .completed)

        // All three change; the MIDDLE package fails to build on the server this time.
        server.missions = [m("A", "a2"), m("B", "b2"), m("C", "c2")]
        server.buildFailures = ["ORD-SCH-B:delivery"]
        let result = reconcile(.manualRefresh)

        XCTAssertEqual(result.status, .partial, "one bad mission is not a failed download")
        XCTAssertEqual(result.failedMissionKeys, ["ORD-SCH-B:delivery"])
        XCTAssertEqual(ready("ORD-SCH-A:delivery"), F.revision("a2"))
        XCTAssertEqual(ready("ORD-SCH-C:delivery"), F.revision("c2"))
        XCTAssertEqual(ready("ORD-SCH-B:delivery"), F.revision("b1"), "the previous valid package is preserved")
        XCTAssertTrue(index.entry("ORD-SCH-B:delivery")!.isStale)
        XCTAssertNotNil(store.readyPackage(for: index.entry("ORD-SCH-B:delivery")!))
        XCTAssertEqual(index.entries.count, 3, "a build failure is never 'not active'")
        guard case .ready(let rows, let freshness) = presentation else { return XCTFail() }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(freshness.staleCount, 1)
        XCTAssertEqual(outcome(result, online: true), .flagNotCurrent)
    }

    func testOnAFirstDownloadTheSiblingsOfAnUnbuildablePackageStillBecomeReady() {
        server.missions = [m("A", "a1"), m("B", "b1"), m("C", "c1")]
        server.buildFailures = ["ORD-SCH-B:delivery"]

        let result = reconcile(.launch)

        XCTAssertEqual(result.status, .partial)
        XCTAssertNotNil(ready("ORD-SCH-A:delivery"))
        XCTAssertNotNil(ready("ORD-SCH-C:delivery"))
        XCTAssertNil(ready("ORD-SCH-B:delivery"), "not ready — and still active")
        guard case .ready(let rows, let freshness) = presentation else { return XCTFail("two usable missions: downloaded Dispatch") }
        XCTAssertEqual(rows.map(\.orderProductUniqueId).sorted(), ["ORD-SCH-A", "ORD-SCH-C"])
        XCTAssertEqual(freshness.pendingCount, 1)
    }

    // MARK: - Background result (test 17)

    func testBackgroundResultMapping() {
        typealias R = DispatchOfflineReconcileResult
        XCTAssertEqual(R(status: .completed, changed: true).backgroundResult, .newData)
        XCTAssertEqual(R(status: .partial, changed: true).backgroundResult, .newData)
        XCTAssertEqual(R(status: .completed, changed: false).backgroundResult, .noData)
        XCTAssertEqual(R(status: .skipped(.noSession)).backgroundResult, .noData)
        XCTAssertEqual(R(status: .skipped(.alreadyCurrent)).backgroundResult, .noData)
        XCTAssertEqual(R(status: .failed(.offline)).backgroundResult, .failed)
        XCTAssertEqual(R(status: .partial, changed: false).backgroundResult, .failed)

        // End to end: first download → newData; identical → noData; offline → failed.
        server.missions = [m("A", "a1")]
        XCTAssertEqual(reconcile(.wake(revision: nil)).backgroundResult, .newData)
        XCTAssertEqual(reconcile(.wake(revision: nil)).backgroundResult, .noData)
        server.offline = true
        XCTAssertEqual(reconcile(.wake(revision: nil)).backgroundResult, .failed)
    }

    // MARK: - Helpers

    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), "condition not reached")
    }

    private func indexBytesWithoutTimestamps() -> JSONValue? {
        guard var value = JSONValue.parse(indexBytes) else { return nil }
        value = value.setting(["last_manifest_at"], .null).setting(["committed_at"], .null).setting(["last_current_at"], .null)
        if case .array(let entries)? = value["entries"] {
            value = value.setting(["entries"], .array(entries.map { $0.setting(["confirmed_at"], .null) }))
        }
        return value
    }

    private func snapshot(excluding: String) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in enumerator where !url.path.contains("/\(excluding)/") {
            if (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
                out[url.path] = try Data(contentsOf: url)
            }
        }
        return out
    }
}
