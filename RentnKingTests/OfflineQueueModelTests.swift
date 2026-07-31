//
//  OfflineQueueModelTests.swift
//  RentnKingTests
//
//  Unit tests for the offline-sync queue models, including the `attempts` retry
//  counter added so a permanently-rejected item can't block the queue forever.
//

import XCTest
import ObjectMapper
@testable import RentnKing

final class OfflineQueueModelTests: XCTestCase {

    // MARK: Driver checklist

    func testDriverChecklistMapsAllFields() throws {
        let json: [String: Any] = [
            "id": 1_700_000_000,
            "order_product_unique_id": "opu-9",
            "equipment_fuel": "Full",
            "equipment_key_location": "With Machine",
            "equipment_driver_status": "ok",
            "status": "Pending",
            "checklist_type": "delivery",
            "attempts": 2
        ]
        let m = try XCTUnwrap(DriverChecklistSubmitModel(JSON: json))
        XCTAssertEqual(m.id, 1_700_000_000)
        XCTAssertEqual(m.order_product_unique_id, "opu-9")
        XCTAssertEqual(m.equipment_fuel, "Full")
        XCTAssertEqual(m.equipment_key_location, "With Machine")
        XCTAssertEqual(m.equipment_driver_status, "ok")
        XCTAssertEqual(m.status, "Pending")
        XCTAssertEqual(m.checklist_type, "delivery")
        XCTAssertEqual(m.attempts, 2)
    }

    /// A fresh item has no attempts recorded (nil), which the retry logic treats as 0.
    func testDriverChecklistFreshItemHasNoAttempts() throws {
        let m = try XCTUnwrap(DriverChecklistSubmitModel(JSON: ["id": 1]))
        XCTAssertNil(m.attempts)
    }

    // MARK: Delivery / pickup inputs

    func testDeliveryPickupInputsMapsAllFields() throws {
        let json: [String: Any] = [
            "id": 42,
            "order_product_unique_id": "opu-7",
            "type": "pickup",
            "inputs_date": "2026-07-24 09:00:00",
            "tnc_status": "1",
            "drivers_license_status": "1",
            "video_status": "0",
            "checklist_status": "1",
            "status": "Pending",
            "attempts": 1
        ]
        let m = try XCTUnwrap(DeliveryPickupInputsSubmitModel(JSON: json))
        XCTAssertEqual(m.id, 42)
        XCTAssertEqual(m.order_product_unique_id, "opu-7")
        XCTAssertEqual(m.type, "pickup")
        XCTAssertEqual(m.inputs_date, "2026-07-24 09:00:00")
        XCTAssertEqual(m.video_status, "0")
        XCTAssertEqual(m.status, "Pending")
        XCTAssertEqual(m.attempts, 1)
    }

    /// The retry cap that dead-letters a stuck item is a positive number.
    func testMaxSyncAttemptsIsSane() {
        XCTAssertGreaterThan(kMaxSyncAttempts, 0)
    }
}
