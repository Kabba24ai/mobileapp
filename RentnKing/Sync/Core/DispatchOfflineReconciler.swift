//
//  DispatchOfflineReconciler.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Dispatch offline mission cache — Phase 3. The ONE coordinator every
//  trigger goes through (silent wake, launch, login, foreground, Dispatch
//  open / pull-to-refresh, network restoration). There is no timer: it only
//  runs when one of those events asks.
//
//  One run:
//    1. GET the manifest — the complete company-wide working set.
//    2. Diff against the durable index; adopt any valid file already on disk
//       (an interrupted run) instead of downloading it again.
//    3. Commit the new membership (missions absent from the manifest leave
//       the active set; missions whose download is still pending keep their
//       previous valid package, stale, or are known-but-not-ready).
//    4. POST packages for new/changed missions only, ≤100 per request, one
//       request at a time; each valid package is written to its own
//       immutable file, then the index is committed — per-mission atomic,
//       so one bad mission never blocks the others.
//    5. Retire / purge unreferenced package files (D7).
//  A killed run is simply resumed by the next trigger: the durable index is
//  always consistent, and files already downloaded are adopted.
//
//  Coalescing: while a run is in flight, new requests wait for it. When it
//  ends they receive its result — or, if it failed or a waiting wake names a
//  different manifest revision, exactly ONE follow-up run serves them all.
//
//  Session binding: a run acts for the session (tenant + credential) it
//  started under. The API client re-reads the base URL and token on every
//  request, so before each request AND when each answer arrives the run
//  re-checks the current session; on any change (logout, another company,
//  another employee) it stops with no write and no follow-up. One tenant's
//  data can never land in another tenant's store.
//

import Foundation

enum DispatchOfflineTrigger: Equatable {
    case wake(revision: String?)
    case launch
    case loginCompleted
    case foreground
    case dispatchScreenOpened
    case manualRefresh
    case networkRestored

    /// Frequent, low-urgency triggers absorbed by the freshness window and the failure cooldown.
    var isThrottled: Bool { self == .foreground || self == .dispatchScreenOpened }
}

enum DispatchOfflineFailure: Equatable {
    case offline
    case unauthenticated
    case updateRequired
    case server(Int)
    case invalidManifest
    case storage
    /// The signed-in session changed mid-run; the run stopped without writing.
    case sessionChanged
}

/// Who a run acts for: the tenant (login api_url) AND the signed-in credential.
struct DispatchOfflineSession: Equatable {
    let tenantKey: String
    /// Opaque identity of the credential (changes on every sign-in) — never the token itself.
    let credential: String
}

/// The iOS background-fetch answer, without UIKit.
enum DispatchOfflineBackgroundResult: Equatable {
    case newData, noData, failed
}

struct DispatchOfflineReconcileResult: Equatable {
    enum Skip: Equatable {
        case noSession, alreadyCurrent, fresh, coolingDown
    }

    enum Status: Equatable {
        /// The manifest and every needed package were applied.
        case completed
        /// The manifest was applied; some packages could not be (see failedMissionKeys / packageFailure).
        case partial
        /// Nothing was applied; the store is unchanged.
        case failed(DispatchOfflineFailure)
        case skipped(Skip)
    }

    var status: Status
    /// The presentable working set (membership or any package revision) changed on disk.
    var changed: Bool = false
    var manifestRevision: String? = nil
    var downloaded: Int = 0
    var adopted: Int = 0
    var removed: Int = 0
    var failedMissionKeys: [String] = []
    /// Why package downloads stopped early, when they did.
    var packageFailure: DispatchOfflineFailure? = nil

    var backgroundResult: DispatchOfflineBackgroundResult {
        if changed { return .newData }
        switch status {
        case .failed, .partial:     return .failed
        case .completed, .skipped:  return .noData
        }
    }

    var isFailure: Bool {
        switch status {
        case .failed, .partial: return true
        case .completed, .skipped: return false
        }
    }

    var sessionChanged: Bool {
        status == .failed(.sessionChanged) || packageFailure == .sessionChanged
    }
}

final class DispatchOfflineReconciler {
    typealias Completion = (DispatchOfflineReconcileResult) -> Void

    /// A foreground / Dispatch-open within this many seconds of a successful manifest is already fresh.
    static let freshnessWindow: TimeInterval = 20

    /// Throttled triggers wait 30 s after one failure, doubling to at most 5 minutes.
    static func cooldown(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        return min(30 * pow(2, Double(min(failures, 10) - 1)), 300)
    }

