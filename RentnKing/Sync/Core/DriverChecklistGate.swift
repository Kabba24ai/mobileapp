//
//  DriverChecklistGate.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Driver Delivery Process Flow (2026-09-27), spec §7 — the final pre-departure
//  gate on the Driver Checklist, locked by D2 (Fuel), D3 (Call) and D11 (Keys):
//
//      Load Map & Go enabled =
//            Assembly Review GO                                (Delivery only)
//        AND Call Customer complete                            (Delivery: the three wizard steps verified, or No Answer;
//                                                               Return: Confirmed + every check, or No Answer)
//        AND (Fuel not required OR Fuel == Full   for the current unit)
//        AND (Keys not required OR Keys == With Machine for the current unit)
//
//  No required field may pass because a default was silently pre-populated:
//  the screen preselects nothing, and an unanswered control is a blocker. The
//  decision carries the blockers as full sentences, in gate order, so the
//  button can say exactly why it is disabled.
//

import Foundation

/// The Call Customer outcome as the driver recorded it. `unset` = nothing chosen yet.
enum CallOutcome: Equatable {
    case unset
    /// Return only: "Confirmed" with the sub-checklist ticks in display order.
    /// `ticks` MUST be the display-length array (one entry per row, unticked =
    /// false) — a shorter array would pass with rows still unticked. The screen
    /// keeps fixed-size arrays for exactly this reason.
    case confirmed(ticks: [Bool])
    /// "No Answer" — an explicit, recorded call attempt (the server texts the customer).
    case noAnswer
    /// Delivery (Call Customer wizard, 2026-09-29): the successful call is the
    /// three verified steps; complete iff every step is — "Confirmed" is DERIVED
    /// from this and can never be asserted by a tap.
    case wizard(CustomerCallVerification)

    /// Return: from the stored segment value ("" | "confirmed" | "no_answer") and the ticks.
    init(callCustomer: String, ticks: [Bool]) {
        switch callCustomer {
        case "confirmed": self = .confirmed(ticks: ticks)
        case "no_answer": self = .noAnswer
        default: self = .unset
        }
    }

    /// Delivery: from the stored call value and the verified steps. No Answer is the
    /// explicit escape only while the wizard has not been started — any step recorded
    /// means the customer answered after all, and the wizard outranks the stale escape.
    /// A stored "confirmed" says nothing on its own (a row written before the wizard).
    init(callCustomer: String, verification: CustomerCallVerification) {
        if callCustomer == "no_answer", !verification.hasProgress {
            self = .noAnswer
        } else {
            self = .wizard(verification)
        }
    }

    /// The call requirement is complete: No Answer, Confirmed with every check
    /// ticked (Return), or every wizard step verified (Delivery).
    var isComplete: Bool {
        switch self {
        case .unset: return false
        case .noAnswer: return true
        case .confirmed(let ticks): return !ticks.isEmpty && !ticks.contains(false)
        case .wizard(let verification): return verification.isComplete
        }
    }

    var isWizard: Bool {
        if case .wizard = self { return true }
        return false
    }

    /// Confirmed → No Answer protection (2026-09-29): No Answer clears the verified
    /// steps, so over a FULLY verified call the driver is asked first. Every other
    /// No Answer — nothing verified, a call in progress, Return — stays one tap.
    var noAnswerNeedsConfirmation: Bool {
        if case .wizard(let verification) = self { return verification.isComplete }
        return false
    }
}

/// What the driver reads before No Answer replaces a confirmed call.
enum NoAnswerConfirmation {
    static let title = "Change to No Answer?"
    static let message = "This call is confirmed. Continuing will clear the verified call steps and change the call result to No Answer."
    static let cancelTitle = "Cancel"
    static let confirmTitle = "Record No Answer"
}

/// The Fuel segment's two explicit answers (the wire strings the server stores).
enum FuelAnswer: String, Equatable {
    case full = "Full"
    case notFull = "Not Full"
}

/// The Keys segment's two explicit answers.
enum KeysAnswer: String, Equatable {
    case withMachine = "With Machine"
    case missing = "Missing"
}

struct DriverChecklistGateInputs {
    let isDeliveryLeg: Bool
    let call: CallOutcome
    /// Whether the unit requires the fuel sign-off (DriverChecklistGate.fuelRequired).
    let fuelRequired: Bool
    /// nil = unanswered.
    let fuel: FuelAnswer?
    let keysRequired: Bool
    let keys: KeysAnswer?
    /// The assembly gate as this phone knows it: true = GO, false = STOP, nil = no review on this phone (§6.4).
    let assemblyReady: Bool?

    init(isDeliveryLeg: Bool, call: CallOutcome, fuelRequired: Bool, fuel: FuelAnswer?,
         keysRequired: Bool, keys: KeysAnswer?, assemblyReady: Bool?) {
        self.isDeliveryLeg = isDeliveryLeg
        self.call = call
        self.fuelRequired = fuelRequired
        self.fuel = fuel
        self.keysRequired = keysRequired
        self.keys = keys
        self.assemblyReady = assemblyReady
    }
}

struct DriverChecklistGateDecision: Equatable {
    let enabled: Bool
    /// Every unmet term, as the sentence the button shows, in gate order (assembly, call, fuel, keys).
    let blockers: [String]

    /// The one sentence under the button.
    var firstBlocker: String? { blockers.first }
}

enum DriverChecklistGate {

    static let blockerAssembly = "Confirm the assembly on Review Assembly before departing."
    /// Return's call (Confirmed with every tick, or No Answer).
    static let blockerCall = "Record the customer call: Confirmed with every check, or No Answer."
    /// Delivery's call (the wizard, or No Answer).
    static let blockerCallWizard = "Complete the customer call: verify the delivery address, the equipment order and the unloading situation — or record No Answer."
    static let blockerFuel = "Fuel is not ready. Equipment recorded as not fuel-ready must not leave the yard — fuel it, or choose a different unit on Review Assembly."
    static let blockerKeys = "The key is not with the machine. Locate it and record With Machine before departing."

    static func evaluate(_ i: DriverChecklistGateInputs) -> DriverChecklistGateDecision {
        var blockers: [String] = []

        if i.isDeliveryLeg {
            // Delivery only: the assembly must be GO as this phone knows it.
            // nil (no review on this phone) is honestly STOP — never a bypass.
            if i.assemblyReady != true { blockers.append(blockerAssembly) }
        }

        if !i.call.isComplete { blockers.append(i.call.isWizard ? blockerCallWizard : blockerCall) }

        if i.isDeliveryLeg {
            if i.fuelRequired && i.fuel != .full { blockers.append(blockerFuel) }
            if i.keysRequired && i.keys != .withMachine { blockers.append(blockerKeys) }
        }

        return DriverChecklistGateDecision(enabled: blockers.isEmpty, blockers: blockers)
    }

    /// Does the fuel sign-off apply to this unit? The yard's own predicate
    /// (`requires_fuel_check`, D5) wins; a cached package that predates it falls
    /// back to the display flag; unknown = ask (a silent skip is never safe).
    static func fuelRequired(requiresFuelCheck: Bool?, isFuel: Bool?) -> Bool {
        if let requires = requiresFuelCheck { return requires }
        return isFuel != false
    }

    static func keysRequired(requiresKeyCheck: Bool?, isKey: Bool?) -> Bool {
        if let requires = requiresKeyCheck { return requires }
        return isKey != false
    }
}
