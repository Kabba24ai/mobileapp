//
//  CheckListFile.swift
//  RentnKing
//
//  Created by Jigar Khatri on 05/12/25.
//

import Foundation
import UIKit



// MARK: - Get Checklist
func getChecklistData() -> [[String: Any]]? {
    guard let jsonData = SDKUserDefault.getData(for: kFileStorageName.kSaveCheckList.rawValue) else { return nil }

    do {
        guard var array = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return nil
        }

        for i in 0..<array.count {

            // Restore rSignature
            if let base64 = array[i]["rSignature"] as? String,
               let data = Data(base64Encoded: base64),
               let image = UIImage(data: data) {
                array[i]["rSignature"] = image
            }

            // Restore dSignature
            if let base64 = array[i]["dSignature"] as? String,
               let data = Data(base64Encoded: base64),
               let image = UIImage(data: data) {
                array[i]["dSignature"] = image
            }
        }

        return array
    } catch {
        print("❌ JSON decode error:", error)
        return nil
    }
}


func saveArrayWithImages(_ array: [[String: Any]]) {
    var safeArray = [[String: Any]]()

    for var dict in array {

        // Convert rSignature UIImage to base64
        if let img = dict["rSignature"] as? UIImage,
           let data = img.jpegData(compressionQuality: 0.7) {
            dict["rSignature"] = data.base64EncodedString()
        } else {
            dict["rSignature"] = ""   // or NSNull()
        }

        // Convert dSignature UIImage to base64
        if let img = dict["dSignature"] as? UIImage,
           let data = img.jpegData(compressionQuality: 0.7) {
            dict["dSignature"] = data.base64EncodedString()
        } else {
            dict["dSignature"] = ""   // or NSNull()
        }

        safeArray.append(dict)
    }

    guard JSONSerialization.isValidJSONObject(safeArray) else {
        print("❌ Not valid JSON - check values")
        return
    }

    do {
        let jsonData = try JSONSerialization.data(withJSONObject: safeArray, options: [])
        SDKUserDefault.save(jsonData, for: kFileStorageName.kSaveCheckList.rawValue)
        
        GlobalMainConstants.appDelegate?.updateCheckListData()

        print("✅ Saved array in MMKV")
    } catch {
        print("❌ JSON encode error:", error)
    }
}