    let store: DispatchOfflineMissionStore
    private let httpClient: SyncHTTPClient
    private let session: () -> DispatchOfflineSession?
    private let retainedOrderProducts: () -> Set<String>
    private let now: () -> Date

    /// Called on the reconciler's queue after every successful commit (the App refreshes the Dispatch screen).
    var onCommit: ((DispatchOfflineIndex) -> Void)?
    var logger: ((String) -> Void)?

    private let queue = DispatchQueue(label: "ai.kabba.dispatch-offline.reconciler")
    private var running = false
    private var pending: [(trigger: DispatchOfflineTrigger, completion: Completion?)] = []
    private var consecutiveFailures = 0
    private var lastFailureAt: Date?

    /// `session` is nil when nobody is signed in; a session for another tenant counts as none.
    init(httpClient: SyncHTTPClient,
         store: DispatchOfflineMissionStore,
         session: @escaping () -> DispatchOfflineSession?,
         retainedOrderProducts: @escaping () -> Set<String>,
         now: @escaping () -> Date = Date.init) {
        self.httpClient = httpClient
        self.store = store
        self.session = session
        self.retainedOrderProducts = retainedOrderProducts
        self.now = now
    }

    // MARK: - Requests

    func request(_ trigger: DispatchOfflineTrigger, completion: Completion? = nil) {
        queue.async { self.enqueue(trigger, completion) }
    }

    private var currentSession: DispatchOfflineSession? {
        guard let current = session(), current.tenantKey == store.tenantKey else { return nil }
        return current
    }

    private func enqueue(_ trigger: DispatchOfflineTrigger, _ completion: Completion?) {
        guard currentSession != nil else {
            // No authenticated session: no request, cache untouched (D6).
            completion?(DispatchOfflineReconcileResult(status: .skipped(.noSession)))
            return
        }
        if running {
            pending.append((trigger, completion))
            return
        }
        if let skip = skipReason(for: trigger) {
            logger?("[dispatch-offline] \(trigger) skipped: \(skip)")
            completion?(DispatchOfflineReconcileResult(status: .skipped(skip), manifestRevision: store.loadIndex().manifestRevision))
            return
        }
        start(trigger: trigger, waiters: [completion])
    }

    private func skipReason(for trigger: DispatchOfflineTrigger) -> DispatchOfflineReconcileResult.Skip? {
        let index = store.loadIndex()
        if case .wake(let revision?) = trigger, !revision.isEmpty,
           index.everCommitted, index.manifestRevision == revision, index.isFullyCurrent {
            return .alreadyCurrent
        }
        guard trigger.isThrottled else { return nil }
        let at = now()
        if let last = index.lastManifestAt, at.timeIntervalSince(last) < Self.freshnessWindow, at >= last {
            return .fresh
        }
        if consecutiveFailures > 0, let failedAt = lastFailureAt,
           at.timeIntervalSince(failedAt) < Self.cooldown(afterFailures: consecutiveFailures) {
            return .coolingDown
        }
        return nil
    }

    private func start(trigger: DispatchOfflineTrigger, waiters: [Completion?]) {
        running = true
        logger?("[dispatch-offline] reconcile (\(trigger))")
        runOnce { result in
            // On the queue. Failed AND partial runs back off throttled triggers (spec §15).
            if result.isFailure, !result.sessionChanged {
                self.consecutiveFailures += 1
                self.lastFailureAt = self.now()
            } else if !result.isFailure {
                self.consecutiveFailures = 0
                self.lastFailureAt = nil
            }
            waiters.forEach { $0?(result) }

            let followers = self.pending
            self.pending = []
            if !followers.isEmpty, Self.needsFollowUp(after: result, for: followers.map(\.trigger)) {
                self.start(trigger: followers[0].trigger, waiters: followers.map(\.completion))
            } else {
                followers.forEach { $0.completion?(result) }
                self.running = false
            }
        }
    }

    /// Triggers that arrived mid-run are served by that run — unless it failed, a partial
    /// run is followed by a repair trigger (wake, pull-to-refresh, login, network, launch),
    /// or a wake names a manifest revision the run did not see. A run stopped by a session
    /// change is never followed up: its waiters belonged to the old session.
    static func needsFollowUp(after result: DispatchOfflineReconcileResult, for triggers: [DispatchOfflineTrigger]) -> Bool {
        if result.sessionChanged { return false }
        if case .failed = result.status { return true }
        if case .partial = result.status, triggers.contains(where: { !$0.isThrottled }) { return true }
        return triggers.contains { trigger in
            guard case .wake(let revision) = trigger else { return false }
            guard let revision = revision, !revision.isEmpty else { return true }
            return revision != result.manifestRevision
        }
    }

