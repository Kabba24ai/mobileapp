//
//  DispatchOfflineWorkingSet.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Dispatch offline mission cache — Phase 3. The Dispatch screen's LOCAL
//  presentation source: the durable company-wide working set, filtered on
//  the phone by driver, leg, date and category. Nothing here touches the
//  network — switching the driver filter offline costs nothing.
//
//  "Not downloaded yet" (this tenant never completed a reconciliation) is a
//  different state from "downloaded, and there is no Dispatch work".
//

import Foundation

struct DispatchOfflineQuery: Equatable {
    enum Legs: Equatable { case all, delivery, `return` }
    enum Dates: Equatable { case today, all }

    /// nil = All Drivers (the whole company).
    var selectedDriverId: Int? = nil
    var legs: Legs = .all
    var dates: Dates = .today
    var categoryId: Int? = nil
}

struct DispatchOfflineRow: Equatable {
    let missionKey: String
    let orderProductUniqueId: String
    let leg: ChecklistLeg
    let effectiveDate: String
    /// The package revision this row was rendered from (local screen edits are keyed to it).
    let revision: String
    let sortKey: String
    let isOverdue: Bool
    /// Shown from an older package while the newest one could not be downloaded yet.
    let isStale: Bool
    /// When the server was last asked for this mission and answered with exactly this content —
    /// its package download, or a later manifest confirming the same revision (nil = unknown).
    /// Local driver actions the server confirmed after it are not in the row yet (review F2).
    let serverObservedAt: Date?
    /// The legacy Dispatch feed row (dispatch.row) plus the derived overdue flags —
    /// exactly what SchedulesModel maps.
    let row: JSONValue
}

enum DispatchOfflinePresentation: Equatable {
    struct Freshness: Equatable {
        let lastManifestAt: Date?
        /// Last calendar day the downloaded working set covers.
        let throughDate: String?
        /// Active missions shown from an older package (the newer one is not downloaded yet).
        let staleCount: Int
        /// Active missions the phone cannot show: never downloaded, or the file is unreadable.
        let pendingCount: Int

        /// Every active mission is shown at its manifest revision (review F1).
        var isComplete: Bool { staleCount == 0 && pendingCount == 0 }
    }

    /// Never downloaded, or active missions without one presentable package yet.
    case notDownloaded
    case ready(rows: [DispatchOfflineRow], freshness: Freshness)
}

enum DispatchOfflineWorkingSet {

    static func present(store: DispatchOfflineMissionStore,
                        query: DispatchOfflineQuery,
                        operations: [SyncOperation],
                        today: String) -> DispatchOfflinePresentation {
        let index = store.loadIndex()
        guard index.everCommitted else { return .notDownloaded }

        let overlay = EffectiveFieldState.CompletionOverlay.from(operations)
        var rows: [DispatchOfflineRow] = []
        var stale = 0, missing = 0
        for entry in index.entries {
            guard let stored = store.readyPackage(for: entry), var row = stored.row, case .object = row else {
                missing += 1 // counted across the whole working set, whatever the filters show
                continue
            }
            if entry.isStale { stale += 1 }
            let isDelivery = entry.leg == .delivery

            switch query.legs {
            case .delivery where !isDelivery, .return where isDelivery: continue
            default: break
            }
            if query.dates == .today, entry.effectiveDate > today { continue }
            if let category = query.categoryId,
               !(row["category_ids"]?.arrayValue ?? []).contains(where: { $0.intValue == category }) { continue }
            // The ACTIVE leg's employee decides membership (same predicate as the feed + card).
            guard DispatchWorkload.orderRowBelongs(selectedDriverId: query.selectedDriverId,
                                                   isDelivered: !isDelivery,
                                                   deliveryEmployeeId: row["delivery_employee"]?["id"]?.intValue,
                                                   pickupEmployeeId: row["pickup_employee"]?["id"]?.intValue) else { continue }
            // Completed on THIS phone (Sync Engine evidence) → out of the working queue.
            if overlay.isLegLocallyCompleted(orderProductUniqueId: entry.orderProductUniqueId, isDeliveryLeg: isDelivery) { continue }

            // Day-dependent flags are derived here, never shipped (they would churn revisions).
            let overdue = !entry.effectiveDate.isEmpty && entry.effectiveDate < today
            row = row.setting("is_delivery_overdue", .bool(isDelivery && overdue))
                     .setting("is_pickup_overdue", .bool(!isDelivery && overdue))

            rows.append(DispatchOfflineRow(missionKey: entry.missionKey, orderProductUniqueId: entry.orderProductUniqueId,
                                           leg: entry.leg, effectiveDate: entry.effectiveDate,
                                           revision: stored.revision,
                                           sortKey: row["sort_key"]?.stringValue ?? DispatchWorkload.openEndedSortKey,
                                           isOverdue: overdue, isStale: entry.isStale,
                                           serverObservedAt: [stored.serverObservedAt, entry.confirmedAt].compactMap { $0 }.max(),
                                           row: row))
        }
        // Review 3: a manifest by itself is not usable Dispatch. Active missions with not one
        // presentable package = still not downloaded (the first download failed or is running),
        // never an empty downloaded list. A genuinely empty manifest IS a real empty Dispatch.
        if !index.entries.isEmpty, missing == index.entries.count { return .notDownloaded }

        rows.sort { ($0.sortKey, $0.missionKey) < ($1.sortKey, $1.missionKey) }

        return .ready(rows: rows, freshness: .init(lastManifestAt: index.lastManifestAt,
                                                   throughDate: index.throughDate,
                                                   staleCount: stale,
                                                   pendingCount: missing))
    }

