//
//  OrderListModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 01/02/24.
//

import Foundation
import ObjectMapper
import UIKit
import CoreData



struct OrdersModel: Mappable{
    internal var id: Int?
    internal var arrProduct: [ProductModel] = []
    internal var products: [ProductModel] = []
    internal var objAdress: AddressModel?
    internal var shipping_address: AddressModel?
    internal var billing_address: AddressModel?
    internal var arrMachineHours : [MachineHoursModel] = []
    internal var addLicenseImageLocally: Bool = false
    internal var license_image_links: [String] = []
    internal var order_image_links: [String] = []
    internal var has_checklist: Int?
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
    
    internal var arrDeliveryStatus: [DeliveryModel] = []
    
    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        id <- map["id"]
        objAdress <- map["address"]
        billing_address <- map["has_shipping_address"]
        shipping_address <- map["has_billing_address"]
        arrMachineHours <- map["order_machine_hours"]
        license_image_links <- map["license_image_links"]
        order_image_links <- map["order_image_links"]
        has_checklist <- map["has_checklist"]
        code <- map["code"]
        license_images <- map["license_images"]
        order_type <- map["order_type"]
        customer_signature <- map["customer_signature"]
        token <- map["token"]
        created_at <- map["created_at"]
        arrProduct <- map["order_products"]
        products <- map["products"]
        description <- map["description"]
        
        payment <- map["payment"]
        sub_total <- map["sub_total"]
        tax_amount <- map["tax_amount"]
        amount <- map["amount"]
        arrDeliveryStatus <- map["deliveries"]
    }
}

struct OrdersListModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var order_number: String?
    internal var customer_name: String?
    internal var customer_email: String?
    internal var customer_phone: String?
    internal var status: String?
    internal var order_date: String?
    internal var payment_type: String?
    internal var payment_status: String?
    internal var objDeliveryAddress: AddressModel?
    internal var objBillingAddress: AddressModel?
    internal var arrProduct : [ProductModel] = []
    internal var arrOrderNote : [OrderNoteModel] = []
    internal var terms_status : String?
    internal var terms_page : String?
    internal var sub_total: String?
    internal var subtotal: String?
    internal var tax_amount: String?
    internal var total: String?
    internal var amount: String?
    internal var is_tax_exempt: String?
    internal var is_same_as_billing: Bool?
    internal var arrLicense: [LicenseModel] = []

    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        order_number <- map["order_number"]
        customer_name <- map["customer_name"]
        customer_email <- map["customer_email"]
        customer_phone <- map["customer_phone"]
        status <- map["status"]
        order_date <- map["order_date"]
        amount <- map["amount"]
        payment_type <- map["payment_type"]
        payment_status <- map["payment_status"]
        objDeliveryAddress <- map["delivery_address"]
        objBillingAddress <- map["billing_address"]
        arrProduct <- map["order_products"]
        arrOrderNote <- map["order_notes"]
        terms_status <- map["terms_status"]
        terms_page <- map["terms_page"]
        sub_total <- map["sub_total"]
        subtotal <- map["subtotal"]
        tax_amount <- map["tax_amount"]
        amount <- map["amount"]
        is_tax_exempt <- map["is_tax_exempt"]
        is_same_as_billing <- map["is_same_as_billing"]
        arrLicense <- map["license"]

    }
}


struct LicenseModel: Mappable{
    internal var id: Int?
    internal var type: String?
    internal var side: String?
    internal var media_url: String?
    internal var media_type: String?

    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        id <- map["id"]
        type <- map["type"]
        side <- map["side"]
        media_url <- map["media_url"]
        media_type <- map["media_type"]
    }
}



