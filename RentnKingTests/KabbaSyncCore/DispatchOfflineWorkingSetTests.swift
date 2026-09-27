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

    // Phase 6 locked rule (Gary, 2026-09-27): only ASSIGNED work is presented. A named driver sees
    // the missions whose ACTIVE leg is theirs, All shows every assigned mission, and a mission whose
    // active leg has no driver is hidden everywhere (it may stay cached for a later assignment).

    /// An unassigned pending delivery, and a delivered row whose return has no driver yet.
    private var unassigned: [M] {
        [
            M(opuid: "ORD-SCH-UD", revision: F.revision("ud"), effectiveDate: today, deliveryDriverId: nil, pickupDriverId: gary),
            M(opuid: "ORD-SCH-UR", leg: .return, revision: F.revision("ur"), effectiveDate: today, deliveryDriverId: gary, pickupDriverId: nil),
        ]
    }

    func testUnassignedMissionsAreHiddenFromEveryDriverAndAllWhileAssignedOnesShowNormally() {
        download(fleet + unassigned)

        XCTAssertEqual(ids(rows(DispatchOfflineQuery(selectedDriverId: gary, dates: .all))), ["ORD-SCH-1", "ORD-SCH-2", "ORD-SCH-6"],
                       "driver A: only their assigned missions, never the unassigned ones")
        XCTAssertEqual(ids(rows(DispatchOfflineQuery(selectedDriverId: blake, dates: .all))), ["ORD-SCH-3", "ORD-SCH-4"],
                       "driver B: only their assigned missions")
        XCTAssertEqual(Set(ids(rows(DispatchOfflineQuery(selectedDriverId: nil, dates: .all)))), Set(fleet.map(\.opuid)),
                       "All: every assigned mission, no unassigned one")
        let cached = store.loadIndex().entries.first { $0.missionKey == unassigned[0].key }
        XCTAssertNotNil(cached.flatMap { store.readyPackage(for: $0) }, "hidden, not deleted: it stays cached for a later assignment")
    }

    func testAnUnassignedMissionAppearsForItsDriverOnceAssignedAndReconciled() {
        // Cached while unassigned (an older revision)…
        download(fleet + [unassigned[0]])
        XCTAssertFalse(ids(rows(DispatchOfflineQuery(selectedDriverId: nil, dates: .all))).contains("ORD-SCH-UD"))

        // …then the office assigns it to Jerome: the next reconciliation brings the new revision.
        var assigned = unassigned[0]
        assigned.deliveryDriverId = jerome
        assigned.revision = F.revision("ud-assigned")
        download(fleet + [assigned])

        XCTAssertTrue(ids(rows(DispatchOfflineQuery(selectedDriverId: jerome, dates: .all))).contains("ORD-SCH-UD"), "the driver it was assigned to")
        XCTAssertFalse(ids(rows(DispatchOfflineQuery(selectedDriverId: gary, dates: .all))).contains("ORD-SCH-UD"),
                       "not the return leg's driver: the ACTIVE leg (the pending delivery) decides")
        XCTAssertFalse(ids(rows(DispatchOfflineQuery(selectedDriverId: blake, dates: .all))).contains("ORD-SCH-UD"))
        XCTAssertTrue(ids(rows(DispatchOfflineQuery(selectedDriverId: nil, dates: .all))).contains("ORD-SCH-UD"), "and All")

        // A mission the server never listed while unassigned appears the same way once it's assigned.
        let newlyListed = M(opuid: "ORD-SCH-NEW", revision: F.revision("new"), effectiveDate: today, deliveryDriverId: blake)
        download(fleet + [assigned, newlyListed])
        XCTAssertTrue(ids(rows(DispatchOfflineQuery(selectedDriverId: blake, dates: .all))).contains("ORD-SCH-NEW"))
    }

    /// The list screen filters live-feed and saved-list rows with the SAME predicate, reading the
    /// row's own `is_delivered` and employees. On identical rows it must present exactly what the
    /// offline working set presents, for every driver and for All.
    func testOnlineAndOfflinePresentationAgreeOnDriverMembership() {
        let missions = fleet + unassigned
        download(missions)
        for driver in [nil, gary, blake, jerome] as [Int?] {
            let offline = Set(ids(rows(DispatchOfflineQuery(selectedDriverId: driver, dates: .all))))
            let online = Set(missions.filter { m in
                let row = F.package(m)["dispatch"]?["row"]
                return DispatchWorkload.orderRowBelongs(selectedDriverId: driver,
                                                        isDelivered: row?["is_delivered"]?.boolValue == true,
                                                        deliveryEmployeeId: row?["delivery_employee"]?["id"]?.intValue,
                                                        pickupEmployeeId: row?["pickup_employee"]?["id"]?.intValue)
            }.map(\.opuid))
            XCTAssertEqual(online, offline, "driver \(driver.map(String.init) ?? "All")")
            XCTAssertFalse(online.contains("ORD-SCH-UD") || online.contains("ORD-SCH-UR"))
        }
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

    func testAnUnreadablePackageCountsAsMissing() throws {
        download(fleet)
        let entry = store.loadIndex().entry("ORD-SCH-3:delivery")!
        try Data("not json".utf8).write(to: store.packagesDirectory.appendingPathComponent(entry.packageFile!))
        let reopened = makeStore() // a new process: nothing decoded in memory

        guard case .ready(let rows, let freshness) = DispatchOfflineWorkingSet.present(
            store: reopened, query: DispatchOfflineQuery(dates: .all), operations: [], today: today) else { return XCTFail() }
        XCTAssertFalse(ids(rows).contains("ORD-SCH-3"))
        XCTAssertEqual(freshness.pendingCount, 1, "a mission the phone cannot show is missing, never current")
        XCTAssertFalse(freshness.isComplete)
    }

    func testEveryRowNamesWhenTheServerWasAskedForIt() {
        let asked = Date(timeIntervalSince1970: 1_790_000_000)
        server.missions = fleet
        let reconciler = DispatchOfflineReconciler(httpClient: server, store: store, session: { [unowned self] in .of(self.store) },
                                                   retainedOrderProducts: { [] }, now: { asked })
        let done = expectation(description: "download")
        reconciler.request(.launch) { _ in done.fulfill() }
        wait(for: [done], timeout: 5)

        let all = rows(DispatchOfflineQuery(dates: .all))
        XCTAssertEqual(all.count, 6)
        XCTAssertTrue(all.allSatisfy { $0.serverObservedAt == asked },
                      "server truth in a package is at least as new as its request (F2: later server confirmation)")
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

    private func downloaded(stale: Int = 0, pending: Int = 0) -> DispatchOfflinePresentation {
        .ready(rows: [], freshness: .init(lastManifestAt: Date(), throughDate: "2026-09-24", staleCount: stale, pendingCount: pending))
    }

    func testAReconciliationOutcomeAlwaysSettlesTheScreen() {
        // Never downloaded: online failure falls back to the live feed (never a permanent spinner);
        // offline says it is not downloaded.
        XCTAssertEqual(P.outcome(presentation: .notDownloaded, failed: true, online: true), .fallBackToFeed)
        XCTAssertEqual(P.outcome(presentation: .notDownloaded, failed: false, online: false), .showNotDownloaded)
        XCTAssertEqual(P.outcome(presentation: .notDownloaded, failed: true, online: false), .showNotDownloaded)
        // Downloaded: a failed/partial run is never presented as current; success clears the header.
        XCTAssertEqual(P.outcome(presentation: downloaded(), failed: true, online: true), .flagNotCurrent)
        XCTAssertEqual(P.outcome(presentation: downloaded(), failed: false, online: false), .flagOffline)
        XCTAssertEqual(P.outcome(presentation: downloaded(), failed: false, online: true), .current)
        // A successful first download renders normally.
        XCTAssertEqual(P.outcome(presentation: .notDownloaded, failed: false, online: true), .current)
    }

    func testTheCacheIsNeverCurrentWhileAnyMissionIsStaleOrMissing() {
        // Review F1: whatever the last answer said, an incomplete working set is flagged.
        XCTAssertEqual(P.outcome(presentation: downloaded(stale: 1), failed: false, online: true), .flagNotCurrent)
        XCTAssertEqual(P.outcome(presentation: downloaded(pending: 1), failed: false, online: true), .flagNotCurrent)
        XCTAssertEqual(P.outcome(presentation: downloaded(stale: 2, pending: 3), failed: true, online: true), .flagNotCurrent)
        XCTAssertEqual(P.outcome(presentation: downloaded(pending: 1), failed: false, online: false), .flagOffline)
        XCTAssertEqual(P.outcome(presentation: downloaded(), failed: false, online: true), .current)
    }

    func testWhichAnswersMeanTheListMayNotBeCurrent() {
        typealias R = DispatchOfflineReconcileResult
        XCTAssertFalse(P.indicatesFailure(R(status: .completed)))
        XCTAssertTrue(P.indicatesFailure(R(status: .partial)))
        XCTAssertTrue(P.indicatesFailure(R(status: .failed(.offline))))
        XCTAssertTrue(P.indicatesFailure(R(status: .skipped(.coolingDown))), "skipped because the last run failed")
        XCTAssertTrue(P.indicatesFailure(R(status: .skipped(.noSession))))
        XCTAssertFalse(P.indicatesFailure(R(status: .skipped(.fresh))))
        XCTAssertFalse(P.indicatesFailure(R(status: .skipped(.alreadyCurrent))))
    }

    func testOnlyARealOutcomeForTheSignedInCompanySettlesTheScreen() {
        typealias R = DispatchOfflineReconcileResult
        // Review F3: a run stopped by a session change is an outcome for nobody.
        XCTAssertFalse(P.postsReconcileOutcome(R(status: .failed(.sessionChanged))))
        XCTAssertFalse(P.postsReconcileOutcome(R(status: .partial, packageFailure: .sessionChanged)))
        XCTAssertFalse(P.postsReconcileOutcome(R(status: .skipped(.fresh))))
        XCTAssertTrue(P.postsReconcileOutcome(R(status: .completed)))
        XCTAssertTrue(P.postsReconcileOutcome(R(status: .partial, packageFailure: .offline)))
        XCTAssertTrue(P.postsReconcileOutcome(R(status: .failed(.offline))))
        // …and only the company it belongs to applies it.
        XCTAssertTrue(P.appliesReconcileOutcome(fromTenant: "aaaa", currentTenant: "aaaa"))
        XCTAssertFalse(P.appliesReconcileOutcome(fromTenant: "aaaa", currentTenant: "bbbb"))
        XCTAssertFalse(P.appliesReconcileOutcome(fromTenant: "aaaa", currentTenant: nil))
        XCTAssertFalse(P.appliesReconcileOutcome(fromTenant: nil, currentTenant: "aaaa"))
    }

    func testOnlyAMissingDownloadForcesARequestOnAFilterChange() {
        XCTAssertTrue(P.filterChangeNeedsFirstDownload(notDownloaded: true, online: true))
        XCTAssertFalse(P.filterChangeNeedsFirstDownload(notDownloaded: true, online: false), "offline: zero requests")
        XCTAssertFalse(P.filterChangeNeedsFirstDownload(notDownloaded: false, online: true), "downloaded: local filtering only")
    }
}

// MARK: - Live feed / Manual Dispatch request binding (review F4)

final class DispatchFeedRequestsTests: XCTestCase {

    private let gary = DispatchFeedScope(pending: true, scheduleType: "All", dateFilter: "All", driverId: "4",
                                         categoryId: "", search: "", transportMode: "Truck")

    func testADriverSwitchWhileARequestIsInFlightDiscardsItsAnswer() {
        let requests = DispatchFeedRequests()
        requests.restart()
        let garysRequest = requests.ticket(for: gary)

        // The employee switches Gary → Blake before Gary's answer lands.
        var blake = gary
        blake.driverId = "7"
        requests.restart()
        let blakesRequest = requests.ticket(for: blake)

        XCTAssertFalse(requests.accepts(garysRequest, currentScope: blake), "Gary's answer never replaces Blake's view")
        XCTAssertTrue(requests.accepts(blakesRequest, currentScope: blake))
    }

    func testEveryNonDriverFilterChangeObsoletesAnInFlightRequest() {
        let changes: [(String, (inout DispatchFeedScope) -> Void)] = [
            ("category", { $0.categoryId = "11" }),
            ("date", { $0.dateFilter = "Today" }),
            ("leg type", { $0.scheduleType = "Delivery" }),
            ("status", { $0.pending = false }),
            ("search", { $0.search = "Cash" }),
            ("transport", { $0.transportMode = "Store" }),
        ]
        for (what, change) in changes {
            let requests = DispatchFeedRequests()
            let inFlight = requests.ticket(for: gary)
            var now = gary
            change(&now)
            // Even without a restart (defence in depth), a different scope is never applied.
            XCTAssertFalse(requests.accepts(inFlight, currentScope: now), "\(what) change")
            requests.restart()
            XCTAssertFalse(requests.accepts(inFlight, currentScope: now), "\(what) change, after restart")
            XCTAssertTrue(requests.accepts(requests.ticket(for: now), currentScope: now))
        }
    }

    func testARefreshOfTheSameScopeObsoletesTheOlderRequest() {
        let requests = DispatchFeedRequests()
        let older = requests.ticket(for: gary)
        requests.restart() // pull-to-refresh / screen reopen: a new request generation
        XCTAssertFalse(requests.accepts(older, currentScope: gary))
    }

    func testTheNextPageOfTheSameListIsAccepted() {
        let requests = DispatchFeedRequests()
        requests.restart()
        let page1 = requests.ticket(for: gary)
        let page2 = requests.ticket(for: gary) // pagination: same generation, same scope
        XCTAssertTrue(requests.accepts(page1, currentScope: gary))
        XCTAssertTrue(requests.accepts(page2, currentScope: gary))
    }

    func testTheSearchScopeIgnoresSurroundingWhitespace() {
        var padded = gary
        padded.search = "  Cash "
        var trimmed = gary
        trimmed.search = "Cash"
        XCTAssertEqual(DispatchFeedScope(pending: true, scheduleType: "All", dateFilter: "All", driverId: "4",
                                         categoryId: "", search: "  Cash ", transportMode: "Truck").search, "Cash")
        XCTAssertEqual(DispatchFeedScope(pending: padded.pending, scheduleType: padded.scheduleType, dateFilter: padded.dateFilter,
                                         driverId: padded.driverId, categoryId: padded.categoryId, search: padded.search,
                                         transportMode: padded.transportMode), trimmed)
    }

    func testATicketRemembersWhenItsRequestWasSent() {
        let requests = DispatchFeedRequests()
        let sent = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(requests.ticket(for: gary, at: sent).startedAt, sent)
    }
}
