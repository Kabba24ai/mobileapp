import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Dispatch offline Phase 5 — every state of the one, local-first T&C screen.
final class TermsScreenPresentationTests: XCTestCase {

    private typealias P = TermsScreenPresentation

    private func agreement(_ order: String = "ORD-A") -> TermsAgreement {
        let entries = [TermsAgreement.Entry(isGlobal: false, content: "<p>Terms.</p>", signatureBlock: "")]
        return TermsAgreement(identity: TermsAgreement.computeIdentity(orderUniqueId: order, customerName: "Jane", entries: entries),
                              orderUniqueId: order, orderNumber: "#1", customerName: "Jane", approvalsRequired: 0, entries: entries)
    }

    private func block(_ status: TermsBlock.AgreementStatus?, agreement: TermsAgreement? = nil, termsStatus: String = "Pending") -> P.Live {
        .block(TermsBlock(status: termsStatus, pageUrl: "https://kabba.test/terms", agreementStatus: status, unavailableReason: nil, agreement: agreement))
    }

    private func signed(_ state: SyncState, order: String = "ORD-A", identity: String? = nil) -> SyncOperation {
        var op = SyncOperation(type: "terms.sign", capturedAt: Date(),
                               identity: SyncBusinessIdentity(orderUniqueId: order),
                               payload: .object(["terms_identity": .string(identity ?? agreement(order).identity)]))
        op.state = state
        return op
    }

    private func resolve(status: String = "Pending", live: P.Live? = nil, stored: TermsAgreement? = nil,
                         ops: [SyncOperation] = [], signUrl: String = "https://kabba.test/terms-and-conditions/ORD-A/mobile") -> P {
        P.resolve(.init(orderUniqueId: "ORD-A", knownTermsStatus: status, live: live, stored: stored, operations: ops, signUrl: signUrl))
    }

    func testExemptAndAcceptedOrdersAreNeverSignedAgain() {
        XCTAssertEqual(resolve(status: "Exempt", stored: agreement()), .notRequired)
        XCTAssertEqual(resolve(status: "Accepted", stored: agreement()), .alreadyAccepted)
        XCTAssertEqual(resolve(live: block(.notRequired, termsStatus: "Accepted")), .alreadyAccepted, "the live status wins")
    }

    func testOfflineTheStoredVerifiedAgreementIsTheDocument() {
        XCTAssertEqual(resolve(stored: agreement()), .document(agreement()))
    }

    func testOnlineTheLiveAgreementIsTheDocument() {
        XCTAssertEqual(resolve(live: block(.available, agreement: agreement())), .document(agreement()))
    }

    func testAnAgreementThatDoesNotVerifyIsNeverShown() {
        var tampered = agreement(); tampered.entries[0].content = "<p>Other.</p>"
        XCTAssertEqual(resolve(live: block(.available, agreement: tampered)), .unableToVerify)
        XCTAssertEqual(resolve(live: block(.available, agreement: agreement("ORD-B"))), .unableToVerify, "another order's document")
        XCTAssertEqual(resolve(live: block(.available, agreement: nil)), .unableToVerify)
        XCTAssertEqual(resolve(stored: agreement("ORD-B")), .unableToVerify)
    }

    func testAnOrderWithoutATrustworthyAgreementSaysSo() {
        XCTAssertEqual(resolve(live: block(.unavailable)), .agreementUnavailable)
        XCTAssertEqual(resolve(live: block(.notSignable)), .agreementUnavailable)
    }

    func testASignatureOnThisPhoneIsShownInsteadOfASecondCapture() {
        XCTAssertEqual(resolve(stored: agreement(), ops: [signed(.pending)]), .signedOnThisPhone(.pending))
        XCTAssertEqual(resolve(stored: agreement(), ops: [signed(.synced)]), .signedOnThisPhone(.synced))
        XCTAssertEqual(resolve(stored: agreement(), ops: [signed(.needsAttention)]), .document(agreement()),
                       "a refused signature never counts: the verified document can be signed")
        XCTAssertEqual(resolve(stored: agreement(), ops: [signed(.pending, identity: "v1:" + String(repeating: "c", count: 64))]),
                       .document(agreement()), "another document's signature")
        XCTAssertEqual(resolve(stored: agreement(), ops: [signed(.pending, order: "ORD-B")]), .document(agreement()))
    }

    func testNothingHeldSaysWhatHappenedNeverABlankPage() {
        XCTAssertEqual(resolve(), .notDownloaded, "offline")
        XCTAssertEqual(resolve(live: .failed), .couldNotLoad)
        XCTAssertEqual(resolve(live: .failed, stored: agreement()), .document(agreement()), "a failed fetch falls back to the stored copy")
        XCTAssertEqual(resolve(live: .unsupported), .hostedPage(URL(string: "https://kabba.test/terms-and-conditions/ORD-A/mobile")!),
                       "an older server: the hosted page, as before")
        XCTAssertEqual(resolve(live: .unsupported, signUrl: "not a url"), .unavailable)
    }
}
