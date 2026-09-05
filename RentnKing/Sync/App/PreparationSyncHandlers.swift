//
//  PreparationSyncHandlers.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Pre-departure preparation lifecycle (2026-09):
//
//    queue_line.switch_equipment    → POST queue-line/{order_product}/switch-equipment
//    delivery_checklist.reset       → POST orders/checklists/{execution}/reset
//    return_checklist.reset         → (same shape; the return leg has no queue
//                                      semantics but shares the contract)
//
//  Both are thin: the canonical reassignment and supersession rules live in
//  Laravel (EquipmentReassignmentService / ChecklistPreparationReset), and the
//  phone only records the operator's decision durably and in order. Because
//  both carry the order product as their business identity, the engine's
//  per-orderingKey FIFO guarantees the substitution reaches Laravel BEFORE any
//  prepare for the replacement unit — the dependency this workflow needs.
//

import Foundation

struct EquipmentSubstitutionSyncHandler: SyncOperationHandler {
    let hasSession: () -> Bool

    var operationType: String { PreparationOperationBuilder.substitutionType }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        return try PreparationRequestFactory.substitutionRequest(for: operation)
    }
}

struct ChecklistRestartSyncHandler: SyncOperationHandler {
    let leg: ChecklistLeg
    let hasSession: () -> Bool

    var operationType: String { PreparationOperationBuilder.restartType(leg) }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        return try PreparationRequestFactory.restartRequest(for: operation)
    }
}
