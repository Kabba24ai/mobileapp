//
//  NextStopStoreTests.swift
//  RentnKingTests — KabbaSyncCore (Foundation only)
//
//  The shop stop is durable because the driver leaves the app to navigate: the
//  selection has to be on disk BEFORE Maps opens, and still be there when iOS
//  has recreated the app behind them.
//
//  Tenant-scoped like every other Sync store (Dispatch offline Phase 4,
//  Amendment B): one company's shop stop can never be read by another, and
//  signed out nothing is read or written.
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class NextStopStoreTests: XCTestCase {

    private var root: URL!
    private var tenant: String?

    private let shop = NextStopShop(uniqueId: "STR-BONAQUA",
                                    name: "Bon Aqua",
                                    fullAddress: "100 Yard Rd, Bon Aqua, TN, 37025")
    private let selectedAt = Date(timeIntervalSince1970: 1_792_000_000)

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("next-stop-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        tenant = "acme"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makeStore() throws -> NextStopStore {
        return try NextStopStore(rootDirectory: root, tenantKey: { [weak self] in self?.tenant })
    }

    // MARK: Round trip

    func testASelectedShopSurvivesAFreshStoreObject() throws {
        let writer = try makeStore()
        try writer.save(NextStopTransition.selectShop(shop, at: selectedAt))

        // A brand-new object = the app process iOS recreated behind the driver.
        let reader = try makeStore()

        XCTAssertEqual(reader.load(), .shopSelected(shop: shop, selectedAt: selectedAt))
    }

    func testArrivalSurvivesToo() throws {
        let store = try makeStore()
        let arrived = NextStopTransition.arrive(NextStopTransition.selectShop(shop, at: selectedAt),
                                                at: selectedAt.addingTimeInterval(900))
        try store.save(arrived)

        XCTAssertEqual(try makeStore().load(), arrived)
    }

    func testNothingSavedReadsAsIdle() throws {
        XCTAssertEqual(try makeStore().load(), .idle)
    }

    func testClearReturnsToIdle() throws {
        let store = try makeStore()
        try store.save(NextStopTransition.selectShop(shop, at: selectedAt))

        try store.clear()

        XCTAssertEqual(store.load(), .idle)
        XCTAssertEqual(try makeStore().load(), .idle, "Cleared on disk, not just in memory.")
    }

    // MARK: Location on disk

    func testTheStateLivesUnderNextStopPerTenant() throws {
        let store = try makeStore()
        try store.save(NextStopTransition.selectShop(shop, at: selectedAt))

        let expected = root
            .appendingPathComponent("next-stop", isDirectory: true)
            .appendingPathComponent("acme", isDirectory: true)
            .appendingPathComponent("state.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path),
                      "Expected the shop stop at next-stop/<tenant>/state.json")
        XCTAssertEqual(store.directory.lastPathComponent, "next-stop",
                       "It must keep its own directory — never inside operations, checklist contexts, terms or Dispatch packages.")
    }

    // MARK: Tenant isolation

    func testOneCompanysShopStopIsInvisibleToAnother() throws {
        let store = try makeStore()
        try store.save(NextStopTransition.selectShop(shop, at: selectedAt))
        XCTAssertEqual(store.load().shop, shop)

        tenant = "other-company"

        XCTAssertEqual(store.load(), .idle, "Another company must never see this shop stop.")

        // And writing as the other company cannot disturb the first one's file.
        try store.save(NextStopTransition.selectShop(
            NextStopShop(uniqueId: "STR-X", name: "Their Yard", fullAddress: "1 Elsewhere"), at: selectedAt))
        tenant = "acme"
        XCTAssertEqual(store.load().shop, shop)
    }

    // MARK: Signed out

    func testSignedOutReadsIdle() throws {
        let store = try makeStore()
        try store.save(NextStopTransition.selectShop(shop, at: selectedAt))

        tenant = nil

        XCTAssertEqual(store.load(), .idle)
    }

    func testSignedOutWriteIsRefused() throws {
        let store = try makeStore()
        tenant = nil

        XCTAssertThrowsError(try store.save(NextStopTransition.selectShop(shop, at: selectedAt))) { error in
            XCTAssertEqual(error as? NextStopStoreError, .noTenant)
        }
        XCTAssertThrowsError(try store.clear()) { error in
            XCTAssertEqual(error as? NextStopStoreError, .noTenant)
        }
    }

    func testAnEmptyTenantKeyIsTreatedAsSignedOut() throws {
        let store = try makeStore()
        tenant = ""

        XCTAssertEqual(store.load(), .idle)
        XCTAssertThrowsError(try store.save(NextStopTransition.selectShop(shop, at: selectedAt)))
    }

    // MARK: Damage

    func testACorruptedFileReadsAsIdleAndLeavesEverythingElseAlone() throws {
        let store = try makeStore()
        try store.save(NextStopTransition.selectShop(shop, at: selectedAt))

        // Something else in the sandbox that this store must never touch.
        let operations = root.appendingPathComponent("operations", isDirectory: true)
        try FileManager.default.createDirectory(at: operations, withIntermediateDirectories: true)
        let parked = operations.appendingPathComponent("op-1.json")
        try Data(#"{"id":"op-1"}"#.utf8).write(to: parked)

        let stateFile = root
            .appendingPathComponent("next-stop", isDirectory: true)
            .appendingPathComponent("acme", isDirectory: true)
            .appendingPathComponent("state.json")
        try Data("this is not json".utf8).write(to: stateFile)

        XCTAssertEqual(store.load(), .idle, "Unreadable state means no shop stop — never a crash.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: parked.path),
                      "Next Stop must never delete or rewrite Sync Engine operations.")

        // And it recovers: a fresh save overwrites the damaged file.
        try store.save(NextStopTransition.selectShop(shop, at: selectedAt))
        XCTAssertEqual(store.load().shop, shop)
    }
}
