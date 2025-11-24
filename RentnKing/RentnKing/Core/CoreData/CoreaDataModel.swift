//
//  CoreaDataModel.swift
//  SAMUH
//
//  Created by Jigar Khatri on 15/07/21.
//

import Foundation
import CoreData




struct SaveImageVideoParameater: Codable {
    var orderID: String
    var type : String
    //var productOrderID: String
    var isImage: Bool
    var name: String
    
    var status: String = "Pending"
    var videoType: String = ""
    var allocated: String = ""
    var end: String = ""
    var over: String = ""
    var over_rate: String = ""
    var productID: String = ""
    var start : String = ""
    var total : String = ""
    var total_cost : String = ""
    
    var qustion_id : String = ""
    var checklist_delivered : String = ""
    var checklist_returned : String = ""
    var checklist_Value : String = ""

}



//public class CategoryListEntity: NSManagedObject {}
//
//extension CategoryListEntity {
//    @nonobjc public class func fetchRequest() -> NSFetchRequest<CategoryListEntity> {
//        return NSFetchRequest<CategoryListEntity>(entityName: "CategoryEntity")
//    }
//
//    @NSManaged public var id: Int64
//    @NSManaged public var uniqueId: String?
//    @NSManaged public var name: String?
//    @NSManaged public var image: String?
//    @NSManaged public var parent: CategoryListEntity?
//    @NSManaged public var children: NSSet?
//}
