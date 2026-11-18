//
//  NextStopRouteEventSyncHandler.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Next Stop route events (2026-10-20): submits one driver answer from the
//  Next Stop screen (next mission / Return to Shop / Arrived at <shop>) to
//  POST dispatch/next-stop/events through the canonical Sync Engine — durable
//  local operation, operation id, idempotent server handling (operation type
//  next_stop.event), Pending Sync / Synced / Needs Attention. The request
//  shape lives in Core (NextStopRouteEventOperation) so it is unit-testable.
//
//  Requires the matching Kabba backend (the route ships with Driver
//  Efficiency): DEPLOY THE BACKEND FIRST. A server without the route answers
//  404 and the answers park as Needs Attention — preserved on the phone, and
//  never blocking any other work.
//

import Foundation

struct NextStopRouteEventSyncHandler: SyncOperationHandler {

    /// Whether a session exists (token + base URL). When false the engine pauses for authentication.
    let hasSession: () -> Bool

    init(hasSession: @escaping () -> Bool) {
        self.hasSession = hasSession
    }

    var operationType: String { NextStopRouteEventOperation.operationType }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        return try NextStopRouteEventOperation.request(for: operation)
    }
}
