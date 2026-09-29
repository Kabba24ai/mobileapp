import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Call Customer wizard (2026-09-29): the successful delivery call is three
/// verified steps — address, equipment order, unloading situation. "Confirmed"
/// is derived from them and only from them; Other needs a note.
final class CustomerCallVerificationTests: XCTestCase {

    func testTheApprovedUnloadingSituationsAreTheServersCodesInDisplayOrder() {
        XCTAssertEqual(UnloadingSituation.codes, ["easy_access", "unload_on_street", "alternate_location", "address_inaccurate", "other"])
        XCTAssertEqual(UnloadingSituation.choices.map(\.title),
                       ["Easy access, room to turn around", "Unload on the street", "Alternate unloading location",
                        "Address inaccurate — alternate location", "Other"])
        for (code, title) in UnloadingSituation.choices {
            let situation = UnloadingSituation(code: code, note: "x")
            XCTAssertEqual(situation?.code, code)
            XCTAssertEqual(situation?.title, title)
        }
        XCTAssertNil(UnloadingSituation(code: "helicopter"), "an unknown code is never a silent default")
    }

    func testOtherNeedsANoteAndTheListedChoicesDoNot() {
        XCTAssertTrue(UnloadingSituation.easyAccess.isValid)
        XCTAssertEqual(UnloadingSituation.easyAccess.note, "")
        XCTAssertFalse(UnloadingSituation(code: "other")!.isValid)
        XCTAssertFalse(UnloadingSituation(code: "other", note: "   \n")!.isValid, "whitespace is not a note")
        let other = UnloadingSituation(code: "other", note: "  Back lot, gate code 4411 ")!
        XCTAssertTrue(other.isValid)
        XCTAssertEqual(other.note, "Back lot, gate code 4411", "trimmed")
        XCTAssertEqual(other, .other(note: "Back lot, gate code 4411"))

        // The server caps the note (DriverCallVerification::NOTE_MAX_LENGTH); the phone
        // must never let a note past it complete the step — a 422 would park the call.
        XCTAssertEqual(UnloadingSituation.noteMaxLength, 500)
        XCTAssertTrue(UnloadingSituation.other(note: String(repeating: "x", count: 500)).isValid)
        XCTAssertFalse(UnloadingSituation.other(note: String(repeating: "x", count: 501)).isValid)
        // Counted like the server (Unicode scalars / mb_strlen), not in grapheme clusters:
        // 👍🏽 is ONE cluster but TWO scalars, so 300 of them are 600 to the server.
        let thumbs = "\u{1F44D}\u{1F3FD}"
        XCTAssertEqual(thumbs.count, 1)
        XCTAssertEqual(UnloadingSituation.length(of: thumbs), 2)
        XCTAssertFalse(UnloadingSituation.other(note: String(repeating: thumbs, count: 300)).isValid, "the server would refuse it")
        XCTAssertTrue(UnloadingSituation.other(note: String(repeating: thumbs, count: 250)).isValid)
        XCTAssertFalse(CustomerCallVerification(addressVerified: true, equipmentVerified: true,
                                                unloading: .other(note: String(repeating: "x", count: 501))).isComplete)
    }

    func testNothingVerifiedIsNotComplete() {
        let fresh = CustomerCallVerification.notStarted
        XCTAssertFalse(fresh.isComplete)
        XCTAssertFalse(fresh.hasProgress)
        XCTAssertEqual(fresh.completedSteps, 0)
        XCTAssertEqual(fresh.nextStep, .address)
    }

    func testEveryStepIsRequiredInOrder() {
        var call = CustomerCallVerification(addressVerified: true)
        XCTAssertFalse(call.isComplete)
        XCTAssertTrue(call.hasProgress)
        XCTAssertEqual(call.completedSteps, 1)
        XCTAssertEqual(call.nextStep, .equipment)

        call.equipmentVerified = true
        XCTAssertFalse(call.isComplete)
        XCTAssertEqual(call.completedSteps, 2)
        XCTAssertEqual(call.nextStep, .unloading)

        call.unloading = .other(note: "")
        XCTAssertFalse(call.isComplete, "Other without a note never completes the third step")
        XCTAssertEqual(call.completedSteps, 2)
        XCTAssertTrue(call.hasProgress)
        XCTAssertEqual(call.nextStep, .unloading)

        call.unloading = .other(note: "Meet at the barn")
        XCTAssertTrue(call.isComplete)
        XCTAssertEqual(call.completedSteps, 3)
        XCTAssertNil(call.nextStep)

        call.unloading = .unloadOnStreet
        XCTAssertTrue(call.isComplete, "changing to another valid choice stays complete")

        call.addressVerified = false
        XCTAssertFalse(call.isComplete, "no step is optional, whatever the others say")
        XCTAssertEqual(call.nextStep, .address)
    }

    func testTheWireStringsRoundTrip() {
        let call = CustomerCallVerification(addressVerified: true, equipmentVerified: true, unloadingCode: "other", unloadingNote: "Side entrance")
        XCTAssertEqual(call.unloadingCode, "other")
        XCTAssertEqual(call.unloadingNote, "Side entrance")
        XCTAssertTrue(call.isComplete)

        let listed = CustomerCallVerification(addressVerified: true, equipmentVerified: false, unloadingCode: "easy_access", unloadingNote: "stale")
        XCTAssertEqual(listed.unloading, .easyAccess)
        XCTAssertEqual(listed.unloadingNote, "", "a listed choice carries no note")

        let unknown = CustomerCallVerification(addressVerified: true, equipmentVerified: true, unloadingCode: "made_up", unloadingNote: "")
        XCTAssertNil(unknown.unloading)
        XCTAssertFalse(unknown.isComplete)
        XCTAssertEqual(CustomerCallVerification(addressVerified: false, equipmentVerified: false, unloadingCode: "", unloadingNote: ""), .notStarted)
    }

    func testTheStepTitlesAreTheControlsOnTheDriverChecklist() {
        XCTAssertEqual(CustomerCallVerification.Step.allCases.map(\.title), ["Delivery Address", "Equipment Order", "Unloading Situation"])
    }
}
