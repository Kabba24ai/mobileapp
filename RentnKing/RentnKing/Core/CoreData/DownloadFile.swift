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

var LicenseUploadDirectory: URL {
   let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
   let documentsDirectory = paths[0]
   return documentsDirectory.appendingPathComponent("LicenseUpload")
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
