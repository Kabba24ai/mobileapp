import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// The driver mini-checklist's local record, pinned down:
///
///  1. Routing is NOT decided here. Start Delivery / Start Return routes by
///     the effective workflow stage (DeliveryWorkflowStage, 2026-09-27); the
///     record is one of that derivation's inputs (evidence), never a router.
///  2. Saved mini-checklist progress is scoped to ORDER-PRODUCT + LEG, stays
///     editable, and round-trips losslessly — including the identity of the
///     unit the fuel/keys answers were given for (D5).
///  3. Progress detection (the GREEN Dispatch band) reflects any non-default
///     entry, locally or as the server reports it.
final class DriverChecklistLocalStateTests: XCTestCase {

    // MARK: - 1. Identity: order-product + leg

    func testKeyIsScopedToOrderProductAndLeg() {
        let productADelivery = DriverChecklistLocalState.key(orderProductUniqueId: "ORD-SCH-AAAA-0001", leg: "delivery")
        let productAPickup   = DriverChecklistLocalState.key(orderProductUniqueId: "ORD-SCH-AAAA-0001", leg: "pickup")
        let productBDelivery = DriverChecklistLocalState.key(orderProductUniqueId: "ORD-SCH-BBBB-0002", leg: "delivery")

        // Delivery cannot populate Return; product A cannot populate product B.
        XCTAssertNotEqual(productADelivery, productAPickup)
        XCTAssertNotEqual(productADelivery, productBDelivery)
        XCTAssertNotEqual(productAPickup, productBDelivery)
    }

    func testV2KeyIgnoresTheOldOrderScopedNamespace() {
        // The pre-correction key ("driverChecklist_<ORDER>_delivery") leaked one
        // product's progress onto every line of a multi-line order. The v2 key
        // must never collide with it.
        let old = "driverChecklist_ORD-XXXX-0001_delivery"
        let new = DriverChecklistLocalState.key(orderProductUniqueId: "ORD-XXXX-0001", leg: "delivery")
        XCTAssertNotEqual(old, new)
        XCTAssertTrue(new.hasPrefix("driverChecklist_v2_"))
    }

    // MARK: - 2b. Round trip + editability

    func testStateRoundTripsThroughItsDictionary() {
        let saved = DriverChecklistLocalState(checks: [true, false, true, false],
                                              callCustomer: "no_answer",
                                              fuel: "Full",
                                              keys: "Missing")
        let restored = DriverChecklistLocalState(dictionary: saved.dictionary())
        XCTAssertEqual(restored, saved)
    }

    func testSavedAnswersRemainEditableNotLocked() {
        // A prior answer is the current saved state — not a historical lock.
        var state = DriverChecklistLocalState(checks: [true, true, false, false],
                                              callCustomer: "confirmed",
                                              fuel: "Full",
                                              keys: "With Machine")
        // Uncheck a previously ticked item, flip the segments back to defaults.
        state.checks[0] = false
        state.callCustomer = "no_answer"
        state.fuel = "Not Full"
        state.keys = "Missing"

        let restored = DriverChecklistLocalState(dictionary: state.dictionary())
        XCTAssertEqual(restored?.checks, [false, true, false, false])
        XCTAssertEqual(restored?.callCustomer, "no_answer")
        XCTAssertEqual(restored?.fuel, "Not Full")
        XCTAssertEqual(restored?.keys, "Missing")
    }

    func testMissingOrForeignDictionaryRestoresNothing() {
        XCTAssertNil(DriverChecklistLocalState(dictionary: nil))
        // A dictionary from some other feature must not crash the restore.
        let foreign = DriverChecklistLocalState(dictionary: ["unexpected": "shape"])
        XCTAssertEqual(foreign?.checks, [])
        XCTAssertEqual(foreign?.hasProgress, false)
    }

    // MARK: - 2c. The unit the fuel/keys answers belong to (D5)

    func testEquipmentIdentityRoundTripsAndIsUnknownWhenAbsent() {
        let saved = DriverChecklistLocalState(checks: [true, false, false, false],
                                              callCustomer: "confirmed",
                                              fuel: "Full",
                                              keys: "With Machine",
                                              equipmentUniqueId: "EQP-A")
        XCTAssertEqual(saved.dictionary()["equipment_unique_id"] as? String, "EQP-A")
        XCTAssertEqual(DriverChecklistLocalState(dictionary: saved.dictionary()), saved)

        // A record written before the identity existed restores as "unknown unit".
        let legacy = DriverChecklistLocalState(dictionary: ["fuel": "Full", "keys": "With Machine"])
        XCTAssertEqual(legacy?.equipmentUniqueId, "")
        XCTAssertEqual(DriverChecklistLocalState().equipmentUniqueId, "")
    }

