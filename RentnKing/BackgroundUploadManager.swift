//
//  BackgroundUploadManager.swift
//  RentnKing
//
//  Created by Jigar Khatri on 18/08/25.
//


import Foundation
import UniformTypeIdentifiers

import Foundation
import UIKit
import UniformTypeIdentifiers




// MARK: - Notifications your UI can observe
extension Notification.Name {
    static let bgUploadProgress = Notification.Name("bgUploadProgress")          // userInfo: ["id": String, "progress": Double]
    static let bgUploadFinished = Notification.Name("bgUploadFinished")          // userInfo: ["id": String, "status": Int, "data": Data]
    static let bgUploadFailed   = Notification.Name("bgUploadFailed")            // userInfo: ["id": String, "error": Error]
}

// MARK: - Model persisted for restore
struct UploadRecord: Codable {
    let id: String
    let endpoint: URL
    let filePath: String
    let mimeType: String
    let fieldName: String
    let fileName: String
    let extraParams: [String: String]
}

// MARK: - BackgroundUploader
final class BackgroundUploader: NSObject {
    static let shared = BackgroundUploader()

    // Stable identifier so iOS can relaunch your app to deliver events
    private let sessionIdentifier = "com.yourapp.background.uploads"

    // iOS gives this to AppDelegate; we call it when all events are delivered
    private var backgroundCompletionHandler: (() -> Void)?

    // Map taskIdentifier -> completion so callers in the current run receive results
    private var completions: [Int: (Result<(HTTPURLResponse, Data), Error>) -> Void] = [:]

    // Buffer response bodies per taskIdentifier
    private var buffers: [Int: Data] = [:]

    // Persist/restore the set of pending uploads across launches
    private let pendingKey = "bg.pending.uploads"

    // Background URLSession (NOT Alamofire)
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false
        cfg.allowsExpensiveNetworkAccess = true     // allow cellular
        cfg.allowsConstrainedNetworkAccess = true   // allow Low Data Mode
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    // Called by AppDelegate when the system wakes your app for background events
    func setSystemCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundCompletionHandler = handler
    }

    // MARK: - Public API

    /// Start a multipart/form-data upload in the background. Completion is called when the server response arrives.
    /// - Important: For background sessions, the upload body **must** come from a FILE, not in-memory Data.
    @discardableResult
    func uploadMultipart(fileURL: URL,
                         fieldName: String = "file",
                         fileName: String? = nil,
                         mimeType: String,
                         to endpoint: URL,
                         method: String = "POST",
                         params: [String: String] = [:],
                         headers: [String: String] = [:],
                         completion: @escaping (Result<(HTTPURLResponse, Data), Error>) -> Void) throws -> URLSessionUploadTask {

        // Build multipart body to a temp file (so background session can stream it)
        let (bodyFileURL, boundary) = try MultipartBuilder.fileBackedBody(
            fileURL: fileURL,
            fieldName: fieldName,
            fileName: fileName ?? fileURL.lastPathComponent,
            mimeType: mimeType,
            params: params
        )

        var req = URLRequest(url: endpoint)
        req.httpMethod = method
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

        // Each upload gets a stable ID that we also store in taskDescription
        let id = UUID().uuidString

        // Create the background uploadTask FROM FILE
        let task = session.uploadTask(with: req, fromFile: bodyFileURL)
        task.taskDescription = id

        // Remember completion for this process run
        completions[task.taskIdentifier] = { [weak self] result in
            // Clean temp file and state
            try? FileManager.default.removeItem(at: bodyFileURL)
            self?.completions[task.taskIdentifier] = nil
            self?.removePending(id: id)
            completion(result)
        }

        // Persist so we can restore after relaunch
        let rec = UploadRecord(id: id, endpoint: endpoint, filePath: fileURL.path, mimeType: mimeType, fieldName: fieldName, fileName: fileName ?? fileURL.lastPathComponent, extraParams: params)
        persistPending(rec)

        // Foreground progress (no events while suspended)
        observeProgress(for: task)

        task.resume()
        return task
    }

    
    public struct FilePart {
        public let fileURL: URL
        public let fieldName: String
        public let fileName: String
        public let mimeType: String

        public init(fileURL: URL, fieldName: String, fileName: String, mimeType: String) {
            self.fileURL = fileURL
            self.fieldName = fieldName
            self.fileName = fileName
            self.mimeType = mimeType
        }
    }

    @discardableResult
    func uploadMultipartMany(parts: [FilePart],
                             to endpoint: URL,
                             method: String = "POST",
                             params: [String: String] = [:],
                             headers: [String: String] = [:],
                             completion: @escaping (Result<(HTTPURLResponse, Data), Error>) -> Void) throws -> URLSessionUploadTask {
        precondition(!parts.isEmpty, "parts must not be empty")
        let (bodyFileURL, boundary) = try MultipartBuilder.fileBackedBodyMany(parts: parts, params: params)
        
        var req = URLRequest(url: endpoint)
        req.httpMethod = method
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        
        let id = UUID().uuidString
        let task = session.uploadTask(with: req, fromFile: bodyFileURL)
        task.taskDescription = id
        
        completions[task.taskIdentifier] = { [weak self] result in
            try? FileManager.default.removeItem(at: bodyFileURL)
            self?.completions[task.taskIdentifier] = nil
            self?.removePending(id: id)
            completion(result)
        }
        
        if let first = parts.first {
            let rec = UploadRecord(id: id, endpoint: endpoint, filePath: first.fileURL.path, mimeType: first.mimeType, fieldName: first.fieldName, fileName: first.fileName, extraParams: params)
            persistPending(rec)
        }
        
        observeProgress(for: task)
        task.resume()
        return task
    }

    /// Restore in-flight tasks after launch and reattach progress buffers.
    func restoreInFlightTasks(_ onComplete: @escaping ([URLSessionTask]) -> Void) {
        session.getAllTasks { tasks in
            for t in tasks {
                self.buffers[t.taskIdentifier] = Data()
                self.observeProgress(for: t)
            }
            print("Restored \(tasks.count) background tasks")
            onComplete(tasks) // ✅ return array
        }
    }
