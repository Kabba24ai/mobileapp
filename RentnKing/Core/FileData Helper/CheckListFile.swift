//
//  CheckListFile.swift
//  RentnKing
//
//  Created by Jigar Khatri on 05/12/25.
//

import Foundation
import UIKit
import ObjectMapper


// MARK: - Pending (prepared) Delivery Checklist  — LOCAL ONLY
//
// Lets an employee prepare & save a Delivery checklist before the customer arrives, WITHOUT
// completing it. Stored under dedicated keys so it can never be mistaken for a completed
// checklist (which is marked by `kCheckListOrderDetailsData_<type>_<uid>`) and never enters the
// final-upload queue (`kSaveCheckList`). No backend contract is involved.

private func pendingCheckListType(_ isDelivery: Bool) -> String { isDelivery ? "Delivery" : "Return" }

private func pendingOrderKey(_ uid: String, _ isDelivery: Bool) -> String {
    "\(kFileStorageName.kPendingCheckList.rawValue)_\(pendingCheckListType(isDelivery))_\(uid)"
}
private func pendingOtherKey(_ uid: String, _ isDelivery: Bool) -> String {
    "\(kFileStorageName.kPendingCheckListOther.rawValue)_\(pendingCheckListType(isDelivery))_\(uid)"
}

/// Saves the current checklist form as a PENDING/prepared draft. Returns false (and saves
/// nothing) if the inputs are missing, so callers can avoid navigating forward on failure.
@discardableResult
func savePendingCheckList(orderUniqueId: String, isDelivery: Bool, objOrderData: OrdersModel?, arrOtherData: [NoteModel]) -> Bool {
    guard !orderUniqueId.isEmpty, let objOrderData = objOrderData else { return false }
    SDKUserDefault.saveMappableObject(objOrderData, for: pendingOrderKey(orderUniqueId, isDelivery))
    SDKUserDefault.saveNSObjectArray(arrOtherData, key: pendingOtherKey(orderUniqueId, isDelivery))
    return true
}

/// Loads a previously saved PENDING checklist (order data + per-product "other" data), or nil.
func getPendingCheckList(orderUniqueId: String, isDelivery: Bool) -> (order: OrdersModel, other: [NoteModel])? {
    guard !orderUniqueId.isEmpty,
          let order = SDKUserDefault.getMappableObject(OrdersModel.self, for: pendingOrderKey(orderUniqueId, isDelivery)) else {
        return nil
    }
    let other = SDKUserDefault.getNSObjectArray(key: pendingOtherKey(orderUniqueId, isDelivery))
    return (order, other)
}

func hasPendingCheckList(orderUniqueId: String, isDelivery: Bool) -> Bool {
    guard !orderUniqueId.isEmpty else { return false }
    return SDKUserDefault.getMappableObject(OrdersModel.self, for: pendingOrderKey(orderUniqueId, isDelivery)) != nil
}

/// Clears the PENDING draft. Called when the checklist is finally submitted (pending → completed)
/// so a completed checklist never reloads as pending.
func clearPendingCheckList(orderUniqueId: String, isDelivery: Bool) {
    guard !orderUniqueId.isEmpty else { return }
    SDKUserDefault.remove(for: pendingOrderKey(orderUniqueId, isDelivery))
    SDKUserDefault.remove(for: pendingOtherKey(orderUniqueId, isDelivery))
}



// MARK: - Phase 3: migrate the legacy customer-checklist queue into the Sync Engine
//
// The pre-Phase-3 queue (`kSaveCheckList`) retried five times and then DELETED the employee's
// signed checklist. Every item still in it is converted into a durable
// `legacy_customer_checklist.submit` operation (payload verbatim, signature → protected asset)
// and the queue is cleared. Items that cannot be converted are moved to a quarantine key —
// never deleted — and surfaced in the Sync Status screen's log.
let kLegacyChecklistQuarantineKey = kFileStorageName.kSaveCheckList.rawValue + "_quarantine"

func migrateLegacyCustomerChecklistQueueIntoSyncEngine() {
    guard let engine = KabbaSync.engine else { return }
    guard let jsonData = SDKUserDefault.getData(for: kFileStorageName.kSaveCheckList.rawValue),
          let items = (try? JSONSerialization.jsonObject(with: jsonData)) as? [[String: Any]], !items.isEmpty else { return }

    var quarantined: [[String: Any]] = []
    var migrated = 0
    for item in items {
        switch LegacyChecklistQueueMigration.convert(item) {
        case .success(let converted):
            do {
                _ = try LegacyChecklistQueueMigration.enqueue(converted, into: engine)
                migrated += 1
            } catch {
                quarantined.append(item)
            }
        case .failure:
            quarantined.append(item)
        }
    }

    if !quarantined.isEmpty, JSONSerialization.isValidJSONObject(quarantined),
       let data = try? JSONSerialization.data(withJSONObject: quarantined) {
        var existing: [[String: Any]] = []
        if let old = SDKUserDefault.getData(for: kLegacyChecklistQuarantineKey),
           let parsed = (try? JSONSerialization.jsonObject(with: old)) as? [[String: Any]] { existing = parsed }
        if let merged = try? JSONSerialization.data(withJSONObject: existing + quarantined) {
            SDKUserDefault.save(merged, for: kLegacyChecklistQuarantineKey)
        } else {
            SDKUserDefault.save(data, for: kLegacyChecklistQuarantineKey)
        }
    }

    SDKUserDefault.remove(for: kFileStorageName.kSaveCheckList.rawValue)
    debugPrint("Customer checklist queue: migrated \(migrated) item(s) into the Sync Engine, quarantined \(quarantined.count)")
}

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


/// Appends new checklist submissions to the EXISTING local queue instead of
/// overwriting it, so back-to-back / concurrent submissions are never lost while
/// an earlier upload is still in flight. Then persists and triggers the uploader.
func appendChecklistData(_ newItems: [[String: Any]]) {
    var queue = getChecklistData() ?? []
    queue.append(contentsOf: newItems)
    saveArrayWithImages(queue)
}


func saveArrayWithImages(_ array: [[String: Any]], triggerUpload: Bool = true) {
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

        // triggerUpload:false is used when we only need to persist the queue (e.g. bumping a
        // rejected item's attempt counter) without kicking off an immediate re-upload of arr[0].
        if triggerUpload {
            GlobalMainConstants.appDelegate?.updateCheckListData()
        }

        print("✅ Saved array in MMKV")
    } catch {
        print("❌ JSON encode error:", error)
    }
}
