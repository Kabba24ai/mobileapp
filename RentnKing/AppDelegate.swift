//
//  AppDelegate.swift
//  RentnKing
//
//  Created by Jigar Khatri on 07/10/23.
//

import UIKit
import EventKit
import Alamofire

var pendingDelivertCount : Int = 0
var pendingPickupCount : Int = 0
var pastDelivertCount : Int = 0
var pastPickupCount : Int = 0
var strUUID : String = ""

//NOTIFICATIN DIC
var dicNotificationData : NSDictionary = [:]
var isHomeScreen : Bool = false


@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var timer : Timer!

    let store = EKEventStore()
    var event:EKEvent!

    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        setupKeyboard(true)
        
        //CREATE FOLDER
        createLicenseUploadFolder()
        createImageVideoUploadFolder()
        
        //SET FIREBASE AND NOTIFICATION
        self.setFireBase_Notificaiton(application: application)
      
        
        //SET TIMER
        if timer == nil{
            timer = Timer.scheduledTimer(timeInterval: 10.0, target: self, selector: #selector(self.uploadAllData), userInfo: nil, repeats: true)
        }
        
        self.getScheduleCount()
        
        //EVENT
        //self.eventAccess(
        return true
    }

    
    /// set orientations you want to be allowed in this property by default
//    var orientationLock = checkDeviceiPad() ? UIInterfaceOrientationMask.all : UIInterfaceOrientationMask.portrait
    var orientationLock = UIInterfaceOrientationMask.portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return self.orientationLock
    }
    

    @objc func uploadAllData(){
        if NetworkReachabilityManager()!.isReachable {
            //GET ORDER DATA
            let arrAllData = CoreDBManager.sharedDatabase.getAllUploadDATA()
            if arrAllData.count != 0{
                NotificationCenter.default.post(name: .startUploadData, object: nil)

                let objData = arrAllData[0]
                if objData.type == uploadType.image.rawValue{
                    let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.orderID ?? "", strType: objData.type ?? "")
                    
                    var imgFront = UIImage()
                    var imgBack = UIImage()
                    if arrData.count > 0{
                        imgFront = loadImage(fileName: arrData[0].name ?? "") ?? UIImage()
                    }
                    
                    if arrData.count > 1{
                        imgBack = loadImage(fileName: arrData[1].name ?? "") ?? UIImage()
                    }
                    
                    self.callLicenseUploadAPI(LicenseParameater: LicenseParameater(order_id: objData.orderID ?? ""), imgFront: imgFront, imgBack: imgBack)
                }
                else if objData.type == uploadType.hours.rawValue{
                    let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.orderID ?? "", strType: objData.type ?? "")
                    self.updateHours(strOrderID: objData.orderID ?? "", arrHours: self.getMachineHoursArray(strOrderID: objData.orderID ?? "", arrData: arrData))
                }
                else if objData.type == uploadType.checkList.rawValue{
                    let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.orderID ?? "", strType: objData.type ?? "")

                    self.updateCheckList(strOrderID: objData.orderID ?? "", arrCheckList: self.getCheckListArray(strOrderID: objData.orderID ?? "", arrData: arrData))
                }
            }
            else{
                DispatchQueue.main.asyncAfter(deadline: .now()){
                    NotificationCenter.default.post(name: .stopUploadData, object: nil)
                }
            }
        }
        else{
            DispatchQueue.main.asyncAfter(deadline: .now()){
                NotificationCenter.default.post(name: .stopUploadData, object: nil)
            }
        }
    }
}







extension AppDelegate :WebServiceHelperDelegate{
    struct DeviceTokenParameater: Codable {
        var device_token : String
        var fcm_token : String
    }
    