//    func restoreInFlightTasks(_ onFound: ((URLSessionTask) -> Void)? = nil) {
//        session.getAllTasks { [weak self] tasks in
//            guard let self = self else { return }
//            for t in tasks {
//                onFound?(t)
//                self.buffers[t.taskIdentifier] = Data()
//                self.observeProgress(for: t)
//            }
//            print("Restored \(tasks.count) background tasks")
//        }
//    }

    // MARK: - Helpers (persist pending)
    private func persistPending(_ record: UploadRecord) {
        var arr = (try? loadPending()) ?? []
        arr.removeAll { $0.id == record.id }
        arr.append(record)
        savePending(arr)
    }

    private func removePending(id: String) {
        var arr = (try? loadPending()) ?? []
        arr.removeAll { $0.id == id }
        savePending(arr)
    }

    private func loadPending() throws -> [UploadRecord] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey) else { return [] }
        return try JSONDecoder().decode([UploadRecord].self, from: data)
    }

    private func savePending(_ records: [UploadRecord]) {
        let data = try? JSONEncoder().encode(records)
        UserDefaults.standard.set(data, forKey: pendingKey)
    }

    // MARK: - Progress via KVO -> NotificationCenter
    private func observeProgress(for task: URLSessionTask) {
        task.progress.addObserver(self, forKeyPath: #keyPath(Progress.fractionCompleted), options: [.new], context: UnsafeMutableRawPointer(bitPattern: task.taskIdentifier))
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == #keyPath(Progress.fractionCompleted), let progress = object as? Progress else { return }
        // We can’t get id here reliably; broadcast by taskIdentifier, and UI can map using restore or your own store.
        NotificationCenter.default.post(name: .bgUploadProgress, object: nil, userInfo: ["id": "unknown", "progress": progress.fractionCompleted])
    }
}

