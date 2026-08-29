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
    internal var delivery_checklist: CheckListResponeData?
    internal var pickup_checklist: CheckListResponeData?
    
    internal var is_delivery_overdue: Bool?
    internal var is_pickup_overdue: Bool?

    internal var is_early: Bool?
    internal var is_late_pickup: Bool?

    internal var dispatch_delivery_date: String?
    internal var dispatch_return_date: String?

//    internal var location: String?
//    internal var order_id: Int?
//    internal var product_id: Int?
//    internal var phone: String?
////    internal var customer_delivery: Int?
//    internal var customer_pickup: Int?
    internal var order: OrdersListModel?

//    internal var delivery_store: StoreOptionsModel?
//    internal var pickup_store: StoreOptionsModel?
    internal var objEquipment : MachineModel?

    internal var is_delivered: Bool?
    internal var is_returned: Bool?

    internal var delivery_employee: EmployeesModel?
    internal var pickup_employee: EmployeesModel?

    // Dispatch parity (Phase 6A) — additive mixed-feed identity keys from
    // orders/schedules/dispatch: the row's source, stable dispatch identity,
    // active fulfillment leg, and the web board's unified sort key
    // ("YYYY-MM-DD|NNNNN") used to weave manual tasks into the workday.
    internal var dispatch_source: String?
    internal var dispatch_item_id: String?
    internal var fulfillment_leg: String?
    internal var sort_key: String?

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
        delivery_checklist <- map["delivery_checklist"]
        pickup_checklist <- map["pickup_checklist"]

        is_delivery_overdue <- map["is_delivery_overdue"]
        is_pickup_overdue <- map["is_pickup_overdue"]
        
        is_early <- map["is_early"]
        is_late_pickup <- map["is_late_pickup"]

        dispatch_delivery_date <- map["dispatch_delivery_date"]
        dispatch_return_date <- map["dispatch_return_date"]

//        name <- map["product_name"]
//        location <- map["location"]
//        order_id <- map["order_id"]
//        product_id <- map["product_id"]
//        phone <- map["phone"]
//        customer_delivery <- map["customer_delivery"]
//        customer_pickup <- map["customer_pickup"]
        order <- map["order"]
//        delivery_store <- map["delivery_store"]
//        pickup_store <- map["pickup_store"]
        objEquipment <- map["equipment"]

        is_delivered <- map["is_delivered"]
        is_returned <- map["is_returned"]

        delivery_employee <- map["delivery_employee"]
        pickup_employee <- map["pickup_employee"]

        dispatch_source <- map["dispatch_source"]
        dispatch_item_id <- map["dispatch_item_id"]
        fulfillment_leg <- map["fulfillment_leg"]
        sort_key <- map["sort_key"]

    }
}


struct CheckListResponeData: Mappable{
    internal var arrived_at: String?
    internal var equipment_driver_status: String?
    internal var equipment_fuel: String?
    internal var equipment_key_location: String?
    internal var is_arrived: Bool?
    internal var is_delivered: Bool?
    internal var ready_to_go_at: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        arrived_at <- map["arrived_at"]
        equipment_driver_status <- map["equipment_driver_status"]
        equipment_fuel <- map["equipment_fuel"]
        equipment_key_location <- map["equipment_key_location"]
        is_arrived <- map["is_arrived"]
        is_delivered <- map["is_delivered"]
        ready_to_go_at <- map["ready_to_go_at"]
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
            lblDelivery,
            lblPickup
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
        var date_filter : String //= "Today" //Today, All
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
                    SDKUserDefault.saveMappableArray(newOrders, for: "\(kFileStorageName.kScheduleOrderList.rawValue)_\(OrdersParameater.schedule_type)_\(OrdersParameater.schedule_status)_\(self.strSelectDay)_\(self.selectDeliveryType)")
                } else {
                    // Append to local
                    var existing = self.getScheduleOrderData(schedule_type: OrdersParameater.schedule_type, schedule_status: OrdersParameater.schedule_status)
                    
                    // Avoid duplicates
                    let filteredNew = newOrders.filter { newItem in
                        !existing.contains(where: { $0.id == newItem.id })
                    }
                    
                    existing.append(contentsOf: filteredNew)
                    SDKUserDefault.saveMappableArray(existing, for: "\(kFileStorageName.kScheduleOrderList.rawValue)_\(OrdersParameater.schedule_type)_\(OrdersParameater.schedule_status)_\(self.strSelectDay)_\(self.selectDeliveryType)")
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

    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
        indicatorHide()
        self.isLoading = false
        self.isHeaderLoading = false
        self.stopAnimatingView()
        self.objRefresh?.endRefreshing()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "scheduleUpdate"{
                

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

