//
//  ChecklistLegCompletion.swift
//  KabbaSyncCore
//
//  ONE answer, per order product, to "is this equipment's checklist done for the leg —
//  and the rental cycle — we are on?", and from it whether an ORDER-WIDE checklist entry
//  (Order Details, the Orders list) may show the completed report or must let the
//  unfinished equipment be completed.
//
//  Canonical truth per line:
//    • Laravel's own flag for the leg (`is_delivered` / `is_returned`). The server reopens
//      a leg — minting a new cycle — exactly when that flag is false, so it always speaks
//      for the CURRENT cycle;
//    • ∨ a durable LOCAL completion operation for that product and leg (offline, not yet
//      confirmed) that belongs to the line's current cycle: when the phone knows the
//      current execution only that execution's completion counts, and a cycle this phone
//      discarded (substitution / restart) never counts.
//  Never: an order-level cache, "any line completed", the first line's flag, or a local
//  draft — drafts keep entered values; they say nothing about what is finished.
//

import Foundation

enum ChecklistLegCompletion {

    struct Line: Equatable {
        let orderProductUniqueId: String
        /// Equipment that never takes a checklist (e.g. Retail) is not part of any leg.
        let requiresChecklist: Bool
        let deliveredOnServer: Bool
        let returnedOnServer: Bool
        /// The current cycle's checklist execution per leg, when this phone knows it.
        var activeDeliveryExecutionId: String = ""
        var activeReturnExecutionId: String = ""
        /// When this phone received the order copy the flags above come from (nil: unknown,
        /// e.g. an offline cached copy). A copy received AFTER Laravel acknowledged a
        /// completion already contains it — if it still says the leg is open, the leg was
        /// reopened (a new cycle) and that synced completion no longer counts.
        var serverStateAsOf: Date? = nil
    }

    static func completionType(_ leg: ChecklistLeg) -> String {
        leg == .delivery ? EffectiveFieldState.deliveryCompleteType : EffectiveFieldState.returnCompleteType
    }

    /// Is this line's checklist for `leg` complete for its current cycle?
    static func isComplete(_ line: Line, leg: ChecklistLeg, operations: [SyncOperation]) -> Bool {
        if leg == .delivery ? line.deliveredOnServer : line.returnedOnServer { return true }
        return hasCurrentCycleCompletion(line, leg: leg, operations: operations)
    }

    /// Does this line take part in `leg`? A return is only owed for equipment that was delivered.
    static func isEligible(_ line: Line, leg: ChecklistLeg, operations: [SyncOperation]) -> Bool {
        guard line.requiresChecklist else { return false }
        return leg == .delivery || isComplete(line, leg: .delivery, operations: operations)
    }

    /// The equipment whose checklist for `leg` is still owed, in order.
    static func unfinished(_ lines: [Line], leg: ChecklistLeg, operations: [SyncOperation]) -> [String] {
        lines.filter { isEligible($0, leg: leg, operations: operations) && !isComplete($0, leg: leg, operations: operations) }
            .map(\.orderProductUniqueId)
    }

    /// The completed report is the right screen only when EVERY eligible line is complete.
    /// With unfinished equipment (or none eligible at all) the entry opens the checklist flow.
    static func everyEligibleLineComplete(_ lines: [Line], leg: ChecklistLeg, operations: [SyncOperation]) -> Bool {
        let eligible = lines.filter { isEligible($0, leg: leg, operations: operations) }
        return !eligible.isEmpty && eligible.allSatisfy { isComplete($0, leg: leg, operations: operations) }
    }

    /// Can the leg be worked on at all (Return: some equipment is out with the customer)?
    static func anyEligibleLine(_ lines: [Line], leg: ChecklistLeg, operations: [SyncOperation]) -> Bool {
        lines.contains { isEligible($0, leg: leg, operations: operations) }
    }

    private static func hasCurrentCycleCompletion(_ line: Line, leg: ChecklistLeg, operations: [SyncOperation]) -> Bool {
        guard !line.orderProductUniqueId.isEmpty else { return false }
        let active = leg == .delivery ? line.activeDeliveryExecutionId : line.activeReturnExecutionId
        let superseded = EffectiveFieldState.supersededExecutionIds(in: operations)
        let discardedAt = EffectiveFieldState.lastDiscardAt(in: operations, orderProductUniqueId: line.orderProductUniqueId)
        return operations.contains { op in
            guard op.type == completionType(leg),
                  EffectiveFieldState.countsAsDurableEvidence(op.state),
                  op.identity.orderProductUniqueId == line.orderProductUniqueId else { return false }
            // Laravel answered after accepting this completion and still reports the leg open:
            // it was reopened since — that completion belongs to a prior cycle.
            if op.state == .synced, let asOf = line.serverStateAsOf,
               let acknowledged = op.acknowledgment?.acknowledgedAt, acknowledged <= asOf { return false }
            let execution = op.identity.checklistExecutionId ?? ""
            // The current cycle is known: only ITS completion counts (a prior cycle's never does).
            if !active.isEmpty, !execution.isEmpty { return execution == active }
            // Unknown (offline first open) or unattributed: stands unless this phone discarded it.
            if !execution.isEmpty, superseded.contains(execution) { return false }
            if let discardedAt, op.queuedAt < discardedAt { return false }
            return true
        }
    }
}

// MARK: - Assembly Review / Queue Line lanes

extension QueueLineLocalOverlay {

    /// The review's "delivered" lane holds a line this phone completed until Laravel shows it.
    /// When Laravel's answer — asked AFTER it acknowledged that completion (`asOf`) — still
    /// reports the line not delivered, the delivery was reopened since (a new cycle): the line
    /// is owed again and must reach its checklist (ChecklistLegCompletion's rule per line).
    /// `serverDelivered`: the answer's own delivered flag per line. nil `asOf` (age unknown,
    /// e.g. an unstamped cached answer) changes nothing.
    func owingLinesReopenedOnServer(_ serverDelivered: [String: Bool], asOf: Date?,
                                    operations: [SyncOperation]) -> QueueLineLocalOverlay {
        guard let asOf else { return self }
        var copy = self
        for product in completedLocally where serverDelivered[product] == false {
            let line = ChecklistLegCompletion.Line(orderProductUniqueId: product, requiresChecklist: true,
                                                   deliveredOnServer: false, returnedOnServer: false,
                                                   serverStateAsOf: asOf)
            if !ChecklistLegCompletion.isComplete(line, leg: .delivery, operations: operations) {
                copy.completedLocally.remove(product)
            }
        }
        return copy
    }
}
