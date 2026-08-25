import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class APIEnvelopeTests: XCTestCase {

    private func env(_ body: [String: Any]) -> APIEnvelope {
        APIEnvelope.parse(Fixtures.json(body))!
    }

    func testCanonicalSuccess() {
        let e = env(["success": true, "message": "ok", "data": ["x": 1], "request_id": "r1"])
        XCTAssertEqual(e.declaredSuccess, true)
        XCTAssertEqual(e.message, "ok")
        XCTAssertEqual(e.data?["x"]?.intValue, 1)
        XCTAssertEqual(e.requestId, "r1")
        XCTAssertFalse(e.replayed)
    }

    func testLegacySuccessStringAndLegacyStatusBool() {
        XCTAssertEqual(env(["success": "1"]).declaredSuccess, true)
        XCTAssertEqual(env(["success": "0"]).declaredSuccess, false)
        XCTAssertEqual(env(["success": 1]).declaredSuccess, true)
        XCTAssertEqual(env(["status": true, "message": "Driver checklist updated successfully."]).declaredSuccess, true)
        XCTAssertEqual(env(["status": false, "message": "Failed"]).declaredSuccess, false)
        XCTAssertEqual(env(["status": "1"]).declaredSuccess, true)
    }

    func testNumericHttpLikeStatusIsNotASuccessFlag() {
        // ApiResponseHelper::error() emits {success:false, status:404}. success wins; and a bare
        // status:404 must never read as "success".
        XCTAssertEqual(env(["success": false, "status": 404]).declaredSuccess, false)
        XCTAssertNil(env(["status": 404]).declaredSuccess)
        XCTAssertNil(env(["message": "no flags"]).declaredSuccess)
    }

    func testReplayMarkers() {
        let e = env(["success": true, "replayed": true, "original_request_id": "r0", "request_id": "r9"])
        XCTAssertTrue(e.replayed)
        XCTAssertEqual(e.originalRequestId, "r0")
    }

    func testValidationErrorsAcceptListsAndSingleStrings() {
        let e = env(["success": false, "errors": ["a": ["one", "two"], "b": "single"]])
        XCTAssertEqual(e.validationErrors["a"], ["one", "two"])
        XCTAssertEqual(e.validationErrors["b"], ["single"])
    }

    func testNonObjectBodiesAreNotEnvelopes() {
        XCTAssertNil(APIEnvelope.parse(Data("[1,2]".utf8)))
        XCTAssertNil(APIEnvelope.parse(Data("<html>".utf8)))
        XCTAssertNil(APIEnvelope.parse(nil))
    }
}
