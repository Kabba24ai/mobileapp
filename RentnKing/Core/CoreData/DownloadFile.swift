//
//  DownloadFile.swift
//  SAMUH
//
//  Created by Jigar Khatri on 01/07/22.
//

import Foundation

/// Keeps large media folders out of iCloud/device backups.
func excludeFromICloudBackup(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    var mutableURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? mutableURL.setResourceValues(values)
}

func createLicenseUploadFolder() {
   do {
      if FileManager.default.fileExists(atPath: LicenseUploadDirectory.path) == false {
          try FileManager.default.createDirectory(at: LicenseUploadDirectory, withIntermediateDirectories: false, attributes: nil)
      }

   } catch {
      print(error);
   }
   excludeFromICloudBackup(LicenseUploadDirectory)
}

func createImageVideoUploadFolder() {
    let folderPath = ImageVideoUploadDirectory.path
    
    if FileManager.default.fileExists(atPath: folderPath) {
        print("📂 Folder already exists: \(folderPath)")
    } else {
        do {
            try FileManager.default.createDirectory(
                at: ImageVideoUploadDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            print("✅ Folder created at: \(folderPath)")
        } catch {
            print("❌ Failed to create folder: \(error.localizedDescription)")
        }
    }
    excludeFromICloudBackup(ImageVideoUploadDirectory)
}


func createOrderFolder(strOrderID: String) {
    let orderFolderPath = ImageVideoUploadDirectory.appendingPathComponent(strOrderID)
    
    if !FileManager.default.fileExists(atPath: orderFolderPath.path) {
        do {
            try FileManager.default.createDirectory(
                at: orderFolderPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
            print("✅ Created folder: \(orderFolderPath.path)")
        } catch {
            print("❌ Failed to create folder: \(error.localizedDescription)")
        }
    } else {
        print("📂 Folder already exists: \(orderFolderPath.path)")
    }
}


func createFileStorageFolder() {
    let folderPath = FileStorageDirectory.path
    
    if FileManager.default.fileExists(atPath: folderPath) {
        print("📂 Folder already exists: \(folderPath)")
    } else {
        do {
            try FileManager.default.createDirectory(
                at: FileStorageDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            print("✅ Folder created at: \(folderPath)")
        } catch {
            print("❌ Failed to create folder: \(error.localizedDescription)")
        }
    }
    excludeFromICloudBackup(FileStorageDirectory)
}



var LicenseUploadDirectory: URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
   let documentsDirectory = paths[0]
   return documentsDirectory.appendingPathComponent("LicenseUpload")
}

var ImageVideoUploadDirectory: URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
   let documentsDirectory = paths[0]
   return documentsDirectory.appendingPathComponent("ImageVideo")
}

var FileStorageDirectory: URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
   let documentsDirectory = paths[0]
   return documentsDirectory.appendingPathComponent("FileStorage")
}




func saveToFile(data: Data, fileName: String) {
    let dataPath = FileStorageDirectory.appendingPathComponent(fileName)
    do {
        try data.write(to: dataPath, options: .atomic)
        print("Saved at: \(dataPath)")
    } catch {
        print("Error saving: \(error)")
    }
}

func readFromFile(fileName: String) -> Data? {
    let fileURL = FileStorageDirectory.appendingPathComponent(fileName)
    return try? Data(contentsOf: fileURL)
}


// MARK: - Media cleanup (prevents unbounded Documents growth)

/// Deletes already-uploaded photos/videos from the app's Documents folder so
/// storage doesn't grow forever. Files that still have a *Pending* upload record
/// are always kept, so nothing un-sent is ever lost.
///
/// Call on the main thread (Core Data's viewContext is main-thread bound); the
/// heavy file I/O is moved to a background queue automatically.
final class MediaCleanupManager {

    static let shared = MediaCleanupManager()
    private init() {}