    // MARK: - One run (always on the queue)

    private func runOnce(_ finish: @escaping Completion) {
        guard let owner = currentSession else {
            return finish(.init(status: .failed(.sessionChanged)))
        }
        let startIndex = store.loadIndex()
        httpClient.perform(DispatchOfflineAPI.manifestRequest()) { result in
            self.queue.async {
                // The answer may belong to a session that has since ended — discard it unread.
                guard self.currentSession == owner else {
                    return finish(.init(status: .failed(.sessionChanged)))
                }
                self.applyManifest(result, owner: owner, startIndex: startIndex, finish: finish)
            }
        }
    }

    private func applyManifest(_ result: SyncHTTPResult, owner: DispatchOfflineSession,
                               startIndex: DispatchOfflineIndex, finish: @escaping Completion) {
        let manifest: DispatchOfflineManifest
        switch result {
        case .failure(let error):
            return finish(.init(status: .failed(Self.failure(statusCode: error.statusCode, transport: true))))
        case .response(let response):
            guard response.isSuccessStatus else {
                return finish(.init(status: .failed(Self.failure(statusCode: response.statusCode, transport: false))))
            }
            guard let decoded = try? DispatchOfflineManifest.decode(envelope: response.body) else {
                return finish(.init(status: .failed(.invalidManifest)))
            }
            manifest = decoded
        }

        let at = now()
        var index = startIndex
        index.manifestRevision = manifest.revision
        index.throughDate = manifest.throughDate
        index.lastManifestAt = at
        index.everCommitted = true

        var outcome = DispatchOfflineReconcileResult(status: .completed, manifestRevision: manifest.revision)
        let manifestKeys = Set(manifest.missions.map(\.missionKey))
        outcome.removed = startIndex.entries.filter { !manifestKeys.contains($0.missionKey) }.count

        index.entries = manifest.missions.map { m in
            var entry = DispatchOfflineIndex.Entry(missionKey: m.missionKey, orderProductUniqueId: m.orderProductUniqueId,
                                                   leg: m.leg, effectiveDate: m.effectiveDate, serverRevision: m.revision,
                                                   readyRevision: nil, packageFile: nil)
            // Keep the previous valid package (it stays presentable while a newer one is pending).
            if let old = startIndex.entry(m.missionKey), store.readyPackage(for: old) != nil {
                entry.readyRevision = old.readyRevision
                entry.packageFile = old.packageFile
            }
            // An interrupted run may already have written exactly this revision.
            if entry.readyRevision != m.revision,
               let file = store.validPackageFile(missionKey: m.missionKey, orderProductUniqueId: m.orderProductUniqueId,
                                                 leg: m.leg, revision: m.revision) {
                entry.readyRevision = m.revision
                entry.packageFile = file
                outcome.adopted += 1
            }
            return entry
        }

        do {
            index.committedAt = at
            try store.commit(index)
        } catch {
            return finish(.init(status: .failed(.storage)))
        }
        onCommit?(index)

        let toDownload = manifest.missions.filter { index.entry($0.missionKey)?.readyRevision != $0.revision }
        let batches = DispatchOfflineAPI.packagesRequests(for: toDownload)
        download(batches[...], owner: owner, index: index, startIndex: startIndex, outcome: outcome, finish: finish)
    }

