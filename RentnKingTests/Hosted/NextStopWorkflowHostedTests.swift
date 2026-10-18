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

    /// A tenant store exactly as getStoreListData() hands it over: `address`
    /// carries the server's full_address.
    fileprivate func store(_ uid: String, _ name: String, _ address: String) -> StoreModel {
        return Mapper<StoreModel>().map(JSON: ["unique_id": uid, "store_name": name, "full_address": address])!
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

// MARK: - Task 4: the Next Stop screen and the mission picker

extension NextStopWorkflowHostedTests {

    /// A Next Stop screen with every outside edge injected: the durable state,
    /// the tenant's stores, and the map opener.
    fileprivate func nextStop(state: NextStopState = .idle,
                              cached: [StoreModel] = [],
                              refreshed: [StoreModel]? = nil,
                              mapSucceeds: Bool = true) -> NextStopProbe {
        let probe = NextStopProbe()
        probe.saved = state
        let vc = NextStopViewController()
        vc.loadState = { probe.saved }
        vc.persistState = { probe.saved = $0; probe.events.append("saved(\($0.shop?.name ?? "idle"))") }
        vc.cachedStores = { cached }
        vc.refreshStores = { done in if let r = refreshed { done(r) } }
        vc.openMap = { address, done in
            probe.events.append("map(\(address))")
            probe.mapAddresses.append(address)
            done(mapSucceeds)
        }
        vc.now = { Date(timeIntervalSince1970: 1_792_000_000) }
        probe.vc = vc
        vc.loadViewIfNeeded()
        return probe
    }

    // MARK: The question

    func testTheScreenAsksWhatTheDriverIsDoingNextAndOffersExactlyTwoPaths() {
        let p = nextStop()

        XCTAssertEqual(p.vc.headlineText, "What are you doing next?")
        XCTAssertEqual(p.vc.primaryChoiceTitles, ["Next Customer / Mission", "Return to Shop"])
    }

    func testOpeningTheScreenTouchesNoSyncOperationAndNoAssignment() {
        let ops = [SyncOperation(type: "manual_dispatch.update_status", capturedAt: Date(), queuedAt: Date(),
                                 identity: SyncBusinessIdentity(manualTaskUniqueId: "MDT-1"),
                                 payload: .object(["status": .string(DispatchManualStatus.arrived)]))]
        let (list, _) = board(orders: [leg("OP-1", sortKey: "2026-10-18|00001", deliveryDriver: garyId)],
                              driverId: garyId, ops: ops)
        let before = list.arrDispatchList.map { ($0.unique_id, $0.delivery_employee?.id, $0.is_delivered) }

        let p = nextStop()
        p.vc.missions = { list.currentNextStopMissions() }
        p.vc.loadViewIfNeeded()

        XCTAssertEqual(list.operationsSnapshot().count, 1, "Opening Next Stop must not add, drop or alter an operation.")
        XCTAssertEqual(list.arrDispatchList.map { ($0.unique_id, $0.delivery_employee?.id, $0.is_delivered) }.count, before.count)
        XCTAssertEqual(p.saved, .idle, "Merely asking the question persists nothing.")
    }

    // MARK: Return to Shop — the tenant's own active stores

    func testTheShopListIsTheTenantsCachedActiveStoresWithTheirCanonicalNameAndAddress() {
        let p = nextStop(cached: [store("STR-1", "Bon Aqua", "100 Yard Rd, Bon Aqua, TN, 37025"),
                                  store("STR-2", "Waverly", "9 Depot St, Waverly, TN, 37185")])

        p.vc.returnToShopTapped()

        XCTAssertEqual(p.vc.shopChoices.map(\.name), ["Bon Aqua", "Waverly"],
                       "Rent N King sees its own stores because they are its active stores — never because they are hard-coded.")
        XCTAssertEqual(p.vc.shopChoices.map(\.fullAddress).first, "100 Yard Rd, Bon Aqua, TN, 37025")
    }

    func testAnOnlineRefreshNeverBlanksTheListTheDriverIsAlreadyLookingAt() {
        let p = nextStop(cached: [store("STR-1", "Bon Aqua", "100 Yard Rd")], refreshed: [])

        p.vc.returnToShopTapped()

        XCTAssertEqual(p.vc.shopChoices.map(\.name), ["Bon Aqua"],
                       "A failed/empty refresh must not erase the cached stores under the driver's finger.")
    }

    func testAnOnlineRefreshDoesReplaceTheListWhenItBringsStores() {
        let p = nextStop(cached: [store("STR-1", "Bon Aqua", "100 Yard Rd")],
                         refreshed: [store("STR-1", "Bon Aqua", "100 Yard Rd"),
                                     store("STR-3", "New Yard", "5 New Rd")])

        p.vc.returnToShopTapped()

        XCTAssertEqual(p.vc.shopChoices.map(\.name), ["Bon Aqua", "New Yard"])
    }

    func testWithNoCachedStoresTheScreenSaysSoHonestlyAndStillOffersTheNextMissionPath() {
        let p = nextStop(cached: [])

        p.vc.returnToShopTapped()

        XCTAssertTrue(p.vc.shopChoices.isEmpty)
        XCTAssertEqual(p.vc.shopUnavailableText,
                       "Your shops have not been downloaded to this phone yet. Connect once to load them.")
        XCTAssertTrue(p.vc.primaryChoiceTitles.contains("Next Customer / Mission"),
                      "No shop list is not a dead end — the driver can still take the next mission.")
    }

    // MARK: Durability before navigation

    func testTheShopIsOnDiskBeforeMapsIsEverAskedToOpen() {
        let p = nextStop(cached: [store("STR-1", "Bon Aqua", "100 Yard Rd, Bon Aqua, TN, 37025")])
        p.vc.returnToShopTapped()

        p.vc.selectShop(at: 0)

        XCTAssertEqual(p.events, ["saved(Bon Aqua)", "map(100 Yard Rd, Bon Aqua, TN, 37025)"],
                       "The driver leaves the app for Maps — the choice must already be durable when they go.")
        XCTAssertEqual(p.saved, .shopSelected(shop: NextStopShop(uniqueId: "STR-1", name: "Bon Aqua",
                                                                 fullAddress: "100 Yard Rd, Bon Aqua, TN, 37025"),
                                              selectedAt: Date(timeIntervalSince1970: 1_792_000_000)))
    }

    func testMapsFailingToOpenLeavesTheShopStopIntactAndUsable() {
        let p = nextStop(cached: [store("STR-1", "Bon Aqua", "nowhere at all")], mapSucceeds: false)
        p.vc.returnToShopTapped()

        p.vc.selectShop(at: 0)

        XCTAssertEqual(p.saved.shop?.name, "Bon Aqua", "A geocode failure is not a reason to forget where the driver is going.")
        XCTAssertEqual(p.vc.arrivedActionTitle, "Arrived at Bon Aqua")
    }

    // MARK: Resume after leaving for Maps

    func testComingBackToTheAppStillShowsTheShopAsTheCurrentDestination() {
        let shop = NextStopShop(uniqueId: "STR-1", name: "Bon Aqua", fullAddress: "100 Yard Rd")
        let p = nextStop(state: .shopSelected(shop: shop, selectedAt: Date(timeIntervalSince1970: 1_792_000_000)))

        p.vc.refreshFromDurableState()   // what viewWillAppear does

        XCTAssertEqual(p.vc.currentDestinationText, "Heading to Bon Aqua")
        XCTAssertEqual(p.vc.arrivedActionTitle, "Arrived at Bon Aqua")
    }

    func testArrivingRecordsTheArrivalAndThenOffersTheNextMission() {
        let shop = NextStopShop(uniqueId: "STR-1", name: "Bon Aqua", fullAddress: "100 Yard Rd")
        let selectedAt = Date(timeIntervalSince1970: 1_792_000_000)
        let p = nextStop(state: .shopSelected(shop: shop, selectedAt: selectedAt))
        p.vc.refreshFromDurableState()

        p.vc.arrivedTapped()

        XCTAssertEqual(p.saved, .arrivedAtShop(shop: shop, selectedAt: selectedAt, arrivedAt: selectedAt))
        XCTAssertEqual(p.vc.currentDestinationText, "At Bon Aqua")
        XCTAssertEqual(p.vc.primaryChoiceTitles, ["Choose Next Mission"],
                       "Once the driver is at the shop the only forward move is the next mission.")
    }

    // MARK: The mission picker

    fileprivate func picker(_ missions: [NextStopMission],
                            source: MissionSourceState = .available) -> NextMissionProbe {
        let probe = NextMissionProbe()
        let vc = NextMissionPickerViewController()
        vc.missions = { missions }
        vc.sourceState = { source }
        vc.openOrderMission = { probe.opened.append("order:\($0)"); return probe.openSucceeds }
        vc.openManualMission = { probe.opened.append("manual:\($0)"); return probe.openSucceeds }
        vc.clearShopStop = { probe.events.append("clearedShopStop") }
        vc.refreshDispatch = { probe.events.append("refreshedDispatch") }
        probe.vc = vc
        vc.loadViewIfNeeded()
        return probe
    }

    func testThePickerRendersDeliveryReturnAndManualDispatchTogether() {
        let p = picker([NextStopMission(identity: .orderProduct("OP-1"), kindLabel: "Delivery",
                                        primaryText: "Cody Cash", secondaryText: "Skid Steer · #4108", sortKey: "a"),
                        NextStopMission(identity: .orderProduct("OP-2"), kindLabel: "Return",
                                        primaryText: "Jane Roe", secondaryText: "Excavator · #4109", sortKey: "b"),
                        NextStopMission(identity: .manualTask("MDT-1"), kindLabel: "Manual Dispatch",
                                        primaryText: "Acme", secondaryText: "Equipment Drop-Off", sortKey: "c")])

        XCTAssertEqual(p.vc.renderedKindLabels, ["Delivery", "Return", "Manual Dispatch"])
        XCTAssertEqual(p.vc.renderedPrimaryTexts, ["Cody Cash", "Jane Roe", "Acme"])
    }

    func testChoosingAMissionEndsTheShopStopBeforeEnteringTheMission() {
        let p = picker([NextStopMission(identity: .orderProduct("OP-1"), kindLabel: "Delivery",
                                        primaryText: "Cody Cash", secondaryText: "", sortKey: "a")])

        p.vc.selectMission(at: 0)

        XCTAssertEqual(p.events, ["clearedShopStop"],
                       "A real mission is the next stop now — the shop stop is over before we route.")
        XCTAssertEqual(p.opened, ["order:OP-1"])
    }

    func testChoosingAManualMissionRoutesThroughTheManualHelper() {
        let p = picker([NextStopMission(identity: .manualTask("MDT-9"), kindLabel: "Manual Dispatch",
                                        primaryText: "Acme", secondaryText: "", sortKey: "a")])

        p.vc.selectMission(at: 0)

        XCTAssertEqual(p.opened, ["manual:MDT-9"])
    }

    func testAMissionThatVanishedBeforeTheTapSaysSoAndRefreshesInsteadOfRouting() {
        let p = picker([NextStopMission(identity: .orderProduct("OP-1"), kindLabel: "Delivery",
                                        primaryText: "Cody Cash", secondaryText: "", sortKey: "a")])
        p.openSucceeds = false

        p.vc.selectMission(at: 0)

        XCTAssertEqual(p.vc.noticeText, "This mission is no longer assigned here. Dispatch has been refreshed.")
        XCTAssertTrue(p.events.contains("refreshedDispatch"))
        XCTAssertEqual(p.opened, ["order:OP-1"], "It tried once, by identity, and was refused — not retried blindly.")
    }

    func testARealEmptyWorkdayAndAnUndownloadedOneReadDifferently() {
        XCTAssertEqual(picker([], source: .available).vc.emptyText,
                       "No remaining missions. You're done for now.")

        XCTAssertEqual(picker([], source: .notDownloaded).vc.emptyText,
                       "Your remaining work has not been downloaded to this phone. Connect once to load it.",
                       "An unavailable cache must never be presented as a finished day.")
    }
}

// MARK: - Probes

final class NextStopProbe {
    var vc: NextStopViewController!
    var saved: NextStopState = .idle
    var events: [String] = []
    var mapAddresses: [String] = []
}

final class NextMissionProbe {
    var vc: NextMissionPickerViewController!
    var opened: [String] = []
    var events: [String] = []
    var openSucceeds = true
}

// MARK: - Task 5: completed Delivery / Return continue into Next Stop

extension NextStopWorkflowHostedTests {

    /// Main Order over a Dispatch board, which is the stack the driver is
    /// actually in when they finish a job.
    fileprivate func orderOverDispatch(completionLeg: ChecklistLeg = .delivery, ops: [SyncOperation] = [])
        throws -> (details: OrderDetailsViewController, list: DispatchListViewController, nav: UINavigationController) {
        let (list, nav) = board(orders: [leg("OP-NEXT", sortKey: "2026-10-18|00002", deliveryDriver: garyId)],
                                driverId: garyId, ops: ops)
        let details = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController)
        details.objOrderData = Mapper<OrdersListModel>().map(JSON: [
            "unique_id": "ORD-1", "order_number": "4108", "customer_name": "Cody Cash",
        ])
        details.strOrderUniqueId = "ORD-1"
        details.strOrderID = "4108"
        details.strProductID = "OP-DONE"
        details.isOrderScreen = true
        details.fromCheckListScreen = true
        details.completionLeg = completionLeg
        details.operationsSnapshot = { ops }
        details.cachedAssemblyReview = { _ in nil }
        details.cachedChecklistContext = { _ in nil }
        // The success animation is not what these tests are about.
        details.presentSuccessOverlay = { (done: @escaping () -> Void) in done() }
        nav.pushViewController(details, animated: false)
        return (details, list, nav)
    }

    func testASuccessfulDeliveryCompletionContinuesIntoNextStop() throws {
        let (details, list, nav) = try orderOverDispatch(completionLeg: .delivery)

        details.completeDeliveryWithSuccess()

        XCTAssertTrue(nav.topViewController is NextStopViewController,
                      "A finished delivery must ask what's next, not strand the driver on the board.")
        XCTAssertTrue(nav.viewControllers.contains { $0 === list },
                      "Dispatch stays the anchor underneath Next Stop.")
        XCTAssertFalse(nav.viewControllers.contains { $0 === details },
                       "The completed job is behind the driver — Main Order must not stay on the stack.")
    }

    func testASuccessfulReturnCompletionContinuesIntoNextStop() throws {
        let (details, _, nav) = try orderOverDispatch(completionLeg: .return)

        details.completeDeliveryWithSuccess()

        XCTAssertTrue(nav.topViewController is NextStopViewController)
    }

    func testNeedsAttentionCompletionStillContinuesAndLeavesTheParkedWorkUntouched() throws {
        var parked = SyncOperation(type: "delivery_checklist.complete", capturedAt: Date(), queuedAt: Date(),
                                   identity: SyncBusinessIdentity(orderProductUniqueId: "OP-DONE"),
                                   payload: .object([:]))
        parked.state = .needsAttention
        let (details, _, nav) = try orderOverDispatch(ops: [parked])

        details.completeLegWithSyncAttention(operationId: parked.id)

        XCTAssertTrue(nav.topViewController is NextStopViewController,
                      "The physical work happened; reconciliation is the office's job, so the driver moves on.")
        let after = details.operationsSnapshot()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.id, parked.id)
        XCTAssertEqual(after.first?.state, .needsAttention,
                       "Next Stop must never retry, discard or re-state parked field work.")
    }

    func testGenuinelyIncompleteWorkStillGoesToTheWarningScreenAndNeverToNextStop() throws {
        // No evidence of terms/licence/video/checklist at all, so the canonical
        // LegCompletionEvaluator must refuse to proceed.
        let (details, _, nav) = try orderOverDispatch(completionLeg: .delivery)
        XCTAssertFalse(details.legCompletionDecision(for: .delivery).canProceed,
                       "Fixture guard: this leg must genuinely be incomplete.")

        details.btnDeliveryComplatedClicked(UIButton())

        XCTAssertTrue(nav.topViewController is WarningViewController,
                      "Incomplete physical work keeps the existing Driver Override screen.")
        XCTAssertFalse(nav.viewControllers.contains { $0 is NextStopViewController })
    }

    func testContinuingWithNoDispatchBeneathDoesNotCrashOrInventAStack() throws {
        let details = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController)
        details.presentSuccessOverlay = { (done: @escaping () -> Void) in done() }
        let nav = UINavigationController(rootViewController: details)

        details.completeDeliveryWithSuccess()

        XCTAssertFalse(nav.viewControllers.contains { $0 is NextStopViewController },
                       "Without a Dispatch anchor there is no workday to continue; the old pop is the correct fallback.")
    }
}

