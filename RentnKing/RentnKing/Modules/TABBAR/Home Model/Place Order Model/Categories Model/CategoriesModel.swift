//
//  CategoriesModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 11/01/24.
//

import Foundation
import ObjectMapper
import UIKit


struct CategoryModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var name: String?
    internal var image: String?
    internal var arrChildCategories: [CategoryModel] = []

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        name <- map["title"]
        image <- map["image"]
        arrChildCategories <- map["child_categories"]
    }
}

struct InventoryStatusModel: Mappable{
    internal var text: String?
    internal var value: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        text <- map["text"]
        value <- map["value"]
    }
}



//extension CategoriesViewController :WebServiceHelperDelegate{
//    func getAnimableSubviews() -> [UIView] {
//        return [UIView](getAllSubviews())
//    }
//    
//    private func getAllSubviews() -> [UIView] {
//        return [
//            imgOrder,
//            lblOrder,
//            imgProduct,
//            lblProduct
//        ]
//    }
//    
//    
//    func getCategorys(){
//        
//        if isLoading{
//            self.catrgoryPlaceholderMarker.register(self.getAnimableSubviews())
//            self.catrgoryPlaceholderMarker.startAnimation()
//        }
//        
//        //Declaration URL
//        let strURL = "\(Url.categorys.absoluteString!)"
//        
//       
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "categorys"
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
//    
//    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String) {
//        indicatorHide()
//        self.isLoading = false
//
//        let arrKey  = data.allKeys as [AnyObject]
//        if (arrKey.firstIndex(where: { $0 as! String == "error" }) == nil){
//            print(data)
//            if strRequest == "categorys"{
//                if data.getStringForID(key: "success") == "1"{
//                    if let arrData = data["data"] as? NSArray{
//                       
//                        self.arrCategorys = []
//                        self.arrCategorys = Mapper<CategoryModel>().mapArray(JSONArray: arrData as! [[String : Any]])
//                        self.arrCategorys = self.arrCategorys.sorted(by: { $0.name ?? "" < $1.name ?? "" })
//
//                        //SET THE VIEW
//                        self.setTheView()
//                    }
//                }
//                else{
//                    //SET THE VIEW
//                    self.setTheView()
//
//                    
//                    //NO DATA
//                    self.emptyDataView.isHidden = false
//                }
//            }
//        }
//        else{
//            indicatorHide()
//            showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
//        }
//    }
//    
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
//}

