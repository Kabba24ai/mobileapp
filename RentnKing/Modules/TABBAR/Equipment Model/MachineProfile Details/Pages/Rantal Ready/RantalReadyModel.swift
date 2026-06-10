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
    internal var unique_id: String?
    internal var question_name: String?
    internal var arrAnswer: [RentalReadyAnswerModel]?
    internal var selected_answer : String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        question_name <- map["question_name"]
        arrAnswer <- map["answers"]
        selected_answer <- map["selected_answer"]
    }
}


struct RentalReadyAnswerModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var answer_name: String?
    internal var type: String?
    internal var is_selected: Bool?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        answer_name <- map["answer_name"]
        type <- map["type"]
        is_selected <- map["is_selected"]
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
        var equipment_unique_id : String?
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
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }
    
    
   
    struct UpdateRentalParameater: Codable {
        var inventory_id : String?
        var machine_hour : String?
        var employee_id : String?
//        var questions : [[String : Any]] = []
    }

    
    func updateRentalReady( dicRentalReadyList : [String : Any]){
    

        //Declaration URL
        let strURL = "\(Url.updateRantalReady.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "updateRantalReady"
        webHelper.methodType = "post"
        webHelper.selectIndex = 0
        webHelper.strURL = strURL
        webHelper.dictType = dicRentalReadyList
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
        indicatorHide()
        self.isLoading = false

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "rantalReady"{
                if let arrData = data["rental_ready_checklist_questions"] as? NSArray{
                    
                    self.arrRentalReady = []
                    self.arrRentalReady = Mapper<RentalReadyModel>().mapArray(JSONArray: arrData as! [[String : Any]])

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
                    showAlertMessage(strMessage: "Updated successfully.")
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
