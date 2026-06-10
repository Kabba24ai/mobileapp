//
//  DownloadFile.swift
//  SAMUH
//
//  Created by Jigar Khatri on 01/07/22.
//

import Foundation

func createLicenseUploadFolder() {
   do {
      if FileManager.default.fileExists(atPath: LicenseUploadDirectory.path) == false {
          try FileManager.default.createDirectory(at: LicenseUploadDirectory, withIntermediateDirectories: false, attributes: nil)
      }
      
   } catch {
      print(error);
   }
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
 


//class FileDownloader {
// 
//    static func loadFileAsync(url: URL, completion: @escaping (String?, Error?) -> Void)
//    {
//
//        let destinationUrl =  subTitleDirectory.appendingPathComponent("\(url.lastPathComponent)")
//        
////        if FileManager().fileExists(atPath: destinationUrl.path)
////        {
////            print("File already exists [\(destinationUrl.path)]")
////            completion(destinationUrl.path, nil)
////        }
////        else
////        {
////        }
//        
//        
//        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: nil, delegateQueue: nil)
//        var request = URLRequest(url: url)
//        request.httpMethod = "GET"
//        let task = session.dataTask(with: request, completionHandler:
//        {
//            data, response, error in
//            if error == nil
//            {
//                if let response = response as? HTTPURLResponse
//                {
//                    if response.statusCode == 200
//                    {
//                        if let data = data
//                        {
//                            if let _ = try? data.write(to: destinationUrl, options: Data.WritingOptions.atomic)
//                            {
//                                completion(destinationUrl.lastPathComponent, error)
//                            }
//                            else
//                            {
//                                completion(destinationUrl.lastPathComponent, error)
//                            }
//                        }
//                        else
//                        {
//                            completion(destinationUrl.lastPathComponent, error)
//                        }
//                    }
//                }
//            }
//            else
//            {
//                completion(destinationUrl.path, error)
//            }
//        })
//        task.resume()
//
//    }
//}
