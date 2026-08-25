import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class SyncResponseInterpreterTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func interpret(_ status: Int, body: [String: Any]?, headers: [String: String] = [:]) -> SyncOutcome {
        SyncResponseInterpreter.interpret(SyncHTTPResponse(statusCode: status, headers: headers, body: body.map(Fixtures.json)), now: now)
    }

    func testCanonicalSuccessIsAcknowledgedWithServerTimes() throws {
        let outcome = interpret(200, body: [
            "success": true, "status": true,
            "data": ["server_received_at": "2026-08-25T17:40:12-05:00", "captured_at": "2026-08-25T14:14:03-05:00"],
            "request_id": "srv-1",
        ])
        guard case .acknowledged(let ack) = outcome else { return XCTFail("expected acknowledgment, got \(outcome)") }
        XCTAssertEqual(ack.statusCode, 200)
        XCTAssertEqual(ack.requestId, "srv-1")
        XCTAssertFalse(ack.replayed)
        XCTAssertEqual(ack.acknowledgedAt, now)
        XCTAssertEqual(ack.serverReceivedAt, KabbaISO8601.date(from: "2026-08-25T17:40:12-05:00"))
        XCTAssertEqual(ack.data?["captured_at"]?.stringValue, "2026-08-25T14:14:03-05:00")
    }

    func testReplayedAcknowledgmentIsRecognisedFromHeaderOrBody() {
        if case .acknowledged(let ack) = interpret(200, body: ["success": true], headers: ["X-Idempotent-Replay": "true"]) {
            XCTAssertTrue(ack.replayed)
        } else { XCTFail() }
        if case .acknowledged(let ack) = interpret(200, body: ["success": true, "replayed": true]) {
            XCTAssertTrue(ack.replayed)
        } else { XCTFail() }
    }

    func testLegacyStatusTrueBodyIsAcknowledged() {
        guard case .acknowledged = interpret(200, body: ["status": true, "message": "Driver checklist updated successfully."]) else {
            return XCTFail("legacy {status:true} must acknowledge")
        }
    }

    func testTwoHundredWithDeclaredFailureIsARejection() {
        let outcome = interpret(200, body: ["success": "0", "message": "Checklist already exists"])
        guard case .failed(let error) = outcome else { return XCTFail("expected failure") }
        XCTAssertEqual(error.statusCode, 200)
        XCTAssertEqual(error.code, "DECLARED_FAILURE")
        XCTAssertEqual(error.message, "Checklist already exists")
        XCTAssertEqual(error.disposition, .needsAttention)
    }

    func testNonSuccessStatusIsClassifiedByStatus() {
        guard case .failed(let e422) = interpret(422, body: ["success": false, "error": ["code": "VALIDATION_FAILED", "message": "bad", "retryable": false]]) else { return XCTFail() }
        XCTAssertEqual(e422.disposition, .needsAttention)
        guard case .failed(let e503) = interpret(503, body: nil) else { return XCTFail() }
        XCTAssertEqual(e503.disposition, .retry)
        guard case .failed(let e401) = interpret(401, body: ["message": "Unauthenticated."]) else { return XCTFail() }
        XCTAssertEqual(e401.disposition, .waitForAuthentication)
    }

    func testEmptyTwoOhFourIsAcknowledgedButHtmlTwoHundredIsADecodingFailure() {
        guard case .acknowledged = interpret(204, body: nil) else { return XCTFail("204 acknowledges") }
        let html = SyncResponseInterpreter.interpret(SyncHTTPResponse(statusCode: 200, headers: [:], body: Data("<html>login</html>".utf8)), now: now)
        guard case .failed(let error) = html else { return XCTFail("html is not an acknowledgment") }
        XCTAssertEqual(error.kind, .decoding)
        XCTAssertEqual(error.disposition, .retry)
    }
}
