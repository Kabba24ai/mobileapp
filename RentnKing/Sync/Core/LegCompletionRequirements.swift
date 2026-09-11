//
//  LegCompletionRequirements.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Leg-aware effective completion (2026-09). When the driver taps
//  "Delivery Complete" / "Return Complete – Next Mission" the app must answer
//  ONE question with ONE definition of "complete":
//
//      which requirements apply to THIS leg, and is each of them effectively
//      satisfied — server-confirmed ∨ durable local Sync Engine evidence?
//
//  Before this file, Order Details lit its chips from one set of sources, the
//  completion gate judged from another, and the gate evaluated all six
//  requirements whatever the leg — so a Return could be blocked by historical
//  Delivery-leg facts (license, T&C, delivery media, delivery checklist), and
//  work sitting durably on the phone could be reported as "Not Completed"
//  while the server feed was stale. This is now the single decision point;
//  view controllers consume `LegCompletionDecision` and never re-derive it.
//
//  Requirement matrix (explicit, never inferred per screen):
//
//      requirement          Delivery completion   Return completion
//      Terms & Conditions   required              ignored (historical)
//      Driver's License     required              ignored (historical)
//      Delivery Photo/Video required              ignored (historical)
//      Delivery Checklist   required              ignored (historical)
//      Return Photo/Video   n/a                   REQUIRED
//      Return Checklist     n/a                   REQUIRED
//
//  Delivery rules are exactly the pre-existing ones (order-scoped license /
//  T&C / delivery media, any-line delivery checklist). Return rules are strict:
//  the focused order product, the Return leg, and the CURRENT return checklist
//  cycle — a sibling line's work, Delivery-leg evidence, or a superseded cycle
//  never satisfies the Return.
//
//  Sync states: pending / syncing / synced evidence = satisfied. A record the
//  server terminally rejected (needsAttention) is still the driver's work —
//  it never becomes a false "Not Completed" override; it is reported as
//  `satisfiedNeedsAttention` so the screen applies the canonical sync-attention
//  treatment (Settings › Sync / Mobile Sync Issues) instead of claiming success.
//

import Foundation

/// A field action the office may require before one leg of ONE order product is complete.
enum FulfillmentRequirement: String, CaseIterable, Codable, Equatable {
    case termsAndConditions
    case driverLicense
    case deliveryMedia
    case deliveryChecklist
    case returnMedia
    case returnChecklist
}

extension ChecklistLeg {
    /// The ONLY requirements that may block completing this leg, in the order
    /// the override screen lists them.
    var completionRequirements: [FulfillmentRequirement] {
        switch self {
        case .delivery: return [.termsAndConditions, .driverLicense, .deliveryMedia, .deliveryChecklist]
        case .return:   return [.returnMedia, .returnChecklist]
        }
    }

    func applies(_ requirement: FulfillmentRequirement) -> Bool {
        completionRequirements.contains(requirement)
    }
}

/// How one applicable requirement stands right now.
enum RequirementStatus: Equatable {
    /// Confirmed outside the engine, or durable local evidence that is pending / syncing / synced.
    case satisfied
    /// The driver DID the work, but the server terminally rejected the record
    /// (Needs Attention). Never "missing work" — reconciliation is the office's job.
    case satisfiedNeedsAttention(operationId: String)
    /// The driver has not performed the action.
    case incomplete

    var isSatisfied: Bool {
        if case .incomplete = self { return false }
        return true
    }
}

/// What the screen knows from OUTSIDE the Sync Engine: the server feed and the
/// legacy local stores. "Confirmed" here can be stale-negative (the server has
/// not caught up) — that is exactly why durable operations are consulted too.
struct LegCompletionInputs: Equatable {
    var orderUniqueId: String
    /// The order product whose leg is being completed. Return evaluation is
    /// strict to this line. Empty → order-wide fallback (any line), which is
    /// the pre-existing semantics for screens that carry no focus product.
    var orderProductUniqueId: String
    /// Every product line on the order (delivery-checklist any-line rule, and
    /// the fallback when there is no focus product).
    var orderProductUniqueIds: [String]