// MARK: - Task 6: a completed Manual Dispatch continues into Next Stop

extension NextStopWorkflowHostedTests {

    /// A Task Details screen over a Dispatch board, with the durable transition
    /// injected so the lifecycle can be driven without a live Sync Engine.
    fileprivate func manualDetail(status: String, wired: Bool = true, enqueueFails: Bool = false)
        -> (detail: ManualDispatchDetailViewController, list: DispatchListViewController,
            nav: UINavigationController, probe: ManualProbe) {
        let probe = ManualProbe()
        var item = manual("MDT-1", sortKey: "2026-10-18|00001")
        item.status = status

        let (list, nav) = board(manuals: [item])
        let detail = ManualDispatchDetailViewController()
        detail.item = item
        detail.enqueueStatus = { uid, newStatus in
            probe.enqueued.append("\(uid):\(newStatus)")
            if enqueueFails { throw NextStopStoreError.noTenant }
            return "op-\(newStatus)"
        }
        detail.onChanged = { probe.changed += 1 }
        if wired { detail.onCompleted = { [weak list] in list?.beginNextStopFlow() } }
        nav.pushViewController(detail, animated: false)
        detail.loadViewIfNeeded()
        return (detail, list, nav, probe)
    }

    func testOnMyWayAndArrivedTransitionsAreUnchangedAndNeverOpenNextStop() {
        for status in [DispatchManualStatus.onMyWay, DispatchManualStatus.arrived] {
            let m = manualDetail(status: DispatchManualStatus.assigned)

            m.detail.submitStatus(status)

            XCTAssertEqual(m.probe.enqueued, ["MDT-1:\(status)"],
                           "The canonical status operation is still the only writer.")
            XCTAssertEqual(m.probe.changed, 1, "The list still refreshes.")
            XCTAssertFalse(m.nav.viewControllers.contains { $0 is NextStopViewController },
                           "\(status) is mid-route — the driver is not finished, so there is nothing to ask.")
        }
    }

