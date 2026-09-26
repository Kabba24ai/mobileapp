//
//  DispatchOfflineFieldBridge.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Dispatch offline mission cache — Phase 4. Preloads the caches the EXISTING
//  screens already read, from each stored mission package, so a mission never
//  opened online still runs Dispatch → Driver Checklist → Order Details →
//  equipment checklist with the phone offline (locked Phase 3 decision D2):
//
//    checklist_context → ChecklistContextStore (<tenant>/<opuid>__<leg>)
//    order_details     → the Order Details cache + the checklist screens' order cache (App writer)
//    assembly          → the Assembly Review cache (App writer, delivery only)
//    terms             → TermsAgreementStore (Phase 5, delivery only, verified agreements only)
//
//  No second cache: each section is the canonical server payload the screen
//  would have cached after an online open. Rules (plan §4.2–§4.3):
//    • never overwrite fresher truth (a later server_time / higher cycle, or a
//      newer observed Order Details / Assembly copy);
//    • never write a context a local substitution or restart has superseded;
//    • the context's employee is the user signed in NOW (P4-D5);
//    • everything is written for THIS store's company only (Amendment B).
//
//  Readiness (Amendment A): a mission is field-ready only when every required
//  section is satisfied at its current package revision — Delivery: context +
//  order_details + assembly + terms (Phase 5, when the order's terms are
//  Pending); Return: context + order_details. A section the
//  server reported `failed`, or a context the phone could not decode, is
//  retryable: the reconciler re-requests that package at the SAME revision.
//

import Foundation

/// The screens' existing order-scoped caches a package fills (each also saved by its screen from
/// a live response, so each has its own freshness stamp).
enum DispatchOfflineOrderCache: String, Codable, CaseIterable, Equatable {
    /// Order Details (`order_details` as OrdersListModel).
    case orderDetails = "order_details"
    /// The checklist screens' copy of the same order (`order_details` as OrdersModel).
    case checklistOrder = "checklist_order"
    /// Assembly Review (`assembly`, delivery only).
    case assembly
    /// Phase 5: the order's frozen Terms agreement (TermsAgreementStore, written by Core — never by the App writer).
    case terms
}

/// The App layer writes the order-scoped sections into the screens' existing
/// (tenant-scoped) caches. Returns false when the write failed.
protocol DispatchOfflineOrderCacheWriting: AnyObject {
    func write(_ cache: DispatchOfflineOrderCache, payload: JSONValue, orderUniqueId: String, tenantKey: String) -> Bool
}

/// Metadata only — which section of which mission revision is satisfied, and how new the
/// order-scoped copies on this phone are. Stored in the company's own dispatch-offline directory.
struct DispatchOfflineFieldLedger: Codable, Equatable {

    enum SectionState: String, Codable, Equatable {
        /// Bridged, or a fresher copy is already on this phone.
        case satisfied
        /// Not required (Return has no Assembly Review).
        case notApplicable
        /// The server reported the section failed to build — retryable.
        case failed
        /// Present but the phone could not use it (does not decode / wrong identity) — retryable.
        case invalid
        /// A pre-Phase-4 server: deep offline unavailable, never retried.
        case notProvided
        /// A local substitution or restart superseded it — waits for the server's new cycle.
        case blocked
        /// Valid, but the local write failed — re-bridged from disk, never re-downloaded.
        case pending
        /// Phase 5 (terms): required, but the order has no trustworthy stored agreement —
        /// settled (retrying cannot help), and the mission is not fully offline-ready.
        case unavailable
    }

    struct Mission: Codable, Equatable {
        /// The package revision these states belong to.
        var revision: String
        /// The package carried a Phase 4 `sections` map (only then is anything retryable).
        var serverReportsSections: Bool
        var checklistContext: SectionState
        var orderDetails: SectionState
        var assembly: SectionState
        /// Phase 5. nil = a ledger written before Phase 5: not settled, so it is re-bridged once.
        var terms: SectionState?

        init(revision: String, serverReportsSections: Bool, checklistContext: SectionState,
             orderDetails: SectionState, assembly: SectionState, terms: SectionState? = .notApplicable) {
            self.revision = revision
            self.serverReportsSections = serverReportsSections
            self.checklistContext = checklistContext
            self.orderDetails = orderDetails
            self.assembly = assembly
            self.terms = terms
        }

