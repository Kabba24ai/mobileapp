//
//  ProductList.swift
//  RentnKing
//
//  Created by Jigar Khatri on 13/01/24.
//

import Foundation
import ObjectMapper
import UIKit



struct ProductModel: Mappable{
    internal var id: Int?
    internal var product_id: Int?
    internal var name: String?
    internal var product_name: String?
    internal var price: Float?
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

    
    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        product_id <- map["product_id"]
        name <- map["name"]
        product_name <- map["product_name"]
        image <- map["image"]
        product_image <- map["product_image"]
        images <- map["images"]
        price <- map["price"]
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
    
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()
        self.isLoading = false

        let arrKey  = data.allKeys as [AnyObject]
        if (arrKey.firstIndex(where: { $0 as! String == "error" }) == nil){
            print(data)
            if strRequest == "categoryProducts"{
                if data.getStringForID(key: "success") == "1"{
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
                else{
                    //SET THE VIEW
                    self.setTheView()

                    
                    //NO DATA
                    self.emptyDataView.isHidden = false
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
}

