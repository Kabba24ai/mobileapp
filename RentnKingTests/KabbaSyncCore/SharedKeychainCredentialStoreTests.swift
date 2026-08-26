import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Phase 6A — the ordering / fallback policy of the ONE shared Keychain item, run against a
/// backend that models the Security framework's access-group semantics on iOS:
///   • add with no group            → the process's default (app-private) group
///   • copy / update / delete with no group → EVERY group the process can reach
/// (SecItem.h: naming kSecAttrAccessGroup *limits* a copy/update/delete to that group.)
/// The real framework is exercised on device by RentnKingHostedTests.
final class SharedKeychainCredentialStoreTests: XCTestCase {

    private let shared  = "group.com.RentnKingNew.shared"
    private let private_ = "A9U32VVCRV.com.RentnKingNew.app"
    private var backend: FakeKeychainBackend!
    private var store: SharedKeychainCredentialStore!
    private var log: [String] = []

    override func setUp() {
        super.setUp()
        backend = FakeKeychainBackend(defaultGroup: private_, reachableGroups: [private_, shared])
        store = SharedKeychainCredentialStore(backend: backend, sharedAccessGroup: shared)
        log = []
        store.logger = { [weak self] in self?.log.append($0) }
    }

    // MARK: - The defect and its fix

    func testWriteStoresExactlyOneCopyInTheSharedGroupAndReadsItStraightBack() throws {
        try store.write("token-A", key: "access_token")

        XCTAssertEqual(store.read("access_token"), "token-A")
        XCTAssertEqual(backend.items.count, 1)
        XCTAssertEqual(backend.items.first?.group, shared)
        XCTAssertEqual(store.lastDiagnostics?.storedIn, .sharedGroup)
    }

    /// The Phase 5 sequence, replayed by hand: shared write first, unqualified delete after.
    /// This is exactly what happened on the iPhone — and it validates that the fake models the
    /// semantics that made it happen.
    func testThePhase5OrderingErasesTheTokenItJustWrote() {
        let data = Data("token-A".utf8)
        XCTAssertEqual(backend.update(data, key: "access_token", accessGroup: shared), KeychainStatus.itemNotFound)
        XCTAssertEqual(backend.add(data, key: "access_token", accessGroup: shared), KeychainStatus.success)
        // "delete the app-private copy" — but the query names no group, so it reaches the shared item too
        XCTAssertEqual(backend.delete(key: "access_token", accessGroup: nil), KeychainStatus.success)

        XCTAssertEqual(backend.copy(key: "access_token", accessGroup: shared).status, KeychainStatus.itemNotFound)
        XCTAssertEqual(backend.copy(key: "access_token", accessGroup: nil).status, KeychainStatus.itemNotFound)
        XCTAssertNil(store.read("access_token"), "nothing left to read — the next request goes out without Authorization")
    }

    func testTheWriteTraceProvesTheOrderDeleteThenAddThenReadBack() throws {
        try store.write("token-A", key: "access_token")

        let ops = store.lastDiagnostics?.steps.map { "\($0.operation)/\($0.accessGroup ?? "unqualified")" }
        XCTAssertEqual(ops, ["delete/unqualified", "add/\(shared)", "copy/\(shared)"])
        XCTAssertEqual(store.lastDiagnostics?.readBackMatched, true)
        XCTAssertEqual(store.lastDiagnostics?.succeeded, true)
    }

    func testRewritingReplacesTheValueWithoutLeavingACopyBehind() throws {
        try store.write("token-A", key: "access_token")
        try store.write("token-B", key: "access_token")

        XCTAssertEqual(store.read("access_token"), "token-B")
        XCTAssertEqual(backend.items.count, 1)
    }

    func testAStaleAppPrivateCopyIsClearedBeforeTheSharedWrite() throws {
        XCTAssertEqual(backend.add(Data("old".utf8), key: "access_token", accessGroup: nil), KeychainStatus.success)
        XCTAssertEqual(backend.items.first?.group, private_)

        try store.write("token-A", key: "access_token")

        XCTAssertEqual(backend.items.count, 1)
        XCTAssertEqual(backend.items.first?.group, shared)
        XCTAssertEqual(store.read("access_token"), "token-A")
    }

