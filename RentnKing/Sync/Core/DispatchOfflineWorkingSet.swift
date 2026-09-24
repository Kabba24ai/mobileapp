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
    /// The legacy Dispatch feed row (dispatch.row) plus the derived overdue flags —
    /// exactly what SchedulesModel maps.
    let row: JSONValue
}

enum DispatchOfflinePresentation: Equatable {
    struct Freshness: Equatable {
        let lastManifestAt: Date?
        /// Last calendar day the downloaded working set covers.
        let throughDate: String?
        let staleCount: Int
        let pendingCount: Int
    }

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
        for entry in index.entries {
            guard let stored = store.readyPackage(for: entry), var row = stored.row, case .object = row else { continue }
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
                                           isOverdue: overdue, isStale: entry.isStale, row: row))
        }
        rows.sort { ($0.sortKey, $0.missionKey) < ($1.sortKey, $1.missionKey) }

        return .ready(rows: rows, freshness: .init(lastManifestAt: index.lastManifestAt,
                                                   throughDate: index.throughDate,
                                                   staleCount: index.entries.filter(\.isStale).count,
                                                   pendingCount: index.entries.filter { !$0.isReady }.count))
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
        /// Never downloaded and the first download failed while online: use the live feed.
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

    static func outcome(notDownloaded: Bool, failed: Bool, online: Bool) -> Outcome {
        if notDownloaded {
            if !online { return .showNotDownloaded }
            return failed ? .fallBackToFeed : .current
        }
        if !online { return .flagOffline }
        return failed ? .flagNotCurrent : .current
    }

    /// A pure filter change makes no request — unless nothing was ever downloaded and the
    /// phone is online (the first download settles the loading state).
    static func filterChangeNeedsFirstDownload(notDownloaded: Bool, online: Bool) -> Bool {
        notDownloaded && online
    }
}
