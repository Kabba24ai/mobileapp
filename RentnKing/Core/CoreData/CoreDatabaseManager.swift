//
//  CoreDatabaseManager.swift
//  SAMUH
//
//  Created by Jigar Khatri on 13/07/21.
//

import Foundation
import CoreData
import ObjectMapper

enum uploadType: String {
    case image //license
    case video_image //delivery , pickup
    case hours
    case checkList
    case license
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
        case .license:
            return "license"
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
    func getAllUploadDATA(status : String = "Pending") -> [UploadData]{
        let objContext = self.managedObjectContext
        let fetchRequest = NSFetchRequest<UploadData>(entityName: "UploadData")
        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "UploadData", in: objContext)!
        
        let predicate0_1 = NSPredicate(format:"status == %@",status)
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

    
    func getUploadListData(strOrderID : String, productID: String = "", strType : String, image_side: String = "", strVideoType : String = "") -> [UploadData]{
        
        let objContext = self.managedObjectContext
        let fetchRequest = NSFetchRequest<UploadData>(entityName: "UploadData")
        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "UploadData", in: objContext)!
        
        let predicate0_1 = NSPredicate(format:"orderID == %@",strOrderID)
        let predicate0_2 = NSPredicate(format:"type == %@",strType)
        let predicate0_3 = NSPredicate(format:"videoType == %@",strVideoType)
        
        var predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3])
        
        if image_side != "" {
            let predicate0_4 = NSPredicate(format:"image_side == %@",image_side)
            predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3, predicate0_4])
        }
        
        fetchRequest.predicate = predicate1
        fetchRequest.entity = disentity
        
        do {
            return try managedObjectContext.fetch(fetchRequest)
        }
        catch {
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
        let predicate0_3 = NSPredicate(format:"productID == %@","\(objSaveData.productID)")
        let predicate0_4 = NSPredicate(format:"image_side == %@","\(objSaveData.image_side)")
        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3, predicate0_4])
        

        fetchRequest.predicate = predicate1
        fetchRequest.entity = disentity
        
        do{
            var objCDDownload:UploadData!
            objCDDownload = (NSEntityDescription.insertNewObject(forEntityName:"UploadData",into:managedObjectContext) as? UploadData)!
            
            objCDDownload.orderID = objSaveData.orderID
            objCDDownload.name = objSaveData.name
            objCDDownload.isImage = objSaveData.isImage
            objCDDownload.type = objSaveData.type
            objCDDownload.videoType = objSaveData.videoType
            objCDDownload.status = objSaveData.status
            objCDDownload.image_side = objSaveData.image_side

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
            
            objCDDownload.license_expiry_date = objSaveData.license_expiry_date
            objCDDownload.auto_inject_by = objSaveData.auto_inject_by

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
    
    //====UPDATE DATABASE STATUS====
    func updateLicenseUploadDataStatus(strOrderID: String, strType: String, image_side: String, newStatus: String, complete: @escaping (_ isUpdated: Bool) -> ()) {
        let objContext = self.managedObjectContext
        let fetchRequest: NSFetchRequest<UploadData> = UploadData.fetchRequest()
        
        let predicate0_1 = NSPredicate(format: "orderID == %@", strOrderID)
        let predicate0_2 = NSPredicate(format: "type == %@", strType)
        let predicate0_3 = NSPredicate(format: "image_side == %@", image_side)
        fetchRequest.predicate = NSCompoundPredicate(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3])
        
        do {
            let results = try objContext.fetch(fetchRequest)
            
            if results.isEmpty {
                complete(false) // nothing found to update
                return
            }
            
            for obj in results {
                obj.status = newStatus  // <-- update your status attribute here
            }
            
            try objContext.save()
            complete(true)
            
        } catch {
            print("Update failed:", error.localizedDescription)
            complete(false)
        }
    }
    
    func updateVideoImageUploadDataStatus(strOrderID: String, strType: String, strVideoType: String, newStatus: String, complete: @escaping (_ isUpdated: Bool) -> ()) {
        
        let objContext = self.managedObjectContext
        let fetchRequest = NSFetchRequest<UploadData>(entityName: "UploadData")
        let disentity: NSEntityDescription = NSEntityDescription.entity(forEntityName: "UploadData", in: objContext)!
        
        let predicate0_1 = NSPredicate(format:"orderID == %@",strOrderID)
        let predicate0_2 = NSPredicate(format:"type == %@",strType)
        let predicate0_3 = NSPredicate(format:"videoType == %@",strVideoType)
        let predicate1 = NSCompoundPredicate.init(type: .and, subpredicates: [predicate0_1, predicate0_2, predicate0_3])
        
        fetchRequest.predicate = predicate1
        fetchRequest.entity = disentity
        
        do{
            let results = try managedObjectContext.fetch(fetchRequest)
            if results.isEmpty {
                complete(false) // nothing found to update
                return
            }
            
            if results.isEmpty {
                complete(false) // nothing found to update
                return
            }
            
            for obj in results {
                obj.status = newStatus  // <-- update your status attribute here
            }
            
            try objContext.save()
            complete(true)
        }
        catch {
            print("Update failed:", error.localizedDescription)
            complete(false)
        }
    }
    
    
    
    //MARK: - FOR CATEGORY
    func saveCategoryListArray(arrCategories: [CategoryModel], context: NSManagedObjectContext, completion: @escaping (Bool) -> Void) {
        for category in arrCategories {
            _ = saveCategory(objCategory: category, context: context)
        }
        do {
            try context.save()
            print("✅ Categories saved successfully")
            completion(true)
        } catch {
            print("❌ Failed to save categories: \(error)")
            completion(true)
        }
    }
    
    func saveCategory(objCategory: CategoryModel, parent: CategoryList? = nil, context: NSManagedObjectContext) -> CategoryList {
        
        let fetchRequest: NSFetchRequest<CategoryList> = CategoryList.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "uniqueId == %@", objCategory.unique_id ?? "")
        
        let entity: CategoryList
        if let existing = try? context.fetch(fetchRequest).first {
            entity = existing
        } else {
            entity = CategoryList(context: context)
        }
        
        // Map values
        entity.id = Int64(objCategory.id ?? 0)
        entity.uniqueId = objCategory.unique_id ?? ""
        entity.name = objCategory.name
        entity.image = objCategory.image
        entity.parent = parent
        
        // 🔹 Handle children recursively
