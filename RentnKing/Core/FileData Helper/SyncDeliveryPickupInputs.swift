//
//  SyncDeliveryPickupInputs.swift
//  RentnKing
//
//  Offline-first store + sync for the Driver Override "Delivery/Pickup inputs" API
//  (orders/schedules/update-delivery-pickup-inputs). Mirrors SyncDriverChecklist.
//

import UIKit
import Alamofire
import ObjectMapper

struct DeliveryPickupInputsSubmitModel: Mappable {
    internal var id: Int?
    internal var order_product_unique_id: String?
    internal var type: String?                    // "delivery" | "pickup"
    internal var inputs_date: String?             // "yyyy-MM-dd HH:mm:ss"
    internal var tnc_status: String?
    internal var drivers_license_status: String?
    internal var video_status: String?
    internal var checklist_status: String?
    internal var status: String?                  // local queue status (pending)
    internal var attempts: Int?                   // retry counter (dead-letter after kMaxSyncAttempts)

    init?(map: Map) {
        mapping(map: map)
    }

    mutating func mapping(map: Map) {
        id                      <- map["id"]
        order_product_unique_id <- map["order_product_unique_id"]
        type                    <- map["type"]
        inputs_date             <- map["inputs_date"]
        tnc_status              <- map["tnc_status"]
        drivers_license_status  <- map["drivers_license_status"]
        video_status            <- map["video_status"]
        checklist_status        <- map["checklist_status"]
        status                  <- map["status"]
        attempts                <- map["attempts"]
    }
}

// MARK: - Save to local

func saveDeliveryPickupInputsLocally(order_product_unique_id: String,
                                     type: String,
                                     inputs_date: String,
                                     tnc_status: String,
                                     drivers_license_status: String,
                                     video_status: String,
                                     checklist_status: String) {
    


    let storageKey = kFileStorageName.kDeliveryPickupInputsSubmit.rawValue

    var arr: [DeliveryPickupInputsSubmitModel] = SDKUserDefault.getMappableArray(DeliveryPickupInputsSubmitModel.self, for: storageKey) ?? []

    // Remove any existing pending record for same product + type to avoid duplicates
    arr.removeAll { $0.order_product_unique_id == order_product_unique_id && $0.type == type }

    if var obj = DeliveryPickupInputsSubmitModel(JSON: [:]) {
        obj.id                      = Int(Date().timeIntervalSince1970)
        obj.order_product_unique_id = order_product_unique_id
        obj.type                    = type
        obj.inputs_date             = inputs_date
        obj.tnc_status              = tnc_status
        obj.drivers_license_status  = drivers_license_status
        obj.video_status            = video_status
        obj.checklist_status        = checklist_status
        obj.status                  = kOrderStatusType.kPending.rawValue
        arr.append(obj)
    }


    SDKUserDefault.saveMappableArray(arr, for: storageKey)
}

// MARK: - Sync

func syncDeliveryPickupInputsWithAPI() {
    let storageKey = kFileStorageName.kDeliveryPickupInputsSubmit.rawValue
    let arr: [DeliveryPickupInputsSubmitModel] = SDKUserDefault.getMappableArray(DeliveryPickupInputsSubmitModel.self, for: storageKey) ?? []

    guard arr.count != 0 else { return }

    if NetworkReachabilityManager()?.isReachable == true {
        let firstData = arr[0]
        if firstData.status == kOrderStatusType.kPending.rawValue {
            callAPIforDeliveryPickupInputs(obj: firstData)
        }
    }
}

func deliveryPickupInputsParams(_ obj: DeliveryPickupInputsSubmitModel) -> [String: Any] {
    return [
        "order_product_unique_id": obj.order_product_unique_id ?? "",
        "type":                    obj.type ?? "",
        "inputs_date":             obj.inputs_date ?? "",
        "tnc_status":              obj.tnc_status ?? "",
        "drivers_license_status":  obj.drivers_license_status ?? "",
        "video_status":            obj.video_status ?? "",
        "checklist_status":        obj.checklist_status ?? ""
    ]
}

