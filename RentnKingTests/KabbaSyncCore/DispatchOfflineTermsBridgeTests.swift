//
//  DispatchOfflineTermsBridgeTests.swift
//  Dispatch offline Phase 5 — the bridge writes each Delivery package's
//  FROZEN Terms agreement into TermsAgreementStore (verified only, per
//  company), and the terms section joins Amendment A's readiness: a Delivery
//  is fully prepared only with its agreement; a failed or unverifiable one is
//  retried at the same revision; an order without a trustworthy stored
//  agreement is settled but never ready; Return is unchanged.
//

import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class DispatchOfflineTermsBridgeTests: XCTestCase {

    private typealias F = DispatchOfflineFixtures
    private typealias M = DispatchOfflineFixtures.Mission

    private let tenantA = URL(string: "https://api.kabba.ai/api/admin/v1/")!
    private let tenantB = URL(string: "https://api.rentnking.com/api/admin/v1/")!

    private var root: URL!
    private var server: FakeDispatchServer!
    private var store: DispatchOfflineMissionStore!
    private var contexts: ChecklistContextStore!
    private var agreements: TermsAgreementStore!
    private var writer: RecordingOrderCacheWriter!
    private var signedInTenant: String?
    private var clock = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        root = Fixtures.tempDirectory(name)
        server = FakeDispatchServer()
        store = try! DispatchOfflineMissionStore(rootDirectory: root, baseURL: tenantA)
        signedInTenant = store.tenantKey
        contexts = try! ChecklistContextStore(rootDirectory: root, tenantKey: { [unowned self] in self.signedInTenant })
        agreements = try! TermsAgreementStore(rootDirectory: root, tenantKey: { [unowned self] in self.signedInTenant })
        writer = RecordingOrderCacheWriter()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeBridge(_ s: DispatchOfflineMissionStore? = nil) -> DispatchOfflineFieldBridge {
        DispatchOfflineFieldBridge(store: s ?? store, contexts: contexts, agreements: agreements, writer: writer,
                                   operations: { [] }, currentEmployee: { nil })
    }

    private func makeReconciler(_ s: DispatchOfflineMissionStore? = nil) -> DispatchOfflineReconciler {
        let s = s ?? store!
        let r = DispatchOfflineReconciler(httpClient: server, store: s,
                                          session: { [unowned self] in self.signedInTenant == s.tenantKey ? .of(s) : nil },
                                          retainedOrderProducts: { [] }, now: { [unowned self] in self.clock })
        r.fieldBridge = makeBridge(s)
        return r
    }

    private lazy var reconciler: DispatchOfflineReconciler = makeReconciler()

    @discardableResult
    private func reconcile(_ trigger: DispatchOfflineTrigger = .manualRefresh, on r: DispatchOfflineReconciler? = nil) -> DispatchOfflineReconcileResult {
        let done = expectation(description: "reconcile")
        var out: DispatchOfflineReconcileResult!
        (r ?? reconciler).request(trigger) { out = $0; done.fulfill() }
        wait(for: [done], timeout: 5)
        return out
    }

    private func m(_ id: String, _ rev: String, leg: ChecklistLeg = .delivery) -> M {
        M(opuid: "ORD-SCH-\(id)", leg: leg, revision: F.revision(rev), orderUid: "ORD-\(id)", executionId: "ORD-CHK-\(id)")
    }

    private var index: DispatchOfflineIndex { store.loadIndex() }
    private func entry(_ mission: M) -> DispatchOfflineIndex.Entry { index.entry(mission.key)! }
    private func stored(_ order: String) -> TermsAgreement? { agreements.current(orderUniqueId: order, tenantKey: store.tenantKey) }
    private func ledgerTerms(_ mission: M) -> DispatchOfflineFieldLedger.SectionState? {
        store.loadFieldLedger().missions[mission.key]?.terms
    }

    // MARK: - Bridging

    func testANeverOpenedDeliveryStoresItsVerifiedAgreementAndIsFieldReady() {
        let a = m("A", "a1")
        server.missions = [a]

        reconcile(.launch)

        let agreement = stored("ORD-A")
        XCTAssertNotNil(agreement)
        XCTAssertTrue(agreement?.isVerified(forOrder: "ORD-A") ?? false)
        XCTAssertEqual(agreement?.identity, F.agreement(a).identity)
        XCTAssertEqual(ledgerTerms(a), .satisfied)
        XCTAssertTrue(makeBridge().isFieldReady(entry(a)), "Delivery = base + order_details + assembly + context + terms")
    }

    func testAnAgreementThatDoesNotVerifyIsNeverStoredAndIsRetriedAtTheSameRevision() {
        var a = m("A", "a1")
        a.tamperedTerms = true
        server.missions = [a]

        reconcile(.launch)

        XCTAssertNil(stored("ORD-A"), "an unverifiable document is never kept")
        XCTAssertEqual(ledgerTerms(a), .invalid)
        XCTAssertFalse(makeBridge().isFieldReady(entry(a)))
        XCTAssertTrue(makeBridge().needsSectionRepair(entry(a)))

        a.tamperedTerms = false
        server.missions = [a]
        clock = clock.addingTimeInterval(30)
        reconcile()

        XCTAssertEqual(entry(a).readyRevision, a.revision, "the same revision")
        XCTAssertNotNil(stored("ORD-A"))
        XCTAssertTrue(makeBridge().isFieldReady(entry(a)))
    }

    func testAFailedTermsSectionKeepsTheRestAndRepairsAtTheSameRevision() {
        var a = m("A", "a1")
        a.termsSection = "failed"
        server.missions = [a]

        let first = reconcile(.launch)

        XCTAssertEqual(first.status, .completed, "a failed section never fails Dispatch")
        XCTAssertNotNil(writer.orderDetails("ORD-A", tenant: store.tenantKey))
        XCTAssertEqual(ledgerTerms(a), .failed)
        XCTAssertFalse(makeBridge().isFieldReady(entry(a)))
        XCTAssertTrue(makeBridge().needsSectionRepair(entry(a)))

        a.termsSection = nil
        server.missions = [a]
        clock = clock.addingTimeInterval(30)
        reconcile()

        XCTAssertTrue(makeBridge().isFieldReady(entry(a)))
        XCTAssertNotNil(stored("ORD-A"))
    }

    func testAnOrderWithoutATrustworthyAgreementIsSettledButNeverReady() {
        var a = m("A", "a1")
        a.termsSection = "unavailable"
        server.missions = [a]

        reconcile(.launch)
        let requests = server.packageRequests.count
        clock = clock.addingTimeInterval(30)
        reconcile()

        XCTAssertEqual(ledgerTerms(a), .unavailable)
        XCTAssertNil(stored("ORD-A"), "nothing is invented")
        XCTAssertFalse(makeBridge().isFieldReady(entry(a)), "not fully prepared for signing")
        XCTAssertFalse(makeBridge().needsSectionRepair(entry(a)), "retrying cannot help")
        XCTAssertEqual(server.packageRequests.count, requests, "never re-downloaded for it")
    }

    func testAReturnCarriesNoAgreementAndItsReadinessIsUnchanged() {
        let r = m("R", "r1", leg: .return)
        server.missions = [r]

        reconcile(.launch)

        XCTAssertNil(stored("ORD-R"))
        XCTAssertEqual(ledgerTerms(r), .notApplicable)
        XCTAssertTrue(makeBridge().isFieldReady(entry(r)), "Return = base + order_details + checklist_context")
    }

    func testAPrePhase5ServerKeepsPhase4Readiness() {
        var a = m("A", "a1")
        a.termsSection = "absent"
        server.missions = [a]

        reconcile(.launch)

        XCTAssertEqual(ledgerTerms(a), .notProvided)
        XCTAssertTrue(makeBridge().isFieldReady(entry(a)), "T&C then works as in Phase 4")
        XCTAssertFalse(makeBridge().needsSectionRepair(entry(a)))
    }

    func testANewerLiveAgreementIsNeverOverwrittenByAnOlderPackage() {
        let a = m("A", "a1")
        server.missions = [a]
        reconcile(.launch)
        let packaged = stored("ORD-A")!

        // A live fetch asked later saved a (hypothetically different) verified copy.
        var live = packaged
        live.entries[0].content += "<p>live</p>"
        live.identity = live.recomputedIdentity
        XCTAssertTrue(store.saveLiveCopy(.terms, orderUniqueId: "ORD-A", askedAt: clock.addingTimeInterval(600)) {
            (try? agreements.save(live, tenantKey: store.tenantKey)) != nil
        })

        var newer = a
        newer.revision = F.revision("a2")
        server.missions = [newer]
        clock = clock.addingTimeInterval(60)
        reconcile()

        XCTAssertEqual(stored("ORD-A"), live, "the newer copy stays")
        XCTAssertEqual(agreements.agreement(orderUniqueId: "ORD-A", identity: packaged.identity, tenantKey: store.tenantKey), packaged,
                       "and the packaged one is still retained")
    }

    func testCompanyBNeverSeesCompanyAsAgreementAndAKeepsIt() throws {
        let a = m("A", "a1")
        server.missions = [a]
        reconcile(.launch)
        XCTAssertNotNil(agreements.current(orderUniqueId: "ORD-A"))

        let storeB = try DispatchOfflineMissionStore(rootDirectory: root, baseURL: tenantB)
        signedInTenant = storeB.tenantKey
        XCTAssertNil(agreements.current(orderUniqueId: "ORD-A"), "no Company A agreement under Company B")

        signedInTenant = store.tenantKey
        XCTAssertNotNil(agreements.current(orderUniqueId: "ORD-A"), "back to A: still usable offline")
    }
}
