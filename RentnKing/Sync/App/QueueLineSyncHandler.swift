//
//  QueueLineSyncHandler.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Checklist-driven Queue Line (2026-09). The former queue_line.mark_staged
//  operation/handler (fuel/key mini-checklist) is retired: staging is now the
//  Delivery Checklist's explicit Save (delivery_checklist.prepare with
//  mark_staged), handled by ChecklistPrepareSyncHandler. What remains here are
//  the screen-facing helpers the board uses: the local-first overlay built
//  from the durable CHECKLIST operations, and the freshness line.
//

import Foundation

/// Screen-facing helpers over the engine for the Queue Line board.
enum KabbaQueueLineSync {

    private static let lastServerSyncKey = "kQueueLineLastServerSyncAt"
    private static let lastRefreshFailedKey = "kQueueLineLastRefreshFailed"

    /// Lane + chip overlay per order product, from the engine snapshot:
    /// staged/completed/in-transit local evidence, Pending Sync, Sync Issue.
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