func callAPIforDeliveryPickupInputs(obj: DeliveryPickupInputsSubmitModel) {
    callDeliveryPickupInputsAPI(params: deliveryPickupInputsParams(obj), localID: obj.id ?? 0) { _ in
        // Draining is handled inside handleDeliveryPickupInputsResponse and only
        // advances on success — draining here unconditionally would re-send a kept
        // (failed) arr[0] in a tight loop.
    }
}

/// Submit the pending record for this product **now** and return the server's message.
/// Used by the Warning screen so it can show the API success/error message directly.
func submitDeliveryPickupInputsNow(order_product_unique_id: String,
                                   type: String,
                                   completion: @escaping (_ success: Bool, _ message: String) -> Void) {
    let storageKey = kFileStorageName.kDeliveryPickupInputsSubmit.rawValue
    let arr: [DeliveryPickupInputsSubmitModel] = SDKUserDefault.getMappableArray(DeliveryPickupInputsSubmitModel.self, for: storageKey) ?? []
    guard let obj = arr.first(where: { $0.order_product_unique_id == order_product_unique_id && $0.type == type }) else {
        completion(false, "")
        return
    }

    let strURL = "\(Url.updateDeliveryPickupInputs.absoluteString!)"
    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = deliveryPickupInputsParams(obj)
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { dic, _, _, _ in
        let isSuccess = dic?.getStringForID(key: "status") == "1"
        let message = dic?.getStringForID(key: "message") ?? ""
        // Remove ONLY on success; on failure keep it so the background sync retries
        // (previously it was removed unconditionally, losing the submission).
        if isSuccess {
            var arrLocal: [DeliveryPickupInputsSubmitModel] = SDKUserDefault.getMappableArray(DeliveryPickupInputsSubmitModel.self, for: storageKey) ?? []
            arrLocal.removeAll { $0.id == obj.id }
            SDKUserDefault.saveMappableArray(arrLocal, for: storageKey)
        }
        DispatchQueue.main.async {
            completion(isSuccess, message)
        }
    }
}

// MARK: - API Call

func callDeliveryPickupInputsAPI(params: [String: Any], localID: Int, completion: @escaping (Bool) -> Void) {
    let strURL = "\(Url.updateDeliveryPickupInputs.absoluteString!)"

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
        handleDeliveryPickupInputsResponse(data: dic, localID: localID) { is_success in
            completion(is_success)
        }
    }
}

func handleDeliveryPickupInputsResponse(data: NSDictionary?, localID: Int, completion: @escaping (Bool) -> Void) {
    let storageKey = kFileStorageName.kDeliveryPickupInputsSubmit.rawValue
    var arr: [DeliveryPickupInputsSubmitModel] = SDKUserDefault.getMappableArray(DeliveryPickupInputsSubmitModel.self, for: storageKey) ?? []

    if data?.getStringForID(key: "status") == "1" {
        // Success — remove and drain the next queued item.
        arr.removeAll { $0.id == localID }
        SDKUserDefault.saveMappableArray(arr, for: storageKey)
        indicatorHide()
        completion(true)
        syncDeliveryPickupInputsWithAPI()
        return
    }

    // Failure / transient error — KEEP for retry (launch / network restore),
    // capping attempts so a permanently-rejected item can't block the queue.
    if let index = arr.firstIndex(where: { $0.id == localID }) {
        let attempts = (arr[index].attempts ?? 0) + 1
        if attempts >= kMaxSyncAttempts {
            debugPrint("Delivery/Pickup Inputs: dropping item \(localID) after \(attempts) failed attempts")
            arr.remove(at: index)                 // dead-letter
        } else {
            arr[index].attempts = attempts        // keep for retry
        }
        SDKUserDefault.saveMappableArray(arr, for: storageKey)
    }
    completion(false)
}