struct AddressModel: Mappable{
    internal var id: Int?
    internal var order_id: Int?
    internal var first_name: String?
    internal var last_name: String?
    internal var full_name: String?
    internal var full_address: String?
    internal var phone: String?
    internal var email: String?
    internal var address: String?
    internal var city: String?
    internal var state_id: String?
    internal var state: String?
    internal var zip_code: String?
    
    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        id <- map["id"]
        order_id <- map["order_id"]
        first_name <- map["first_name"]
        last_name <- map["last_name"]
        full_name <- map["full_name"]
        full_address <- map["full_address"]
        phone <- map["phone"]
        email <- map["email"]
        address <- map["address"]
        city <- map["city"]
        state_id <- map["state_id"]
        state <- map["state"]
        zip_code <- map["zip_code"]
    }
}



struct OrderProductModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var product_name: String?
    internal var price: String?
    internal var quantity: Int?
    internal var sub_total: String?
    internal var tax: String?
    internal var total: String?
    internal var objProductData : ProductDataModel?
    internal var is_delivered: Bool?
    internal var is_returned: Bool?
    internal var arrDeliveryMedia: [LicenseModel] = []
    internal var arrPickupMedia: [LicenseModel] = []
    internal var equipment_location: String?

    
    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        product_name <- map["product_name"]
        price <- map["price"]
        quantity <- map["quantity"]
        sub_total <- map["sub_total"]
        tax <- map["tax"]
        total <- map["total"]
        objProductData <- map["product_data"]
        is_delivered <- map["is_delivered"]
        is_returned <- map["is_returned"]
        arrDeliveryMedia <- map["delivery_media"]
        arrPickupMedia <- map["pickup_media"]
        equipment_location <- map["equipment_location"]
    }
}

struct ProductDataModel: Mappable{
    internal var product_image_url: String?
    internal var product_type: String?
    internal var product_variant: String?
    internal var product_price: String?
    internal var pickup_date: String?
    internal var pickup_transport_mode: String?
    internal var delivery_date: String?
    internal var delivery_transport_mode: String?
    internal var store_name: String?
    internal var store_address: String?
    internal var arrProductOptions: [ProductOptionsItemsModel] = []
    internal var arrProductMoreOptions: [ProductOptionsItemsModel] = []

    internal var distance_type: String?
    internal var distance_range: String?
    internal var service_option_price: Float?

    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        product_image_url <- map["product_image_url"]
        product_type <- map["product_type"]
        product_variant <- map["product_variant"]
        pickup_date <- map["pickup_date"]
        product_price <- map["product_price"]
        pickup_transport_mode <- map["pickup_transport_mode"]
        delivery_date <- map["delivery_date"]
        delivery_transport_mode <- map["delivery_transport_mode"]
        arrProductOptions <- map["product_option_items"]
        arrProductMoreOptions <- map["product_rental_items_prices_with_labels"]
        store_name <- map["store_name"]
        store_address <- map["store_address"]

        distance_type <- map["distance_type"]
        distance_range <- map["distance_range"]
        service_option_price <- map["service_option_price"]
    }
}


struct ProductOptionsItemsModel: Mappable{
    internal var name: String?
    internal var label: String?
    internal var value: Float?
    internal var price: Float?

    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        name <- map["name"]
        label <- map["label"]
        value <- map["value"]
        price <- map["price"]
    }
}







struct OrderNoteModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var note: String?
    internal var created_by_id: Int?
    internal var created_by: String?
    internal var created_at: String?
    internal var status: String?
    internal var type: String?
    internal var mainOrderUniqueID: String?
    
    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        note <- map["note"]
        created_by_id <- map["created_by_id"]
        created_by <- map["created_by"]
        created_at <- map["created_at"]
        status <- map["status"]
        type <- map["type"]
        mainOrderUniqueID <- map["mainOrderUniqueID"]
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

struct DeliveryModel: Mappable{
    internal var id: Int?
    internal var product_id: Int?
    
    internal var delivery_date: String?
    internal var delivery_status: Type_Status?
    internal var delivery_time: String?
    internal var customer_delivery: Int?
    
    internal var pickup_date: String?
    internal var pickup_status: Type_Status?
    internal var pickup_time: String?
    internal var customer_pickup: Int?
    
    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        id <- map["id"]
        product_id <- map["product_id"]
        