    func testACopyTheUnqualifiedDeleteCannotReachIsOverwrittenInPlace() throws {
        // Stricter semantics than iOS documents (an unqualified query that stays in the default
        // group): the add answers duplicate and the store must update rather than fail.
        backend.unqualifiedQueriesSpanAllGroups = false
        XCTAssertEqual(backend.add(Data("old".utf8), key: "access_token", accessGroup: shared), KeychainStatus.success)

        try store.write("token-A", key: "access_token")
        let written = store.lastDiagnostics

        XCTAssertEqual(store.read("access_token"), "token-A")
        XCTAssertEqual(backend.items.count, 1)
        XCTAssertEqual(written?.steps.map(\.operation), ["delete", "add", "update", "copy"])
    }

    // MARK: - Fallback when the shared group is unusable

    func testFallsBackToTheAppPrivateGroupWhenTheSharedGroupIsUnavailable() throws {
        backend.reachableGroups = [private_]          // e.g. a Simulator that answers -34018

        try store.write("token-A", key: "access_token")
        let written = store.lastDiagnostics

        XCTAssertEqual(store.read("access_token"), "token-A")
        XCTAssertEqual(backend.items.count, 1)
        XCTAssertEqual(backend.items.first?.group, private_)
        XCTAssertEqual(written?.storedIn, .appPrivate)
        XCTAssertFalse(store.sharedGroupUsable)
        XCTAssertTrue(log.contains { $0.contains("add(\(shared))=\(KeychainStatus.missingEntitlement)") }, "\(log)")
    }

    func testAnUnexpectedSharedWriteFailureIsThrownNotSwallowed() {
        backend.failAdds = -25308                     // errSecInteractionNotAllowed

        XCTAssertThrowsError(try store.write("token-A", key: "access_token")) { error in
            XCTAssertEqual(error as? KeychainCredentialStoreError, .osStatus(-25308))
        }
        XCTAssertTrue(store.sharedGroupUsable, "an unrelated failure must not demote the shared group")
        XCTAssertNil(store.read("access_token"))
    }

    func testAWriteWhoseReadBackDoesNotMatchIsReportedAsAFailure() {
        backend.corruptReads = true

        XCTAssertThrowsError(try store.write("token-A", key: "access_token")) { error in
            XCTAssertEqual(error as? KeychainCredentialStoreError, .readBackFailed)
        }
        XCTAssertEqual(store.lastDiagnostics?.readBackMatched, false)
        XCTAssertEqual(store.lastDiagnostics?.succeeded, false)
    }

    // MARK: - Reads and removal

    func testReadPrefersTheSharedGroupButStillFindsAnAppPrivateCopy() {
        XCTAssertEqual(backend.add(Data("private-only".utf8), key: "access_token", accessGroup: nil), KeychainStatus.success)
        XCTAssertEqual(store.read("access_token"), "private-only")

        XCTAssertEqual(backend.add(Data("shared".utf8), key: "access_token", accessGroup: shared), KeychainStatus.success)
        XCTAssertEqual(store.read("access_token"), "shared")
    }

    func testRemoveClearsEveryCopyAndAReadAfterwardsIsTraced() throws {
        try store.write("token-A", key: "access_token")
        XCTAssertEqual(backend.add(Data("stray".utf8), key: "access_token", accessGroup: nil), KeychainStatus.success)

        store.remove("access_token")

        XCTAssertTrue(backend.items.isEmpty)
        log = []
        XCTAssertNil(store.read("access_token"))
        XCTAssertEqual(log.count, 1, "a read that finds nothing is reported")
        XCTAssertTrue(log[0].hasPrefix("keychain.read FAILED"), log[0])
    }

    func testSuccessfulReadsAreNotLogged() throws {
        try store.write("token-A", key: "access_token")
        log = []
        _ = store.read("access_token")
        XCTAssertTrue(log.isEmpty)
    }

    // MARK: - Self-test and sanitization

