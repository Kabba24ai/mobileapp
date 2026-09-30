import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Driver Delivery Process Flow (2026-09-27), spec §7 — the final pre-departure
/// gate, locked by D2 / D3 / D11:
///
///     Load Map & Go enabled =
///           Assembly Review GO                                (Delivery only)
///       AND Call Customer complete                            (Confirmed + every check, or No Answer)
///       AND (Fuel not required OR Fuel == Full   for the current unit)
///       AND (Keys not required OR Keys == With Machine for the current unit)
///
/// No required field may pass because a default was silently pre-populated:
/// an unanswered control is a blocker. Return has a band of its own — the call
/// term only.
final class DriverChecklistGateTests: XCTestCase {

    private func decide(isDeliveryLeg: Bool = true,
                        call: CallOutcome = .noAnswer,
                        fuelRequired: Bool = false, fuel: FuelAnswer? = nil,
                        keysRequired: Bool = false, keys: KeysAnswer? = nil,
                        assemblyReady: Bool? = true) -> DriverChecklistGateDecision {
        DriverChecklistGate.evaluate(DriverChecklistGateInputs(
            isDeliveryLeg: isDeliveryLeg, call: call,
            fuelRequired: fuelRequired, fuel: fuel,
            keysRequired: keysRequired, keys: keys,
            assemblyReady: assemblyReady))
    }

    // MARK: - Call Customer (D3)

    func testAnUnansweredCallBlocks() {
        let d = decide(call: .unset)
        XCTAssertFalse(d.enabled)
        XCTAssertEqual(d.blockers, [DriverChecklistGate.blockerCall])
    }

    func testConfirmedNeedsEveryTick() {
        XCTAssertFalse(decide(call: .confirmed(ticks: [true, true, false, true])).enabled)
        XCTAssertEqual(decide(call: .confirmed(ticks: [true, false])).blockers, [DriverChecklistGate.blockerCall])
        XCTAssertFalse(decide(call: .confirmed(ticks: [])).enabled, "Confirmed with nothing ticked is not a completed call")
        XCTAssertTrue(decide(call: .confirmed(ticks: [true, true, true, true])).enabled)
    }

    func testNoAnswerIsAnExplicitAttemptedCallAndPasses() {
        XCTAssertTrue(decide(call: .noAnswer).enabled)
    }

    // MARK: - Call Customer wizard (2026-09-29): Confirmed is DERIVED from three verified steps

    private func wizard(address: Bool = false, equipment: Bool = false, unloading: UnloadingSituation? = nil) -> CallOutcome {
        .wizard(CustomerCallVerification(addressVerified: address, equipmentVerified: equipment, unloading: unloading))
    }

    func testTheWizardBlocksUntilEveryStepIsVerified() {
        for (name, call) in [("0/3", wizard()),
                             ("address only", wizard(address: true)),
                             ("address + equipment", wizard(address: true, equipment: true)),
                             ("Other without a note", wizard(address: true, equipment: true, unloading: .other(note: "")))] {
            let d = decide(call: call)
            XCTAssertFalse(d.enabled, name)
            XCTAssertEqual(d.blockers, [DriverChecklistGate.blockerCallWizard], name)
        }
        XCTAssertTrue(decide(call: wizard(address: true, equipment: true, unloading: .easyAccess)).enabled, "3/3")
        XCTAssertTrue(decide(call: wizard(address: true, equipment: true, unloading: .other(note: "Back lot"))).enabled)
        XCTAssertTrue(DriverChecklistGate.blockerCallWizard.contains("No Answer"), "the escape is named")
    }

    func testNoAnswerSatisfiesTheCallWithoutTheWizard() {
        XCTAssertTrue(decide(call: .noAnswer).enabled)
        XCTAssertTrue(decide(call: .noAnswer, fuelRequired: true, fuel: .full, keysRequired: true, keys: .withMachine).enabled)
    }

    func testFuelAndKeysStillBlockAfterACompleteCall() {
        let complete = wizard(address: true, equipment: true, unloading: .alternateLocation)
        XCTAssertEqual(decide(call: complete, fuelRequired: true, fuel: .notFull).blockers, [DriverChecklistGate.blockerFuel])
        XCTAssertEqual(decide(call: complete, fuelRequired: true, fuel: nil).blockers, [DriverChecklistGate.blockerFuel])
        XCTAssertEqual(decide(call: complete, keysRequired: true, keys: .missing).blockers, [DriverChecklistGate.blockerKeys])
        XCTAssertEqual(decide(call: complete, keysRequired: true, keys: nil).blockers, [DriverChecklistGate.blockerKeys])
        XCTAssertEqual(decide(call: wizard(address: true), fuelRequired: true, fuel: .notFull, keysRequired: true, keys: .missing, assemblyReady: false).blockers,
                       [DriverChecklistGate.blockerAssembly, DriverChecklistGate.blockerCallWizard, DriverChecklistGate.blockerFuel, DriverChecklistGate.blockerKeys],
                       "gate order holds")
    }

