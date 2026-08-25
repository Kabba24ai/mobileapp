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

    /// True while a checklist item is uploading, so a second submit (or a retry
    /// trigger) doesn't start a duplicate concurrent upload of the same arr[0].
    /// In-memory only → always reset to false on a fresh launch.
    var isCheckListUploading = false

    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        setupKeyboard(true)
        
        UIApplication.shared.applicationIconBadgeNumber = 0
        self.checkAppVersionAndLogoutIfNeeded()
        
        //CREATE FOLDER
        createLicenseUploadFolder()
        createImageVideoUploadFolder()
        createFileStorageFolder()

        // Offline Sync Engine (Phase 2): the durable, idempotent queue for field operations.
        // Bootstrapped BEFORE any legacy sync trigger so the old driver-checklist queue is
        // migrated into it first. Registers its BGAppRefreshTask (must happen before launch
        // completes) and listens for app-active / session-expired itself.
        KabbaSync.bootstrap(
            baseURL: { URL(string: Application.BaseURL_NEW) },
            accessToken: { UserDefaults.standard.accessToken },
            language: { UserDefaults.standard.language },
            legacyMigrations: [
                migrateLegacyDriverChecklistQueueIntoSyncEngine,
                migrateLegacyCustomerChecklistQueueIntoSyncEngine,      // Phase 3: retires the 5-retry dead-letter
                migrateLegacyDeliveryPickupInputsQueueIntoSyncEngine,   // Phase 3: retires the last legacy queue
            ],
            onSessionExpired: { [weak self] in self?.handleExpiredSession() }
        )

        //RECLAIM ALREADY-UPLOADED MEDIA (7-day grace; keeps Pending files)
//        MediaCleanupManager.shared.purgeUploadedMedia(graceDays: 7)
        
        
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
            syncDriverChecklistWithAPI()
            syncDeliveryPickupInputsWithAPI()
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
            
            //GET NOTIFICATION COUNT
            if UserDefaults.standard.user != nil{
                syncOrderNoteWithAPI()
                syncEquipmentWithAPI()
                self.getNotificationListApi()
                self.updateCheckListData()
                syncDriverChecklistWithAPI()
                syncDeliveryPickupInputsWithAPI()
                self.uploadAllData()          // retry pending media now that we're online
                KabbaSync.kick("network available at launch", ignoreBackoff: true)
            }
        }


        // 👂 Listen for future internet restoration
        monitor.onNetworkRestored = {
            print("🌐 Internet restored after launch → Sync now")

            //GET NOTIFICATION COUNT
            if UserDefaults.standard.user != nil{
                syncOrderNoteWithAPI()
                syncEquipmentWithAPI()
                self.getNotificationListApi()
                self.updateCheckListData()
                syncDriverChecklistWithAPI()
                syncDeliveryPickupInputsWithAPI()
                self.uploadAllData()          // retry pending media when connectivity returns
                KabbaSync.kick("network restored", ignoreBackoff: true)
            }
        }
    }

    /// A genuine HTTP 401 reached the canonical network layer (KabbaAPIClient / the legacy
    /// WebServiceHelper): the token is dead. End the session the way Settings › Log Out does —
    /// WITHOUT touching the Sync Engine's stored operations, which stay on the phone and resume
    /// after the employee signs back in. Before Phase 1 a 401 never logged anyone out.
    func handleExpiredSession() {
        guard UserDefaults.standard.user != nil || UserDefaults.standard.accessToken != nil else { return }

        // Phase 5: the queue is untouched — quote it so the employee knows nothing was lost.
        let pending = KabbaSession.pendingWorkCount()
        KabbaSession.end()

        UserDefaults.standard.user = nil
        UserDefaults.standard.accessToken = nil          // clears the shared Keychain item (extension included)
        UserDefaults.standard.baseURL = ""
        defaultsToExtension?.set("", forKey: "api_url")
        defaultsToExtension?.removeObject(forKey: "auth_token")
        defaultsToExtension?.synchronize()

        let storyBoard = UIStoryboard(name: GlobalMainConstants.LOGIN_MODEL, bundle: nil)
        if let login = storyBoard.instantiateViewController(withIdentifier: "LoginViewController") as? LoginViewController {
            let navigationController = UINavigationController()
            navigationController.viewControllers = [login]
            self.window?.rootViewController = navigationController
            self.window?.makeKeyAndVisible()
        }
        let kept = pending > 0 ? " \(pending) item\(pending == 1 ? "" : "s") saved on this phone \(pending == 1 ? "is" : "are") kept and will sync after you sign in." : ""
        showAlertMessage(strMessage: "Your session has expired. Please sign in again." + kept)
    }
    
    

    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        // Phase 4: the Sync Engine's media transfers have their own background session.
        if identifier == SyncBackgroundUploader.sessionIdentifier {
            SyncBackgroundUploader.shared.handleEvents(completionHandler: completionHandler)
            return
        }
        BackgroundUploader.shared.setSystemCompletionHandler(completionHandler)
      }


    /// set orientations you want to be allowed in this property by default