    func testCompletedDurablyEnqueuesTheCanonicalOperationAndThenOpensNextStop() {
        let m = manualDetail(status: DispatchManualStatus.arrived)

        m.detail.submitStatus(DispatchManualStatus.completed)

        XCTAssertEqual(m.probe.enqueued, ["MDT-1:Completed"],
                       "Completion still goes through the one manual_dispatch.update_status writer.")
        XCTAssertTrue(m.nav.topViewController is NextStopViewController,
                      "A finished manual task ends the same way a finished delivery does.")
        XCTAssertTrue(m.nav.viewControllers.contains { $0 === m.list })
        XCTAssertFalse(m.nav.viewControllers.contains { $0 === m.detail },
                       "The completed task is behind the driver.")
    }

    func testCancellingATaskDoesNotOpenNextStop() {
        let m = manualDetail(status: DispatchManualStatus.arrived)

        m.detail.submitStatus(DispatchManualStatus.cancelled)

        XCTAssertEqual(m.probe.enqueued, ["MDT-1:Cancelled"])
        XCTAssertFalse(m.nav.viewControllers.contains { $0 is NextStopViewController },
                       "A cancelled task is not accomplished work; it must not drive the workday forward.")
    }

    func testADurableEnqueueFailureNeverFalselyAdvancesTheDriver() {
        let m = manualDetail(status: DispatchManualStatus.arrived, enqueueFails: true)

        m.detail.submitStatus(DispatchManualStatus.completed)

        XCTAssertEqual(m.probe.changed, 0, "Nothing was recorded, so nothing is announced.")
        XCTAssertFalse(m.nav.viewControllers.contains { $0 is NextStopViewController },
                       "If the transition did not reach disk, the task is NOT complete and the driver stays put.")
        XCTAssertTrue(m.nav.topViewController === m.detail)
    }

