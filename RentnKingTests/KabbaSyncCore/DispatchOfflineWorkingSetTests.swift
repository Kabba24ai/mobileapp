//
//  DispatchOfflineWorkingSetTests.swift
//  Dispatch offline Phase 3 — the Dispatch screen's local presentation source:
//  the company-wide cache filtered by driver / leg / date / category entirely
//  on the phone, with the not-downloaded state kept distinct from "no work".
//

import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class DispatchOfflineWorkingSetTests: XCTestCase {

    private typealias F = DispatchOfflineFixtures
    private typealias M = DispatchOfflineFixtures.Mission

    private let gary = 4, blake = 7, jerome = 9
    private let today = "2026-09-22"
    private var root: URL!
    private var server: FakeDispatchServer!
    private var store: DispatchOfflineMissionStore!

    override func setUp() {
        super.setUp()
        root = Fixtures.tempDirectory(name)
        server = FakeDispatchServer()
        store = makeStore()
    }

    private func makeStore() -> DispatchOfflineMissionStore {
        try! DispatchOfflineMissionStore(rootDirectory: root, baseURL: URL(string: "https://api.kabba.ai/api/admin/v1/")!)
    }

    /// Six missions, three drivers, both legs: overdue, today, +1, +2.
    private var fleet: [M] {
        [
            M(opuid: "ORD-SCH-1", revision: F.revision("1"), effectiveDate: "2026-09-20", deliveryDriverId: gary, categoryIds: [11], priority: 2),
            M(opuid: "ORD-SCH-2", leg: .return, revision: F.revision("2"), effectiveDate: today, deliveryDriverId: jerome, pickupDriverId: gary, categoryIds: [12], priority: 1),
            M(opuid: "ORD-SCH-3", revision: F.revision("3"), effectiveDate: today, deliveryDriverId: blake, categoryIds: [11], priority: 3),
            M(opuid: "ORD-SCH-4", leg: .return, revision: F.revision("4"), effectiveDate: "2026-09-23", deliveryDriverId: gary, pickupDriverId: blake, categoryIds: [12]),
            M(opuid: "ORD-SCH-5", revision: F.revision("5"), effectiveDate: "2026-09-23", deliveryDriverId: jerome, categoryIds: [11]),
            M(opuid: "ORD-SCH-6", revision: F.revision("6"), effectiveDate: "2026-09-24", deliveryDriverId: gary, pickupDriverId: jerome, categoryIds: [13]),
        ]
    }

    private func download(_ missions: [M]) {
        server.missions = missions
        let reconciler = DispatchOfflineReconciler(httpClient: server, store: store, session: { [unowned self] in .of(self.store) },
                                                   retainedOrderProducts: { [] })
        let done = expectation(description: "download")
        reconciler.request(.launch) { _ in done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    private func rows(_ query: DispatchOfflineQuery, operations: [SyncOperation] = [], store s: DispatchOfflineMissionStore? = nil) -> [DispatchOfflineRow] {
        guard case .ready(let rows, _) = DispatchOfflineWorkingSet.present(store: s ?? store, query: query, operations: operations, today: today) else {
            XCTFail("expected a downloaded working set"); return []
        }
        return rows
    }

    private func ids(_ rows: [DispatchOfflineRow]) -> [String] { rows.map(\.orderProductUniqueId) }

    // MARK: - Company-wide, local filtering (tests 7, 18)

    func testCompanyCacheHoldsEveryDriver() {
        download(fleet)

        let all = rows(DispatchOfflineQuery(selectedDriverId: nil, dates: .all))

        XCTAssertEqual(all.count, 6, "All Drivers is the whole company working set")
        let activeDrivers = Set(all.map { r -> Int? in
            (r.leg == .delivery ? r.row["delivery_employee"] : r.row["pickup_employee"])?["id"]?.intValue
        })
        XCTAssertEqual(activeDrivers, [gary, blake, jerome])
    }

    func testDriverSwitchingMakesNoRequest() {
        download(fleet)
        let before = server.requestCount
        server.setOffline(true)

        let garys = rows(DispatchOfflineQuery(selectedDriverId: gary, dates: .all))
        let blakes = rows(DispatchOfflineQuery(selectedDriverId: blake, dates: .all))
        let jeromes = rows(DispatchOfflineQuery(selectedDriverId: jerome, dates: .all))
        let everyone = rows(DispatchOfflineQuery(selectedDriverId: nil, dates: .all))

        XCTAssertEqual(server.requestCount, before, "switching drivers never touches the network")
        // The ACTIVE leg's employee decides membership: #2 is a return → Gary (pickup), not Jerome (delivery).
        XCTAssertEqual(ids(garys), ["ORD-SCH-1", "ORD-SCH-2", "ORD-SCH-6"])
        XCTAssertEqual(ids(blakes), ["ORD-SCH-3", "ORD-SCH-4"])
        XCTAssertEqual(ids(jeromes), ["ORD-SCH-5"])
        XCTAssertEqual(everyone.count, 6)
    }

    func testAnActiveLegWithoutADriverIsNeverHidden() {
        download([M(opuid: "ORD-SCH-X", revision: F.revision("x"), deliveryDriverId: nil)])
        XCTAssertEqual(ids(rows(DispatchOfflineQuery(selectedDriverId: gary, dates: .all))), ["ORD-SCH-X"])
    }

    // MARK: - Filters

    func testTodayMeansOverdueAndTodayWhileAllIsTheWholeHorizon() {
        download(fleet)
        XCTAssertEqual(ids(rows(DispatchOfflineQuery(dates: .today))), ["ORD-SCH-1", "ORD-SCH-2", "ORD-SCH-3"])
        XCTAssertEqual(rows(DispatchOfflineQuery(dates: .all)).count, 6)
    }

    func testTheLegFilterMatchesTheDeliveryAndReturnToggles() {
        download(fleet)
        XCTAssertEqual(ids(rows(DispatchOfflineQuery(legs: .delivery, dates: .all))), ["ORD-SCH-1", "ORD-SCH-3", "ORD-SCH-5", "ORD-SCH-6"])
        XCTAssertEqual(ids(rows(DispatchOfflineQuery(legs: .return, dates: .all))), ["ORD-SCH-2", "ORD-SCH-4"])
    }

    func testTheCategoryFilterUsesTheRowsCategories() {
        download(fleet)
        XCTAssertEqual(ids(rows(DispatchOfflineQuery(dates: .all, categoryId: 11))), ["ORD-SCH-1", "ORD-SCH-3", "ORD-SCH-5"])
        XCTAssertEqual(rows(DispatchOfflineQuery(dates: .all, categoryId: 99)), [])
    }

    func testALegCompletedOnThisPhoneLeavesTheWorkingQueue() {
        download(fleet)
        var op = SyncOperation(type: "delivery_checklist.complete", capturedAt: Date(),
                               identity: SyncBusinessIdentity(orderProductUniqueId: "ORD-SCH-1"), payload: .object([:]))
        op.state = .pending

        XCTAssertFalse(ids(rows(DispatchOfflineQuery(dates: .all), operations: [op])).contains("ORD-SCH-1"))
    }

    func testOverdueIsDerivedFromTheEffectiveDate() {
        download(fleet)
        let all = rows(DispatchOfflineQuery(dates: .all))
        let overdue = all.first { $0.orderProductUniqueId == "ORD-SCH-1" }!
        let todays = all.first { $0.orderProductUniqueId == "ORD-SCH-2" }!

        XCTAssertTrue(overdue.isOverdue)
        XCTAssertEqual(overdue.row["is_delivery_overdue"], .bool(true))
        XCTAssertFalse(todays.isOverdue)
        XCTAssertEqual(todays.row["is_pickup_overdue"], .bool(false))
    }

    func testRowsFollowTheBoardSortKey() {
        download(fleet.shuffled())
        let sortKeys = rows(DispatchOfflineQuery(dates: .all)).map(\.sortKey)
        XCTAssertEqual(sortKeys, sortKeys.sorted())
        XCTAssertEqual(ids(rows(DispatchOfflineQuery(dates: .today))), ["ORD-SCH-1", "ORD-SCH-2", "ORD-SCH-3"],
                       "overdue first, then today by priority")
    }

    // MARK: - Freshness + states (tests 13, 14)

    func testRelaunchOfflineRendersCachedSet() {
        download(fleet)
        server.setOffline(true)

        // Force quit, relaunch with no network: a new store instance over the same files.
        let relaunched = makeStore()
        guard case .ready(let rows, let freshness) = DispatchOfflineWorkingSet.present(
            store: relaunched, query: DispatchOfflineQuery(dates: .all), operations: [], today: today) else {
            return XCTFail("cached Dispatch must render offline")
        }
        XCTAssertEqual(rows.count, 6)
        XCTAssertNotNil(freshness.lastManifestAt)
        XCTAssertEqual(freshness.throughDate, "2026-09-24")
    }

    func testNeverCommittedIsNotDownloadedNotEmpty() {
        server.setOffline(true)
        download(fleet) // a fresh install that has never reached the server
        XCTAssertEqual(DispatchOfflineWorkingSet.present(store: store, query: DispatchOfflineQuery(), operations: [], today: today),
                       .notDownloaded)
    }

    func testAnEmptyManifestIsARealEmptyDispatch() {
        download([])
        guard case .ready(let rows, _) = DispatchOfflineWorkingSet.present(store: store, query: DispatchOfflineQuery(), operations: [], today: today) else {
            return XCTFail("an empty manifest is a downloaded, empty Dispatch")
        }
        XCTAssertEqual(rows, [])
    }

    func testStaleAndPendingMissionsAreCounted() {
        download(fleet)
        var next = fleet
        next[0].revision = F.revision("1-v2")
        next.append(M(opuid: "ORD-SCH-7", revision: F.revision("7"), effectiveDate: today))
        server.goOfflineAfterManifests = server.manifestRequests + 1
        download(next)

        guard case .ready(let rows, let freshness) = DispatchOfflineWorkingSet.present(
            store: store, query: DispatchOfflineQuery(dates: .all), operations: [], today: today) else { return XCTFail() }
        XCTAssertEqual(freshness.staleCount, 1)
        XCTAssertEqual(freshness.pendingCount, 1)
        XCTAssertEqual(rows.count, 6, "the stale mission still shows; the undownloaded one cannot")
        XCTAssertTrue(rows.first { $0.orderProductUniqueId == "ORD-SCH-1" }!.isStale)
        XCTAssertEqual(rows.first { $0.orderProductUniqueId == "ORD-SCH-1" }!.revision, F.revision("1"),
                       "each row names the package revision it was rendered from")
    }

    func testTheOfflineAllLineNamesTheLastDownloadedDay() {
        XCTAssertEqual(DispatchOfflineWorkingSet.offlineAllLine(throughDate: "2026-09-25"),
                       "Offline — showing downloaded Dispatch through Sep 25")
        XCTAssertEqual(DispatchOfflineWorkingSet.offlineAllLine(throughDate: "garbage"),
                       "Offline — showing downloaded Dispatch")
    }

    func testTheLocalDateUsesThePhonesCalendarDay() {
        let chicago = TimeZone(identifier: "America/Chicago")!
        let lateEvening = ISO8601DateFormatter().date(from: "2026-09-23T03:30:00Z")! // 22:30 Sep 22 in Chicago
        XCTAssertEqual(DispatchOfflineWorkingSet.localDateString(lateEvening, timeZone: chicago), "2026-09-22")
    }
}

// MARK: - Dispatch screen policy (review I-2 / I-3)

final class DispatchOfflineScreenPolicyTests: XCTestCase {

    private typealias P = DispatchOfflineScreenPolicy

    func testPendingTodayIsAlwaysTheDurableCache() {
        XCTAssertEqual(P.source(pending: true, search: "", day: "Today", selectedDriverId: ""), .offlineCache)
        XCTAssertEqual(P.source(pending: true, search: "", day: "Today", selectedDriverId: "4"), .offlineCache)
    }

    func testPendingAllUsesTheLiveFeedOnlyForANamedDriver() {
        // D5: the mixed feed scopes a missing driver to the signed-in user — it can never stand in
        // for the company-wide All Drivers set.
        XCTAssertEqual(P.source(pending: true, search: "", day: "All", selectedDriverId: ""), .offlineCache)
        XCTAssertEqual(P.source(pending: true, search: "", day: "All", selectedDriverId: "4"), .cacheThenFeed)
    }

    func testCompletedAndSearchStayOnTheOnlineFeed() {
        XCTAssertEqual(P.source(pending: false, search: "", day: "Today", selectedDriverId: ""), .feed)
        XCTAssertEqual(P.source(pending: true, search: "Cash", day: "Today", selectedDriverId: ""), .feed)
        XCTAssertEqual(P.source(pending: true, search: "  ", day: "Today", selectedDriverId: ""), .offlineCache, "blank search is no search")
    }

    func testAReconciliationOutcomeAlwaysSettlesTheScreen() {
        // Never downloaded: online failure falls back to the live feed (never a permanent spinner);
        // offline says it is not downloaded.
        XCTAssertEqual(P.outcome(notDownloaded: true, failed: true, online: true), .fallBackToFeed)
        XCTAssertEqual(P.outcome(notDownloaded: true, failed: false, online: false), .showNotDownloaded)
        XCTAssertEqual(P.outcome(notDownloaded: true, failed: true, online: false), .showNotDownloaded)
        // Downloaded: a failed/partial run is never presented as current; success clears the header.
        XCTAssertEqual(P.outcome(notDownloaded: false, failed: true, online: true), .flagNotCurrent)
        XCTAssertEqual(P.outcome(notDownloaded: false, failed: false, online: false), .flagOffline)
        XCTAssertEqual(P.outcome(notDownloaded: false, failed: false, online: true), .current)
        // A successful first download renders normally.
        XCTAssertEqual(P.outcome(notDownloaded: true, failed: false, online: true), .current)
    }

    func testOnlyAMissingDownloadForcesARequestOnAFilterChange() {
        XCTAssertTrue(P.filterChangeNeedsFirstDownload(notDownloaded: true, online: true))
        XCTAssertFalse(P.filterChangeNeedsFirstDownload(notDownloaded: true, online: false), "offline: zero requests")
        XCTAssertFalse(P.filterChangeNeedsFirstDownload(notDownloaded: false, online: true), "downloaded: local filtering only")
    }
}