        private var states: [SectionState?] { [checklistContext, orderDetails, assembly, terms] }

        /// Every required section is present. Terms from a pre-Phase-5 server (`notProvided`) keep
        /// Phase 4's readiness: T&C then works as it did in Phase 4 (online, or the override).
        var isComplete: Bool {
            [checklistContext, orderDetails, assembly].allSatisfy { $0 == .satisfied || $0 == .notApplicable }
                && (terms == .satisfied || terms == .notApplicable || terms == .notProvided)
        }
        /// Nothing left to do at this revision (complete, or permanently unavailable from this server).
        var isSettled: Bool { states.allSatisfy { $0 == .satisfied || $0 == .notApplicable || $0 == .notProvided || $0 == .unavailable } }
        var isRetryable: Bool { serverReportsSections && !isComplete && states.contains { $0 == .failed || $0 == .invalid } }

        enum CodingKeys: String, CodingKey {
            case revision, serverReportsSections = "server_reports_sections"
            case checklistContext = "checklist_context", orderDetails = "order_details", assembly, terms
        }
    }

    var missions: [String: Mission] = [:]
    /// Cache → order uid → when the server was asked (phone clock) for the newest copy in that
    /// cache on this phone, written by the bridge or by the screen from a live response.
    var observedAt: [DispatchOfflineOrderCache: [String: Date]] = [:]

    func observed(_ cache: DispatchOfflineOrderCache, _ orderUniqueId: String) -> Date? { observedAt[cache]?[orderUniqueId] }

    enum CodingKeys: String, CodingKey {
        case missions, observedAt = "observed_at"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        missions = try c.decodeIfPresent([String: Mission].self, forKey: .missions) ?? [:]
        let raw = try c.decodeIfPresent([String: [String: Date]].self, forKey: .observedAt) ?? [:]
        for (key, value) in raw { if let cache = DispatchOfflineOrderCache(rawValue: key) { observedAt[cache] = value } }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(missions, forKey: .missions)
        try c.encode(Dictionary(uniqueKeysWithValues: observedAt.map { ($0.key.rawValue, $0.value) }), forKey: .observedAt)
    }
}

final class DispatchOfflineFieldBridge {

    struct Report: Equatable {
        /// Missions (re)bridged in this pass.
        var bridgedMissionKeys: [String] = []
        /// Ready missions that are not field-ready after this pass (diagnostics).
        var incompleteMissionKeys: [String] = []
    }

    let store: DispatchOfflineMissionStore
    private let contexts: ChecklistContextStore
    private let agreements: TermsAgreementStore?
    private weak var writer: DispatchOfflineOrderCacheWriting?
    private let operations: () -> [SyncOperation]
    private let currentEmployee: () -> ChecklistContext.Employee?

    init(store: DispatchOfflineMissionStore,
         contexts: ChecklistContextStore,
         agreements: TermsAgreementStore? = nil,
         writer: DispatchOfflineOrderCacheWriting?,
         operations: @escaping () -> [SyncOperation],
         currentEmployee: @escaping () -> ChecklistContext.Employee?) {
        self.store = store
        self.contexts = contexts
        self.agreements = agreements
        self.writer = writer
        self.operations = operations
        self.currentEmployee = currentEmployee
    }

    // MARK: - Bridging

    /// Bridges every ready mission whose sections are not settled at its ready revision.
    /// Idempotent: a settled revision is never bridged again.
    @discardableResult
    func bridge(index: DispatchOfflineIndex) -> Report {
        let ops = operations()
        let employee = currentEmployee()
        let tenant = store.tenantKey
        var report = Report()

        store.updateFieldLedger { ledger in
            for entry in index.entries where entry.isReady {
                guard let revision = entry.readyRevision, let stored = store.readyPackage(for: entry) else { continue }
                if let done = ledger.missions[entry.missionKey], done.revision == revision, done.isSettled { continue }

                let package = stored.package
                let observed = stored.serverObservedAt ?? stored.cachedAt
                let sections = DispatchOfflinePackageSections.from(package)
                let orderUid = DispatchOfflinePackageContent.orderUniqueId(package)

                let contextState = bridgeContext(package, entry: entry, observed: stored.serverObservedAt,
                                                 operations: ops, employee: employee, tenant: tenant)
                let orderState = bridgeOrderDetails(package, sections: sections, orderUid: orderUid,
                                                    observed: observed, ledger: &ledger, tenant: tenant)
                let assemblyState = bridgeAssembly(package, leg: entry.leg, sections: sections, orderUid: orderUid,
                                                   observed: observed, ledger: &ledger, tenant: tenant)
                let termsState = bridgeTerms(package, leg: entry.leg, sections: sections, orderUid: orderUid,
                                             observed: observed, ledger: &ledger, tenant: tenant)
                ledger.missions[entry.missionKey] = DispatchOfflineFieldLedger.Mission(
                    revision: revision, serverReportsSections: sections != nil,
                    checklistContext: contextState, orderDetails: orderState, assembly: assemblyState, terms: termsState)
                report.bridgedMissionKeys.append(entry.missionKey)
            }

            report.incompleteMissionKeys = index.entries
                .filter { $0.isReady && !isFieldReady($0, ledger: ledger, operations: ops) }
                .map(\.missionKey).sorted()
        }
        return report
    }

