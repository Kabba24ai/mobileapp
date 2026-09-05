//
//  QueueLineOperations.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Checklist-driven Queue Line (2026-09).
//
//  The Queue Line ITEM is the order product. Laravel's board feed carries an
//  explicit `identity` block (order product, order, equipment, store,
//  fulfillment leg, checklist execution) and a `checklist.delivery` state; the
//  phone keeps that identity together into the Delivery Checklist instead of
//  re-deriving it from array position or the order alone.
//
//  There is NO Queue Line-specific staging operation any more. The Delivery
//  Checklist is the canonical preparation controller:
//
//      delivery_checklist.prepare  + mark_staged  → Pending → Staged
//      delivery_checklist.complete (signed)       → Delivered
//
//  Those durable checklist operations are ALSO the board's local-first
//  evidence: QueueLineLocalOverlay reads the engine snapshot and moves cards
//  between lanes immediately, before Laravel confirms. The retired
//  queue_line.mark_staged path (fuel/key mini-checklist) was removed with its
//  endpoints — the fleet updates as one, so no compatibility shim exists.
//

import Foundation

// MARK: - Wire contract (decodes the Laravel board item)

/// The `identity` block on every board item.
struct QueueLineItemIdentity: Codable, Equatable {
    let queueLineItemId: String
    let orderUniqueId: String
    let orderProductUniqueId: String
    let equipmentUniqueId: String?
    let storeUniqueId: String?
    let fulfillmentLeg: String
    let checklistExecutionId: String?

    enum CodingKeys: String, CodingKey {
        case queueLineItemId = "queue_line_item_id"
        case orderUniqueId = "order_unique_id"
        case orderProductUniqueId = "order_product_unique_id"
        case equipmentUniqueId = "equipment_unique_id"
        case storeUniqueId = "store_unique_id"
        case fulfillmentLeg = "fulfillment_leg"
        case checklistExecutionId = "checklist_execution_id"
    }

    var leg: ChecklistLeg { ChecklistLeg(rawValue: fulfillmentLeg) ?? .delivery }
}

/// `checklist.delivery` on a board item: not_prepared | prepared | completed.
struct QueueLineChecklistState: Codable, Equatable {
    enum Status: String, Codable, Equatable {
        case notPrepared = "not_prepared"
        case prepared
        case completed
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    let leg: String
    let checklistExecutionId: String?
    let status: Status
    let preparedAt: String?
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case leg
        case checklistExecutionId = "checklist_execution_id"
        case status
        case preparedAt = "prepared_at"
        case completedAt = "completed_at"
    }
}

/// The parts of a Queue Line board item the sync layer cares about. The full UI
/// model lives in the app (ObjectMapper); this Codable view exists so the shared
/// contract fixtures are decoded by the same test suite that covers the engine.
struct QueueLineItemContract: Codable, Equatable {
    struct Equipment: Codable, Equatable {
        let uniqueId: String?
        let displayId: String?
        let name: String?
        let isFuel: Bool?
        let isKey: Bool?

        enum CodingKeys: String, CodingKey {
            case uniqueId = "unique_id", displayId = "display_id", name, isFuel = "is_fuel", isKey = "is_key"
        }
    }

    struct Checklist: Codable, Equatable {
        let delivery: QueueLineChecklistState
    }

    let orderProductUniqueId: String
    let orderUniqueId: String
    let orderNumber: String
    let status: String
    let staged: Bool
    /// Derived from the canonical dispatch On My Way state — prepared
    /// equipment currently traveling to the customer (checklist-driven Queue
    /// Line, 2026-09). Operational badge only; gates nothing.
    let inTransit: Bool
    let readiness: String?
    let fulfillmentLeg: String
    let identity: QueueLineItemIdentity
    let checklist: Checklist
    let equipment: Equipment?

    enum CodingKeys: String, CodingKey {
        case orderProductUniqueId = "order_product_unique_id"
        case orderUniqueId = "order_unique_id"
        case orderNumber = "order_number"
        case status, staged, readiness
        case inTransit = "in_transit"
        case fulfillmentLeg = "fulfillment_leg"
        case identity, checklist, equipment
    }

    static func decode(_ data: Data) throws -> QueueLineItemContract {
        try KabbaISO8601.makeDecoder().decode(QueueLineItemContract.self, from: data)
    }
}

// MARK: - Local display state

