//
//  Equpment.swift
//  RentnKing
//
//  Created by Jigar Khatri on 23/12/25.
//

import UIKit
import ObjectMapper


struct EquipmentParameater: Codable {
    var type : String = ""
}

// MARK: - Get Equipment List
func getEquipmentList(completion: @escaping ([MachineModel]) -> Void) {
    if !getEquipmentData().isEmpty {
        completion(getEquipmentData())
    }
    
    CallAPIforGetEquipmentList(EquipmentParameater: EquipmentParameater()) { isSaved in
        if isSaved {
            completion(getEquipmentData())
        } else {
            completion([])
        }
    }
}



func getEquipmentData() -> [MachineModel] {
    if let arr = SDKUserDefault.getMappableArray(MachineModel.self, for: kFileStorageName.kEquipmentList.rawValue) {
        return arr
    }
    return []
}


func CallAPIforGetEquipmentList(EquipmentParameater : EquipmentParameater, completion: @escaping (Bool) -> Void) {

    guard let parameater = try? EquipmentParameater.asDictionary() else {
        showAlertMessage(strMessage: str.invalidRequestParamater)
        return
    }
    
    //Declaration URL
    let strURL = "\(Url.equipmentList.absoluteString!)"

    //Create object for webservicehelper and start to call method
    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = parameater
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.serviceWithAlert = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { data, arr, isDic, error in
        
        if data?.getStringForID(key: "success") == "1" {
            if let arrData = data?["equipment"] as? NSArray {
                
                var arrData = Mapper<MachineModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                arrData = arrData.sorted(by: { $0.equipment_name ?? "" < $1.equipment_name ?? "" })
                
                //SAVE ARRAY
                SDKUserDefault.saveMappableArray(arrData, for: kFileStorageName.kEquipmentList.rawValue)
                completion(true)
            }
        }
    }
}




// MARK: - Get Store List

func getStoreList(completion: @escaping ([StoreModel]) -> Void) {
    if !getStoreListData().isEmpty {
        completion(getStoreListData())
    }
    
    CallAPIforStoreList { isSaved in
        if isSaved {
            completion(getStoreListData())
        } else {
            completion([])
        }
    }
}

func getStoreListData() -> [StoreModel] {
    if let arr = SDKUserDefault.getMappableArray(StoreModel.self, for: kFileStorageName.kStoreList.rawValue) {
        return arr
    }
    return []
}

func CallAPIforStoreList(completion: @escaping (Bool) -> Void) {

    //Declaration URL
    let strURL = "\(Url.getStores.absoluteString!)"
   
    //Create object for webservicehelper and start to call method
    let webHelper = WebServiceHelper()
    webHelper.methodType = "get"
    webHelper.strURL = strURL
    webHelper.dictType = [:]
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.serviceWithAlert = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { data, arr, isDic, error in
        
        if data?.getStringForID(key: "success") == "1" {
            if let arrData = data?["stores"] as? NSArray {
                
                let arr = Mapper<StoreModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                
                //SAVE ARRAY
                SDKUserDefault.saveMappableArray(arr, for: kFileStorageName.kStoreList.rawValue)
                completion(true)
            }
        }
    }
}


