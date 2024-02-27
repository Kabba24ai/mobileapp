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
    internal var name: String?
    internal var location: String?
    internal var order_id: Int?
    internal var phone: String?
    internal var delivery_date: String?
    internal var delivery_status: Type_Status?
    internal var delivery_time: String?
    internal var customer_delivery: String?
    internal var pickup_date: String?
    internal var pickup_status: Type_Status?
    internal var pickup_time: String?
    internal var customer_pickup: String?
    internal var order: OrdersModel?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        name <- map["name"]
        location <- map["location"]
        order_id <- map["order_id"]
        phone <- map["phone"]
        delivery_date <- map["delivery_date"]
        delivery_status <- map["delivery_status"]
        delivery_time <- map["delivery_time"]
        customer_delivery <- map["customer_delivery"]
        pickup_date <- map["pickup_date"]
        pickup_status <- map["pickup_status"]
        pickup_time <- map["pickup_time"]
        customer_pickup <- map["customer_pickup"]
        order <- map["order"]
    }
}

struct Type_Status: Mappable{
    internal var value: Int?
    internal var label: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        value <- map["id"]
        label <- map["label"]
    }
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
            viewDelivery,
            viewPickup,
            viewLine
        ]
    }
    
    
    struct OrdersParameater: Codable {
        var page : String
        var limit : String = "\(Application.PageLimit)"
    }

    
    func getScheduleList(OrdersParameater : OrdersParameater){
        DispatchQueue.main.async {
            self.schedulePlaceholderMarker.register(self.getAnimableSubviews())
            self.schedulePlaceholderMarker.startAnimation()
        }
        
        guard let parameater = try? OrdersParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.scheduleList.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "scheduleList"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
    }
    
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()
        self.isLoading = false
        self.stopAnimatingView()
        self.objRefresh?.endRefreshing()

        if data.getStringForID(key: "success") == "1"{
            print(data)
            if strRequest == "scheduleList"{
                
                if let arrData = data["data"] as? NSArray{
                    if arrData.count != 0{
                        let arr = Mapper<SchedulesModel>().mapArray(JSONArray: arrData as! [[String : Any]])

                        if self.pageCount == 1{
                            self.arrOrderList = []
                        }
                        
                        for obj in arr{
                            self.arrOrderList.append(obj)
                        }
                        
                        //CHECK LOADING
                        self.bool_Load = true
                        if arr.count >= Int(Application.PageLimit){
                            self.bool_Load = false
                            self.pageCount += 1
                        }
                        
                        //SET THE VIEW
                        self.setTheView()
                    }
                    else{
                        //SET THE VIEW
                        self.setTheView()
                    }
                }
                else{
                }

            }
        }
        else{
            indicatorHide()
            //SET THE VIEW
            self.setTheView()
            showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
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