    private func download(_ batches: ArraySlice<SyncHTTPRequest>,
                          owner: DispatchOfflineSession,
                          index: DispatchOfflineIndex,
                          startIndex: DispatchOfflineIndex,
                          outcome: DispatchOfflineReconcileResult,
                          finish: @escaping Completion) {
        guard let request = batches.first else {
            return complete(index: index, startIndex: startIndex, outcome: outcome, finish: finish)
        }
        let requestedKeys = Self.requestedKeys(request)
        // Never send a request for a session that has ended (the client would use the new one's URL + token).
        guard currentSession == owner else {
            return abortForSessionChange(startIndex: startIndex, outcome: outcome, finish: finish)
        }
        httpClient.perform(request) { result in
            self.queue.async {
                guard self.currentSession == owner else {
                    return self.abortForSessionChange(startIndex: startIndex, outcome: outcome, finish: finish)
                }
                var index = index
                var outcome = outcome
                var stop = false

                switch result {
                case .failure(let error):
                    outcome.packageFailure = Self.failure(statusCode: error.statusCode, transport: true)
                    outcome.failedMissionKeys += batches.flatMap(Self.requestedKeys)
                    stop = true
                case .response(let response) where !response.isSuccessStatus:
                    let failure = Self.failure(statusCode: response.statusCode, transport: false)
                    outcome.packageFailure = failure
                    if failure == .unauthenticated || failure == .updateRequired {
                        outcome.failedMissionKeys += batches.flatMap(Self.requestedKeys)
                        stop = true
                    } else {
                        outcome.failedMissionKeys += requestedKeys
                    }
                case .response(let response):
                    if let decoded = try? DispatchOfflinePackagesResponse.decode(envelope: response.body, requested: Set(requestedKeys)) {
                        var satisfied = Set<String>()
                        for package in decoded.packages {
                            do {
                                let file = try self.store.writePackage(package, cachedAt: self.now())
                                if let i = index.entries.firstIndex(where: { $0.missionKey == package.missionKey }) {
                                    // A package newer than the manifest is the newest known truth.
                                    index.entries[i].readyRevision = package.revision
                                    index.entries[i].serverRevision = package.revision
                                    index.entries[i].packageFile = file
                                    outcome.downloaded += 1
                                    satisfied.insert(package.missionKey)
                                }
                            } catch {
                                // Not written → not ready; the previous package (if any) stays.
                            }
                        }
                        let inactive = Set(decoded.notActive)
                        index.entries.removeAll { inactive.contains($0.missionKey) }
                        outcome.removed += inactive.count
                        outcome.failedMissionKeys += requestedKeys.filter { !satisfied.contains($0) && !inactive.contains($0) }
                    } else {
                        outcome.failedMissionKeys += requestedKeys
                    }
                    do {
                        try self.store.commit(index)
                        self.onCommit?(index)
                    } catch {
                        outcome.packageFailure = .storage
                        outcome.failedMissionKeys += batches.dropFirst().flatMap(Self.requestedKeys)
                        index = self.store.loadIndex()
                        stop = true
                    }
                }

                if stop {
                    self.complete(index: index, startIndex: startIndex, outcome: outcome, finish: finish)
                } else {
                    self.download(batches.dropFirst(), owner: owner, index: index, startIndex: startIndex, outcome: outcome, finish: finish)
                }
            }
        }
    }

    /// The session changed mid-download: stop — no write, no cleanup, no follow-up.
    private func abortForSessionChange(startIndex: DispatchOfflineIndex,
                                       outcome: DispatchOfflineReconcileResult,
                                       finish: Completion) {
        var outcome = outcome
        outcome.status = .partial
        outcome.packageFailure = .sessionChanged
        outcome.changed = startIndex.presentableSignature != store.loadIndex().presentableSignature
        logger?("[dispatch-offline] stopped: the signed-in session changed")
        finish(outcome)
    }

    private func complete(index: DispatchOfflineIndex,
                          startIndex: DispatchOfflineIndex,
                          outcome: DispatchOfflineReconcileResult,
                          finish: Completion) {
        var outcome = outcome
        let collected = store.collectGarbage(index, retainingOrderProducts: retainedOrderProducts(), now: now())
        var final = index
        if collected != index, (try? store.commit(collected)) != nil {
            final = collected
        }
        outcome.failedMissionKeys = Array(Set(outcome.failedMissionKeys)).sorted()
        if !outcome.failedMissionKeys.isEmpty || outcome.packageFailure != nil {
            outcome.status = .partial
        }
        outcome.changed = startIndex.presentableSignature != final.presentableSignature
        logger?("[dispatch-offline] done: \(outcome.status) changed=\(outcome.changed) downloaded=\(outcome.downloaded) adopted=\(outcome.adopted) removed=\(outcome.removed) failed=\(outcome.failedMissionKeys.count)")
        finish(outcome)
    }

    // MARK: - Helpers

    private static func requestedKeys(_ request: SyncHTTPRequest) -> [String] {
        (request.jsonBody?["missions"]?.arrayValue ?? []).compactMap { mission in
            guard let id = mission["order_product_unique_id"]?.stringValue,
                  let legRaw = mission["leg"]?.stringValue, let leg = ChecklistLeg(rawValue: legRaw) else { return nil }
            return DispatchOfflineValidation.missionKey(orderProductUniqueId: id, leg: leg)
        }
    }

    private static func failure(statusCode: Int?, transport: Bool) -> DispatchOfflineFailure {
        switch statusCode {
        case 401?: return .unauthenticated
        case 426?: return .updateRequired
        case let status? where !transport: return .server(status)
        default: return .offline
        }
    }
}
