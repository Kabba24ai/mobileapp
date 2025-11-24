//
//  UpdateOrderNoteData.swift
//  RentnKing
//
//  Created by DEEPAK JAIN on 15/10/25.
//

import UIKit
import Alamofire

func syncOrderNoteWithAPI() {
    let storageKey = "\(kFileStorageName.kOrderNoteData.rawValue)"
    let arrNoteData: [OrderNoteModel] = SDKUserDefault.getMappableArray(OrderNoteModel.self, for: storageKey) ?? []
    if arrNoteData.count != 0 {
        if NetworkReachabilityManager()!.isReachable {
            let firstData = arrNoteData[0]
            if firstData.status == kOrderStatusType.kPending.rawValue {
                let strType = firstData.type ?? ""
                if strType == kOrderStatusType.kAdd.rawValue {
                    //Add Note
                    callAPIforAddNote(dic_note: firstData)
                }
                else if strType == kOrderStatusType.kEdit.rawValue {
                    //Edit Note
                    callAPIforUpdateNote(dic_note: firstData)
                }
                else if strType == kOrderStatusType.kDelete.rawValue {
                    //Delete Note
                    callAPIforDeleteNote(dic_note: firstData)
                }
            }
        }
    }
}

func callAPIforAddNote(dic_note: OrderNoteModel) {
    let strNote = dic_note.note ?? ""
    let strUniqueID = dic_note.unique_id ?? ""
    let strCreatedByID = "\(dic_note.created_by_id ?? 0)"
    addNote(AddNoteParameater: AddNoteParameater(order_unique_id: strUniqueID, note: strNote, user_id: strCreatedByID), note_id: dic_note.id ?? 0) { is_success in
        syncOrderNoteWithAPI()
    }
}

func callAPIforUpdateNote(dic_note: OrderNoteModel) {
    let strNote = dic_note.note ?? ""
    let strUniqueID = dic_note.unique_id ?? ""
    let strCreatedByID = "\(dic_note.created_by_id ?? 0)"
    updateNote(UpdateNoteParameater: UpdateNoteParameater(order_note_unique_id: strUniqueID, note: strNote, user_id: strCreatedByID), note_id: dic_note.id ?? 0) { is_success in
        syncOrderNoteWithAPI()
    }
}

func callAPIforDeleteNote(dic_note: OrderNoteModel) {
    let strUniqueID = dic_note.unique_id ?? ""
    deleteNote(struniqueID: strUniqueID, note_id: dic_note.id ?? 0) { is_success in
        syncOrderNoteWithAPI()
    }
}

func addNote(AddNoteParameater:AddNoteParameater, note_id: Int, completion: @escaping (Bool) -> Void) {
   
    guard let parameater = try? AddNoteParameater.asDictionary() else {
        showAlertMessage(strMessage: str.invalidRequestParamater)
        return
    }

    //Declaration URL
    let strURL = "\(Url.addOrderNote.absoluteString!)"
    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = parameater
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { dic, arr, success, err in
        handleResponse(data: dic, note_id: note_id) { is_success in
            completion(is_success)
        }
    }
}

func updateNote(UpdateNoteParameater: UpdateNoteParameater, note_id: Int, completion: @escaping (Bool) -> Void) {
   
    guard let parameater = try? UpdateNoteParameater.asDictionary() else {
        showAlertMessage(strMessage: str.invalidRequestParamater)
        return
    }

    //Declaration URL
    let strURL = "\(Url.updateOrderNote.absoluteString!)"
    
    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = parameater
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { dic, arr, success, err in
        handleResponse(data: dic, note_id: note_id) { is_success in
            completion(is_success)
        }
    }
}

func deleteNote(struniqueID: String, note_id: Int, completion: @escaping (Bool) -> Void) {
    
    let params = ["order_note_unique_id": struniqueID]

    //Declaration URL
    let strURL = "\(Url.deleteNote.absoluteString!)"

    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = params
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { dic, arr, success, err in
        handleResponse(data: dic, note_id: note_id) { is_success in
            completion(is_success)
        }
    }
}

func handleResponse(data: NSDictionary?, note_id: Int, completion: @escaping (Bool) -> Void) {
    if data?.getStringForID(key: "success") == "1"{
        print(data!)
        indicatorHide()
        let storageKey = "\(kFileStorageName.kOrderNoteData.rawValue)"
        var arrNoteData: [OrderNoteModel] = SDKUserDefault.getMappableArray(OrderNoteModel.self, for: storageKey) ?? []
        
        if note_id != 0 {
            // Remove note from array if it exists
            if let index = arrNoteData.firstIndex(where: { $0.id == note_id }) {
                arrNoteData.remove(at: index)
                
                // Save updated array back
                SDKUserDefault.saveMappableArray(arrNoteData, for: storageKey)
                completion(true)
            }
        }
        else {
            completion(true)
        }
        
    }
    else {
        print(data!)
        debugPrint("Getting Error")
        if note_id == 0 {
            if data?.getStringForID(key: "message") != ""{
                showAlertMessage(strMessage: data!.getStringForID(key: "message"))
            }
            else{
                showAlertMessage(strMessage: "\(str.somethingWentWrong)")
            }
        }
    }
}