    // MARK: - Readiness (Amendment A)

    /// Every required section is satisfied at the mission's ready revision, and its context is
    /// still usable (no local substitution/restart has superseded it since).
    func isFieldReady(_ entry: DispatchOfflineIndex.Entry) -> Bool {
        isFieldReady(entry, ledger: store.loadFieldLedger(), operations: operations())
    }

    /// The mission is at its manifest revision but a section the server reported failed (or a
    /// context the phone could not decode) is missing: re-request its package at the same revision.
    func needsSectionRepair(_ entry: DispatchOfflineIndex.Entry) -> Bool {
        needsSectionRepair(entry, ledger: store.loadFieldLedger())
    }

    /// Every mission of `index` that needs a same-revision repair download.
    func repairableMissionKeys(in index: DispatchOfflineIndex) -> Set<String> {
        let ledger = store.loadFieldLedger()
        return Set(index.entries.filter { needsSectionRepair($0, ledger: ledger) }.map(\.missionKey))
    }

    private func isFieldReady(_ entry: DispatchOfflineIndex.Entry, ledger: DispatchOfflineFieldLedger, operations ops: [SyncOperation]) -> Bool {
        guard entry.isReady, let revision = entry.readyRevision,
              let mission = ledger.missions[entry.missionKey], mission.revision == revision, mission.isComplete,
              let context = contexts.load(orderProductUniqueId: entry.orderProductUniqueId, leg: entry.leg, tenantKey: store.tenantKey)
        else { return false }
        return ChecklistContextFallbackPolicy.canServeOffline(context, equipmentHint: nil, strictUnit: false, operations: ops)
    }

    private func needsSectionRepair(_ entry: DispatchOfflineIndex.Entry, ledger: DispatchOfflineFieldLedger) -> Bool {
        guard entry.isCurrent, let revision = entry.readyRevision,
              let mission = ledger.missions[entry.missionKey], mission.revision == revision else { return false }
        return mission.isRetryable
    }

    // MARK: - Sections

    private func bridgeContext(_ package: JSONValue, entry: DispatchOfflineIndex.Entry, observed: Date?,
                               operations ops: [SyncOperation], employee: ChecklistContext.Employee?,
                               tenant: String) -> DispatchOfflineFieldLedger.SectionState {
        guard case .object(var object)? = package["checklist_context"] else { return .invalid }
        if let employee = employee, let json = JSONValue.parse(try? JSONEncoder().encode(employee)) {
            object["employee"] = json // P4-D5: the user signed in now
        }
        guard let data = try? JSONValue.object(object).serialized(), let context = try? ChecklistContext.decode(envelopeData: data),
              context.identity.orderProductUniqueId == entry.orderProductUniqueId, context.leg == entry.leg else { return .invalid }

        let superseded = EffectiveFieldState.supersededExecutionIds(in: ops)
        if superseded.contains(context.executionId) { return .blocked }
        if let discardedAt = EffectiveFieldState.lastDiscardAt(in: ops, orderProductUniqueId: entry.orderProductUniqueId),
           discardedAt > (observed ?? .distantPast) { return .blocked }

        if let existing = contexts.load(orderProductUniqueId: entry.orderProductUniqueId, leg: entry.leg, tenantKey: tenant),
           !superseded.contains(existing.executionId), Self.isFresher(existing, than: context) {
            return .satisfied
        }
        do {
            try contexts.save(context, tenantKey: tenant)
            return .satisfied
        } catch {
            return .pending
        }
    }

