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
var arrNotifications : [NotificationsModel] = []

let defaultsToExtension = UserDefaults(suiteName: "group.com.RentnKingNew.shared")


struct NotificationsModel: Mappable{
    internal var order_id: Int?
    
    init?(map:Map) {
        mapping(map: map)
    }
    
    mutating func mapping(map:Map){
        order_id <- map["order_id"]
    }
}


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
        
        UIApplication.shared.applicationIconBadgeNumber = 0
        self.checkAppVersionAndLogoutIfNeeded()
        
        //CREATE FOLDER
        createLicenseUploadFolder()
        createImageVideoUploadFolder()
        createFileStorageFolder()
        
        
        //SET FIREBASE AND NOTIFICATION
        self.setFireBase_Notificaiton(application: application)
      
        //SAVE TOKEN
        
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
        
//        UserDefaults.standard.baseURL = "https://api.rentnking.com/api/admin/v1/"
//        UserDefaults.standard.baseURL = "https://api.kabba.ai/api/admin/v1/"
        
        //GET NOTIFICATION COUNT
        if UserDefaults.standard.user != nil{
            self.getNotificationListApi()
            self.updateCheckListData()
        }
        
        //UPDATE ORDER NOTE DATA
        setupNetworkMonitor()

        return true
    }
    
    
    func checkAppVersionAndLogoutIfNeeded() {
        let targetVersion = "1.0.0"
        let targetBuild = "1015"

        // Current app version & build
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""

        // Stored version & build from last install
        let storedVersion = UserDefaults.standard.string(forKey: "last_app_version")
        let storedBuild = UserDefaults.standard.string(forKey: "last_app_build")

        // First install → just save and exit
        guard let oldVersion = storedVersion,
              let oldBuild = storedBuild else {

            UserDefaults.standard.set(currentVersion, forKey: "last_app_version")
            UserDefaults.standard.set(currentBuild, forKey: "last_app_build")
            
            //REMOVE ALL DATA
            UserDefaults.standard.user = nil
            UserDefaults.standard.accessToken = nil

            return
        }

        // If app updated to target version/build
        if currentVersion == targetVersion &&
           currentBuild == targetBuild &&
           (oldVersion != currentVersion || oldBuild != currentBuild) {

            //REMOVE ALL DATA
            UserDefaults.standard.user = nil
            UserDefaults.standard.accessToken = nil

        }

        // Save current version/build
        UserDefaults.standard.set(currentVersion, forKey: "last_app_version")
        UserDefaults.standard.set(currentBuild, forKey: "last_app_build")
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
                        
                        arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.orderID ?? "", strType: objData.type ?? "", image_side: objData.image_side ?? "")
                    }
                    
                    
                    let params = LicenseParameater(
                                order_unique_id: objData.orderID ?? "",
                                type: objData.type ?? "",
                                video_type: media_type,
                                order_product_unique_id: objData.productID ?? "",
                                image_side: objData.image_side ?? "",
                                license_expiry_date: objData.license_expiry_date ?? "",
                                auto_inject_by: objData.auto_inject_by ?? ""
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
        
        
        //GET NOTIFICATION COUNT
        if UserDefaults.standard.user != nil{
            self.getNotificationListApi()
        }
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 3.0) {
            AppUpdateManager.shared.checkForUpdate()
        }
    }
}



struct LoginParameater: Codable {
    var email : String = ""
    var password : String = ""
}

struct NotificationParameater: Codable {
    var order_id : String
}

