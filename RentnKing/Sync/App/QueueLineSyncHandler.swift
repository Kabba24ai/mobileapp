//
//  QueueLineSyncHandler.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Phase 4 — offline Mark as Staged. The Queue Line screen enqueues ONE durable
//  `queue_line.mark_staged` operation per tap; this handler turns it into the
//  idempotent POST queue-line/{order_product}/mark-staged. A 409 (assignment
//  changed, item left the yard) parks it as Needs Attention; the board overlays
//  Pending Sync / Sync Issue from the engine snapshot and never pretends the
//  server has confirmed anything.
//

import Foundation

struct QueueLineStageSyncHandler: SyncOperationHandler {
    let hasSession: () -> Bool

    var operationType: String { QueueLineOperationBuilder.markStagedType }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        return try QueueLineRequestFactory.markStagedRequest(for: operation)
    }
}

/// Screen-facing helpers over the engine for the Queue Line board.
enum KabbaQueueLineSync {

    private static let lastServerSyncKey = "kQueueLineLastServerSyncAt"
    private static let lastRefreshFailedKey = "kQueueLineLastRefreshFailed"

    /// Durably records the staging command. Throws when the engine is unavailable.
    @discardableResult
    static func enqueueMarkStaged(_ command: QueueLineStageCommand) throws -> SyncOperation {
        guard let engine = KabbaSync.engine else {
            throw SyncHandlerError.invalidPayload("Offline staging is unavailable on this device")
        }
        return try QueueLineOperationBuilder.enqueueMarkStaged(command, into: engine)
    }

    /// Pending Sync / Sync Issue per order product, from the engine snapshot.
    static func overlay() -> QueueLineLocalOverlay {
        guard let engine = KabbaSync.engine else { return QueueLineLocalOverlay() }
        return QueueLineLocalOverlay.from(engine.snapshot())
    }

    // MARK: Board freshness (server-confirmed vs cached vs pending)

    static func recordServerRefresh(succeeded: Bool, now: Date = Date()) {
        let defaults = UserDefaults.standard
        if succeeded { defaults.set(now.timeIntervalSince1970, forKey: lastServerSyncKey) }
        defaults.set(!succeeded, forKey: lastRefreshFailedKey)
    }

    static var lastServerSyncAt: Date? {
        let raw = UserDefaults.standard.double(forKey: lastServerSyncKey)
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }

    static var lastRefreshFailed: Bool { UserDefaults.standard.bool(forKey: lastRefreshFailedKey) }

    static func freshnessLine(pendingCount: Int) -> String {
        QueueLineFreshness.line(lastServerSyncAt: lastServerSyncAt, lastRefreshFailed: lastRefreshFailed, pendingCount: pendingCount)
    }
}
