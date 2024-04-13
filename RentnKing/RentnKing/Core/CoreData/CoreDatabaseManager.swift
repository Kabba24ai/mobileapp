//
//  CoreDatabaseManager.swift
//  SAMUH
//
//  Created by Jigar Khatri on 13/07/21.
//

import Foundation
import CoreData

class CoreDBManager: NSObject {
    
    static let sharedDatabase = CoreDBManager()
    
    // MARK: - Core Data stack
    lazy var applicationDocumentsDirectory: URL = {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[urls.count-1]
    }()
    
    lazy var managedObjectModel: NSManagedObjectModel = {
        let modelURL = Bundle.main.url(forResource: "RentnKingDataBase", withExtension: "momd")!
        return NSManagedObjectModel(contentsOf: modelURL)!
    }()
    
    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
        
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
        let url = self.applicationDocumentsDirectory.appendingPathComponent("RentnKingDataBase.sqlite")
//        UserDefaultManager.setStringToUserDefaults(value: url.path, key: LOCAL_DATABASE_PATH)
        
        var failureReason = "There was an error creating or loading the application's saved data."
        do {
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
        } catch {
            
            var dict = [String: AnyObject]()
            dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data" as AnyObject?
            dict[NSLocalizedFailureReasonErrorKey] = failureReason as AnyObject?
            
            dict[NSUnderlyingErrorKey] = error as NSError
            let wrappedError = NSError(domain: "YOUR_ERROR_DOMAIN", code: 9999, userInfo: dict)
            NSLog("Unresolved error \(wrappedError), \(wrappedError.userInfo)")
            abort()
        }
        
        return coordinator
    }()
    
    
    lazy var persistentContainer: NSPersistentContainer = {
        
        let container = NSPersistentContainer(name: "RentnKingDataBase")
        let url = self.applicationDocumentsDirectory.appendingPathComponent("RentnKingDataBase.sqlite")
        NSLog("Database Path: \(url)")
      //  UserDefaultManager.setStringToUserDefaults(value: url.path, key: LOCAL_DATABASE_PATH)
        
        /*add necessary support for migration*/
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions =  [description]
        /*add necessary support for migration*/
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()
    
    
    lazy var managedObjectContext: NSManagedObjectContext = {        return CoreDBManager.sharedDatabase.persistentContainer.viewContext
    }()
    
    // MARK: - Core Data Saving support
    
    func saveContext () {
        if managedObjectContext.hasChanges {
            DispatchQueue.main.async {
                do {
                    try self.managedObjectContext.save()
                } catch {
                    let nserror = error as NSError
                    NSLog("Unresolved error \(nserror), \(nserror.userInfo)")
                }
            }
            
        }
    }
    
    
    //==== GET DATA ==== //
    func getAllUploadDATA() -> [UploadData]{
        let objContext = self.managedObjectContext
        let fetchRequest = NSFetchRequest<UploadData>(entityName: "UploadData")
        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "UploadData", in: objContext)!
        fetchRequest.entity = disentity
        
        do{
            return try managedObjectContext.fetch(fetchRequest)
        }
        catch
        {
            return []
        }
    }

    func getUploadListData(strOrderID : String) -> [UploadData]{
        
        let objContext = self.managedObjectContext
        let fetchRequest = NSFetchRequest<UploadData>(entityName: "UploadData")
        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "UploadData", in: objContext)!
        
        let predicate0_1 = NSPredicate(format:"orderID == %@",strOrderID)
        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1])
        
        fetchRequest.predicate = predicate1
        fetchRequest.entity = disentity
        
        do{
            return try managedObjectContext.fetch(fetchRequest)
        }
        catch
        {
            return []
        }
    }
    