    func testSelfTestRoundTripsAProbeAndLeavesNothingBehind() {
        let diag = store.selfTest()

        XCTAssertTrue(diag.succeeded, diag.description)
        XCTAssertEqual(diag.readBackMatched, true)
        XCTAssertEqual(diag.storedIn, .sharedGroup)
        XCTAssertTrue(backend.items.isEmpty)
        XCTAssertEqual(log.count, 1, "one consolidated line")
        XCTAssertTrue(log[0].hasPrefix("keychain.self_test ok"), log[0])
    }

    func testSelfTestReportsFailureWhenNothingCanBeStored() {
        backend.failAdds = KeychainStatus.missingEntitlement

        let diag = store.selfTest()

        XCTAssertFalse(diag.succeeded)
        XCTAssertEqual(diag.readBackMatched, false)
        XCTAssertTrue(log[0].hasPrefix("keychain.self_test FAILED"), log[0])
    }

    func testDiagnosticsNeverContainTheStoredValue() throws {
        let secret = "SECRET-" + UUID().uuidString
        try store.write(secret, key: "access_token")
        _ = store.read("access_token")
        store.remove("access_token")
        store.selfTest()

        for line in log { XCTAssertFalse(line.contains(secret), line) }
        XCTAssertFalse(store.lastDiagnostics!.description.contains(secret))
    }
}

// MARK: - Fake backend

/// Models the Security framework's access-group semantics on iOS (see the class comment above).
final class FakeKeychainBackend: KeychainItemBackend {

    struct Item: Equatable {
        let group: String
        let key: String
        var value: Data
    }

    private(set) var items: [Item] = []
    let defaultGroup: String
    var reachableGroups: Set<String>
    /// iOS: a query naming no access group covers every group the process can reach.
    var unqualifiedQueriesSpanAllGroups = true
    /// Force every add to answer this status (nil = behave normally).
    var failAdds: Int32?
    /// Return a different value than stored (simulates a read-back mismatch).
    var corruptReads = false

    init(defaultGroup: String, reachableGroups: Set<String>) {
        self.defaultGroup = defaultGroup
        self.reachableGroups = reachableGroups
    }

    func add(_ value: Data, key: String, accessGroup: String?) -> Int32 {
        if let forced = failAdds { return forced }
        let group = accessGroup ?? defaultGroup
        guard reachableGroups.contains(group) else { return KeychainStatus.missingEntitlement }
        if items.contains(where: { $0.group == group && $0.key == key }) { return KeychainStatus.duplicateItem }
        items.append(Item(group: group, key: key, value: value))
        return KeychainStatus.success
    }

    func update(_ value: Data, key: String, accessGroup: String?) -> Int32 {
        if let group = accessGroup, !reachableGroups.contains(group) { return KeychainStatus.missingEntitlement }
        let matches = indices(key: key, accessGroup: accessGroup)
        guard !matches.isEmpty else { return KeychainStatus.itemNotFound }
        for index in matches { items[index].value = value }
        return KeychainStatus.success
    }

    func copy(key: String, accessGroup: String?) -> (status: Int32, value: Data?) {
        if let group = accessGroup, !reachableGroups.contains(group) { return (KeychainStatus.missingEntitlement, nil) }
        guard let index = indices(key: key, accessGroup: accessGroup).first else { return (KeychainStatus.itemNotFound, nil) }
        let value = corruptReads ? Data("corrupted".utf8) : items[index].value
        return (KeychainStatus.success, value)
    }

    func delete(key: String, accessGroup: String?) -> Int32 {
        if let group = accessGroup, !reachableGroups.contains(group) { return KeychainStatus.missingEntitlement }
        let matches = indices(key: key, accessGroup: accessGroup)
        guard !matches.isEmpty else { return KeychainStatus.itemNotFound }
        for index in matches.sorted(by: >) { items.remove(at: index) }
        return KeychainStatus.success
    }

    private func indices(key: String, accessGroup: String?) -> [Int] {
        items.indices.filter { index in
            let item = items[index]
            guard item.key == key else { return false }
            if let group = accessGroup { return item.group == group }
            return unqualifiedQueriesSpanAllGroups ? reachableGroups.contains(item.group) : item.group == defaultGroup
        }
    }
}
