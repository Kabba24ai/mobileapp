//
//  APIError.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The ONE error representation for the canonical network layer and the Sync
//  Engine. It carries the HTTP status, the server's machine-readable code and
//  retry classification, validation errors, the correlation id, and the
//  transport failure kind — so no ViewController has to parse a Laravel failure
//  body itself, and the Sync Engine can decide retry vs needs-attention from
//  one place (APIErrorClassifier).
//

import Foundation

/// Why a request never produced an HTTP response.
enum TransportFailure: String, Codable, Equatable {
    case offline            // no route to host / not connected
    case dns                // host lookup failed
    case timeout
    case connectionLost     // dropped mid-flight
    case cannotConnect      // refused / unreachable host
    case tls                // certificate / secure connection failure
    case cancelled
    case other
}

/// What the Sync Engine should do with an operation after this failure.
enum RetryDisposition: String, Codable, Equatable {
    /// Temporary — keep the operation pending and retry with backoff. Never gives up.
    case retry
    /// 401 — stop retrying until a valid session exists; the operation stays stored.
    case waitForAuthentication
    /// 426 — stop retrying until the app is updated; the operation stays stored.
    case waitForAppUpdate
    /// Permanent/business rejection — park it for a person (payload preserved).
    case needsAttention
}

struct APIError: Error, Codable, Equatable {

    enum Kind: String, Codable {
        case transport       // no HTTP response at all
        case http            // an HTTP status outside 2xx (or a 2xx whose body says the operation failed)
        case decoding        // 2xx but the body could not be understood
        case invalidRequest  // the client could not even build the request (e.g. no base URL / no session)
    }

    let kind: Kind
    let statusCode: Int?
    /// Server machine-readable code (`error.code` / legacy `error_code`).
    let code: String?
    /// Human-readable message — the server's, or a transport description.
    let message: String
    /// Field → messages from a 422.
    let validationErrors: [String: [String]]
    /// Correlation id (`request_id` body field or X-Request-Id header).
    let requestId: String?
    /// The server's own classification (`error.retryable`), when it sent one.
    let serverRetryable: Bool?
    let transport: TransportFailure?
    /// Underlying system error text for diagnostics (never shown as the primary employee message).
    let underlyingDescription: String?

    init(kind: Kind,
         statusCode: Int? = nil,
         code: String? = nil,
         message: String,
         validationErrors: [String: [String]] = [:],
         requestId: String? = nil,
         serverRetryable: Bool? = nil,
         transport: TransportFailure? = nil,
         underlyingDescription: String? = nil) {
        self.kind = kind
        self.statusCode = statusCode
        self.code = code
        self.message = message
        self.validationErrors = validationErrors
        self.requestId = requestId
        self.serverRetryable = serverRetryable
        self.transport = transport
        self.underlyingDescription = underlyingDescription
    }

    var isAuthenticationFailure: Bool { statusCode == 401 }
    var isAppUpdateRequired: Bool { statusCode == 426 }
    var isValidationFailure: Bool { statusCode == 422 }
    var isConflict: Bool { statusCode == 409 }
    var isNotFound: Bool { statusCode == 404 }
    var isServerFailure: Bool { (statusCode ?? 0) >= 500 }
    var isTransportFailure: Bool { kind == .transport }

    var disposition: RetryDisposition { APIErrorClassifier.disposition(for: self) }

    /// Employee-safe one-liner (no raw status codes as the primary message).
    var employeeMessage: String {
        switch kind {
        case .transport:
            switch transport ?? .other {
            case .offline, .dns, .cannotConnect: return "No connection to Kabba. Saved on this phone — will sync when connected."
            case .timeout, .connectionLost:      return "The connection dropped. Saved on this phone — will retry."
            case .tls:                           return "Secure connection to Kabba failed."
            case .cancelled:                     return "The request was cancelled."
            case .other:                         return "Network problem. Saved on this phone — will retry."
            }
        case .decoding:
            return "Kabba answered in an unexpected format. Will retry."
        case .invalidRequest:
            return message
        case .http:
            if isAuthenticationFailure { return "Your session has expired. Please sign in again." }
            if isAppUpdateRequired { return "This version of the app must be updated." }
            if isServerFailure || statusCode == 429 { return "Kabba is temporarily unavailable. Will retry." }
            return message
        }
    }

    // MARK: Convenience constructors

    static func transport(_ failure: TransportFailure, description: String? = nil) -> APIError {
        APIError(kind: .transport, message: description ?? "Network transport failure (\(failure.rawValue))",
                 transport: failure, underlyingDescription: description)
    }

    static func invalidRequest(_ message: String) -> APIError {
        APIError(kind: .invalidRequest, message: message)
    }
}

/// Bridging for legacy call sites that still receive `Error`/`NSError`: a meaningful domain
/// and code instead of the historical fabricated `code: 401`.
extension APIError: CustomNSError, LocalizedError {
    static var errorDomain: String { "ai.kabba.api" }

    /// HTTP status when there was a response; negative transport codes otherwise.
    var errorCode: Int {
        if let status = statusCode { return status }
        switch transport ?? .other {
        case .offline:        return -1009
        case .dns:            return -1003
        case .timeout:        return -1001
        case .connectionLost: return -1005
        case .cannotConnect:  return -1004
        case .tls:            return -1200
        case .cancelled:      return -999
        case .other:          return -1
        }
    }

