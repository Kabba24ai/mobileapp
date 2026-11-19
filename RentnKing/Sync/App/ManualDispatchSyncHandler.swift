//
//  ManualDispatchSyncHandler.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Dispatch parity (Phase 6A): a Manual Dispatch status transition
//  (Assigned → On My Way → Arrived → Completed, or Cancelled), with the
//  driver's tap time as captured_at (2026-10-20), submitted to
//  POST dispatch/manual/update-status through the canonical Sync Engine —
//  durable local operation, operation id, idempotent server handling
//  (operation type manual_dispatch.update_status), Pending Sync / Synced /
//  Needs Attention. No ad-hoc networking, no second retry system.
//
//  Conflict semantics: a task reassigned away on the web answers 403 (and an
//  order-leg action answers 409 DISPATCH_ASSIGNMENT_CHANGED) — both
//  non-retryable, so the engine parks the operation as Needs Attention with
//  the captured work intact and the next feed refresh drops the card.
//

import Foundation

struct ManualDispatchSyncHandler: SyncOperationHandler {

    static let operationType = DispatchManualStatus.statusOperationType
    static let path = "dispatch/manual/update-status"

    /// Whether a session exists (token + base URL). When false the engine pauses for authentication.
    let hasSession: () -> Bool

    init(hasSession: @escaping () -> Bool) {
        self.hasSession = hasSession
    }

    var operationType: String { ManualDispatchSyncHandler.operationType }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        guard var body = operation.payload.objectValue,
              body["manual_dispatch_task_unique_id"]?.stringValue?.isEmpty == false,
              body["status"]?.stringValue?.isEmpty == false else {
            throw SyncHandlerError.invalidPayload("Manual dispatch payload is missing its task id or status")
        }

        body["operation_id"] = .string(operation.id)
        // The moment the driver tapped (2026-10-20). The server keeps it on the
        // operation record only — the task's own stamps stay server time — so
        // Driver Efficiency can measure a task synchronized late on the phone's
        // clock. Older servers ignore the field.
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))

        return SyncHTTPRequest(method: "POST",
                               path: ManualDispatchSyncHandler.path,
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id)
    }

    /// Builds and durably enqueues one status transition. Returns after the record is on disk.
    @discardableResult
    static func enqueue(into engine: SyncEngine,
                        taskUniqueId: String,
                        status: String,
                        capturedAt: Date = Date(),
                        operationId: String = UUID().uuidString) throws -> SyncOperation {
        return try engine.enqueue(type: operationType,
                                  payload: .object([
                                      "manual_dispatch_task_unique_id": .string(taskUniqueId),
                                      "status": .string(status),
                                  ]),
                                  identity: SyncBusinessIdentity(manualTaskUniqueId: taskUniqueId),
                                  capturedAt: capturedAt,
                                  displayTitle: "Manual dispatch · \(status)",
                                  operationId: operationId)
    }
}

/// One item of a Manual Dispatch task confirmed picked up / delivered
/// (2026-11: several items on one task, and combined dispatches). Submitted to
/// POST dispatch/manual/item-progress through the same Sync Engine as a
/// status transition — durable local operation, operation id, idempotent
/// server handling (manual_dispatch.item_progress). It moves ONLY that item's
/// own state: never the task's status, never a sibling item.
struct ManualDispatchItemProgressSyncHandler: SyncOperationHandler {

    static let operationType = DispatchManualItemProgress.operationType
    static let path = "dispatch/manual/item-progress"

    let hasSession: () -> Bool

    init(hasSession: @escaping () -> Bool) {
        self.hasSession = hasSession
    }

    var operationType: String { ManualDispatchItemProgressSyncHandler.operationType }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        guard var body = operation.payload.objectValue,
              body["manual_dispatch_task_unique_id"]?.stringValue?.isEmpty == false,
              case .number? = body["item_id"] else {
            throw SyncHandlerError.invalidPayload("Manual dispatch item payload is missing its task or item id")
        }

        body["operation_id"] = .string(operation.id)

        return SyncHTTPRequest(method: "POST",
                               path: ManualDispatchItemProgressSyncHandler.path,
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id)
    }

    /// Builds and durably enqueues one item confirmation. Returns after the record is on disk.
    @discardableResult
    static func enqueue(into engine: SyncEngine,
                        taskUniqueId: String,
                        itemId: Int,
                        itemLabel: String,
                        step: DispatchManualItemProgress.NextStep,
                        capturedAt: Date = Date(),
                        operationId: String = UUID().uuidString) throws -> SyncOperation {
        let key = step == .deliver ? "delivered" : "picked_up"
        return try engine.enqueue(type: operationType,
                                  payload: .object([
                                      "manual_dispatch_task_unique_id": .string(taskUniqueId),
                                      "item_id": .number(Double(itemId)),
                                      key: .bool(true),
                                  ]),
                                  identity: SyncBusinessIdentity(manualTaskUniqueId: taskUniqueId),
                                  capturedAt: capturedAt,
                                  displayTitle: "\(itemLabel) · \(step == .deliver ? "Delivered" : "Picked up")",
                                  operationId: operationId)
    }
}