    var licenseConfirmed: Bool = false
    var termsConfirmed: Bool = false
    var deliveryMediaConfirmed: Bool = false
    var deliveryChecklistConfirmed: Bool = false
    /// Return media / checklist confirmed FOR `orderProductUniqueId`.
    var returnMediaConfirmed: Bool = false
    var returnChecklistConfirmed: Bool = false
    /// The current return checklist execution for the focus product, when the
    /// phone knows it (cached context). Empty → unknown.
    var activeReturnExecutionId: String = ""

    init(orderUniqueId: String,
         orderProductUniqueId: String,
         orderProductUniqueIds: [String],
         licenseConfirmed: Bool = false,
         termsConfirmed: Bool = false,
         deliveryMediaConfirmed: Bool = false,
         deliveryChecklistConfirmed: Bool = false,
         returnMediaConfirmed: Bool = false,
         returnChecklistConfirmed: Bool = false,
         activeReturnExecutionId: String = "") {
        self.orderUniqueId = orderUniqueId
        self.orderProductUniqueId = orderProductUniqueId
        self.orderProductUniqueIds = orderProductUniqueIds
        self.licenseConfirmed = licenseConfirmed
        self.termsConfirmed = termsConfirmed
        self.deliveryMediaConfirmed = deliveryMediaConfirmed
        self.deliveryChecklistConfirmed = deliveryChecklistConfirmed
        self.returnMediaConfirmed = returnMediaConfirmed
        self.returnChecklistConfirmed = returnChecklistConfirmed
        self.activeReturnExecutionId = activeReturnExecutionId
    }
}

/// The four sections the Driver Override screen can show. Derived from the
/// decision only — a screen never decides on its own which to present.
struct OverrideSections: Equatable {
    var terms: Bool
    var license: Bool
    var video: Bool
    var checklist: Bool

    static let none = OverrideSections(terms: false, license: false, video: false, checklist: false)
    var isEmpty: Bool { !terms && !license && !video && !checklist }
}

/// The answer for one leg of one order product.
struct LegCompletionDecision: Equatable {
    let leg: ChecklistLeg
    /// Exactly the leg's applicable requirements — nothing else is ever judged.
    let statuses: [FulfillmentRequirement: RequirementStatus]

    /// nil when the requirement does not apply to this leg.
    func status(_ requirement: FulfillmentRequirement) -> RequirementStatus? {
        statuses[requirement]
    }

    /// Genuinely incomplete requirements, in override-screen order.
    var missing: [FulfillmentRequirement] {
        leg.completionRequirements.filter { statuses[$0] == .incomplete }
    }

    var canProceed: Bool { missing.isEmpty }

    /// The override screen exists for INCOMPLETE work, never for Pending Sync.
    var shouldPresentOverride: Bool { !canProceed }

    /// Operations whose Needs Attention state is the only evidence for a
    /// requirement — the driver proceeds, the screen shows the canonical
    /// sync-attention treatment instead of a success animation.
    var needsAttentionOperationIds: [String] {
        var ids: [String] = []
        for requirement in leg.completionRequirements {
            if case .satisfiedNeedsAttention(let id)? = statuses[requirement], !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids
    }

    var requiresSyncAttention: Bool { !needsAttentionOperationIds.isEmpty }

    var overrideSections: OverrideSections {
        let missing = self.missing
        return OverrideSections(terms: missing.contains(.termsAndConditions),
                                license: missing.contains(.driverLicense),
                                video: missing.contains(.deliveryMedia) || missing.contains(.returnMedia),
                                checklist: missing.contains(.deliveryChecklist) || missing.contains(.returnChecklist))
    }
}

enum LegCompletionEvaluator {

    /// The ONE decision: applicable requirements × effective satisfaction.
    static func evaluate(leg: ChecklistLeg,
                         inputs: LegCompletionInputs,
                         operations: [SyncOperation]) -> LegCompletionDecision {
        var statuses: [FulfillmentRequirement: RequirementStatus] = [:]
        for requirement in leg.completionRequirements {
            statuses[requirement] = status(of: requirement, inputs: inputs, operations: operations)
        }
        return LegCompletionDecision(leg: leg, statuses: statuses)
    }

