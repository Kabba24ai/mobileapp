//
//  CoreDatabaseManager.swift
//  SAMUH
//
//  Created by Jigar Khatri on 13/07/21.
//

import Foundation
import CoreData

enum uploadType: String {
    case image
    case video_image
    case hours
    case checkList
}

extension uploadType {
    var rawValue: String {
        switch self {
        case .image:
            return "image"
            
        case .video_image:
            return "video_image"
            
        case .hours:
            return "hours"

        case .checkList:
            return "checkList"
        }
    }
}




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

    
    func getUploadListData(strOrderID : String, strType : String) -> [UploadData]{
        
        let objContext = self.managedObjectContext
        let fetchRequest = NSFetchRequest<UploadData>(entityName: "UploadData")
        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "UploadData", in: objContext)!
        
        let predicate0_1 = NSPredicate(format:"orderID == %@",strOrderID)
        let predicate0_2 = NSPredicate(format:"type == %@",strType)
        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2])
        
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
    

    
    //====SAVE DATABASE=====
    func saveUploadDataList(objSaveData:SaveImageVideoParameater ,complete:@escaping (_ isSave:Bool) -> ()){

        
        let objContext = self.managedObjectContext
        let fetchRequest = NSFetchRequest<UploadData>(entityName: "UploadData")
        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "UploadData", in: objContext)!
        let predicate0_1 = NSPredicate(format:"orderID == %@","\(objSaveData.orderID)")
        let predicate0_2 = NSPredicate(format:"type == %@","\(objSaveData.type)")
        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2])
        

        fetchRequest.predicate = predicate1
        fetchRequest.entity = disentity
        
        do{
            var objCDDownload:UploadData!
            objCDDownload = (NSEntityDescription.insertNewObject(forEntityName:"UploadData",into:managedObjectContext) as? UploadData)!
            
            objCDDownload.orderID = objSaveData.orderID
            objCDDownload.name = objSaveData.name
            objCDDownload.isImage = objSaveData.isImage
            objCDDownload.type = objSaveData.type
            
            objCDDownload.allocated = objSaveData.allocated
            objCDDownload.end = objSaveData.end
            objCDDownload.over = objSaveData.over
            objCDDownload.over_rate = objSaveData.over_rate
            objCDDownload.productID = objSaveData.productID
            objCDDownload.start = objSaveData.start
            objCDDownload.total = objSaveData.total
            objCDDownload.total_cost = objSaveData.total_cost
            
            objCDDownload.qustion_id = objSaveData.qustion_id
            objCDDownload.checklist_delivered = objSaveData.checklist_delivered
            objCDDownload.checklist_returned = objSaveData.checklist_returned
            objCDDownload.checklist_Value = objSaveData.checklist_Value

            self.saveContext()
            complete(true)
        }
        
    }


   
    
    //====DELETE DATABASE ===
    func deleteUploadData(strOrderID : String, strType : String, complete:@escaping (_ isSave:Bool) -> ()){
        
        let objContext = self.managedObjectContext
        let fetchRequest = NSFetchRequest<UploadData>(entityName: "UploadData")
        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "UploadData", in: objContext)!

        let predicate0_1 = NSPredicate(format:"orderID == %@","\(strOrderID)")
        let predicate0_2 = NSPredicate(format:"type == %@","\(strType)")
        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2])
        
        fetchRequest.predicate = predicate1
        fetchRequest.entity = disentity
      
        
        do{
            let results = try  managedObjectContext.fetch(fetchRequest as! NSFetchRequest<NSFetchRequestResult>) as! [UploadData]
          
            for obj in results{
                managedObjectContext.delete(obj)
            }
            
            self.saveContext()
            complete(true)

        }
        catch
        {
            print("CHAT SYNCH FAILED")
        }
    }
}




