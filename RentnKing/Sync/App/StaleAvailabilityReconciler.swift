//
//  StaleAvailabilityReconciler.swift
//  RentnKing — Sync App layer
//
//  Applies StaleAvailabilityRetirement (Core) with what THIS phone holds as a line's
//  canonical unit: the cached Assembly Review of the order (written by the offline
//  package bridge and by every live review fetch). Runs whenever either side of the
//  proof can have changed — a QUEUE_ASSIGNMENT_CHANGED rejection just landed, a
//  review was cached, the engine came up — and retires only what the rule proves.
//  Everything else in the queue is untouched.
//

import Foundation

enum StaleAvailabilityReconciler {

    /// The unit this phone holds for the line (unique id + display name), or nil when it holds none.
    static func canonicalUnit(orderUniqueId: String?, orderProductUniqueId: String?) -> (id: String, name: String?)? {
        guard let order = orderUniqueId, let product = orderProductUniqueId,
              let envelope = KabbaAssemblySync.cached(orderUniqueId: order),
              let member = envelope.data.members.first(where: { $0.orderProductUniqueId == product }),
              let unit = member.equipment?.uniqueId?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty else { return nil }
        return (unit, member.equipment?.name)
    }

    /// Judges every parked availability the server refused with QUEUE_ASSIGNMENT_CHANGED and
    /// retires the ones the rule proves obsolete. Returns the retired operation ids.
    /// Never call from the engine's own queue (it reads the engine synchronously).
    @discardableResult
    static func run(engine: SyncEngine? = KabbaSync.engine,
                    now: Date = Date(),
                    canonicalUnit: ((SyncOperation) -> (id: String, name: String?)?)? = nil) -> [String] {
        guard let engine else { return [] }
        let lookup = canonicalUnit ?? { op in
            Self.canonicalUnit(orderUniqueId: op.identity.orderUniqueId, orderProductUniqueId: op.identity.orderProductUniqueId)
        }
        var retired: [String] = []
        for op in engine.snapshot() where op.state == .needsAttention
            && op.type == AssemblyOperationBuilder.availabilityType
            && op.attempts.lastErrorCode == StaleAvailabilityRetirement.assignmentChangedCode {
            let canonical = lookup(op)
            guard let supersession = StaleAvailabilityRetirement.supersession(for: op,
                                                                              canonicalEquipmentUniqueId: canonical?.id,
                                                                              canonicalEquipmentName: canonical?.name,
                                                                              now: now) else { continue }
            engine.supersede(operationId: op.id, with: supersession)
            retired.append(op.id)
        }
        return retired
    }

    /// The triggers call this: a pass on the main queue, off whatever thread noticed the change.
    static func schedule(reason: String) {
        DispatchQueue.main.async {
            let retired = run()
            if !retired.isEmpty {
                KabbaSync.engine?.logger?("stale availability retired (\(reason)): \(retired.map { String($0.prefix(8)) }.joined(separator: ", "))")
            }
        }
    }

    /// Does this changed operation deserve a pass? (A rejection that named the machine the line has now.)
    static func concerns(_ op: SyncOperation) -> Bool {
        op.state == .needsAttention
            && op.type == AssemblyOperationBuilder.availabilityType
            && op.attempts.lastErrorCode == StaleAvailabilityRetirement.assignmentChangedCode
    }
}
