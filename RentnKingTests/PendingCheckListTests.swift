//
//  PendingCheckListTests.swift
//  RentnKingTests
//
//  Focused tests for the Pending (prepare-before-arrival) Delivery Checklist storage added in
//  CheckListFile.swift. These verify the state model in isolation:
//    • Save persists checklist data (order + per-product "other" data).
//    • Save creates a PENDING record — NOT a Completed one (never writes the completed key).
//    • Repeated Save updates the same record (no duplicates / idempotent).
//    • Reopening loads the saved values.
//    • Delivery and Return are isolated (this feature is delivery-only).
//    • Failed/empty Save stores nothing and returns false.
//    • Clearing (finalization) removes the record so it never reloads as pending.
//
//  Persistence uses the app's SDKUserDefault store, so these run against the app test host.
//

import XCTest
import ObjectMapper
@testable import RentnKing

final class PendingCheckListTests: XCTestCase {

    // A unique order id per run so tests never collide with real/cached data.
    private let uid = "pending-test-order-\(UUID().uuidString)"

    private func makeOrder(id: Int) -> OrdersModel {
        return OrdersModel(JSON: ["id": id, "products": [["id": id]]])!
    }

    private func makeOther(startHours: Float) -> NoteModel {
        let n = NoteModel()
        n.startHours = startHours
        return n
    }

    override func tearDown() {
        clearPendingCheckList(orderUniqueId: uid, isDelivery: true)
        clearPendingCheckList(orderUniqueId: uid, isDelivery: false)
        super.tearDown()
    }

    // MARK: - Save persists / reopening loads

    func testSavePersistsOrderAndOtherData() {
        let ok = savePendingCheckList(orderUniqueId: uid, isDelivery: true,
                                      objOrderData: makeOrder(id: 111),
                                      arrOtherData: [makeOther(startHours: 42)])
        XCTAssertTrue(ok, "Save with valid inputs should succeed")
        XCTAssertTrue(hasPendingCheckList(orderUniqueId: uid, isDelivery: true))

        let loaded = getPendingCheckList(orderUniqueId: uid, isDelivery: true)
        XCTAssertNotNil(loaded, "Reopening should load the saved pending checklist")
        XCTAssertEqual(loaded?.order.id, 111)
        XCTAssertEqual(loaded?.other.first?.startHours, 42)
    }

    // MARK: - Pending is NOT Completed

    func testSaveDoesNotMarkChecklistCompleted() {
        _ = savePendingCheckList(orderUniqueId: uid, isDelivery: true,
                                 objOrderData: makeOrder(id: 1), arrOtherData: [])
        // The completed marker keyed "kCheckListOrderDetailsData_Delivery_<uid>" must NOT exist.
        XCTAssertFalse(isCheckListOrderDetailSaved(strOrderUniqeID: "Delivery_\(uid)"),
                       "Pending Save must never create the completed-checklist marker")
    }

    // MARK: - Idempotent update (no duplicates)

    func testRepeatedSaveUpdatesSameRecord() {
        _ = savePendingCheckList(orderUniqueId: uid, isDelivery: true,
                                 objOrderData: makeOrder(id: 1), arrOtherData: [makeOther(startHours: 2310)])
        _ = savePendingCheckList(orderUniqueId: uid, isDelivery: true,
                                 objOrderData: makeOrder(id: 1), arrOtherData: [makeOther(startHours: 2311)])

        let loaded = getPendingCheckList(orderUniqueId: uid, isDelivery: true)
        XCTAssertEqual(loaded?.other.count, 1, "Re-saving updates in place, never appends a duplicate")
        XCTAssertEqual(loaded?.other.first?.startHours, 2311, "Latest value wins")
    }

    // MARK: - Delivery / Return isolation

    func testDeliveryAndReturnAreIsolated() {
        _ = savePendingCheckList(orderUniqueId: uid, isDelivery: true,
                                 objOrderData: makeOrder(id: 1), arrOtherData: [])
        XCTAssertTrue(hasPendingCheckList(orderUniqueId: uid, isDelivery: true))
        XCTAssertFalse(hasPendingCheckList(orderUniqueId: uid, isDelivery: false),
                       "Saving a Delivery draft must not create a Return draft")
    }

    // MARK: - Failure / empty guard

    func testEmptyOrderIdSavesNothing() {
        let ok = savePendingCheckList(orderUniqueId: "", isDelivery: true,
                                      objOrderData: makeOrder(id: 1), arrOtherData: [])
        XCTAssertFalse(ok, "Save with an empty order id should fail")
        XCTAssertFalse(hasPendingCheckList(orderUniqueId: "", isDelivery: true))
    }

    func testNilOrderDataSavesNothing() {
        let ok = savePendingCheckList(orderUniqueId: uid, isDelivery: true,
                                      objOrderData: nil, arrOtherData: [])
        XCTAssertFalse(ok, "Save with nil order data should fail")
        XCTAssertFalse(hasPendingCheckList(orderUniqueId: uid, isDelivery: true))
    }

    // MARK: - Clear (finalization)

    func testClearRemovesPending() {
        _ = savePendingCheckList(orderUniqueId: uid, isDelivery: true,
                                 objOrderData: makeOrder(id: 1), arrOtherData: [makeOther(startHours: 5)])
        XCTAssertTrue(hasPendingCheckList(orderUniqueId: uid, isDelivery: true))

        clearPendingCheckList(orderUniqueId: uid, isDelivery: true)
        XCTAssertFalse(hasPendingCheckList(orderUniqueId: uid, isDelivery: true),
                       "After finalization the pending draft must be gone")
        XCTAssertNil(getPendingCheckList(orderUniqueId: uid, isDelivery: true))
    }
}
