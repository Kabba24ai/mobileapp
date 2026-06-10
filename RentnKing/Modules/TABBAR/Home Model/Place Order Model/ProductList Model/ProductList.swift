//
//  ProductList.swift
//  RentnKing
//
//  Created by Jigar Khatri on 13/01/24.
//

import Foundation
import ObjectMapper
import UIKit

struct Product: Mappable{
    internal var id: Int?
    internal var use_global:Bool?
    internal var checklist_id: Int?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        use_global <- map["use_global"]
        checklist_id <- map["checklist_id"]

    }
}


//struct OrderProductModel: Mappable{
//    internal var id: Int?
//    internal var unique_id: String?
//    internal var product_name: String?
//    internal var price: String?
//    internal var quantity: Int?
//    internal var sub_total: String?
//    internal var tax: String?
//    internal var total: String?
//    internal var objProductData : ProductDataModel?
//    internal var is_delivered: Bool?
//    internal var is_returned: Bool?
//    internal var arrDeliveryMedia: [LicenseModel] = []
//    internal var arrPickupMedia: [LicenseModel] = []
//    internal var equipment_location: String?
//
//    
//    init?(map:Map) {
//        mapping(map: map)
//    }
//    
//    mutating func mapping(map:Map){
//        id <- map["id"]
//        unique_id <- map["unique_id"]
//        product_name <- map["product_name"]
//        price <- map["price"]
//        quantity <- map["quantity"]
//        sub_total <- map["sub_total"]
//        tax <- map["tax"]
//        total <- map["total"]
//        objProductData <- map["product_data"]
//        is_delivered <- map["is_delivered"]
//        is_returned <- map["is_returned"]
//        arrDeliveryMedia <- map["delivery_media"]
//        arrPickupMedia <- map["pickup_media"]
//    }
//}

struct ProductModel: Mappable{
    internal var id: Int?
    internal var product_id: Int?
    internal var unique_id: String?
    internal var machine_id: Int?
    internal var objProductData : ProductDataModel?

//    internal var hour_tracking : Bool?
//    internal var hour_rate : Float?
    internal var allocated_hours : Float?

    internal var objCategory: CategoryModel?
    internal var objMachine: MachineModel?
    internal var objProduct: Product?
    internal var storeAdderss: StoreModel?
    internal var arrQuestions: [CustomerCheckListModel] = []
//    internal var checkList: CheckListModel?
    internal var name: String?
    internal var product_name: String?
    internal var price: Float?
    internal var quantity: Int?
    internal var sub_total: String?
    internal var tax: String?
    internal var total: String?

    internal var product_price: String?
    internal var image: String?
    internal var product_image: String?
    internal var images: [String]?
    internal var order: Int?
    internal var content: String?
    internal var description: String?
    internal var options: [ProductOptionsModel] = []
    internal var product_options: ProductOptionsModel!
    internal var dicOptions: NSDictionary?
    internal var qty: Int = 1
    internal var selectDate: String = ""
    internal var arrTaxes: [ProductTaxessModel] = []
    internal var objMachineHours : MachineHoursModel!
    internal var store_pickup: Int?
    internal var delivery_pickup: Int?
    internal var delivery_price: Float?
    internal var delivery_range: Int?
    internal var delivery: Bool?
    internal var pickup: Bool?
    internal var storeID: String = ""

    internal var delivery_note: String = ""
    internal var delivery_emp: Int = 0
    internal var delivery_sign: String = ""
    internal var returned_note: String = ""
    internal var returned_emp: Int = 0
    internal var return_sign: String = ""

    internal var inTime: String = ""
    internal var outTime: String = ""

    internal var start_hours: Float = 0.0
    internal var end_hours: Float = 0.0
    internal var total_charge: Float = 0.0

    internal var is_delivered: Bool?
    internal var is_returned: Bool?

    internal var power_source_type: String?
    internal var has_def: String?

    
    internal var fuel_final_reading: String = ""
    internal var fuel_initial_reading: String = ""

    internal var equipment_location: String?

    internal var arrDeliveryMedia: [LicenseModel] = []
    internal var arrPickupMedia: [LicenseModel] = []

    internal var delivery_store: StoreOptionsModel?
    internal var pickup_store: StoreOptionsModel?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        objProductData <- map["product_data"]
//        hour_tracking <- map["hour_tracking"]
//        hour_rate <- map["hour_rate"]
        allocated_hours <- map["allocated_hours"]
        arrQuestions <- map["customer_checklist_questions"]
        unique_id <- map["unique_id"]
        product_id <- map["product_id"]
        machine_id <- map["machine_id"]
        objMachine <- map["equipment_details"]
        objProduct <- map["product"]
        storeAdderss <- map["store"]
//        checkList <- map["checklist"]
        name <- map["name"]
        product_name <- map["product_name"]
        image <- map["image"]
        product_image <- map["product_image"]
        images <- map["images"]
        price <- map["price"]
        quantity <- map["quantity"]
        sub_total <- map["sub_total"]
        tax <- map["tax"]
        total <- map["total"]

