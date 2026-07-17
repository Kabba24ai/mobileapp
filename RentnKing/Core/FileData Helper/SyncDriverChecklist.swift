//
//  SyncDriverChecklist.swift
//  RentnKing
//

import UIKit
import Alamofire
import ObjectMapper

struct DriverChecklistSubmitModel: Mappable {
    internal var id: Int?
    internal var order_product_unique_id: String?
    internal var equipment_fuel: String?
    internal var equipment_key_location: String?
    internal var equipment_driver_status: String?
    internal var status: String?
    internal var checklist_type: String?

    init?(map: Map) {
        mapping(map: map)
    }

    mutating func mapping(map: Map) {
        id                       <- map["id"]
        order_product_unique_id  <- map["order_product_unique_id"]
        equipment_fuel           <- map["equipment_fuel"]
        equipment_key_location   <- map["equipment_key_location"]
        equipment_driver_status  <- map["equipment_driver_status"]
        status                   <- map["status"]
        checklist_type                   <- map["checklist_type"]
    }
}

// MARK: - Save to local

func saveDriverChecklistLocally(order_product_unique_id: String,
                                equipment_fuel: String,
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

func syncDriverChecklistWithAPI() {
    let storageKey = kFileStorageName.kDriverChecklistSubmit.rawValue
    let arr: [DriverChecklistSubmitModel] = SDKUserDefault.getMappableArray(DriverChecklistSubmitModel.self, for: storageKey) ?? []

    guard arr.count != 0 else { return }

    if NetworkReachabilityManager()!.isReachable {
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
        "equipment_key_location":  obj.equipment_key_location ?? "",
        "equipment_driver_status": obj.equipment_driver_status ?? "",
        "checklist_type": obj.checklist_type ?? ""
    ]

    callDriverChecklistAPI(params: dicData, localID: obj.id ?? 0) { _ in
        //syncDriverChecklistWithAPI()
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
        print("API URL====>>\(strURL)\n\nParams:===>\(params)\n\nResponse:====>>\(dic)")
        handleDriverChecklistResponse(data: dic, localID: localID) { is_success in
            completion(is_success)
        }
    }
}

func handleDriverChecklistResponse(data: NSDictionary?, localID: Int, completion: @escaping (Bool) -> Void) {
    // Always remove from local queue — success or error, call only once, no retry
    let storageKey = kFileStorageName.kDriverChecklistSubmit.rawValue
    var arr: [DriverChecklistSubmitModel] = SDKUserDefault.getMappableArray(DriverChecklistSubmitModel.self, for: storageKey) ?? []
    if let index = arr.firstIndex(where: { $0.id == localID }) {
        arr.remove(at: index)
        SDKUserDefault.saveMappableArray(arr, for: storageKey)
    }

    if data?.getStringForID(key: "status") == "1" {
        indicatorHide()
        completion(true)
    } else {
        debugPrint("Driver Checklist API Error")
        if data?.getStringForID(key: "message") != "" {
            DispatchQueue.main.async {
                showAlertMessage(strMessage: data?.getStringForID(key: "message") ?? str.somethingWentWrong, isDismiss: true)
            }
            
        } else {
            showAlertMessage(strMessage: "\(str.somethingWentWrong)")
        }
        completion(false)
    }
}
