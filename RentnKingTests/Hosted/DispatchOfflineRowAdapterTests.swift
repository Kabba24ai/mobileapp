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

    // MARK: - Review F2: the durable driver trip stage on the card

    /// An offline Sync Engine over a fresh directory, with the app's REAL driver-checklist handler.
    private func offlineEngine() throws -> SyncEngine {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SyncEngine(store: try FileSyncOperationStore(rootDirectory: dir), httpClient: OfflineClient(),
                          handlers: [DriverChecklistSyncHandler(hasSession: { true })],
                          policy: SyncRetryPolicy(backoffSchedule: [600]))
    }

    private func record(_ status: kDriverCheckListStatus, product: String, leg: String, on engine: SyncEngine) throws {
        try DriverChecklistSyncHandler.enqueue(into: engine, orderProductUniqueId: product, orderUniqueId: nil,
                                               equipmentFuel: "", callCustomer: "", equipmentKeyLocation: "",
                                               equipmentDriverStatus: status.rawValue, checklistType: leg)
    }

    func testLoadMapAndGoSavedOfflineShowsOnTheCachedCard() throws {
        let model = try XCTUnwrap(DispatchOfflineRowAdapter.schedulesModel(from: try fixtureRow()))
        let product = try XCTUnwrap(model.unique_id)
        let engine = try offlineEngine()
        XCTAssertNil(DriverStagePresentation.applying(DriverStageOverlay.from(engine.snapshot()), to: model, serverObservedAt: nil)
            .delivery_checklist?.ready_to_go_at, "nothing saved yet → the row as served")

        // The payload the app's handler really writes is what the overlay reads.
        try record(.kOnMyWay, product: product, leg: DriverChecklistLocalState.legDelivery, on: engine)
        let departed = DriverStagePresentation.applying(DriverStageOverlay.from(engine.snapshot()), to: model, serverObservedAt: nil)
        XCTAssertNotNil(departed.delivery_checklist?.ready_to_go_at, "green band / dark icon: On My Way")
        XCTAssertEqual(departed.delivery_checklist?.is_arrived, false)

        try record(.kArrived, product: product, leg: DriverChecklistLocalState.legDelivery, on: engine)
        let arrived = DriverStagePresentation.applying(DriverStageOverlay.from(engine.snapshot()), to: model, serverObservedAt: nil)
        XCTAssertEqual(arrived.delivery_checklist?.is_arrived, true)
        XCTAssertNotNil(arrived.delivery_checklist?.arrived_at)
        XCTAssertEqual(arrived.delivery_checklist?.call_customer, model.delivery_checklist?.call_customer,
                       "only the stage is overlaid; the rest of the row is untouched")
    }

    func testAnotherLegsOrProductsStageNeverShows() throws {
        let model = try XCTUnwrap(DispatchOfflineRowAdapter.schedulesModel(from: try fixtureRow()))
        let engine = try offlineEngine()
        try record(.kOnMyWay, product: try XCTUnwrap(model.unique_id), leg: DriverChecklistLocalState.legPickup, on: engine)
        try record(.kArrived, product: "ORD-SCH-SOMEONE-ELSE", leg: DriverChecklistLocalState.legDelivery, on: engine)

        let shown = DriverStagePresentation.applying(DriverStageOverlay.from(engine.snapshot()), to: model, serverObservedAt: nil)
        XCTAssertNil(shown.delivery_checklist?.ready_to_go_at)
        XCTAssertEqual(shown.delivery_checklist?.is_arrived, false)
    }

    // MARK: - Review F4: every request parameter is part of its scope

    func testEveryRequestParameterIsPartOfTheRequestsScope() {
        typealias P = DispatchListViewController.DispatchParameater
        let base = P(page: "1", schedule_type: "All", schedule_status: "Pending", category_id: "", search: "",
                     transport_mode: "Truck", date_filter: "All", driver_id: "4")
        var nextPage = base
        nextPage.page = "2"
        XCTAssertEqual(nextPage.feedScope, base.feedScope, "the next page is the same list")

        let changes: [(String, (inout P) -> Void)] = [
            ("driver", { $0.driver_id = "7" }), ("date", { $0.date_filter = "Today" }),
            ("category", { $0.category_id = "11" }), ("search", { $0.search = "Cash" }),
            ("transport", { $0.transport_mode = "Store" }), ("leg type", { $0.schedule_type = "Return" }),
            ("status", { $0.schedule_status = "Completed" }),
        ]
        for (what, change) in changes {
            var changed = base
            change(&changed)
            XCTAssertNotEqual(changed.feedScope, base.feedScope, what)
        }
    }

    func testTheNotDownloadedStateSaysSoInsteadOfNoResults() {
        let view = EmptyDataView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        view.dispatchNotDownloaded()
        let labels = view.allSubviewLabels().compactMap(\.text)
        XCTAssertTrue(labels.contains("Dispatch isn't downloaded to this phone yet"))
        XCTAssertFalse(labels.contains("No results found."))
    }

    // MARK: - Phase 6 locked rule (Gary, 2026-09-27): only ASSIGNED missions in normal Dispatch views

    private func listRow(_ uid: String, delivered: Bool, deliveryDriver: Int?, pickupDriver: Int?) throws -> SchedulesModel {
        let base = try fixtureRow()
        func employee(_ id: Int?) -> JSONValue {
            guard let id = id, case .object(var e)? = base["delivery_employee"] else { return .null }
            e["id"] = .number(Double(id))
            e["name"] = .string("Driver \(id)")
            return .object(e)
        }
        var row = setting(base, "unique_id", .string(uid))
        row = setting(row, "is_delivered", .bool(delivered))
        row = setting(row, "delivery_status", .string(delivered ? "Completed" : "Pending"))
        row = setting(row, "delivery_employee", employee(deliveryDriver))
        row = setting(row, "pickup_employee", employee(pickupDriver))
        return try XCTUnwrap(DispatchOfflineRowAdapter.schedulesModel(from: row))
    }

    /// The list screen's own filter (`rebuildRows`) — the ONE gate the live feed, the saved list and
    /// the offline cache all pass through: a named driver sees their assigned missions, All sees every
    /// assigned mission, and a mission whose ACTIVE leg has no driver is never shown.
    func testTheDispatchListShowsOnlyAssignedMissionsForEveryDriverAndAll() throws {
        let list = DispatchListViewController()   // the view is never loaded: no network, no feed request
        list.selectStatus = "1"
        list.arrDispatchList = [
            try listRow("P6-ASSIGNED-DELIVERY-A", delivered: false, deliveryDriver: 4, pickupDriver: nil),
            try listRow("P6-ASSIGNED-RETURN-B", delivered: true, deliveryDriver: 4, pickupDriver: 7),
            try listRow("P6-UNASSIGNED-DELIVERY", delivered: false, deliveryDriver: nil, pickupDriver: 7),
            try listRow("P6-UNASSIGNED-RETURN", delivered: true, deliveryDriver: 4, pickupDriver: nil),
        ]
        func shown(_ driver: String) -> [String] {
            list.selectDriverID = driver
            list.rebuildRows()
            return (0..<list.arrRows.count).compactMap { list.orderIndexForRow($0) }.map { list.arrDispatchList[$0].unique_id ?? "" }
        }
        XCTAssertEqual(Set(shown("")), ["P6-ASSIGNED-DELIVERY-A", "P6-ASSIGNED-RETURN-B"], "All: every assigned mission, no unassigned one")
        XCTAssertEqual(shown("4"), ["P6-ASSIGNED-DELIVERY-A"], "driver A: only the pending delivery assigned to them")
        XCTAssertEqual(shown("7"), ["P6-ASSIGNED-RETURN-B"], "driver B: only the return assigned to them")

        // The Completed history is out of scope: its membership is unchanged.
        list.selectStatus = "2"
        XCTAssertEqual(shown("").count, 4, "Completed + All: every row, as before")
        XCTAssertEqual(Set(shown("4")), ["P6-ASSIGNED-DELIVERY-A", "P6-UNASSIGNED-DELIVERY", "P6-UNASSIGNED-RETURN"],
                       "Completed + a named driver: the pre-Phase-6 rule")
    }
}

private final class OfflineClient: SyncHTTPClient {
    func perform(_ request: SyncHTTPRequest, completion: @escaping (SyncHTTPResult) -> Void) {
        completion(.failure(APIError.transport(.offline, description: "hosted test: offline")))
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
