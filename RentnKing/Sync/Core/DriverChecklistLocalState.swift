//
//  DriverChecklistLocalState.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The driver MINI-checklist a driver answers on Screen 2 (Dispatch → Driver
//  Checklist → Order Details) before leaving for a delivery or return: call
//  customer, the call sub-checklist, fuel and keys. NOT the full Delivery/
//  Return equipment checklist — that is a separate system (ChecklistContext).
//
//  This file owns the two rules the 2026-09 workflow correction is built on:
//
//  1. ROUTING IS ABSOLUTE (DriverChecklistRouting). A Start Delivery / Start
//     Return tap ALWAYS opens the Driver Checklist screen. Saved progress —
//     local, server, partial, complete, even "driver already arrived" — only
//     changes what Screen 2 shows, never which screen opens. The old shortcut
//     (is_arrived → straight to Order Details) is the bug this replaces.
//
//  2. PROGRESS IS SCOPED TO ORDER-PRODUCT + LEG (DriverChecklistLocalState).
//     Delivery cannot populate Return, product A cannot populate product B,
//     one order cannot populate another. The pre-correction key was scoped to
//     the ORDER, which leaked state across the lines of a multi-line order —
//     hence the "v2" key namespace: old order-scoped blobs are simply ignored.
//
//  Saved answers are current state, not a historical lock: every value here
//  restores into the same editable controls that wrote it.
//

import Foundation

/// Where a Dispatch "Start Delivery" / "Start Return" tap must navigate.
public enum DriverChecklistRouting {

    public enum Destination: Equatable {
        /// Screen 2 — the Driver Checklist. The only valid destination.
        case driverChecklist
    }

    /// The navigation rule: EVERY combination of prior state routes to the
    /// Driver Checklist. The inputs exist so the rule is enforced where the
    /// temptation lives — a future "skip when X" must change this function's
    /// signature and the tests that pin all combinations down.
    public static func destination(isArrived: Bool,
                                   readyToGoAt: String?,
                                   hasSavedProgress: Bool) -> Destination {
        // Saved checklist progress changes the CONTENTS of Screen 2,
        // never the routing around Screen 2.
        return .driverChecklist
    }
}

/// The locally persisted state of one driver mini-checklist (one order
/// product, one leg). Field names mirror the canonical wire contract of
/// `driver_checklist.update` where one exists.
public struct DriverChecklistLocalState: Equatable {

    public static let legDelivery = "delivery"
    public static let legPickup = "pickup"

    /// The call-customer sub-checklist ticks, in display order.
    /// Delivery has 4 items, return has 3 — the count is owned by the screen.
    public var checks: [Bool]
    /// "confirmed" | "no_answer" (segment; "confirmed" is the default).
    public var callCustomer: String
    /// "" | "Not Full" | "Full" (delivery only; "" = equipment has no fuel).
    public var fuel: String
    /// "" | "Missing" | "With Machine" (delivery only; "" = no keys).
    public var keys: String

    public init(checks: [Bool] = [],
                callCustomer: String = "",
                fuel: String = "",
                keys: String = "") {
        self.checks = checks
        self.callCustomer = callCustomer
        self.fuel = fuel
        self.keys = keys
    }

    // MARK: - Identity

    /// UserDefaults key, scoped to ORDER-PRODUCT + LEG. "v2" retires the old
    /// order-scoped key ("driverChecklist_<orderUID>_<leg>") that leaked
    /// progress across the products of a multi-line order.
    public static func key(orderProductUniqueId: String, leg: String) -> String {
        "driverChecklist_v2_\(orderProductUniqueId)_\(leg)"
    }

    // MARK: - Round trip (UserDefaults dictionary)

    /// The dictionary layout keeps the pre-correction field names
    /// ("deliveryChecks", "fuel", "keys", "call_customer") so the shape stays
    /// recognisable in a device dump, but lives under the v2 key.
    public func dictionary() -> [String: Any] {
        [
            "deliveryChecks": checks.map { $0 ? 1 : 0 },
            "call_customer": callCustomer,
            "fuel": fuel,
            "keys": keys,
        ]
    }

    public init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        self.checks = (dictionary["deliveryChecks"] as? [Int])?.map { $0 == 1 } ?? []
        self.callCustomer = dictionary["call_customer"] as? String ?? ""
        self.fuel = dictionary["fuel"] as? String ?? ""
        self.keys = dictionary["keys"] as? String ?? ""
    }

    // MARK: - Progress

    /// True when the driver has entered anything beyond the untouched
    /// defaults — this is what turns the Dispatch button band GREEN. It never
    /// influences routing (see DriverChecklistRouting).
    public var hasProgress: Bool {
        if checks.contains(true) { return true }
        if callCustomer == "no_answer" { return true }   // deliberate non-default selection
        if fuel == "Full" { return true }                // default is "Not Full"
        if keys == "With Machine" { return true }        // default is "Missing"
        return false
    }

    /// Progress as the SERVER reports it in the dispatch feed's checklist
    /// block — used so a reassigned driver's phone (no local state) still
    /// shows the green band for work the previous driver saved.
    public static func serverHasProgress(driverChecks: [Int]?,
                                         callCustomer: String?,
                                         fuel: String?,
                                         keys: String?) -> Bool {
        if driverChecks?.contains(1) == true { return true }
        if callCustomer == "no_answer" { return true }
        if fuel == "Full" { return true }
        if keys == "With Machine" { return true }
        return false
    }
}
