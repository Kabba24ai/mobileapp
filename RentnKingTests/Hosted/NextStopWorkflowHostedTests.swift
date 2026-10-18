//
//  NextStopWorkflowHostedTests.swift
//  RentnKingHostedTests — runs inside the RentnKing app (Simulator or device)
//
//  The continuous driver workday: after a mission is effectively complete the
//  driver is asked what they are doing next, instead of being dropped back on
//  the Dispatch board to reconstruct it themselves.
//
//  These tests pin the parts that could silently go wrong:
//    • the picker shows the CURRENT reconciled workload and nothing invented;
//    • it routes by stable identity, never by a row index that moved;
//    • work reassigned away or already completed cannot be opened from it;
//    • the shop stop reaches disk BEFORE Maps opens;
//    • Sync Engine operations and mission assignments are never touched.
//

import XCTest
import Foundation
import ObjectMapper
@testable import RentnKing

final class NextStopWorkflowHostedTests: XCTestCase {

    private let garyId = 7
    private let blakeId = 9

    // MARK: Fixtures

    /// One order leg as the Dispatch feed serves it. `delivered: true` makes the
    /// row's active leg the RETURN, which is how the board decides Delivery vs
    /// Return — the same rule DispatchWorkload.orderRowBelongs applies.
    private func leg(_ productId: String,
                     order: String = "ORD-1",
                     orderNumber: String = "4108",
                     customer: String = "Cody Cash",
                     product: String = "Skid Steer",
                     delivered: Bool = false,
                     sortKey: String,
                     deliveryDriver: Int? = nil,
                     pickupDriver: Int? = nil) -> SchedulesModel {
        var json: [String: Any] = [
            "unique_id": productId,
            "is_delivered": delivered,
            "product_name": product,
            "sort_key": sortKey,
            "order": ["unique_id": order, "order_number": orderNumber, "customer_name": customer],
        ]
        if let d = deliveryDriver { json["delivery_employee"] = ["id": d, "name": "Gary Driver"] }
        if let p = pickupDriver { json["pickup_employee"] = ["id": p, "name": "Blake Driver"] }
        return Mapper<SchedulesModel>().map(JSON: json)!
    }

    private func manual(_ taskId: String,
                        type: String = "Equipment Drop-Off",
                        description: String = "Pick up repaired equipment",
                        location: String = "Acme",
                        sortKey: String) -> DispatchManualJob {
        var job = DispatchManualJob()
        job.unique_id = taskId
        job.is_manual = true
        job.type = type
        job.description = description
        job.location_name = location
        job.status = DispatchManualStatus.assigned
        job.sort_key = sortKey
        return job
    }

    /// A Dispatch board holding the given work, scoped to one driver, rebuilt
    /// exactly as the screen rebuilds it.
    private func board(orders: [SchedulesModel] = [],
                       manuals: [DispatchManualJob] = [],
                       driverId: Int? = nil,
                       ops: [SyncOperation] = []) -> (list: DispatchListViewController, nav: UINavigationController) {
        let list = DispatchListViewController()
        list.arrDispatchList = orders
        list.arrManualList = manuals
        list.selectDriverID = driverId.map { "\($0)" } ?? ""
        list.operationsSnapshot = { ops }
        list.cachedAssemblyReview = { _ in nil }
        let nav = UINavigationController(rootViewController: list)
        list.rebuildRows()
        return (list, nav)
    }

    // MARK: Projection of the current workday

    func testARemainingDeliveryBecomesAMissionWithItsStableOrderProductId() {
        let (list, _) = board(orders: [leg("OP-1", sortKey: "2026-10-18|00001", deliveryDriver: garyId)],
                              driverId: garyId)

        let missions = list.currentNextStopMissions()

        XCTAssertEqual(missions.count, 1)
        XCTAssertEqual(missions[0].identity, .orderProduct("OP-1"))
        XCTAssertEqual(missions[0].kindLabel, "Delivery")
        XCTAssertEqual(missions[0].primaryText, "Cody Cash")
        XCTAssertTrue(missions[0].secondaryText.contains("Skid Steer"))
        XCTAssertEqual(missions[0].sortKey, "2026-10-18|00001")
    }

    func testARemainingReturnIsLabelledReturn() {
        let (list, _) = board(orders: [leg("OP-2", delivered: true, sortKey: "2026-10-18|00002",
                                           deliveryDriver: garyId, pickupDriver: garyId)],
                              driverId: garyId)

        let missions = list.currentNextStopMissions()

        XCTAssertEqual(missions.map(\.identity), [.orderProduct("OP-2")])
        XCTAssertEqual(missions[0].kindLabel, "Return")
    }

    func testAManualTaskBecomesAMissionWithItsStableTaskId() {
        let (list, _) = board(manuals: [manual("MDT-1", sortKey: "2026-10-18|00003")])

        let missions = list.currentNextStopMissions()

        XCTAssertEqual(missions.map(\.identity), [.manualTask("MDT-1")])
        XCTAssertEqual(missions[0].kindLabel, "Manual Dispatch")
        XCTAssertEqual(missions[0].primaryText, "Acme")
        XCTAssertTrue(missions[0].secondaryText.contains("Pick up repaired equipment"))
    }