    /// - Parameter graceDays: uploaded files are kept this many days before being
    ///   deleted (0 = delete as soon as they're uploaded).
//    func purgeUploadedMedia(graceDays: Int = 7) {
//
//        // 1) Snapshot the still-Pending files on the current (main) thread.
//        let pending = CoreDBManager.sharedDatabase.getAllUploadDATA(status: "Pending")
//        var pendingKeys = Set<String>()
//        for item in pending {
//            let name = item.name ?? ""
//            guard !name.isEmpty else { continue }
//            pendingKeys.insert("\(item.orderID ?? "")/\(name)")   // ImageVideo/<order>/<file>
//            pendingKeys.insert(name)                               // LicenseUpload/<file>
//        }
//
//        let cutoff = Date().addingTimeInterval(-Double(graceDays) * 86_400)
//
//        // 2) Do the file I/O off the main thread.
//        DispatchQueue.global(qos: .utility).async {
//            let fm = FileManager.default
//
//            self.sweep(ImageVideoUploadDirectory, fm: fm, cutoff: cutoff) { url in
//                let folder = url.deletingLastPathComponent().lastPathComponent
//                return pendingKeys.contains("\(folder)/\(url.lastPathComponent)")
//            }
//            self.sweep(LicenseUploadDirectory, fm: fm, cutoff: cutoff) { url in
//                pendingKeys.contains(url.lastPathComponent)
//            }
//            self.removeEmptyFolders(in: ImageVideoUploadDirectory, fm: fm)
//        }
//    }

    /// Immediately reclaims a single order's local media once that order is fully done
    /// (delivery + return). Deletes NOTHING if any file for the order is still Pending
    /// upload — so nothing un-sent is ever lost. Call on the main thread (Core Data's
    /// viewContext is main-bound); the file I/O is moved off the main thread.
    func purgeMedia(forOrder orderId: String) {
        guard !orderId.isEmpty else { return }

        // 1) Safety gate: never delete while anything for this order is still uploading.
        let stillPending = CoreDBManager.sharedDatabase.getAllUploadDATA(status: "Pending")
            .contains { ($0.orderID ?? "") == orderId }
        guard !stillPending else {
            print("MediaCleanup: order \(orderId) still has pending uploads — keeping media")
            return
        }

        // 2) Clear this order's Core Data upload rows (photos/videos + license).
        CoreDBManager.sharedDatabase.deleteUploadData(strOrderID: orderId, strType: uploadType.video_image.rawValue) { _ in }
        CoreDBManager.sharedDatabase.deleteUploadData(strOrderID: orderId, strType: uploadType.image.rawValue) { _ in }

        // 3) Delete the files off the main thread.
        let imageVideoFolder = ImageVideoUploadDirectory.appendingPathComponent(orderId)
        let licenseDir = LicenseUploadDirectory
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            try? fm.removeItem(at: imageVideoFolder)                       // ImageVideo/<order>/
            // LicenseUpload/<order>_front.png, <order>_back.png, …
            if let files = try? fm.contentsOfDirectory(at: licenseDir, includingPropertiesForKeys: nil) {
                for url in files where url.lastPathComponent.hasPrefix("\(orderId)_") {
                    try? fm.removeItem(at: url)
                }
            }
            print("MediaCleanup: reclaimed local media for completed order \(orderId)")
        }
    }

    /// Deletes regular files older than `cutoff`, unless `isPending` says to keep them.
    private func sweep(_ dir: URL, fm: FileManager, cutoff: Date, isPending: (URL) -> Bool) {
        guard fm.fileExists(atPath: dir.path) else { return }
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: keys) else { return }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            if isPending(url) { continue }                         // keep un-sent files
            let modified = values?.contentModificationDate ?? .distantPast
            if modified < cutoff {                                 // uploaded AND older than grace
                try? fm.removeItem(at: url)
            }
        }
    }

    /// Removes now-empty order sub-folders.
    private func removeEmptyFolders(in dir: URL, fm: FileManager) {
        guard let subs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for folder in subs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
                try? fm.removeItem(at: folder)
            }
        }
    }
}
 