    /// Effective status of one requirement (leg-agnostic; callers pick the
    /// leg's list through `evaluate`).
    static func status(of requirement: FulfillmentRequirement,
                       inputs: LegCompletionInputs,
                       operations: [SyncOperation]) -> RequirementStatus {
        switch requirement {
        case .termsAndConditions:
            return orderScoped(confirmed: inputs.termsConfirmed, types: [EffectiveFieldState.termsAcceptedType], inputs: inputs, operations: operations)
        case .driverLicense:
            return orderScoped(confirmed: inputs.licenseConfirmed, types: [EffectiveFieldState.licenseMediaType], inputs: inputs, operations: operations)
        case .deliveryMedia:
            return orderScoped(confirmed: inputs.deliveryMediaConfirmed, types: [EffectiveFieldState.deliveryMediaType], inputs: inputs, operations: operations)
        case .deliveryChecklist:
            return deliveryChecklist(inputs: inputs, operations: operations)
        case .returnMedia:
            return returnMedia(inputs: inputs, operations: operations)
        case .returnChecklist:
            return returnChecklist(inputs: inputs, operations: operations)
        }
    }

    // MARK: - Delivery leg (pre-existing semantics, unchanged)

    /// License / T&C / delivery media are ORDER-level facts: any durable op of
    /// the type for this order satisfies (as `EffectiveFieldState` always did).
    private static func orderScoped(confirmed: Bool,
                                    types: Set<String>,
                                    inputs: LegCompletionInputs,
                                    operations: [SyncOperation]) -> RequirementStatus {
        if confirmed { return .satisfied }
        guard !inputs.orderUniqueId.isEmpty else { return .incomplete }
        let evidence = operations.filter { types.contains($0.type) && $0.identity.orderUniqueId == inputs.orderUniqueId }
        return status(from: evidence)
    }

    /// The delivery checklist is satisfied by a durable completion for ANY line
    /// of the order (the pre-existing `effectiveLegCompleted` rule).
    private static func deliveryChecklist(inputs: LegCompletionInputs, operations: [SyncOperation]) -> RequirementStatus {
        if inputs.deliveryChecklistConfirmed { return .satisfied }
        let targets = deliveryTargets(inputs)
        guard !targets.isEmpty else { return .incomplete }
        let evidence = operations.filter { op in
            guard let product = op.identity.orderProductUniqueId, targets.contains(product) else { return false }
            return op.type == EffectiveFieldState.deliveryCompleteType || isLegacySubmission(op, leg: .delivery)
        }
        return status(from: evidence)
    }

    // MARK: - Return leg (strict: product + leg + current cycle)

    static func returnMedia(inputs: LegCompletionInputs, operations: [SyncOperation]) -> RequirementStatus {
        if inputs.returnMediaConfirmed { return .satisfied }
        let targets = returnTargets(inputs)
        guard !targets.isEmpty else { return .incomplete }
        return best(targets.map { product in
            status(from: operations.filter { op in
                op.type == EffectiveFieldState.returnMediaType
                    && op.identity.orderProductUniqueId == product
                    && belongsToCurrentReturnCycle(op, product: product, inputs: inputs, operations: operations)
            })
        })
    }

    static func returnChecklist(inputs: LegCompletionInputs, operations: [SyncOperation]) -> RequirementStatus {
        if inputs.returnChecklistConfirmed { return .satisfied }
        let targets = returnTargets(inputs)
        guard !targets.isEmpty else { return .incomplete }
        return best(targets.map { product in
            status(from: operations.filter { op in
                guard op.identity.orderProductUniqueId == product else { return false }
                guard op.type == EffectiveFieldState.returnCompleteType || isLegacySubmission(op, leg: .return) else { return false }
                return belongsToCurrentReturnCycle(op, product: product, inputs: inputs, operations: operations)
            })
        })
    }

