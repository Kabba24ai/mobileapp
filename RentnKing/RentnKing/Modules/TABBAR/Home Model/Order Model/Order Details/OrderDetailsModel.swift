//
//  OrderDetailsModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 15/02/24.
//

import Foundation
import ObjectMapper
import UIKit



struct UserListModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var full_name: String?
    internal var email: String?
    internal var status: String?
    
    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        
        full_name <- map["full_name"]
        email <- map["email"]
        status <- map["status"]
    }
}

extension OrderDetailsViewController {
    //LOADER
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            lblBillingInfo,
            lblName,
            lblNumber,
            imgCall,
            lblNoteTitle,
            viewAddNoteBtn,
            lblEmail,
            lblAddress,
            imgMapAddress,
            imgEditAddress,
            lblSubAmount,
            lblSubAmountPrice,
            lblTax,
            lblTaxPrice,
            lblTotalAmount,
            lblTotlaPrice,
            lblProductTitle,
            lblPayment,
            lblPaymentType,
            viewLicense,
            viewTermsAndCondition,
            viewCheckListDeliv,
            viewCheckListRet,
            viewPhotVideoDeli,
            viewDeliveryStatus,
            viewPaymentType,
            lblDeliveryInfo,
            lblDeliveryName,
            lblDeliveryNumber,
            imgDeliveryCall,
            lblDeliveryEmail,
            lblDeliveryAddress,
            imgDeliveryMapAddress,
            imgDeliveryEditAddress
        ]
    }
    
    func CallAPIforGetUsers(CatrgoryParameater : CatrgoryParameater){
        
        guard let parameater = try? CatrgoryParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.usersList.absoluteString!)"
        
        
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPIwithCompletation { dic, arr, success, err in
            indicatorHide()
            if dic?.getStringForID(key: "success") == "1" {
                if let arrData = dic?["users"] as? NSArray {
                    
                    let arrData = Mapper<UserListModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrUserList = arrData.sorted(by: { $0.full_name ?? "" < $1.full_name ?? "" })
                    
                    // Overwrite old data
                    SDKUserDefault.saveMappableArray(arrData, for: kFileStorageName.kOrderDetailUserData.rawValue)
                }
            }
            else {
                indicatorHide()
                showAlertMessage(strMessage: "\(str.somethingWentWrong)")
            }
        }
    }
    
    func CallAPIforGetOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater){
        if isLoading{
            DispatchQueue.main.async {
                self.orderDetailsPlaceholderMarker.register(self.getAnimableSubviews())
                self.orderDetailsPlaceholderMarker.startAnimation()
            }
        }
        
        
        guard let parameater = try? OrdersDetailsParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.orderDetails.absoluteString!)"
        
        
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPIwithCompletation { dic, arr, success, err in
            indicatorHide()
            if dic?.getStringForID(key: "success") == "1" {
                if let dicData = dic?["order"] as? NSDictionary{
                    
                    //SET DATA
                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
                    self.objOrderData = OrdersListModel(map: map)
                    
                    // Overwrite old data
                    SDKUserDefault.saveMappableObject(self.objOrderData, for: "\(kFileStorageName.kOrderDetailData.rawValue)_\(self.strOrderUniqueId)")
                    
                    //SET THE VIEW
                    self.setTheView()
                }
                else{
                    //SET THE VIEW
                    self.setTheView()
                }
            }
            else {
                indicatorHide()
                showAlertMessage(strMessage: "\(str.somethingWentWrong)")
            }
        }
    }

}
