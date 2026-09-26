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
    /// Dispatch offline Phase 5: a signature captured on this phone, bound to the order's frozen agreement.
    static let termsSignedType = "terms.sign"
    static let driverChecklistType = "driver_checklist.update"
    /// Pre-departure preparation lifecycle (2026-09): the two operations that
    /// DISCARD a preparation cycle. Both are the phone's local-first record of
    /// a supersession Laravel performs canonically.
    static let equipmentSubstitutionType = PreparationOperationBuilder.substitutionType
    static let deliveryRestartType = "delivery_checklist.reset"
    static let returnRestartType = "return_checklist.reset"

    /// Operations that end a preparation cycle for their order product.
    static let preparationDiscardTypes: Set<String> = [
        equipmentSubstitutionType, deliveryRestartType, returnRestartType,
    ]

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

    /// Checklist executions this phone durably discarded — the cycles named by
    /// a substitution or a restart operation. Evidence belonging to one of these
    /// cycles describes a machine that is no longer being prepared, so it must
    /// never satisfy the current one.
    static func supersededExecutionIds(in operations: [SyncOperation]) -> Set<String> {
        var ids = Set<String>()
        for op in operations where preparationDiscardTypes.contains(op.type) && countsAsDurableEvidence(op.state) {
            if let execution = op.identity.checklistExecutionId, !execution.isEmpty { ids.insert(execution) }
        }
        return ids
    }

    /// Order products whose preparation this phone durably discarded AFTER the
    /// given moment. Used to decide whether older local evidence still stands.
    static func lastDiscardAt(in operations: [SyncOperation], orderProductUniqueId: String) -> Date? {
        operations
            .filter { preparationDiscardTypes.contains($0.type)
                && countsAsDurableEvidence($0.state)
                && $0.identity.orderProductUniqueId == orderProductUniqueId }
            .map(\.queuedAt)
            .max()
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
    /// ∨ durable local evidence. Terms are an ORDER-level fact — one signature
    /// covers every line of its order, whichever product's workflow surfaced it:
    ///   • terms.accept (the hosted page already recorded acceptance server-side):
    ///     any retained op for the order, as before;
    ///   • terms.sign (signed on this phone, Phase 5): a HEALTHY op (pending /
    ///     syncing / synced) for this order whose terms identity is the verified
    ///     agreement this phone holds for it (`termsIdentity`; empty = the phone
    ///     holds none, nothing contradicts the op). A parked (Needs Attention)
    ///     terms.sign never satisfies: the server refused it (the wrong order's
    ///     document, corrupted data) — it is kept, never relabelled.
    static func termsSatisfied(serverAccepted: Bool,
                                      operations: [SyncOperation],
                                      orderUniqueId: String,
                                      termsIdentity: String = "") -> Bool {
        serverAccepted
            || hasDurableEvidence(in: operations, types: [termsAcceptedType], orderUniqueId: orderUniqueId)
            || !healthyTermsSignatures(in: operations, orderUniqueId: orderUniqueId, termsIdentity: termsIdentity).isEmpty
    }

    /// The Order List's T&C tile (display only, Phase 5 hardening): the server's Accepted, or a HEALTHY
    /// terms.sign for this order at the verified identity. A signing is never turned into an in-memory
    /// "Accepted" — so a signature the server refuses (Needs Attention) stops showing as signed.
    static func termsShownAsSigned(serverStatus: String?,
                                   operations: [SyncOperation],
                                   orderUniqueId: String,
                                   termsIdentity: String) -> Bool {
        serverStatus == "Accepted"
            || !healthyTermsSignatures(in: operations, orderUniqueId: orderUniqueId, termsIdentity: termsIdentity).isEmpty
    }

    /// The terms.sign operations that count for this order and verified identity.
    static func healthyTermsSignatures(in operations: [SyncOperation],
                                       orderUniqueId: String,
                                       termsIdentity: String) -> [SyncOperation] {
        guard !orderUniqueId.isEmpty else { return [] }
        return operations.filter { op in
            op.type == termsSignedType
                && op.identity.orderUniqueId == orderUniqueId
                && countsAsDurableEvidence(op.state) && op.state != .needsAttention
                && (termsIdentity.isEmpty || TermsSignOperationBuilder.termsIdentity(of: op) == termsIdentity)
        }
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
                                              orderProductUniqueId: String,
                                              activeExecutionId: String = "") -> Bool {
        if serverHasVideo { return true }
        guard !orderProductUniqueId.isEmpty else { return false }

        // Preparation-cycle identity (2026-09): a walk-around video is evidence
        // about ONE physical machine. When the caller knows which cycle is
        // active, only that cycle's video counts — so a video shot for the unit
        // a substitution replaced can never let the replacement skip its own.
        let superseded = supersededExecutionIds(in: operations)
        let discardedAt = lastDiscardAt(in: operations, orderProductUniqueId: orderProductUniqueId)

        return operations.contains { op in
            guard op.type == deliveryMediaType,
                  countsAsDurableEvidence(op.state),
                  op.identity.orderProductUniqueId == orderProductUniqueId,
                  op.assets.contains(where: { $0.mimeType.hasPrefix("video/") }) else { return false }

            let opExecution = op.identity.checklistExecutionId ?? ""

            if !activeExecutionId.isEmpty {
                return opExecution == activeExecutionId
            }

            // No active cycle known (legacy/offline first open): the evidence
            // still stands unless this phone discarded its cycle, or captured
            // it before a discard it cannot attribute.
            if !opExecution.isEmpty, superseded.contains(opExecution) { return false }
            if let discardedAt, op.queuedAt < discardedAt { return false }
            return true
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

// MARK: - Driver trip stage (Load Map & Go / On My Way / Arrived) — review F2
//
// The same local-first rule, for the driver's trip on one order product + leg:
//
//     durable local action → immediate effective state → later server confirmation
//
// Load Map & Go and Arrived are driver_checklist.update operations the Sync Engine
// keeps on disk (pending → synced, retained). Screen 2 and the Dispatch card derive
// the stage from them over the row's server copy, so leaving Dispatch, a force-quit
// or a relaunch offline can never forget a departure or an arrival — and never
// offers the step again. There is no second store for the stage.

/// The driver's trip stage as Screen 2 shows it.
enum DriverTripStage: Int, Comparable {
    /// The Driver Checklist; Load Map & Go not yet tapped.
    case notStarted = 0
    /// Departed ("On My Way"): the server stamps ready_to_go_at.
    case onMyWay = 1
    case arrived = 2

    static func < (a: DriverTripStage, b: DriverTripStage) -> Bool { a.rawValue < b.rawValue }
}

/// What the row's own checklist block says — server truth as last downloaded.
struct DriverStageServerState: Equatable {
    var readyToGoAt: String?
    var arrivedAt: String?
    var isArrived: Bool
}

struct DriverStageEffective: Equatable {
    var stage: DriverTripStage
    /// "yyyy-MM-dd HH:mm:ss" — the server's stamp, else when the driver did it on this phone.
    var readyToGoAt: String?
    var arrivedAt: String?

    /// Load Map & Go records a departure only before the leg departed.
    var recordsDeparture: Bool { stage == .notStarted }
    /// Arrived records an arrival only once — afterwards the button only continues.
    var recordsArrival: Bool { stage != .arrived }
}

/// Durable local evidence of every driver trip on this phone, from engine.snapshot().
struct DriverStageOverlay: Equatable {

    /// Statuses the server stamps ready_to_go_at for (On My Way back-fills it).
    static let departureStatuses: Set<String> = ["On My Way", "Ready to Go"]
    static let arrivalStatus = "Arrived"

    struct Step: Equatable {
        let isArrival: Bool
        let capturedAt: Date
        /// When the server confirmed it; nil while it is not confirmed (pending, syncing, needs attention).
        let confirmedAt: Date?
    }

    /// "order product|leg" → its trip steps.
    private let steps: [String: [Step]]

    static func from(_ operations: [SyncOperation]) -> DriverStageOverlay {
        var steps: [String: [Step]] = [:]
        for op in operations where op.type == EffectiveFieldState.driverChecklistType
            && EffectiveFieldState.countsAsDurableEvidence(op.state) {
            guard let product = op.payload["order_product_unique_id"]?.stringValue, !product.isEmpty,
                  let leg = op.payload["checklist_type"]?.stringValue, !leg.isEmpty,
                  let status = op.payload["equipment_driver_status"]?.stringValue else { continue }
            let isArrival = status == arrivalStatus
            // A partial save carries answers only — it is no stage.
            guard isArrival || departureStatuses.contains(status) else { continue }
            steps[key(product, leg), default: []].append(
                Step(isArrival: isArrival, capturedAt: op.capturedAt,
                     confirmedAt: op.state == .synced ? op.acknowledgment?.acknowledgedAt : nil))
        }
        return DriverStageOverlay(steps: steps)
    }

    /// The stage for one order product + leg (`leg` = the driver checklist_type:
    /// "delivery" | "pickup"). The furthest of server truth and every local step the server
    /// has not yet been OBSERVED to supersede: a step stands while unconfirmed, and once
    /// confirmed only until a copy of the row asked for after that confirmation is shown
    /// (the office may have recalled the trip since). `serverObservedAt` = when the server
    /// was asked for the row shown; nil = unknown, so every local step stands.
    func effective(orderProductUniqueId: String, leg: String, server: DriverStageServerState,
                   serverObservedAt: Date?) -> DriverStageEffective {
        let serverReady = server.readyToGoAt.flatMap { $0.isEmpty ? nil : $0 }
        let serverArrived = server.arrivedAt.flatMap { $0.isEmpty ? nil : $0 }
        var stage: DriverTripStage = server.isArrived ? .arrived : (serverReady != nil ? .onMyWay : .notStarted)
        var readyToGoAt = serverReady
        var arrivedAt = server.isArrived ? serverArrived : nil

        let standing = (steps[Self.key(orderProductUniqueId, leg)] ?? []).filter { step in
            guard let confirmed = step.confirmedAt, let observed = serverObservedAt else { return true }
            return observed < confirmed
        }
        // Like the server: the first departure stamps ready_to_go_at, the latest Arrived wins.
        let departure = standing.filter { !$0.isArrival }.min { $0.capturedAt < $1.capturedAt }
        let arrival = standing.filter(\.isArrival).max { $0.capturedAt < $1.capturedAt }
        if arrival != nil {
            stage = max(stage, .arrived)
        } else if departure != nil {
            stage = max(stage, .onMyWay)
        }
        if stage >= .onMyWay, readyToGoAt == nil {
            readyToGoAt = (departure ?? arrival).map { Self.stamp($0.capturedAt) }
        }
        if stage == .arrived, arrivedAt == nil {
            arrivedAt = arrival.map { Self.stamp($0.capturedAt) }
        }
        return DriverStageEffective(stage: stage, readyToGoAt: readyToGoAt, arrivedAt: arrivedAt)
    }

    /// The row format ("yyyy-MM-dd HH:mm:ss", phone time zone) Screen 2 already stamps and parses.
    static func stamp(_ date: Date) -> String {
        stampFormatter.string(from: date)
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static func key(_ product: String, _ leg: String) -> String { "\(product)|\(leg)" }
}
