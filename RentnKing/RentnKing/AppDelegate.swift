//
//  AppDelegate.swift
//  RentnKing
//
//  Created by Jigar Khatri on 07/10/23.
//

import UIKit
import EventKit
import Alamofire
import ObjectMapper

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
    let context = CoreDBManager.sharedDatabase.persistentContainer.viewContext

    let store = EKEventStore()
    var event:EKEvent!

    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        setupKeyboard(true)
        
        //CREATE FOLDER
        createLicenseUploadFolder()
        createImageVideoUploadFolder()
        createFileStorageFolder()
        
        
        //SET FIREBASE AND NOTIFICATION
        self.setFireBase_Notificaiton(application: application)
      
        //SAVE TOKEN
        UserDefaults.standard.accessToken = Application.token
        
        // ✅ If nothing is pending, then start fresh
        BackgroundUploader.shared.restoreInFlightTasks { tasks in
            print("Restored \(tasks.count) background tasks")
            if tasks.isEmpty {
                // No tasks restored → safe to start new uploads
                DispatchQueue.main.async {
                    self.uploadAllData()
                }
            }
        }
        
        
        //UPDATE ORDER NOTE DATA
        setupNetworkMonitor()

        return true
    }
    
    private func setupNetworkMonitor() {
        let monitor = NetworkMonitor.shared
        
        // 🔄 Sync immediately if already online
        if monitor.isReachable() {
            print("✅ Internet available at launch → Sync now")
            syncOrderNoteWithAPI()
            syncEquipmentWithAPI()
        }
        
        // 👂 Listen for future internet restoration
        monitor.onNetworkRestored = {
            print("🌐 Internet restored after launch → Sync now")
            syncOrderNoteWithAPI()
            syncEquipmentWithAPI()
        }
    }
    
    

    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        BackgroundUploader.shared.setSystemCompletionHandler(completionHandler)
      }


    /// set orientations you want to be allowed in this property by default
//    var orientationLock = checkDeviceiPad() ? UIInterfaceOrientationMask.all : UIInterfaceOrientationMask.portrait
    var orientationLock = UIInterfaceOrientationMask.portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return self.orientationLock
    }
    

    @objc func uploadAllData() {
        if NetworkReachabilityManager()!.isReachable {
            //GET ORDER DATA
            let arrAllData = CoreDBManager.sharedDatabase.getAllUploadDATA()
            if arrAllData.count != 0{
                NotificationCenter.default.post(name: .startUploadData, object: nil)

                let objData = arrAllData[0]
                
                if objData.type == uploadType.image.rawValue ||
                    objData.type == uploadType.video_image.rawValue {
                    
                    var media_type = objData.videoType ?? "delivery" //For Video Image
                    
                    var arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.orderID ?? "", strType: objData.type ?? "", strVideoType: objData.videoType ?? "")
                    
                    
                    if objData.type == uploadType.image.rawValue {
                        media_type = "license" // For License Only
                        
                        arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.orderID ?? "", strType: objData.type ?? "")
                    }
                    
                    
                    let params = LicenseParameater(
                                order_unique_id: objData.orderID ?? "",
                                type: objData.type ?? "",
                                video_type: media_type,
                                order_product_unique_id: objData.productID ?? ""
                            )

                    uploadImagesAndVideos(arrData, meta: params)
                    
                }
                
                

//                if objData.type == uploadType.image.rawValue{
//                    let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.orderID ?? "", strType: objData.type ?? "")
//                    
//                    let params = LicenseParameater(
//                                order_unique_id: objData.orderID ?? "",
//                                type: objData.type ?? "",
//                                video_type: "license",
//                                order_product_unique_id: objData.productID ?? ""
//                            )
//
//                    uploadImagesAndVideos(arrData, meta: params)
//                }
//                else if objData.type == uploadType.video_image.rawValue {
//                    
//                    let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.orderID ?? "", strType: objData.type ?? "", strVideoType: objData.videoType ?? "")
//                    
//                    let params = LicenseParameater(
//                                order_unique_id: objData.orderID ?? "",
//                                type: objData.type ?? "",
//                                video_type: objData.videoType ?? "delivery",
//                                order_product_unique_id: objData.productID ?? ""
//                            )
//
//                    uploadImagesAndVideos(arrData, meta: params)
//
//                }
//                else if objData.type == uploadType.hours.rawValue{
//                    let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.orderID ?? "", strType: objData.type ?? "")
//                    self.updateHours(strOrderID: objData.orderID ?? "", arrHours: self.getMachineHoursArray(strOrderID: objData.orderID ?? "", arrData: arrData))
//                }
//                else if objData.type == uploadType.checkList.rawValue{
//                    let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.orderID ?? "", strType: objData.type ?? "")
//
//                    self.updateCheckList(strOrderID: objData.orderID ?? "", arrCheckList: self.getCheckListArray(strOrderID: objData.orderID ?? "", arrData: arrData))
//                }
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
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        NetworkMonitor.shared.startListening()
    }
}



