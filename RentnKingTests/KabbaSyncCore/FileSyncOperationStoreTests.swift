import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class FileSyncOperationStoreTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func sample(id: String = UUID().uuidString) -> SyncOperation {
        var op = SyncOperation(id: id, type: "test.operation",
                               capturedAt: Date(timeIntervalSince1970: 1_756_140_843), // 2026-08-25T…
                               queuedAt: Date(timeIntervalSince1970: 1_756_153_212),
                               identity: SyncBusinessIdentity(orderUniqueId: "ORD-1", orderProductUniqueId: "ORD-SCH-1"),
                               payload: Fixtures.payload,
                               assets: [SyncAsset(clientMediaId: "media-1", relativePath: "ORD-1/sig.jpg", mimeType: "image/jpeg", fieldName: "signature_media")],
                               displayTitle: "Driver checklist · Ready to Go")
        op.attempts.attemptCount = 2
        op.attempts.lastErrorCode = "SERVER_ERROR"
        return op
    }

    func testSaveLoadRoundTripPreservesEverythingIncludingDatesToTheSecond() throws {
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let op = sample()
        try store.save(op)

        let loaded = try XCTUnwrap(try store.load(id: op.id))
        XCTAssertEqual(loaded, op)
        XCTAssertEqual(loaded.capturedAt.timeIntervalSince1970, op.capturedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(loaded.assets.first?.clientMediaId, "media-1")
        XCTAssertEqual(loaded.payload["checklist_type"]?.stringValue, "delivery")
        XCTAssertEqual(loaded.schemaVersion, SyncOperation.currentSchemaVersion)
    }

    func testRecordsSurviveANewStoreInstanceOverTheSameDirectory() throws {
        let first = try FileSyncOperationStore(rootDirectory: dir)
        let a = sample(); let b = sample()
        try first.save(a); try first.save(b)

        // "Force quit and relaunch": a brand-new store over the same directory.
        let second = try FileSyncOperationStore(rootDirectory: dir)
        let all = try second.loadAll()
        XCTAssertEqual(Set(all.map(\.id)), Set([a.id, b.id]))
    }

    func testDeleteRemovesOnlyThatRecord() throws {
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let a = sample(); let b = sample()
        try store.save(a); try store.save(b)
        try store.delete(id: a.id)
        XCTAssertNil(try store.load(id: a.id))
        XCTAssertNotNil(try store.load(id: b.id))
        XCTAssertNoThrow(try store.delete(id: "does-not-exist"))
    }

    func testCorruptRecordIsQuarantinedNotDeleted() throws {
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let good = sample()
        try store.save(good)
        let corrupt = store.operationsDirectory.appendingPathComponent("BROKEN-0001.json")
        try Data("{not json".utf8).write(to: corrupt)

        let all = try store.loadAll()
        XCTAssertEqual(all.map(\.id), [good.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: corrupt.path), "moved out of the operations directory")
        XCTAssertEqual(store.quarantined.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.quarantined[0].path), "original bytes preserved")
    }

    func testDirectoriesAreCreatedAndAssetsDirectoryIsExposed() throws {
        let store = try FileSyncOperationStore(rootDirectory: dir.appendingPathComponent("nested/deeper"))
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.operationsDirectory.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetsDirectory.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.quarantineDirectory.path, isDirectory: &isDir) && isDir.boolValue)
        let values = try store.rootDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testFilenameIsSanitised() throws {
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let op = SyncOperation(id: "../evil/../id", type: "t", capturedAt: Date(), payload: .object([:]))
        try store.save(op)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.operationsDirectory.path)
        XCTAssertEqual(files, ["evilid.json"])
        XCTAssertEqual(try store.load(id: op.id)?.id, op.id)
    }
}
