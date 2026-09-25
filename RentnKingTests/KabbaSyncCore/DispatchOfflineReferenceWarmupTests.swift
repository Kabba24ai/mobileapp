//
//  DispatchOfflineReferenceWarmupTests.swift
//  Dispatch offline Phase 4 (P4-D6): the reference lists the offline checklist
//  and Order Details read are refreshed only after a reconciliation on launch,
//  login, foreground or network restored — never a wake, a Dispatch open, a
//  manual refresh or a timer — and only when empty or older than 12 hours.
//

import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class DispatchOfflineReferenceWarmupTests: XCTestCase {

    private typealias W = DispatchOfflineReferenceWarmup
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func result(_ status: DispatchOfflineReconcileResult.Status) -> DispatchOfflineReconcileResult {
        DispatchOfflineReconcileResult(status: status)
    }

    func testItRunsOnlyAfterTheFourListedTriggers() {
        for trigger in [DispatchOfflineTrigger.launch, .loginCompleted, .foreground, .networkRestored] {
            XCTAssertTrue(W.runs(after: trigger, result: result(.completed)), "\(trigger)")
        }
        for trigger in [DispatchOfflineTrigger.wake(revision: "r1"), .wake(revision: nil), .dispatchScreenOpened, .manualRefresh] {
            XCTAssertFalse(W.runs(after: trigger, result: result(.completed)), "\(trigger) never warms lists")
        }
    }

    func testItRunsOnlyWhenTheServerWasJustReachable() {
        XCTAssertTrue(W.runs(after: .launch, result: result(.partial)))
        XCTAssertTrue(W.runs(after: .foreground, result: result(.skipped(.fresh))), "reconciled moments ago")
        XCTAssertTrue(W.runs(after: .foreground, result: result(.skipped(.alreadyCurrent))))
        XCTAssertFalse(W.runs(after: .launch, result: result(.failed(.offline))))
        XCTAssertFalse(W.runs(after: .networkRestored, result: result(.failed(.server(503)))))
        XCTAssertFalse(W.runs(after: .launch, result: result(.skipped(.noSession))), "signed out: nothing requested")
        XCTAssertFalse(W.runs(after: .foreground, result: result(.skipped(.coolingDown))), "the server just failed")
    }

    func testAListIsRefreshedOnlyWhenEmptyOrOlderThanTwelveHours() {
        XCTAssertTrue(W.isDue(isEmpty: true, lastWarmedAt: now, now: now), "empty: always")
        XCTAssertTrue(W.isDue(isEmpty: false, lastWarmedAt: nil, now: now), "never warmed for this company")
        XCTAssertFalse(W.isDue(isEmpty: false, lastWarmedAt: now.addingTimeInterval(-11 * 3600), now: now))
        XCTAssertFalse(W.isDue(isEmpty: false, lastWarmedAt: now.addingTimeInterval(-12 * 3600), now: now))
        XCTAssertTrue(W.isDue(isEmpty: false, lastWarmedAt: now.addingTimeInterval(-12 * 3600 - 1), now: now))
        XCTAssertTrue(W.isDue(isEmpty: false, lastWarmedAt: now.addingTimeInterval(3600), now: now),
                      "a stamp in the future (clock changed) never blocks a refresh")
    }

    func testTheListsAreTheOnesTheOfflineScreensRead() {
        XCTAssertEqual(Set(W.List.allCases.map(\.rawValue)),
                       ["employees", "drivers", "equipment", "stores", "categories", "prices", "users"])
    }

    func testTheStampKeysAreCompanyScoped() {
        let a = DispatchOfflineTenantStorage.storageKey(W.stampKey(.equipment), tenantKey: "aaaaaaaaaaaaaaaa")
        let b = DispatchOfflineTenantStorage.storageKey(W.stampKey(.equipment), tenantKey: "bbbbbbbbbbbbbbbb")
        XCTAssertNotNil(a)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, W.stampKey(.equipment))
        XCTAssertNil(DispatchOfflineTenantStorage.storageKey(W.stampKey(.equipment), tenantKey: nil), "signed out: no stamp")
    }
}
