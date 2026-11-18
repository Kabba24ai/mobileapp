//
//  DispatchOfflineReferenceWarmup.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Dispatch offline mission cache — Phase 4 (P4-D6). The reference lists the
//  offline equipment checklist and Order Details read (employees, drivers,
//  equipment, stores, categories, prices + product settings, users) are
//  refreshed through their EXISTING endpoints after a reconciliation that
//  just reached the server on launch, login, foreground or network restored —
//  never on a wake, a Dispatch open, a manual refresh or a timer — and only a
//  list that is empty or was last refreshed more than 12 hours ago. The
//  per-list stamp lives beside the list, scoped to the company like the list
//  itself (Amendment B).
//

import Foundation

enum DispatchOfflineReferenceWarmup {

    enum List: String, CaseIterable, Equatable {
        case employees, drivers, equipment, stores, categories, prices, users
    }

    static let maxAge: TimeInterval = 12 * 60 * 60

    /// The trigger is one of the four listed, and the run just reached the server.
    static func runs(after trigger: DispatchOfflineTrigger, result: DispatchOfflineReconcileResult) -> Bool {
        switch trigger {
        case .launch, .loginCompleted, .foreground, .networkRestored: break
        case .wake, .dispatchScreenOpened, .manualRefresh: return false
        }
        switch result.status {
        case .completed, .partial, .skipped(.fresh), .skipped(.alreadyCurrent): return true
        case .failed, .skipped(.noSession), .skipped(.coolingDown): return false
        }
    }

    /// Empty, never refreshed for this company, older than 12 h, or stamped in the future.
    static func isDue(isEmpty: Bool, lastWarmedAt: Date?, now: Date) -> Bool {
        guard !isEmpty, let last = lastWarmedAt, last <= now else { return true }
        return now.timeIntervalSince(last) > maxAge
    }

    /// The unscoped stamp key (company-scoped by DispatchOfflineTenantStorage, prefix kReferenceWarmedAt_).
    static func stampKey(_ list: List) -> String { "kReferenceWarmedAt_\(list.rawValue)" }
}
