//
//  DriverChecklistLocalState.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The driver MINI-checklist a driver answers on Screen 2 (Dispatch → Driver
//  Checklist → Order Details) before leaving for a delivery or return: call
//  customer (Delivery: the three-step wizard; Return: the call sub-checklist),
//  fuel and keys. NOT the full Delivery/Return equipment checklist — that is a
//  separate system (ChecklistContext).
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
//  3. THE CALL BELONGS TO THE MISSION (2026-09-29). The Delivery call's three
//     verified steps (address, equipment order, unloading situation) and the
//     explicit No Answer are never bound to a unit: a switch leaves them
//     exactly as they were. "Confirmed" is derived from the steps, never stored
//     as a claim (a stored "confirmed" without the steps reads as not completed).
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

    /// Return's call sub-checklist ticks, in display order (3 items — the count is
    /// owned by the screen). Delivery no longer has ticks (the wizard replaced them).
    public var checks: [Bool]
    /// "" | "confirmed" | "no_answer" — "" = unset (nothing is preselected, spec §7.1).
    /// On Delivery "confirmed" is DERIVED: it is written by `callVerification`'s setter
    /// when the three steps are complete and means nothing by itself (`deliveryCallOutcome`).
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
    /// Call Customer wizard (Delivery): the three verified steps, as the wire carries them.
    public var addressVerified: Bool
    public var equipmentVerified: Bool
    /// The unloading situation code ("" = not chosen) and its note (Other only).
    public var unloadingSituation: String
    public var unloadingNote: String

    public init(checks: [Bool] = [],
                callCustomer: String = "",
                fuel: String = "",
                keys: String = "",
                equipmentUniqueId: String = "",
                assignmentEpisode: String = "",
                addressVerified: Bool = false,
                equipmentVerified: Bool = false,
                unloadingSituation: String = "",
                unloadingNote: String = "") {
        self.checks = checks
        self.callCustomer = callCustomer
        self.fuel = fuel
        self.keys = keys
        self.equipmentUniqueId = equipmentUniqueId
        self.assignmentEpisode = assignmentEpisode
        self.addressVerified = addressVerified
        self.equipmentVerified = equipmentVerified
        self.unloadingSituation = unloadingSituation
        self.unloadingNote = unloadingNote
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
    /// recognisable in a device dump, but lives under the v2 key. The wizard's
    /// four keys are the server's names.
    public func dictionary() -> [String: Any] {
        [
            "deliveryChecks": checks.map { $0 ? 1 : 0 },
            "call_customer": callCustomer,
            "fuel": fuel,
            "keys": keys,
            "equipment_unique_id": equipmentUniqueId,
            "assignment_episode": assignmentEpisode,
            "address_verified": addressVerified,
            "equipment_verified": equipmentVerified,
            "unloading_situation": unloadingSituation,
            "unloading_note": unloadingNote,
        ]
    }

    /// A record written before the wizard has none of its keys: every step reads
    /// as NOT completed (never mapped from the retired ticks).
    public init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }
        self.checks = (dictionary["deliveryChecks"] as? [Int])?.map { $0 == 1 } ?? []
        self.callCustomer = dictionary["call_customer"] as? String ?? ""
        self.fuel = dictionary["fuel"] as? String ?? ""
        self.keys = dictionary["keys"] as? String ?? ""
        self.equipmentUniqueId = dictionary["equipment_unique_id"] as? String ?? ""
        self.assignmentEpisode = dictionary["assignment_episode"] as? String ?? ""
        self.addressVerified = dictionary["address_verified"] as? Bool ?? false
        self.equipmentVerified = dictionary["equipment_verified"] as? Bool ?? false
        self.unloadingSituation = dictionary["unloading_situation"] as? String ?? ""
        self.unloadingNote = dictionary["unloading_note"] as? String ?? ""
    }

    // MARK: - The Delivery call (Call Customer wizard, 2026-09-29)

    /// The three steps as one value. Setting it re-derives `callCustomer`: "confirmed"
    /// when complete, otherwise "" — and any recorded step retires a standing No Answer
    /// (the customer answered after all; the escape is not a mode the wizard runs inside).
    public var callVerification: CustomerCallVerification {
        get {
            CustomerCallVerification(addressVerified: addressVerified, equipmentVerified: equipmentVerified,
                                     unloadingCode: unloadingSituation, unloadingNote: unloadingNote)
        }
        set {
            addressVerified = newValue.addressVerified
            equipmentVerified = newValue.equipmentVerified
            unloadingSituation = newValue.unloadingCode
            unloadingNote = newValue.unloadingNote
            callCustomer = newValue.isComplete ? "confirmed" : ""
        }
    }

    /// No Answer: the explicit, recorded escape. The steps return to not completed so a
    /// later successful call starts again at the address (the server does the same).
    public mutating func recordNoAnswer() {
        callVerification = .notStarted
        callCustomer = "no_answer"
    }

    /// The Delivery call as the gate judges it — derived, never trusted from `callCustomer`.
    var deliveryCallOutcome: CallOutcome {
        CallOutcome(callCustomer: callCustomer, verification: callVerification)
    }

    // MARK: - Restore (D5, spec §7.3): local copy first, else the server copy — unit-checked

    /// The record to show on Screen 2 for the `effectiveUnit` (the row's unit
    /// overlaid by this phone's own unacknowledged switch). Call Customer — the
    /// wizard's steps, No Answer, Return's ticks — always restores — it belongs to
    /// the customer interaction, not to a machine.
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
        // for an assignment that no longer exists. The call is untouched.
        record.fuel = ""
        record.keys = ""
        record.equipmentUniqueId = unit
        record.assignmentEpisode = assignmentEpisode
        return record
    }

    /// The server's copy of the mini-checklist as a record. The wizard's steps come
    /// through as the feed reports them (false / null = not completed); the call
    /// column is kept as recorded — `deliveryCallOutcome` derives the truth.
    public init(server: DriverChecklistServerCopy) {
        self.init(checks: (server.checks ?? []).map { $0 == 1 },
                  callCustomer: server.callCustomer ?? "",
                  fuel: server.fuel ?? "",
                  keys: server.keys ?? "",
                  equipmentUniqueId: server.equipmentUniqueId ?? "",
                  addressVerified: server.addressVerified == true,
                  equipmentVerified: server.equipmentVerified == true,
                  unloadingSituation: server.unloadingSituation ?? "",
                  unloadingNote: server.unloadingNote ?? "")
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
        if callVerification.hasProgress { return true }
        return false
    }

    /// Progress as the SERVER reports it in the dispatch feed's checklist
    /// block — used so a reassigned driver's phone (no local state) still
    /// shows the green band for work the previous driver saved.
    public static func serverHasProgress(driverChecks: [Int]?,
                                         callCustomer: String?,
                                         fuel: String?,
                                         keys: String?,
                                         addressVerified: Bool? = nil,
                                         equipmentVerified: Bool? = nil,
                                         unloadingSituation: String? = nil) -> Bool {
        if driverChecks?.contains(1) == true { return true }
        if let call = callCustomer, !call.isEmpty { return true }
        if let fuel, !fuel.isEmpty { return true }
        if let keys, !keys.isEmpty { return true }
        if addressVerified == true || equipmentVerified == true { return true }
        if let situation = unloadingSituation, !situation.isEmpty { return true }
        return false
    }
}
