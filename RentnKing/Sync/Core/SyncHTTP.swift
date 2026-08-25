//
//  SyncHTTP.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The seam between the Sync Engine and the network: the engine describes a
//  request, a SyncHTTPClient (URLSession in the app, a fake in tests) performs
//  it, and a SyncOperationHandler per operation type knows how to build the
//  request and read the answer. The engine itself never touches URLSession.
//

import Foundation

struct SyncHTTPRequest: Equatable {
    var method: String
    /// Relative to the API base URL, e.g. "orders/schedules/driver-checklist".
    var path: String
    var headers: [String: String]
    var jsonBody: JSONValue?
    /// The operation's idempotency key; the client sends it as X-Operation-Id.
    var operationId: String
    /// Files to attach as multipart parts (media operations). Empty → JSON body.
    var attachments: [SyncAsset]
    /// Large-file hint (Phase 4): the app's HTTP client may hand the transfer to a
    /// background URLSession that survives suspension; the Sync Engine still owns the
    /// operation, its state and the acknowledgment.
    var prefersBackgroundTransfer: Bool

    init(method: String = "POST",
         path: String,
         headers: [String: String] = [:],
         jsonBody: JSONValue? = nil,
         operationId: String,
         attachments: [SyncAsset] = [],
         prefersBackgroundTransfer: Bool = false) {
        self.method = method
        self.path = path
        self.headers = headers
        self.jsonBody = jsonBody
        self.operationId = operationId
        self.attachments = attachments
        self.prefersBackgroundTransfer = prefersBackgroundTransfer
    }
}

struct SyncHTTPResponse: Equatable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data?

    init(statusCode: Int, headers: [String: String] = [:], body: Data? = nil) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    var envelope: APIEnvelope? { APIEnvelope.parse(body) }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var requestId: String? { header("X-Request-Id") }
    var isReplay: Bool { header("X-Idempotent-Replay")?.lowercased() == "true" }
    var isSuccessStatus: Bool { (200..<300).contains(statusCode) }
}

/// Either an HTTP exchange completed (any status) or it never did.
enum SyncHTTPResult {
    case response(SyncHTTPResponse)
    /// Transport failure or the client could not build the request.
    case failure(APIError)
}

protocol SyncHTTPClient: AnyObject {
    func perform(_ request: SyncHTTPRequest, completion: @escaping (SyncHTTPResult) -> Void)
}

enum SyncOutcome: Equatable {
    case acknowledged(SyncAcknowledgment)
    case failed(APIError)
}

enum SyncHandlerError: Error, Equatable {
    /// No session / base URL — the engine pauses for authentication instead of failing the operation.
    case notAuthenticated(String)
    /// The stored payload cannot be turned into a request — the operation needs attention.
    case invalidPayload(String)
}

protocol SyncOperationHandler {
    /// e.g. "driver_checklist.update"
    var operationType: String { get }
    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest
    func interpret(_ response: SyncHTTPResponse, for operation: SyncOperation, now: Date) -> SyncOutcome
    /// Media handlers return true: the engine deletes the operation's local files the
    /// moment Laravel acknowledges it (MediaCleanupPolicy). Everything else keeps them.
    var removesAssetsAfterAcknowledgment: Bool { get }
    /// Phase 5: only the adapter that drains items an OLD build queued in its legacy
    /// format may target a deprecated route (DeprecatedMobileEndpoints). Default false —
    /// the engine parks any other operation that tries.
    var mayUseDeprecatedEndpoint: Bool { get }
}

extension SyncOperationHandler {
    /// Default: canonical + legacy envelope reading, HTTP status authoritative.
    func interpret(_ response: SyncHTTPResponse, for operation: SyncOperation, now: Date) -> SyncOutcome {
        SyncResponseInterpreter.interpret(response, now: now)
    }

    var removesAssetsAfterAcknowledgment: Bool { false }

    var mayUseDeprecatedEndpoint: Bool { false }
}

enum SyncResponseInterpreter {
    static func interpret(_ response: SyncHTTPResponse, now: Date) -> SyncOutcome {
        let status = response.statusCode

        guard response.isSuccessStatus else {
            return .failed(APIErrorClassifier.classify(statusCode: status, body: response.body, headers: response.headers))
        }

        guard let envelope = response.envelope else {
            if response.body == nil || response.body?.isEmpty == true {
                // 2xx with no body (e.g. 204) is an acknowledgment.
                return .acknowledged(SyncAcknowledgment(acknowledgedAt: now, statusCode: status, requestId: response.requestId,
                                                        replayed: response.isReplay, serverReceivedAt: nil, data: nil))
            }
            return .failed(APIErrorClassifier.decodingFailure(statusCode: status, headers: response.headers,
                                                              detail: "Non-JSON body (\(response.body?.count ?? 0) bytes)"))
        }

        // Legacy endpoints answer 200 with success:"0" / status:false — that is a rejection.
        if envelope.declaredSuccess == false {
            return .failed(APIErrorClassifier.classifyDeclaredFailure(statusCode: status, envelope: envelope, headers: response.headers))
        }

        let serverReceivedAt = envelope.data?["server_received_at"]?.stringValue.flatMap(KabbaISO8601.date(from:))

        return .acknowledged(SyncAcknowledgment(acknowledgedAt: now,
                                                statusCode: status,
                                                requestId: envelope.requestId ?? response.requestId,
                                                replayed: envelope.replayed || response.isReplay,
                                                serverReceivedAt: serverReceivedAt,
                                                data: envelope.data))
    }
}
