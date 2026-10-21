//
//  SyncStatusHostedTests.swift
//  RentnKingHostedTests — MOBILE-QUALITY-01 items 01/02 inside the app: Settings → Sync
//  groups a refused record under "Needs your attention", Sync Now says what it did
//  (including when nothing can be sent), and the review screen removes exactly ONE
//  record after a confirmation that never claims Kabba has it.
//

import XCTest
@testable import RentnKing

private final class RefusingClient: SyncHTTPClient {
    /// Results by order product: a refusal for the reassigned line, offline for the rest.
    var refuse: Set<String> = []
    func perform(_ request: SyncHTTPRequest, completion: @escaping (SyncHTTPResult) -> Void) {
        let product = request.jsonBody?["order_product_unique_id"]?.stringValue ?? ""
        if refuse.contains(product) {
            let error: [String: Any] = ["code": "DISPATCH_ASSIGNMENT_CHANGED", "message": "This dispatch is no longer assigned to you.", "retryable": false]
            let body: [String: Any] = ["success": false, "message": error["message"]!, "error": error, "request_id": "mq01-409"]
            completion(.response(SyncHTTPResponse(statusCode: 409, headers: [:], body: try! JSONSerialization.data(withJSONObject: body))))
        } else {
            completion(.failure(APIError.transport(.offline, description: "hosted: offline")))
        }
    }
}

private struct StepHandler: SyncOperationHandler {
    let operationType = EffectiveFieldState.driverChecklistType
    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        SyncHTTPRequest(method: "POST", path: "test/step", headers: ["X-Operation-Id": operation.id],
                        jsonBody: operation.payload, operationId: operation.id)
    }
}

final class SyncStatusHostedTests: XCTestCase {

    private var dir: URL!
    private var client: RefusingClient!
    private var engine: SyncEngine!
    private var log: SyncRemovedRecordLog!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("SyncStatusHostedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        client = RefusingClient()
        client.refuse = ["ORD-SCH-REASSIGNED"]
        engine = SyncEngine(store: try FileSyncOperationStore(rootDirectory: dir), httpClient: client,
                            handlers: [StepHandler()], policy: SyncRetryPolicy(backoffSchedule: [60]))
        log = SyncRemovedRecordLog(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func poll(_ description: String, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }

    private func step(_ product: String, title: String) throws -> SyncOperation {
        try engine.enqueue(type: EffectiveFieldState.driverChecklistType,
                           payload: .object(["order_product_unique_id": .string(product), "checklist_type": .string("delivery")]),
                           identity: SyncBusinessIdentity(orderUniqueId: "ORD-MQ01", orderProductUniqueId: product),
                           capturedAt: Date(), displayTitle: title)
    }

    private func labels(in view: UIView) -> [UILabel] {
        var found: [UILabel] = []
        if let label = view as? UILabel { found.append(label) }
        for sub in view.subviews { found += labels(in: sub) }
        return found
    }

    private func find<T: UIView>(_ type: T.Type, id: String, in view: UIView) -> T? {
        if let match = view as? T, match.accessibilityIdentifier == id { return match }
        for sub in view.subviews { if let hit = find(type, id: id, in: sub) { return hit } }
        return nil
    }

    // MARK: -

    func testARefusedRecordIsGroupedForAttentionAndSyncNowSaysWhatItDid() throws {
        let refused = try step("ORD-SCH-REASSIGNED", title: "Driver checklist · On My Way (delivery)")
        let waiting = try step("ORD-SCH-OTHER", title: "Driver checklist · Arrived (delivery)")
        poll("refusal parked, other attempted") {
            engine.operation(id: refused.id)?.state == .needsAttention && (engine.operation(id: waiting.id)?.attempts.attemptCount ?? 0) >= 1
        }

        let screen = SyncStatusViewController(theme: .system, engine: { [engine] in engine }, removedRecords: { [log] in log })
        let nav = UINavigationController(rootViewController: screen)
        nav.loadViewIfNeeded()
        screen.loadViewIfNeeded()
        screen.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        screen.view.layoutIfNeeded()

        let table = try XCTUnwrap(screen.view.subviews.compactMap { $0 as? UITableView }.first)
        XCTAssertEqual(table.numberOfSections, 2, "attention + waiting")
        let attentionHeader = screen.tableView(table, viewForHeaderInSection: 0).map { labels(in: $0).map { $0.text ?? "" } } ?? []
        XCTAssertEqual(attentionHeader, ["NEEDS YOUR ATTENTION (1)"])
        let row = screen.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0))
        let rowText = row.textLabel?.attributedText?.string ?? ""
        XCTAssertTrue(rowText.contains("Kabba refused this · This job was reassigned"), rowText)
        XCTAssertFalse(rowText.lowercased().contains("synced"), "a refused record is never called synced")

        // Sync Now: the parked record is not resent; the waiting one tries and stays offline.
        let item = try XCTUnwrap(screen.navigationItem.rightBarButtonItem)
        UIApplication.shared.sendAction(item.action!, to: item.target, from: nil, for: nil)
        XCTAssertEqual(item.title, "Syncing…")
        XCTAssertFalse(item.isEnabled)
        let report = try XCTUnwrap(find(UILabel.self, id: "sync.status.report", in: screen.view))
        poll("report shown") { (report.attributedText?.string ?? report.text ?? "").hasPrefix("Couldn't reach Kabba.") }
        let text = report.attributedText?.string ?? ""
        XCTAssertTrue(text.contains("1 record waiting for a connection."), text)
        XCTAssertTrue(text.contains("1 record needs your attention. Sync Now does not resend it — a person decides."), text)
        XCTAssertEqual(item.title, "Sync Now")
        XCTAssertTrue(item.isEnabled)
        XCTAssertEqual(engine.operation(id: refused.id)?.attempts.attemptCount, 1, "Sync Now never resends a refusal")
    }

