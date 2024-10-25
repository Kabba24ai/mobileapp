//
//  CoreaDataModel.swift
//  SAMUH
//
//  Created by Jigar Khatri on 15/07/21.
//

import Foundation




struct SaveImageVideoParameater: Codable {
    var orderID: String
    var type : String
    var isImage: Bool
    var name: String
    
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
