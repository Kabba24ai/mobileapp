//
//  File.swift
//  RentnKing
//
//  Created by Jigar Khatri on 16/01/24.
//

import Foundation
import UIKit
import ObjectMapper

struct StoreModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var name: String?
    internal var phone: String?
    internal var address: String?
    internal var city: String?
    internal var state: String?
    internal var zip_code: String?

    internal var fullAddress: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        name <- map["store_name"]
        phone <- map["phone"]
        address <- map["full_address"]
        city <- map["city"]
        state <- map["state"]
        zip_code <- map["zip_code"]
    }
}



struct CheckListModel: Mappable{
    internal var id: Int?
    internal var arrQuestions: [QuestionsListModel]?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        arrQuestions <- map["questions"]
    }
}


struct QuestionsListModel: Mappable{
    internal var checklist_id: Int?
    internal var objQuestion: QuestionsModel?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        checklist_id <- map["checklist_id"]
        objQuestion <- map["question"]
    }
}


struct QuestionsModel: Mappable{
    internal var id: Int?
    internal var question: String?
    internal var question_value: Float?
    internal var delivered: Float = -1
    internal var returned: Float = -1
   
    internal var balance: Float?
    internal var customerOwes: Float?

    internal var checklist_type: String?
    internal var arrAnswer: [AnswerCheckListModel] = []
    internal var objSelectAnswer: SelectAnswerModel!
    internal var fuel_type : Int = 0
    
    internal var sd_clean_price: String?
    internal var ex_clean_price: String?

    internal var tires_values: [String : String] = [:]
    internal var fuel_values_with_guage: [String : String] = [:]
    internal var fuel_values_with_no_guage: [String : String] = [:]
    internal var clean_delivered_values: [String : String] = [:]
    internal var clean_returned_values: [String : String] = [:]


    
    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        question <- map["question"]
        question_value <- map["question_value"]
        delivered <- map["in"]
        returned <- map["out"]

        checklist_type <- map["checklist_type"]
        arrAnswer <- map["answers"]

        sd_clean_price <- map["sd_clean_price"]
        ex_clean_price <- map["ex_clean_price"]
        
        fuel_type <- map["fuel_type"]
        tires_values <- map["tires_values"]
        fuel_values_with_guage <- map["fuel_values_with_guage"]
        fuel_values_with_no_guage <- map["fuel_values_with_no_guage"]
        clean_delivered_values <- map["clean_delivered_values"]
        clean_returned_values <- map["clean_returned_values"]
        objSelectAnswer <- map["selected_status"]
    }
}

struct SelectAnswerModel: Mappable{
    internal var answer: String?
    internal var status: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        answer <- map["answer"]
        status <- map["status"]
    }
}




extension ProductDetailsViewController :WebServiceHelperDelegate{
    struct ProductParameater: Codable {
        var product_id : String
    }
    
    func getProductList(ProductParameater : ProductParameater){
        DispatchQueue.main.async {
            self.productDetailsPlaceholderMarker.register(self.getAnimableSubviews())
            self.productDetailsPlaceholderMarker.startAnimation()
        }
        
        guard let parameater = try? ProductParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.productsDetaisl.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "productsDetaisl"
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
    
    func getStoreAddress(){
       
        //Declaration URL
        let strURL = "\(Url.getStores.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "getStores"
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


        
        let arrKey  = data.allKeys as [AnyObject]
        if (arrKey.firstIndex(where: { $0 as! String == "error" }) == nil){
            print(data)
            if strRequest == "productsDetaisl"{
                if data.getStringForID(key: "success") == "1"{
                    if let objData = data["data"] as? NSDictionary{
                       

                        
                        //SET DATA
                        let map = Map(mappingType: .fromJSON, JSON: objData as! [String : Any])
                        self.objData = ProductModel(map: map)

                        //SET THE VIEW
                        self.setTheView()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                            //SET DETAILS
                            self.setDetails()
                        }
                    }
                }
                else{
                    //SET THE VIEW
                    self.setDetails()

                    
                    //NO DATA
                    self.tblView.isHidden = true
                    self.emptyDataView.isHidden = false
                }
            }
            else if strRequest == "getStores"{
                if let arrData = data["data"] as? NSArray{
                    
                    let arr = Mapper<StoreModel>().mapArray(JSONArray: arrData as! [[String : Any]])

                    self.arrStoreList = []
                    for obj in arr{
                        let address = "\(obj.address ?? ""), \(obj.city ?? ""), \(obj.state ?? ""), \(obj.zip_code ?? "")"
                        
                        var objData = obj
                        objData.fullAddress = address
                        self.arrStoreList.append(objData)
                    }
                    
                    //CEHCK DATA
                    if objData != nil{
                        if objData.storeID != ""{
                            self.selectWillPickup = true
                            
                            let MenuID = self.arrStoreList.map{$0.id}
                            if let index = MenuID.firstIndex(of: Int(objData.storeID )){
                                
                                self.txtStore.text = self.arrStoreList[index].fullAddress
                                self.storeID = objData.storeID 
                            }
                        }
                    }
 
                }
            }
        }
        else{
            indicatorHide()
            showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        
        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
    
    
    
    //LOADER
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            imgProduct,
            viewPrice,
            lblName,
            addToCartBUtton,
            lblSelectTitle,
            viewSelectDate,
            lblDetails,
            viewAddCart,
            lblDeliveryOptions,
            imgWantDelivery,
            lblWantDelivery,
            imgWillPickup,
            lblWillPickup
        ]
    }
}


