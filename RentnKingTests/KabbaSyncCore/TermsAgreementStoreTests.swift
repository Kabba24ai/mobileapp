import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Dispatch offline Phase 5 — the phone's copy of each order's frozen agreement:
/// verified agreements only, per company (Amendment B), every identity retained.
final class TermsAgreementStoreTests: XCTestCase {

    private var root: URL!
    private var signedIn: String? = "tenantA"
    private var store: TermsAgreementStore!

    override func setUp() {
        super.setUp()
        root = Fixtures.tempDirectory(name)
        store = try! TermsAgreementStore(rootDirectory: root, tenantKey: { [unowned self] in self.signedIn })
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func agreement(_ order: String, _ text: String = "<p>Terms.</p>") -> TermsAgreement {
        let entries = [TermsAgreement.Entry(isGlobal: false, content: text, signatureBlock: "")]
        return TermsAgreement(identity: TermsAgreement.computeIdentity(orderUniqueId: order, customerName: "Jane", entries: entries),
                              orderUniqueId: order, orderNumber: "#1", customerName: "Jane", approvalsRequired: 0, entries: entries)
    }

    func testAVerifiedAgreementIsStoredAndServedForItsCompany() throws {
        try store.save(agreement("ORD-A"), tenantKey: "tenantA")

        XCTAssertEqual(store.current(orderUniqueId: "ORD-A"), agreement("ORD-A"))
        XCTAssertEqual(store.agreement(orderUniqueId: "ORD-A", identity: agreement("ORD-A").identity), agreement("ORD-A"))
    }

    /// Phase 5 hardening: the server's "this order has no trustworthy agreement" is remembered per
    /// company, so the screen can say so offline; the newest report wins either way, and every
    /// identity already stored is kept as local evidence.
    func testAnOrderReportedUnavailableIsRememberedPerCompanyAndTheNewestReportWins() throws {
        try store.recordUnavailable(orderUniqueId: "ORD-A", tenantKey: "tenantA")
        XCTAssertTrue(store.isUnavailable(orderUniqueId: "ORD-A"))
        XCTAssertFalse(store.isUnavailable(orderUniqueId: "ORD-A", tenantKey: "tenantB"), "per company")
        XCTAssertFalse(store.isUnavailable(orderUniqueId: "ORD-B"))
        XCTAssertNil(store.current(orderUniqueId: "ORD-A"))

        try store.save(agreement("ORD-A"), tenantKey: "tenantA")
        XCTAssertFalse(store.isUnavailable(orderUniqueId: "ORD-A"), "a verified agreement replaces the report")
        XCTAssertEqual(store.current(orderUniqueId: "ORD-A"), agreement("ORD-A"))

        try store.recordUnavailable(orderUniqueId: "ORD-A", tenantKey: "tenantA")
        XCTAssertTrue(store.isUnavailable(orderUniqueId: "ORD-A"))
        XCTAssertNil(store.current(orderUniqueId: "ORD-A"), "a newer report: nothing is offered for signing")
        XCTAssertEqual(store.agreement(orderUniqueId: "ORD-A", identity: agreement("ORD-A").identity), agreement("ORD-A"),
                       "the identity already stored is kept as local evidence")

        signedIn = nil
        XCTAssertFalse(store.isUnavailable(orderUniqueId: "ORD-A"), "no company signed in: nothing")
    }

    func testAnUnverifiedAgreementIsNeverStored() {
        var tampered = agreement("ORD-A"); tampered.entries[0].content = "<p>Other.</p>"
        XCTAssertThrowsError(try store.save(tampered, tenantKey: "tenantA")) { error in
            XCTAssertEqual(error as? TermsAgreementStoreError, .unverified)
        }
        XCTAssertNil(store.current(orderUniqueId: "ORD-A"))
    }

    func testCompaniesNeverSeeEachOthersAgreements() throws {
        try store.save(agreement("ORD-A"), tenantKey: "tenantA")

        signedIn = "tenantB"
        XCTAssertNil(store.current(orderUniqueId: "ORD-A"), "no Company A data under Company B")
        signedIn = nil
        XCTAssertNil(store.current(orderUniqueId: "ORD-A"), "signed out reads nothing")
        signedIn = "tenantA"
        XCTAssertNotNil(store.current(orderUniqueId: "ORD-A"), "A's copy is still usable")
    }

    func testEveryIdentityIsRetainedAndTheNewestIsCurrent() throws {
        let first = agreement("ORD-A", "<p>First.</p>")
        let second = agreement("ORD-A", "<p>Second.</p>")
        try store.save(first, tenantKey: "tenantA")
        try store.save(second, tenantKey: "tenantA")

        XCTAssertEqual(store.current(orderUniqueId: "ORD-A"), second)
        XCTAssertEqual(store.agreement(orderUniqueId: "ORD-A", identity: first.identity), first, "kept as local evidence")
    }

    func testADamagedFileIsNeverServed() throws {
        try store.save(agreement("ORD-A"), tenantKey: "tenantA")
        let dir = root.appendingPathComponent("terms-agreements/tenantA/ORD-A", isDirectory: true)
        var raw = try String(contentsOf: dir.appendingPathComponent("current.json"), encoding: .utf8)
        raw = raw.replacingOccurrences(of: "Terms.", with: "Forged.")
        try raw.write(to: dir.appendingPathComponent("current.json"), atomically: true, encoding: .utf8)

        XCTAssertNil(store.current(orderUniqueId: "ORD-A"), "re-verified on every read")
    }
}
