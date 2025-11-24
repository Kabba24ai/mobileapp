//
//  MachineHoursModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 08/02/24.
//

import Foundation
import ObjectMapper



struct OrdersDetailsParameater: Codable {
    var unique_id : String
    var product_id : String
}

extension MachineHoursViewController :WebServiceHelperDelegate{
 
    
    func getOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater){
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
    
  
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            print(data)
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
//            else if strRequest == "machineHours"{
//                if self.selectIndex != -1{
//                    self.delegate?.UpdateMachinHours(selectIndex: self.selectIndex, arrUpdateMachinHours: self.objOrderData.arrMachineHours)
//                }
//                
//                showAlertMessage(strMessage: "Machine Hours update successfully")
//
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
//                    self.navigationController?.popViewController(animated: true)
//                }
//
//            }
        }
        else{
            indicatorHide()
            //SET THE VIEW
            self.setTheView()
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
