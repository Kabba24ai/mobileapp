//
//  MachineProfileModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 18/03/25.
//

import Foundation
import UIKit
import ObjectMapper

struct FilterTypes {
    let text: String?
    let value: String?
}


struct MachineModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var category_id: Int?
    internal var equipment_id: String?
    internal var equipment_name: String?
    internal var status: String?
    internal var powerSourceType: String = ""
    internal var hasDEF: String = ""
    internal var gas_tank_capacity: String = ""
    internal var def_tank_capacity: String = ""
    internal var diesel_tank_capacity: String = ""
    internal var current_order_unique_id: String = ""
    internal var current_status : String = ""
    internal var current_status_updated_by : String = ""
    internal var current_status_changed_at : String = ""
    internal var objProductCategory : ProductCategoryModel?
    
    internal var overage_rate : String = ""
    internal var hour_tracking : String = ""
    internal var arrCheckList : [ChecklistQuestionsModel] = []
    internal var arrAnswerRentalCheckList: [RentalReadyModel]?//: [RentalReadyAnswerModel]?
    
    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        category_id <- map["product_category_id"]
        equipment_id <- map["equipment_id"]
        equipment_name <- map["equipment_name"]
        equipment_name <- map["equipment_name"]
        status <- map["current_status"]
        powerSourceType <- map["power_source_type"]
        hasDEF <- map["has_def"]
        gas_tank_capacity <- map["gas_tank_capacity"]
        def_tank_capacity <- map["def_tank_capacity"]
        diesel_tank_capacity <- map["diesel_tank_capacity"]
        current_order_unique_id <- map["current_order_unique_id"]
        overage_rate <- map["overage_rate"]
        hour_tracking <- map["is_tracked"]
        current_status <- map["current_status"]
        arrCheckList <- map["checklist_qas"]
        current_status_updated_by <- map["current_status_updated_by"]
        current_status_changed_at <- map["current_status_changed_at"]
        objProductCategory <- map["product_category"]
        arrAnswerRentalCheckList <- map["rental_ready_checklist_questions"]
    }
}

struct ProductCategoryModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var title: String?
    
    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        title <- map["title"]
    }
}


struct ChecklistQuestionsModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var question_name: String?
    internal var question_delivery_text: String?
    internal var question_return_text: String?
    internal var required_question: Bool?
    internal var arrAnswer: [ChecklistAnswerModel]?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        question_name <- map["question_name"]
        question_delivery_text <- map["question_delivery_text"]
        question_return_text <- map["question_return_text"]
        required_question <- map["required_question"]
        arrAnswer <- map["answers"]
    }
}

struct ChecklistAnswerModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var answer_delivery_text: String?
    internal var answer_return_text: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        answer_delivery_text <- map["answer_delivery_text"]
        answer_return_text <- map["answer_return_text"]
    }
}


extension MachineProfileViewController :WebServiceHelperDelegate{
//    func getAnimableSubviews() -> [UIView] {
//        return [UIView](getAllSubviews())
//    }
//    
//    private func getAllSubviews() -> [UIView] {
//        return [
//            self.viewSearch
//        ]
//    }
//  


//    struct EquipmentParameater: Codable {
//        var type : String = ""
//    }
    
//    func getMachineProfileListAPI(EquipmentParameater : EquipmentParameater){
//        
//        DispatchQueue.main.async {
//            if self.isLoading{
//                self.machineProfilePlaceholderMarker.register(self.getAnimableSubviews())
//                self.machineProfilePlaceholderMarker.startAnimation()
//            }
//        }
//        
//        guard let parameater = try? EquipmentParameater.asDictionary() else {
//            showAlertMessage(strMessage: str.invalidRequestParamater)
//            return
//        }
//
//        //Declaration URL
//        let strURL = "\(Url.equipmentList.absoluteString!)"
//
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "equipmentList"
//        webHelper.methodType = "post"
//        webHelper.strURL = strURL
//        webHelper.dictType = parameater
//        webHelper.dictHeader = NSDictionary()
//        webHelper.delegateWeb = self
//        webHelper.showLogForCallingAPI = true
//        webHelper.serviceWithAlert = true
//        webHelper.indicatorShowOrHide = false
//        webHelper.callAPI()
//    }
    
    
    
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
   
//    func getInventoryClass(){
//
//        //Declaration URL
//        let strURL = "\(Url.inventoryClass.absoluteString!)"
//        
//       
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "inventoryClass"
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
//    
//    
//    func getInventorystatus(){
//
//        //Declaration URL
//        let strURL = "\(Url.inventoryStatus.absoluteString!)"
//        
//       
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "inventoryStatus"
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
//    
//    
//    func getInventoryService(){
//
//        //Declaration URL
//        let strURL = "\(Url.inventoryService.absoluteString!)"
//        
//       
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "inventoryService"
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
//    
    
 
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String) {
        indicatorHide()
        self.isLoading = false
        self.objRefresh?.endRefreshing()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "equipmentList"{
                if let arrData = data["equipment"] as? NSArray{
                    
                    self.arrMachineProfileList = []
                    self.arrMachineProfileList = Mapper<MachineModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrMainMachineProfileList = self.arrMachineProfileList
                    
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
            
//            else if strRequest == "inventoryClass"{
//                print(data)
//                
//                if let arrData = data["data"] as? NSArray{
//                    
//                    self.arrClass = []
//                    self.arrClass = Mapper<CategoryModel>().mapArray(JSONArray: arrData as! [[String : Any]])
//                    self.arrClass = self.arrClass.sorted(by: { $0.name ?? "" < $1.name ?? "" })
//                    
//                    //SET EMPTY OBJECT
//                    var objData : CategoryModel!
//                    let map = Map(mappingType: .fromJSON, JSON: [:])
//                    objData = CategoryModel(map: map)
//                    objData.id = 0
//                    objData.name = "All"
//                    
//                    //ADD
//                    self.arrClass.insert(objData, at: 0)
//                }
//            }
//            
//            else if strRequest == "inventoryStatus"{
//                if let arrData = data["data"] as? NSArray{
//                    
//                    self.arrStatues = []
//                    self.arrStatues = Mapper<InventoryStatusModel>().mapArray(JSONArray: arrData as! [[String : Any]])
//                    self.arrStatues = self.arrStatues.sorted(by: { $0.text ?? "" < $1.text ?? "" })
//                    
//                    //SET EMPTY OBJECT
//                    var objData : InventoryStatusModel!
//                    let map = Map(mappingType: .fromJSON, JSON: [:])
//                    objData = InventoryStatusModel(map: map)
//                    objData.value = "All"
//                    objData.text = "All"
//                    
//                    //ADD
//                    self.arrStatues.insert(objData, at: 0)
//                }
//            }
//            
//            else if strRequest == "inventoryService"{
//                indicatorHide()
//
//                if let arrData = data["data"] as? NSArray{
//                    
//                    self.arrServices = []
//                    self.arrServices = Mapper<InventoryStatusModel>().mapArray(JSONArray: arrData as! [[String : Any]])
//                    self.arrServices = self.arrServices.sorted(by: { $0.text ?? "" < $1.text ?? "" })
//                    
//                    //SET EMPTY OBJECT
//                    var objData : InventoryStatusModel!
//                    let map = Map(mappingType: .fromJSON, JSON: [:])
//                    objData = InventoryStatusModel(map: map)
//                    objData.value = "All"
//                    objData.text = "All"
//                    
//                    //ADD
//                    self.arrServices.insert(objData, at: 0)
//                }
//            }
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