    func testTheBoardItselfWiresCompletionIntoNextStop() throws {
        // Not an injected callback: the production push path must do this.
        let (list, nav) = board(manuals: [manual("MDT-7", sortKey: "2026-10-18|00001")])
        XCTAssertTrue(list.openManualMission(taskUniqueId: "MDT-7"))
        let detail = try XCTUnwrap(nav.topViewController as? ManualDispatchDetailViewController)
        detail.enqueueStatus = { (_: String, _: String) in "op-1" }
        // onCompleted — the thing under test — is left exactly as production set
        // it. Only the unrelated list refresh is neutralised: refreshList()
        // drives storyboard outlets, and these fixtures build the Dispatch
        // controller programmatically, so its outlets are nil here.
        XCTAssertNotNil(detail.onCompleted, "The board must wire completion into Next Stop itself.")
        detail.onChanged = {}

        detail.submitStatus(DispatchManualStatus.completed)

        XCTAssertTrue(nav.topViewController is NextStopViewController,
                      "Opening a manual mission FROM Next Stop must also return to Next Stop when it completes.")
    }
}

final class ManualProbe {
    var enqueued: [String] = []
    var changed = 0
}

// MARK: - Task 7: offline, relaunch, reassignment and non-interference

extension NextStopWorkflowHostedTests {