//    var orientationLock = checkDeviceiPad() ? UIInterfaceOrientationMask.all : UIInterfaceOrientationMask.portrait
    var orientationLock = UIInterfaceOrientationMask.portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return self.orientationLock
    }
    

    @objc func uploadAllData() {
        // Phase 4: with the Sync Engine up, anything still in the legacy Core Data upload queue is
        // migrated into per-file operations (files moved into protected storage, rows stamped
        // MIGRATED / QUARANTINED — never deleted) and the engine drains. This entry point is only
        // reached once the legacy BackgroundUploader reported no in-flight tasks, so a legacy
        // upload that is about to finish is never uploaded twice. The legacy uploader below runs
        // only if the engine is unavailable.
        if KabbaSync.isReady {
            migrateLegacyMediaQueueIntoSyncEngine()
            KabbaSync.kick("media", ignoreBackoff: true)
            return
        }

        if NetworkReachabilityManager()?.isReachable == true {
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
            }
            else{
                //QUEUE EMPTY — everything uploaded; reclaim local media (keeps Pending, 7-day grace)
//                MediaCleanupManager.shared.purgeUploadedMedia(graceDays: 7)
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
    /// Phase 5 (additive): the device model only — never the user-assigned device name.
    var device_name : String = UIDevice.current.model
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
                    #if DEBUG
                    print("✅ Upload finished: \(response.statusCode)")
                    print("Response: \(String(data: data, encoding: .utf8) ?? "")")
                    #endif
                    
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

            // The temp compressed image copies were already streamed into the multipart
            // body, so delete them now to free temporary storage.
            cleanupTempParts(fileParts)
        } catch {
            print("Upload start error: \(error.localizedDescription)")
            // Also clean up on failure — otherwise the temp JPEGs leak on every failed attempt.
            cleanupTempParts(fileParts)
        }
    }

    /// Deletes any temp-directory file parts (compressed JPEG copies) once they're no longer needed.
    private func cleanupTempParts(_ fileParts: [BackgroundUploader.FilePart]) {
        let tmpDir = FileManager.default.temporaryDirectory.path
        for part in fileParts where part.fileURL.path.hasPrefix(tmpDir) {
            try? FileManager.default.removeItem(at: part.fileURL)
        }
    }

    // MARK: - File Preparation

    private func createFileParts(from arrData: [UploadData]) -> [BackgroundUploader.FilePart]? {
        var parts: [BackgroundUploader.FilePart] = []
        
        for item in arrData {
            if item.isImage {
                var imgUploaded = UIImage()

                if item.type == uploadType.image.rawValue {
                    imgUploaded = loadImage(fileName: item.name ?? "") ?? UIImage()
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
        // Phase 3: with the Sync Engine up, anything still in the legacy queue is migrated into it
        // and the engine drains; the legacy uploader below runs only if the engine is unavailable.
        if KabbaSync.isReady {
            migrateLegacyCustomerChecklistQueueIntoSyncEngine()
            KabbaSync.kick("customer checklist", ignoreBackoff: true)
            return
        }

        // Don't start a second upload while one is already in flight.
        if isCheckListUploading { return }

        let arr = getChecklistData() ?? []
        guard let obj = arr.first else { return }

        isCheckListUploading = true
        self.updateCheckList(dicCheckList: obj)
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
                    // Bearer token must come from the "token" key (matches LoginModel) — it was
                    // wrongly reading "full_name", which would send a bogus Authorization header.
                    UserDefaults.standard.accessToken = userData.getStringForID(key: "token")
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
                // Upload finished — release the in-flight lock BEFORE triggering the next drain.
                self.isCheckListUploading = false

                //REFRESH ORDER DETAILS
                self.CallAPIforGetOrderDetails(strChecklistType: strChecklistType, OrdersDetailsParameater: OrdersDetailsParameater(unique_id: orderid))

                // Remove ONLY the item that was just uploaded. updateCheckListData() always
                // sends arr[0], so removing the first entry drains the queue one-by-one
                // without dropping other rows that share the same equipment_unique_id.
                var arr = getChecklistData() ?? []
                let justUploaded = arr.first     // the checklist item that was just saved
                if !arr.isEmpty {
                    arr.removeFirst()
                }

                // Persist the trimmed queue; saveArrayWithImages also triggers the next upload.
                saveArrayWithImages(arr)

                // Order fully done (Return checklist saved) → reclaim this order's local
                // photos/videos/license. purgeMedia is a no-op if any file is still uploading,
                // so nothing un-sent is ever lost.
                if (justUploaded?["type"] as? String) == "Return",
                   let orderUniqueId = justUploaded?["order_unique_id"] as? String, !orderUniqueId.isEmpty {
                    MediaCleanupManager.shared.purgeMedia(forOrder: orderUniqueId)
                }
            }
            else if strRequest == "getNotification"{
                UIApplication.shared.applicationIconBadgeNumber = 0
                if let arrData = data["notifications"] as? NSArray{
                    
                    arrNotifications = []
                    arrNotifications = Mapper<NotificationsModel>().mapArray(JSONArray: (arrData as? [[String : Any]]) ?? [])
                    
                    UIApplication.shared.applicationIconBadgeNumber = arrNotifications.count
                    NotificationCenter.default.post(name: .notificationCount, object: nil)

                }
            }
            else if strRequest == "updateNotification"{
                self.getNotificationListApi()
            }
        }
        else{
            if strRequest == "updateCheckList"{
                // Server accepted the HTTP call but rejected the checklist (success != "1").
                // Release the lock, then KEEP the item for retry — but cap attempts so a
                // permanently-rejected checklist can't block the whole queue forever.
                self.isCheckListUploading = false

                var arr = getChecklistData() ?? []
                if !arr.isEmpty {
                    let attempts = ((arr[0]["_attempts"] as? Int) ?? 0) + 1
                    if attempts >= kMaxSyncAttempts {
                        print("Checklist: dropping server-rejected item after \(attempts) attempts")
                        arr.removeFirst()                       // dead-letter → unblock the queue
                        saveArrayWithImages(arr)                // persist + advance to the next item
                    } else {
                        arr[0]["_attempts"] = attempts          // keep; retry on next launch / network restore
                        saveArrayWithImages(arr, triggerUpload: false)   // persist without an immediate re-upload loop
                    }
                }
            }
            else if strRequest == "getNotification"{
                arrNotifications = []
                UIApplication.shared.applicationIconBadgeNumber = 0
                NotificationCenter.default.post(name: .notificationCount, object: nil)

            }
        }
    }

    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }

    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        if strRequest == "updateCheckList"{
            // The checklist upload failed (network drop, parse error, or a code
            // 100/101/102/401 rejection). DON'T drain the item and DON'T fall through
            // to uploadAllData() — that drains the image/video queue, not this one.
            // Just release the lock; the item stays queued and retries via the
            // launch / network-restore triggers that call updateCheckListData().
            self.isCheckListUploading = false
            return
        }

        // (M8) Previously any unrelated API failure drained the media queue here — surprising
        // coupling. Media retries now happen via their proper triggers: launch, network
        // available/restored, and the background uploader's own completion handler.

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
                    let map = Map(mappingType: .fromJSON, JSON: (dicData as? [String : Any]) ?? [:])
                    let objOrderData = OrdersListModel(map: map)
                    
                    
                    SDKUserDefault.remove(for: "\(kFileStorageName.kCheckListOrderDetailsData.rawValue)_\(strChecklistType)_\(objOrderData?.unique_id ?? "")")
                    SDKUserDefault.remove(for: "\(kFileStorageName.kCheckListOtherData.rawValue)_\(strChecklistType)_\(objOrderData?.unique_id ?? "")")

                    
                }
            }
           
        }
    }
    
}


