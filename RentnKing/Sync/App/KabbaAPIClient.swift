//
//  KabbaAPIClient.swift
//  RentnKing — Sync App layer (Foundation only; UIKit-free on purpose)
//
//  The canonical network layer for the Sync Engine and for new code paths:
//
//   • HTTP status is authoritative. 2xx → response; anything else → APIError
//     carrying the real status, the server's error.code / retryable flag and
//     the correlation id. No fabricated "401" for unrelated failures.
//   • Every request carries X-Request-Id (new per attempt), X-Mobile-Platform,
//     X-Mobile-Version, X-Mobile-Build, X-Device-Id (per-install id), lang,
//     Accept, and — for idempotent operations — X-Operation-Id.
//   • A genuine HTTP 401 posts `.kabbaAuthenticationExpired` (debounced) so the
//     app can end the session; the Sync Engine pauses on it independently.
//
//  Legacy screens still use WebServiceHelper (Alamofire). That helper now adds
//  the same standard headers via `legacyStandardHeaders()` and bridges its
//  failures through `legacyError(...)` so callers see real status codes.
//

import Foundation

// MobileClientMetadata lives in Sync/Core/ClientMetadata.swift (Phase 5) so it is unit-tested.

struct KabbaAPIClientConfiguration {
    /// The per-environment API base (…/api/admin/v1/). nil when logged out.
    var baseURL: () -> URL?
    /// The bearer token from the Keychain-backed store. nil when logged out.
    var accessToken: () -> String?
    var language: () -> String
    var metadata: () -> MobileClientMetadata
    var timeout: TimeInterval

    init(baseURL: @escaping () -> URL?,
         accessToken: @escaping () -> String?,
         language: @escaping () -> String,
         metadata: @escaping () -> MobileClientMetadata,
         timeout: TimeInterval = 30) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.language = language
        self.metadata = metadata
        self.timeout = timeout
    }
}

extension Notification.Name {
    /// Posted on the main queue when a request received a genuine HTTP 401.
    /// userInfo: ["path": String, "request_id": String]
    static let kabbaAuthenticationExpired = Notification.Name("ai.kabba.sync.authenticationExpired")
    /// Phase 5 — a genuine HTTP 426 APP_UPDATE_REQUIRED. userInfo: ["policy": Data (the 426 body), "path": String, "request_id": String]
    static let kabbaAppUpdateRequired = Notification.Name("ai.kabba.sync.appUpdateRequired")
    /// Phase 5 — the server's non-blocking update advice changed (X-Mobile-Update headers). userInfo: ["level": String]
    static let kabbaUpdateAdviceChanged = Notification.Name("ai.kabba.sync.updateAdviceChanged")
    /// Phase 5 — an authenticated response carried X-Session-Expires-At. userInfo: ["expires_at": String]
    static let kabbaSessionExpiryChanged = Notification.Name("ai.kabba.sync.sessionExpiryChanged")
}

final class KabbaAPIClient: SyncHTTPClient {

    private(set) static var shared: KabbaAPIClient?

    @discardableResult
    static func configure(_ configuration: KabbaAPIClientConfiguration, session: URLSession? = nil) -> KabbaAPIClient {
        let client = KabbaAPIClient(configuration: configuration, session: session)
        shared = client
        return client
    }

    let configuration: KabbaAPIClientConfiguration
    private let session: URLSession
    private let unauthorizedLock = NSLock()
    private var lastUnauthorizedAt: Date?
    /// One session-expiry notification per this many seconds, however many requests fail.
    private let unauthorizedDebounce: TimeInterval = 5

