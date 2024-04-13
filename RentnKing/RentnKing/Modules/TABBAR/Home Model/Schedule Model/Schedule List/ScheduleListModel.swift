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
    internal var product_id: Int?
    internal var phone: String?
    internal var delivery_date: String?
    internal var delivery_status: Type_Status?
    internal var delivery_time: String?
    internal var customer_delivery: Int?
    internal var pickup_date: String?
    internal var pickup_status: Type_Status?
    internal var pickup_time: String?
    internal var customer_pickup: Int?
    internal var order: OrdersModel?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        name <- map["name"]
        location <- map["location"]
        order_id <- map["order_id"]
        product_id <- map["product_id"]
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
    var id : String
    var delivery_status : String
    var pickup_status : String
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
        var limit : String = "\(Application.PageLimit)"
        var type : String //Delivery,Pickup
        var status : String  // 1 = pending , 2 = completed
        
        var search : String = ""
        var category_id : String = ""
        var deliveryType : String = ""
    }

    
    func getScheduleList(OrdersParameater : OrdersParameater){
        DispatchQueue.main.async {
            if self.isHeaderLoading{
                self.schedulePlaceholderMarker.register(self.getAnimableSubviews())
                self.schedulePlaceholderMarker.startAnimation()
            }
        }
        
        guard let parameater = try? OrdersParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.scheduleList.absoluteString!)"
        
        print("============")
        print(strURL)
        print(parameater)

       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "scheduleList"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
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
    
    
    func getCategorys(){

        //Declaration URL
        let strURL = "\(Url.categorys.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "categorys"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
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
        self.isHeaderLoading = false
        self.stopAnimatingView()
        self.objRefresh?.endRefreshing()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "scheduleList"{
                if let dicData = data["data"] as? NSDictionary{
                    if let arrData = dicData["data"] as? NSArray{
                        if arrData.count != 0{
                            let arr = Mapper<SchedulesModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                            
                            if self.pageCount == 1{
                                self.arrScheduleList = []
                            }
                            
                            for obj in arr{
                                self.arrScheduleList.append(obj)
                            }
                            
                        
                            //SET FILTER
//                            self.filter()
                            
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
                }
            }
            else if strRequest == "categorys"{
                if data.getStringForID(key: "success") == "1"{
                    if let arrData = data["data"] as? NSArray{
                       
                        self.arrCategorys = []
                        self.arrCategorys = Mapper<CategoryModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                        self.arrCategorys = self.arrCategorys.sorted(by: { $0.name ?? "" < $1.name ?? "" })
                        
                        //SET EMPTY OBJECT
                        var objData : CategoryModel!
                        let map = Map(mappingType: .fromJSON, JSON: [:])
                        objData = CategoryModel(map: map)
                        objData.id = 0
                        objData.name = "All"
                        
                        //ADD
                        self.arrCategorys.insert(objData, at: 0)
                    }
                }
            }
            else if strRequest == "scheduleUpdate"{
                //UPDATE COUNT
                GlobalMainConstants.appDelegate?.getScheduleCount()
                

                print(data)
                if self.arrScheduleList.count != 0{
                    
                    if self.arrScheduleList.count == 0{
                        return
                    }
                    let objData = self.arrScheduleList[index]

                    
                 
                    //TERMS AND CONDITION
                    let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
                    if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
                        newViewController.delegate = self
                        newViewController.selectIndex = index
                        newViewController.strOrderID = "\(objData.order_id ?? 0)"
                        newViewController.strProductID = "\(objData.product_id ?? 0)"
                        self.navigationController?.pushViewController(newViewController, animated: true)
                    }
                    
                    
                    //UPDATE OBJECT
                    if self.selectStatus == "2"{
                        
                        //UPDATE ARRAY
                        var objData = self.arrScheduleList[index]
                        if self.selectType.lowercased() == "Delivery".lowercased(){
                            objData.delivery_status?.value = "2"
                        }
                        else{
                            objData.pickup_status?.value = "2"
                        }
                        
                        self.arrScheduleList.remove(at: index)
                        self.arrScheduleList.insert(objData, at: index)
                        
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                            //RELOAD TABLE
                            self.tblView.reloadData()
                        }
                    }
                    else{
                        self.arrScheduleList.remove(at: index)

                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                            //RELOAD TABLE
                            self.tblView.reloadData()
                        }
                    }
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