    // MARK: - 2d. Restore is unit-checked (D5, spec §7.3)

    private let unitA = "EQP-A"
    private let unitB = "EQP-B"

    private func recordForA() -> DriverChecklistLocalState {
        DriverChecklistLocalState(checks: [true, false, true, false], callCustomer: "confirmed",
                                  fuel: "Full", keys: "With Machine", equipmentUniqueId: unitA)
    }

    func testTheSameUnitRestoresEverything() {
        let restored = DriverChecklistLocalState.restore(local: recordForA(), server: nil, effectiveUnit: unitA)
        XCTAssertEqual(restored, recordForA())
    }

    func testAReplacedUnitResetsFuelAndKeysButKeepsTheCall() {
        let restored = DriverChecklistLocalState.restore(local: recordForA(), server: nil, effectiveUnit: unitB)
        XCTAssertEqual(restored?.checks, [true, false, true, false])
        XCTAssertEqual(restored?.callCustomer, "confirmed")
        XCTAssertEqual(restored?.fuel, "", "Unit A's fuel answer never speaks for Unit B")
        XCTAssertEqual(restored?.keys, "")
        XCTAssertEqual(restored?.equipmentUniqueId, unitB, "the record now belongs to the effective unit")
    }

    func testTheServerCopyRestoresUnderTheSameRuleOnAnotherPhone() {
        let server = DriverChecklistServerCopy(callCustomer: "no_answer", fuel: "Full", keys: "With Machine",
                                               checks: [0, 1, 0, 0], equipmentUniqueId: unitA)
        let sameUnit = DriverChecklistLocalState.restore(local: nil, server: server, effectiveUnit: unitA)
        XCTAssertEqual(sameUnit, DriverChecklistLocalState(checks: [false, true, false, false], callCustomer: "no_answer",
                                                           fuel: "Full", keys: "With Machine", equipmentUniqueId: unitA))

        let otherUnit = DriverChecklistLocalState.restore(local: nil, server: server, effectiveUnit: unitB)
        XCTAssertEqual(otherUnit?.callCustomer, "no_answer")
        XCTAssertEqual(otherUnit?.checks, [false, true, false, false])
        XCTAssertEqual(otherUnit?.fuel, "")
        XCTAssertEqual(otherUnit?.keys, "")
    }

    func testAnAbsentIdentityWhileAUnitIsAssignedRestoresNoFuelOrKeys() {
        // A record written before the identity existed (or a legacy server row).
        let legacy = DriverChecklistLocalState(checks: [true], callCustomer: "confirmed", fuel: "Full", keys: "With Machine")
        let restored = DriverChecklistLocalState.restore(local: legacy, server: nil, effectiveUnit: unitA)
        XCTAssertEqual(restored?.fuel, "")
        XCTAssertEqual(restored?.keys, "")
        XCTAssertEqual(restored?.callCustomer, "confirmed")

        let serverLegacy = DriverChecklistServerCopy(callCustomer: "confirmed", fuel: "Not Full", keys: "Missing", checks: [1], equipmentUniqueId: nil)
        XCTAssertEqual(DriverChecklistLocalState.restore(local: nil, server: serverLegacy, effectiveUnit: unitA)?.fuel, "")
    }

    func testNoUnitAssignedRestoresAsRecorded() {
        for unit in [String?.none, ""] {
            let restored = DriverChecklistLocalState.restore(local: recordForA(), server: nil, effectiveUnit: unit)
            XCTAssertEqual(restored, recordForA(), "effectiveUnit=\(String(describing: unit))")
        }
    }

    func testLocalWinsOverTheServerCopyAndNothingRestoresNothing() {
        let server = DriverChecklistServerCopy(callCustomer: "no_answer", fuel: "Not Full", keys: "Missing", checks: nil, equipmentUniqueId: unitA)
        XCTAssertEqual(DriverChecklistLocalState.restore(local: recordForA(), server: server, effectiveUnit: unitA), recordForA())
        XCTAssertNil(DriverChecklistLocalState.restore(local: nil, server: nil, effectiveUnit: unitA))
    }

