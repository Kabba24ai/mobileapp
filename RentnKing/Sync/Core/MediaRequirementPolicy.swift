//
//  MediaRequirementPolicy.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Driver Delivery Process Flow (2026-09-27), spec §10.3 / D7 — ONE delivery
//  media requirement, used by the Order Details tiles, the Complete gate and
//  the checklist's smart route, so they can never disagree again:
//
//      Delivery requires a VIDEO for THIS product in the CURRENT cycle.
//
//  Photos never satisfy it on their own — not as a local op, not as a feed
//  item, not through any order-level flag. Another product's video, a Return
//  video or a superseded cycle's video never satisfies. Order-scoped VIDEO
//  evidence (a video item on any line of the order, a video op with no cycle
//  id) counts only when no cycle is known for the product.
//

import Foundation

enum MediaRequirementPolicy {

    /// The durable delivery-video operations that satisfy the requirement for
    /// this product (every retained state — the caller decides how a Needs
    /// Attention record is presented). The evidence rule itself is
    /// EffectiveFieldState's; this is the one place that names it.
    static func deliveryVideoEvidence(operations: [SyncOperation],
                                      orderProductUniqueId: String,
                                      activeExecutionId: String?) -> [SyncOperation] {
        EffectiveFieldState.deliveryVideoEvidence(in: operations,
                                                  orderProductUniqueId: orderProductUniqueId,
                                                  activeExecutionId: activeExecutionId ?? "")
    }

    /// Is the delivery video requirement met?
    /// - `serverHasVideoForCycle`: the context's `delivery_video_present` for the active cycle.
    /// - `orderHasVideo`: order-scoped VIDEO evidence (a video item on any line of the order,
    ///   never a photo — the caller filters by media type); counts only while no cycle is
    ///   known for the product.
    static func deliveryVideoSatisfied(serverHasVideoForCycle: Bool,
                                       operations: [SyncOperation],
                                       orderProductUniqueId: String,
                                       activeExecutionId: String?,
                                       orderHasVideo: Bool) -> Bool {
        if serverHasVideoForCycle { return true }
        if !deliveryVideoEvidence(operations: operations, orderProductUniqueId: orderProductUniqueId,
                                  activeExecutionId: activeExecutionId).isEmpty { return true }
        if (activeExecutionId ?? "").isEmpty, orderHasVideo { return true }
        return false
    }
}
