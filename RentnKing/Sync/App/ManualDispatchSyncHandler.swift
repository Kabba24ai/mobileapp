//
//  ManualDispatchSyncHandler.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Dispatch parity (Phase 6A): a Manual Dispatch status transition
//  (Assigned → On My Way → Arrived → Completed, or Cancelled) submitted to
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