struct LoginParameater: Codable {
    var email : String = "garyj@rentnking.com"
    var password : String = "Gary#1234"
}



extension AppDelegate :WebServiceHelperDelegate {
  
    
    func loginAPI(LoginParameater : LoginParameater){
        guard let parameater = try? LoginParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.login.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "login"
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
    
    
//    func callAPIforCategoryList(CatrgoryParameater : CatrgoryParameater, isdata: Bool, completion: @escaping (Bool) -> Void) {
//        
//        guard let parameater = try? CatrgoryParameater.asDictionary() else {
//            showAlertMessage(strMessage: str.invalidRequestParamater)
//            return
//        }
//        
//        
//        //Declaration URL
//        let strURL = "\(Url.categoryList.absoluteString!)"
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.methodType = "post"
//        webHelper.strURL = strURL
//        webHelper.dictType = parameater
//        webHelper.dictHeader = NSDictionary()
//        webHelper.delegateWeb = self
//        webHelper.showLogForCallingAPI = true
//        webHelper.serviceWithAlert = true
//        webHelper.indicatorShowOrHide = false
//        webHelper.callAPIwithCompletation { data, strRequest, error in
//            
//            if let strData = data {
//                saveToFile(data: strData, fileName: "CategoryList")
//            }
//        }
//
//    }

    
    func getScheduleCount(){

//        //Declaration URL
//        let strURL = "\(Url.scheduleListCound.absoluteString!)"
//        
//       
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "scheduleListCound"
//        webHelper.methodType = "get"
//        webHelper.strURL = strURL
//        webHelper.dictType = [:]
//        webHelper.dictHeader = NSDictionary()
//        webHelper.delegateWeb = self
//        webHelper.showLogForCallingAPI = true
//        webHelper.serviceWithAlert = true
//        webHelper.indicatorShowOrHide = false
//        webHelper.callAPI()
    }
    
    
    struct LicenseParameater: Codable {
        var order_unique_id : String
        var type : String
        var video_type : String
        var order_product_unique_id : String
    }

//    func callLicenseUploadAPI(LicenseParameater : LicenseParameater, imgFront : UIImage, imgBack : UIImage) {
//        guard let parameater = try? LicenseParameater.asDictionary() else {
//            showAlertMessage(strMessage: str.invalidRequestParamater)
//            return
//        }
//        
//        //Declaration URL
//        let strURL = "\(Url.uploadLicenseMedia.absoluteString!)"
//
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        
//      
//        //SET IMAGE
//        let dicImgFront = ["img": imgFront,
//                           "name": "\(Date().timeIntervalSince1970).jpeg",
//                           "key": "media[]",
//                           "type": "license"] as [String : Any]
//        
//        let dicImgBack = ["img": imgBack,
//                          "name": "\(Date().timeIntervalSince1970).jpeg",
//                          "key": "media[]",
//                          "type": "license"] as [String : Any]
//        
//        webHelper.arr_Mutlipleimages.append(dicImgFront)
//        webHelper.arr_Mutlipleimages.append(dicImgBack)
//        webHelper.strMethodName = "uploadLicense"
//        webHelper.strOrderID = LicenseParameater.order_unique_id
//        webHelper.strURL = strURL
//        webHelper.dictType = parameater
//        webHelper.dictHeader = NSDictionary()
//        webHelper.delegateWeb = self
//        webHelper.showLogForCallingAPI = true
//        webHelper.serviceWithAlert = true
//        webHelper.indicatorShowOrHide = false
//        webHelper.callUploadingMultipleImages()
//    }
    
    // MARK: - Mixed Image & Video Upload

    private func uploadImagesAndVideos(_ arrData: [UploadData], meta: LicenseParameater) {
        guard let fileParts = createFileParts(from: arrData) else { return }
        
        guard let url = URL(string: Url.uploadLicenseMedia.absoluteString ?? "") else {
            print("Invalid upload URL")
            return
        }
        
        let params: [String: String] = [
            "order_unique_id": meta.order_unique_id,
            "order_product_unique_id": meta.order_product_unique_id,
            "type": meta.video_type
        ]
        
        do {
            try BackgroundUploader.shared.uploadMultipartMany(
                parts: fileParts,
                to: url,
                method: "POST",
                params: params,
                headers: [
                    "Authorization": "Bearer \(UserDefaults.standard.accessToken ?? "")",
                    "lang": UserDefaults.standard.language
                ]
            ) { result in
                switch result {
                case .success((let response, let data)):
                    print("✅ Upload finished: \(response.statusCode)")
                    print("Response: \(String(data: data, encoding: .utf8) ?? "")")
                    
                    if response.statusCode == 200 {
                        
                        if meta.type == uploadType.image.rawValue {
                            //LICENSE UPLOAD SUCCESS
                            CoreDBManager.sharedDatabase.updateLicenseUploadDataStatus(strOrderID: meta.order_unique_id, strType: meta.type, newStatus: "SUCCESS") { _ in
                                self.uploadAllData()
                            }
                        }
                        else {
                            CoreDBManager.sharedDatabase.updateVideoImageUploadDataStatus(
                                strOrderID: meta.order_unique_id,
                                strType: meta.type, strVideoType: meta.video_type,
                                newStatus: "SUCCESS"
                            ) { _ in
                                self.uploadAllData()
                            }
                        }
                    }
                    
                case .failure(let error):
                    print("Upload failed: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Upload start error: \(error.localizedDescription)")
        }
    }

    // MARK: - File Preparation

    private func createFileParts(from arrData: [UploadData]) -> [BackgroundUploader.FilePart]? {
        var parts: [BackgroundUploader.FilePart] = []
        
        for item in arrData {
            if item.isImage {
                var imgUploaded = UIImage()

                if item.type == uploadType.image.rawValue {
                    imgUploaded = loadImage(fileName: arrData[0].name ?? "") ?? UIImage()
                }
                else {
                    imgUploaded = loadImagefromImageVideoDirectory(fileName: "\(item.orderID ?? "")/\(item.name ?? "")") ?? UIImage()
                }

                if let imageData = imgUploaded.jpegData(compressionQuality: 0.25) {
                    
                    let tmpURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(item.name ?? "")")
                    try? imageData.write(to: tmpURL)
                    
                    parts.append(
                        BackgroundUploader.FilePart(
                            fileURL: tmpURL,
                            fieldName: "media[]",
                            fileName: tmpURL.lastPathComponent,
                            mimeType: "image/jpeg"
                        )
                    )
                }
            } else {
                if let videoURL = getVideoUrl(fileName: "\(item.orderID ?? "")/\(item.name ?? "")") {
                    parts.append(
                        BackgroundUploader.FilePart(
                            fileURL: videoURL,
                            fieldName: "media[]",
                            fileName: videoURL.lastPathComponent,
                            mimeType: "video/mp4"
                        )
                    )
                }
            }
        }
        
        if parts.isEmpty {
            print("⚠️ No files found to upload")
            return nil
        }
        return parts
    }
   
    
//    func uploadImagAndVideo(arrData : [UploadData]){
        // Prepare your local file URLs from your picker/recorder
//        let img1 = URL(fileURLWithPath: "/path/to/a.jpg")
//        let img2 = URL(fileURLWithPath: "/path/to/b.png")
//        let vid1 = URL(fileURLWithPath: "/path/to/c.mp4")
//        
//        let endpoint = URL(string: "https://api.yourserver.com/uploads")!
//        let headers = ["Authorization": "Bearer <token>"]
//
//        let parts: [BGFilePart] = [
//            BGFilePart(fileURL: img1, fieldName: "files[]", fileName: "a.jpg", mimeType: "image/jpeg"),
//            BGFilePart(fileURL: img2, fieldName: "files[]", fileName: "b.png", mimeType: "image/png"),
//            BGFilePart(fileURL: vid1, fieldName: "files[]", fileName: "c.mp4", mimeType: "video/mp4"),
//        ]
//        let parts: [BackgroundUploader.FilePart] = [
//            .init(fileURL: img1, fieldName: "files[]", fileName: "a.jpg", mimeType: FileStore.mimeType(for: img1.pathExtension)),
//            .init(fileURL: img2, fieldName: "files[]", fileName: "b.png", mimeType: FileStore.mimeType(for: img2.pathExtension)),
//            .init(fileURL: vid1, fieldName: "files[]", fileName: "c.mp4", mimeType: FileStore.mimeType(for: vid1.pathExtension))
//        ]
//        
//        do {
//            try BackgroundUploader.shared.uploadMultipartMany(
//                parts: parts,
//                to: endpoint,
//                params: ["albumId": "123"],
//                headers: headers
//            ) { result in
//                switch result {
//                case .success((let http, let data)):
//                    print("Multi success: status=\(http.statusCode) body=\(String(data: data, encoding: .utf8) ?? "<binary>")")
//                case .failure(let error):
//                    print("Multi failed:", error)
//                }
//            }
//        } catch {
//            print("Failed to enqueue multi upload:", error)
//        }
//    }
    
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
    
//    func updateHours(strOrderID :String, arrHours : [[String : Any]]){
//    
//        //Declaration URL
//        let strURL = "\(Url.machineHours.absoluteString!)"
//        
//       
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "machineHours"
//        webHelper.methodType = "post"
//        webHelper.selectIndex = Int(strOrderID) ?? 0
//        webHelper.strURL = strURL
//        webHelper.dictType = [:]
//        webHelper.arryType = arrHours
//        webHelper.dictHeader = NSDictionary()
//        webHelper.delegateWeb = self
//        webHelper.showLogForCallingAPI = true
//        webHelper.serviceWithAlert = true
//        webHelper.indicatorShowOrHide = false
////        webHelper.callAPI2()
//    }
    
    
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

    
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String) {
        indicatorHide()
        
        if data.getStringForID(key: "success") == "1"{
            print(data)
            
            if strRequest == "login"{
                print(data)
                if let userData = data["user"] as? NSDictionary{
                    
                    //SAVE USER DATA
                    let userObj = User()
                    userObj.id = userData.getStringForID(key: "id")
                    userObj.email = userData.getStringForID(key: "email")
                    userObj.full_name = userData.getStringForID(key: "full_name")
                    
                    
                    
                    //SAVE OBJECT
                    UserDefaults.standard.user = userObj
                    UserDefaults.standard.accessToken = userData.getStringForID(key: "full_name")
                }
            }
            
            //            else
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
            //            else if strRequest == "uploadLicense"{
            //                //LICENSE UPLOAD SUCCESS
            //                CoreDBManager.sharedDatabase.updateLicenseUploadDataStatus(strOrderID: orderid, strType: uploadType.image.rawValue, newStatus: "SUCCESS") { _ in
            //                    self.uploadAllData()
            //                }
            //            }
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



