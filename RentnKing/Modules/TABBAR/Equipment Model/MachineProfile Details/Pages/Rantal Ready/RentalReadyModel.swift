//
//  RentalReadyModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 19/03/25.
//

import Foundation
import UIKit
import ObjectMapper



struct RentalReadyModel: Mappable{
    internal var id: Int?

    internal var machine_hour: Int = 0
    internal var has_machine_hour: Int = 0
    internal var status_change: String?
    internal var objEmploye: EmployeeModel?
    internal var checkList: CheckListModel?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]

        machine_hour <- map["machine_hour"]
        has_machine_hour <- map["has_machine_hour"]
        status_change <- map["status_change"]
        objEmploye <- map["employee"]
        checkList <- map["checklist"]
    }
}

struct EmployeeModel: Mappable{
    internal var name: String?
        
    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        name <- map["name"]
    }
}


extension RantalReadyVC :WebServiceHelperDelegate{
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            self.lblUpdate,
            self.lblUpdateName,
            self.lblUpdateTime,
            self.lblMachineHrTitle,
            self.txtMachineHr,
            self.lblEmployee,
            self.viewEmployee
            
        ]
    }
  

    
    
    struct RentalIDParameater: Codable {
        var id : String?
    }

    
    func getRentalReadyAPI(RentalIDParameater : RentalIDParameater){
        
        DispatchQueue.main.async {
            if self.isLoading{
                self.rantalReadyPlaceholderMarker.register(self.getAnimableSubviews())
                self.rantalReadyPlaceholderMarker.startAnimation()
            }
        }
        
        guard let parameater = try? RentalIDParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.rantalReady.absoluteString!)"
        
        print(parameater)
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "rantalReady"
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
    
    
    func getEmployeesListAPI(){
        
        //Declaration URL
        let strURL = "\(Url.employeesList.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "employeesList"
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
    
 
    struct UpdateRentalParameater: Codable {
        var inventory_id : String?
        var machine_hour : String?
        var employee_id : String?
//        var questions : [[String : Any]] = []
    }

    
    func updateRentalReady(UpdateRentalParameater : UpdateRentalParameater, arrData : [[String : Any]]){
    
        
        guard var parameater = try? UpdateRentalParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        parameater["questions"] = arrData
        print(parameater)

        //Declaration URL
        let strURL = "\(Url.updateRantalReady.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "updateRantalReady"
        webHelper.methodType = "post"
        webHelper.selectIndex = 0
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI2()
    }
    
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()
        self.isLoading = false

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "rantalReady"{
                if let dicData = data["data"] as? NSDictionary{
                    //SET EMPTY OBJECT
                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
                    self.objRentalReadyData = RentalReadyModel(map: map)
                    
                    
                    //SET THE VIEW
                    self.setTheView()
                }
                else{
                    //SET THE VIEW
                    self.setTheView()
                }
            }
            else if strRequest == "employeesList"{
                if data.getStringForID(key: "success") == "1"{
                    if let arrData = data["data"] as? NSArray{
                       
                        self.arrEmployesList = []
                        self.arrEmployesList = Mapper<EmployeesModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                        self.arrEmployesList = self.arrEmployesList.sorted(by: { $0.name ?? "" < $1.name ?? "" })

                    }
                }
            }
            else if strRequest == "updateRantalReady"{
                self.navigationController?.popViewController(animated: true)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                    showAlertMessage(strMessage: "Successfully Updated")
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
