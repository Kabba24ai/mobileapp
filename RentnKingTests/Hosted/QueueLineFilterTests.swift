//
//  QueueLineFilterTests.swift
//  RentnKingHostedTests — runs inside the RentnKing app (Simulator or device)
//
//  Queue Line filters (2026-09-13): Delivery Store (sticky) AND Type; the
//  remembered store resolves against the live store list and falls back to
//  All when that store is gone; All itself is remembered.
//

import XCTest
@testable import RentnKing

final class QueueLineFilterTests: XCTestCase {

    private let bonAqua = QueueLineFilterStore(uniqueId: "STO-BA", name: "Bon Aqua")
    private let waverly = QueueLineFilterStore(uniqueId: "STO-WV", name: "Waverly")

    // MARK: - Type

    func testTypeUsesTheSamePredicateAsTheCardIcon() {
        XCTAssertTrue(QueueLineTypeFilter.truck.matches(transportMode: "Truck"))
        XCTAssertFalse(QueueLineTypeFilter.truck.matches(transportMode: "Store"))
        XCTAssertTrue(QueueLineTypeFilter.store.matches(transportMode: "Store"))
        XCTAssertFalse(QueueLineTypeFilter.store.matches(transportMode: "Truck"))
        // A feed that omitted the mode shows the truck icon, so the Truck filter keeps it.
        XCTAssertTrue(QueueLineTypeFilter.truck.matches(transportMode: nil))
        XCTAssertFalse(QueueLineTypeFilter.store.matches(transportMode: nil))
        for mode: String? in [nil, "Truck", "Store"] { XCTAssertTrue(QueueLineTypeFilter.all.matches(transportMode: mode)) }
        XCTAssertEqual(QueueLineTypeFilter.allCases.map(\.title), ["All", "Truck", "In Store"])
    }

    // MARK: - Store AND Type

    func testStoreAndTypeCombineWithAnd() {
        let bonAquaTruck = QueueLineFilter(storeUniqueId: "STO-BA", type: .truck)
        XCTAssertTrue(bonAquaTruck.includes(storeUniqueId: "STO-BA", transportMode: "Truck"))
        XCTAssertFalse(bonAquaTruck.includes(storeUniqueId: "STO-BA", transportMode: "Store"), "wrong type")
        XCTAssertFalse(bonAquaTruck.includes(storeUniqueId: "STO-WV", transportMode: "Truck"), "wrong store")
        XCTAssertFalse(bonAquaTruck.includes(storeUniqueId: nil, transportMode: "Truck"), "no store attribution never matches a store filter")

        let anyStoreTruck = QueueLineFilter(storeUniqueId: nil, type: .truck)
        XCTAssertTrue(anyStoreTruck.includes(storeUniqueId: "STO-WV", transportMode: "Truck"))
        XCTAssertFalse(anyStoreTruck.includes(storeUniqueId: "STO-WV", transportMode: "Store"))

        let waverlyStore = QueueLineFilter(storeUniqueId: "STO-WV", type: .store)
        XCTAssertTrue(waverlyStore.includes(storeUniqueId: "STO-WV", transportMode: "Store"))
        XCTAssertFalse(waverlyStore.includes(storeUniqueId: "STO-BA", transportMode: "Store"))

        let everything = QueueLineFilter()
        XCTAssertFalse(everything.isActive)
        XCTAssertTrue(everything.includes(storeUniqueId: nil, transportMode: nil))
        XCTAssertTrue(QueueLineFilter(storeUniqueId: "STO-BA", type: .all).isActive)
        XCTAssertTrue(QueueLineFilter(storeUniqueId: nil, type: .store).isActive)
    }

    // MARK: - Active-filter line + empty scope wording

    func testActiveFilterLineNamesBothFilters() {
        XCTAssertEqual(QueueLineFilter.storeLine(name: "Bon Aqua"), "Delivery Store: Bon Aqua")
        XCTAssertEqual(QueueLineFilter.storeLine(name: "All"), "Delivery Store: All")
        XCTAssertEqual(QueueLineFilter(storeUniqueId: nil, type: .store).typeLine, "Type: In Store")
        XCTAssertEqual(QueueLineFilter().typeLine, "Type: All")
    }

