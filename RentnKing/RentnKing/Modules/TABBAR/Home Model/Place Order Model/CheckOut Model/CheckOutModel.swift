//
//  CheckOutModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 11/01/24.
//

import Foundation
import ObjectMapper



struct StatesModel: Mappable{
    internal var id: Int?
    internal var name: String?
    internal var is_default: Int?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        name <- map["name"]
        is_default <- map["is_default"]
    }
}

//SINGUP SCREEN ..........................
extension CheckOutViewController :WebServiceHelperDelegate{

    
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
    
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()
        self.isLoading = false
        
        let arrKey  = data.allKeys as [AnyObject]
        if (arrKey.firstIndex(where: { $0 as! String == "error" }) == nil){
            print(data)
            if strRequest == "getStates"{
                if let arrData = data["data"] as? NSArray{
                   
                    self.arrStates = []
                    self.arrStates = Mapper<StatesModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrStates = self.arrStates.sorted(by: { $0.name ?? "" < $1.name ?? "" })
                    
    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                        self.checkOutPlaceholderMarker.remove()
                        
                        //RELOAD TABLE
                        self.tblView.reloadData()
                    }
                }
            }
        }
        else{
            indicatorHide()
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

