//
//  AddressModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 27/02/24.
//

import Foundation
import ObjectMapper

struct UpdateAddressParameater: Codable {
    var address_id : String
    var name: String
    var phone: String
    var email: String
    var state: String
    var city: String
    var zip_code: String
    var address: String
    var country: String = "US"

}

extension AddressViewController :WebServiceHelperDelegate{
    
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
    
    func updateAddress(UpdateAddressParameater:UpdateAddressParameater){
       
        guard let parameater = try? UpdateAddressParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.updateAddress.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "updateAddress"
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
    
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "getStates"{
                if let arrData = data["data"] as? NSArray{
                   
                    self.arrStates = []
                    self.arrStates = Mapper<StatesModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrStates = self.arrStates.sorted(by: { $0.name ?? "" < $1.name ?? "" })
                    
                }
            }
            else if strRequest == "updateAddress"{
                print(data)
                
                //BACK
                self.navigationController?.popViewController(animated: true)

                DispatchQueue.main.async {
                    showAlertMessage(strMessage: data.getStringForID(key: "message"))
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
