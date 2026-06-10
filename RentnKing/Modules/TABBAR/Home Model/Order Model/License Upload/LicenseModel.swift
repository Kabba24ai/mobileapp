////
////  LicenseModel.swift
////  RentnKing
////
////  Created by Jigar Khatri on 03/02/24.
////
//
//import Foundation
//import UIKit
//import ObjectMapper
//
//
//
//extension LicenseUploadViewController: WebServiceHelperDelegate {
////
////    func getOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater){
////        guard let parameater = try? OrdersDetailsParameater.asDictionary() else {
////            showAlertMessage(strMessage: str.invalidRequestParamater)
////            return
////        }
////
////        //Declaration URL
////        let strURL = "\(Url.orderDetails.absoluteString!)"
////        
////       
////        //Create object for webservicehelper and start to call method
////        let webHelper = WebServiceHelper()
////        webHelper.strMethodName = "orderDetails"
////        webHelper.methodType = "post"
////        webHelper.strURL = strURL
////        webHelper.dictType = parameater
////        webHelper.dictHeader = NSDictionary()
////        webHelper.delegateWeb = self
////        webHelper.showLogForCallingAPI = true
////        webHelper.serviceWithAlert = true
////        webHelper.indicatorShowOrHide = false
////        webHelper.callAPI()
////    }
////    
////    
////    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
////        indicatorHide()
////
////        if data.getStringForID(key: "success") == "1"{
////            print(data)
////            if strRequest == "orderDetails"{
////                
////                
////                if let dicData = data["data"] as? NSDictionary{
////                   
////                    
////                    //SET DATA
////                    var objOrderData : OrdersModel!
////                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
////                    objOrderData = OrdersModel(map: map)
////                    self.arrLicense = objOrderData.a
////
////                    //SET THE VIEW
////                    self.setTheView()
////                }
////                else{
////                    //SET THE VIEW
////                    self.setTheView()
////                }
////            }
////        }
////        else{
////            indicatorHide()
////            //SET THE VIEW
////            showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
////        }
////    }
////    
////    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
////    }
////    
////    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
////        indicatorHide()
////        self.setTheView()
////
////        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
////    }
//    
//    func getOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater){
//        guard let parameater = try? OrdersDetailsParameater.asDictionary() else {
//            showAlertMessage(strMessage: str.invalidRequestParamater)
//            return
//        }
//
//        //Declaration URL
//        let strURL = "\(Url.orderDetails.absoluteString!)"
//        
//       
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "orderDetails"
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
//    
//    
//    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
//        indicatorHide()
//
//        if data.getStringForID(key: "success") == "1"{
//            print(data)
//            if strRequest == "orderDetails"{
//                
//                
//                if let dicData = data["data"] as? NSDictionary{
//                   
//                    
//                    //SET DATA
//                    var objOrderData : OrdersModel!
//                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
//                    objOrderData = OrdersModel(map: map)
//                    //Temp Comment//self.arrLicense = objOrderData.license_image_links
//
//                    //SET THE VIEW
//                    self.setTheView()
//                }
//                else{
//                    //SET THE VIEW
//                    self.setTheView()
//                }
//            }
//        }
//        else{
//            indicatorHide()
//            //SET THE VIEW
//            showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
//        }
//    }
//    
//    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
//    }
//    
//    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
//        indicatorHide()
//        self.setTheView()
//
//        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
//    }
//}
//
