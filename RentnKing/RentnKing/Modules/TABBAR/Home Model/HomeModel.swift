//
//  HomeModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 07/10/24.
//

import Foundation
import ObjectMapper
import UIKit



extension HomeViewController :WebServiceHelperDelegate{

    @objc func getTimeClockSettingAPI(){
        
        //Declaration URL
        let strURL = "\(Url.timeClockSetting.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "timeClockSetting"
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
    
   
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String) {
      
        let arrKey  = data.allKeys as [AnyObject]
        if (arrKey.firstIndex(where: { $0 as! String == "error" }) == nil){
            print(data)
            if strRequest == "timeClockSetting"{
                if data.getStringForID(key: "success") == "1"{
                    if let dicData = data["data"] as? NSDictionary{
                        UserDefaults.standard.masterCode = dicData.getStringForID(key: "master_time_clock_code")

                    }
                }
    
            }

        }
       
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
    }
}