    /// Preparation-cycle identity for Return evidence (mirrors the delivery
    /// video rule): evidence naming a cycle counts only for THAT cycle — never
    /// a cycle this phone durably discarded, and, when the current cycle is
    /// known, only the current one. Cycle-less evidence (captured from Order
    /// Details, or migrated from the legacy queue) stands unless this phone
    /// restarted the product's return checklist AFTER it was captured.
    static func belongsToCurrentReturnCycle(_ op: SyncOperation,
                                            product: String,
                                            inputs: LegCompletionInputs,
                                            operations: [SyncOperation]) -> Bool {
        let execution = op.identity.checklistExecutionId ?? ""
        if !execution.isEmpty {
            if EffectiveFieldState.supersededExecutionIds(in: operations).contains(execution) { return false }
            if !inputs.activeReturnExecutionId.isEmpty { return execution == inputs.activeReturnExecutionId }
            return true
        }
        if let discardedAt = lastReturnDiscardAt(in: operations, orderProductUniqueId: product), op.queuedAt < discardedAt {
            return false
        }
        return true
    }

    /// The latest durable "Delete Checklist / Start Over" for the RETURN leg of
    /// this product. Delivery-leg discards (substitution, delivery restart)
    /// belong to the pre-departure phase and never invalidate Return evidence.
    static func lastReturnDiscardAt(in operations: [SyncOperation], orderProductUniqueId: String) -> Date? {
        operations
            .filter { $0.type == EffectiveFieldState.returnRestartType
                && EffectiveFieldState.countsAsDurableEvidence($0.state)
                && $0.identity.orderProductUniqueId == orderProductUniqueId }
            .map(\.queuedAt)
            .max()
    }

    // MARK: - Shared

    /// Durable evidence → status. Any healthy record (pending / syncing /
    /// synced) outranks a parked one; a parked record alone is still the
    /// driver's work, reported as Needs Attention rather than missing.
    private static func status(from evidence: [SyncOperation]) -> RequirementStatus {
        let durable = evidence.filter { EffectiveFieldState.countsAsDurableEvidence($0.state) }
        if durable.contains(where: { $0.state != .needsAttention }) { return .satisfied }
        if let parked = durable.first(where: { $0.state == .needsAttention }) {
            return .satisfiedNeedsAttention(operationId: parked.id)
        }
        return .incomplete
    }

    /// Order-wide fallback merge: the best status any target line reaches.
    private static func best(_ statuses: [RequirementStatus]) -> RequirementStatus {
        if statuses.contains(.satisfied) { return .satisfied }
        if let parked = statuses.first(where: { if case .satisfiedNeedsAttention = $0 { return true }; return false }) { return parked }
        return .incomplete
    }

    /// Return evaluation targets: the focus product, else (no focus) every
    /// line the screen passed — the pre-existing any-line semantics.
    private static func returnTargets(_ inputs: LegCompletionInputs) -> [String] {
        if !inputs.orderProductUniqueId.isEmpty { return [inputs.orderProductUniqueId] }
        return inputs.orderProductUniqueIds.filter { !$0.isEmpty }
    }

    /// Delivery evaluation targets: every line (any-line rule), else the focus product.
    private static func deliveryTargets(_ inputs: LegCompletionInputs) -> [String] {
        let all = inputs.orderProductUniqueIds.filter { !$0.isEmpty }
        if !all.isEmpty { return all }
        return inputs.orderProductUniqueId.isEmpty ? [] : [inputs.orderProductUniqueId]
    }

    /// A pre-Phase-3 queue item migrated into the engine (`legacy_customer_checklist.submit`)
    /// carries its leg as `type` = "Delivery" | "Return" in the verbatim payload.
    private static func isLegacySubmission(_ op: SyncOperation, leg: ChecklistLeg) -> Bool {
        guard op.type == LegacyChecklistQueueMigration.operationType else { return false }
        let type = (op.payload["type"]?.stringValue ?? "").lowercased()
        return type == (leg.isDelivery ? "delivery" : "return")
    }
}
