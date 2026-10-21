//
//  QueueLinePayment.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The Queue Line card's payment badge (MOBILE-QUALITY-01, item 08): ALWAYS exactly
//  Paid or Pending, next to the equipment's availability.
//
//  The classification is Kabba's (QueueLinePaymentClassification on the server: paid
//  in full, No Cost, or On Account for an approved credit account = Paid; anything
//  still to collect = Pending; unknown or inconsistent = Pending, flagged for review).
//  The phone never re-implements it. A board served before that classification
//  existed only has the latest payment row's raw status (payment_label); then only
//  "Paid" reads Paid — everything else, On Account included, is Pending: the phone
//  cannot tell an approved account from an unapproved one, so it never guesses Paid.
//  Operational priority only; nothing here is a financial record.
//

import Foundation

struct QueueLinePaymentBadge: Equatable {
    let isPaid: Bool
    /// Kabba flagged the order's payment state as unknown or inconsistent.
    let needsReview: Bool
    let reviewReason: String?

    var text: String { isPaid ? "Paid" : "Pending" }

    var accessibilityLabel: String {
        if needsReview {
            return "Payment Pending, needs review" + (reviewReason.map { ": \($0)" } ?? "")
        }
        return "Payment \(text)"
    }

    /// - Parameters:
    ///   - status: the server's `payment.status` ("paid" / "pending"), nil on an older board.
    ///   - legacyLabel: `payment_label`, the latest payment row's raw status (older boards).
    static func resolve(status: String?, needsReview: Bool?, reviewReason: String?, legacyLabel: String?) -> QueueLinePaymentBadge {
        let trimmed = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "paid":
            return QueueLinePaymentBadge(isPaid: true, needsReview: false, reviewReason: nil)
        case "pending":
            return QueueLinePaymentBadge(isPaid: false, needsReview: needsReview ?? false, reviewReason: reviewReason)
        case nil, "":
            let legacy = legacyLabel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return QueueLinePaymentBadge(isPaid: legacy == "paid", needsReview: false, reviewReason: nil)
        default:
            // A classification this app does not know: never Paid.
            return QueueLinePaymentBadge(isPaid: false, needsReview: true, reviewReason: "Unrecognised payment status \(status ?? "")")
        }
    }
}
