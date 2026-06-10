//
//  Untitled.swift
//  RentnKing
//
//  Created by DEEPAK JAIN on 01/01/26.
//

import UIKit
import Alamofire
import ObjectMapper

struct SubmitEqipmentModel: Mappable{
    internal var id: Int?
    internal var equipment_unique_id: String?
    internal var user_id: String?
    internal var user_name: String?
    internal var equipment_hours: String?
    internal var checklist: [[String: Any]]?
    internal var status: String?
    internal var equipment_status: String?
    
    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        id <- map["id"]
        equipment_unique_id <- map["equipment_unique_id"]
        user_id <- map["user_id"]
        user_name <- map["user_name"]
        equipment_hours <- map["equipment_hours"]
        checklist <- map["checklist"]
        status <- map["status"]
        equipment_status <- map["equipment_status"]
    }
}



func syncEquipmentWithAPI() {
    let storageKey = "\(kFileStorageName.kEquipmentSubmit.rawValue)"
    let arrEqipmentRentalData: [SubmitEqipmentModel] = SDKUserDefault.getMappableArray(SubmitEqipmentModel.self, for: storageKey) ?? []
    if arrEqipmentRentalData.count != 0 {
        if NetworkReachabilityManager()!.isReachable {
            let firstData = arrEqipmentRentalData[0]
            if firstData.status == kOrderStatusType.kPending.rawValue {
                callAPIforUpdateRentalReady(dic: firstData)
            }
        }
    }
}

func callAPIforUpdateRentalReady(dic: SubmitEqipmentModel) {
    
    let dicData : [String : Any] = [
        "equipment_unique_id": dic.equipment_unique_id ?? "",
        "user_id": dic.user_id ?? "",
        "equipment_hours" : dic.equipment_hours ?? "0",
        "checklist": dic.checklist ?? [[:]]
    ]
    
    updateRentalReady(dicRentalReadyList: dicData, id: dic.id ?? 0) { is_success in
        syncEquipmentWithAPI()
    }
}

func updateRentalReady(dicRentalReadyList: [String : Any], id: Int, completion: @escaping (Bool) -> Void) {
   
    //Declaration URL
    let strURL = "\(Url.updateRantalReady.absoluteString!)"
    
   
    //Create object for webservicehelper and start to call method
    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = dicRentalReadyList
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { dic, arr, success, err in
        handleResponse(data: dic, id: id) { is_success in
            completion(is_success)
        }
    }
}

func handleResponse(data: NSDictionary?, id: Int, completion: @escaping (Bool) -> Void) {
    guard let dic_response = data else { return }
    
    if dic_response.getStringForID(key: "success") == "1"{
        print(dic_response)
        indicatorHide()
        let storageKey = "\(kFileStorageName.kEquipmentSubmit.rawValue)"
        var arrEqipmentRentalData: [SubmitEqipmentModel] = SDKUserDefault.getMappableArray(SubmitEqipmentModel.self, for: storageKey) ?? []
        
        if id != 0 {
            // Remove note from array if it exists
            if let index = arrEqipmentRentalData.firstIndex(where: { $0.id == id }) {
                arrEqipmentRentalData.remove(at: index)
                
                // Save updated array back
                SDKUserDefault.saveMappableArray(arrEqipmentRentalData, for: storageKey)
                
//                CallAPIforGetEquipmentList(EquipmentParameater: EquipmentParameater()) { isSaved in
//                    print(isSaved)
//                    NotificationCenter.default.post(name: .refreshMachineProfileList, object: nil)
//                }

                completion(true)
            }
        }
        else {
            completion(true)
        }
        
    }
    else {
        print(dic_response)
        debugPrint("Getting Error")
        if id == 0 {
            if data?.getStringForID(key: "message") != ""{
                showAlertMessage(strMessage: data!.getStringForID(key: "message"))
            }
            else{
                showAlertMessage(strMessage: "\(str.somethingWentWrong)")
            }
        }
    }
}