//            if !objCategory.arrChildCategories.isEmpty {
//                for childModel in objCategory.arrChildCategories {
//                    let childEntity = saveCategory(objCategory: childModel, parent: entity, context: context)
//                    entity.addToChildren(childEntity) // <-- Core Data helper
//                }
//            }
        
        saveChildCategories(objCategory.arrChildCategories, parent: entity, context: context)

            
        
        return entity
    }
    
    func saveChildCategories(_ children: [CategoryModel],
                             parent: CategoryList,
                             context: NSManagedObjectContext) {
        guard !children.isEmpty else { return }
        
        for childModel in children {
            let childEntity = saveCategory(objCategory: childModel, parent: parent, context: context)
            parent.addToChildren(childEntity) // Core Data auto-generated method
        }
    }
    
    func loadCategoriesFromCoreData(context: NSManagedObjectContext) -> [CategoryModel] {
        let fetchRequest: NSFetchRequest<CategoryList> = CategoryList.fetchRequest()
        
        do {
            var categories = try context.fetch(fetchRequest)
            categories = categories.sorted(by: { $0.name ?? "" < $1.name ?? "" })

            // Map to CategoryModel
            let arrCategoryModels = categories.map { categoryEntity -> CategoryModel in
                let map = Map(mappingType: .fromJSON, JSON: [:])
                var model = CategoryModel(map: map)!
                model.id = Int(categoryEntity.id)
                model.name = categoryEntity.name
                model.unique_id = categoryEntity.uniqueId ?? "0"
                model.image = categoryEntity.image
                
                // Map child categories recursively if needed
//                if let children = categoryEntity.children as? Set<CategoryList> {
//                    let _ = children.map { childEntity -> CategoryModel in
//                        let map = Map(mappingType: .fromJSON, JSON: [:])
//                        var childModel = CategoryModel(map: map)!
//                        childModel.id = Int(childEntity.id)
//                        childModel.name = "--\(childEntity.name ?? "")"
//                        childModel.unique_id = Int(childEntity.uniqueId ?? "0") ?? 0
//                        childModel.image = childEntity.image
//                        
//                        model.arrChildCategories.append(childModel)
//                        return childModel
//                    }
//                }
                
                return model
            }
            
            return arrCategoryModels
            
        } catch {
            print("Failed to fetch: \(error)")
            return []
        }
    }
    
    
}




