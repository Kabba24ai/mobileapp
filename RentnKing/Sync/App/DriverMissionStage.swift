//
//  DriverMissionStage.swift
//  RentnKing — Sync App
//
//  Driver Delivery Process Flow (2026-09-27), spec §3.2 / §3.3: the ONE place
//  the app assembles the inputs of `DeliveryWorkflowStage.resolve` from the
//  phone's durable stores — the Sync Engine's operations, the Dispatch row's
//  server copy (when the caller has one), the driver mini-checklist record in
//  UserDefaults and the cached Assembly Review. Dispatch's Start button, the
//  Driver Checklist and the driver-origin Assembly Review all call it, so the
//  three screens can never derive three different stages.
//

import Foundation

enum DriverMissionStage {

    /// What a caller knows about the mission besides the engine and the caches.
    struct Inputs {
        let orderProductUniqueId: String
        let isDeliveryLeg: Bool
        /// The Dispatch row's server copy of the trip; nil when the caller has no
        /// row (the review) — the phone's own durable steps then decide alone.
        let serverTrip: DriverStageServerState?
        let serverObservedAt: Date?
        /// The row's server copy of the mini-checklist (nil when unknown / empty).
        let serverChecklist: DriverChecklistServerCopy?
        /// The server says the leg is completed.
        let serverLegCompleted: Bool
        /// The caller IS the Driver Checklist: being there is the §3.3.1 evidence.
        let onDriverChecklist: Bool

        init(orderProductUniqueId: String, isDeliveryLeg: Bool,
             serverTrip: DriverStageServerState? = nil, serverObservedAt: Date? = nil,
             serverChecklist: DriverChecklistServerCopy? = nil, serverLegCompleted: Bool = false,
             onDriverChecklist: Bool = false) {
            self.orderProductUniqueId = orderProductUniqueId
            self.isDeliveryLeg = isDeliveryLeg
            self.serverTrip = serverTrip
            self.serverObservedAt = serverObservedAt
            self.serverChecklist = serverChecklist
            self.serverLegCompleted = serverLegCompleted
            self.onDriverChecklist = onDriverChecklist
        }

        var leg: String { isDeliveryLeg ? DriverChecklistLocalState.legDelivery : DriverChecklistLocalState.legPickup }
    }

    /// The driver's trip stage — durable local steps over the row's server copy.
    static func trip(_ i: Inputs, operations: [SyncOperation]) -> DriverStageEffective {
        DriverStageOverlay.from(operations).effective(
            orderProductUniqueId: i.orderProductUniqueId, leg: i.leg,
            server: i.serverTrip ?? DriverStageServerState(readyToGoAt: nil, arrivedAt: nil, isArrived: false),
            serverObservedAt: i.serverObservedAt)
    }

    /// The mission's assembly gate as this phone knows it (nil = no review on this
    /// phone → honestly STOP, §6.4). Return has no assembly gate.
    static func assemblyGate(orderProductUniqueId: String, isDeliveryLeg: Bool,
                             review: AssemblyReview?, operations: [SyncOperation]) -> AssemblyPolicy.LocalGate? {
        guard isDeliveryLeg else { return nil }
        return AssemblyPolicy.gate(forMission: orderProductUniqueId, in: review,
                                   queue: QueueLineLocalOverlay.from(operations),
                                   overlay: AssemblyLocalOverlay.from(operations))
    }

    /// The driver mini-checklist record on this phone for the product × leg.
    static func localRecord(orderProductUniqueId: String, leg: String) -> DriverChecklistLocalState? {
        DriverChecklistLocalState(dictionary: UserDefaults.standard.dictionary(
            forKey: DriverChecklistLocalState.key(orderProductUniqueId: orderProductUniqueId, leg: leg)))
    }

    /// Where the mission is (spec §3.3). Never stored; the stage IS the resume point.
    static func stage(_ i: Inputs, review: AssemblyReview?, operations: [SyncOperation]) -> DeliveryWorkflowStage {
        let evidence = i.onDriverChecklist || DriverChecklistEvidence.exists(
            localRecord: localRecord(orderProductUniqueId: i.orderProductUniqueId, leg: i.leg),
            serverChecklist: i.serverChecklist,
            operations: operations,
            orderProductUniqueId: i.orderProductUniqueId,
            leg: i.leg)
        return DeliveryWorkflowStage.resolve(DeliveryWorkflowInputs(
            legCompleted: EffectiveFieldState.legSatisfied(serverCompleted: i.serverLegCompleted,
                                                           operations: operations,
                                                           orderProductUniqueId: i.orderProductUniqueId,
                                                           isDeliveryLeg: i.isDeliveryLeg),
            trip: trip(i, operations: operations).stage,
            assemblyGate: assemblyGate(orderProductUniqueId: i.orderProductUniqueId, isDeliveryLeg: i.isDeliveryLeg,
                                       review: review, operations: operations),
            hasDriverChecklistEvidence: evidence))
    }
}
