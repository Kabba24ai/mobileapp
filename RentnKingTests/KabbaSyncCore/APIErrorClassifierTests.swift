import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class APIErrorClassifierTests: XCTestCase {

    private func classify(_ status: Int, body: [String: Any]? = nil) -> APIError {
        APIErrorClassifier.classify(statusCode: status, body: body.map(Fixtures.json), headers: ["X-Request-Id": "hdr-req-1"])
    }

    func testEveryStatusClassIsDistinguishedNotCollapsedIntoOneCode() {
        XCTAssertEqual(classify(400).code, "BAD_REQUEST")
        XCTAssertEqual(classify(401).code, "UNAUTHENTICATED")
        XCTAssertEqual(classify(403).code, "FORBIDDEN")
        XCTAssertEqual(classify(404).code, "NOT_FOUND")
        XCTAssertEqual(classify(409).code, "CONFLICT")
        XCTAssertEqual(classify(422).code, "VALIDATION_FAILED")
        XCTAssertEqual(classify(426).code, "APP_UPDATE_REQUIRED")
        XCTAssertEqual(classify(429).code, "RATE_LIMITED")
        XCTAssertEqual(classify(500).code, "SERVER_ERROR")
        XCTAssertEqual(classify(503).code, "SERVER_ERROR")
        XCTAssertEqual(classify(418).code, "HTTP_ERROR")
        XCTAssertEqual(classify(500).statusCode, 500)
        XCTAssertEqual(classify(404).requestId, "hdr-req-1", "falls back to the response header")
    }

    func testDispositionsByStatus() {
        XCTAssertEqual(classify(400).disposition, .needsAttention)
        XCTAssertEqual(classify(401).disposition, .waitForAuthentication)
        XCTAssertEqual(classify(403).disposition, .needsAttention)
        XCTAssertEqual(classify(404).disposition, .needsAttention)
        XCTAssertEqual(classify(409).disposition, .needsAttention)
        XCTAssertEqual(classify(422).disposition, .needsAttention)
        XCTAssertEqual(classify(426).disposition, .waitForAppUpdate)
        XCTAssertEqual(classify(429).disposition, .retry)
        XCTAssertEqual(classify(500).disposition, .retry)
        XCTAssertEqual(classify(502).disposition, .retry)
        XCTAssertEqual(classify(503).disposition, .retry)
    }

    func testServerRetryableFlagOverridesTheStatusClass() {
        let inProgress = classify(409, body: ["success": false, "error": ["code": "OPERATION_IN_PROGRESS", "message": "busy", "retryable": true]])
        XCTAssertEqual(inProgress.code, "OPERATION_IN_PROGRESS")
        XCTAssertEqual(inProgress.serverRetryable, true)
        XCTAssertEqual(inProgress.disposition, .retry)

        let permanent500 = classify(500, body: ["success": false, "error": ["code": "DATA_CORRUPT", "message": "no", "retryable": false]])
        XCTAssertEqual(permanent500.disposition, .needsAttention)
    }

    func testCanonicalEnvelopeFieldsAreExtracted() {
        let error = classify(422, body: [
            "success": false,
            "message": "Validation failed.",
            "error": ["code": "VALIDATION_FAILED", "message": "Validation failed.", "retryable": false],
            "errors": ["checklist_type": ["The selected checklist type is invalid."]],
            "request_id": "srv-req-77",
        ])
        XCTAssertEqual(error.code, "VALIDATION_FAILED")
        XCTAssertEqual(error.message, "Validation failed.")
        XCTAssertEqual(error.validationErrors["checklist_type"], ["The selected checklist type is invalid."])
        XCTAssertEqual(error.requestId, "srv-req-77", "body request_id wins over the header")
        XCTAssertTrue(error.isValidationFailure)
    }

    func testLegacyErrorCodeKeyIsStillRead() {
        let error = classify(409, body: ["success": false, "error_code": "CHECKLIST_ALREADY_SUBMITTED", "message": "exists", "status": 409])
        XCTAssertEqual(error.code, "CHECKLIST_ALREADY_SUBMITTED")
        XCTAssertEqual(error.message, "exists")
    }

    func testTransportFailuresMapFromURLErrorCodesAndAlwaysRetry() {
        func t(_ code: Int) -> APIError {
            APIErrorClassifier.transportError(from: NSError(domain: NSURLErrorDomain, code: code, userInfo: nil))
        }
        XCTAssertEqual(t(NSURLErrorNotConnectedToInternet).transport, .offline)
        XCTAssertEqual(t(NSURLErrorCannotFindHost).transport, .dns)
        XCTAssertEqual(t(NSURLErrorDNSLookupFailed).transport, .dns)
        XCTAssertEqual(t(NSURLErrorTimedOut).transport, .timeout)
        XCTAssertEqual(t(NSURLErrorNetworkConnectionLost).transport, .connectionLost)
        XCTAssertEqual(t(NSURLErrorCannotConnectToHost).transport, .cannotConnect)
        XCTAssertEqual(t(NSURLErrorSecureConnectionFailed).transport, .tls)
        XCTAssertEqual(t(NSURLErrorCancelled).transport, .cancelled)
        XCTAssertEqual(t(-12345).transport, .other)

        for code in [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost] {
            XCTAssertEqual(t(code).disposition, .retry)
            XCTAssertEqual(t(code).kind, .transport)
            XCTAssertNil(t(code).statusCode)
        }
        let nonURL = APIErrorClassifier.transportError(from: NSError(domain: "Other", code: 5, userInfo: nil))
        XCTAssertEqual(nonURL.transport, .other)
    }

    func testDecodingFailureRetriesBecauseOperationsAreIdempotent() {
        let error = APIErrorClassifier.decodingFailure(statusCode: 200, headers: ["x-request-id": "lower-case-header"], detail: "html")
        XCTAssertEqual(error.kind, .decoding)
        XCTAssertEqual(error.disposition, .retry)
        XCTAssertEqual(error.requestId, "lower-case-header")
    }

    func testInvalidRequestNeedsAttention() {
        XCTAssertEqual(APIError.invalidRequest("bad payload").disposition, .needsAttention)
    }

    func testNSErrorBridgingCarriesRealStatusAndCodeInsteadOfFabricated401() {
        let http = classify(422) as NSError
        XCTAssertEqual(http.domain, "ai.kabba.api")
        XCTAssertEqual(http.code, 422)
        XCTAssertEqual(http.userInfo["kabba.code"] as? String, "VALIDATION_FAILED")

        let offline = APIError.transport(.offline) as NSError
        XCTAssertEqual(offline.code, -1009)
        XCTAssertNotEqual(offline.code, 401)
        XCTAssertEqual(offline.userInfo["kabba.retryable"] as? Bool, true)
        XCTAssertFalse(offline.localizedDescription.isEmpty)
    }

    func testEmployeeMessagesNeverLeadWithRawStatusCodes() {
        XCTAssertFalse(classify(500).employeeMessage.contains("500"))
        XCTAssertFalse(APIError.transport(.offline).employeeMessage.contains("1009"))
        XCTAssertTrue(classify(401).employeeMessage.lowercased().contains("sign in"))
    }
}
