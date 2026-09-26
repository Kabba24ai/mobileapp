import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Dispatch offline Phase 5 — the order's frozen Terms agreement on the phone:
/// the kabba-order-terms v1 identity (pinned to Laravel by the shared vectors,
/// computed independently of both implementations), verification before
/// anything is shown or signed, the inert renderer, and the `terms` block.
final class TermsAgreementTests: XCTestCase {

    private typealias F = DispatchOfflineFixtures

    private func agreement(order: String = "ORD-TEST-0001", name: String = "Jane Doe") -> TermsAgreement {
        let entries = [
            TermsAgreement.Entry(isGlobal: true, content: "<p>Standard terms.</p>[product_terms][/product_terms]",
                                 signatureBlock: "<p>[customer_name][/customer_name] [customer_signature][/customer_signature]</p>"),
            TermsAgreement.Entry(isGlobal: false, content: "<p>Addendum.</p>[customer_approval][/customer_approval]", signatureBlock: ""),
        ]
        return TermsAgreement(identity: TermsAgreement.computeIdentity(orderUniqueId: order, customerName: name, entries: entries),
                              orderUniqueId: order, orderNumber: "#1234", customerName: name, approvalsRequired: 1, entries: entries)
    }

    // MARK: - Identity (shared with Laravel)

    func testTheSharedVectorsReproduceExactlyTheCanonicalBytesAndIdentity() throws {
        let root = try XCTUnwrap(JSONValue.parse(F.data("terms_agreement_identity")))
        let vectors = try XCTUnwrap(root["vectors"]?.arrayValue)
        XCTAssertGreaterThanOrEqual(vectors.count, 4)

        for vector in vectors {
            let name = vector["name"]?.stringValue ?? "?"
            let entries = try XCTUnwrap(vector["entries"]?.arrayValue).map { item in
                TermsAgreement.Entry(isGlobal: item["is_global"]?.boolValue ?? false,
                                     content: item["content"]?.stringValue ?? "",
                                     signatureBlock: item["signature_block"]?.stringValue ?? "")
            }
            let order = try XCTUnwrap(vector["order_unique_id"]?.stringValue)
            let customer = try XCTUnwrap(vector["customer_name"]?.stringValue)
            let bytes = TermsAgreement.canonicalBytes(orderUniqueId: order, customerName: customer, entries: entries)

            XCTAssertEqual(bytes, Data(base64Encoded: try XCTUnwrap(vector["canonical_base64"]?.stringValue)), "\(name): canonical bytes")
            XCTAssertEqual(TermsAgreement.computeIdentity(orderUniqueId: order, customerName: customer, entries: entries),
                           vector["identity"]?.stringValue, "\(name): identity")
        }
    }

    func testLineEndingsAreNormalizedAndNothingElseIs() {
        let lf = TermsAgreement.Entry(isGlobal: false, content: "a\nb\nc", signatureBlock: "")
        let crlf = TermsAgreement.Entry(isGlobal: false, content: "a\r\nb\rc", signatureBlock: "")
        XCTAssertEqual(TermsAgreement.computeIdentity(orderUniqueId: "O", customerName: "N", entries: [lf]),
                       TermsAgreement.computeIdentity(orderUniqueId: "O", customerName: "N", entries: [crlf]))

        // No Unicode normalization: é (U+00E9) and e + U+0301 are different contract text.
        let composed = TermsAgreement.Entry(isGlobal: false, content: "caf\u{00E9}", signatureBlock: "")
        let decomposed = TermsAgreement.Entry(isGlobal: false, content: "cafe\u{0301}", signatureBlock: "")
        XCTAssertNotEqual(TermsAgreement.computeIdentity(orderUniqueId: "O", customerName: "N", entries: [composed]),
                          TermsAgreement.computeIdentity(orderUniqueId: "O", customerName: "N", entries: [decomposed]))
    }

    func testTheIdentityIsBoundToTheOrderAndTheCustomerSubstitution() {
        XCTAssertNotEqual(agreement(order: "ORD-A").identity, agreement(order: "ORD-B").identity, "same text, another order")
        XCTAssertNotEqual(agreement(name: "Jane Doe").identity, agreement(name: "Jane Dough").identity)
    }

    // MARK: - Verification (before anything is shown or signed)

    func testAnIntactAgreementVerifiesOnlyForItsOwnOrder() {
        let a = agreement(order: "ORD-A")
        XCTAssertTrue(a.isVerified(forOrder: "ORD-A"))
        XCTAssertFalse(a.isVerified(forOrder: "ORD-B"), "another order's document")
        XCTAssertFalse(a.isVerified(forOrder: ""))
    }

