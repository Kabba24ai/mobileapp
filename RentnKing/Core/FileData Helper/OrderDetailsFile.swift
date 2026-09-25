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
    if let cached = getOrderDetailData(strOrderUniqeID: OrdersDetailsParameater.unique_id) {
        completion(cached)
    }
    
    callAPIforGetOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater) { isSaved in
        // Saved, or kept the newer copy already here (Dispatch offline Phase 4); nil only when
        // there is no copy for the signed-in company at all.
        if isSaved, let saved = getOrderDetailData(strOrderUniqeID: OrdersDetailsParameater.unique_id) {
            completion(saved)
        } else {
            completion(nil)
        }
    }
}

// MARK: - Get Local Data
func getOrderDetailData(strOrderUniqeID : String) -> OrdersModel? {
    OrderDetailsCache.loadChecklistOrder(orderUniqueId: strOrderUniqeID)
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

    // Dispatch offline Phase 4: when this was asked, and for which company (§4.3, Amendment B).
    let askedAt = Date(), tenant = KabbaTenantScope.currentKey

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
                
                //SET DATA IN LOCAL — unless a newer copy (a mission package asked later) is already here
                if let order = arr_data {
                    OrderDetailsCache.saveLive(order, orderUniqueId: OrdersDetailsParameater.unique_id, askedAt: askedAt, tenantKey: tenant)
                }
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


// MARK: - Users list (Order Details notes / payment "processed by")
func callAPIforUsersList(CatrgoryParameater : CatrgoryParameater = CatrgoryParameater(), completion: @escaping (Bool) -> Void) {
    guard let parameater = try? CatrgoryParameater.asDictionary() else {
        showAlertMessage(strMessage: str.invalidRequestParamater)
        return
    }
    let tenant = KabbaTenantScope.currentKey   // the company this request is for (Dispatch offline Phase 4, Amendment B)

    //Declaration URL
    let strURL = "\(Url.usersList.absoluteString!)"

    //Create object for webservicehelper and start to call method
    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = parameater
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.serviceWithAlert = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { dic, arr, success, err in
        if dic?.getStringForID(key: "success") == "1", let arrData = dic?["users"] as? NSArray {
            let arrData = Mapper<UserListModel>().mapArray(JSONArray: arrData as! [[String : Any]])

            // Overwrite old data
            completion(SDKUserDefault.saveMappableArray(arrData, for: kFileStorageName.kOrderDetailUserData.rawValue, tenantKey: tenant))
        } else {
            completion(false)
        }
    }
}