    func testTheDeliveryOutcomeIsDerivedFromTheRecordNeverAsserted() {
        let none = CustomerCallVerification.notStarted
        let complete = CustomerCallVerification(addressVerified: true, equipmentVerified: true, unloading: .unloadOnStreet)
        // "confirmed" in the record means nothing without the steps (a row written before the wizard).
        XCTAssertEqual(CallOutcome(callCustomer: "confirmed", verification: none), .wizard(none))
        XCTAssertFalse(CallOutcome(callCustomer: "confirmed", verification: none).isComplete)
        XCTAssertEqual(CallOutcome(callCustomer: "", verification: complete), .wizard(complete))
        XCTAssertTrue(CallOutcome(callCustomer: "", verification: complete).isComplete)
        // No Answer is the explicit escape — only while the wizard has not been started.
        XCTAssertEqual(CallOutcome(callCustomer: "no_answer", verification: none), .noAnswer)
        XCTAssertEqual(CallOutcome(callCustomer: "no_answer", verification: CustomerCallVerification(addressVerified: true)),
                       .wizard(CustomerCallVerification(addressVerified: true)),
                       "the customer answered after all: the wizard outranks a stale No Answer")
    }

    /// Confirmed → No Answer protection: the driver is asked first ONLY when No Answer
    /// would wipe a fully verified call. Every other No Answer stays one tap.
    func testNoAnswerAsksFirstOnlyOverAFullyVerifiedCall() {
        XCTAssertTrue(wizard(address: true, equipment: true, unloading: .easyAccess).noAnswerNeedsConfirmation)
        XCTAssertTrue(wizard(address: true, equipment: true, unloading: .other(note: "Back lot")).noAnswerNeedsConfirmation)

        for (name, call) in [("nothing verified", wizard()),
                             ("address only", wizard(address: true)),
                             ("address + equipment", wizard(address: true, equipment: true)),
                             ("Other without a note", wizard(address: true, equipment: true, unloading: .other(note: ""))),
                             ("No Answer already", CallOutcome.noAnswer),
                             ("unset", CallOutcome.unset),
                             ("Return, every tick", CallOutcome.confirmed(ticks: [true, true, true]))] {
            XCTAssertFalse(call.noAnswerNeedsConfirmation, name)
        }

        // The alert says what continuing does — both consequences, in the driver's words.
        XCTAssertTrue(NoAnswerConfirmation.message.contains("clear the verified call steps"))
        XCTAssertTrue(NoAnswerConfirmation.message.contains("change the call result to No Answer"))
        XCTAssertEqual(NoAnswerConfirmation.cancelTitle, "Cancel")
        XCTAssertFalse(NoAnswerConfirmation.title.isEmpty)
        XCTAssertFalse(NoAnswerConfirmation.confirmTitle.isEmpty)
    }

    // MARK: - Fuel (D2)

    func testFuelUnansweredBlocksWhereFuelApplies() {
        let d = decide(fuelRequired: true, fuel: nil)
        XCTAssertFalse(d.enabled)
        XCTAssertEqual(d.blockers, [DriverChecklistGate.blockerFuel])
    }

    func testNotFullNeverEnablesDeparture() {
        let d = decide(fuelRequired: true, fuel: .notFull)
        XCTAssertFalse(d.enabled)
        XCTAssertEqual(d.blockers, [DriverChecklistGate.blockerFuel])
        XCTAssertTrue(DriverChecklistGate.blockerFuel.contains("must not leave the yard"))
    }

    func testFullPassesAndFuelIsIgnoredWhereItDoesNotApply() {
        XCTAssertTrue(decide(fuelRequired: true, fuel: .full).enabled)
        XCTAssertTrue(decide(fuelRequired: false, fuel: nil).enabled)
        XCTAssertTrue(decide(fuelRequired: false, fuel: .notFull).enabled, "a unit that needs no fuel sign-off is never blocked by a stray answer")
    }

    // MARK: - Keys (D11)

    func testKeysUnansweredOrMissingBlocksWhereKeysApply() {
        for keys in [KeysAnswer?.none, .missing] {
            let d = decide(keysRequired: true, keys: keys)
            XCTAssertFalse(d.enabled, "keys=\(String(describing: keys))")
            XCTAssertEqual(d.blockers, [DriverChecklistGate.blockerKeys])
        }
    }

    func testWithMachinePassesAndKeysAreIgnoredWhereTheyDoNotApply() {
        XCTAssertTrue(decide(keysRequired: true, keys: .withMachine).enabled)
        XCTAssertTrue(decide(keysRequired: false, keys: nil).enabled)
        XCTAssertTrue(decide(keysRequired: false, keys: .missing).enabled)
    }

    // MARK: - Assembly Review (Delivery only)