/// What the Queue Line board overlays on top of the cached/server items —
/// a pure function of the engine snapshot, built from the SAME durable
/// checklist operations the Delivery Checklist writes:
///
///   • stagedLocally    — a complete checklist Save (prepare + mark_staged) is
///                        durably on this phone → the card belongs in the
///                        Staged lane NOW, whatever the cached feed says.
///   • completedLocally — a signed completion is durably on this phone → the
///                        card belongs in the Completed lane NOW, and a stale
///                        feed replace can never reinsert it into Pending.
///   • inTransitLocally — this phone durably recorded the delivery driver
///                        status On My Way for the product.
///   • pendingSync      — the staging Save has not been server-acknowledged
///                        yet ("Pending Sync" chip).
///   • attention        — a staging Save was terminally rejected ("Sync
///                        Issue" chip; the office resolves it on Manage
///                        Schedule Conflicts).
struct QueueLineLocalOverlay: Equatable {
    /// order product → the pending/syncing staging-save operation id
    var pendingStage: [String: String] = [:]
    /// order product → the employee-facing reason
    var attention: [String: String] = [:]
    /// Durable staging evidence (any retained state — incl. synced/attention).
    var stagedLocally: Set<String> = []
    /// Durable signed-completion evidence for the delivery leg.
    var completedLocally: Set<String> = []
    /// Durable local On My Way evidence for the delivery leg.
    var inTransitLocally: Set<String> = []

    func isPendingStage(_ orderProductUniqueId: String) -> Bool { pendingStage[orderProductUniqueId] != nil }
    func attentionReason(_ orderProductUniqueId: String) -> String? { attention[orderProductUniqueId] }
    func isStagedLocally(_ orderProductUniqueId: String) -> Bool { stagedLocally.contains(orderProductUniqueId) }
    func isCompletedLocally(_ orderProductUniqueId: String) -> Bool { completedLocally.contains(orderProductUniqueId) }
    func isInTransitLocally(_ orderProductUniqueId: String) -> Bool { inTransitLocally.contains(orderProductUniqueId) }

    static func from(_ operations: [SyncOperation]) -> QueueLineLocalOverlay {
        var overlay = QueueLineLocalOverlay()

        // Capture order matters: a substitution / restart DISCARDS the staging
        // evidence recorded before it, and a later Save re-earns it. Replaying
        // the operations in the order the operator created them is what makes
        // "Staged Unit A → switch → Pending → Save → Staged Unit B" come out
        // right locally, before Laravel has confirmed anything.
        for op in operations.sorted(by: { $0.queuedAt < $1.queuedAt }) {
            guard let product = op.identity.orderProductUniqueId,
                  EffectiveFieldState.countsAsDurableEvidence(op.state) else { continue }

            if EffectiveFieldState.preparationDiscardTypes.contains(op.type) {
                // The preparation this card was staged on no longer exists.
                overlay.stagedLocally.remove(product)
                overlay.pendingStage[product] = nil
                overlay.attention[product] = nil
                continue
            }

            switch op.type {
            case EffectiveFieldState.deliveryPrepareType:
                // Only the explicit Save (staging intent) moves lanes; a
                // partial progress sync is invisible to lane membership.
                guard op.payload["mark_staged"]?.boolValue == true else { continue }
                overlay.stagedLocally.insert(product)
                switch op.state {
                case .pending, .syncing:
                    overlay.pendingStage[product] = op.id
                case .needsAttention:
                    overlay.attention[product] = op.attentionReason ?? "The staging Save was not accepted by Kabba."
                case .synced:
                    break
                }

            case EffectiveFieldState.deliveryCompleteType:
                overlay.completedLocally.insert(product)

            case EffectiveFieldState.driverChecklistType:
                if op.payload["checklist_type"]?.stringValue == "delivery",
                   op.payload["equipment_driver_status"]?.stringValue == "On My Way" {
                    overlay.inTransitLocally.insert(product)
                }

            default:
                break
            }
        }

        // A newer pending Save supersedes an older rejection for the same product.
        for product in overlay.pendingStage.keys { overlay.attention[product] = nil }
        // A completed item is past staging chatter entirely.
        for product in overlay.completedLocally {
            overlay.pendingStage[product] = nil
            overlay.attention[product] = nil
            overlay.inTransitLocally.remove(product)
        }
        return overlay
    }
}

/// Wording for the board's freshness line — the employee can always tell server-
/// confirmed data from a cached list and from local pending changes.
enum QueueLineFreshness {
    static func line(lastServerSyncAt: Date?, lastRefreshFailed: Bool, pendingCount: Int, now: Date = Date()) -> String {
        var text: String
        if let last = lastServerSyncAt {
            let age = now.timeIntervalSince(last)
            let stamp = QueueLineFreshness.clock(last)
            if lastRefreshFailed {
                text = "Offline · showing the list saved at \(stamp)"
            } else if age < 60 {
                text = "Updated just now"
            } else if age < 3600 {
                text = "Updated \(Int(age / 60)) min ago"
            } else {
                text = "Updated at \(stamp)"
            }
        } else {
            text = lastRefreshFailed ? "Offline · no saved list yet" : "Loading…"
        }
        if pendingCount > 0 {
            text += " · \(pendingCount) change\(pendingCount == 1 ? "" : "s") pending sync"
        }
        return text
    }

    private static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