        delivery_date <- map["delivery_date"]
        delivery_status <- map["delivery_status"]
        delivery_time <- map["delivery_time"]
        customer_delivery <- map["customer_delivery"]
        
        pickup_date <- map["pickup_date"]
        pickup_status <- map["pickup_status"]
        pickup_time <- map["pickup_time"]
        customer_pickup <- map["customer_pickup"]
    }
}
struct CatrgoryParameater: Codable {
    var page : String = "1"
    var per_page : String = "100"
}



extension OrderListViewController {//}:WebServiceHelperDelegate{
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            viewSearch
        ]
    }
    
    struct OrdersParameater: Codable {
        var page : String
        var per_page : String = "50"
        var search : String = ""
        var category_id : String = ""
        var status : String = "All"
        var payment_method  : String = "All"
    }
    
    
 
    
    func callAPIforGetOrderList(OrdersParameater: OrdersParameater, completion: @escaping (Bool) -> Void) {
        
        guard let parameters = try? OrdersParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            completion(false)
            return
        }
        
        let strURL = "\(Url.orderList.absoluteString!)"
        
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
                
                let newOrders = Mapper<OrdersListModel>().mapArray(JSONArray: arrData)
                
                // Manage local storage
                if self.pageCount == 1 {
                    // Overwrite old data
                    SDKUserDefault.saveMappableArray(newOrders, for: kFileStorageName.kOrderList.rawValue)
                } else {
                    // Append to local
                    var existing = self.getOrderData()
                    
                    // Avoid duplicates
                    let filteredNew = newOrders.filter { newItem in
                        !existing.contains(where: { $0.id == newItem.id })
                    }
                    
                    existing.append(contentsOf: filteredNew)
                    SDKUserDefault.saveMappableArray(existing, for: kFileStorageName.kOrderList.rawValue)
                }
                
                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
//    func getOrderList(OrdersParameater : OrdersParameater) {
//        
//        DispatchQueue.main.async {
//            if self.isLoading{
//                self.orderPlaceholderMarker.register(self.getAnimableSubviews())
//                self.orderPlaceholderMarker.startAnimation()
//            }
//        }
//        
//        
//        guard let parameater = try? OrdersParameater.asDictionary() else {
//            showAlertMessage(strMessage: str.invalidRequestParamater)
//            return
//        }
//        
//        //Declaration URL
//        let strURL = "\(Url.orderList.absoluteString!)"
//        
//        print(parameater)
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "orderList"
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
    
    
    