    func testATamperedOrInconsistentAgreementNeverVerifies() {
        var content = agreement(order: "ORD-A"); content.entries[1].content = "<p>Changed.</p>"
        var name = agreement(order: "ORD-A"); name.customerName = "Someone Else"
        var approvals = agreement(order: "ORD-A"); approvals.approvalsRequired = 0
        var identity = agreement(order: "ORD-A"); identity.identity = "v1:" + String(repeating: "0", count: 64)
        var format = agreement(order: "ORD-A"); format.identity = "sha256:" + String(repeating: "0", count: 64)
        var empty = agreement(order: "ORD-A"); empty.entries = []; empty.approvalsRequired = 0
        empty.identity = empty.recomputedIdentity

        for (label, a) in [("content", content), ("name", name), ("approvals", approvals), ("identity", identity), ("format", format), ("empty", empty)] {
            XCTAssertFalse(a.isVerified(forOrder: "ORD-A"), label)
        }
    }

    func testTheServersAgreementDecodesAndVerifies() throws {
        let live = try XCTUnwrap(JSONValue.parse(F.data("terms_agreement")))
        let block = try XCTUnwrap(TermsBlock.decode(live["data"]))
        XCTAssertEqual(block.agreementStatus, .available)
        XCTAssertEqual(block.status, "Pending")
        let agreement = try XCTUnwrap(block.agreement)
        XCTAssertTrue(agreement.isVerified(forOrder: agreement.orderUniqueId), "Laravel's identity recomputes on the phone")

        let packaged = try XCTUnwrap(DispatchOfflinePackageContent.terms(F.packageTemplate)?.agreement)
        XCTAssertTrue(packaged.isVerified(forOrder: "ORD-BJVZ-CSDO"))
        XCTAssertEqual(DispatchOfflinePackageSections.from(F.packageTemplate)?.terms, .ok)
    }

    func testTheTermsBlockReportsUnavailableAndNotRequiredAgreements() {
        let unavailable = TermsBlock.decode(.object([
            "status": .string("Pending"), "page_url": .string(""), "agreement_status": .string("unavailable"),
            "unavailable_reason": .string("no_stored_agreement"), "agreement": .null,
        ]))
        XCTAssertEqual(unavailable?.agreementStatus, .unavailable)
        XCTAssertEqual(unavailable?.unavailableReason, "no_stored_agreement")
        XCTAssertNil(unavailable?.agreement)

        let accepted = TermsBlock.decode(.object(["status": .string("Accepted"), "agreement_status": .string("not_required"), "agreement": .null]))
        XCTAssertEqual(accepted?.agreementStatus, .notRequired)
        XCTAssertNil(TermsAgreement.decode(.object(["identity": .string("v1:x")])), "not an agreement")
    }

    // MARK: - Renderer (presentation only)

    func testTheBodyPlacesInertMarkersWhereThePageHasControls() {
        let body = TermsAgreementRenderer.bodyHTML(agreement())

        XCTAssertEqual(body, "<p>Standard terms.</p><p>Addendum.</p>\(TermsAgreementRenderer.approvalMarker)"
                       + "<p>Jane Doe \(TermsAgreementRenderer.signMarker)</p>")
        XCTAssertFalse(body.contains("[customer_approval]"))
        XCTAssertFalse(body.contains("<input"), "no active controls — the page adds its own")
    }

    func testTheCustomerNameIsEscapedAndAddendaStandAloneWithoutStandardTerms() {
        let entries = [TermsAgreement.Entry(isGlobal: true, content: "[product_terms][/product_terms]", signatureBlock: "[customer_name][/customer_name]")]
        let hostile = TermsAgreement(identity: "", orderUniqueId: "O", orderNumber: "", customerName: "<img src=x onerror=alert(1)>",
                                     approvalsRequired: 0, entries: entries)
        XCTAssertEqual(TermsAgreementRenderer.bodyHTML(hostile), "&lt;img src=x onerror=alert(1)&gt;")

        let addendaOnly = TermsAgreement(identity: "", orderUniqueId: "O", orderNumber: "", customerName: "N", approvalsRequired: 0,
                                         entries: [.init(isGlobal: false, content: "<p>One</p>", signatureBlock: "<p>unused</p>"),
                                                   .init(isGlobal: false, content: "<p>Two</p>", signatureBlock: "")])
        XCTAssertEqual(TermsAgreementRenderer.bodyHTML(addendaOnly), "<p>One</p>\n<p>Two</p>")
    }
}