    private func bridgeOrderDetails(_ package: JSONValue, sections: DispatchOfflinePackageSections?, orderUid: String?,
                                    observed: Date, ledger: inout DispatchOfflineFieldLedger,
                                    tenant: String) -> DispatchOfflineFieldLedger.SectionState {
        guard let sections = sections, let writer = writer else { return .notProvided }
        switch sections.orderDetails {
        case .ok?:
            guard let uid = orderUid, let payload = DispatchOfflinePackageContent.orderDetails(package) else { return .invalid }
            // Both screens' caches, each against its own stamp: a live Order Details open never
            // stops the checklist screens' copy from being written (and vice versa).
            let written = [DispatchOfflineOrderCache.orderDetails, .checklistOrder].map {
                Self.write($0, payload, uid: uid, observed: observed, ledger: &ledger, writer: writer, tenant: tenant)
            }
            return written.allSatisfy { $0 } ? .satisfied : .pending
        case .notApplicable?:
            return .notApplicable
        case .failed?, .unavailable?, nil:
            return .failed
        }
    }

    private func bridgeAssembly(_ package: JSONValue, leg: ChecklistLeg, sections: DispatchOfflinePackageSections?, orderUid: String?,
                                observed: Date, ledger: inout DispatchOfflineFieldLedger,
                                tenant: String) -> DispatchOfflineFieldLedger.SectionState {
        guard leg == .delivery else { return .notApplicable }
        guard let sections = sections, let writer = writer else { return .notProvided }
        switch sections.assembly {
        case .ok?:
            guard let uid = orderUid, let envelope = DispatchOfflinePackageContent.assembly(package) else { return .invalid }
            return Self.write(.assembly, envelope, uid: uid, observed: observed, ledger: &ledger, writer: writer, tenant: tenant)
                ? .satisfied : .pending
        case .notApplicable?:
            return .notApplicable
        case .failed?, .unavailable?, nil:
            return .failed
        }
    }

    /// Phase 5: the order's frozen Terms agreement → TermsAgreementStore, Delivery only, and only
    /// when it VERIFIES (its identity recomputes and it is this package's order). A newer copy
    /// (a live fetch asked later) is never overwritten.
    private func bridgeTerms(_ package: JSONValue, leg: ChecklistLeg, sections: DispatchOfflinePackageSections?, orderUid: String?,
                             observed: Date, ledger: inout DispatchOfflineFieldLedger,
                             tenant: String) -> DispatchOfflineFieldLedger.SectionState {
        guard leg == .delivery else { return .notApplicable }
        guard let sections = sections, let status = sections.terms, let agreements = agreements else { return .notProvided }
        switch status {
        case .notApplicable: return .notApplicable
        case .unavailable: return .unavailable
        case .failed: return .failed
        case .ok:
            guard let uid = orderUid, let agreement = DispatchOfflinePackageContent.terms(package)?.agreement,
                  agreement.isVerified(forOrder: uid) else { return .invalid }
            if let newest = ledger.observed(.terms, uid), newest >= observed { return .satisfied }
            do {
                try agreements.save(agreement, tenantKey: tenant)
            } catch {
                return .pending
            }
            ledger.observedAt[.terms, default: [:]][uid] = observed
            return .satisfied
        }
    }

    /// Writes one cache unless a copy asked for at the same time or later is already there
    /// (true = the cache holds a copy at least this new).
    private static func write(_ cache: DispatchOfflineOrderCache, _ payload: JSONValue, uid: String, observed: Date,
                              ledger: inout DispatchOfflineFieldLedger, writer: DispatchOfflineOrderCacheWriting,
                              tenant: String) -> Bool {
        if let newest = ledger.observed(cache, uid), newest >= observed { return true }
        guard writer.write(cache, payload: payload, orderUniqueId: uid, tenantKey: tenant) else { return false }
        ledger.observedAt[cache, default: [:]][uid] = observed
        return true
    }

    /// A higher cycle always wins; within a cycle, the later server snapshot wins.
    static func isFresher(_ existing: ChecklistContext, than incoming: ChecklistContext) -> Bool {
        if existing.identity.cycle != incoming.identity.cycle { return existing.identity.cycle > incoming.identity.cycle }
        guard let a = serverDate(existing.serverTime), let b = serverDate(incoming.serverTime) else { return false }
        return a > b
    }

    private static func serverDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
