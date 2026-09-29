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
    /// "" | "confirmed" | "no_answer" — "" = unset (nothing is preselected, spec §7.1).
    public var callCustomer: String
    /// "" | "Not Full" | "Full" (delivery only; "" = unanswered, or the unit needs no fuel sign-off).
    public var fuel: String
    /// "" | "Missing" | "With Machine" (delivery only; "" = unanswered, or no key sign-off).
    public var keys: String
    /// D5: the unique id of the unit `fuel` / `keys` were answered for
    /// ("" = unknown — a record written before the identity existed).
    public var equipmentUniqueId: String
    /// The assignment episode `fuel` / `keys` were answered in (2026-09-29): the id of this
    /// phone's latest durable switch for the line; "" = the row's own assignment, or no switch
    /// operation still retained (the engine prunes acknowledged operations after its retention
    /// window — a mismatch then only re-asks; the assignment flow also retires fuel / keys the
    /// moment any host records a delivery switch, so nothing depends on the operation
    /// surviving). A unit that comes back after a switch is a NEW episode of the same unit.
    public var assignmentEpisode: String

    public init(checks: [Bool] = [],
                callCustomer: String = "",
                fuel: String = "",
                keys: String = "",
                equipmentUniqueId: String = "",
                assignmentEpisode: String = "") {
        self.checks = checks
        self.callCustomer = callCustomer
        self.fuel = fuel
        self.keys = keys
        self.equipmentUniqueId = equipmentUniqueId
        self.assignmentEpisode = assignmentEpisode
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
            "assignment_episode": assignmentEpisode,
        ]
    }

    public init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        self.checks = (dictionary["deliveryChecks"] as? [Int])?.map { $0 == 1 } ?? []
        self.callCustomer = dictionary["call_customer"] as? String ?? ""
        self.fuel = dictionary["fuel"] as? String ?? ""
        self.keys = dictionary["keys"] as? String ?? ""
        self.equipmentUniqueId = dictionary["equipment_unique_id"] as? String ?? ""
        self.assignmentEpisode = dictionary["assignment_episode"] as? String ?? ""
    }

    // MARK: - Restore (D5, spec §7.3): local copy first, else the server copy — unit-checked

    /// The record to show on Screen 2 for the `effectiveUnit` (the row's unit
    /// overlaid by this phone's own unacknowledged switch). Call Customer and
    /// its ticks always restore — they belong to the customer interaction.
    /// Fuel and Keys restore only when the recorded unit IS the effective unit
    /// AND in the same assignment episode (`assignmentEpisode`: this phone's
    /// latest durable switch for the line, "" = the row's own assignment); if
    /// either differs, or the unit is absent while one is assigned, they return
    /// to unanswered — no phone inherits answers given for a replaced unit, nor
    /// for the same unit's earlier episode (switched away and back, 2026-09-29).
    /// With no unit assigned at all the record restores as recorded.
    public static func restore(local: DriverChecklistLocalState?,
                               server: DriverChecklistServerCopy?,
                               effectiveUnit: String?,
                               assignmentEpisode: String = "") -> DriverChecklistLocalState? {
        // The feed's checklist block is always present (nulls inside); a copy that
        // holds nothing is not a record — nothing restores nothing (review 8/9 #2).
        let serverRecord = server.flatMap { $0.isEmpty ? nil : DriverChecklistLocalState(server: $0) }
        guard var record = local ?? serverRecord else { return nil }

        guard let unit = effectiveUnit, !unit.isEmpty else { return record }
        if record.equipmentUniqueId == unit && record.assignmentEpisode == assignmentEpisode { return record }

        // Another unit, or the same unit in a NEW assignment episode: the answers were given
        // for an assignment that no longer exists.
        record.fuel = ""
        record.keys = ""
        record.equipmentUniqueId = unit
        record.assignmentEpisode = assignmentEpisode
        return record
    }

    /// The server's copy of the mini-checklist as a record.
    public init(server: DriverChecklistServerCopy) {
        self.init(checks: (server.checks ?? []).map { $0 == 1 },
                  callCustomer: server.callCustomer ?? "",
                  fuel: server.fuel ?? "",
                  keys: server.keys ?? "",
                  equipmentUniqueId: server.equipmentUniqueId ?? "")
    }

    // MARK: - Progress

    /// True when the driver has recorded anything — this is what turns the
    /// Dispatch button band GREEN. Nothing is preselected any more (spec §7.1),
    /// so every non-empty answer is an explicit one, including Not Full and
    /// Missing (recorded, and blocking departure). Routing reads the workflow
    /// stage, not this flag (DeliveryWorkflowStage).
    public var hasProgress: Bool {
        if checks.contains(true) { return true }
        if !callCustomer.isEmpty { return true }
        if !fuel.isEmpty { return true }
        if !keys.isEmpty { return true }
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
        if let call = callCustomer, !call.isEmpty { return true }
        if let fuel, !fuel.isEmpty { return true }
        if let keys, !keys.isEmpty { return true }
        return false
    }
}
