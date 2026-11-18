//
//  QueueLinePaymentTests.swift
//  KabbaSyncCoreTests — MOBILE-QUALITY-01 item 08: a Queue Line card always shows exactly
//  Paid or Pending; the server's classification wins; an older board never reads On
//  Account (or anything else but a "Paid" latest payment) as Paid.
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class QueueLinePaymentTests: XCTestCase {

    func testTheServersClassificationWins() {
        let paid = QueueLinePaymentBadge.resolve(status: "paid", needsReview: nil, reviewReason: nil, legacyLabel: "Account")
        XCTAssertTrue(paid.isPaid, "On Account for an approved credit account is Paid when Kabba says so")
        XCTAssertEqual(paid.text, "Paid")
        XCTAssertEqual(paid.accessibilityLabel, "Payment Paid")

        let pending = QueueLinePaymentBadge.resolve(status: "pending", needsReview: false, reviewReason: nil, legacyLabel: "Paid")
        XCTAssertFalse(pending.isPaid, "the row status never overrides the order-level classification")
        XCTAssertEqual(pending.text, "Pending")
    }

    func testAFlaggedPaymentIsPendingAndSaysWhy() {
        let review = QueueLinePaymentBadge.resolve(status: "pending", needsReview: true,
                                                   reviewReason: "Marked On Account, but the customer has no approved credit account.",
                                                   legacyLabel: "Account")
        XCTAssertFalse(review.isPaid)
        XCTAssertTrue(review.needsReview)
        XCTAssertEqual(review.accessibilityLabel, "Payment Pending, needs review: Marked On Account, but the customer has no approved credit account.")
    }

    func testAnOlderBoardFallsBackConservatively() {
        // The latest row's raw status says nothing about the whole order (a deposit's latest row can
        // read "Paid"), so without Kabba's classification every card is Pending.
        for legacy: String? in ["Paid", "Account", "Partial Payment", "Pending", "No Payment Recorded", "Invoice Cash", nil, ""] {
            let badge = QueueLinePaymentBadge.resolve(status: nil, needsReview: nil, reviewReason: nil, legacyLabel: legacy)
            XCTAssertFalse(badge.isPaid, "\(String(describing: legacy)) must not read Paid without Kabba's classification")
            XCTAssertEqual(badge.text, "Pending")
        }
    }

    func testAnUnknownClassificationIsNeverPaid() {
        let odd = QueueLinePaymentBadge.resolve(status: "settled", needsReview: false, reviewReason: nil, legacyLabel: "Paid")
        XCTAssertFalse(odd.isPaid)
        XCTAssertTrue(odd.needsReview)
    }

    func testTheSharedBoardFixtureCarriesTheClassification() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/queue_line_board_item.json")
        let item = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let payment = try XCTUnwrap(item["payment"] as? [String: Any])
        XCTAssertEqual(payment["status"] as? String, "pending")
        XCTAssertEqual(payment["label"] as? String, "Pending")
        XCTAssertNotNil(item["payment_label"], "the raw label stays for older apps")
    }
}
