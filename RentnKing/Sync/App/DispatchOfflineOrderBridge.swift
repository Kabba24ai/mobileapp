//
//  DispatchOfflineOrderBridge.swift
//  RentnKing — Sync App layer
//
//  Dispatch offline mission cache — Phase 4 (plan §4.1, M3). Writes a mission
//  package's order-scoped sections into the caches the EXISTING screens
//  already read — never a second cache — for the package's own company:
//
//    order_details → Order Details        MMKV kOrderDetailData_<uid>   (OrdersListModel)
//                  → the checklist screens MMKV kOrderDetailsData_<uid>  (OrdersModel)
//    assembly      → Assembly Review       UserDefaults kQueueLineAssembly_<uid>
//
//  Every key is company-scoped (DispatchOfflineTenantStorage, Amendment B).
//  Notes written on this phone while offline (the kOrderNoteData queue) are
//  re-applied onto the fresh copy exactly as Order Details applies them, so a
//  bridge never hides one. The Core bridge decides WHEN to write (freshness,
//  company, readiness); this file only knows HOW.
//

import Foundation
import ObjectMapper

final class DispatchOfflineOrderBridge: DispatchOfflineOrderCacheWriting {

    static let shared = DispatchOfflineOrderBridge()

    func write(_ cache: DispatchOfflineOrderCache, payload: JSONValue, orderUniqueId: String, tenantKey: String) -> Bool {
        switch cache {
        case .orderDetails:
            guard let json = Self.foundationObject(payload), let order = OrdersListModel(JSON: json) else { return false }
            return SDKUserDefault.saveMappableObject(OrderNoteQueue.reapplied(to: order, orderUniqueId: orderUniqueId),
                                                     for: OrderDetailsCache.detailsKey(orderUniqueId), tenantKey: tenantKey)
        case .checklistOrder:
            guard let json = Self.foundationObject(payload), let order = OrdersModel(JSON: json) else { return false }
            return SDKUserDefault.saveMappableObject(order, for: OrderDetailsCache.checklistKey(orderUniqueId), tenantKey: tenantKey)
        case .assembly:
            // The package carries the endpoint's {data, meta}; the screen's cache is the whole envelope.
            guard case .object(var envelope) = payload else { return false }
            envelope["success"] = .bool(true)
            guard let data = try? JSONValue.object(envelope).serialized(),
                  (try? AssemblyReviewEnvelope.decode(data)) != nil else { return false }
            return KabbaAssemblySync.cache(data, orderUniqueId: orderUniqueId, tenantKey: tenantKey)
        case .terms:
            return false // Core writes the agreement store itself (DispatchOfflineFieldBridge.bridgeTerms)
        }
    }

    /// The same Foundation tree a live response hands ObjectMapper (NSNumber / NSNull).
    private static func foundationObject(_ value: JSONValue) -> [String: Any]? {
        guard case .object = value, let data = try? value.serialized() else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

// MARK: - The order caches the screens read

/// One place builds each order cache key (the SDKUserDefault accessors scope it to the signed-in
/// company) and saves a live response only when it is not older than the copy already there.
enum OrderDetailsCache {

    static func detailsKey(_ orderUniqueId: String) -> String { "\(kFileStorageName.kOrderDetailData.rawValue)_\(orderUniqueId)" }
    static func checklistKey(_ orderUniqueId: String) -> String { "\(kFileStorageName.kOrderDetailsData.rawValue)_\(orderUniqueId)" }

    /// Order Details' copy for the signed-in company (bridged from a package, or saved online).
    static func load(orderUniqueId: String) -> OrdersListModel? {
        SDKUserDefault.getMappableObject(OrdersListModel.self, for: detailsKey(orderUniqueId))
    }

    /// The checklist screens' copy for the signed-in company.
    static func loadChecklistOrder(orderUniqueId: String) -> OrdersModel? {
        SDKUserDefault.getMappableObject(OrdersModel.self, for: checklistKey(orderUniqueId))
    }

    /// Order Details got a live POST orders/details answer to a request SENT at `askedAt` for
    /// `tenantKey` (both captured when the request went out). Not saved when a newer copy (a
    /// package asked later) is already on this phone, nor for a company no longer signed in.
    @discardableResult
    static func saveLive(_ order: OrdersListModel, orderUniqueId: String, askedAt: Date, tenantKey: String?) -> Bool {
        guard let tenant = tenantKey else { return false }
        return DispatchOfflineSync.saveLiveCopy(.orderDetails, orderUniqueId: orderUniqueId, askedAt: askedAt, tenantKey: tenant) {
            SDKUserDefault.saveMappableObject(order, for: detailsKey(orderUniqueId), tenantKey: tenant)
        }
    }

    /// The checklist screens got a live answer (same rule).
    @discardableResult
    static func saveLive(_ order: OrdersModel, orderUniqueId: String, askedAt: Date, tenantKey: String?) -> Bool {
        guard let tenant = tenantKey else { return false }
        return DispatchOfflineSync.saveLiveCopy(.checklistOrder, orderUniqueId: orderUniqueId, askedAt: askedAt, tenantKey: tenant) {
            SDKUserDefault.saveMappableObject(order, for: checklistKey(orderUniqueId), tenantKey: tenant)
        }
    }
}

// MARK: - Notes written offline

/// The notes Order Details queued on this phone while offline (`kOrderNoteData`, drained by
/// syncOrderNoteWithAPI), applied onto a fresh server copy of the order the way Order Details
/// applies them: add / edit by id (newest first), and a queued delete removes the server note.
enum OrderNoteQueue {

    static func queued() -> [OrderNoteModel] {
        SDKUserDefault.getMappableArray(OrderNoteModel.self, for: kFileStorageName.kOrderNoteData.rawValue) ?? []
    }

    static func reapplied(to order: OrdersListModel, orderUniqueId: String, queue: [OrderNoteModel] = queued()) -> OrdersListModel {
        var order = order
        var notes = order.arrOrderNote
        for note in queue where note.mainOrderUniqueID == orderUniqueId {
            if (note.type ?? "") == kOrderStatusType.kDelete.rawValue {
                // A queued delete carries the SERVER note's unique_id (its own id is local).
                if let uid = note.unique_id, !uid.isEmpty { notes.removeAll { $0.unique_id == uid } }
            } else if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index] = note
            } else {
                notes.insert(note, at: 0)
            }
        }
        order.arrOrderNote = notes
        return order
    }
}
