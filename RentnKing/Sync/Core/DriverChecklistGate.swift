//
//  DriverChecklistGate.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Driver Delivery Process Flow (2026-09-27), spec §7 — the final pre-departure
//  gate on the Driver Checklist, locked by D2 (Fuel), D3 (Call) and D11 (Keys):
//
//      Load Map & Go enabled =
//            Assembly Review GO                                (Delivery only)
//        AND Call Customer complete                            (Confirmed + every check, or No Answer)
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
    /// "Confirmed" with the sub-checklist ticks in display order.
    case confirmed(ticks: [Bool])
    /// "No Answer" — an explicit, recorded call attempt (the server texts the customer).
    case noAnswer

    /// From the stored segment value ("" | "confirmed" | "no_answer") and the ticks.
    init(callCustomer: String, ticks: [Bool]) {
        switch callCustomer {
        case "confirmed": self = .confirmed(ticks: ticks)
        case "no_answer": self = .noAnswer
        default: self = .unset
        }
    }

    /// The call requirement is complete: No Answer, or Confirmed with every check ticked.
    var isComplete: Bool {
        switch self {
        case .unset: return false
        case .noAnswer: return true
        case .confirmed(let ticks): return !ticks.isEmpty && !ticks.contains(false)
        }
    }
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
    static let blockerCall = "Record the customer call: Confirmed with every check, or No Answer."
    static let blockerFuel = "Fuel is not ready. Equipment recorded as not fuel-ready must not leave the yard — fuel it, or choose a different unit on Review Assembly."
    static let blockerKeys = "The key is not with the machine. Locate it and record With Machine before departing."

    static func evaluate(_ i: DriverChecklistGateInputs) -> DriverChecklistGateDecision {
        var blockers: [String] = []

        if i.isDeliveryLeg {
            // Delivery only: the assembly must be GO as this phone knows it.
            // nil (no review on this phone) is honestly STOP — never a bypass.
            if i.assemblyReady != true { blockers.append(blockerAssembly) }
        }

        if !i.call.isComplete { blockers.append(blockerCall) }

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
