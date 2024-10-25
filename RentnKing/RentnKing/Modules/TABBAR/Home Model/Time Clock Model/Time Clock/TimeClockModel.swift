//
//  TimeClockModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 25/09/24.
//

import Foundation
import ObjectMapper
import UIKit

struct EmpStatusModel: Mappable{
    internal var status_code: String?
    internal var status_type: String?
    internal var status_name: String?
    internal var created_date: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        status_code <- map["status_code"]
        status_type <- map["status_type"]
        status_name <- map["status_name"]
        created_date <- map["created_date"]
    }
}

struct EmployeesModel: Mappable{
    internal var id: Int?
    internal var name: String?
    internal var employee_code: String?
    internal var email: String?
    internal var phone: String?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        name <- map["name"]
        employee_code <- map["employee_code"]
        email <- map["email"]
        phone <- map["phone"]
    }
}



struct EmployeParameater: Codable {
    var employee_id : String
    var temporary_code : String
}


extension TimeClockViewController :WebServiceHelperDelegate{

    func getStatusAPI(){
        
        //Declaration URL
        let strURL = "\(Url.statusList.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "statusList"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
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
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }
    
    
   
    
    
    func getEmployeesStatusAPI(EmployeParameater : EmployeParameater){
        guard let parameater = try? EmployeParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.employeeStatus.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "employeeStatus"
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
        if strRequest != "employeeStatus"{
            indicatorHide()
        }

        let arrKey  = data.allKeys as [AnyObject]
        if (arrKey.firstIndex(where: { $0 as! String == "error" }) == nil){
            print(data)
            if strRequest == "statusList"{
                if data.getStringForID(key: "success") == "1"{
                    if let arrData = data["data"] as? NSArray{
                       
                        self.arrStatusList = []
                        self.arrStatusList = Mapper<EmpStatusModel>().mapArray(JSONArray: arrData as! [[String : Any]])

                    }
                }
    
            }
            else if strRequest == "employeesList"{
                if data.getStringForID(key: "success") == "1"{
                    if let arrData = data["data"] as? NSArray{
                       
                        self.arrEmployesList = []
                        self.arrEmployesList = Mapper<EmployeesModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                        self.arrEmployesList = self.arrEmployesList.sorted(by: { $0.name ?? "" < $1.name ?? "" })

                        //SET THE VIEW
                        self.setTheView()
                    }
                }
    
            }
            else if strRequest == "employeeStatus"{
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0){
                    indicatorHide()
                }
                if data.getStringForID(key: "success") == "1"{
                    print(data)
                    
                    if let dicData = data["data"] as? NSDictionary{
                        //GET CURRENT OBJECT
                        var strLastTime : String = ""
                        var strLastStatus : String = ""
                        var strCurrentDate : String = ""
                        var strSeftTime : String = ""
                        var arrStatusList : [EmpStatusModel] = []
                        
                        if let objData = dicData["current_status"] as? NSDictionary{
                            strLastTime = objData.getStringForID(key: "last_updated_time")
                            strLastStatus = objData.getStringForID(key: "status_name")
                        }
                        
                        
                        if let objScheduleData = dicData["schedule_details"] as? NSDictionary{
                            strCurrentDate = objScheduleData.getStringForID(key: "current_date")
                            strSeftTime = "\(objScheduleData.getStringForID(key: "start_time") ?? "") - \(objScheduleData.getStringForID(key: "end_time") ?? "")"
                            
                            if let arrData = objScheduleData["status_history"] as? NSArray{
                                let arrList = Mapper<EmpStatusModel>().mapArray(JSONArray: arrData as! [[String : Any]])

                                arrStatusList = []
                                for obj in arrList{
                                    let MenuID = self.arrStatusList.map{$0.status_code}
                                    if let index = MenuID.firstIndex(of: obj.status_code){
                                        var objSchedule = obj
                                        objSchedule.status_name = self.arrStatusList[index].status_name
                                        
                                        if objSchedule.created_date != ""{
                                            arrStatusList.append(objSchedule)
                                        }
                                    }
                                }
                            }
                        }
                        
                        
                        //GET NEX STATUS
                        var arrNextStatus : [EmpStatusModel] = []
                        if let arrData = dicData["upcoming_status"] as? NSArray{
                            for obj in arrData{
                                let MenuID = self.arrStatusList.map{$0.status_code}
                                if let index = MenuID.firstIndex(of: "\(obj)"){
                                    arrNextStatus.append(self.arrStatusList[index])
                                }
                            }
                        }
                        
                        //GET EMPLYOEES
                        var objEmp : EmployeesModel!
                        let map = Map(mappingType: .fromJSON, JSON: [:])
                        objEmp = EmployeesModel(map: map)
                        if let objData = dicData["employee"] as? NSDictionary{
                            objEmp.id = objData["id"] as? Int
                            objEmp.name = objData.getStringForID(key: "name")
                            objEmp.employee_code = objData.getStringForID(key: "employee_code")
                            objEmp.email = objData.getStringForID(key: "email")
                            objEmp.phone = objData.getStringForID(key: "phone")

                            
                            if arrNextStatus.count != 0{
                                //MOVE FORGOT SCREEN
                                let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TIMECLOCK_MODEL, bundle: nil)
                                if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ClockInViewController") as? ClockInViewController{
                                    newViewController.objData = objEmp
                                    newViewController.arrNextStatus = arrNextStatus
                                    newViewController.strLastTime = strLastTime
                                    newViewController.strLastStatus = strLastStatus
                                    newViewController.strCurrentDate = strCurrentDate
                                    newViewController.strShiftTime = strSeftTime
                                    newViewController.arrStatusList = arrStatusList
                                    self.navigationController?.pushViewController(newViewController, animated: true)
                                }
                            }
                        }
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
        self.setTheView()
        
       
        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}




extension ClockInViewController :WebServiceHelperDelegate{

    
    struct EmployeParameater: Codable {
        var employee_id : String
        var status_code : String
        var comment : String
    }

    
    
    func updateEmployeesStatusAPI(EmployeParameater : EmployeParameater){
        guard let parameater = try? EmployeParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.updateEmployeeStatus.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "updateEmployeeStatus"
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
        if strRequest != "employeeStatus"{
            indicatorHide()
        }

        let arrKey  = data.allKeys as [AnyObject]
        if (arrKey.firstIndex(where: { $0 as! String == "error" }) == nil){
            print(data)
            if strRequest == "updateEmployeeStatus"{
                if data.getStringForID(key: "success") == "1"{
                    //BACK SCREE
                    self.navigationController?.popToRootViewController(animated: true)

                    DispatchQueue.main.async {
                        showAlertMessage(strMessage: "Status successful update")
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
        self.setTheView()
        
       
        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}



extension TimeClockLockViewController :WebServiceHelperDelegate{
    
    func getStatusAPI(){
        
        //Declaration URL
        let strURL = "\(Url.statusList.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "statusList"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }
    
    func getEmployeesStatusAPI(EmployeParameater : EmployeParameater){
        guard let parameater = try? EmployeParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.employeeStatus.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "employeeStatus"
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
     

        let arrKey  = data.allKeys as [AnyObject]
        if (arrKey.firstIndex(where: { $0 as! String == "error" }) == nil){
            print(data)

            if strRequest == "statusList"{
                if data.getStringForID(key: "success") == "1"{
                    if let arrData = data["data"] as? NSArray{
                       
                        self.arrStatusList = []
                        self.arrStatusList = Mapper<EmpStatusModel>().mapArray(JSONArray: arrData as! [[String : Any]])

                    }
                }
    
            }
            else if strRequest == "employeeStatus"{
                
                if let dicData = data["data"] as? NSDictionary{
                    //GET CURRENT OBJECT
                    var strLastTime : String = ""
                    var strLastStatus : String = ""
                    var strCurrentDate : String = ""
                    var strSeftTime : String = ""
                    var arrStatusList : [EmpStatusModel] = []
                    
                    if let objData = dicData["current_status"] as? NSDictionary{
                        strLastTime = objData.getStringForID(key: "last_updated_time")
                        strLastStatus = objData.getStringForID(key: "status_name")
                    }
                    
                    
                    if let objScheduleData = dicData["schedule_details"] as? NSDictionary{
                        strCurrentDate = objScheduleData.getStringForID(key: "current_date")
                        strSeftTime = "\(objScheduleData.getStringForID(key: "start_time") ?? "") - \(objScheduleData.getStringForID(key: "end_time") ?? "")"
                        
                        if let arrData = objScheduleData["status_history"] as? NSArray{
                            let arrList = Mapper<EmpStatusModel>().mapArray(JSONArray: arrData as! [[String : Any]])

                            arrStatusList = []
                            for obj in arrList{
                                let MenuID = self.arrStatusList.map{$0.status_code}
                                if let index = MenuID.firstIndex(of: obj.status_code){
                                    var objSchedule = obj
                                    objSchedule.status_name = self.arrStatusList[index].status_name
                                    
                                    if objSchedule.created_date != ""{
                                        arrStatusList.append(objSchedule)
                                    }
                                }
                            }
                        }
                    }
                    
                    
                    //GET NEX STATUS
                    var arrNextStatus : [EmpStatusModel] = []
                    if let arrData = dicData["upcoming_status"] as? NSArray{
                        for obj in arrData{
                            let MenuID = self.arrStatusList.map{$0.status_code}
                            if let index = MenuID.firstIndex(of: "\(obj)"){
                                arrNextStatus.append(self.arrStatusList[index])
                            }
                        }
                    }
                    
                    //GET EMPLYOEES
                    var objEmp : EmployeesModel!
                    let map = Map(mappingType: .fromJSON, JSON: [:])
                    objEmp = EmployeesModel(map: map)
                    if let objData = dicData["employee"] as? NSDictionary{
                        objEmp.id = objData["id"] as? Int
                        objEmp.name = objData.getStringForID(key: "name")
                        objEmp.employee_code = objData.getStringForID(key: "employee_code")
                        objEmp.email = objData.getStringForID(key: "email")
                        objEmp.phone = objData.getStringForID(key: "phone")

                        
                        if arrNextStatus.count != 0{
                            //MOVE FORGOT SCREEN
                            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TIMECLOCK_MODEL, bundle: nil)
                            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ClockInViewController") as? ClockInViewController{
                                newViewController.objData = objEmp
                                newViewController.arrNextStatus = arrNextStatus
                                newViewController.strLastTime = strLastTime
                                newViewController.strLastStatus = strLastStatus
                                newViewController.strCurrentDate = strCurrentDate
                                newViewController.strShiftTime = strSeftTime
                                newViewController.arrStatusList = arrStatusList
                                self.navigationController?.pushViewController(newViewController, animated: true)
                            }
                        }
                    }
                }
                else {
                    indicatorHide()
                    showAlertMessage(strMessage: data.getStringForID(key: "message"))
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
        self.setTheView()
        
       
        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}
