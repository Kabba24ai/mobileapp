//
//  EffectiveFieldState.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Local-first workflow (2026-09): once a field action is DURABLY persisted on
//  the phone, the app immediately behaves as though it is complete. The server
//  reconciles afterward. This is the ONE place that rule is computed:
//
//      effective = canonical server state  ∨  durable local evidence
//
//  Durable local evidence = a Sync Engine operation of the right type for the
//  right business identity, in ANY retained state:
//    • pending / syncing   — saved on this phone, on its way
//    • synced              — server confirmed (kept in the store)
//    • needsAttention      — server terminally rejected it, but the DRIVER's
//                            work stands (§ never reinsert): reconciliation is
//                            an office problem (Mobile Sync Issues board), not
//                            an instruction to repeat the physical job.
//
//  Consumers pass `engine.snapshot()`; this file never talks to the network,
//  never mutates, and never forges a cache — it is an overlay, so server truth
//  in feeds/caches stays unmodified underneath.
//

import Foundation

enum EffectiveFieldState {

    // MARK: - Operation types (mirror KabbaSync registrations)

    static let deliveryCompleteType = "delivery_checklist.complete"
    static let returnCompleteType = "return_checklist.complete"
    static let deliveryPrepareType = "delivery_checklist.prepare"
    static let returnPrepareType = "return_checklist.prepare"
    static let deliveryMediaType = "delivery_media.upload"
    static let returnMediaType = "return_media.upload"
    static let licenseMediaType = "license_media.upload"
    static let termsAcceptedType = "terms.accept"
    static let driverChecklistType = "driver_checklist.update"

    /// Every retained operation counts as durable completion for WORKFLOW
    /// purposes — including needsAttention (work preserved) and synced
    /// (record retained after ack, so there is no race with a stale feed).
    static func countsAsDurableEvidence(_ state: SyncState) -> Bool {
        switch state {
        case .pending, .syncing, .synced, .needsAttention:
            return true
        }
    }

    /// Is there durable local evidence of an operation of one of `types` for
    /// this identity? nil identity fields are wildcards; provided fields must
    /// match the op's SyncBusinessIdentity exactly.
    static func hasDurableEvidence(in operations: [SyncOperation],
                                          types: Set<String>,
                                          orderUniqueId: String? = nil,
                                          orderProductUniqueId: String? = nil) -> Bool {
        operations.contains { op in
            guard types.contains(op.type), countsAsDurableEvidence(op.state) else { return false }
            if let orderUniqueId, op.identity.orderUniqueId != orderUniqueId { return false }
            if let orderProductUniqueId, op.identity.orderProductUniqueId != orderProductUniqueId { return false }
            return true
        }
    }

    // MARK: - Dispatch completion overlay (QueueLineLocalOverlay pattern)

    /// Per-render overlay for the Dispatch working queue: which order products
    /// have a durably-completed delivery/return on THIS phone. A row whose
    /// active leg appears here leaves the working list immediately — and a
    /// server feed replace can never reinsert it, because the evidence out-
    /// lives the feed (ops are retained through synced/needsAttention).
    struct CompletionOverlay: Equatable {
        let completedDeliveryProducts: Set<String>
        let completedReturnProducts: Set<String>

        static func from(_ operations: [SyncOperation]) -> CompletionOverlay {
            var delivery = Set<String>()
            var returns = Set<String>()
            for op in operations where countsAsDurableEvidence(op.state) {
                guard let productUid = op.identity.orderProductUniqueId else { continue }
                if op.type == deliveryCompleteType { delivery.insert(productUid) }
                if op.type == returnCompleteType { returns.insert(productUid) }
            }
            return CompletionOverlay(completedDeliveryProducts: delivery, completedReturnProducts: returns)
        }

        /// The dispatch row's ACTIVE leg is locally complete → drop it from the
        /// working queue. (`isDeliveryLeg` mirrors the feed's `is_delivered ==
        /// false` convention: false means the row is showing its return leg.)
        func isLegLocallyCompleted(orderProductUniqueId: String, isDeliveryLeg: Bool) -> Bool {
            isDeliveryLeg
                ? completedDeliveryProducts.contains(orderProductUniqueId)
                : completedReturnProducts.contains(orderProductUniqueId)
        }

        var isEmpty: Bool {
            completedDeliveryProducts.isEmpty && completedReturnProducts.isEmpty
        }
    }

    // MARK: - Requirement checks (exception/override screen + chips)

    /// Delivery/return media requirement satisfied? server truth ∨ durable local media op.
    static func mediaSatisfied(serverHasMedia: Bool,
                                      operations: [SyncOperation],
                                      orderUniqueId: String,
                                      isDeliveryLeg: Bool) -> Bool {
        serverHasMedia || hasDurableEvidence(
            in: operations,
            types: [isDeliveryLeg ? deliveryMediaType : returnMediaType],
            orderUniqueId: orderUniqueId
        )
    }

    /// License requirement satisfied? server truth ∨ durable local license op.
    static func licenseSatisfied(serverHasLicense: Bool,
                                        operations: [SyncOperation],
                                        orderUniqueId: String) -> Bool {
        serverHasLicense || hasDurableEvidence(in: operations,
                                               types: [licenseMediaType],
                                               orderUniqueId: orderUniqueId)
    }

    /// Terms & Conditions requirement satisfied? server truth (Accepted/Exempt)
    /// ∨ durable local acceptance op. Terms are an ORDER-level fact — any
    /// terms.accept evidence for the order satisfies, whichever product's
    /// workflow surfaced the signing.
    static func termsSatisfied(serverAccepted: Bool,
                                      operations: [SyncOperation],
                                      orderUniqueId: String) -> Bool {
        serverAccepted || hasDurableEvidence(in: operations,
                                             types: [termsAcceptedType],
                                             orderUniqueId: orderUniqueId)
    }

    /// Delivery VIDEO requirement satisfied for ONE order product?
    /// server truth ∨ a durable local delivery-media operation FOR THIS
    /// product that carries a video asset. Per-product identity is strict:
    /// a sibling product's video, a Return-leg video, or a photo never
    /// satisfies. All retained states count (pending/syncing/synced/
    /// needsAttention) — the operator never re-captures work that is
    /// durably on the phone (post-Save smart routing, 2026-09).
    static func deliveryVideoSatisfied(serverHasVideo: Bool,
                                              operations: [SyncOperation],
                                              orderProductUniqueId: String) -> Bool {
        if serverHasVideo { return true }
        guard !orderProductUniqueId.isEmpty else { return false }

        return operations.contains { op in
            op.type == deliveryMediaType
                && countsAsDurableEvidence(op.state)
                && op.identity.orderProductUniqueId == orderProductUniqueId
                && op.assets.contains { $0.mimeType.hasPrefix("video/") }
        }
    }

    /// Leg completion satisfied? server truth ∨ durable local completion op.
    static func legSatisfied(serverCompleted: Bool,
                                    operations: [SyncOperation],
                                    orderProductUniqueId: String,
                                    isDeliveryLeg: Bool) -> Bool {
        serverCompleted || hasDurableEvidence(
            in: operations,
            types: [isDeliveryLeg ? deliveryCompleteType : returnCompleteType],
            orderProductUniqueId: orderProductUniqueId
        )
    }
}
