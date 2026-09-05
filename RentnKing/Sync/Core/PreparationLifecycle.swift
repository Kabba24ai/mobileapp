//
//  PreparationLifecycle.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Pre-departure preparation lifecycle (2026-09).
//
//  The computer-assigned Equipment ID is a DEFAULT, not a pre-departure lock.
//  While the machine is still in the yard the operator may substitute another
//  eligible unit, or discard a saved-but-not-delivered checklist and start
//  over — both directly from the canonical Delivery Checklist, which is now the
//  preparation workbench for every entry point.
//
//  Both corrections are the SAME business event: the prepared checklist
//  certifies a PHYSICAL machine, so discarding the machine discards the
//  certification. Laravel expresses that by superseding the checklist EXECUTION
//  and minting the next cycle; this file is the phone's side of that contract:
//
//    • PreparationPolicy   — may the operator substitute / restart right now,
//                            and does it need a confirmation? Pure function of
//                            the context + what is locally entered.
//    • PreparationOperationBuilder — the two durable Sync Engine operations.
//
//  Ordering is free: both operations carry the order product as their business
//  identity, and SyncOperation.orderingKey makes the engine send everything for
//  one order product strictly in capture order. A prepare for the replacement
//  unit can therefore never overtake the substitution that created its cycle.
//

import Foundation

// MARK: - Policy

enum PreparationLifecycle {

    /// Why a substitution / restart is not available right now.
    enum Block: Equatable {
        /// On My Way — the machine physically left the yard.
        case inTransit
        /// The leg is delivered; the checklist is permanent operational evidence.
        case delivered

        /// The employee-facing sentence. Mirrors the server's refusal so the
        /// phone and Laravel never tell the operator two different stories.
        var message: String {
            switch self {
            case .inTransit:
                return "This equipment is already on its way to the customer. Changing the unit or restarting the checklist is no longer a yard decision — Dispatch or the office has to handle it."
            case .delivered:
                return "This delivery is complete. Its checklist is permanent record and can't be restarted here."
            }
        }
    }

    /// What the operator must confirm before the preparation is discarded.
    enum Confirmation: Equatable {
        /// Nothing meaningful would be lost — just do it.
        case none
        /// Answers were entered against the outgoing unit but never saved.
        case discardPartial
        /// A complete checklist was Saved (prepared / Staged).
        case discardPrepared
    }
}

/// The rules that decide whether the yard may still change its mind. Pure, so
/// the checklist screen never re-implements them and the tests can pin them.
enum PreparationPolicy {

    /// Substituting a unit and restarting a checklist share one cutoff: the
    /// machine must still be in the yard, and the leg must not be delivered.
    static func block(for context: ChecklistContext) -> PreparationLifecycle.Block? {
        // Delivery is the Queue Line's unit of work; the return leg has no
        // pre-departure phase to protect.
        guard context.leg.isDelivery else { return nil }

        if context.isCompleted || context.serverState.isDelivered { return .delivered }
        if context.serverState.inTransit == true { return .inTransit }
        return nil
    }

    /// May the operator open the equipment picker for this product? An
    /// office-assigned unit is the PRESELECTED default, never a lock —
    /// substituting before departure is routine yard work.
    static func maySubstituteEquipment(_ context: ChecklistContext) -> Bool {
        block(for: context) == nil
    }

    /// May "Delete Checklist / Start Over" be offered? Only when there is a
    /// non-final preparation to discard — a blank, never-touched checklist has
    /// nothing to restart.
    static func mayRestartChecklist(_ context: ChecklistContext, hasLocalAnswers: Bool) -> Bool {
        guard block(for: context) == nil else { return false }
        return hasPreparationToDiscard(context, hasLocalAnswers: hasLocalAnswers)
    }

    /// Is there preparation work that a reset/substitution would throw away?
    /// Server-side prepared answers, a `prepared` execution, a staged Queue Line
    /// item, or answers the operator has entered on this screen.
    static func hasPreparationToDiscard(_ context: ChecklistContext, hasLocalAnswers: Bool) -> Bool {
        if hasLocalAnswers { return true }
        if context.isPrepared { return true }
        if context.serverState.queueStaged == true { return true }
        return context.questions.contains { ($0.preparedAnswerId ?? "").isEmpty == false }
    }

    /// What must the operator confirm before the outgoing unit's preparation is
    /// discarded? Nothing entered → no interruption; entered but not saved →
    /// the partial wording; Saved/Staged → the prepared wording.
    static func confirmation(for context: ChecklistContext, hasLocalAnswers: Bool) -> PreparationLifecycle.Confirmation {
        let saved = context.isPrepared
            || context.serverState.queueStaged == true
            || context.questions.contains { ($0.preparedAnswerId ?? "").isEmpty == false }

        if saved { return .discardPrepared }
        return hasLocalAnswers ? .discardPartial : .none
    }

