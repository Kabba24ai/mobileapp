//
//  ChecklistContextFallbackPolicy.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Dispatch offline Phase 4 (P4-D4, review gaps G-A–G-D): whether a CACHED
//  checklist context may be served when the server cannot be reached.
//
//  A cached context names one execution (cycle) and one unit. After this phone
//  durably substituted the unit or restarted the checklist, that context is
//  the REPLACED cycle — serving it would put the old unit's questions and
//  execution id back on screen (and later prepares would target a superseded
//  execution). The replacement's canonical context only exists on the server,
//  so offline it is "needs a connection" instead.
//
//  A context with no unit (an unassigned delivery, `assignment: none`) is never
//  served offline either: choosing its unit needs the server's `selected` path.
//

import Foundation

enum ChecklistContextFallbackPolicy {

    /// - Parameters:
    ///   - equipmentHint: the unit the screen asks for.
    ///   - strictUnit: true when the hint comes from a local action (a substitution or
    ///     restart just recorded): the cached unit must then match it. False keeps today's
    ///     rule for an ordinary open — the context's own unit is authoritative.
    static func canServeOffline(_ cached: ChecklistContext,
                                equipmentHint: String?,
                                strictUnit: Bool,
                                operations: [SyncOperation]) -> Bool {
        guard cached.equipment.hasUnit else { return false }
        if EffectiveFieldState.supersededExecutionIds(in: operations).contains(cached.executionId) { return false }
        if strictUnit, let hint = equipmentHint, !hint.isEmpty, cached.equipment.equipmentUniqueId != hint { return false }
        if let discardedAt = EffectiveFieldState.lastDiscardAt(in: operations, orderProductUniqueId: cached.identity.orderProductUniqueId),
           discardedAt > (cached.cachedAt ?? .distantPast) {
            return false
        }
        return true
    }
}
