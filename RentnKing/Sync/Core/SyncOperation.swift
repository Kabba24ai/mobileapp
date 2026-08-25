//
//  SyncOperation.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The durable local representation of one state-changing field operation.
//  Stored as one JSON file per operation (FileSyncOperationStore). Designed so
//  later operation types (delivery/return checklist, signature, media,
//  driver's license, Queue Line commands) fit without schema changes: the
//  business identity is optional per field, the payload is an arbitrary JSON
//  object, and `assets` carries stable client_media_id + durable file refs.
//

import Foundation

/// The small, explicit sync state machine. There is deliberately NO
/// "failed after N retries → deleted" state.
enum SyncState: String, Codable, Equatable {
    /// Durably stored on the phone; Laravel has not acknowledged it yet.
    case pending
    /// A request for this operation is in flight right now.
    case syncing
    /// Laravel accepted and persisted it.
    case synced
    /// Laravel rejected it permanently (or a person must decide). Still stored.
    case needsAttention = "needs_attention"
}

/// Business keys an operation may relate to. Every field is optional — a
/// driver checklist step has an order product, a Queue Line command may only
/// have equipment, a driver's-license upload has an order.
struct SyncBusinessIdentity: Codable, Equatable {
    var orderUniqueId: String?
    var orderProductUniqueId: String?
    var equipmentUniqueId: String?
    var checklistExecutionId: String?
    var employeeId: String?

    init(orderUniqueId: String? = nil,
         orderProductUniqueId: String? = nil,
         equipmentUniqueId: String? = nil,
         checklistExecutionId: String? = nil,
         employeeId: String? = nil) {
        self.orderUniqueId = orderUniqueId
        self.orderProductUniqueId = orderProductUniqueId
        self.equipmentUniqueId = equipmentUniqueId
        self.checklistExecutionId = checklistExecutionId
        self.employeeId = employeeId
    }

    /// Short, non-sensitive summary for diagnostics.
    var summary: String {
        var parts: [String] = []
        if let o = orderUniqueId { parts.append("order \(o)") }
        if let p = orderProductUniqueId { parts.append("product \(p)") }
        if let e = equipmentUniqueId { parts.append("equipment \(e)") }
        if let c = checklistExecutionId { parts.append("checklist \(c)") }
        return parts.joined(separator: " · ")
    }
}

/// A local file that belongs to an operation (photo, video, signature, license
/// scan). `relativePath` is relative to the store's assets directory so the
/// record survives container path changes across app updates. Cleanup of the
/// file is only ever allowed after the server confirmed persistence.
struct SyncAsset: Codable, Equatable {
    /// Stable client-generated id sent to the server for duplicate-safe uploads.
    let clientMediaId: String
    let relativePath: String
    let mimeType: String
    /// Multipart field name the server expects (e.g. "media[]", "signature_media").
    let fieldName: String
    var byteCount: Int64?
    var sha256: String?
    /// Set when the server acknowledged THIS asset; local cleanup may follow.
    var acknowledgedAt: Date?

    init(clientMediaId: String = UUID().uuidString,
         relativePath: String,
         mimeType: String,
         fieldName: String,
         byteCount: Int64? = nil,
         sha256: String? = nil,
         acknowledgedAt: Date? = nil) {
        self.clientMediaId = clientMediaId
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.fieldName = fieldName
        self.byteCount = byteCount
        self.sha256 = sha256
        self.acknowledgedAt = acknowledgedAt
    }
}

/// Everything the engine learned from trying to sync the operation.
struct SyncAttemptRecord: Codable, Equatable {
    var attemptCount: Int = 0
    var lastAttemptedAt: Date?
    /// Backoff gate: the engine does not retry before this instant (nil = immediately).
    var nextAttemptAt: Date?
    var lastStatusCode: Int?
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var lastRequestId: String?
    var lastTransportFailure: TransportFailure?
    var lastDisposition: RetryDisposition?

    init() {}
}

/// The server's acknowledgment of the operation.
struct SyncAcknowledgment: Codable, Equatable {
    let acknowledgedAt: Date
    let statusCode: Int
    let requestId: String?
    /// True when Laravel replayed a stored acknowledgment (the first response was lost).
    let replayed: Bool
    let serverReceivedAt: Date?
    let data: JSONValue?
}

struct SyncOperation: Codable, Equatable, Identifiable {
    /// Schema version of this record; bump when a migration of stored files is needed.
    static let currentSchemaVersion = 1

    /// The client-generated idempotency key — generated ONCE at creation, never regenerated.
    let id: String
    var operationId: String { id }

    /// Stable type name, e.g. "driver_checklist.update".
    let type: String

    /// When the employee actually did the work (device clock).
    let capturedAt: Date
    /// When the operation was durably queued.
    let queuedAt: Date

    var identity: SyncBusinessIdentity
    /// The request payload as a JSON object (no secrets — the token is added at send time).
    var payload: JSONValue
    var assets: [SyncAsset]

    var state: SyncState
    var attempts: SyncAttemptRecord
    var acknowledgment: SyncAcknowledgment?
    /// Employee-facing summary when state == .needsAttention.
    var attentionReason: String?
    /// Non-sensitive label for lists ("Driver checklist · Ready to Go").
    var displayTitle: String?
    var schemaVersion: Int

    init(id: String = UUID().uuidString,
         type: String,
         capturedAt: Date,
         queuedAt: Date = Date(),
         identity: SyncBusinessIdentity = SyncBusinessIdentity(),
         payload: JSONValue,
         assets: [SyncAsset] = [],
         displayTitle: String? = nil) {
        self.id = id
        self.type = type
        self.capturedAt = capturedAt
        self.queuedAt = queuedAt
        self.identity = identity
        self.payload = payload
        self.assets = assets
        self.state = .pending
        self.attempts = SyncAttemptRecord()
        self.acknowledgment = nil
        self.attentionReason = nil
        self.displayTitle = displayTitle
        self.schemaVersion = SyncOperation.currentSchemaVersion
    }

    var isTerminal: Bool { state == .synced }
    var isEligibleForSync: Bool { state == .pending }

    /// The identity this operation shares ordering with (same order product, etc.).
    var orderingKey: String {
        identity.orderProductUniqueId
            ?? identity.orderUniqueId
            ?? identity.equipmentUniqueId
            ?? identity.checklistExecutionId
            ?? id
    }
}