// MARK: - URLSession Delegates
extension BackgroundUploader: URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // All background events delivered — tell the system we're done
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }

    // Collect server response data
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffers[dataTask.taskIdentifier, default: Data()].append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            if let ctx = UnsafeMutableRawPointer(bitPattern: task.taskIdentifier) {
                task.progress.removeObserver(self, forKeyPath: #keyPath(Progress.fractionCompleted), context: ctx)
            }
            buffers[task.taskIdentifier] = nil
        }

        guard let id = task.taskDescription else { return }

        // Load pending record for this task
        guard let record = (try? loadPending())?.first(where: { $0.id == id }) else {
            return
        }

        if let error = error {
            // ❌ Upload failed - > Restart Process
            DispatchQueue.main.async {
                (UIApplication.shared.delegate as? AppDelegate)?.uploadAllData()
            }
            return
        }

        guard let http = task.response as? HTTPURLResponse else {
            return
        }

        let body = buffers[task.taskIdentifier] ?? Data()

        if http.statusCode == 200 {
            // ✅ Upload success → update DB
            let strType = record.extraParams["type"] ?? ""
            let strOrderId = record.extraParams["order_unique_id"] ?? ""
            let strImageType = record.extraParams["side"] ?? ""
            
            if strType == uploadType.license.rawValue {
                //FOR LICENSE IMAGE
                CoreDBManager.sharedDatabase.updateLicenseUploadDataStatus(strOrderID: strOrderId, strType: uploadType.image.rawValue, image_side: strImageType, newStatus: "SUCCESS") { _ in
                    DispatchQueue.main.async {
                        (UIApplication.shared.delegate as? AppDelegate)?.uploadAllData()
                    }
                }
            }
            else {
                //FOR PICKUP AND DELIVERY IMAGE
                CoreDBManager.sharedDatabase.updateVideoImageUploadDataStatus(
                    strOrderID: strOrderId,
                    strType: uploadType.video_image.rawValue,
                    strVideoType: strType,
                    newStatus: "SUCCESS"
                ) { _ in
                    DispatchQueue.main.async {
                        (UIApplication.shared.delegate as? AppDelegate)?.uploadAllData()
                    }
                }
            }
        } else {
            // ❌ Server returned error and restart process
            DispatchQueue.main.async {
                (UIApplication.shared.delegate as? AppDelegate)?.uploadAllData()
            }
        }
    }


    // Optional: progress logging while in foreground
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(max(totalBytesExpectedToSend, 1))
        print("Upload progress: \(progress)")
    }
}

// MARK: - MultipartBuilder
enum MultipartBuilder {
    static func fileBackedBody(fileURL: URL,
                               fieldName: String,
                               fileName: String,
                               mimeType: String,
                               params: [String: String]) throws -> (url: URL, boundary: String) {
        let boundary = "Boundary-\(UUID().uuidString)"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bg-multipart-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: tmp.path, contents: nil, attributes: nil)
        let fh = try FileHandle(forWritingTo: tmp)
        defer { try? fh.close() }

        func write(_ s: String) throws { if #available(iOS 13.4, *) {
            try fh.write(contentsOf: Data(s.utf8))
        } else {
            // Fallback on earlier versions
        } }
        for (k, v) in params {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n")
            try write("\(v)\r\n")
        }
        try write("--\(boundary)\r\n")
        try write("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        try write("Content-Type: \(mimeType)\r\n\r\n")

        let src = try FileHandle(forReadingFrom: fileURL)
        defer { try? src.close() }
        while autoreleasepool(invoking: {
            let chunk = src.readData(ofLength: 1 << 20)
            if chunk.isEmpty { return false }
            if #available(iOS 13.4, *) {
                try? fh.write(contentsOf: chunk)
            } else {
                // Fallback on earlier versions
            }
            return true
        }) {}

        try write("\r\n--\(boundary)--\r\n")
        return (tmp, boundary)
    }

    static func fileBackedBodyMany(parts: [BackgroundUploader.FilePart],
                                   params: [String: String]) throws -> (url: URL, boundary: String) {
        let boundary = "Boundary-\(UUID().uuidString)"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("bg-multipart-\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: tmp.path, contents: nil, attributes: nil)
        let fh = try FileHandle(forWritingTo: tmp)
        defer { try? fh.close() }

        func write(_ s: String) throws { if #available(iOS 13.4, *) {
            try fh.write(contentsOf: Data(s.utf8))
        } else {
            // Fallback on earlier versions
        } }
        for (k, v) in params {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n")
            try write("\(v)\r\n")
        }
        for part in parts {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(part.fieldName)\"; filename=\"\(part.fileName)\"\r\n")
            try write("Content-Type: \(part.mimeType)\r\n\r\n")
            let src = try FileHandle(forReadingFrom: part.fileURL)
            defer { try? src.close() }
            while autoreleasepool(invoking: {
                let chunk = src.readData(ofLength: 1 << 20)
                if chunk.isEmpty { return false }
                if #available(iOS 13.4, *) {
                    try? fh.write(contentsOf: chunk)
                } else {
                    // Fallback on earlier versions
                }
                return true
            }) {}
            try write("\r\n")
        }
        try write("--\(boundary)--\r\n")
        return (tmp, boundary)
    }
}