    /// Choosing the unit that is already assigned changes nothing — never a
    /// confirmation, never an operation, never a discarded checklist.
    static func isSameUnit(_ context: ChecklistContext, replacementUniqueId: String) -> Bool {
        guard let current = context.equipment.equipmentUniqueId, !current.isEmpty else { return false }
        return current == replacementUniqueId
    }

    // MARK: Wording (one source, so the screen and the tests agree)

    static func substitutionTitle() -> String { "Change equipment and start over?" }

    static func substitutionMessage(currentCode: String, replacementCode: String, confirmation: PreparationLifecycle.Confirmation) -> String {
        switch confirmation {
        case .discardPrepared:
            return "The saved checklist belongs to Equipment \(currentCode). Changing to Equipment \(replacementCode) will discard that preparation and start a new checklist for the replacement unit."
        case .discardPartial:
            return "Checklist work already entered belongs to Equipment \(currentCode). Changing to Equipment \(replacementCode) will clear that preparation and start a new checklist for the replacement unit."
        case .none:
            return "Equipment \(replacementCode) will be prepared for this order instead of Equipment \(currentCode)."
        }
    }

    static func restartTitle() -> String { "Start this checklist over?" }

    static func restartMessage(currentCode: String) -> String {
        "This will discard the saved preparation for Equipment \(currentCode) and return this item to Pending. The equipment assignment will remain."
    }
}

// MARK: - Durable operations

/// One operator decision that discards a preparation cycle.
struct EquipmentSubstitutionCapture: Equatable {
    var orderUniqueId: String
    var orderProductUniqueId: String
    /// The cycle being discarded — carried for diagnostics and so the local
    /// overlay knows which execution's evidence stops counting.
    var supersededExecutionId: String
    var previousEquipmentUniqueId: String?
    var replacementEquipmentUniqueId: String
    /// The employee physically staging (self-selected on shared terminals).
    var performedByUniqueId: String
    /// Required by the server for a non-direct product match.
    var reason: String?
    var capturedAt: Date = Date()
}

/// "Delete Checklist / Start Over" for the SAME unit.
struct ChecklistRestartCapture: Equatable {
    var orderUniqueId: String
    var orderProductUniqueId: String
    var executionId: String
    var leg: ChecklistLeg
    var equipmentUniqueId: String?
    var employeeUserId: Int
    var reason: String?
    var capturedAt: Date = Date()
}

enum PreparationOperationBuilder {

    /// Canonical reassignment — the SAME endpoint and service the web Queue
    /// Line board uses. The checklist never edits an assignment locally.
    static let substitutionType = "queue_line.switch_equipment"

    static func restartType(_ leg: ChecklistLeg) -> String { leg.operationPrefix + ".reset" }

    // MARK: Payloads

    static func substitutionPayload(_ capture: EquipmentSubstitutionCapture) -> JSONValue {
        var body: [String: JSONValue] = [
            "order_product_unique_id": .string(capture.orderProductUniqueId),
            "equipment_unique_id": .string(capture.replacementEquipmentUniqueId),
            "performed_by": .string(capture.performedByUniqueId),
        ]
        if let reason = capture.reason, !reason.isEmpty { body["reason"] = .string(reason) }
        return .object(body)
    }

    static func restartPayload(_ capture: ChecklistRestartCapture) -> JSONValue {
        var body: [String: JSONValue] = [
            "order_product_unique_id": .string(capture.orderProductUniqueId),
        ]
        if capture.employeeUserId > 0 { body["user_id"] = .number(Double(capture.employeeUserId)) }
        if let reason = capture.reason, !reason.isEmpty { body["reason"] = .string(reason) }
        return .object(body)
    }

    // MARK: Identity + labels

    static func identity(_ capture: EquipmentSubstitutionCapture) -> SyncBusinessIdentity {
        SyncBusinessIdentity(orderUniqueId: capture.orderUniqueId,
                             orderProductUniqueId: capture.orderProductUniqueId,
                             equipmentUniqueId: capture.replacementEquipmentUniqueId,
                             checklistExecutionId: capture.supersededExecutionId.isEmpty ? nil : capture.supersededExecutionId)
    }

    static func identity(_ capture: ChecklistRestartCapture) -> SyncBusinessIdentity {
        SyncBusinessIdentity(orderUniqueId: capture.orderUniqueId,
                             orderProductUniqueId: capture.orderProductUniqueId,
                             equipmentUniqueId: capture.equipmentUniqueId,
                             checklistExecutionId: capture.executionId)
    }

    // MARK: Enqueue

