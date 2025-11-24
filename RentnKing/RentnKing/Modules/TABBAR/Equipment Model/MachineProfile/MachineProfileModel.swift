//
//  MachineProfileModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 18/03/25.
//

import Foundation
import UIKit
import ObjectMapper


struct MachineProfileModel: Mappable{
    internal var id: Int?
    internal var checklist_id: Int?
    internal var order_id: Int?
    internal var tech_id: Int?
    internal var category_id: Int?
    internal var category: String?
    internal var product_name: String?
    internal var machine_id: String?
    internal var machine_status: String?
    internal var first_name: String?
    internal var last_name: String?
    internal var location_name: String?
    internal var class_name: String?
    internal var has_machine_hour: Int = 0
    internal var status_change: String?
    
    
    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        checklist_id <- map["checklist_id"]
        order_id <- map["order_id"]
        tech_id <- map["tech_id"]
        category_id <- map["imcategory_idage"]
        category <- map["category"]
        product_name <- map["product_name"]
        machine_id <- map["machine_id"]
        machine_status <- map["machine_status"]
        first_name <- map["first_name"]
        last_name <- map["last_name"]
        location_name <- map["location_name"]
        class_name <- map["class_name"]
        has_machine_hour <- map["has_machine_hour"]
        status_change <- map["status_change"]
    }
}



extension MachineProfileViewController :WebServiceHelperDelegate{
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            self.viewSearch
        ]
    }
  

    
    
    struct MAchineProfileParameater: Codable {
        var category_id : String = ""
        var class_id : String = ""
        var machine_status : String = ""
        var service_status : String = ""
        var search : String = ""
    }

    
    func getMachineProfileListAPI(MAchineProfileParameater : MAchineProfileParameater){
        
        DispatchQueue.main.async {
            if self.isLoading{
                self.machineProfilePlaceholderMarker.register(self.getAnimableSubviews())
                self.machineProfilePlaceholderMarker.startAnimation()
            }
        }
        
        guard let parameater = try? MAchineProfileParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.maintenanceProfile.absoluteString!)"
        
        print(parameater)
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "maintenanceProfile"
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
    
    
    
//    func getInventoryCategorys(){
//        
//        //Declaration URL
//        let strURL = "\(Url.categorys.absoluteString!)"
//        
//       
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "inventoryCategorys"
//        webHelper.methodType = "get"
//        webHelper.strURL = strURL
//        webHelper.dictType = [:]
//        webHelper.dictHeader = NSDictionary()
//        webHelper.delegateWeb = self
//        webHelper.showLogForCallingAPI = true
//        webHelper.serviceWithAlert = true
//        webHelper.indicatorShowOrHide = false
//        webHelper.callAPI()
//    }
   
    func getInventoryClass(){

        //Declaration URL
        let strURL = "\(Url.inventoryClass.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "inventoryClass"
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
    
    
    func getInventorystatus(){

        //Declaration URL
        let strURL = "\(Url.inventoryStatus.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "inventoryStatus"
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
    
    
    func getInventoryService(){

        //Declaration URL
        let strURL = "\(Url.inventoryService.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "inventoryService"
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
    
    
 
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String) {
        indicatorHide()
        self.isLoading = false
        self.objRefresh?.endRefreshing()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "maintenanceProfile"{
                if let arrData = data["data"] as? NSArray{
                    
                    self.arrMachineProfileList = []
                    self.arrMachineProfileList = Mapper<MachineProfileModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                   // self.arrMachineProfileList = self.arrMachineProfileList.sorted(by: { $0.category ?? "" < $1.category ?? "" })

                    
                    //SET THE VIEW
                    self.setTheView()
                }
                else{
                    //SET THE VIEW
                    self.setTheView()
                }

            }
//            else if strRequest == "inventoryCategorys"{
//                
//                if let arrData = data["data"] as? NSArray{
//                   
//                    self.arrCategorys = []
//                    self.arrCategorys = Mapper<CategoryModel>().mapArray(JSONArray: arrData as! [[String : Any]])
//                    self.arrCategorys = self.arrCategorys.sorted(by: { $0.name ?? "" < $1.name ?? "" })
//                    
//                    //SET EMPTY OBJECT
//                    var objData : CategoryModel!
//                    let map = Map(mappingType: .fromJSON, JSON: [:])
//                    objData = CategoryModel(map: map)
//                    objData.id = 0
//                    objData.name = "All"
//                    
//                    //ADD
//                    self.arrCategorys.insert(objData, at: 0)
//                }
//            }
            
            else if strRequest == "inventoryClass"{
                print(data)
                
                if let arrData = data["data"] as? NSArray{
                    
                    self.arrClass = []
                    self.arrClass = Mapper<CategoryModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrClass = self.arrClass.sorted(by: { $0.name ?? "" < $1.name ?? "" })
                    
                    //SET EMPTY OBJECT
                    var objData : CategoryModel!
                    let map = Map(mappingType: .fromJSON, JSON: [:])
                    objData = CategoryModel(map: map)
                    objData.id = 0
                    objData.name = "All"
                    
                    //ADD
                    self.arrClass.insert(objData, at: 0)
                }
            }
            
            else if strRequest == "inventoryStatus"{
                if let arrData = data["data"] as? NSArray{
                    
                    self.arrStatues = []
                    self.arrStatues = Mapper<InventoryStatusModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrStatues = self.arrStatues.sorted(by: { $0.text ?? "" < $1.text ?? "" })
                    
                    //SET EMPTY OBJECT
                    var objData : InventoryStatusModel!
                    let map = Map(mappingType: .fromJSON, JSON: [:])
                    objData = InventoryStatusModel(map: map)
                    objData.value = "All"
                    objData.text = "All"
                    
                    //ADD
                    self.arrStatues.insert(objData, at: 0)
                }
            }
            
            else if strRequest == "inventoryService"{
                indicatorHide()

                if let arrData = data["data"] as? NSArray{
                    
                    self.arrServices = []
                    self.arrServices = Mapper<InventoryStatusModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrServices = self.arrServices.sorted(by: { $0.text ?? "" < $1.text ?? "" })
                    
                    //SET EMPTY OBJECT
                    var objData : InventoryStatusModel!
                    let map = Map(mappingType: .fromJSON, JSON: [:])
                    objData = InventoryStatusModel(map: map)
                    objData.value = "All"
                    objData.text = "All"
                    
                    //ADD
                    self.arrServices.insert(objData, at: 0)
                }
            }
        }
        else{
            indicatorHide()
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        self.isLoading = false

        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}
