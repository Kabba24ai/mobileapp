//
//  CheckListFile.swift
//  RentnKing
//
//  Created by Jigar Khatri on 05/12/25.
//



// MARK: - Get Checklist
func getSaveCheckList(completion: @escaping ([CategoryModel]) -> Void) {
    if !getCatData().isEmpty {
        completion(getCatData())
    } else {
        //CALL API
        
    }
}


func getChecklistData() -> [[String : Any]] {
    var arrChecklist : [[String : Any]] = []

    //GET DATA FROM MKV
//    if let arr_data = SDKUserDefault.get
//    if let arr_data = SDKUserDefault.getMappableArray([String : Any], for: kFileStorageName.kSaveCheckList.rawValue) {
//        arrChecklist = arr_data
//    }

    return arrChecklist
}


