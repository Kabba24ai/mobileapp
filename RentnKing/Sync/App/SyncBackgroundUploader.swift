//
//  SyncBackgroundUploader.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Phase 4 — large-file transport for Sync Engine media operations.
//
//  Division of labour (Step 15):
//    • the Sync Engine owns the OPERATION — its id, client_media_id, durable file,
//      state, retries and the acknowledgment;
//    • this background URLSession owns the TRANSFER of the (file-backed) multipart
//      body, so an upload survives the app being suspended or killed mid-flight.
//
//  The two share the operation id: it is the task's `taskDescription`, so after a
//  relaunch `restore()` can tell the engine which operations are still in flight
//  (engine.holdForExternalTransfer) and, when the delegate fires, hand the result
//  back (engine.completeExternalTransfer). No second retry database exists — a
//  task that is gone without a result simply leaves its operation pending and the
//  engine re-sends it; the server converges on client_media_id.
//
//  Body files live under <KabbaSync root>/uploads (protected, excluded from
//  backup) and are deleted when their task finishes.
//

import Foundation

final class SyncBackgroundUploader: NSObject {

    static let shared = SyncBackgroundUploader()
    static let sessionIdentifier = "ai.kabba.sync.uploads"

    struct Handoff: Equatable {
        let operationId: String
        let requestId: String
        let bodyFileURL: URL
    }

    /// Called (on an arbitrary queue) with the final result of a transfer that had no live
    /// in-process completion — i.e. it finished after a relaunch.
    var externalCompletion: ((String, SyncHTTPResult) -> Void)?

    private(set) var uploadsDirectory: URL?
    private var completions: [String: (SyncHTTPResult) -> Void] = [:]
    private var buffers: [Int: Data] = [:]
    private var systemCompletionHandler: (() -> Void)?
    private let lock = NSLock()
    private var sessionStorage: URLSession?

    var isConfigured: Bool { uploadsDirectory != nil }

    func configure(rootDirectory: URL) {
        let dir = rootDirectory.appendingPathComponent("uploads", isDirectory: true)
        try? FileSyncOperationStore.ensureProtectedDirectory(dir, fileManager: .default)
        lock.lock(); uploadsDirectory = dir; lock.unlock()
    }

    private var session: URLSession {
        if let s = sessionStorage { return s }
        let cfg = URLSessionConfiguration.background(withIdentifier: SyncBackgroundUploader.sessionIdentifier)
        cfg.sessionSendsLaunchEvents = true
        cfg.isDiscretionary = false
        cfg.allowsExpensiveNetworkAccess = true
        cfg.allowsConstrainedNetworkAccess = true
        cfg.waitsForConnectivity = true
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        sessionStorage = s
        return s
    }

    // MARK: - Transfers

    /// Starts the background upload of an already-built multipart body file. The completion
    /// fires in THIS process if it is still alive when the task finishes; otherwise the
    /// result reaches the engine through `externalCompletion` after relaunch.
    func upload(_ urlRequest: URLRequest, bodyFileURL: URL, operationId: String, requestId: String,
                completion: @escaping (SyncHTTPResult) -> Void) {
        let task = session.uploadTask(with: urlRequest, fromFile: bodyFileURL)
        task.taskDescription = SyncBackgroundUploader.encode(Handoff(operationId: operationId, requestId: requestId, bodyFileURL: bodyFileURL))
        lock.lock()
        completions[operationId] = completion
        buffers[task.taskIdentifier] = Data()
        lock.unlock()
        task.resume()
    }

    /// Operation ids whose upload tasks are still alive in the background session (after a
    /// relaunch). The engine must hold these instead of re-sending them.
    func restore(_ completion: @escaping ([String]) -> Void) {
        session.getAllTasks { tasks in
            let ids = tasks.compactMap { SyncBackgroundUploader.decode($0.taskDescription)?.operationId }
            self.lock.lock()
            for task in tasks where self.buffers[task.taskIdentifier] == nil { self.buffers[task.taskIdentifier] = Data() }
            self.lock.unlock()
            completion(ids)
        }
    }

    /// AppDelegate → application(_:handleEventsForBackgroundURLSession:completionHandler:)
    func handleEvents(completionHandler: @escaping () -> Void) {
        lock.lock(); systemCompletionHandler = completionHandler; lock.unlock()
        _ = session // make sure the session exists so the delegate receives the events
    }

    // MARK: - taskDescription codec

    static func encode(_ handoff: Handoff) -> String {
        [handoff.operationId, handoff.requestId, handoff.bodyFileURL.path].joined(separator: "\n")
    }

    static func decode(_ description: String?) -> Handoff? {
        guard let parts = description?.components(separatedBy: "\n"), parts.count == 3, !parts[0].isEmpty else { return nil }
        return Handoff(operationId: parts[0], requestId: parts[1], bodyFileURL: URL(fileURLWithPath: parts[2]))
    }
}

extension SyncBackgroundUploader: URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let handler = systemCompletionHandler
        systemCompletionHandler = nil
        lock.unlock()
        DispatchQueue.main.async { handler?() }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffers[dataTask.taskIdentifier, default: Data()].append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let handoff = SyncBackgroundUploader.decode(task.taskDescription) else { return }

        lock.lock()
        let body = buffers.removeValue(forKey: task.taskIdentifier) ?? Data()
        let completion = completions.removeValue(forKey: handoff.operationId)
        lock.unlock()

        try? FileManager.default.removeItem(at: handoff.bodyFileURL)

        let result: SyncHTTPResult
        if let error = error {
            result = .failure(APIErrorClassifier.transportError(from: error))
        } else if let http = task.response as? HTTPURLResponse {
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let k = key as? String, let v = value as? String { headers[k] = v }
            }
            if headers["X-Request-Id"] == nil { headers["X-Request-Id"] = handoff.requestId }
            if http.statusCode == 401 { KabbaAPIClient.noteUnauthorizedResponse(path: MediaRequestFactory.path) }
            result = .response(SyncHTTPResponse(statusCode: http.statusCode, headers: headers, body: body))
        } else {
            result = .failure(APIError.transport(.other, description: "No HTTP response"))
        }

        if let completion = completion {
            completion(result)
        } else {
            externalCompletion?(handoff.operationId, result)
        }
    }
}
