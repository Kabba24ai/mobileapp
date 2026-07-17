//
//  AddressModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 27/02/24.
//

import Foundation
import ObjectMapper


extension AssignDriverViewController :WebServiceHelperDelegate{
    
   
    
    struct UpdateDriversParameater: Codable {
        var order_product_unique_id: String
        var user_delivery_id: String
        var user_pickup_id: String
    }
    
    func updateDriver(UpdateDriversParameater:UpdateDriversParameater){
       
        guard let parameater = try? UpdateDriversParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.dispatchUpdateStatus.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "dispatchUpdateStatus"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }
    
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "dispatchUpdateStatus"{
                print(data)
                
                //BACK
                self.navigationController?.popViewController(animated: true)

                showAlertMessage(strMessage: data.getStringForID(key: "message"))

                
                DispatchQueue.main.async {
                    self.delegate?.updateDriver(delivery_employee: self.delivery_employee, pickup_employee: self.pickup_employee, index: self.selectDispatchIndex)
                }
            }
        }
        else{
            indicatorHide()
            //SET THE VIEW
//            self.setTheView()
            if data.getStringForID(key: "message") != ""{
                showAlertMessage(strMessage: data.getStringForID(key: "message"))
            }
            else{
                showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
            }
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        

        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}
