//
//  SyncDriverChecklist.swift
//  RentnKing
//

import UIKit
import Alamofire
import ObjectMapper

/// Max times a queued offline submission is retried before it is dropped
/// (dead-lettered) so a permanently-rejected item can't block the whole queue.
let kMaxSyncAttempts = 5

struct DriverChecklistSubmitModel: Mappable {
    internal var id: Int?
    internal var order_product_unique_id: String?
    internal var equipment_fuel: String?
    internal var call_customer: String?
    internal var equipment_key_location: String?
    internal var equipment_driver_status: String?
    internal var status: String?
    internal var checklist_type: String?
    internal var attempts: Int?

    init?(map: Map) {
        mapping(map: map)
    }

    mutating func mapping(map: Map) {
        id                       <- map["id"]
        order_product_unique_id  <- map["order_product_unique_id"]
        equipment_fuel           <- map["equipment_fuel"]
        call_customer           <- map["call_customer"]
        equipment_key_location   <- map["equipment_key_location"]
        equipment_driver_status  <- map["equipment_driver_status"]
        status                   <- map["status"]
        checklist_type                   <- map["checklist_type"]
        attempts                 <- map["attempts"]
    }
}

// MARK: - Save to local

/// Records one driver checklist step. Phase 2: goes into the durable, idempotent Sync
/// Engine (KabbaSync) — the step is on disk before this returns, survives app kill /
/// reboot, retries with backoff, and is never dead-lettered. Returns the operation id so
/// the caller can show sync status. Falls back to the legacy MMKV queue only if the engine
/// failed to bootstrap.
@discardableResult
func saveDriverChecklistLocally(order_product_unique_id: String,
                                equipment_fuel: String,
                                call_customer: String,
                                equipment_key_location: String,
                                equipment_driver_status: String,
                                checklist_type: String) -> String? {
    if let engine = KabbaSync.engine {
        do {
            let operation = try DriverChecklistSyncHandler.enqueue(
                into: engine,
                orderProductUniqueId: order_product_unique_id,
                orderUniqueId: nil,
                equipmentFuel: equipment_fuel,
                callCustomer: call_customer,
                equipmentKeyLocation: equipment_key_location,
                equipmentDriverStatus: equipment_driver_status,
                checklistType: checklist_type
            )
            return operation.id
        } catch {
            debugPrint("Driver Checklist: sync engine enqueue failed (\(error)) — falling back to legacy queue")
        }
    }

    legacySaveDriverChecklistLocally(order_product_unique_id: order_product_unique_id,
                                     equipment_fuel: equipment_fuel,
                                     call_customer: call_customer,
                                     equipment_key_location: equipment_key_location,
                                     equipment_driver_status: equipment_driver_status,
                                     checklist_type: checklist_type)
    return nil
}

/// Migrates anything still sitting in the legacy MMKV queue (kDriverChecklistSubmit) into the
/// Sync Engine, preserving the original capture time (the legacy `id` is the epoch second the
/// step was saved), then clears the legacy queue. Runs once per launch from KabbaSync.bootstrap.
func migrateLegacyDriverChecklistQueueIntoSyncEngine() {
    guard let engine = KabbaSync.engine else { return }
    let storageKey = kFileStorageName.kDriverChecklistSubmit.rawValue
    let arr: [DriverChecklistSubmitModel] = SDKUserDefault.getMappableArray(DriverChecklistSubmitModel.self, for: storageKey) ?? []
    guard !arr.isEmpty else { return }

    var remaining: [DriverChecklistSubmitModel] = []
    for item in arr {
        guard let productId = item.order_product_unique_id, !productId.isEmpty else { continue }
        let epoch = item.id ?? 0
        let captured = epoch > 1_600_000_000 ? Date(timeIntervalSince1970: TimeInterval(epoch)) : Date()
        do {
            _ = try DriverChecklistSyncHandler.enqueue(
                into: engine,
                orderProductUniqueId: productId,
                orderUniqueId: nil,
                equipmentFuel: item.equipment_fuel ?? "",
                callCustomer: item.call_customer ?? "",
                equipmentKeyLocation: item.equipment_key_location ?? "",
                equipmentDriverStatus: item.equipment_driver_status ?? "",
                checklistType: item.checklist_type ?? "",
                capturedAt: captured
            )
        } catch {
            remaining.append(item)
        }
    }

    if remaining.isEmpty {
        SDKUserDefault.remove(for: storageKey)
    } else {
        SDKUserDefault.saveMappableArray(remaining, for: storageKey)
    }
    debugPrint("Driver Checklist: migrated \(arr.count - remaining.count) legacy item(s) into the Sync Engine")
}

