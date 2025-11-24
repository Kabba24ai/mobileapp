//
//  ScheduleListModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 14/02/24.
//

import Foundation
import ObjectMapper
import UIKit


struct SchedulesModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var product_name: String?

    internal var delivery_date: String?
    internal var delivery_transport_mode: String?
    internal var delivery_time: String?
    internal var delivery_status: String?

    internal var pickup_date: String?
    internal var pickup_transport_mode: String?
    internal var pickup_time: String?
    internal var pickup_status: String?

    internal var objProduct: ProductDataModel?
//
//    
//    internal var location: String?
//    internal var order_id: Int?
//    internal var product_id: Int?
//    internal var phone: String?
////    internal var customer_delivery: Int?
//    internal var customer_pickup: Int?
    internal var order: OrdersListModel?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        product_name <- map["product_name"]

        delivery_date <- map["delivery_date"]
        delivery_transport_mode <- map["delivery_transport_mode"]
        delivery_time <- map["delivery_time"]
        delivery_status <- map["delivery_status"]

        pickup_date <- map["pickup_date"]
        pickup_transport_mode <- map["pickup_transport_mode"]
        pickup_time <- map["pickup_time"]
        pickup_status <- map["pickup_status"]

        objProduct <- map["product_data"]
//
//        name <- map["product_name"]
//        location <- map["location"]
//        order_id <- map["order_id"]
//        product_id <- map["product_id"]
//        phone <- map["phone"]
//        customer_delivery <- map["customer_delivery"]
//        customer_pickup <- map["customer_pickup"]
        order <- map["order"]
    }
}


struct Type_Status: Mappable{
    internal var value: String?
    internal var label: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        value <- map["value"]
        label <- map["label"]
    }
}


struct UpdateStatusParameater: Codable {
    var order_product_unique_id : String
    var schedule_type : String //Delivery, Return
    var schedule_status : String //Pending, Completed
}

extension ScheduleListViewController :WebServiceHelperDelegate{
    
    //LOADER
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            viewPending,
            viewCompleted,
            lblDelivery,
            lblPickup,
            viewLine,
            viewPendingCount,
            viewDeliveryCount,
            viewPickupCount,
            viewCompletedCount
            
        ]
    }
    
    
    struct OrdersParameater: Codable {
        var page : String
        var per_page : String = "\(Application.PageLimit)"
        var schedule_type : String //Delivery,Return
        var schedule_status : String  // 1 = pending , 2 = completed
        
        var search : String = ""
        var category_id : String = ""
        var transport_mode : String = "All" //Truck, Store
    }

    func callAPIforGetScheduleList(OrdersParameater: OrdersParameater, completion: @escaping (Bool) -> Void) {
        
        guard let parameters = try? OrdersParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            completion(false)
            return
        }
        
        let strURL = "\(Url.scheduleList.absoluteString!)"
        
        let webHelper = WebServiceHelper()
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameters
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        
        webHelper.callAPIwithCompletation { [weak self] data, arr, isDic, error in
            guard let self = self else { return }
            
            indicatorHide()
            self.isLoading = false
            
            guard error == nil else {
                completion(false)
                return
            }
            debugPrint(data ?? NSNull())
            
            if data?.getStringForID(key: "success") == "1",
               let arrData = data?["orders"] as? [[String: Any]] {
                
                let newOrders = Mapper<SchedulesModel>().mapArray(JSONArray: arrData)
                
                // Manage local storage
                if self.pageCount == 1 {
                    // Overwrite old data
                    SDKUserDefault.saveMappableArray(newOrders, for: "\(kFileStorageName.kScheduleOrderList.rawValue)_\(OrdersParameater.schedule_type)_\(OrdersParameater.schedule_status)")
                } else {
                    // Append to local
                    var existing = self.getScheduleOrderData(schedule_type: OrdersParameater.schedule_type, schedule_status: OrdersParameater.schedule_status)
                    
                    // Avoid duplicates
                    let filteredNew = newOrders.filter { newItem in
                        !existing.contains(where: { $0.id == newItem.id })
                    }
                    
                    existing.append(contentsOf: filteredNew)
                    SDKUserDefault.saveMappableArray(existing, for: "\(kFileStorageName.kScheduleOrderList.rawValue)_\(OrdersParameater.schedule_type)_\(OrdersParameater.schedule_status)")
                }
                
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
 
    
    func updateStatus(UpdateStatusParameater : UpdateStatusParameater, index : Int){
       
        guard let parameater = try? UpdateStatusParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.scheduleUpdate.absoluteString!)"

       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "scheduleUpdate"
        webHelper.methodType = "post"
        webHelper.selectIndex = index
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }

    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String) {
        indicatorHide()
        self.isLoading = false
        self.isHeaderLoading = false
        self.stopAnimatingView()
        self.objRefresh?.endRefreshing()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "scheduleUpdate"{
                //UPDATE COUNT
                GlobalMainConstants.appDelegate?.getScheduleCount()
                

                print(data)
                if self.arrScheduleList.count != 0{
                    
                    if self.arrScheduleList.count == 0{
                        return
                    }
                   
        
                    //UPDATE ARRAY
                    self.arrScheduleList.remove(at: index)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                        //RELOAD TABLE
                        self.tblView.reloadData()
                    }
//                    var objData = self.arrScheduleList[index]
//
//                    //UPDATE OBJECT
//                    if self.selectStatus == "2"{
//                        
//                        //UPDATE ARRAY
//                        var objData = self.arrScheduleList[index]
//                        if self.selectType.lowercased() == "Delivery".lowercased(){
//                            objData.delivery_status?.value = "2"
//                        }
//                        else{
//                            objData.pickup_status?.value = "2"
//                        }
//                        
//                        self.arrScheduleList.remove(at: index)
//                        self.arrScheduleList.insert(objData, at: index)
//                        
//                        
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
//                            //RELOAD TABLE
//                            self.tblView.reloadData()
//                        }
//                    }
//                    else{
//                        self.arrScheduleList.remove(at: index)
//
//                        
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
//                            //RELOAD TABLE
//                            self.tblView.reloadData()
//                        }
//                    }
                }
            }
        }
        else{
            print(strRequest)
            print(data)

            indicatorHide()
            //SET THE VIEW
            self.setTheView()
            if strRequest != "scheduleList"{
                showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")

            }
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        self.isLoading = false
        self.setTheView()
        
        //NO DATA
        self.emptyDataView.isHidden = false

        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}

