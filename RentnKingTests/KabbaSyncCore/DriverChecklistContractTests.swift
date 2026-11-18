import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// D5 (Driver Delivery Process Flow, 2026-09-27): the shared Laravel fixtures
/// carry the equipment identity on every driver-checklist block and the yard's
/// fuel / key predicates on every equipment block. Decoded from the SAME files
/// the Laravel suite generates (Scripts/sync-contract-fixtures.sh), so a
/// contract drift on either side fails here first.
final class DriverChecklistContractTests: XCTestCase {

    private func fixtureJSON(_ name: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheMixedFeedRowsCarryTheEquipmentIdentityOnBothChecklistBlocks() throws {
        let orders = try XCTUnwrap(try fixtureJSON("dispatch_list_mixed")["orders"] as? [[String: Any]])
        let row = try XCTUnwrap(orders.first { $0["delivery_checklist"] != nil })
        let delivery = try XCTUnwrap(row["delivery_checklist"] as? [String: Any])
        let pickup = try XCTUnwrap(row["pickup_checklist"] as? [String: Any])

        XCTAssertTrue(delivery.keys.contains("equipment_unique_id"), "delivery_checklist.equipment_unique_id is part of the contract (null when never recorded)")
        XCTAssertTrue(pickup.keys.contains("equipment_unique_id"))
    }

    func testTheOfflinePackageCarriesTheIdentityAndTheYardPredicates() throws {
        let body = try fixtureJSON("dispatch_offline_packages")
        let packages = try XCTUnwrap((body["data"] as? [String: Any])?["packages"] as? [[String: Any]])
        let dispatch = try XCTUnwrap(packages.first?["dispatch"] as? [String: Any])
        let row = try XCTUnwrap(dispatch["row"] as? [String: Any])
        let equipment = try XCTUnwrap(dispatch["equipment"] as? [String: Any])

        // The fixture's mission has a unit assigned and the driver's answers recorded for it.
        let checklist = try XCTUnwrap(row["delivery_checklist"] as? [String: Any])
        let identity = try XCTUnwrap(checklist["equipment_unique_id"] as? String)
        XCTAssertEqual(identity, equipment["unique_id"] as? String, "the recorded identity is the assigned unit")

        XCTAssertNotNil(equipment["requires_fuel_check"] as? Bool)
        XCTAssertNotNil(equipment["requires_key_check"] as? Bool)
        let rowEquipment = try XCTUnwrap(row["equipment"] as? [String: Any])
        XCTAssertEqual(rowEquipment["requires_fuel_check"] as? Bool, equipment["requires_fuel_check"] as? Bool, "the feed row and the package block agree")
        XCTAssertEqual(rowEquipment["requires_key_check"] as? Bool, equipment["requires_key_check"] as? Bool)
        // The broader display flags stay beside them.
        XCTAssertNotNil(equipment["is_fuel"] as? Bool)
        XCTAssertNotNil(equipment["is_key"] as? Bool)
    }
}
