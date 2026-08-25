//
//  SyncRetryPolicy.swift
//  RentnKing — Sync Core (Foundation only)
//

import Foundation

struct SyncRetryPolicy: Equatable {
    /// Delay before the next automatic attempt after the Nth failed attempt (capped at the last entry).
    /// Retryable failures NEVER exhaust — the schedule only slows them down.
    var backoffSchedule: [TimeInterval] = [30, 60, 120, 300, 900]

    /// A record found in `.syncing` at launch older than this was interrupted mid-request
    /// (app killed); it is reset to `.pending`. Idempotency makes the re-send safe.
    var staleSyncingTimeout: TimeInterval = 180

    /// How long acknowledged operations stay on disk for diagnostics before pruning.
    var syncedRetention: TimeInterval = 7 * 24 * 60 * 60

    static let `default` = SyncRetryPolicy()

    init() {}

    init(backoffSchedule: [TimeInterval], staleSyncingTimeout: TimeInterval = 180, syncedRetention: TimeInterval = 7 * 24 * 60 * 60) {
        self.backoffSchedule = backoffSchedule
        self.staleSyncingTimeout = staleSyncingTimeout
        self.syncedRetention = syncedRetention
    }

    /// `attempt` is the number of attempts made so far (>= 1).
    func delay(afterAttempt attempt: Int) -> TimeInterval {
        guard !backoffSchedule.isEmpty else { return 60 }
        let index = max(0, min(attempt - 1, backoffSchedule.count - 1))
        return backoffSchedule[index]
    }
}
