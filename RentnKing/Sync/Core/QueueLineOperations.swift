//
//  QueueLineOperations.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Phase 4 — Queue Line item-level orchestration.
//
//  The Queue Line ITEM is the order product. Laravel's board feed now carries an
//  explicit `identity` block (order product, order, equipment, store, fulfillment
//  leg, checklist execution) and a `checklist.delivery` state; the phone keeps
//  that identity together through Mark as Staged and into the Delivery Checklist
//  instead of re-deriving it from array position or the order alone.
//
//  Mark as Staged is a durable Sync Engine operation (`queue_line.mark_staged`):
//  one operation id generated at tap time, replayed by Laravel through the
//  mobile operation ledger, parked as Needs Attention on a 409 conflict with
//  newer server truth (assignment changed, item left the yard).
//

import Foundation

// MARK: - Wire contract (decodes the Laravel board item / acknowledgment)

/// The `identity` block on every board item and on the mark-staged acknowledgment.
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
    let fullyStaged: Bool
    let fulfillmentLeg: String
    let identity: QueueLineItemIdentity
    let checklist: Checklist
    let equipment: Equipment?

    enum CodingKeys: String, CodingKey {
        case orderProductUniqueId = "order_product_unique_id"
        case orderUniqueId = "order_unique_id"
        case orderNumber = "order_number"
        case status, staged
        case fullyStaged = "fully_staged"
        case fulfillmentLeg = "fulfillment_leg"
        case identity, checklist, equipment
    }

    static func decode(_ data: Data) throws -> QueueLineItemContract {
        try KabbaISO8601.makeDecoder().decode(QueueLineItemContract.self, from: data)
    }
}

/// The `data` of a mark-staged acknowledgment (success envelope).
struct QueueLineStageAcknowledgment: Codable, Equatable {
    let orderProductUniqueId: String
    let fullyStaged: Bool
    let replayed: Bool
    let status: String?
    let identity: QueueLineItemIdentity?
    let stagedAt: String?

    enum CodingKeys: String, CodingKey {
        case orderProductUniqueId = "order_product_unique_id"
        case fullyStaged = "fully_staged"
        case replayed, status, identity
        case stagedAt = "staged_at"
    }

    static func decode(envelopeData: Data) throws -> QueueLineStageAcknowledgment {
        struct Envelope: Decodable { let data: QueueLineStageAcknowledgment }
        return try KabbaISO8601.makeDecoder().decode(Envelope.self, from: envelopeData).data
    }
}

// MARK: - The employee command

/// What the employee did on the Mark as Staged sheet — for the CURRENTLY ASSIGNED
/// unit only. (Reassign + stage stays an online call: the switch itself is not an
/// idempotent operation yet, and a queued stage against a unit the server never
/// saw assigned would always be a conflict.)
struct QueueLineStageCommand: Equatable {
    var orderProductUniqueId: String
    var orderUniqueId: String
    var orderNumber: String
    var productName: String
    var equipmentUniqueId: String
    var equipmentName: String
    var performedByUniqueId: String
    var performedByName: String
    /// nil = the unit has no fuel trait (not applicable); the field is omitted.
    var fuelFull: Bool?
    /// nil = the unit has no key trait (not applicable); the field is omitted.
    var keyWithMachine: Bool?
    var capturedAt: Date = Date()

    /// Mirrors Laravel's readiness rules so an offline command can never be queued
    /// in a state the server is guaranteed to reject (QUEUE_FUEL_NOT_FULL / QUEUE_KEY_MISSING).
    func localValidationProblems() -> [String] {
        var problems: [String] = []
        if orderProductUniqueId.isEmpty { problems.append("Missing order item") }
        if equipmentUniqueId.isEmpty { problems.append("No equipment is assigned to this item") }
        if performedByUniqueId.isEmpty { problems.append("Select the employee who staged this machine") }
        if fuelFull == false { problems.append("Fill the machine, then mark it as staged") }
        if keyWithMachine == false { problems.append("Locate the key and leave it with the machine, then mark it as staged") }
        return problems
    }
}

enum QueueLineOperationBuilder {

    static let markStagedType = "queue_line.mark_staged"

