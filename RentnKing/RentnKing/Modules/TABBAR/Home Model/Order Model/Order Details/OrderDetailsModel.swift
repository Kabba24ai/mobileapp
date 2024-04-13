//
//  OrderDetailsModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 15/02/24.
//

import Foundation
import ObjectMapper
import UIKit




extension OrderDetailsViewController :WebServiceHelperDelegate{
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
            viewLicense,
            viewTermsAndCondition,
            viewHoursStart,
            viewHoursEnd,
            viewCheckList,
            viewPhotVideo,
            viewDeliveryStatus,
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

    
    func getOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater){
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
        webHelper.strMethodName = "orderDetails"
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
    
    
    func updateStatus(UpdateStatusParameater : UpdateStatusParameater, index : Int){
       
        guard let parameater = try? UpdateStatusParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.scheduleUpdate.absoluteString!)"

       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "scheduleUpdate"
        webHelper.methodType = "post"
        webHelper.selectIndex = index
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "orderDetails"{
                if let dicData = data["data"] as? NSDictionary{
                    
                    //SET DATA
                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
                    self.objOrderData = OrdersModel(map: map)
                    
                    
                    //SET THE VIEW
                    self.setTheView()
                }
                else{
                    //SET THE VIEW
                    self.setTheView()
                }
            }
            else if strRequest == "scheduleUpdate"{
                print(data)
                
                //UPDATE
                if self.objOrderData.arrDeliveryStatus.count != 0{
                    var objDelivery = self.objOrderData.arrDeliveryStatus[index]
                    
                    if self.deliveryType.lowercased() == "Delivery".lowercased(){
                        objDelivery.delivery_status?.value = "2"
                    }
                    else{
                        objDelivery.pickup_status?.value = "2"
                    }
                    
                    //UPDATE DATA
                    self.objOrderData.arrDeliveryStatus.remove(at: index)
                    self.objOrderData.arrDeliveryStatus.insert(objDelivery, at: index)
                }
                
                //RELOAD TABLE
                self.setFooter()
            }
        }
        else{
            indicatorHide()
            //SET THE VIEW
//            self.setTheView()
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