    /// A leg this phone durably completed, as EffectiveFieldState's completion
    /// overlay recognises it.
    fileprivate func completedLegOp(_ productId: String, delivery: Bool = true) -> SyncOperation {
        var op = SyncOperation(type: delivery ? "delivery_checklist.complete" : "return_checklist.complete",
                               capturedAt: Date(), queuedAt: Date(),
                               identity: SyncBusinessIdentity(orderProductUniqueId: productId),
                               payload: .object(["order_product_unique_id": .string(productId)]))
        op.state = .pending
        return op
    }

    func testAMissionCompletedOnThisPhoneDoesNotComeBackInThePicker() {
        // The driver just finished OP-DONE; OP-NEXT is what's left.
        let (list, _) = board(orders: [leg("OP-DONE", sortKey: "2026-10-18|00001", deliveryDriver: garyId),
                                       leg("OP-NEXT", sortKey: "2026-10-18|00002", deliveryDriver: garyId)],
                              driverId: garyId,
                              ops: [completedLegOp("OP-DONE")])

        let missions = list.currentNextStopMissions()

        XCTAssertEqual(missions.map(\.identity), [.orderProduct("OP-NEXT")],
                       "The job the driver just finished must not be offered back to them.")
        XCTAssertFalse(list.openOrderMission(orderProductUniqueId: "OP-DONE"),
                       "Nor may it be reopened from a stale pick.")
    }