    var errorUserInfo: [String: Any] {
        var info: [String: Any] = [
            NSLocalizedDescriptionKey: employeeMessage,
            "kabba.kind": kind.rawValue,
            "kabba.retryable": disposition == .retry,
        ]
        if let code = code { info["kabba.code"] = code }
        if let requestId = requestId { info["kabba.request_id"] = requestId }
        if let underlying = underlyingDescription { info["kabba.underlying"] = underlying }
        return info
    }

    var errorDescription: String? { employeeMessage }
}

/// Maps HTTP status / body / transport errors to APIError and APIError to a retry disposition.
enum APIErrorClassifier {

    /// Builds the APIError for a completed HTTP exchange that is NOT a success.
    static func classify(statusCode: Int, body: Data?, headers: [String: String] = [:]) -> APIError {
        let envelope = APIEnvelope.parse(body)
        let headerRequestId = headers.first { $0.key.lowercased() == "x-request-id" }?.value

        let message = envelope?.errorMessage
            ?? envelope?.message
            ?? defaultMessage(forStatus: statusCode)

        return APIError(kind: .http,
                        statusCode: statusCode,
                        code: envelope?.errorCode ?? defaultCode(forStatus: statusCode),
                        message: message,
                        validationErrors: envelope?.validationErrors ?? [:],
                        requestId: envelope?.requestId ?? headerRequestId,
                        serverRetryable: envelope?.retryable)
    }

    /// A 2xx whose body declares failure (legacy endpoints answer 200 + success:false/status:false).
    static func classifyDeclaredFailure(statusCode: Int, envelope: APIEnvelope, headers: [String: String] = [:]) -> APIError {
        let headerRequestId = headers.first { $0.key.lowercased() == "x-request-id" }?.value
        return APIError(kind: .http,
                        statusCode: statusCode,
                        code: envelope.errorCode ?? "DECLARED_FAILURE",
                        message: envelope.errorMessage ?? envelope.message ?? "The server rejected the operation.",
                        validationErrors: envelope.validationErrors,
                        requestId: envelope.requestId ?? headerRequestId,
                        serverRetryable: envelope.retryable)
    }

    static func decodingFailure(statusCode: Int, headers: [String: String] = [:], detail: String? = nil) -> APIError {
        let headerRequestId = headers.first { $0.key.lowercased() == "x-request-id" }?.value
        return APIError(kind: .decoding, statusCode: statusCode, code: "UNREADABLE_RESPONSE",
                        message: "Unreadable response from server.", requestId: headerRequestId,
                        underlyingDescription: detail)
    }

    /// Maps a URLError / NSURLErrorDomain code to a transport failure kind.
    static func transportFailure(forURLErrorCode code: Int) -> TransportFailure {
        switch code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff:
            return .offline
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return .dns
        case NSURLErrorTimedOut:
            return .timeout
        case NSURLErrorNetworkConnectionLost:
            return .connectionLost
        case NSURLErrorCannotConnectToHost, NSURLErrorResourceUnavailable:
            return .cannotConnect
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return .tls
        case NSURLErrorCancelled:
            return .cancelled
        default:
            return .other
        }
    }

    static func transportError(from error: Error) -> APIError {
        let ns = error as NSError
        let failure: TransportFailure = ns.domain == NSURLErrorDomain ? transportFailure(forURLErrorCode: ns.code) : .other
        return APIError.transport(failure, description: ns.localizedDescription)
    }

    /// The Sync Engine's retry decision. Server `error.retryable` wins when present.
    static func disposition(for error: APIError) -> RetryDisposition {
        switch error.kind {
        case .transport:
            return .retry
        case .decoding:
            // A 2xx we could not read: the operation may already be applied. Retrying is
            // safe because operations are idempotent — the retry converges on the replay.
            return .retry
        case .invalidRequest:
            return .needsAttention
        case .http:
            guard let status = error.statusCode else { return .retry }
            if status == 401 { return .waitForAuthentication }
            if status == 426 { return .waitForAppUpdate }
            if let serverSays = error.serverRetryable { return serverSays ? .retry : .needsAttention }
            if status == 429 || status >= 500 { return .retry }
            return .needsAttention
        }
    }

    // MARK: Defaults

    static func defaultCode(forStatus status: Int) -> String {
        switch status {
        case 400: return "BAD_REQUEST"
        case 401: return "UNAUTHENTICATED"
        case 403: return "FORBIDDEN"
        case 404: return "NOT_FOUND"
        case 409: return "CONFLICT"
        case 422: return "VALIDATION_FAILED"
        case 426: return "APP_UPDATE_REQUIRED"
        case 429: return "RATE_LIMITED"
        case 500...599: return "SERVER_ERROR"
        default: return "HTTP_ERROR"
        }
    }

    static func defaultMessage(forStatus status: Int) -> String {
        switch status {
        case 400: return "The request could not be understood."
        case 401: return "Unauthenticated."
        case 403: return "You are not allowed to perform this action."
        case 404: return "Resource not found."
        case 409: return "The operation conflicts with the current state."
        case 422: return "Validation failed."
        case 426: return "App update required."
        case 429: return "Too many requests."
        case 500...599: return "Server error."
        default: return "The request could not be completed (HTTP \(status))."
        }
    }
}
