//
//  DispatchWorkload.swift
//  RentnKing — Sync Core layer (Foundation only, no UIKit)
//
//  Dispatch parity (Phase 6A blocker): the mixed Dispatch contract types and
//  the pure workload logic behind the Dispatch screen — Manual Dispatch DTO,
//  status lifecycle, and the sort_key weave that renders a driver's mixed
//  workday (order legs + manual tasks) in the exact order the web Dispatch
//  board shows it.
//
//  Server contract (POST orders/schedules/dispatch, include_manual=1):
//    orders[]       — paginated order-product rows (legacy shape + additive
//                     dispatch_source / dispatch_item_id / fulfillment_leg /
//                     sort_key)
//    manual_jobs[]  — page 1 only: the driver's open Manual Dispatch tasks in
//                     the shared ManualDispatchTaskPayload shape
//  Every item's sort_key is the web board's unified route-sequence key:
//  "YYYY-MM-DD|NNNNN" (effective date primary, zero-padded priority secondary,
//  NULLs last) — plain lexicographic comparison reproduces the board order.
//
//  This file is deliberately in Sync/Core so it compiles into the
//  KabbaSyncCoreTests logic bundle and `swift test` — the weave, the DTO
//  decode against the shared Laravel fixtures, and the reconciliation rules
//  are all executable without an app host.
//

import Foundation

// MARK: - Manual Dispatch status lifecycle

/// The Manual Dispatch lifecycle, mirroring the server enum
/// (App\Enums\Dispatch\ManualDispatchStatus). Values are the human labels the
/// API sends/accepts verbatim.
public enum DispatchManualStatus {
    public static let pending   = "Pending"
    public static let assigned  = "Assigned"
    public static let onMyWay   = "On My Way"
    public static let arrived   = "Arrived"
    public static let completed = "Completed"
    public static let cancelled = "Cancelled"

    /// The single forward action offered on a card, given the current status.
    /// Pending advances by being assigned a driver on the web side, so the app
    /// only progresses Assigned → On My Way → Arrived → Completed.
    public static func next(after status: String?) -> String? {
        switch status {
        case assigned: return onMyWay
        case onMyWay:  return arrived
        case arrived:  return completed
        default:       return nil
        }
    }

    /// A non-terminal task can still be cancelled.
    public static func isTerminal(_ status: String?) -> Bool {
        return status == completed || status == cancelled
    }
}

// MARK: - Manual Dispatch DTO

/// One Manual Dispatch task as served by the mixed feed's manual_jobs (and by
/// POST dispatch/manual — the shared ManualDispatchTaskPayload shape). Every
/// field is optional by design: a manual task has NO order, product, customer
/// or checklist, and the DTO must never drop a task because an optional field
/// is absent.
public struct DispatchManualJob: Codable, Equatable {
    public struct EquipmentRef: Codable, Equatable {
        public var id: Int?
        public var equipment_id: String?
        public var name: String?
    }

    public struct StoreRef: Codable, Equatable {
        public var id: Int?
        public var name: String?
    }

    public struct DriverRef: Codable, Equatable {
        public var id: Int?
        public var name: String?
    }

    public var unique_id: String?
    public var is_manual: Bool?
    public var type: String?            // e.g. "Equipment Drop-Off" (type_label)
    public var description: String?     // task / description snapshot
    public var status: String?          // Pending | Assigned | On My Way | Arrived | Completed | Cancelled
    public var priority: Int?

    public var date: String?            // formatted dispatch date
    public var time: String?            // dispatch time (nullable)

    public var location_name: String?
    public var address: String?         // full address (server: full_address)
    public var city: String?
    public var state: String?
    public var zip_code: String?
    public var contact_name: String?
    public var phone: String?
    public var instructions: String?
    public var store: String?           // originating store name

    public var task_context: String?
    public var equipment: EquipmentRef?
    public var location_source: String?
    public var supplier_name: String?

    public var schedule_state: String?
    public var is_return: Bool?
    public var dispatch_subtype: String?   // 'inventory_transfer' badges the store-moving task
    public var origin_store: StoreRef?
    public var destination_store: StoreRef?

    // Mixed-feed identity (additive contract keys)
    public var dispatch_source: String?    // "manual"
    public var dispatch_item_id: String?   // "manual:MDT-…"
    public var sort_key: String?           // "YYYY-MM-DD|NNNNN"
    public var driver: DriverRef?

    public init() {}

    /// "City, ST" convenience for card subtitles.
    public var locationLine: String {
        return [city, state].compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
    }

    /// Decodes the feed's manual_jobs array. Tolerant by construction — a
    /// malformed individual entry is skipped, never the whole list.
    public static func decodeList(fromJSONArray array: [[String: Any]]) -> [DispatchManualJob] {
        let decoder = JSONDecoder()
        return array.compactMap { dict in
            guard JSONSerialization.isValidJSONObject(dict),
                  let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(DispatchManualJob.self, from: data)
        }
    }
}

// MARK: - Mixed workday weave

/// A reference into one of the two source arrays that back the Dispatch table.
public enum DispatchRowRef: Equatable {
    case order(Int)   // index into the order-leg array (server pagination order)
    case manual(Int)  // index into the manual-task array (server board order)
}

public enum DispatchWorkload {

    /// The sort key an item without one sorts under: date-less and
    /// priority-less — after every dated/prioritised item, the same rule the
    /// web board applies (NULLs last).
    public static let openEndedSortKey = "9999-12-31|09999"

    /// Weaves the two server-ordered lists into ONE workday by sort_key —
    /// stable: each source keeps its own internal order, and on an equal key
    /// the order leg renders before the manual task (matching the web board's
    /// concat order of delivery legs before manuals on the same slot).
    public static func weave(orderSortKeys: [String?], manualSortKeys: [String?]) -> [DispatchRowRef] {
        var rows: [DispatchRowRef] = []
        rows.reserveCapacity(orderSortKeys.count + manualSortKeys.count)

        var o = 0
        var m = 0
        while o < orderSortKeys.count && m < manualSortKeys.count {
            let orderKey = orderSortKeys[o] ?? openEndedSortKey
            let manualKey = manualSortKeys[m] ?? openEndedSortKey
            if manualKey < orderKey {
                rows.append(.manual(m)); m += 1
            } else {
                rows.append(.order(o)); o += 1
            }
        }
        while o < orderSortKeys.count { rows.append(.order(o)); o += 1 }
        while m < manualSortKeys.count { rows.append(.manual(m)); m += 1 }

        return rows
    }

    /// Whether a manual task belongs under the given schedule-type filter.
    /// Web-board rule: manual tasks live in the DELIVERIES column — they show
    /// under Delivery and All, never under Return-only. (The server already
    /// enforces this by sending no manual_jobs on a Return-only request; this
    /// is the client-side statement of the same rule for cached data.)
    public static func manualBelongs(inScheduleType scheduleType: String) -> Bool {
        return scheduleType != "Return"
    }

    /// Server-refresh reconciliation for the manual list: the fresh server
    /// snapshot REPLACES the cached one (present = assigned to me and open;
    /// absent = reassigned/completed/cancelled — it must disappear). nil means
    /// the response carried no manual_jobs key (legacy server): keep nothing
    /// rather than resurrect state the server no longer vouches for.
    public static func reconciledManualList(cached: [DispatchManualJob],
                                            serverSnapshot: [DispatchManualJob]?) -> [DispatchManualJob] {
        return serverSnapshot ?? []
    }
}