    func testAnAllNilServerBlockRestoresNothing() {
        // The feed emits the checklist block for every row with nulls inside; that
        // is not a record, so opening Screen 2 restores nothing from it — for any
        // effective unit, including none.
        let allNil = DriverChecklistServerCopy()
        XCTAssertTrue(allNil.isEmpty)
        for unit in [unitA, "", nil] as [String?] {
            XCTAssertNil(DriverChecklistLocalState.restore(local: nil, server: allNil, effectiveUnit: unit), "effectiveUnit=\(String(describing: unit))")
        }
        // A copy with one real value is a record; the identity alone is enough to be one.
        XCTAssertNotNil(DriverChecklistLocalState.restore(local: nil, server: DriverChecklistServerCopy(checks: [0, 0]), effectiveUnit: unitA))
        XCTAssertNotNil(DriverChecklistLocalState.restore(local: nil, server: DriverChecklistServerCopy(equipmentUniqueId: unitA), effectiveUnit: unitA))
    }

    // MARK: - 3. Progress detection (the green band)

    func testAnUntouchedScreenIsNotProgress() {
        // Nothing preselected any more (spec §7.1): unset call, no fuel, no keys.
        let fresh = DriverChecklistLocalState(checks: [false, false, false, false], callCustomer: "", fuel: "", keys: "")
        XCTAssertFalse(fresh.hasProgress)
        XCTAssertFalse(DriverChecklistLocalState.serverHasProgress(driverChecks: [0, 0, 0, 0], callCustomer: nil, fuel: nil, keys: nil))
    }

    func testEveryExplicitAnswerCountsAsProgress() {
        XCTAssertTrue(DriverChecklistLocalState(checks: [false, true, false]).hasProgress, "one tick")
        XCTAssertTrue(DriverChecklistLocalState(callCustomer: "no_answer").hasProgress, "no-answer selection")
        XCTAssertTrue(DriverChecklistLocalState(callCustomer: "confirmed").hasProgress, "confirmed is an explicit choice now, not a default")
        XCTAssertTrue(DriverChecklistLocalState(fuel: "Full").hasProgress)
        XCTAssertTrue(DriverChecklistLocalState(fuel: "Not Full").hasProgress, "Not Full is a recorded answer (A2) — it blocks departure, but it is progress")
        XCTAssertTrue(DriverChecklistLocalState(keys: "With Machine").hasProgress)
        XCTAssertTrue(DriverChecklistLocalState(keys: "Missing").hasProgress)
    }

    func testPartialProgressIsProgress() {
        // 3 items, driver checked only 1, backed out → green band, not blank.
        let partial = DriverChecklistLocalState(checks: [true, false, false])
        XCTAssertTrue(partial.hasProgress)
    }

    func testAProgressedRecordIsWorkflowEvidence() {
        // The green-band predicate is an input to DeliveryWorkflowStage (evidence),
        // never a destination: nothing on the record says where Start Delivery goes.
        let progressed = DriverChecklistLocalState(checks: [true, true, true, true],
                                                   callCustomer: "no_answer",
                                                   fuel: "Full",
                                                   keys: "With Machine")
        XCTAssertTrue(progressed.hasProgress)
        XCTAssertTrue(DriverChecklistEvidence.exists(localRecord: progressed, serverChecklist: nil, operations: [],
                                                     orderProductUniqueId: "P1", leg: "delivery"))
    }

    func testServerReportedProgressMatchesTheSameRules() {
        XCTAssertTrue(DriverChecklistLocalState.serverHasProgress(driverChecks: [0, 0, 0, 0],
                                                                  callCustomer: "confirmed",
                                                                  fuel: "Not Full",
                                                                  keys: "Missing"),
                      "explicit answers the server holds are progress, whatever they say")
        XCTAssertFalse(DriverChecklistLocalState.serverHasProgress(driverChecks: nil,
                                                                   callCustomer: nil,
                                                                   fuel: nil,
                                                                   keys: nil))
        XCTAssertFalse(DriverChecklistLocalState.serverHasProgress(driverChecks: [0, 0],
                                                                   callCustomer: "",
                                                                   fuel: "",
                                                                   keys: ""), "empty strings are unset")
        XCTAssertTrue(DriverChecklistLocalState.serverHasProgress(driverChecks: [1, 0, 0, 0],
                                                                  callCustomer: nil,
                                                                  fuel: nil,
                                                                  keys: nil))
        XCTAssertTrue(DriverChecklistLocalState.serverHasProgress(driverChecks: nil,
                                                                  callCustomer: "no_answer",
                                                                  fuel: nil,
                                                                  keys: nil))
        XCTAssertTrue(DriverChecklistLocalState.serverHasProgress(driverChecks: nil,
                                                                  callCustomer: nil,
                                                                  fuel: "Full",
                                                                  keys: "With Machine"))
    }


