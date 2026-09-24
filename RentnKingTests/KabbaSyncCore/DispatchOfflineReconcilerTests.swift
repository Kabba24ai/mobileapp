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
            hasSession: { [unowned self] in self.session },
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

        let contexts = try ChecklistContextStore(rootDirectory: root)
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
        value = value.setting(["last_manifest_at"], .null).setting(["committed_at"], .null)
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