    /// "YYYY-MM-DD" of the phone's calendar day — the Today filter's "today".
    static func localDateString(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// D3: the small factual line shown offline under Pending + All.
    static func offlineAllLine(throughDate: String?) -> String {
        let base = "Offline — showing downloaded Dispatch"
        guard let raw = throughDate, DispatchOfflineValidation.isDate(raw) else { return base }
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = TimeZone(identifier: "UTC")
        parse.dateFormat = "yyyy-MM-dd"
        guard let date = parse.date(from: raw) else { return base }
        let show = DateFormatter()
        show.locale = Locale(identifier: "en_US_POSIX")
        show.timeZone = TimeZone(identifier: "UTC")
        show.dateFormat = "MMM d"
        return "\(base) through \(show.string(from: date))"
    }
}

private extension JSONValue {
    func setting(_ key: String, _ value: JSONValue) -> JSONValue {
        guard case .object(var object) = self else { return self }
        object[key] = value
        return .object(object)
    }
}

/// The Dispatch screen's decisions, kept pure so they are unit-tested (the view controller
/// only applies them).
enum DispatchOfflineScreenPolicy {
    enum Source: Equatable {
        /// Order legs from the durable cache only.
        case offlineCache
        /// The cached horizon first; online, the live All feed for a named driver replaces it (D3).
        case cacheThenFeed
        /// The existing online feed (Completed, Search).
        case feed
    }

    static func source(pending: Bool, search: String, day: String, selectedDriverId: String) -> Source {
        guard pending, search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .feed }
        // All Drivers stays on the cache (D5): the mixed feed scopes a missing driver to the
        // signed-in user and would replace the whole company with one person's jobs.
        guard day == "All", !selectedDriverId.isEmpty else { return .offlineCache }
        return .cacheThenFeed
    }

    enum Outcome: Equatable {
        /// Never downloaded. Online after a failed first download: the live feed takes over.
        /// Offline with a feed snapshot on the phone: show that snapshot (the screen keeps
        /// listening, so the outcome after reconnecting reaches the live feed).
        case fallBackToFeed
        /// Never downloaded and offline: say so (never "no results").
        case showNotDownloaded
        /// The shown list is the last saved one — flag it.
        case flagNotCurrent
        /// Offline: flag the saved list (All names the last downloaded day).
        case flagOffline
        /// Reconciled: no header.
        case current
    }

    /// How the screen settles for what is on disk now and the last answer. A failed or partial
    /// run — or ANY active mission missing, stale or failed to download, whatever the last
    /// answer said — is never presented as current (review F1).
    ///
    /// `hasFeedSnapshot`: this phone holds a last live Dispatch list (the feed snapshot). With
    /// nothing downloaded and no connection it beats an empty "not downloaded" screen (release
    /// 2026-09-30) — the only offline list while a server has no offline endpoints.
    static func outcome(presentation: DispatchOfflinePresentation, failed: Bool, online: Bool,
                        hasFeedSnapshot: Bool = false) -> Outcome {
        guard case .ready(_, let freshness) = presentation else {
            if !online { return hasFeedSnapshot ? .fallBackToFeed : .showNotDownloaded }
            return failed ? .fallBackToFeed : .current
        }
        if !online { return .flagOffline }
        return (failed || !freshness.isComplete) ? .flagNotCurrent : .current
    }