    static func payload(_ command: QueueLineStageCommand) -> JSONValue {
        var body: [String: JSONValue] = [
            "order_product_unique_id": .string(command.orderProductUniqueId),
            "order_unique_id": .string(command.orderUniqueId),
            "equipment_unique_id": .string(command.equipmentUniqueId),
            "performed_by": .string(command.performedByUniqueId),
        ]
        if let fuel = command.fuelFull { body["fuel_full"] = .bool(fuel) }
        if let key = command.keyWithMachine { body["key_with_machine"] = .bool(key) }
        return .object(body)
    }

    static func identity(_ command: QueueLineStageCommand) -> SyncBusinessIdentity {
        SyncBusinessIdentity(orderUniqueId: command.orderUniqueId,
                             orderProductUniqueId: command.orderProductUniqueId,
                             equipmentUniqueId: command.equipmentUniqueId,
                             employeeId: command.performedByUniqueId)
    }

    /// Non-sensitive: order number + product + unit code. Never the customer.
    static func displayTitle(_ command: QueueLineStageCommand) -> String {
        var parts = ["Mark as Staged"]
        if !command.orderNumber.isEmpty { parts.append("#\(command.orderNumber)") }
        if !command.productName.isEmpty { parts.append(command.productName) }
        if !command.equipmentName.isEmpty { parts.append(command.equipmentName) }
        return parts.joined(separator: " · ")
    }

    /// Durably records the staging command. Returns after it is on disk.
    @discardableResult
    static func enqueueMarkStaged(_ command: QueueLineStageCommand,
                                  into engine: SyncEngine,
                                  operationId: String = UUID().uuidString) throws -> SyncOperation {
        try engine.enqueue(type: markStagedType,
                           payload: payload(command),
                           identity: identity(command),
                           capturedAt: command.capturedAt,
                           displayTitle: displayTitle(command),
                           operationId: operationId)
    }
}

enum QueueLineRequestFactory {
    static func markStagedRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard var body = operation.payload.objectValue,
              let productId = body["order_product_unique_id"]?.stringValue, !productId.isEmpty,
              body["equipment_unique_id"]?.stringValue?.isEmpty == false,
              body["performed_by"]?.stringValue?.isEmpty == false else {
            throw SyncHandlerError.invalidPayload("Mark as Staged command is missing its item, unit or employee")
        }
        // The operation id is also the fuel/key ledger token, so every server-side row
        // written for this command carries the same identity as the operation itself.
        body["operation_id"] = .string(operation.id)
        body["idempotency_token"] = .string(operation.id)
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))
        body["order_product_unique_id"] = nil
        body["order_unique_id"] = nil
        return SyncHTTPRequest(method: "POST",
                               path: "queue-line/\(productId)/mark-staged",
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id)
    }
}

// MARK: - Local display state

/// What the Queue Line board overlays on top of the cached/server items: which
/// products have a staging command still on the phone (Pending Sync) and which
/// were rejected (Sync Issue). Pure function of the engine snapshot.
struct QueueLineLocalOverlay: Equatable {
    /// order product → the pending/syncing operation id
    var pendingStage: [String: String] = [:]
    /// order product → the employee-facing reason
    var attention: [String: String] = [:]

    func isPendingStage(_ orderProductUniqueId: String) -> Bool { pendingStage[orderProductUniqueId] != nil }
    func attentionReason(_ orderProductUniqueId: String) -> String? { attention[orderProductUniqueId] }

    static func from(_ operations: [SyncOperation]) -> QueueLineLocalOverlay {
        var overlay = QueueLineLocalOverlay()
        for op in operations where op.type == QueueLineOperationBuilder.markStagedType {
            guard let product = op.identity.orderProductUniqueId else { continue }
            switch op.state {
            case .pending, .syncing:
                overlay.pendingStage[product] = op.id
            case .needsAttention:
                overlay.attention[product] = op.attentionReason ?? "Staging was not accepted by Kabba."
            case .synced:
                break
            }
        }
        // A newer pending command supersedes an older rejection for the same product.
        for product in overlay.pendingStage.keys { overlay.attention[product] = nil }
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