    /// Durably records a substitution. Returns nil when the chosen unit is the
    /// one already assigned — a no-op must never enqueue an operation or
    /// discard a checklist.
    @discardableResult
    static func enqueueSubstitution(_ capture: EquipmentSubstitutionCapture,
                                    into engine: SyncEngine,
                                    operationId: String = UUID().uuidString) throws -> SyncOperation? {
        guard !capture.replacementEquipmentUniqueId.isEmpty else { return nil }
        if let previous = capture.previousEquipmentUniqueId, previous == capture.replacementEquipmentUniqueId {
            return nil
        }

        return try engine.enqueue(type: substitutionType,
                                  payload: substitutionPayload(capture),
                                  identity: identity(capture),
                                  capturedAt: capture.capturedAt,
                                  displayTitle: "Equipment switched · \(capture.replacementEquipmentUniqueId)",
                                  operationId: operationId)
    }

    @discardableResult
    static func enqueueRestart(_ capture: ChecklistRestartCapture,
                               into engine: SyncEngine,
                               operationId: String = UUID().uuidString) throws -> SyncOperation {
        try engine.enqueue(type: restartType(capture.leg),
                           payload: restartPayload(capture),
                           identity: identity(capture),
                           capturedAt: capture.capturedAt,
                           displayTitle: "\(capture.leg.isDelivery ? "Delivery" : "Return") checklist · restarted",
                           operationId: operationId)
    }
}

/// The request shapes for the two operations (app layer wires the session check).
enum PreparationRequestFactory {

    static func substitutionRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard let product = operation.payload["order_product_unique_id"]?.stringValue, !product.isEmpty else {
            throw SyncHandlerError.invalidPayload("Equipment substitution has no order product")
        }
        guard operation.payload["equipment_unique_id"]?.stringValue?.isEmpty == false else {
            throw SyncHandlerError.invalidPayload("Equipment substitution has no replacement unit")
        }
        var body = operation.payload.objectValue ?? [:]
        body["operation_id"] = .string(operation.id)
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))

        return SyncHTTPRequest(method: "POST",
                               path: "queue-line/\(product)/switch-equipment",
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id)
    }

    static func restartRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard let executionId = operation.identity.checklistExecutionId, !executionId.isEmpty else {
            throw SyncHandlerError.invalidPayload("Checklist restart has no execution id")
        }
        var body = operation.payload.objectValue ?? [:]
        body["operation_id"] = .string(operation.id)
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))

        return SyncHTTPRequest(method: "POST",
                               path: "orders/checklists/\(executionId)/reset",
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id)
    }
}

// MARK: - Hour-meter math (total over every Float — never traps)
//
// The legacy total-charge pass did `Int(hours.rounded(.up))` on unvalidated
// Float arithmetic. The hours text field re-renders a large model value in
// scientific notation ("2.002e+11"); appending digits lands them in the
// EXPONENT ("2.002e+11200"), which parses to ±infinity — and Int(±.infinity)
// is a hard Swift trap that crashed the preparation workbench mid-keystroke.
// Overage hours are by definition a small non-negative number, so both
// conversions clamp to 0...cap and treat every non-finite value as no overage.
enum ChecklistHoursMath {

    /// Ceiling of (end − start) clamped to 0...cap. Non-finite input → 0
    /// overage (the operator fixes the meter reading; the app never dies).
    static func overageHours(start: Float, end: Float, cap: Int = 1_000_000) -> Int {
        guard start.isFinite || end.isFinite else { return 0 }
        let delta = end - start
        guard !delta.isNaN else { return 0 }
        guard delta > 0 else { return 0 }
        let rounded = delta.rounded(.up)
        return rounded >= Float(cap) ? cap : Int(rounded)
    }

    /// Billable hours above the allocation, truncated like the legacy
    /// Int(Float) conversion, clamped to 0...cap, total over every Float.
    static func additionalHours(total: Int, allocated: Float, cap: Int = 1_000_000) -> Int {
        let boundedTotal = max(0, min(total, cap))
        guard !allocated.isNaN else { return 0 }
        guard allocated.isFinite else { return allocated < 0 ? boundedTotal : 0 }
        let delta = Float(boundedTotal) - allocated
        guard delta.isFinite, delta > 0 else { return 0 }
        return delta >= Float(cap) ? cap : Int(delta)
    }
}

// MARK: - Machine-row synthesis policy
//
// The hours/cleaning/fuel rows describe the PHYSICAL MACHINE being prepared,
// not the order line. A machine (re)pick rebuilds them for the new unit and
// must REPLACE the previous unit's rows — the substitution flow used to
// prepend a fresh Start Hours + Fuel pair on every pick, and after two
// substitutions the checklist demanded three hour meters and could never
// reach 100% for staging.
enum SynthesizedRowPolicy {
    static let machineRowTypes: Set<String> = ["text", "cleaning", "fuel"]

    static func isMachineRow(type: String?) -> Bool {
        guard let type = type else { return false }
        return machineRowTypes.contains(type)
    }
}
