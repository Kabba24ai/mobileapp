//
//  DispatchOfflineMissionStoreTests.swift
//  Dispatch offline Phase 3 — the durable, per-tenant mission store: immutable
//  per-revision package files, an atomically replaced active index, and the
//  D7 cleanup rule (7-day grace + never while Sync Engine work references the
//  order product). Field work is never touched.
//

import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class DispatchOfflineMissionStoreTests: XCTestCase {

    private typealias F = DispatchOfflineFixtures
    private let kabba = URL(string: "https://api.kabba.ai/api/admin/v1/")!
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func store(_ root: URL, base: URL? = nil) throws -> DispatchOfflineMissionStore {
        try DispatchOfflineMissionStore(rootDirectory: root, baseURL: base ?? kabba)
    }

    private func package(_ m: F.Mission) -> DispatchOfflinePackage {
        try! DispatchOfflinePackagesResponse.decode(envelope: F.packagesBody([F.package(m)]), requested: [m.key]).packages[0]
    }

    private func entry(_ m: F.Mission, file: String?) -> DispatchOfflineIndex.Entry {
        .init(missionKey: m.key, orderProductUniqueId: m.opuid, leg: m.leg, effectiveDate: m.effectiveDate,
              serverRevision: m.revision, readyRevision: file == nil ? nil : m.revision, packageFile: file)
    }

    /// Writes the package and commits an index that points at it.
    @discardableResult
    private func commitReady(_ s: DispatchOfflineMissionStore, _ missions: [F.Mission], at date: Date? = nil) throws -> DispatchOfflineIndex {
        var index = s.loadIndex()
        index.entries = try missions.map { entry($0, file: try s.writePackage(package($0), cachedAt: date ?? t0)) }
        index.everCommitted = true
        index.committedAt = date ?? t0
        try s.commit(index)
        return index
    }

    // MARK: - Durability

    func testNewInstanceReadsTheSameActiveSet() throws {
        let root = Fixtures.tempDirectory()
        let a = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))
        let b = F.Mission(opuid: "ORD-SCH-B", leg: .return, revision: F.revision("b1"))
        let written = try commitReady(try store(root), [a, b])

        // Force quit / reboot: a brand-new store over the same directory.
        let relaunched = try store(root)
        let index = relaunched.loadIndex()
        XCTAssertEqual(index, written)
        XCTAssertTrue(index.everCommitted)
        for e in index.entries {
            let stored = try XCTUnwrap(relaunched.readyPackage(for: e))
            XCTAssertEqual(stored.missionKey, e.missionKey)
            XCTAssertEqual(stored.revision, e.readyRevision)
        }
    }

    func testANewStoreIsEmptyAndNeverCommitted() throws {
        let index = try store(Fixtures.tempDirectory()).loadIndex()
        XCTAssertFalse(index.everCommitted)
        XCTAssertEqual(index.entries, [])
    }

    func testNewRevisionNeverOverwritesPrevious() throws {
        let s = try store(Fixtures.tempDirectory())
        let v1 = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("v1"))
        var v2 = v1; v2.revision = F.revision("v2")

        let f1 = try s.writePackage(package(v1), cachedAt: t0)
        let f2 = try s.writePackage(package(v2), cachedAt: t0)

        XCTAssertNotEqual(f1, f2, "one immutable file per (mission, revision)")
        XCTAssertEqual(s.loadPackage(file: f1)?.revision, v1.revision)
        XCTAssertEqual(s.loadPackage(file: f2)?.revision, v2.revision)
        XCTAssertEqual(s.validPackageFile(missionKey: v1.key, orderProductUniqueId: v1.opuid, leg: .delivery, revision: v1.revision), f1)
    }

    func testFailedIndexCommitKeepsPreviousConsistentIndex() throws {
        let root = Fixtures.tempDirectory()
        let s = try store(root)
        let a = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))
        let before = try commitReady(s, [a])

        // The replacement package is written, then the index commit dies (crash / disk).
        var a2 = a; a2.revision = F.revision("a2")
        let b = F.Mission(opuid: "ORD-SCH-B", revision: F.revision("b1"))
        var next = s.loadIndex()
        next.entries = [entry(a2, file: try s.writePackage(package(a2), cachedAt: t0)),
                        entry(b, file: try s.writePackage(package(b), cachedAt: t0))]
        s.failNextIndexCommit = true
        XCTAssertThrowsError(try s.commit(next))

        let relaunched = try store(root)
        XCTAssertEqual(relaunched.loadIndex(), before, "the previous index is intact")
        for e in relaunched.loadIndex().entries {
            XCTAssertNotNil(relaunched.readyPackage(for: e), "every referenced file exists")
        }
    }

    func testMissingReferencedFileIsNotReady() throws {
        let s = try store(Fixtures.tempDirectory())
        let a = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))
        let index = try commitReady(s, [a])

        try FileManager.default.removeItem(at: s.packagesDirectory.appendingPathComponent(index.entries[0].packageFile!))

        XCTAssertNil(try store(s.rootDirectory).readyPackage(for: index.entries[0]))
    }

    func testAPackageFileForAnotherMissionOrRevisionIsNotReady() throws {
        let s = try store(Fixtures.tempDirectory())
        let a = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))
        let index = try commitReady(s, [a])
        var wrong = index.entries[0]
        wrong.readyRevision = F.revision("other")
        XCTAssertNil(s.readyPackage(for: wrong))
    }

    func testCorruptPackageIsQuarantinedNotPresentedAndQuarantineIsCapped() throws {
        let s = try store(Fixtures.tempDirectory())
        let a = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))
        let index = try commitReady(s, [a])
        let file = s.packagesDirectory.appendingPathComponent(index.entries[0].packageFile!)
        try Data("{ truncated".utf8).write(to: file)

        XCTAssertNil(try store(s.rootDirectory).readyPackage(for: index.entries[0]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: s.quarantineDirectory.path).count, 1)

        for i in 0..<30 {
            let junk = s.packagesDirectory.appendingPathComponent("junk\(i).json")
            try Data("x".utf8).write(to: junk)
            _ = s.loadPackage(file: junk.lastPathComponent)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: s.quarantineDirectory.path).count,
                       DispatchOfflineMissionStore.quarantineLimit)
    }

    func testCorruptIndexReadsAsNoCacheAndIsQuarantined() throws {
        let s = try store(Fixtures.tempDirectory())
        try commitReady(s, [F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))])
        try Data("not json".utf8).write(to: s.indexURL)

        XCTAssertFalse(try store(s.rootDirectory).loadIndex().everCommitted)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: s.quarantineDirectory.path).count, 1)
    }

    // MARK: - Tenant isolation

    func testTenantsNeverShareADirectory() throws {
        let root = Fixtures.tempDirectory()
        let kabbaStore = try store(root)
        let rentnking = try store(root, base: URL(string: "https://api.rentnking.com/api/admin/v1/")!)
        try commitReady(kabbaStore, [F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))])

        XCTAssertNotEqual(kabbaStore.directory, rentnking.directory)
        XCTAssertFalse(rentnking.loadIndex().everCommitted, "one tenant never sees another's Dispatch")
        XCTAssertEqual(DispatchOfflineTenant.key(baseURL: URL(string: "HTTPS://API.Kabba.ai/api/admin/v1")!),
                       DispatchOfflineTenant.key(baseURL: kabba), "normalized: case and trailing slash")
    }

    func testAnIndexRecordedForAnotherBaseURLReadsAsNoCache() throws {
        let s = try store(Fixtures.tempDirectory())
        var index = try commitReady(s, [F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))])
        index.baseURL = "https://elsewhere.example/api/admin/v1"
        // Written raw: commit() always stamps the store's own tenant.
        try KabbaISO8601.makeEncoder().encode(index).write(to: s.indexURL)
        XCTAssertFalse(try store(s.rootDirectory).loadIndex().everCommitted)
    }

    // MARK: - D7 cleanup

    private func day(_ n: Double) -> Date { t0.addingTimeInterval(n * 86_400) }

    private func dropEverything(_ s: DispatchOfflineMissionStore) throws -> DispatchOfflineIndex {
        var index = s.loadIndex()
        index.entries = []
        try s.commit(index)
        return index
    }

    func testARemovedMissionsPackageIsPurgedOnlyAfterTheSevenDayGrace() throws {
        let s = try store(Fixtures.tempDirectory())
        let a = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))
        let file = try commitReady(s, [a]).entries[0].packageFile!
        let path = s.packagesDirectory.appendingPathComponent(file).path

        var index = try dropEverything(s)
        index = s.collectGarbage(index, retainingOrderProducts: [], now: day(0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "day 0: retired, not purged")
        XCTAssertEqual(index.retired.map(\.packageFile), [file])
        XCTAssertEqual(index.retired.first?.retiredAt, day(0))

        index = s.collectGarbage(index, retainingOrderProducts: [], now: day(6.9))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "day 6: still inside the grace period")

        index = s.collectGarbage(index, retainingOrderProducts: [], now: day(7))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "day 7, no referencing work: purged")
        XCTAssertEqual(index.retired, [])
    }

    func testAPackageReferencedBySyncEngineWorkIsNeverPurged() throws {
        let s = try store(Fixtures.tempDirectory())
        let a = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))
        let file = try commitReady(s, [a]).entries[0].packageFile!

        var index = s.collectGarbage(try dropEverything(s), retainingOrderProducts: [a.opuid], now: day(0))
        index = s.collectGarbage(index, retainingOrderProducts: [a.opuid], now: day(30))
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.packagesDirectory.appendingPathComponent(file).path),
                      "an order product with Sync Engine work keeps its package")

        index = s.collectGarbage(index, retainingOrderProducts: [], now: day(31))
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.packagesDirectory.appendingPathComponent(file).path),
                       "once the work is gone and the grace has passed, it is purged")
    }

    func testASupersededRevisionFollowsTheSameGraceRule() throws {
        let s = try store(Fixtures.tempDirectory())
        let v1 = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("v1"))
        let old = try commitReady(s, [v1]).entries[0].packageFile!
        var v2 = v1; v2.revision = F.revision("v2")
        let current = try commitReady(s, [v2]).entries[0].packageFile!

        var index = s.collectGarbage(s.loadIndex(), retainingOrderProducts: [], now: day(0))
        XCTAssertEqual(index.retired.map(\.packageFile), [old])
        index = s.collectGarbage(index, retainingOrderProducts: [], now: day(8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.packagesDirectory.appendingPathComponent(old).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.packagesDirectory.appendingPathComponent(current).path),
                      "the active revision is never collected")
    }

    func testAMissionThatReturnsLeavesTheRetiredList() throws {
        let s = try store(Fixtures.tempDirectory())
        let a = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))
        let active = try commitReady(s, [a])
        var index = s.collectGarbage(try dropEverything(s), retainingOrderProducts: [], now: day(0))
        XCTAssertEqual(index.retired.count, 1)

        index.entries = active.entries
        index = s.collectGarbage(index, retainingOrderProducts: [], now: day(10))
        XCTAssertEqual(index.retired, [])
        XCTAssertNotNil(s.readyPackage(for: index.entries[0]))
    }

    func testAnOrphanFileIsRecordedAsRetiredNotDeletedOnSight() throws {
        let s = try store(Fixtures.tempDirectory())
        let a = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1"))
        let orphan = try s.writePackage(package(a), cachedAt: t0) // crash before any index referenced it

        let index = s.collectGarbage(s.loadIndex(), retainingOrderProducts: [], now: day(0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.packagesDirectory.appendingPathComponent(orphan).path))
        XCTAssertEqual(index.retired.map(\.packageFile), [orphan])
        XCTAssertEqual(index.retired.map(\.orderProductUniqueId), [a.opuid])
    }

    func testCleanupNeverTouchesSyncEngineWorkOrChecklistContexts() throws {
        let root = Fixtures.tempDirectory()
        let engineStore = try FileSyncOperationStore(rootDirectory: root)
        let contexts = try ChecklistContextStore(rootDirectory: root)
        var op = SyncOperation(type: "delivery_checklist.complete", capturedAt: t0,
                               identity: SyncBusinessIdentity(orderProductUniqueId: "ORD-SCH-A"), payload: .object(["x": .string("y")]))
        op.state = .needsAttention
        try engineStore.save(op)
        let asset = engineStore.assetsDirectory.appendingPathComponent("signature.png")
        try Data("signature-bytes".utf8).write(to: asset)
        try contexts.save(try ChecklistContext.decode(envelopeData: F.data("delivery_checklist_context")))

        let snapshot = try snapshotFiles(root, excluding: "dispatch-offline")

        let s = try store(root)
        try commitReady(s, [F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a1")),
                            F.Mission(opuid: "ORD-SCH-B", revision: F.revision("b1"))])
        var index = s.collectGarbage(try dropEverything(s), retainingOrderProducts: [], now: day(0))
        index = s.collectGarbage(index, retainingOrderProducts: [], now: day(100))
        try s.commit(index)

        XCTAssertEqual(try snapshotFiles(root, excluding: "dispatch-offline"), snapshot,
                       "operations, assets and checklist contexts are byte-identical")
    }

    private func snapshotFiles(_ root: URL, excluding: String) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in enumerator where !url.path.contains("/\(excluding)/") {
            if (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
                out[url.path] = try Data(contentsOf: url)
            }
        }
        XCTAssertFalse(out.isEmpty)
        return out
    }
}