    init(configuration: KabbaAPIClientConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = configuration.timeout
            config.timeoutIntervalForResource = configuration.timeout * 4
            config.waitsForConnectivity = false      // fail fast; the Sync Engine owns waiting
            config.httpAdditionalHeaders = ["Accept": "application/json"]
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Headers

    /// "ios-<uuid>" — matches the server's X-Request-Id whitelist and is new for every attempt.
    static func newRequestId() -> String {
        "ios-" + UUID().uuidString.lowercased()
    }

    func standardHeaders(requestId: String = KabbaAPIClient.newRequestId(),
                         operationId: String? = nil,
                         includeAuthorization: Bool = true) -> [String: String] {
        var headers = configuration.metadata().headers
        headers["X-Request-Id"] = requestId
        headers["Accept"] = "application/json"
        headers["lang"] = configuration.language()
        if let operationId = operationId {
            headers["X-Operation-Id"] = operationId
        }
        if includeAuthorization, let token = configuration.accessToken(), !token.isEmpty {
            headers["Authorization"] = "Bearer " + token
        }
        return headers
    }

    /// For the legacy WebServiceHelper: the same metadata + correlation headers, no Authorization
    /// (the helper already sets its own). Empty before bootstrap.
    static func legacyStandardHeaders(includeAuthorization: Bool = false) -> [String: String] {
        shared?.standardHeaders(includeAuthorization: includeAuthorization) ?? ["X-Request-Id": newRequestId()]
    }

    // MARK: - SyncHTTPClient

    func perform(_ request: SyncHTTPRequest, completion: @escaping (SyncHTTPResult) -> Void) {
        let forward: (Result<SyncHTTPResponse, APIError>) -> Void = { result in
            switch result {
            case .success(let response): completion(.response(response))
            case .failure(let error):    completion(.failure(error))
            }
        }

        if request.attachments.isEmpty {
            send(method: request.method, path: request.path, jsonBody: request.jsonBody,
                 extraHeaders: request.headers, operationId: request.operationId, completion: forward)
        } else {
            sendMultipart(method: request.method, path: request.path, fields: request.jsonBody, attachments: request.attachments,
                          extraHeaders: request.headers, operationId: request.operationId,
                          background: request.prefersBackgroundTransfer, completion: forward)
        }
    }

    /// Where attachment relativePaths resolve. Set by the bootstrap to the Sync Engine store's assets directory.
    var assetsDirectory: URL?

    // MARK: - Multipart (fields + files), file-backed body

    func sendMultipart(method: String,
                       path: String,
                       fields: JSONValue?,
                       attachments: [SyncAsset],
                       extraHeaders: [String: String] = [:],
                       operationId: String? = nil,
                       background: Bool = false,
                       completion: @escaping (Result<SyncHTTPResponse, APIError>) -> Void) {
        guard let base = configuration.baseURL(), let url = KabbaAPIClient.resolve(path: path, against: base),
              let token = configuration.accessToken(), !token.isEmpty else {
            completion(.failure(APIError(kind: .http, statusCode: 401, code: "NO_SESSION",
                                         message: "Not signed in.", serverRetryable: false)))
            return
        }
        guard let assetsDirectory = assetsDirectory else {
            completion(.failure(APIError.invalidRequest("Assets directory is not configured")))
            return
        }

        // Phase 4: media operations ask for a background transfer. The body is built in the
        // protected uploads directory (it must outlive this process) and handed to the
        // background URLSession; the Sync Engine keeps owning the operation.
        let uploader = SyncBackgroundUploader.shared
        let useBackground = background && uploader.isConfigured && operationId != nil
        let bodyDirectory = useBackground ? (uploader.uploadsDirectory ?? FileManager.default.temporaryDirectory) : FileManager.default.temporaryDirectory

        let body: SyncMultipartBody
        do {
            body = try SyncMultipartBuilder.build(fields: fields, assets: attachments, assetsDirectory: assetsDirectory, directory: bodyDirectory)
        } catch SyncMultipartError.assetMissing(let relativePath) {
            completion(.failure(APIError.invalidRequest("A file for this operation is missing on the phone (\(relativePath)).")))
            return
        } catch {
            completion(.failure(APIError.invalidRequest("Could not build the upload: \(error.localizedDescription)")))
            return
        }

        let requestId = KabbaAPIClient.newRequestId()
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.uppercased()
        urlRequest.timeoutInterval = configuration.timeout * 4
        var headers = standardHeaders(requestId: requestId, operationId: operationId)
        for (key, value) in extraHeaders { headers[key] = value }
        for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        urlRequest.setValue(body.contentType, forHTTPHeaderField: "Content-Type")

        if useBackground, let operationId = operationId {
            uploader.upload(urlRequest, bodyFileURL: body.fileURL, operationId: operationId, requestId: requestId) { result in
                switch result {
                case .response(let response): completion(.success(response))
                case .failure(let error):     completion(.failure(error))
                }
            }
            return
        }

        let task = session.uploadTask(with: urlRequest, fromFile: body.fileURL) { [weak self] data, response, error in
            try? FileManager.default.removeItem(at: body.fileURL)
            if let error = error {
                completion(.failure(APIErrorClassifier.transportError(from: error)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(APIError.transport(.other, description: "No HTTP response")))
                return
            }
            var headerMap: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let k = key as? String, let v = value as? String { headerMap[k] = v }
            }
            if headerMap["X-Request-Id"] == nil { headerMap["X-Request-Id"] = requestId }
            self?.observe(statusCode: http.statusCode, headers: headerMap, body: data, path: path, requestId: requestId)
            completion(.success(SyncHTTPResponse(statusCode: http.statusCode, headers: headerMap, body: data)))
        }
        task.resume()
    }

    // MARK: - Generic JSON request

    /// Performs a JSON request. Success = ANY completed HTTP exchange (the caller reads the
    /// status via SyncResponseInterpreter / APIErrorClassifier); failure = transport-level or
    /// the request could not be built (no base URL / no session → surfaced as a 401-shaped
    /// error so the Sync Engine pauses for authentication).
    func send(method: String,
              path: String,
              jsonBody: JSONValue? = nil,
              extraHeaders: [String: String] = [:],
              operationId: String? = nil,
              completion: @escaping (Result<SyncHTTPResponse, APIError>) -> Void) {
        guard let base = configuration.baseURL(), let url = KabbaAPIClient.resolve(path: path, against: base) else {
            completion(.failure(APIError(kind: .http, statusCode: 401, code: "NO_SESSION",
                                         message: "Not signed in.", serverRetryable: false)))
            return
        }
        guard let token = configuration.accessToken(), !token.isEmpty else {
            completion(.failure(APIError(kind: .http, statusCode: 401, code: "NO_SESSION",
                                         message: "Not signed in.", serverRetryable: false)))
            return
        }

        let requestId = KabbaAPIClient.newRequestId()
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.uppercased()
        urlRequest.timeoutInterval = configuration.timeout

        var headers = standardHeaders(requestId: requestId, operationId: operationId)
        for (key, value) in extraHeaders { headers[key] = value }
        for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

        if let body = jsonBody {
            do {
                urlRequest.httpBody = try body.serialized()
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                completion(.failure(APIError.invalidRequest("Payload is not valid JSON: \(error.localizedDescription)")))
                return
            }
        }

        let task = session.dataTask(with: urlRequest) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(APIErrorClassifier.transportError(from: error)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(APIError.transport(.other, description: "No HTTP response")))
                return
            }
            var headerMap: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let k = key as? String, let v = value as? String { headerMap[k] = v }
            }
            if headerMap["X-Request-Id"] == nil { headerMap["X-Request-Id"] = requestId }
            self?.observe(statusCode: http.statusCode, headers: headerMap, body: data, path: path, requestId: requestId)
            completion(.success(SyncHTTPResponse(statusCode: http.statusCode, headers: headerMap, body: data)))
        }
        task.resume()
    }

    // MARK: - Legacy bridging (WebServiceHelper)

    /// A meaningful Error for a legacy Alamofire result: real HTTP status + server code when
    /// there was a response, a transport classification when there was not.
    static func legacyError(statusCode: Int?, data: Data?, error: Error?) -> Error {
        if let status = statusCode {
            if (200..<300).contains(status) {
                // 2xx whose body could not be understood.
                return APIErrorClassifier.decodingFailure(statusCode: status, detail: error?.localizedDescription)
            }
            return APIErrorClassifier.classify(statusCode: status, body: data)
        }
        if let error = error {
            return APIErrorClassifier.transportError(from: error)
        }
        return APIError.transport(.other, description: "No response")
    }

    /// The body declared failure (legacy `code` 100/101/102/401/105 pattern) although HTTP was 2xx.
    static func legacyDeclaredFailure(_ body: NSDictionary?, statusCode: Int?) -> Error {
        let code = (body?["code"] as? String) ?? (body?["code"] as? NSNumber)?.stringValue ?? "DECLARED_FAILURE"
        let message = (body?["msg"] as? String) ?? (body?["message"] as? String) ?? "The server rejected the request."
        return APIError(kind: .http, statusCode: statusCode ?? 200, code: "LEGACY_" + code, message: message, serverRetryable: false)
    }

    /// Called by the legacy helper when it sees a real HTTP 401.
    static func noteUnauthorizedResponse(path: String) {
        shared?.handleUnauthorized(path: path, requestId: "legacy")
    }

    /// Phase 5 — the legacy helper (Alamofire) hands every completed exchange here so 426,
    /// update advice and session expiry are handled ONCE, whichever network path saw them.
    static func noteLegacyResponse(statusCode: Int?, headers: [AnyHashable: Any]?, body: Data?, path: String) {
        guard let status = statusCode else { return }
        var headerMap: [String: String] = [:]
        for (key, value) in headers ?? [:] {
            if let k = key as? String, let v = value as? String { headerMap[k] = v }
        }
        shared?.observe(statusCode: status, headers: headerMap, body: body, path: path, requestId: headerMap["X-Request-Id"] ?? "legacy")
    }

    // MARK: - Response observation (Phase 5)

    private(set) var latestUpdateAdvice: UpdateAdvice?
    private var lastUpdateRequiredAt: Date?

    /// One place that reads the cross-cutting parts of every response: 401 → session
    /// expired; 426 → update required (body carried as-is, never logged); policy headers →
    /// non-blocking update advice; X-Session-Expires-At → the phone's session record.
    func observe(statusCode: Int, headers: [String: String], body: Data?, path: String, requestId: String) {
        if statusCode == 401 {
            handleUnauthorized(path: path, requestId: requestId)
        }
        if statusCode == 426 {
            handleUpdateRequired(body: body, path: path, requestId: requestId)
        }
        if let advice = UpdateAdvice.from(headers: headers) {
            let changed: Bool = unauthorizedLock.withLock {
                let changed = advice != latestUpdateAdvice
                latestUpdateAdvice = advice
                return changed
            }
            if changed {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .kabbaUpdateAdviceChanged, object: nil, userInfo: ["level": advice.level.rawValue])
                }
            }
        }
        if let expires = headers.first(where: { $0.key.caseInsensitiveCompare("X-Session-Expires-At") == .orderedSame })?.value {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .kabbaSessionExpiryChanged, object: nil, userInfo: ["expires_at": expires])
            }
        }
    }

    private func handleUpdateRequired(body: Data?, path: String, requestId: String) {
        let shouldPost: Bool = unauthorizedLock.withLock {
            let now = Date()
            if let last = lastUpdateRequiredAt, now.timeIntervalSince(last) < unauthorizedDebounce { return false }
            lastUpdateRequiredAt = now
            return true
        }
        guard shouldPost else { return }
        var info: [String: Any] = ["path": path, "request_id": requestId]
        if let body = body { info["policy"] = body }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .kabbaAppUpdateRequired, object: nil, userInfo: info)
        }
    }

    private func handleUnauthorized(path: String, requestId: String) {
        let shouldPost: Bool = unauthorizedLock.withLock {
            let now = Date()
            if let last = lastUnauthorizedAt, now.timeIntervalSince(last) < unauthorizedDebounce { return false }
            lastUnauthorizedAt = now
            return true
        }
        guard shouldPost else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .kabbaAuthenticationExpired, object: nil,
                                            userInfo: ["path": path, "request_id": requestId])
        }
    }

    // MARK: - URL resolution

    /// "orders/schedules/driver-checklist" against "https://host/api/admin/v1" or ".../v1/".
    static func resolve(path: String, against base: URL) -> URL? {
        var baseString = base.absoluteString
        if !baseString.hasSuffix("/") { baseString += "/" }
        guard let normalizedBase = URL(string: baseString) else { return nil }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: trimmed, relativeTo: normalizedBase)?.absoluteURL
    }
}