    func updateToken(DeviceTokenParameater:DeviceTokenParameater){
        guard let parameater = try? DeviceTokenParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.updateToken.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "updateToken"
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

    
    func getScheduleCount(){

        //Declaration URL
        let strURL = "\(Url.scheduleListCound.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "scheduleListCound"
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
    
    
    struct LicenseParameater: Codable {
        var order_id : String
    }

    func callLicenseUploadAPI(LicenseParameater : LicenseParameater, imgFront : UIImage, imgBack : UIImage) {
        guard let parameater = try? LicenseParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.uploadLicense.absoluteString!)"

        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        
      
        //SET IMAGE
        let dicImgFront = ["img": imgFront,
                           "name": "\(Date().timeIntervalSince1970).jpeg",
                           "key": "file[]",
                           "type": "img"] as [String : Any]
        
        let dicImgBack = ["img": imgBack,
                          "name": "\(Date().timeIntervalSince1970).jpeg",
                          "key": "file[]",
                          "type": "img"] as [String : Any]
        
        webHelper.selectIndex = Int(LicenseParameater.order_id) ?? 0
        webHelper.arr_Mutlipleimages.append(dicImgFront)
        webHelper.arr_Mutlipleimages.append(dicImgBack)
        webHelper.strMethodName = "uploadLicense"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callUploadingMultipleImages()
    }
   
    
    
    func getMachineHoursArray(strOrderID :String, arrData : [UploadData]) -> [[String : Any]]{
        var arrHours : [[String : Any]] = []
        
        for objData in arrData{
            let dicData : [String : Any] = ["order_id" : strOrderID ,
                                            "product_id" : objData.productID ?? "",
                                            "start" : objData.start ?? "",
                                            "allocated" : objData.allocated ?? "",
                                            "end" : objData.end ?? "",
                                            "total" : objData.total ?? "",
                                            "over" : objData.over ?? "",
                                            "over_rate" : objData.over_rate ?? "",
                                            "total_cost" : objData.total_cost ?? ""]
            
            arrHours.append(dicData)
        }
        return arrHours
    }
    
    func updateHours(strOrderID :String, arrHours : [[String : Any]]){
    
        //Declaration URL
        let strURL = "\(Url.machineHours.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "machineHours"
        webHelper.methodType = "post"
        webHelper.selectIndex = Int(strOrderID) ?? 0
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.arryType = arrHours
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI2()
    }
    
    
    func getCheckListArray(strOrderID :String, arrData : [UploadData]) -> [[String : Any]]{
        var arrHours : [[String : Any]] = []
        
        for objData in arrData{
            let dicData : [String : Any] = ["order_id" : strOrderID ,
                                            "product_id" : objData.productID ?? "",
                                            "question_id" : objData.qustion_id ?? "",
                                            "in" : objData.checklist_delivered ?? "",
                                            "out" : objData.checklist_returned ?? "",
                                            "value" : objData.checklist_Value ?? ""]
            
            arrHours.append(dicData)
        }
        return arrHours
    }
    
    func updateCheckList(strOrderID :String, arrCheckList : [[String : Any]]){
    
        //Declaration URL
        let strURL = "\(Url.updateCheckList.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "updateCheckList"
        webHelper.methodType = "post"
        webHelper.selectIndex = Int(strOrderID) ?? 0
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.arryType = arrCheckList
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI2()
    }
    
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()

        if strRequest == "updateToken"{
            print(data)
        }
        
        if data.getStringForID(key: "success") == "1"{
            print(data)
            if strRequest == "scheduleListCound"{
                if let dicData = data["data"] as? NSDictionary{
                    pendingDelivertCount = Int(dicData.getStringForID(key: "pendingDeliveryCount")) ?? 0
                    pendingPickupCount = Int(dicData.getStringForID(key: "pendingPickupCount")) ?? 0
                    pastDelivertCount = Int(dicData.getStringForID(key: "pastPendingDeliveryCount")) ?? 0
                    pastPickupCount = Int(dicData.getStringForID(key: "pastPendingPickupCount")) ?? 0
                    NotificationCenter.default.post(name: .scheduleCount, object: nil)
                    
                    
                    UIApplication.shared.applicationIconBadgeNumber = pendingDelivertCount + pendingPickupCount + pastDelivertCount + pastPickupCount
                }
            }
            else if strRequest == "uploadLicense"{
                //LICENSE UPLOAD
                CoreDBManager.sharedDatabase.deleteUploadData(strOrderID: "\(index)", strType: uploadType.image.rawValue) { _ in
                    self.uploadAllData()
                }
            }
            else if strRequest == "machineHours" {
                //LICENSE UPLOAD
                CoreDBManager.sharedDatabase.deleteUploadData(strOrderID: "\(index)", strType: uploadType.hours.rawValue) { _ in
                    self.uploadAllData()
                }
            }
            else if strRequest == "updateCheckList"{
                //LICENSE UPLOAD
                CoreDBManager.sharedDatabase.deleteUploadData(strOrderID: "\(index)", strType: uploadType.checkList.rawValue) { _ in
                    self.uploadAllData()
                }
            }

        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        self.uploadAllData()
    }
}