    // MARK: Assignment episodes (2026-09-29) — fuel / keys never cross a switch, even back to the same unit

    private func recordForA(episode: String) -> DriverChecklistLocalState {
        DriverChecklistLocalState(checks: [true, false, true, false], callCustomer: "confirmed",
                                  fuel: "Full", keys: "With Machine", equipmentUniqueId: unitA, assignmentEpisode: episode)
    }

    func testTheSameUnitInTheSameEpisodeRestoresEverything() {
        XCTAssertEqual(DriverChecklistLocalState.restore(local: recordForA(episode: "SW-1"), server: nil, effectiveUnit: unitA, assignmentEpisode: "SW-1"),
                       recordForA(episode: "SW-1"))
        XCTAssertEqual(DriverChecklistLocalState.restore(local: recordForA(episode: ""), server: nil, effectiveUnit: unitA, assignmentEpisode: ""),
                       recordForA(episode: ""), "no switch on this phone, the row's unit: as before")
    }

    func testTheSameUnitInANewEpisodeResetsFuelAndKeysButKeepsTheCall() {
        // Answered for A on the row's episode, then A → B → A on the review: A is a NEW assignment.
        let restored = DriverChecklistLocalState.restore(local: recordForA(episode: ""), server: nil, effectiveUnit: unitA, assignmentEpisode: "SW-2")
        XCTAssertEqual(restored?.checks, [true, false, true, false])
        XCTAssertEqual(restored?.callCustomer, "confirmed")
        XCTAssertEqual(restored?.fuel, "", "the answer given for A's earlier episode never speaks for A's new one")
        XCTAssertEqual(restored?.keys, "")
        XCTAssertEqual(restored?.equipmentUniqueId, unitA)
        XCTAssertEqual(restored?.assignmentEpisode, "SW-2", "the record now belongs to the current episode")

        let later = DriverChecklistLocalState.restore(local: recordForA(episode: "SW-1"), server: nil, effectiveUnit: unitA, assignmentEpisode: "SW-3")
        XCTAssertEqual(later?.fuel, "")
        XCTAssertEqual(later?.keys, "")
        XCTAssertEqual(later?.assignmentEpisode, "SW-3")
    }

    func testTheServerCopyNeverSpeaksForAnEpisodeThisPhoneStarted() {
        let server = DriverChecklistServerCopy(callCustomer: "no_answer", fuel: "Full", keys: "With Machine", checks: [0, 1, 0, 0], equipmentUniqueId: unitA)
        let afterASwitch = DriverChecklistLocalState.restore(local: nil, server: server, effectiveUnit: unitA, assignmentEpisode: "SW-1")
        XCTAssertEqual(afterASwitch?.callCustomer, "no_answer")
        XCTAssertEqual(afterASwitch?.fuel, "")
        XCTAssertEqual(afterASwitch?.keys, "")
        XCTAssertEqual(afterASwitch?.assignmentEpisode, "SW-1")
        XCTAssertEqual(DriverChecklistLocalState.restore(local: nil, server: server, effectiveUnit: unitA, assignmentEpisode: "")?.fuel, "Full",
                       "no local switch: the server's answers for the row's unit restore as before")
    }

    func testTheEpisodeRoundTripsThroughTheDictionaryAndIsEmptyWhenAbsent() {
        let record = recordForA(episode: "SW-9")
        XCTAssertEqual(record.dictionary()["assignment_episode"] as? String, "SW-9")
        XCTAssertEqual(DriverChecklistLocalState(dictionary: record.dictionary()), record)
        let legacy = DriverChecklistLocalState(dictionary: ["fuel": "Full", "equipment_unique_id": unitA])
        XCTAssertEqual(legacy?.assignmentEpisode, "", "a record written before episodes existed reads as the row's episode")
    }

    func testAnEpisodeNoLongerRetainedOnThePhoneIsStillNotTheRecordedOne() {
        // The switch the record was bound to was pruned (retention window): "" ≠ "SW-1" — fuel and
        // keys clear (a spurious re-ask at worst); they never revive.
        let restored = DriverChecklistLocalState.restore(local: recordForA(episode: "SW-1"), server: nil, effectiveUnit: unitA, assignmentEpisode: "")
        XCTAssertEqual(restored?.fuel, "")
        XCTAssertEqual(restored?.keys, "")
        XCTAssertEqual(restored?.callCustomer, "confirmed")
        XCTAssertEqual(restored?.assignmentEpisode, "")
    }
}