    func testAssemblyStopOrUnknownBlocksFirst() {
        XCTAssertEqual(decide(call: .unset, assemblyReady: false).blockers, [DriverChecklistGate.blockerAssembly, DriverChecklistGate.blockerCall])
        XCTAssertEqual(decide(assemblyReady: nil).blockers, [DriverChecklistGate.blockerAssembly], "no review on this phone is honestly STOP (§6.4)")
        XCTAssertFalse(decide(assemblyReady: false).enabled)
    }

    // MARK: - The whole gate

    func testEverythingSatisfiedEnablesWithNoBlockers() {
        let d = decide(call: .confirmed(ticks: [true, true, true, true]),
                       fuelRequired: true, fuel: .full,
                       keysRequired: true, keys: .withMachine,
                       assemblyReady: true)
        XCTAssertTrue(d.enabled)
        XCTAssertEqual(d.blockers, [])
    }

    func testBlockersAreListedInGateOrder() {
        let d = decide(call: .unset, fuelRequired: true, fuel: .notFull, keysRequired: true, keys: .missing, assemblyReady: false)
        XCTAssertFalse(d.enabled)
        XCTAssertEqual(d.blockers, [DriverChecklistGate.blockerAssembly, DriverChecklistGate.blockerCall,
                                    DriverChecklistGate.blockerFuel, DriverChecklistGate.blockerKeys])
    }

    func testNoDefaultEverPasses() {
        // The screen's old defaults — "confirmed" with no ticks, Not Full, Missing — all block.
        let d = decide(call: .confirmed(ticks: [false, false, false, false]),
                       fuelRequired: true, fuel: .notFull,
                       keysRequired: true, keys: .missing)
        XCTAssertFalse(d.enabled)
        XCTAssertEqual(d.blockers.count, 3)
    }

    // MARK: - Return band (§7.5, §13)

    func testReturnAsksOnlyForTheCall() {
        XCTAssertTrue(decide(isDeliveryLeg: false, call: .noAnswer,
                             fuelRequired: true, fuel: .notFull,
                             keysRequired: true, keys: .missing,
                             assemblyReady: false).enabled,
                      "fuel, keys and the assembly gate never participate on Return")
        XCTAssertEqual(decide(isDeliveryLeg: false, call: .unset, assemblyReady: false).blockers, [DriverChecklistGate.blockerCall])
        XCTAssertFalse(decide(isDeliveryLeg: false, call: .confirmed(ticks: [true, false, true])).enabled)
        XCTAssertTrue(decide(isDeliveryLeg: false, call: .confirmed(ticks: [true, true, true])).enabled)
    }

    // MARK: - "Applies" (§7.1): requires_* wins; a package that predates it falls back to is_*

    func testFuelRequiredPrefersTheYardPredicateAndFallsBackToTheDisplayFlag() {
        XCTAssertTrue(DriverChecklistGate.fuelRequired(requiresFuelCheck: true, isFuel: false))
        XCTAssertFalse(DriverChecklistGate.fuelRequired(requiresFuelCheck: false, isFuel: true))
        XCTAssertTrue(DriverChecklistGate.fuelRequired(requiresFuelCheck: nil, isFuel: true))
        XCTAssertTrue(DriverChecklistGate.fuelRequired(requiresFuelCheck: nil, isFuel: nil), "unknown = ask (never a silent skip)")
        XCTAssertFalse(DriverChecklistGate.fuelRequired(requiresFuelCheck: nil, isFuel: false))
    }

    func testKeysRequiredPrefersTheYardPredicateAndFallsBackToTheDisplayFlag() {
        XCTAssertTrue(DriverChecklistGate.keysRequired(requiresKeyCheck: true, isKey: false))
        XCTAssertFalse(DriverChecklistGate.keysRequired(requiresKeyCheck: false, isKey: true))
        XCTAssertTrue(DriverChecklistGate.keysRequired(requiresKeyCheck: nil, isKey: true))
        XCTAssertTrue(DriverChecklistGate.keysRequired(requiresKeyCheck: nil, isKey: nil))
        XCTAssertFalse(DriverChecklistGate.keysRequired(requiresKeyCheck: nil, isKey: false))
    }

    // MARK: - Wire values (the segment strings the screen and the server share)

    func testAnswersUseTheContractStrings() {
        XCTAssertEqual(FuelAnswer.full.rawValue, "Full")
        XCTAssertEqual(FuelAnswer.notFull.rawValue, "Not Full")
        XCTAssertEqual(KeysAnswer.withMachine.rawValue, "With Machine")
        XCTAssertEqual(KeysAnswer.missing.rawValue, "Missing")
        XCTAssertNil(FuelAnswer(rawValue: ""), "an empty answer is unset, never a value")
        XCTAssertNil(KeysAnswer(rawValue: ""))
        XCTAssertEqual(CallOutcome(callCustomer: "", ticks: [true]), .unset)
        XCTAssertEqual(CallOutcome(callCustomer: "no_answer", ticks: []), .noAnswer)
        XCTAssertEqual(CallOutcome(callCustomer: "confirmed", ticks: [true, false]), .confirmed(ticks: [true, false]))
    }
}
