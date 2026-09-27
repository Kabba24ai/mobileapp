//
//  DeliveryWorkflowStage.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Driver Delivery Process Flow (2026-09-27), spec §3.3 / §5: the ONE pure
//  derivation of where a driver is in a delivery, computed from the durable
//  stores the phone already has — leg completion, the driver's trip steps
//  (DriverStageOverlay over the row), the cached Assembly Review gate and the
//  driver mini-checklist evidence. Never stored anywhere; every surface that
//  routes (Dispatch's Start button, Order Details, the checklist exits) reads
//  it, so the stage IS the resume point and there is no "resume mode".
//
//  Precedence is physical truth first (delivered > arrived > on my way), then
//  the yard gate, then the driver's own progress. Once the driver is On My Way
//  or Arrived, a stale or later assembly STOP never rewinds them: the
//  assignment is locked (spec §3.4) and only an office recall — observed on
//  the server row after the local step — lowers the stage.
//

import Foundation

/// Where the driver is in one delivery mission (order product × leg).
enum DeliveryWorkflowStage: Int, Comparable {
    /// Gate STOP, no review on this phone, or nothing durable yet for this driver.
    case assemblyReview = 0
    /// Gate GO and the driver has durable mini-checklist evidence (Screen 2).
    case driverChecklist = 1
    case onMyWay = 2
    case arrived = 3
    case delivered = 4

    static func < (a: DeliveryWorkflowStage, b: DeliveryWorkflowStage) -> Bool { a.rawValue < b.rawValue }
}

/// The inputs, each from an existing durable store (spec §3.2).
struct DeliveryWorkflowInputs {
    /// EffectiveFieldState.legSatisfied (server ∨ a durable completion op).
    let legCompleted: Bool
    /// DriverStageOverlay.effective(…).stage (durable local steps ∨ the server row).
    let trip: DriverTripStage
    /// AssemblyPolicy.gate over the cached review + overlays; nil = no review on this phone (§6.4).
    let assemblyGate: AssemblyPolicy.LocalGate?
    /// §3.3.1 — DriverChecklistEvidence.exists.
    let hasDriverChecklistEvidence: Bool

    init(legCompleted: Bool, trip: DriverTripStage, assemblyGate: AssemblyPolicy.LocalGate?, hasDriverChecklistEvidence: Bool) {
        self.legCompleted = legCompleted
        self.trip = trip
        self.assemblyGate = assemblyGate
        self.hasDriverChecklistEvidence = hasDriverChecklistEvidence
    }
}

extension DeliveryWorkflowStage {

    static func resolve(_ i: DeliveryWorkflowInputs) -> DeliveryWorkflowStage {
        if i.legCompleted { return .delivered }
        if i.trip == .arrived { return .arrived }
        if i.trip == .onMyWay { return .onMyWay }
        guard let gate = i.assemblyGate, gate.ready else { return .assemblyReview }
        return i.hasDriverChecklistEvidence ? .driverChecklist : .assemblyReview
    }
}

/// Where a Dispatch "Start Delivery" / "Start Return" tap opens, by stage (spec §5).
/// Total over the enum; no stage at or beyond On My Way is ever routed to the yard gate.
enum DeliveryWorkflowRouting {

    enum Destination: Equatable {
        /// The Assembly Review, driver origin (Delivery only).
        case assemblyReview
        /// Screen 2 — the Driver Checklist (not started or On My Way).
        case driverChecklist
        /// Order Details — the customer-site hub (D4: Arrived resumes here).
        case mainOrder
        /// Nothing to open: the card leaves the working list.
        case none
    }

    static func destination(for stage: DeliveryWorkflowStage, isDeliveryLeg: Bool) -> Destination {
        switch stage {
        case .assemblyReview:
            // Return has no Assembly Review (§13): its gate stage is Screen 2.
            return isDeliveryLeg ? .assemblyReview : .driverChecklist
        case .driverChecklist, .onMyWay:
            return .driverChecklist
        case .arrived:
            return .mainOrder
        case .delivered:
            return .none
        }
    }
}

/// The server's copy of the driver mini-checklist for one leg, as the Dispatch
/// row's checklist block reports it (null = the server holds nothing).
struct DriverChecklistServerCopy: Equatable {
    var callCustomer: String?
    var fuel: String?
    var keys: String?
    var checks: [Int]?
    /// D5: the unit the fuel/keys answers were given for.
    var equipmentUniqueId: String?

    init(callCustomer: String? = nil, fuel: String? = nil, keys: String? = nil,
         checks: [Int]? = nil, equipmentUniqueId: String? = nil) {
        self.callCustomer = callCustomer
        self.fuel = fuel
        self.keys = keys
        self.checks = checks
        self.equipmentUniqueId = equipmentUniqueId
    }

    var isEmpty: Bool {
        callCustomer == nil && fuel == nil && keys == nil && checks == nil && equipmentUniqueId == nil
    }
}

/// §3.3.1 — what makes a second Start Delivery skip the review: any durable
/// trace that this driver reached Screen 2 for this product × leg.
enum DriverChecklistEvidence {

    static func exists(localRecord: DriverChecklistLocalState?,
                       serverChecklist: DriverChecklistServerCopy?,
                       operations: [SyncOperation],
                       orderProductUniqueId: String,
                       leg: String) -> Bool {
        // A v2 record under this product × leg — written when Screen 2 is first
        // shown through the driver road and on every mutation. Defaults count.
        if localRecord != nil { return true }

        // A retained driver_checklist.update op (partial save or transition) for
        // this product × leg, in every retained state (work stands).
        let hasOperation = operations.contains { op in
            op.type == EffectiveFieldState.driverChecklistType
                && EffectiveFieldState.countsAsDurableEvidence(op.state)
                && op.payload["order_product_unique_id"]?.stringValue == orderProductUniqueId
                && op.payload["checklist_type"]?.stringValue == leg
        }
        if hasOperation { return true }

        // Server mini-checklist state on the row — present, not merely non-default.
        if let serverChecklist, !serverChecklist.isEmpty { return true }

        return false
    }
}
