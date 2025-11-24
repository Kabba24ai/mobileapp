//
//  PaymentModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 27/01/24.
//

import Foundation
import ObjectMapper
import UIKit

//SINGUP SCREEN ..........................
extension PaymentViewController :WebServiceHelperDelegate{

    
    func getStatesAPI(){
    
        //Declaration URL
        let strURL = "\(Url.getStates.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "getStates"
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
    
    
    struct placeOrderParameater: Codable {
        var first_name: String
        var last_name: String
        var email: String
        var phone: String
        var address: String
        var zipcode: String
        var city: String
        var state: String
        var country: String = "US"

        var note: String
        var same_as_delivery: Bool
        var payment_method: String
        
        var delivery_first_name: String
        var delivery_last_name: String
        var delivery_email: String
        var delivery_mobile: String
        var delivery_address: String
        var delivery_zipcode: String
        var delivery_city: String
        var delivery_state: String
        var delivery_country: String = "US"
        
        var tax_amount : String
        var total_amount : String
        
        var card_number: String
        var mm_yy: String
        var cvc: String
        
    }
    
    func placeOrderAPI(placeOrderParameater:placeOrderParameater, arrCart : NSMutableDictionary){
        guard var parameater = try? placeOrderParameater.asDictionary() else {
            return
        }
        
        
        parameater["carts"] = arrCart

        print(parameater)
        //Declaration URL
        let strURL = "\(Url.placeORder.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "placeORder"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
//        webHelper.callAPI2()
    }
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String) {
        indicatorHide()
        print(data)
        
        if data.getStringForID(key: "success") == "1"{
            print(data)
            if strRequest == "getStates"{
                if let arrData = data["data"] as? NSArray{
                   
                    self.arrStates = []
                    self.arrStates = Mapper<StatesModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrStates = self.arrStates.sorted(by: { $0.name ?? "" < $1.name ?? "" })
                    
                }
            }
            else if strRequest == "placeORder"{
                //MOVE TO  SCREEN
                if let dicData = data["data"] as? NSDictionary{
                    let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
                    if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderSuccessViewController") as? OrderSuccessViewController{
                        newViewController.signUrl = data.getStringForID(key: "signUrl")
                        self.navigationController?.pushViewController(newViewController, animated: true)
                    }
                }
            }
        }
        else{
            indicatorHide()
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

