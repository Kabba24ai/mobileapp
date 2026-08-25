//
//  TestSupport.swift
//  KabbaSyncCoreTests
//
//  Shared doubles for the Sync Engine core tests. Runs under SwiftPM
//  (`swift test`, @testable import) and under the direct-swiftc runner
//  (Scripts/test-sync-core.sh, single module — no import needed).
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Scripted HTTP client: hands back queued results in order, then `defaultResult`.
/// Records every request so tests can assert operation ids and ordering.
final class FakeSyncHTTPClient: SyncHTTPClient {
    private let lock = NSLock()
    private var script: [SyncHTTPResult] = []
    private(set) var recorded: [SyncHTTPRequest] = []
    var defaultResult: SyncHTTPResult = .failure(APIError.transport(.offline, description: "fake: offline"))
    /// Optional per-request delay to simulate latency (seconds).
    var latency: TimeInterval = 0

    func enqueue(_ results: SyncHTTPResult...) {
        lock.withLock { script.append(contentsOf: results) }
    }

    func perform(_ request: SyncHTTPRequest, completion: @escaping (SyncHTTPResult) -> Void) {
        let result: SyncHTTPResult = lock.withLock {
            recorded.append(request)
            return script.isEmpty ? defaultResult : script.removeFirst()
        }
        if latency > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + latency) { completion(result) }
        } else {
            completion(result)
        }
    }

    var requestCount: Int { lock.withLock { recorded.count } }
}

/// Minimal handler for a JSON operation type.
struct TestOperationHandler: SyncOperationHandler {
    static let type = "test.operation"
    var operationType: String { TestOperationHandler.type }
    var authenticated: () -> Bool = { true }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard authenticated() else { throw SyncHandlerError.notAuthenticated("no session") }
        guard var body = operation.payload.objectValue else { throw SyncHandlerError.invalidPayload("payload must be an object") }
        body["operation_id"] = .string(operation.id)
        return SyncHTTPRequest(method: "POST",
                               path: "test/operation",
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id)
    }
}

enum Fixtures {
    static func tempDirectory(_ name: String = #function) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KabbaSyncCoreTests", isDirectory: true)
            .appendingPathComponent(name.replacingOccurrences(of: "()", with: "") + "-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    static func ok(_ body: [String: Any] = ["success": true, "message": "ok", "data": [:], "request_id": "srv-req-0001"],
                   status: Int = 200,
                   headers: [String: String] = ["X-Request-Id": "srv-req-0001"]) -> SyncHTTPResult {
        .response(SyncHTTPResponse(statusCode: status, headers: headers, body: json(body)))
    }

    static func failure(_ status: Int, code: String? = nil, retryable: Bool? = nil, message: String = "failed") -> SyncHTTPResult {
        var error: [String: Any] = ["code": code ?? "ERR", "message": message]
        if let r = retryable { error["retryable"] = r }
        let body: [String: Any] = ["success": false, "message": message, "error": error, "errors": [String: Any](), "request_id": "srv-req-fail"]
        return .response(SyncHTTPResponse(statusCode: status, headers: ["X-Request-Id": "srv-req-fail"], body: json(body)))
    }

    static let payload: JSONValue = .object([
        "order_product_unique_id": .string("ORD-SCH-TEST-0001"),
        "checklist_type": .string("delivery"),
        "equipment_driver_status": .string("Ready to Go"),
    ])
}

extension XCTestCase {
    /// Polls until `condition` is true or the timeout passes. The engine runs on its own
    /// serial queue, so tests observe it by polling its thread-safe accessors.
    @discardableResult
    func waitUntil(timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line,
                   _ description: String = "condition", _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
        return false
    }

    func makeEngine(store: SyncOperationStore,
                    client: FakeSyncHTTPClient,
                    handler: SyncOperationHandler = TestOperationHandler(),
                    backoff: [TimeInterval] = [0.05]) -> SyncEngine {
        SyncEngine(store: store, httpClient: client, handlers: [handler],
                   policy: SyncRetryPolicy(backoffSchedule: backoff))
    }
}