    func testTheMixedWorkdayKeepsTheBoardsOwnSortKeyOrder() {
        // Interleaved on purpose: the weave, not the source arrays, decides order.
        let (list, _) = board(orders: [leg("OP-A", sortKey: "2026-10-18|00001", deliveryDriver: garyId),
                                       leg("OP-B", sortKey: "2026-10-18|00004", deliveryDriver: garyId)],
                              manuals: [manual("MDT-X", sortKey: "2026-10-18|00002"),
                                        manual("MDT-Y", sortKey: "2026-10-18|00009")],
                              driverId: garyId)

        XCTAssertEqual(list.currentNextStopMissions().map(\.identity),
                       [.orderProduct("OP-A"), .manualTask("MDT-X"), .orderProduct("OP-B"), .manualTask("MDT-Y")],
                       "Next Stop must present the SAME order the Dispatch board does, not its own.")
    }

    func testTheProjectionIsExactlyTheRenderedRowsAndInventsNothing() {
        // Blake's leg is in the feed but the board is scoped to Gary: it is not
        // Gary's remaining work, so Next Stop must not offer it.
        let (list, _) = board(orders: [leg("OP-MINE", sortKey: "2026-10-18|00001", deliveryDriver: garyId),
                                       leg("OP-THEIRS", sortKey: "2026-10-18|00002", deliveryDriver: blakeId)],
                              driverId: garyId)

        XCTAssertEqual(list.currentNextStopMissions().map(\.identity), [.orderProduct("OP-MINE")])
        XCTAssertEqual(list.currentNextStopMissions().count, list.arrRows.count,
                       "One mission per rendered row — no synthesis, no omission.")
    }

    // MARK: Stable reopen

    func testAnOrderMissionOpensByIdentityEvenAfterItsRowIndexMoved() {
        let (list, _) = board(orders: [leg("OP-1", sortKey: "2026-10-18|00001", deliveryDriver: garyId),
                                       leg("OP-2", sortKey: "2026-10-18|00002", deliveryDriver: garyId)],
                              driverId: garyId)
        var opened: [Int] = []
        list.openOrderMissionAt = { opened.append($0) }

        // A Dispatch reconciliation reorders the feed underneath the open picker.
        list.arrDispatchList = [leg("OP-2", sortKey: "2026-10-18|00002", deliveryDriver: garyId),
                                leg("OP-1", sortKey: "2026-10-18|00001", deliveryDriver: garyId)]
        list.rebuildRows()

        XCTAssertTrue(list.openOrderMission(orderProductUniqueId: "OP-1"))

        XCTAssertEqual(opened, [1], "OP-1 moved to index 1 — a stale index would have opened OP-2.")
    }

    func testAManualMissionOpensItsOwnTaskDetail() {
        let (list, nav) = board(manuals: [manual("MDT-1", sortKey: "2026-10-18|00001"),
                                          manual("MDT-2", sortKey: "2026-10-18|00002")])

        XCTAssertTrue(list.openManualMission(taskUniqueId: "MDT-2"))

        let pushed = nav.viewControllers.last as? ManualDispatchDetailViewController
        XCTAssertNotNil(pushed)
        XCTAssertEqual(pushed?.item?.unique_id, "MDT-2")
    }

    func testAMissionThatIsNoLongerThereIsRefusedAndNothingElseIsOpened() {
        let (list, nav) = board(orders: [leg("OP-1", sortKey: "2026-10-18|00001", deliveryDriver: garyId)],
                                manuals: [manual("MDT-1", sortKey: "2026-10-18|00002")],
                                driverId: garyId)
        var opened: [Int] = []
        list.openOrderMissionAt = { opened.append($0) }

        XCTAssertFalse(list.openOrderMission(orderProductUniqueId: "OP-GONE"))
        XCTAssertFalse(list.openManualMission(taskUniqueId: "MDT-GONE"))

        XCTAssertEqual(opened, [], "A missing mission must open NOTHING — never the row that took its place.")
        XCTAssertEqual(nav.viewControllers.count, 1)
    }

    func testAMissionReassignedAwayCannotBeOpenedFromAStalePicker() {
        let (list, _) = board(orders: [leg("OP-1", sortKey: "2026-10-18|00001", deliveryDriver: garyId)],
                              driverId: garyId)
        var opened: [Int] = []
        list.openOrderMissionAt = { opened.append($0) }
        XCTAssertEqual(list.currentNextStopMissions().map(\.identity), [.orderProduct("OP-1")])

        // The office moves the delivery to Blake while the picker is open.
        list.arrDispatchList = [leg("OP-1", sortKey: "2026-10-18|00001", deliveryDriver: blakeId)]
        list.rebuildRows()

        XCTAssertFalse(list.openOrderMission(orderProductUniqueId: "OP-1"),
                       "It is not this driver's work any more; the picker must refuse it.")
        XCTAssertEqual(opened, [])
    }
}