    func testTheWholeNextStopFlowNeverDisturbsParkedFieldWork() {
        var parked = SyncOperation(type: "delivery_checklist.complete", capturedAt: Date(), queuedAt: Date(),
                                   identity: SyncBusinessIdentity(orderProductUniqueId: "OP-PARKED"),
                                   payload: .object([:]))
        parked.state = .needsAttention
        let (list, _) = board(orders: [leg("OP-NEXT", sortKey: "2026-10-18|00002", deliveryDriver: garyId)],
                              driverId: garyId, ops: [parked])
        let before = list.operationsSnapshot()

        // Walk the entire feature: ask, pick a shop, arrive, then take a mission.
        let p = nextStop(cached: [store("STR-1", "Bon Aqua", "100 Yard Rd")])
        p.vc.missions = { list.currentNextStopMissions() }
        p.vc.returnToShopTapped()
        p.vc.selectShop(at: 0)
        p.vc.arrivedTapped()
        p.vc.refreshFromDurableState()

        let after = list.operationsSnapshot()
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(after.first?.id, parked.id)
        XCTAssertEqual(after.first?.state, .needsAttention,
                       "Next Stop touches no operation — it is workflow state, not queued work.")
    }

    func testTakingAMissionAfterAShopStopClearsTheShopStopDurably() {
        // End to end through the screen's own wiring, not an injected stub.
        let (list, _) = board(orders: [leg("OP-NEXT", sortKey: "2026-10-18|00002", deliveryDriver: garyId)],
                              driverId: garyId)
        var opened: [Int] = []
        list.openOrderMissionAt = { opened.append($0) }

        let p = nextStop(cached: [store("STR-1", "Bon Aqua", "100 Yard Rd")])
        p.vc.missions = { list.currentNextStopMissions() }
        p.vc.openOrderMission = { list.openOrderMission(orderProductUniqueId: $0) }
        p.vc.returnToShopTapped()
        p.vc.selectShop(at: 0)
        p.vc.arrivedTapped()
        XCTAssertEqual(p.saved.shop?.name, "Bon Aqua")

        // "Choose Next Mission" → the picker → take the remaining delivery.
        let nav = UINavigationController(rootViewController: p.vc)
        p.vc.nextCustomerTapped()
        let picker = nav.topViewController as? NextMissionPickerViewController
        XCTAssertNotNil(picker)
        picker?.loadViewIfNeeded()        // the driver taps a row on a visible screen
        XCTAssertEqual(picker?.renderedPrimaryTexts, ["Cody Cash"])
        picker?.selectMission(at: 0)

        XCTAssertEqual(p.saved, .idle,
                       "A real mission is the next stop now — the shop stop must be over, on disk.")
        XCTAssertEqual(opened, [0], "And the mission itself is entered.")
    }

