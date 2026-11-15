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
    
    /// Kabba itself answered no (the order isn't there for this company) — not a lost connection.
    static func kabbaDeclined(answer: NSDictionary?, error: Error?) -> Bool {
        if answer != nil { return true }
        guard let apiError = error as? APIError, apiError.kind == .http, let status = apiError.statusCode else { return false }
        return status == 403 || status == 404 || status == 422 || (200..<300).contains(status)
    }

    func CallAPIforGetUsers(CatrgoryParameater : CatrgoryParameater){
        // The request + company-scoped save live in callAPIforUsersList (shared with the
        // Dispatch offline reference warm-up, Phase 4 P4-D6).
        callAPIforUsersList(CatrgoryParameater: CatrgoryParameater) { isSaved in
            indicatorHide()
            if isSaved {
                self.arrUserList = self.getUsersData().sorted(by: { $0.full_name ?? "" < $1.full_name ?? "" })
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
        
        // Dispatch offline Phase 4: when this was asked, and for which company (§4.3, Amendment B).
        let askedAt = Date(), tenant = KabbaTenantScope.currentKey

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
                    self.orderCopyAsOf = askedAt
                    
                    // Overwrite old data — unless a newer copy (a mission package asked later) is already here
                    if let order = self.objOrderData {
                        OrderDetailsCache.saveLive(order, orderUniqueId: self.strOrderUniqueId, askedAt: askedAt, tenantKey: tenant)
                    }
                    
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
//                showAlertMessage(strMessage: "OrderDetails \(str.somethingWentWrong)")
                // No copy on this phone: Kabba saying the order isn't there (deleted, another
                // company) reads "isn't available"; offline or failed reads "isn't downloaded" —
                // never an endless skeleton.
                if self.objOrderData == nil {
                    if OrderDetailsViewController.kabbaDeclined(answer: dic, error: err) {
                        self.showOrderUnavailable()
                    } else {
                        self.showOrderNotDownloaded()
                    }
                }
            }
        }
    }

}