/// LEGACY (pre-Phase-2) MMKV queue writer. Kept only as the fallback when the Sync Engine is
/// unavailable and for the migration above. Do not add new callers.
func legacySaveDriverChecklistLocally(order_product_unique_id: String,
                                      equipment_fuel: String,
                                      call_customer: String,
                                      equipment_key_location: String,
                                      equipment_driver_status: String,
                                      checklist_type: String) {
    let storageKey = kFileStorageName.kDriverChecklistSubmit.rawValue
    var arr: [DriverChecklistSubmitModel] = SDKUserDefault.getMappableArray(DriverChecklistSubmitModel.self, for: storageKey) ?? []

    // Remove any existing pending record for same product to avoid duplicates
    arr.removeAll { $0.order_product_unique_id == order_product_unique_id }

    if var obj = DriverChecklistSubmitModel(JSON: [:]) {
        obj.id                      = Int(Date().timeIntervalSince1970)
        obj.order_product_unique_id = order_product_unique_id
        obj.call_customer          = call_customer
        obj.equipment_fuel          = equipment_fuel
        obj.equipment_key_location  = equipment_key_location
        obj.equipment_driver_status = equipment_driver_status
        obj.status                  = kOrderStatusType.kPending.rawValue
        obj.checklist_type = checklist_type
        arr.append(obj)
    }

    SDKUserDefault.saveMappableArray(arr, for: storageKey)
}

// MARK: - Sync

/// Legacy trigger kept for its call sites (AppDelegate launch / network-restore, the checklist
/// screen). With the Sync Engine bootstrapped it simply asks the engine to drain; the legacy
/// MMKV drain below only runs if the engine is unavailable.
func syncDriverChecklistWithAPI() {
    if KabbaSync.isReady {
        KabbaSync.kick("driver checklist", ignoreBackoff: true)
        return
    }
    legacySyncDriverChecklistWithAPI()
}

func legacySyncDriverChecklistWithAPI() {
    let storageKey = kFileStorageName.kDriverChecklistSubmit.rawValue
    let arr: [DriverChecklistSubmitModel] = SDKUserDefault.getMappableArray(DriverChecklistSubmitModel.self, for: storageKey) ?? []

    guard arr.count != 0 else { return }

    if NetworkReachabilityManager()?.isReachable == true {
        let firstData = arr[0]
        if firstData.status == kOrderStatusType.kPending.rawValue {
            callAPIforDriverChecklist(obj: firstData)
        }
    }
}

func callAPIforDriverChecklist(obj: DriverChecklistSubmitModel) {
    let dicData: [String: Any] = [
        "order_product_unique_id": obj.order_product_unique_id ?? "",
        "equipment_fuel":          obj.equipment_fuel ?? "",
        "call_customer":          obj.call_customer ?? "",
        "equipment_key_location":  obj.equipment_key_location ?? "",
        "equipment_driver_status": obj.equipment_driver_status ?? "",
        "checklist_type": obj.checklist_type ?? ""
    ]

    callDriverChecklistAPI(params: dicData, localID: obj.id ?? 0) { _ in
        // Drain handled inside handleDriverChecklistResponse (only advances on success).
    }
}

// MARK: - API Call

func callDriverChecklistAPI(params: [String: Any], localID: Int, completion: @escaping (Bool) -> Void) {
    let strURL = "\(Url.driverChecklist.absoluteString!)"

    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = params
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { dic, arr, success, err in
        #if DEBUG
        print("API URL====>>\(strURL)\n\nParams:===>\(params)\n\nResponse:====>>\(dic)")
        #endif
        handleDriverChecklistResponse(data: dic, localID: localID) { is_success in
            completion(is_success)
        }
    }
}

func handleDriverChecklistResponse(data: NSDictionary?, localID: Int, completion: @escaping (Bool) -> Void) {
    let storageKey = kFileStorageName.kDriverChecklistSubmit.rawValue
    var arr: [DriverChecklistSubmitModel] = SDKUserDefault.getMappableArray(DriverChecklistSubmitModel.self, for: storageKey) ?? []

    if data?.getStringForID(key: "status") == "1" {
        // Success — remove the item and drain the next queued one.
        arr.removeAll { $0.id == localID }
        SDKUserDefault.saveMappableArray(arr, for: storageKey)
        indicatorHide()
        completion(true)
        legacySyncDriverChecklistWithAPI()
        return
    }

    // LEGACY fallback only (engine unavailable). The Sync Engine path above never drops an
    // item — see SyncEngine. This dead-letter cap remains solely for the fallback queue.
    if let index = arr.firstIndex(where: { $0.id == localID }) {
        let attempts = (arr[index].attempts ?? 0) + 1
        if attempts >= kMaxSyncAttempts {
            debugPrint("Driver Checklist: dropping item \(localID) after \(attempts) failed attempts")
            arr.remove(at: index)                 // dead-letter — stop blocking the queue
        } else {
            arr[index].attempts = attempts        // keep for the next retry
        }
        SDKUserDefault.saveMappableArray(arr, for: storageKey)
    }
    completion(false)
}
