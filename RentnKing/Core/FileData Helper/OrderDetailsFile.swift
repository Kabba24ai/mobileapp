//
//  OrderDetailsFile.swift
//  RentnKing
//
//  Created by Jigar Khatri on 13/01/26.
//

import Foundation
import ObjectMapper

// MARK: - Fetch Orders (Main Controller)
func getOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater, completion: @escaping (OrdersModel?) -> Void) {
    if (getOrderDetailData(strOrderUniqeID: OrdersDetailsParameater.unique_id) != nil) {
        completion(getOrderDetailData(strOrderUniqeID: OrdersDetailsParameater.unique_id)!)
    }
    
    callAPIforGetOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater) { isSaved in
        if isSaved {
            completion(getOrderDetailData(strOrderUniqeID: OrdersDetailsParameater.unique_id)!)
        } else {
            completion(nil)
        }
    }
}

// MARK: - Get Local Data
func getOrderDetailData(strOrderUniqeID : String) -> OrdersModel? {
    if let dic = SDKUserDefault.getMappableObject(OrdersModel.self, for: "\(kFileStorageName.kOrderDetailsData.rawValue)_\(strOrderUniqeID)") {
        return dic
    }
    return nil
}

func getChecklistOrderDetailData(strOrderUniqeID : String) -> OrdersModel? {
    if let dic = SDKUserDefault.getMappableObject(OrdersModel.self, for: "\(kFileStorageName.kCheckListOrderDetailsData.rawValue)_\(strOrderUniqeID)") {
        return dic
    }
    return nil
}

func isCheckListOrderDetailSaved(strOrderUniqeID: String) -> Bool {
    let key = "\(kFileStorageName.kCheckListOrderDetailsData.rawValue)_\(strOrderUniqeID)"
    
    return SDKUserDefault.getMappableObject(OrdersModel.self, for: key) != nil
}


func getChecklistOtherData(strOrderUniqeID : String) -> [NoteModel]? {
    return SDKUserDefault.getNSObjectArray(key: "\(kFileStorageName.kCheckListOtherData.rawValue)_\(strOrderUniqeID)")
}

func isCheckListOtherDataSaved(strOrderUniqeID: String) -> Bool {
    let arr = SDKUserDefault.getNSObjectArray(key: "\(kFileStorageName.kCheckListOtherData.rawValue)_\(strOrderUniqeID)")
    return arr.count == 0 ? false : true
}



func callAPIforGetOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater, completion: @escaping (Bool) -> Void) {
    guard let parameater = try? OrdersDetailsParameater.asDictionary() else {
        showAlertMessage(strMessage: str.invalidRequestParamater)
        return
    }

    //Declaration URL
    let strURL = "\(Url.orderDetails.absoluteString!)"
   
    //Create object for webservicehelper and start to call method
    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = parameater
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.serviceWithAlert = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { dic, arr, isSuccess, errorr in
        indicatorHide()

        if dic?.getStringForID(key: "success") == "1" {
            
            if let dicData = dic?["order"] as? NSDictionary {
                
                //SET DATA
                let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
                let arr_data = OrdersModel(map: map)
                
                //SET DATA IN LOCAL
                SDKUserDefault.saveMappableObject(arr_data!, for: "\(kFileStorageName.kOrderDetailsData.rawValue)_\(OrdersDetailsParameater.unique_id)")
                completion(true)
            }
            else {
                completion(false)
            }
        }
        else {
            completion(false)
        }
    }
}