    func testEmptyScopeWordingSaysWhyTheLaneIsEmpty() {
        XCTAssertNil(QueueLineFilter().emptyMessage(lane: "pending", storeName: "All"), "no filter → the lane's own wording")
        XCTAssertEqual(QueueLineFilter(storeUniqueId: "STO-BA", type: .truck).emptyMessage(lane: "pending", storeName: "Bon Aqua"),
                       "Nothing pending for Bon Aqua · Truck. Change the filter to see other stores or types.")
        XCTAssertEqual(QueueLineFilter(storeUniqueId: nil, type: .store).emptyMessage(lane: "staged", storeName: "All"),
                       "Nothing staged for all stores · In Store. Change the filter to see other stores or types.")
        XCTAssertEqual(QueueLineFilter(storeUniqueId: "STO-WV", type: .all).emptyMessage(lane: "completed today", storeName: "Waverly"),
                       "Nothing completed today for Waverly. Change the filter to see other stores or types.")
    }

    // MARK: - Remembered store resolution

    func testNothingRememberedMeansAll() {
        for id: String? in [nil, ""] {
            let r = QueueLineStoreMemory.resolve(rememberedId: id, rememberedName: "stale", stores: [bonAqua, waverly])
            XCTAssertEqual(r, .init(storeUniqueId: nil, name: "All", forgotten: false))
        }
    }

    func testARememberedActiveStoreResolvesToItsCurrentName() {
        let r = QueueLineStoreMemory.resolve(rememberedId: "STO-WV", rememberedName: "Old Name", stores: [bonAqua, waverly])
        XCTAssertEqual(r, .init(storeUniqueId: "STO-WV", name: "Waverly", forgotten: false))
    }

    func testARememberedStoreMissingFromTheLiveListFallsBackToAll() {
        let r = QueueLineStoreMemory.resolve(rememberedId: "STO-GONE", rememberedName: "Closed Store", stores: [bonAqua, waverly])
        XCTAssertEqual(r, .init(storeUniqueId: nil, name: "All", forgotten: true))
    }

    func testWithNoStoreListYetTheRememberedStoreIsKeptAndNamedFromTheFeedOrMemory() {
        let fromFeed = QueueLineStoreMemory.resolve(rememberedId: "STO-BA", rememberedName: nil, stores: [], feedStores: [bonAqua])
        XCTAssertEqual(fromFeed, .init(storeUniqueId: "STO-BA", name: "Bon Aqua", forgotten: false))
        let fromMemory = QueueLineStoreMemory.resolve(rememberedId: "STO-BA", rememberedName: "Bon Aqua", stores: [], feedStores: [])
        XCTAssertEqual(fromMemory, .init(storeUniqueId: "STO-BA", name: "Bon Aqua", forgotten: false))
        let nameless = QueueLineStoreMemory.resolve(rememberedId: "STO-BA", rememberedName: nil, stores: [], feedStores: [])
        XCTAssertEqual(nameless, .init(storeUniqueId: "STO-BA", name: "Selected store", forgotten: false))
    }

    func testTwoStoresWithTheSameNameAreToldApartByTheirId() {
        let waverly2 = QueueLineFilterStore(uniqueId: "STO-WV2", name: "Waverly")
        let r = QueueLineStoreMemory.resolve(rememberedId: "STO-WV2", rememberedName: "Waverly", stores: [bonAqua, waverly, waverly2])
        XCTAssertEqual(r.storeUniqueId, "STO-WV2")
        XCTAssertTrue(QueueLineFilter(storeUniqueId: "STO-WV2", type: .all).includes(storeUniqueId: "STO-WV2", transportMode: "Truck"))
        XCTAssertFalse(QueueLineFilter(storeUniqueId: "STO-WV2", type: .all).includes(storeUniqueId: "STO-WV", transportMode: "Truck"))
    }

    // MARK: - Persistence (the app's UserDefaults convention)

    func testTheStoreChoiceIsRememberedByIdAndAllIsRememberedExplicitly() throws {
        let suite = "QueueLineFilterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(QueueLineStoreMemory.remembered(in: defaults).id, "never chosen")

        QueueLineStoreMemory.remember(storeUniqueId: "STO-BA", name: "Bon Aqua", in: defaults)
        var memory = QueueLineStoreMemory.remembered(in: defaults)
        XCTAssertEqual(memory.id, "STO-BA")
        XCTAssertEqual(memory.name, "Bon Aqua")

        QueueLineStoreMemory.remember(storeUniqueId: nil, name: "All", in: defaults)
        memory = QueueLineStoreMemory.remembered(in: defaults)
        XCTAssertEqual(memory.id, "", "All is an explicit, remembered choice — not an absent one")
        XCTAssertEqual(QueueLineStoreMemory.resolve(rememberedId: memory.id, rememberedName: memory.name, stores: [bonAqua]).storeUniqueId, nil)
    }
}
