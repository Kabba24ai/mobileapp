//
//  Equpment.swift
//  RentnKing
//
//  Created by Jigar Khatri on 23/12/25.
//

import UIKit
import ObjectMapper


struct EquipmentParameater: Codable {
    var type : String?
}

// MARK: - Get Equipment List
func getEquipmentList(strType : String = "Checklist", completion: @escaping ([MachineModel]) -> Void) {
    if !getEquipmentData().isEmpty {
        completion(getEquipmentData())
    }
    
    CallAPIforGetEquipmentList(EquipmentParameater: EquipmentParameater(type: strType)) { isSaved in
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




// MARK: - Get Customer List

struct CustomerParameater: Codable {
    var page : Int?
    var per_page : Int?
    var tag : String?
    var tax_status : String?
    var search_name : String?
}

func getCustomerList(page: Int,
                     perPage: Int,
                     search_name: String = "", completion: @escaping ([CustomerModel]) -> Void) {
    
    if !getCustomerData().isEmpty {
        completion(getCustomerData())
    }
    
    let param = CustomerParameater(
           page: page,
           per_page: perPage,
           search_name: search_name
    )

    
    CallAPIforGetCustomerList(CustomerParameater: param) { arrData in
        if page == 1 {
            //SAVE ARRAY
            SDKUserDefault.saveMappableArray(arrData, for: kFileStorageName.kCustomerList.rawValue)
            
            completion(getCustomerData())
        }
        else {
            completion(arrData)
        }
        
    }
}



func getCustomerData() -> [CustomerModel] {
    if let arr = SDKUserDefault.getMappableArray(CustomerModel.self, for: kFileStorageName.kCustomerList.rawValue) {
        return arr
    }
    return []
}


func CallAPIforGetCustomerList(CustomerParameater : CustomerParameater, completion: @escaping ([CustomerModel]) -> Void) {

    guard let parameater = try? CustomerParameater.asDictionary() else {
        showAlertMessage(strMessage: str.invalidRequestParamater)
        return
    }
    
    //Declaration URL
    let strURL = "\(Url.customerList.absoluteString!)"

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
        
        if let dic_response = data {
            
            print("Customer Data Response====>>>")
            print(dic_response)
            
            if dic_response.getStringForID(key: "success") == "1" {
                if let arrData = dic_response["customers"] as? NSArray {
                    
                    let arrData = Mapper<CustomerModel>().mapArray(JSONArray: arrData as! [[String : Any]])

                    completion(arrData)
                }
            }
            
        }

    }
    
    
}
