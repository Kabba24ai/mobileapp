//
//  ChecklistFinalizationPresentation.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The final checklist screen (CheckListUpdateViewController, shared by the
//  Delivery and Return legs) ends with two actions and one number:
//
//      [ Customer Signature ]   [ Submit ]
//      ┌──────────────────────────────────┐
//      │ Total Charge              $0.00  │
//      └──────────────────────────────────┘
//
//  Everything visible there derives from THIS state — never from whichever
//  button was tapped last:
//    • unsigned  → Customer Signature is the active (yellow) next action and
//                  Submit is gray AND non-interactive;
//    • signed    → the signature button reads "✓ Customer Signed" in the
//                  completed gray, Submit becomes the active yellow action;
//    • the charge panel is green at $0.00 and red for a positive charge, so
//                  the customer-facing amount is impossible to miss right
//                  before submission. A negative value (credit) has no approved
//                  presentation yet and keeps the neutral style.
//
//  The screen's existing "replace / delete equipment" mode never required a
//  signature; its destructive Submit stays usable.
//
//  Presentation only: it does not compute, round or change the charge. The
//  formatter is exactly the pre-existing "\(currency)\(String(format: "%.2f"))".
//

import Foundation

struct ChecklistFinalizationPresentation: Equatable {

    enum SignatureState: Equatable {
        /// No customer signature captured yet — it is the next action.
        case required
        /// A signature exists (drawn on this phone or already on the server).
        case captured
    }

    enum ChargeState: Equatable {
        /// Displays as $0.00 (|amount| < half a cent).
        case zero
        /// The customer owes money.
        case due
        /// Negative total — no approved styling; report rather than invent.
        case credit
    }

    /// The visual role of a button. The screen maps roles to its palette.
    enum ButtonTone: Equatable {
        case activeYellow
        case completedGray
        case disabledGray
        case destructiveRed
    }

    /// The accent (border + amount colour) of the Total Charge panel.
    enum ChargeAccent: Equatable {
        case green
        case red
        case neutral
    }

    static let signatureRequiredTitle = "Customer Signature"
    static let signatureCapturedTitle = "✓ Customer Signed"

    let signature: SignatureState
    let charge: ChargeState
    let isDeleteMode: Bool

    init(hasSignature: Bool, totalCharge: Double, isDeleteMode: Bool = false) {
        self.signature = hasSignature ? .captured : .required
        self.charge = Self.chargeState(for: totalCharge)
        self.isDeleteMode = isDeleteMode
    }

    // MARK: Signature button

    var signatureTitle: String {
        signature == .captured ? Self.signatureCapturedTitle : Self.signatureRequiredTitle
    }

    var signatureTone: ButtonTone {
        signature == .captured ? .completedGray : .activeYellow
    }

    // MARK: Submit button

    /// Submit is genuinely non-interactive until the signature exists —
    /// except in delete mode, which never had a signature step.
    var submitIsEnabled: Bool {
        isDeleteMode || signature == .captured
    }

    var submitTone: ButtonTone {
        if isDeleteMode { return .destructiveRed }
        return submitIsEnabled ? .activeYellow : .disabledGray
    }

    // MARK: Charge panel

    var chargeAccent: ChargeAccent {
        switch charge {
        case .zero:   return .green
        case .due:    return .red
        case .credit: return .neutral
        }
    }

    /// Anything that still displays as $0.00 is zero; the screen never
    /// compares formatted strings.
    static func chargeState(for amount: Double) -> ChargeState {
        if amount.isNaN || abs(amount) < 0.005 { return .zero }
        return amount > 0 ? .due : .credit
    }

    /// The pre-existing currency presentation, unchanged.
    static func formattedCharge(_ amount: Double, currency: String) -> String {
        "\(currency)\(String(format: "%.2f", amount))"
    }
}
