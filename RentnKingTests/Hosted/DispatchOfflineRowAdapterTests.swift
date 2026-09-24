//
//  DispatchOfflineRowAdapterTests.swift
//  RentnKingHostedTests — runs inside the RentnKing app (Simulator or device)
//
//  Dispatch offline (Phase 3): a cached package's dispatch.row maps through
//  the UNCHANGED SchedulesModel exactly like a live Dispatch feed row, so the
//  Dispatch card, Driver Checklist and Assign Driver screen see the same data
//  offline. Uses the shared Laravel fixture (dispatch_offline_packages.json).
//

import XCTest
import Foundation
@testable import RentnKing

final class DispatchOfflineRowAdapterTests: XCTestCase {

    private func fixtureRow() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KabbaSyncCore/Fixtures/dispatch_offline_packages.json")
        let root = try XCTUnwrap(JSONValue.parse(try Data(contentsOf: url)))
        return try XCTUnwrap(root["data"]?["packages"]?.arrayValue?.first?["dispatch"]?["row"])
    }

    private func setting(_ row: JSONValue, _ key: String, _ value: JSONValue) -> JSONValue {
        guard case .object(var object) = row else { return row }
        object[key] = value
        return .object(object)
    }

    func testTheCachedRowMapsEveryFieldTheDispatchCardReads() throws {
        let row = try fixtureRow()
        let model = try XCTUnwrap(DispatchOfflineRowAdapter.schedulesModel(from: row))

        XCTAssertEqual(model.id, row["id"]?.intValue)
        XCTAssertEqual(model.unique_id, row["unique_id"]?.stringValue)
        XCTAssertEqual(model.product_name, "Skid Steer")
        XCTAssertEqual(model.sort_key, row["sort_key"]?.stringValue)
        XCTAssertEqual(model.fulfillment_leg, "delivery")
        XCTAssertEqual(model.is_delivered, false)
        XCTAssertEqual(model.delivery_transport_mode, "Truck")
        // Server-formatted display strings — the phone cannot reproduce the env date format.
        XCTAssertEqual(model.delivery_date, row["delivery_date"]?.stringValue)
        XCTAssertEqual(model.delivery_time, row["delivery_time"]?.stringValue)

        // Card header, call button, End Point.
        XCTAssertEqual(model.order?.id, row["order"]?["id"]?.intValue)
        XCTAssertEqual(model.order?.order_number, "1650")
        XCTAssertEqual(model.order?.customer_name, "Cody Cash")
        XCTAssertEqual(model.order?.customer_phone, "555-0199")
        XCTAssertEqual(model.order?.objDeliveryAddress?.full_address, "12 Farm Road, Clarksville, TN, 37040")

        // Start Point + Driver Checklist fuel/keys segments.
        XCTAssertEqual(model.objEquipment?.equipment_store?.name, "HQ")
        XCTAssertEqual(model.objEquipment?.is_fuel, true)
        XCTAssertEqual(model.objEquipment?.is_key, false)

        // Assign Driver: both legs' employees.
        XCTAssertEqual(model.delivery_employee?.name, "Gary Driver")
        XCTAssertEqual(model.pickup_employee?.name, "Blake Driver")

        // Green band / Screen 2 restore: driver-checklist progress from server truth.
        XCTAssertEqual(model.delivery_checklist?.equipment_fuel, "Full")
        XCTAssertEqual(model.delivery_checklist?.call_customer, "Yes")
        XCTAssertEqual(model.delivery_checklist?.driver_checks, [1, 2])
        XCTAssertEqual(model.delivery_checklist?.is_arrived, false)
        XCTAssertNil(model.delivery_checklist?.ready_to_go_at)

        XCTAssertNotNil(model.objProduct, "product options for Screen 2")
    }

    func testTheDerivedOverdueFlagReachesTheCard() throws {
        let row = setting(try fixtureRow(), "is_delivery_overdue", .bool(true))
        XCTAssertEqual(DispatchOfflineRowAdapter.schedulesModel(from: row)?.is_delivery_overdue, true)
    }

    func testANullUnitOrEmployeeMapsToNil() throws {
        var row = setting(try fixtureRow(), "equipment", .null)
        row = setting(row, "pickup_employee", .null)
        let model = try XCTUnwrap(DispatchOfflineRowAdapter.schedulesModel(from: row))
        XCTAssertNil(model.objEquipment)
        XCTAssertNil(model.pickup_employee)
        XCTAssertEqual(model.delivery_employee?.name, "Gary Driver")
    }

    func testANonObjectRowIsRejected() {
        XCTAssertNil(DispatchOfflineRowAdapter.schedulesModel(from: .null))
        XCTAssertNil(DispatchOfflineRowAdapter.schedulesModel(from: .array([])))
    }

    func testTheNotDownloadedStateSaysSoInsteadOfNoResults() {
        let view = EmptyDataView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        view.dispatchNotDownloaded()
        let labels = view.allSubviewLabels().compactMap(\.text)
        XCTAssertTrue(labels.contains("Dispatch isn't downloaded to this phone yet"))
        XCTAssertFalse(labels.contains("No results found."))
    }
}

private extension UIView {
    func allSubviewLabels() -> [UILabel] {
        subviews.flatMap { sub -> [UILabel] in
            let own: [UILabel] = (sub as? UILabel).map { [$0] } ?? []
            return own + sub.allSubviewLabels()
        }
    }
}
