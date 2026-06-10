//
//  CRMListModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 26/05/26.
//

import Foundation
import ObjectMapper



extension CRMListViewController :WebServiceHelperDelegate{
    
 
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
        indicatorHide()
        self.isLoading = false
        self.objRefresh?.endRefreshing()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "customers"{
                if let arrData = data["customers"] as? NSArray{
                    
                    self.arrCustomerList = []
                    self.arrCustomerList = Mapper<CustomerModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrMainCustomerList = self.arrCustomerList
                    
                    //SET THE VIEW
                    self.setTheView()
                }
                else{
                    //SET THE VIEW
                    self.setTheView()
                }

            }
        }
        else{
            indicatorHide()
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        self.isLoading = false

        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}
