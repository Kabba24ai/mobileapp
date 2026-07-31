//
//  QueueLineModelTests.swift
//  RentnKingTests
//
//  Unit tests for the Queue Line data models (ObjectMapper mapping).
//  Pure, deterministic — no app/network state required.
//

import XCTest
import ObjectMapper
@testable import RentnKing

final class QueueLineModelTests: XCTestCase {

    /// A representative grouped item as returned by api/admin/v1/queue-line.
    private let sampleJSON: [String: Any] = [
        "order_product_unique_id": "opu-1",
        "order_number": "#3324",
        "customer_name": "Dylan Hunt",
        "status": "staged",
        "staged": true,
        "is_fast_track": true,
        "urgency": "rush",
        "staged_by": "Garry",
        "staged_at": "2026-07-20T21:41:06-05:00",
        "product": [
            "unique_id": "p-1",
            "name": "Zero Turn Residential",
            "image_url": "https://example.com/img.png"
        ],
        "equipment": [
            "unique_id": "eq-1",
            "display_id": "SPA-ZT-1",
            "name": "Spartan Shield HD",
            "status": "maintenance",
            "status_label": "Maint. Hold",
            "is_fuel": true,
            "is_key": false
        ]
    ]

    func testMapsTopLevelFields() throws {
        let model = try XCTUnwrap(QueueLineModel(JSON: sampleJSON), "mapping should succeed")
        XCTAssertEqual(model.order_product_unique_id, "opu-1")
        XCTAssertEqual(model.order_number, "#3324")
        XCTAssertEqual(model.customer_name, "Dylan Hunt")
        XCTAssertEqual(model.status, "staged")
        XCTAssertEqual(model.staged, true)
        XCTAssertEqual(model.is_fast_track, true)
        XCTAssertEqual(model.urgency, "rush")
        XCTAssertEqual(model.staged_by, "Garry")
        XCTAssertEqual(model.staged_at, "2026-07-20T21:41:06-05:00")
    }

    func testMapsNestedProduct() throws {
        let model = try XCTUnwrap(QueueLineModel(JSON: sampleJSON))
        XCTAssertEqual(model.product?.name, "Zero Turn Residential")
        XCTAssertEqual(model.product?.image_url, "https://example.com/img.png")
    }

    func testMapsNestedEquipment() throws {
        let model = try XCTUnwrap(QueueLineModel(JSON: sampleJSON))
        XCTAssertEqual(model.equipment?.unique_id, "eq-1")
        XCTAssertEqual(model.equipment?.display_id, "SPA-ZT-1")
        XCTAssertEqual(model.equipment?.name, "Spartan Shield HD")
        XCTAssertEqual(model.equipment?.status, "maintenance")
        XCTAssertEqual(model.equipment?.status_label, "Maint. Hold")
        XCTAssertEqual(model.equipment?.is_fuel, true)
        XCTAssertEqual(model.equipment?.is_key, false)
    }

    /// An empty payload must map to a valid object with nil fields — never crash.
    func testEmptyPayloadDoesNotCrash() {
        let model = QueueLineModel(JSON: [:])
        XCTAssertNotNil(model)
        XCTAssertNil(model?.order_number)
        XCTAssertNil(model?.equipment)
        XCTAssertNil(model?.is_fast_track)
    }

    /// A completed item is detected by status == "completed" OR completed == true
    /// (the same rule the board uses to place cards and hide the thumb).
    func testCompletedDetection() throws {
        let byStatus = try XCTUnwrap(QueueLineModel(JSON: ["status": "completed"]))
        let byFlag   = try XCTUnwrap(QueueLineModel(JSON: ["completed": true]))
        XCTAssertTrue((byStatus.status ?? "") == "completed" || byStatus.completed == true)
        XCTAssertTrue((byFlag.status ?? "") == "completed" || byFlag.completed == true)
    }
}