//    func getDownloadListWithShowIDData(strShowID : String) -> [DownloadList]{
//        
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<DownloadList>(entityName: "DownloadList")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "DownloadList", in: objContext)!
//        
//        let predicate0_1 = NSPredicate(format:"show_id == %@",strShowID)
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1])
//        
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        
//        
//        
////        let objContext = self.managedObjectContext
////        let fetchRequest = NSFetchRequest<DownloadList>(entityName: "DownloadList")
////        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "DownloadList", in: objContext)!
////        fetchRequest.entity = disentity
//        
//        do{
//            return try managedObjectContext.fetch(fetchRequest)
////            return try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [DownloadList]
//        }
//        catch
//        {
//            return []
//        }
//    }
//    
//
//
//    
//    func getDownloadListWithProfileData(strProfileID : String) -> [DownloadList]{
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<DownloadList>(entityName: "DownloadList")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "DownloadList", in: objContext)!
//        let predicate1 = NSPredicate(format:"profile_id == \(strProfileID)")
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            return try managedObjectContext.fetch(fetchRequest)
//
////            return try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [DownloadList]
//        }
//        catch
//        {
//            return []
//        }
//    }
//    
//    func getAllDownloadData() -> [Download]{
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<Download>(entityName: "Download")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "Download", in: objContext)!
////        let predicate1 = NSPredicate(format:"show_id == \(strID)")
////        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//   
//        
//        do{
//            
//            let results = try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [Download]
//            print(results)
//            return try managedObjectContext.fetch(fetchRequest)
//
////            return try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [Download]
//        }
//        catch
//        {
//            return []
//        }
//    }
//    
// 
//    func getDownloadListWithEpisodeIDData(episodeID : String ,strProfileID : String) -> [Download]{
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<Download>(entityName: "Download")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "Download", in: objContext)!
//        
//        let predicate0_1 = NSPredicate(format:"episode_id == %@",episodeID)
//        let predicate0_2 = NSPredicate(format:"profile_id == %@",strProfileID)
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2])
//        
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            return try managedObjectContext.fetch(fetchRequest)
//
////            return try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [Download]
//        }
//        catch
//        {
//            return []
//        }
//    }
//    
//    func getDownloadVideosWithShowIDData(showID : String, videoID : String, strProfileID : String) -> [Download]{
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<Download>(entityName: "Download")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "Download", in: objContext)!
//
//        let predicate0_1 = NSPredicate(format:"show_id == %@",showID)
//        let predicate0_2 = NSPredicate(format:"video_id == %@",videoID)
////        let predicate0_3 = NSPredicate(format:"profile_id == %@",strProfileID)
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2])
//        
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            return try managedObjectContext.fetch(fetchRequest)
//
//            
////            return try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [Download]
//        }
//        catch
//        {
//            return []
//        }
//    }
//    
//    func getSessionIDData(session_id : String) -> [Download]{
//        
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<Download>(entityName: "Download")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "Download", in: objContext)!
//
//        let predicate0_1 = NSPredicate(format:"session_id == %@",session_id)
//            
//        fetchRequest.predicate = predicate0_1
//        fetchRequest.entity = disentity
//        
//        
//        
//        do{
////            return try managedObjectContext.fetch(fetchRequest)
//            return try managedObjectContext.fetch(fetchRequest)
//        }
//        catch
//        {
//            return []
//        }
//    }
//    
//    
//    func getDownloadVideosWithShowAndProfileIDData(showID : String, strProfileID : String, strUserID : String) -> [Download]{
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<Download>(entityName: "Download")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "Download", in: objContext)!
//        
//        let predicate0_1 = NSPredicate(format:"show_id == %@",showID)
//        let predicate0_2 = NSPredicate(format:"profile_id == %@",strProfileID)
//        let predicate0_3 = NSPredicate(format:"userID == %@",strUserID)
//
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3])
//        
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            
//            return try managedObjectContext.fetch(fetchRequest)
//
//            
//         //   return try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [Download]
//        }
//        catch
//        {
//            return []
//        }
//    }
    

    
//    //====SAVE DATABASE=====
//    func saveDownalodList(objSaveData:SaveDownloadParameater ,complete:@escaping (_ isSave:Bool) -> ()){
//
//        
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<DownloadList>(entityName: "DownloadList")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "DownloadList", in: objContext)!
//        let predicate0_1 = NSPredicate(format:"show_id == \(objSaveData.show_id)")
//        let predicate0_2 = NSPredicate(format:"profile_id == %@",objSaveData.profile_id)
//        let predicate0_3 = NSPredicate(format:"userID == %@",objSaveData.userID)
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3])
//        
//
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            var objCDDownload:DownloadList!
//            let results = try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [DownloadList]
//            if(results.count == 0)
//            {
//                
//                objCDDownload = (NSEntityDescription.insertNewObject(forEntityName:"DownloadList",into:managedObjectContext) as? DownloadList)!
//                
//                objCDDownload.profile_id = objSaveData.profile_id
//                objCDDownload.profile_name = objSaveData.profile_name
//                objCDDownload.profile_image = objSaveData.profile_image
//                objCDDownload.show_id = objSaveData.show_id
//                objCDDownload.show_name = objSaveData.show_name
//                objCDDownload.show_image = objSaveData.show_image
//                objCDDownload.isShow = objSaveData.isShow
//                objCDDownload.userID = objSaveData.userID
//                
//                self.saveContext()
//
//                //SAVE SHOW VIDEO OR DOWNALOAD
//                //SAVE DOWNLOAD URL
//                saveDownalodURL(objSaveShowData: DownloadVideoParameater(download_percentage: "", isDownload: "false", profile_id: objSaveData.profile_id, show_id: objSaveData.show_id, video_id: objSaveData.video_id, video_name: objSaveData.video_name, video_url: objSaveData.video_url, download_URL: "", isPush: "false", episode_id : objSaveData.episode_id ,episode_name: objSaveData.episode_name, video_img: objSaveData.video_img, userID: objSaveData.userID, subTitleUrl: objSaveData.subTitleUrl, expiry_date: objSaveData.expiry_date, download_ID: objSaveData.download_ID)) { isSave in
//                    if isSave{
//                        complete(true)
//                    }
//                }
//            }
//            else{
//                saveDownalodURL(objSaveShowData: DownloadVideoParameater(download_percentage: "", isDownload: "false", profile_id: objSaveData.profile_id, show_id: objSaveData.show_id, video_id: objSaveData.video_id, video_name: objSaveData.video_name, video_url: objSaveData.video_url, download_URL: "", isPush: "false", episode_id : objSaveData.episode_id ,episode_name: objSaveData.episode_name, video_img: objSaveData.video_img, userID: objSaveData.userID, subTitleUrl: objSaveData.subTitleUrl, expiry_date: objSaveData.expiry_date, download_ID: objSaveData.download_ID)) { isSave in
//                    if isSave{
//                        complete(true)
//                    }
//                }
//            }
//        }
//        catch
//        {
//            print("CHAT SYNCH FAILED")
//        }
//        
//    }
//
//    
//    func saveDownalodURL(objSaveShowData:DownloadVideoParameater,complete:@escaping (_ isSave:Bool) -> ()){
//        
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<Download>(entityName: "Download")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "Download", in: objContext)!
//        let predicate0_1 = NSPredicate(format:"show_id == \(objSaveShowData.show_id)")
//        let predicate0_2 = NSPredicate(format:"profile_id == %@",objSaveShowData.profile_id)
//        let predicate0_3 = NSPredicate(format:"video_id == %@",objSaveShowData.video_id)
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3])
//
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            var objCDDownloadShow:Download!
//            let results = try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [Download]
//            if(results.count == 0)
//            {
//         
//                objCDDownloadShow = (NSEntityDescription.insertNewObject(forEntityName:"Download",into:managedObjectContext) as? Download)!
//                
//                objCDDownloadShow.download_percentage = objSaveShowData.download_percentage
//                objCDDownloadShow.isDownload = objSaveShowData.isDownload
//                objCDDownloadShow.profile_id = objSaveShowData.profile_id
//                objCDDownloadShow.show_id = objSaveShowData.show_id
//                objCDDownloadShow.video_id = objSaveShowData.video_id
//                objCDDownloadShow.video_name = objSaveShowData.video_name
//                objCDDownloadShow.video_url = objSaveShowData.video_url
//                objCDDownloadShow.download_URL = objSaveShowData.download_URL
//                objCDDownloadShow.video_quality = UserDefaults.standard.defaultDownloadVideo
//                if UserDefaults.standard.defaultDownloadVideo == ""{
//                    objCDDownloadShow.video_quality = "360"
//                }
//                objCDDownloadShow.session_id = ""
//                objCDDownloadShow.episode_id = objSaveShowData.episode_id
//                objCDDownloadShow.episode_name = objSaveShowData.episode_name
//                objCDDownloadShow.video_img = objSaveShowData.video_img
//                objCDDownloadShow.userID = objSaveShowData.userID
//                objCDDownloadShow.subTitleUrl = objSaveShowData.subTitleUrl
//                objCDDownloadShow.expiry_date = objSaveShowData.expiry_date
//                objCDDownloadShow.download_ID = objSaveShowData.download_ID
//                self.saveContext()
//                complete(true)
//            }
//        }
//        catch
//        {
//            print("CHAT SYNCH FAILED")
//        }
//    }
//    
//    
//    //====UPDATE DATABASE=====
//    func updateDownalodURL(showID : String, videoID : String, strProfileID : String, download_percentage : String ,sessionID : String , isisDownload : String, FileName : String, complete:@escaping (_ isSave:Bool) -> ()){
//        
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<Download>(entityName: "Download")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "Download", in: objContext)!
//
//        let predicate0_1 = NSPredicate(format:"show_id == %@",showID)
//        let predicate0_2 = NSPredicate(format:"video_id == %@",videoID)
//        let predicate0_3 = NSPredicate(format:"profile_id == %@",strProfileID)
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3])
//        
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//      
//        
//        do{
//            var objCDDownloadShow:Download!
//            let results = try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [Download]
//            if(results.count != 0)
//            {
//                let obj = results[0]
//                objCDDownloadShow = results[0] as Download
//                objCDDownloadShow.download_percentage = download_percentage
//                objCDDownloadShow.isDownload = isisDownload
//                objCDDownloadShow.show_id = obj.show_id
//                objCDDownloadShow.video_id = obj.video_id
//                objCDDownloadShow.video_name = obj.video_name
//                objCDDownloadShow.video_url = obj.video_url
//                objCDDownloadShow.download_URL = FileName
//                objCDDownloadShow.session_id = sessionID
//                self.saveContext()
//                complete(true)
//            }
//            else{
//                complete(false)
//            }
//        }
//        catch
//        {
//            print("CHAT SYNCH FAILED")
//        }
//        
//    }
//    
//    func updateDownalodPresontageURL(videoID : String, percentage : String, isPush : String, complete:@escaping (_ isSave:Bool) -> ()){
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<Download>(entityName: "Download")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "Download", in: objContext)!
//        let predicate1 = NSPredicate(format:"video_id == \(videoID)")
//        
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            var objCDDownloadShow:Download!
//            let results = try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [Download]
//            if(results.count != 0)
//            {
//                
//                objCDDownloadShow = results[0] as Download
//                objCDDownloadShow.download_percentage = percentage
//                objCDDownloadShow.isDownload = objCDDownloadShow.isDownload
//                objCDDownloadShow.show_id = objCDDownloadShow.show_id
//                objCDDownloadShow.video_id = objCDDownloadShow.video_id
//                objCDDownloadShow.video_name = objCDDownloadShow.video_name
//                objCDDownloadShow.video_url = objCDDownloadShow.video_url
//                objCDDownloadShow.download_URL = objCDDownloadShow.download_URL
//                objCDDownloadShow.isPush = isPush
//                self.saveContext()
//                complete(true)
//            }
//            else{
//                complete(false)
//            }
//        }
//        catch
//        {
//            print("CHAT SYNCH FAILED")
//        }
//        
//    }
//    
//
//    
//    func updateExpityDownalodVideo(showID : String, videoID : String, downloadId : String, expiryDate : String, isDownload : String, complete:@escaping (_ isSave:Bool) -> ()){
//        
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<Download>(entityName: "Download")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "Download", in: objContext)!
//
//        let predicate0_1 = NSPredicate(format:"show_id == %@",showID)
//        let predicate0_2 = NSPredicate(format:"video_id == %@",videoID)
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2])
//        
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//      
//        
//        do{
//            var objCDDownloadShow:Download!
//            let results = try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [Download]
//            if(results.count != 0)
//            {
//                objCDDownloadShow = results[0] as Download
//                objCDDownloadShow.expiry_date = expiryDate
//                objCDDownloadShow.download_ID = downloadId
//                objCDDownloadShow.isDownload = isDownload
//
//                self.saveContext()
//                complete(true)
//            }
//            else{
//                complete(false)
//            }
//        }
//        catch
//        {
//            print("CHAT SYNCH FAILED")
//        }
//        
//    }
//    
//    
//    //    ======DELETE=====
//    
//    func deleteShows(strShowID:String, strProfileID:String,complete:(_ isDone:Bool) -> ()){
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<DownloadList>(entityName: "DownloadList")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "DownloadList", in: objContext)!
//     
//        let predicate0_1 = NSPredicate(format:"show_id == %@",strShowID)
//        let predicate0_2 = NSPredicate(format:"profile_id == %@",strProfileID)
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2])
//     
//        
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            let results = try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [DownloadList]
//            if(results.count != 0)
//            {
//                for result in results {
//                    objContext.delete(result)
//                }
//            }
//            self.saveContext()
//            complete(true)
//        }
//        catch
//        {
//            complete(false)
//        }
//    }
//    
//    
//    func deleteVideos(showID : String, videoID : String, strProfileID : String,complete:(_ isDone:Bool) -> ()){
//        //DELETE SUBTITL
//        if let objUser = UserDefaults.standard.user{
//            deleteSubTitle(strVideoID: videoID, strProfileID: strProfileID, strUserID: objUser.id ?? "") { isSave in
//            }
//        }
//
//        
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<Download>(entityName: "Download")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "Download", in: objContext)!
//
//        let predicate0_1 = NSPredicate(format:"show_id == %@",showID)
//        let predicate0_2 = NSPredicate(format:"video_id == %@",videoID)
//        let predicate0_3 = NSPredicate(format:"profile_id == %@",strProfileID)
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3])
//        
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            let results = try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [Download]
//            if(results.count != 0)
//            {
//                for result in results {
//                    objContext.delete(result)
//                }
//            }
//            self.saveContext()
//            complete(true)
//        }
//        catch
//        {
//            complete(false)
//        }
//    }
//    
//    
//    
//    
//    
//    
//    
//    
//    
//    
//    //====SAVE SUBTITLE DATABASE=====
//    func saveSubtitleList(objSaveData:SaveSubTitleParameater ,strProfileID : String, strUserID : String ,complete:@escaping (_ isSave:Bool) -> ()){
//       
//        
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<VideoSubtitle>(entityName: "VideoSubtitle")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "VideoSubtitle", in: objContext)!
//        let predicate0_1 = NSPredicate(format:"video_id == \(objSaveData.video_id)")
//        let predicate0_2 = NSPredicate(format:"profile_id == %@",strProfileID)
//        let predicate0_3 = NSPredicate(format:"userID == %@",strUserID)
//
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3])
//
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            var objCDDownload:VideoSubtitle!
//            objCDDownload = (NSEntityDescription.insertNewObject(forEntityName:"VideoSubtitle",into:managedObjectContext) as? VideoSubtitle)!
//            
//            objCDDownload.profile_id = strProfileID
//            objCDDownload.userID = strUserID
//            objCDDownload.lung = objSaveData.lung
//            objCDDownload.subTitleUrl = objSaveData.subTitleUrl
//            objCDDownload.video_id = objSaveData.video_id
//
//            self.saveContext()
//            complete(true)
//            
//            
//            let results = try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [VideoSubtitle]
//            if(results.count == 0)
//            {
//
//
//            }
//
//        }
//        catch
//        {
//            print("CHAT SYNCH FAILED")
//        }
//        
//    }
//    
//    func getSubtitleDataDData(strVideoID : String, strProfileID : String, strUserID : String) -> [VideoSubtitle]{
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<VideoSubtitle>(entityName: "VideoSubtitle")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "VideoSubtitle", in: objContext)!
//        
//        let predicate0_1 = NSPredicate(format:"video_id == %@",strVideoID)
//        let predicate0_2 = NSPredicate(format:"profile_id == %@",strProfileID)
//        let predicate0_3 = NSPredicate(format:"userID == %@",strUserID)
//
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3])
//        
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            
//            return try managedObjectContext.fetch(fetchRequest)
//
//        }
//        catch
//        {
//            return []
//        }
//    }
//    
//    func deleteSubTitle(strVideoID : String, strProfileID : String, strUserID : String,complete:(_ isDone:Bool) -> ()){
//
//        let objContext = self.managedObjectContext
//        let fetchRequest = NSFetchRequest<VideoSubtitle>(entityName: "VideoSubtitle")
//        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "VideoSubtitle", in: objContext)!
//     
//        let predicate0_1 = NSPredicate(format:"video_id == %@",strVideoID)
//        let predicate0_2 = NSPredicate(format:"profile_id == %@",strProfileID)
//        let predicate0_3 = NSPredicate(format:"userID == %@",strUserID)
//        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3])
//     
//        
//        fetchRequest.predicate = predicate1
//        fetchRequest.entity = disentity
//        
//        do{
//            let results = try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [VideoSubtitle]
//            if(results.count != 0)
//            {
//                for result in results {
//                    let strDownloadURL : NSString = ("\(subTitleDirectory)" as NSString).appendingPathComponent(result.subTitleUrl ?? "") as NSString
//                    try? FileManager.default.removeItem(atPath: "\(strDownloadURL)")
//
//                    objContext.delete(result)
//                }
//            }
//            self.saveContext()
//            complete(true)
//        }
//        catch
//        {
//            complete(false)
//        }
//    }
    
    

}




