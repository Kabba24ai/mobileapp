//
//  DriverChecklistLocalState.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The driver MINI-checklist a driver answers on Screen 2 (Dispatch → Driver
//  Checklist → Order Details) before leaving for a delivery or return: call
//  customer, the call sub-checklist, fuel and keys. NOT the full Delivery/
//  Return equipment checklist — that is a separate system (ChecklistContext).
//
//  This file owns the record's rules:
//
//  1. PROGRESS IS SCOPED TO ORDER-PRODUCT + LEG. Delivery cannot populate
//     Return, product A cannot populate product B, one order cannot populate
//     another. The pre-correction key was scoped to the ORDER, which leaked
//     state across the lines of a multi-line order — hence the "v2" key
//     namespace: old order-scoped blobs are simply ignored.
//
//  2. FUEL AND KEYS BELONG TO ONE UNIT (D5, 2026-09-27). The record carries the
//     identity of the unit those answers were given for, so a replaced unit
//     always starts unanswered — on this phone and on any other phone that
//     restores from the server's copy.
//
//  Routing is NOT decided here. A Start Delivery / Start Return tap opens the
//  screen the effective workflow stage names (DeliveryWorkflowStage, spec §5);
//  this record is one of that derivation's inputs (evidence), never a router.
//  The 2026-09 "routing is absolute" rule that lived here trusted a stale
//  server is_arrived; the stage derivation trusts the effective, local-first
//  trip stage instead.
//
//  Saved answers are current state, not a historical lock: every value here
//  restores into the same editable controls that wrote it.
//

import Foundation

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
    /// D5: the unique id of the unit `fuel` / `keys` were answered for
    /// ("" = unknown — a record written before the identity existed).
    public var equipmentUniqueId: String

    public init(checks: [Bool] = [],
                callCustomer: String = "",
                fuel: String = "",
                keys: String = "",
                equipmentUniqueId: String = "") {
        self.checks = checks
        self.callCustomer = callCustomer
        self.fuel = fuel
        self.keys = keys
        self.equipmentUniqueId = equipmentUniqueId
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
            "equipment_unique_id": equipmentUniqueId,
        ]
    }

    public init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        self.checks = (dictionary["deliveryChecks"] as? [Int])?.map { $0 == 1 } ?? []
        self.callCustomer = dictionary["call_customer"] as? String ?? ""
        self.fuel = dictionary["fuel"] as? String ?? ""
        self.keys = dictionary["keys"] as? String ?? ""
        self.equipmentUniqueId = dictionary["equipment_unique_id"] as? String ?? ""
    }

    // MARK: - Progress

    /// True when the driver has entered anything beyond the untouched
    /// defaults — this is what turns the Dispatch button band GREEN. Routing
    /// reads the workflow stage, not this flag (DeliveryWorkflowStage).
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