        product_price <- map["price"]
        qty <- map["qty"]
        order <- map["order"]
        content <- map["content"]
        description <- map["description"]
        options <- map["options"]
        product_options <- map["options"]
        dicOptions <- map["product_options"]
        arrTaxes <- map["taxes"]
        
        store_pickup <- map["store_pickup"]
        delivery_pickup <- map["delivery_pickup"]
        delivery_price <- map["delivery_price"]
        delivery_range <- map["delivery_range"]
        storeID <- map["storeID"]

        delivery_note <- map["delivery_note"]
        delivery_emp <- map["delivery_by"]
        delivery_sign <- map["delivery_signature_media_url"]
        returned_note <- map["returned_note"]
        returned_emp <- map["pickup_by"]
        return_sign <- map["return_signature_media_url"]

//        inTime <- map["in_time"]
//        outTime <- map["out_time"]
        
        start_hours <- map["start_hours"]
        end_hours <- map["end_hours"]

        is_delivered <- map["is_delivered"]
        is_returned <- map["is_returned"]

        total_charge <- map["total_charge"]
        
        power_source_type <- map["power_source_type"]
        has_def <- map["has_def"]

        fuel_final_reading <- map["fuel_final_reading"]
        fuel_initial_reading <- map["fuel_initial_reading"]
        
        equipment_location <- map["equipment_location"]

        arrDeliveryMedia <- map["delivery_media"]
        arrPickupMedia <- map["pickup_media"]

        delivery_store <- map["delivery_store"]
        pickup_store <- map["pickup_store"]

    }
}


struct ProductOptionsModel: Mappable{
    internal var id: Int?
    internal var name: String?
    internal var product_name: String?
    internal var values :[OptionsValueModel] = []
    internal var deldate: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        name <- map["name"]
        product_name <- map["product_name"]
        values <- map["values"]
        deldate <- map["deldate"]

    }
}

struct StoreOptionsModel: Mappable{
    internal var id: Int?
    internal var name: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        name <- map["store_name"]
        
    }
}



struct OptionsValueModel: Mappable{
    internal var id: Int?
    internal var option_value: String?
    internal var value_type: Bool?
    internal var type: Bool?
    internal var comment: String?
    internal var price: Float?
    internal var isDisplay: Bool = true


    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        option_value <- map["option_value"]
        value_type <- map["value_type"]
        type <- map["value_type"]
        comment <- map["comment"]
        price <- map["affect_price"]

    }
}



struct ProductTaxessModel: Mappable{
    internal var id: Int?
    internal var title: String?
    internal var percentage: Float?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        title <- map["title"]
        percentage <- map["percentage"]

    }
}



extension ProductListViewController :WebServiceHelperDelegate{
    struct ProductParameater: Codable {
        var category_id : String
    }
    
    func getProductList(ProductParameater : ProductParameater){
        
        guard let parameater = try? ProductParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.categoryProducts.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "categoryProducts"
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
    
    struct ProductSearchParameater: Codable {
        var product_search : String
    }
    
    func getProductSearchList(ProductSearchParameater : ProductSearchParameater){
        
        guard let parameater = try? ProductSearchParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.searchProducts.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "searchProducts"
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
    
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
        indicatorHide()
        self.isLoading = false

        let arrKey  = data.allKeys as [AnyObject]
        if (arrKey.firstIndex(where: { $0 as! String == "error" }) == nil){
//            print(data)
            if data.getStringForID(key: "success") == "1"{

                if strRequest == "categoryProducts"{
                    if let objData = data["data"] as? NSDictionary{
                        if let objProduct = objData["products"] as? NSDictionary{
                            if let arrData = objProduct["data"] as? NSArray{
                                self.arrProductList = []
                                self.arrProductList = Mapper<ProductModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                                self.arrProductList = self.arrProductList.sorted(by: { $0.order ?? 0 < $1.order ?? 0})

                                //SET THE VIEW
                                self.setTheView()

                            }
                            else{
                                //SET THE VIEW
                                self.setTheView()

                            }
                        }
                        else{
                            //SET THE VIEW
                            self.setTheView()
                        }
                    }else{
                        //SET THE VIEW
                        self.setTheView()

                    }
                }
                else if strRequest == "searchProducts"{
                    if let arrData = data["data"] as? NSArray{
                        self.arrProductList = []
                        self.arrProductList = Mapper<ProductModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                        self.arrProductList = self.arrProductList.sorted(by: { $0.order ?? 0 < $1.order ?? 0})

                        //SET THE VIEW
                        self.setTheView()

                    }
                    else{
                        //SET THE VIEW
                        self.setTheView()

                    }
                }

            }
            else{
                //SET THE VIEW
                self.setTheView()

                
                //NO DATA
                self.emptyDataView.isHidden = false
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
}

