import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// The 2026-09 Dispatch workflow correction, pinned down:
///
///  1. Start Delivery / Start Return ALWAYS routes to the Driver Checklist —
///     no combination of prior state (arrived, ready-to-go, saved progress)
///     may reopen the old Screen 1 → Screen 3 shortcut.
///  2. Saved mini-checklist progress is scoped to ORDER-PRODUCT + LEG, stays
///     editable, and round-trips losslessly.
///  3. Progress detection (the GREEN Dispatch band) reflects any non-default
///     entry, locally or as the server reports it — and is routing-inert.
final class DriverChecklistLocalStateTests: XCTestCase {

    // MARK: - 1. The navigation rule is absolute

    func testEveryPriorStateCombinationRoutesToTheDriverChecklist() {
        // All 8 combinations of (isArrived, readyToGoAt, hasSavedProgress):
        // the pre-correction code bypassed Screen 2 when is_arrived was true.
        for isArrived in [false, true] {
            for readyToGo in [nil, "2026-09-01 08:15:00"] {
                for progress in [false, true] {
                    XCTAssertEqual(
                        DriverChecklistRouting.destination(isArrived: isArrived,
                                                           readyToGoAt: readyToGo,
                                                           hasSavedProgress: progress),
                        .driverChecklist,
                        "Bypass regression: isArrived=\(isArrived) readyToGo=\(String(describing: readyToGo)) progress=\(progress) must still open the Driver Checklist"
                    )
                }
            }
        }
    }

    // MARK: - 2. Identity: order-product + leg

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

    // MARK: - 3. Progress detection (the green band) — routing-inert

    func testUntouchedDefaultsAreNotProgress() {
        // The defaults a fresh screen starts with: nothing ticked,
        // call = confirmed (segment default), fuel Not Full, keys Missing.
        let fresh = DriverChecklistLocalState(checks: [false, false, false, false],
                                              callCustomer: "confirmed",
                                              fuel: "Not Full",
                                              keys: "Missing")
        XCTAssertFalse(fresh.hasProgress)
    }

    func testEachNonDefaultEntryCountsAsProgress() {
        XCTAssertTrue(DriverChecklistLocalState(checks: [false, true, false]).hasProgress, "one tick")
        XCTAssertTrue(DriverChecklistLocalState(callCustomer: "no_answer").hasProgress, "no-answer selection")
        XCTAssertTrue(DriverChecklistLocalState(fuel: "Full").hasProgress, "fuel flipped")
        XCTAssertTrue(DriverChecklistLocalState(keys: "With Machine").hasProgress, "keys flipped")
    }

    func testPartialProgressIsProgress() {
        // 3 items, driver checked only 1, backed out → green band, not blank.
        let partial = DriverChecklistLocalState(checks: [true, false, false])
        XCTAssertTrue(partial.hasProgress)
    }

    func testServerReportedProgressMatchesTheSameRules() {
        XCTAssertFalse(DriverChecklistLocalState.serverHasProgress(driverChecks: [0, 0, 0, 0],
                                                                   callCustomer: "confirmed",
                                                                   fuel: "Not Full",
                                                                   keys: "Missing"))
        XCTAssertFalse(DriverChecklistLocalState.serverHasProgress(driverChecks: nil,
                                                                   callCustomer: nil,
                                                                   fuel: nil,
                                                                   keys: nil))
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

    func testProgressNeverChangesTheRoute() {
        // Belt and braces: the green-band predicate feeding the routing rule
        // still yields the checklist destination.
        let progressed = DriverChecklistLocalState(checks: [true, true, true, true],
                                                   callCustomer: "no_answer",
                                                   fuel: "Full",
                                                   keys: "With Machine")
        XCTAssertTrue(progressed.hasProgress)
        XCTAssertEqual(DriverChecklistRouting.destination(isArrived: false,
                                                          readyToGoAt: nil,
                                                          hasSavedProgress: progressed.hasProgress),
                       .driverChecklist)
    }
}