//    func getCategorys(CatrgoryParameater : CatrgoryParameater){
//        
//        guard let parameater = try? CatrgoryParameater.asDictionary() else {
//            showAlertMessage(strMessage: str.invalidRequestParamater)
//            return
//        }
//        
//        //Declaration URL
//        let strURL = "\(Url.categorys.absoluteString!)"
//        
//        
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "categorys"
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
    
    
//    func updateStatus(UpdateStatusParameater : UpdateStatusParameater, index : Int){
//        
//        guard let parameater = try? UpdateStatusParameater.asDictionary() else {
//            showAlertMessage(strMessage: str.invalidRequestParamater)
//            return
//        }
//        
//        //Declaration URL
//        let strURL = "\(Url.scheduleUpdate.absoluteString!)"
//        
//        
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "scheduleUpdate"
//        webHelper.methodType = "post"
//        webHelper.selectIndex = index
//        webHelper.strURL = strURL
//        webHelper.dictType = parameater
//        webHelper.dictHeader = NSDictionary()
//        webHelper.delegateWeb = self
//        webHelper.showLogForCallingAPI = true
//        webHelper.serviceWithAlert = true
//        webHelper.indicatorShowOrHide = true
//        webHelper.callAPI()
//    }
    
    
//    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
//        indicatorHide()
//        self.isLoading = false
//        self.stopAnimatingView()
//        self.objRefresh?.endRefreshing()
//        
//        if data.getStringForID(key: "success") == "1"{
////            if strRequest == "orderList"{
////                print(data)
////                
////                if let arrData = data["orders"] as? NSArray{
////                    let arr = Mapper<OrdersListModel>().mapArray(JSONArray: arrData as! [[String : Any]])
////                    
////                    if self.pageCount == 1{
////                        self.arrOrderList = []
////                    }
////                    
////                    for obj in arr{
////                        self.arrOrderList.append(obj)
////                    }
////                    
////                    //CHECK LOADING
////                    self.bool_Load = true
////                    if arr.count >= Int(Application.PageOrderLimit){
////                        self.bool_Load = false
////                        self.pageCount += 1
////                    }
////                    
////                    //SET THE VIEW
////                    self.setTheView()
////                }
////                else{
////                    //SET THE VIEW
////                    self.setTheView()
////                }
////            }
////            else if strRequest == "categorys"{
////                if data.getStringForID(key: "success") == "1"{
////                    if let arrData = data["product_categories"] as? NSArray{
////                        
////                        self.arrCategorys = []
////                        var arrData = Mapper<CategoryModel>().mapArray(JSONArray: arrData as! [[String : Any]])
////                        arrData = arrData.sorted(by: { $0.name ?? "" < $1.name ?? "" })
////                        
////
////                        for obj in arrData{
////                            self.arrCategorys.append(obj)
////
////                            if obj.arrChildCategories.count != 0{
////                                let arrChildData = obj.arrChildCategories.sorted(by: { $0.name ?? "" < $1.name ?? "" })
////                                for objChild in arrChildData{
////                                    var obj = objChild
////                                    obj.name = "--\(obj.name ?? "")"
////                                    self.arrCategorys.append(obj)
////                                }
////                            }
////                        }
////                        
////                        
////                        //SET EMPTY OBJECT
////                        var objData : CategoryModel!
////                        let map = Map(mappingType: .fromJSON, JSON: [:])
////                        objData = CategoryModel(map: map)
////                        objData.id = 0
////                        objData.name = "All"
////                        
////                        //ADD
////                        self.arrCategorys.insert(objData, at: 0)
////                    }
////                }
////            }
//            
//            if strRequest == "scheduleUpdate"{
//                //                //UPDATE COUNT
//                //                GlobalMainConstants.appDelegate?.getScheduleCount()
//                //
//                //                print(data)
//                //                if self.arrOrderList.count == 0{
//                //                    return
//                //                }
//                //                var objData = self.arrOrderList[index]
//                //
//                //
//                //                //UPDATE
//                //                if objData.arrDeliveryStatus.count != 0{
//                //                    var objDelivery = objData.arrDeliveryStatus[self.deliveryIndex]
//                //
//                //                    if self.deliveryType.lowercased() == "Delivery".lowercased(){
//                //                        objDelivery.delivery_status?.value = "2"
//                //                    }
//                //                    else{
//                //                        objDelivery.pickup_status?.value = "2"
//                //                    }
//                //                    
//                //                    //UPDATE DATA
//                //                    objData.arrDeliveryStatus.remove(at: self.deliveryIndex)
//                //                    objData.arrDeliveryStatus.insert(objDelivery, at: self.deliveryIndex)
//                //                }
//                //
//                //                //UPDATE TERMS
//                //                self.arrOrderList.remove(at: index)
//                //                self.arrOrderList.insert(objData, at: index)
//                //
//                //
//                //
//                //                //RELOAD TABLE
//                //                self.tblView.reloadData()
//            }
//        }
//        else{
//            indicatorHide()
//            //SET THE VIEW
//            self.setTheView()
//            //            showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
//        }
//    }
    
//    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
//    }
//    
//    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
//        indicatorHide()
//        self.isLoading = false
//        self.setTheView()
//        
//        //NO DATA
//        self.emptyDataView.isHidden = false
//        
//        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
//    }
    
}