    /// Nothing was ever downloaded, there is no connection, and the phone holds the last live
    /// Dispatch list: show that list (flagged not current) instead of "not downloaded" — what
    /// 1.0.22 showed offline, and all there is while the server has no offline endpoints.
    static func offlineShowsFeedSnapshot(presentation: DispatchOfflinePresentation, online: Bool, hasFeedSnapshot: Bool) -> Bool {
        presentation == .notDownloaded && !online && hasFeedSnapshot
    }

    /// The screen fell back to the live feed because nothing was downloaded; once the working set
    /// is presentable it returns to the normal cached Dispatch (review 3).
    static func leavesFeedFallback(presentation: DispatchOfflinePresentation) -> Bool {
        if case .ready = presentation { return true }
        return false
    }

    /// Whether an answer means the list may not be current: a failed or partial run, or a
    /// request skipped because the last run failed (cooling down) or nobody is signed in.
    static func indicatesFailure(_ result: DispatchOfflineReconcileResult) -> Bool {
        switch result.status {
        case .failed, .partial: return true
        case .completed: return false
        case .skipped(let why): return why == .coolingDown || why == .noSession
        }
    }

    /// Whether a finished run is an outcome a Dispatch screen should settle on: never a skip
    /// (the requester settles those itself), never a run stopped by a session change (it is
    /// the old session's — review F3).
    static func postsReconcileOutcome(_ result: DispatchOfflineReconcileResult) -> Bool {
        if case .skipped = result.status { return false }
        return !result.sessionChanged
    }

    /// Only the company that is signed in now applies an outcome (review F3).
    static func appliesReconcileOutcome(fromTenant: String?, currentTenant: String?) -> Bool {
        guard let from = fromTenant, let current = currentTenant else { return false }
        return from == current
    }

    /// A pure filter change makes no request — unless nothing was ever downloaded and the
    /// phone is online (the first download settles the loading state).
    static func filterChangeNeedsFirstDownload(notDownloaded: Bool, online: Bool) -> Bool {
        notDownloaded && online
    }
}

/// Review F4: the presentation scope a live-feed / Manual Dispatch request was made for —
/// everything that decides which rows the screen shows.
struct DispatchFeedScope: Equatable {
    var pending: Bool
    var scheduleType: String
    var dateFilter: String
    var driverId: String
    var categoryId: String
    /// Trimmed: surrounding whitespace is no different search.
    var search: String
    var transportMode: String

    init(pending: Bool, scheduleType: String, dateFilter: String, driverId: String,
         categoryId: String, search: String, transportMode: String) {
        self.pending = pending
        self.scheduleType = scheduleType
        self.dateFilter = dateFilter
        self.driverId = driverId
        self.categoryId = categoryId
        self.search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transportMode = transportMode
    }
}

/// Review F4: binds every live-feed / Manual Dispatch request to the scope AND request
/// generation that started it. A new list (screen open, refresh, any filter or search
/// change) restarts the generation, so every answer still in flight becomes obsolete; later
/// pages of the same list share it. An obsolete answer is discarded — it never writes a cache
/// slot and never replaces the scope on screen. Main thread only (the Dispatch screen).
final class DispatchFeedRequests {
    struct Ticket: Equatable {
        let generation: Int
        let scope: DispatchFeedScope
        /// When the request was sent: the answer's server truth is at least this new (F2).
        let startedAt: Date
    }

    private(set) var generation = 0

    func restart() { generation += 1 }

    func ticket(for scope: DispatchFeedScope, at startedAt: Date = Date()) -> Ticket {
        Ticket(generation: generation, scope: scope, startedAt: startedAt)
    }

    func accepts(_ ticket: Ticket, currentScope: DispatchFeedScope) -> Bool {
        ticket.generation == generation && ticket.scope == currentScope
    }
}
