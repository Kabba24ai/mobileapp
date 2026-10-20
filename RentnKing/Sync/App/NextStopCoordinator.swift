//
//  NextStopCoordinator.swift
//  RentnKing — Sync App layer
//
//  The app's one way in to the durable shop stop. Deliberately tiny: it holds
//  the store KabbaSync built and forwards four calls. It is NOT a second sync
//  engine — it makes no network request and schedules no background work.
//  Since 2026-10-20 it also hands each Next Stop answer to the canonical Sync
//  Engine (record), which owns delivery, retries and idempotency.
//
//  Reads are forgiving (no store configured, or signed out, means `.idle`) so a
//  screen can always ask "is there a shop stop?" without guarding. Writes
//  propagate their error, because the caller has to know the shop reached disk
//  before it opens Maps.
//

import Foundation

enum NextStopCoordinator {

    private(set) static var store: NextStopStore?

    static func configure(store: NextStopStore) {
        NextStopCoordinator.store = store
    }

    /// The signed-in company's shop stop, or `.idle`.
    static func state() -> NextStopState {
        return store?.load() ?? .idle
    }

    /// Persists the shop stop. Throws when there is no store or nobody signed
    /// in — never silently drops the driver's choice.
    static func save(_ state: NextStopState) throws {
        guard let store = store else { throw NextStopStoreError.noTenant }
        try store.save(state)
    }

    /// Ends the shop stop.
    static func clear() throws {
        guard let store = store else { throw NextStopStoreError.noTenant }
        try store.clear()
    }

    /// Best-effort end of the shop stop, for paths where the driver is already
    /// moving on and a failed delete must not block them.
    static func clearIgnoringFailure() {
        try? clear()
    }

    /// Records one Next Stop answer as a durable next_stop.event operation for
    /// the Sync Engine to deliver (2026-10-20). Route evidence only: a failure
    /// to record it never blocks the driver, who is already moving on — the
    /// report then shows that trip's start as not recorded.
    static func record(_ event: NextStopRouteEvent?) {
        guard let event = event, let engine = KabbaSync.engine else { return }
        let employeeId = Int(UserDefaults.standard.user?.id ?? "")
        _ = try? NextStopRouteEventOperation.enqueue(into: engine, event: event, employeeId: employeeId)
    }
}
