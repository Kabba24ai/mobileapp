import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Checklist finalization screen (2026-09): the signature → Submit hierarchy
/// and the Total Charge panel derive from ONE presentation state, not from
/// whichever button was tapped last. These tests pin that state model.
final class ChecklistFinalizationPresentationTests: XCTestCase {

    // MARK: - Signature workflow

    func test1_noSignature_signatureActive_submitDisabled() {
        let p = ChecklistFinalizationPresentation(hasSignature: false, totalCharge: 0)
        XCTAssertEqual(p.signature, .required)
        XCTAssertEqual(p.signatureTone, .activeYellow)
        XCTAssertEqual(p.signatureTitle, "Customer Signature")
        XCTAssertFalse(p.submitIsEnabled)
        XCTAssertEqual(p.submitTone, .disabledGray)
    }

    func test2_signatureCaptured_completed_submitEnabled() {
        let p = ChecklistFinalizationPresentation(hasSignature: true, totalCharge: 0)
        XCTAssertEqual(p.signature, .captured)
        XCTAssertEqual(p.signatureTone, .completedGray)
        XCTAssertTrue(p.submitIsEnabled)
        XCTAssertEqual(p.submitTone, .activeYellow)
    }

    func test3_signedStateProducesCompletedLabel() {
        XCTAssertEqual(ChecklistFinalizationPresentation(hasSignature: true, totalCharge: 12).signatureTitle, "✓ Customer Signed")
        XCTAssertEqual(ChecklistFinalizationPresentation.signatureCapturedTitle, "✓ Customer Signed")
        XCTAssertEqual(ChecklistFinalizationPresentation.signatureRequiredTitle, "Customer Signature")
    }

    func testSignatureRemovedReturnsToUnsignedState() {
        // The UI re-derives from state: dropping the signature flips everything back.
        let signed = ChecklistFinalizationPresentation(hasSignature: true, totalCharge: 0)
        let unsigned = ChecklistFinalizationPresentation(hasSignature: false, totalCharge: 0)
        XCTAssertNotEqual(signed, unsigned)
        XCTAssertFalse(unsigned.submitIsEnabled)
        XCTAssertEqual(unsigned.signatureTitle, "Customer Signature")
    }

    func testDeleteModeKeepsTheDestructiveSubmitUsableWithoutASignature() {
        // The existing "replace / delete equipment" mode never required a signature.
        let p = ChecklistFinalizationPresentation(hasSignature: false, totalCharge: 0, isDeleteMode: true)
        XCTAssertTrue(p.submitIsEnabled)
        XCTAssertEqual(p.submitTone, .destructiveRed)
    }

    // MARK: - Charge presentation

    func test4_zeroCharge_greenState() {
        let p = ChecklistFinalizationPresentation(hasSignature: false, totalCharge: 0)
        XCTAssertEqual(p.charge, .zero)
        XCTAssertEqual(p.chargeAccent, .green)
        // Float noise that still displays as $0.00 is zero.
        XCTAssertEqual(ChecklistFinalizationPresentation.chargeState(for: 0.001), .zero)
        XCTAssertEqual(ChecklistFinalizationPresentation.chargeState(for: -0.001), .zero)
    }

    func test5_positiveCharge_redState() {
        let p = ChecklistFinalizationPresentation(hasSignature: true, totalCharge: 52.58)
        XCTAssertEqual(p.charge, .due)
        XCTAssertEqual(p.chargeAccent, .red)
        XCTAssertEqual(ChecklistFinalizationPresentation.chargeState(for: 0.01), .due)
    }

    func testNegativeChargeIsReportedAsCreditNotStyledAsDue() {
        // No approved presentation exists for a credit; it keeps the neutral style.
        let p = ChecklistFinalizationPresentation(hasSignature: true, totalCharge: -5)
        XCTAssertEqual(p.charge, .credit)
        XCTAssertEqual(p.chargeAccent, .neutral)
    }

    func test6_formattingUnchanged() {
        // Exactly the pre-existing "\(currency)\(String(format: "%.2f", value))".
        XCTAssertEqual(ChecklistFinalizationPresentation.formattedCharge(0, currency: "$"), "$0.00")
        XCTAssertEqual(ChecklistFinalizationPresentation.formattedCharge(52.58, currency: "$"), "$52.58")
        XCTAssertEqual(ChecklistFinalizationPresentation.formattedCharge(1234.5, currency: "$"), "$1234.50")
        XCTAssertEqual(ChecklistFinalizationPresentation.formattedCharge(Double(Float(0.1) + Float(0.2)), currency: "$"), "$0.30")
    }

    func testChargeStateIsIndependentOfSignature() {
        XCTAssertEqual(ChecklistFinalizationPresentation(hasSignature: false, totalCharge: 52.58).chargeAccent, .red)
        XCTAssertEqual(ChecklistFinalizationPresentation(hasSignature: true, totalCharge: 0).chargeAccent, .green)
    }
}