    func testOpeningNextStopLeavesTheDispatchBoardsOwnRenderingAlone() {
        let (list, _) = board(orders: [leg("OP-1", sortKey: "2026-10-18|00001", deliveryDriver: garyId),
                                       leg("OP-2", delivered: true, sortKey: "2026-10-18|00002",
                                           deliveryDriver: garyId, pickupDriver: garyId)],
                              manuals: [manual("MDT-1", sortKey: "2026-10-18|00003")],
                              driverId: garyId)
        let rowsBefore = list.arrRows
        let feedBefore = list.arrDispatchList.map { $0.unique_id }
        let manualsBefore = list.arrManualList.map { $0.unique_id }

        _ = list.currentNextStopMissions()
        list.beginNextStopFlow()

        XCTAssertEqual(list.arrRows, rowsBefore, "The rendered board is untouched.")
        XCTAssertEqual(list.arrDispatchList.map { $0.unique_id }, feedBefore)
        XCTAssertEqual(list.arrManualList.map { $0.unique_id }, manualsBefore)
    }

    func testOfflineWithNoCachedWorkTheWorkdayIsUnknownNotFinished() {
        let (list, _) = board(driverId: garyId)
        list.isAwaitingFirstDownload = true
        list.beginNextStopFlow()
        // The source state the board hands Next Stop when it has nothing cached.
        let p = picker([], source: .notDownloaded)

        XCTAssertTrue(list.arrRows.isEmpty)
        XCTAssertEqual(p.vc.emptyText,
                       "Your remaining work has not been downloaded to this phone. Connect once to load it.")
    }
}