extension AppDelegate :WebServiceHelperDelegate {
  
    
   
    
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
    
    
    func getNotificationListApi(){
        
        //Declaration URL
        let strURL = "\(Url.getNotification.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "getNotification"
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
    
   
    func updateNotificationApi(NotificationParameater : NotificationParameater){
        guard let parameater = try? NotificationParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.updateNotification.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "updateNotification"
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
    
 
    
    struct LicenseParameater: Codable {
        var order_unique_id : String
        var type : String
        var video_type : String
        var order_product_unique_id : String
        var image_side: String
        var license_expiry_date: String
        var auto_inject_by: String
    }

    
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
            "type": meta.video_type,
            "side": meta.image_side,
            "license_expiry_date": meta.license_expiry_date,
            "auto_inject_by": meta.auto_inject_by
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
                            CoreDBManager.sharedDatabase.updateLicenseUploadDataStatus(strOrderID: meta.order_unique_id, strType: meta.type, image_side: meta.image_side, newStatus: "SUCCESS") { _ in
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
   
    
    
   
    func updateCheckListData(){
        let arr = getChecklistData()
        if arr?.count != 0{
            if let obj = arr?[0]{
                self.updateCheckList(dicCheckList: obj)
            }
        }
    }
    
    
    func getUploadedFiles(dicCheckList : [String : Any]) -> [[String : Any]]{
        //SET IMAGE
        var arr_Mutlipleimages : [[String : Any]] = []
        if ("\(dicCheckList["type"] ?? "")" == "Delivery" ? dicCheckList["dSignature"] as? UIImage ?? UIImage() : dicCheckList["rSignature"] as? UIImage ?? UIImage()) != UIImage(){
            let dicData = ["img": "\(dicCheckList["type"] ?? "")" == "Delivery" ? dicCheckList["dSignature"] as? UIImage ?? UIImage() : dicCheckList["rSignature"] as? UIImage ?? UIImage() ,
                           "name": "\(Date().timeIntervalSince1970).jpeg",
                           "key": "signature_media"] as [String : Any]
            arr_Mutlipleimages.append(dicData)
        }

        return arr_Mutlipleimages
    }
  
    func updateCheckList(dicCheckList : [String : Any]){
        ImpactGenerator()
       
        //Declaration URL
        var strURL = ""
        
        
        if "\(dicCheckList["type"] ?? "")" == "Delivery"{
            strURL = "\(Url.updateDeliveryCheckList.absoluteString!)"
        }
        else{
            strURL = "\(Url.updateReturnCheckList.absoluteString!)"
        }
        
        print(strURL)
        print(dicCheckList)

        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.arr_Mutlipleimages = self.getUploadedFiles(dicCheckList: dicCheckList)
        webHelper.strMethodName = "updateCheckList"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = dicCheckList
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.strOrderID = "\(dicCheckList["equipment_unique_id"] ?? "")"
        webHelper.startUploadingMultipleImages()
    }

    
    
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
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
            else if strRequest == "updateCheckList"{
                //REMVOE DATA
                self.CallAPIforGetOrderDetails(strChecklistType: strChecklistType, OrdersDetailsParameater: OrdersDetailsParameater(unique_id: orderid))
                
                // REMOVE DATA safely using a mutable local copy
                var arr = getChecklistData() ?? []
                
                // Remove all items matching equipment_unique_id == orderid
                arr.removeAll { item in
                    (item["equipment_unique_id"] as? String) == orderid
                }
                
                if arr.count != 0{
                    saveArrayWithImages(arr)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                        self.updateCheckListData()
                    })
                }
                
                    
            }
            else if strRequest == "getNotification"{
                UIApplication.shared.applicationIconBadgeNumber = 0
                if let arrData = data["notifications"] as? NSArray{
                    
                    arrNotifications = []
                    arrNotifications = Mapper<NotificationsModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    
                    UIApplication.shared.applicationIconBadgeNumber = arrNotifications.count
                    NotificationCenter.default.post(name: .notificationCount, object: nil)

                }
            }
            else if strRequest == "updateNotification"{
                self.getNotificationListApi()
            }
        }
        else{
            if strRequest == "getNotification"{
                arrNotifications = []
                UIApplication.shared.applicationIconBadgeNumber = 0
                NotificationCenter.default.post(name: .notificationCount, object: nil)

            }
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        self.uploadAllData()
        
        if strRequest == "getNotification"{
            arrNotifications = []
            UIApplication.shared.applicationIconBadgeNumber = 0
            NotificationCenter.default.post(name: .notificationCount, object: nil)

        }
    }

    
    
    func CallAPIforGetOrderDetails(strChecklistType : String, OrdersDetailsParameater : OrdersDetailsParameater){
        guard let parameater = try? OrdersDetailsParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.orderDetails.absoluteString!)"
        
        
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPIwithCompletation { dic, arr, success, err in
            indicatorHide()
            if dic?.getStringForID(key: "success") == "1" {
                if let dicData = dic?["order"] as? NSDictionary{
                    
                    //SET DATA
                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
                    let objOrderData = OrdersListModel(map: map)
                    
                    
                    SDKUserDefault.remove(for: "\(kFileStorageName.kCheckListOrderDetailsData.rawValue)_\(strChecklistType)_\(objOrderData?.unique_id ?? "")")
                    SDKUserDefault.remove(for: "\(kFileStorageName.kCheckListOtherData.rawValue)_\(strChecklistType)_\(objOrderData?.unique_id ?? "")")

                    
                }
            }
           
        }
    }
    
}


