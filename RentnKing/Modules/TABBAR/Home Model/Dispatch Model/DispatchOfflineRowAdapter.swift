//
//  DispatchOfflineRowAdapter.swift
//  RentnKing
//
//  Dispatch offline (Phase 3): a cached mission package's `dispatch.row` is
//  the SAME row the live Dispatch feed serves (Laravel builds both from one
//  mapping, parity-tested), so it maps through the unchanged SchedulesModel —
//  the Dispatch card, Driver Checklist and Assign Driver screen read it exactly
//  as they read a feed row.
//

import Foundation
import ObjectMapper

enum DispatchOfflineRowAdapter {

    static func schedulesModel(from row: JSONValue) -> SchedulesModel? {
        guard case .object = row, let json = row.anyValue as? [String: Any] else { return nil }
        return Mapper<SchedulesModel>().map(JSON: json)
    }
}

/// Review F2: the driver's trip stage on a Dispatch row, derived from the durable Sync Engine
/// steps (Load Map & Go / Arrived) over the row's server copy. The card reads these fields;
/// Screen 2 derives the same stage itself from DriverStageOverlay.
enum DriverStagePresentation {

    static func serverState(_ checklist: CheckListResponeData?) -> DriverStageServerState {
        DriverStageServerState(readyToGoAt: checklist?.ready_to_go_at, arrivedAt: checklist?.arrived_at,
                               isArrived: checklist?.is_arrived ?? false)
    }

    /// The row with its ACTIVE leg's effective stage applied (unchanged when not started).
    static func applying(_ overlay: DriverStageOverlay, to row: SchedulesModel, serverObservedAt: Date?) -> SchedulesModel {
        guard let id = row.unique_id, !id.isEmpty else { return row }
        let isDeliveryLeg = row.is_delivered == false
        let checklist = isDeliveryLeg ? row.delivery_checklist : row.pickup_checklist
        let effective = overlay.effective(orderProductUniqueId: id,
                                          leg: isDeliveryLeg ? DriverChecklistLocalState.legDelivery : DriverChecklistLocalState.legPickup,
                                          server: serverState(checklist), serverObservedAt: serverObservedAt)
        guard effective.stage != .notStarted,
              var updated = checklist ?? Mapper<CheckListResponeData>().map(JSON: [:]) else { return row }
        updated.ready_to_go_at = effective.readyToGoAt
        if effective.stage == .arrived {
            updated.arrived_at = effective.arrivedAt
            updated.is_arrived = true
        }
        var shown = row
        if isDeliveryLeg { shown.delivery_checklist = updated } else { shown.pickup_checklist = updated }
        return shown
    }
}
