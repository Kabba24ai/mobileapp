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
        name <- map["name"]
        phone <- map["phone"]
        address <- map["address"]
        city <- map["city"]
        state <- map["state"]
        zip_code <- map["zip_code"]
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
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
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


