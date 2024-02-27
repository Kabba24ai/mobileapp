//
//  OrderListModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 01/02/24.
//

import Foundation
import ObjectMapper

struct OrdersModel: Mappable{
    internal var id: Int?
    internal var arrProduct: [ProductModel] = []
//    internal var products: [ProductModel] = []
    internal var objAdress: AddressModel?
    internal var shipping_address: AddressModel?
    internal var billing_address: AddressModel?
    internal var arrMachineHours : [MachineHoursModel] = []
    internal var license_image_links: [String] = []
    internal var order_image_links: [String] = []
    internal var code: String?
    internal var license_images: String?
    internal var order_type: String?
    internal var customer_signature: String?
    internal var token: String?
    internal var created_at: String?
    internal var description: String?
    
    internal var payment: PaymentModel?
    internal var sub_total: String?
    internal var tax_amount: String?
    internal var amount: String?

    
    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        objAdress <- map["address"]
        shipping_address <- map["has_shipping_address"]
        billing_address <- map["has_billing_address"]
        arrMachineHours <- map["order_machine_hours"]
        license_image_links <- map["license_image_links"]
        order_image_links <- map["order_image_links"]
        code <- map["code"]
        license_images <- map["license_images"]
        order_type <- map["order_type"]
        customer_signature <- map["customer_signature"]
        token <- map["token"]
        created_at <- map["created_at"]
        arrProduct <- map["order_products"]
        description <- map["description"]

        payment <- map["payment"]
        sub_total <- map["sub_total"]
        tax_amount <- map["tax_amount"]
        amount <- map["amount"]
    }
}

struct PaymentModel: Mappable{
    internal var status: StatusModel?

    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        status <- map["status"]
    }
}

struct StatusModel: Mappable{
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

struct AddressModel: Mappable{
    internal var id: Int?
    internal var name: String?
    internal var phone: String?
    internal var email: String?
    internal var address: String?
    internal var city: String?
    internal var country: String?
    internal var state: String?
    internal var zip_code: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        name <- map["name"]
        phone <- map["phone"]
        email <- map["email"]
        address <- map["address"]
        city <- map["city"]
        country <- map["country"]
        state <- map["state"]
        zip_code <- map["zip_code"]
    }
}



struct MachineHoursModel: Mappable{
    internal var id: Int?
    internal var product_id: Int?

    internal var start: Float?
    internal var end: Float?
    internal var allocated: Int?
    internal var additinal: Int?
    internal var price: Float?

    internal var total: Float?
    internal var total_cost: Float?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        product_id <- map["product_id"]
        start <- map["start"]
        end <- map["end"]
        allocated <- map["allocated"]
        additinal <- map["over"]
        price <- map["over_rate"]
        total <- map["total"]
        total_cost <- map["total_cost"]
    }
}


extension OrderListViewController :WebServiceHelperDelegate{
    struct OrdersParameater: Codable {
        var page : String
        var limit : String = "\(Application.PageLimit)"
    }

    
    func getOrderList(OrdersParameater : OrdersParameater){
        guard let parameater = try? OrdersParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.orderList.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "orderList"
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
//            print(data)
            if strRequest == "orderList"{
                
                
                if let dicData = data["data"] as? NSDictionary{
                    if let arrData = dicData["data"] as? NSArray{
                        let arr = Mapper<OrdersModel>().mapArray(JSONArray: arrData as! [[String : Any]])

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
                    //SET THE VIEW
                    self.setTheView()
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