    func testSyncNowWithOnlyRefusedRecordsExplainsThatNothingCanBeSent() throws {
        let refused = try step("ORD-SCH-REASSIGNED", title: "Driver checklist · On My Way (delivery)")
        poll("parked") { engine.operation(id: refused.id)?.state == .needsAttention }

        let screen = SyncStatusViewController(theme: .system, engine: { [engine] in engine }, removedRecords: { [log] in log })
        screen.loadViewIfNeeded()
        let item = try XCTUnwrap(screen.navigationItem.rightBarButtonItem)
        UIApplication.shared.sendAction(item.action!, to: item.target, from: nil, for: nil)
        let report = try XCTUnwrap(find(UILabel.self, id: "sync.status.report", in: screen.view))
        poll("report shown") { (report.attributedText?.string ?? "").hasPrefix("Nothing new to send.") }
    }

    func testReviewRemovesOnlyThatRecordAfterAnHonestConfirmation() throws {
        let refused = try step("ORD-SCH-REASSIGNED", title: "Driver checklist · On My Way (delivery)")
        let waiting = try step("ORD-SCH-OTHER", title: "Driver checklist · Arrived (delivery)")
        poll("parked") { engine.operation(id: refused.id)?.state == .needsAttention }

        let op = try XCTUnwrap(engine.operation(id: refused.id))
        let message = SyncRecordReviewViewController.removalMessage(op: op, review: SyncRecordReview.of(op))
        XCTAssertTrue(message.hasPrefix("Kabba refused this record, so none of it is stored on Kabba."), message)
        XCTAssertTrue(message.contains("driver step"), message)
        XCTAssertFalse(message.lowercased().contains("synced with"), message)

        var removedIds: [String] = []
        let review = SyncRecordReviewViewController(operationId: refused.id, theme: .system, engine: { [engine] in engine },
                                                    remove: { [engine, log] id in
                                                        removedIds.append(id)
                                                        try KabbaSync.removeRecord(id, engine: engine, log: log)
                                                    })
        review.loadViewIfNeeded()
        XCTAssertNotNil(find(UIButton.self, id: "sync.review.remove", in: review.view))
        XCTAssertNotNil(find(UIButton.self, id: "sync.review.retry", in: review.view))
        let visible = labels(in: review.view).compactMap(\.text).joined(separator: "\n")
        XCTAssertTrue(visible.contains("This job was reassigned"), visible)
        XCTAssertTrue(visible.contains("What you can do"), visible)

        try KabbaSync.removeRecord(refused.id, engine: engine, log: log)
        XCTAssertNil(engine.operation(id: refused.id))
        XCTAssertNotNil(engine.operation(id: waiting.id), "the other record is untouched")
        XCTAssertEqual(log.entries().map(\.operationId), [refused.id])
        XCTAssertEqual(log.entries().first?.errorCode, "DISPATCH_ASSIGNMENT_CHANGED")
        XCTAssertTrue(removedIds.isEmpty, "the seam is only used by the screen's own confirmation")

        // The list now shows the removal trace instead of the record.
        let screen = SyncStatusViewController(theme: .system, engine: { [engine] in engine }, removedRecords: { [log] in log })
        screen.loadViewIfNeeded()
        let table = try XCTUnwrap(screen.view.subviews.compactMap { $0 as? UITableView }.first)
        let headers = (0..<table.numberOfSections).flatMap { s in screen.tableView(table, viewForHeaderInSection: s).map { labels(in: $0).compactMap(\.text) } ?? [] }
        XCTAssertEqual(headers, ["WAITING TO SYNC (1)", "REMOVED FROM THIS PHONE · LAST 30 DAYS"])
    }
}
