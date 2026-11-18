//
//  DispatchWakeTests.swift
//  Dispatch offline Phase 2 — installation registration for silent Dispatch
//  wakes, and recognising a Dispatch wake among incoming pushes.
//

import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class DispatchWakeTests: XCTestCase {

    // MARK: - Registration request

    func testRegistrationRequestIsAnAuthenticatedJSONPostOfTheFCMToken() {
        let request = DispatchInstallationRegistration.request(fcmToken: "fcm-token-1", operationId: "op-register-1")

        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "mobile/installations")
        XCTAssertEqual(request.jsonBody, .object(["fcm_token": .string("fcm-token-1")]))
        XCTAssertEqual(request.operationId, "op-register-1")
        XCTAssertTrue(request.attachments.isEmpty)
        // Installation identity is NOT in the body: the client adds X-Device-Id to every request,
        // and the server takes identity only from that header.
        XCTAssertNil(request.jsonBody?["installation_id"])
    }

    func testRegistrationNeedsASessionAndARealToken() {
        XCTAssertTrue(DispatchInstallationRegistration.shouldRegister(fcmToken: "fcm-token-1", hasSession: true))
        XCTAssertFalse(DispatchInstallationRegistration.shouldRegister(fcmToken: "fcm-token-1", hasSession: false))
        XCTAssertFalse(DispatchInstallationRegistration.shouldRegister(fcmToken: nil, hasSession: true))
        XCTAssertFalse(DispatchInstallationRegistration.shouldRegister(fcmToken: "", hasSession: true))
        XCTAssertFalse(DispatchInstallationRegistration.shouldRegister(fcmToken: "   ", hasSession: true))
    }

    func testEveryRegistrationTriggerRegistersAndNoTriggerUnregisters() {
        // Launch, login completion and FCM token refresh all (re)register — the server upserts.
        XCTAssertEqual(Set(DispatchInstallationRegistration.Trigger.allCases),
                       [.launch, .loginCompleted, .tokenRefresh])
        // Logout / user switching never deactivate the Dispatch registration: there is
        // deliberately no unregister request in the contract.
        XCTAssertFalse(DispatchInstallationRegistration.Trigger.allCases.map(\.rawValue).contains { $0.contains("logout") })
    }

    func testTheRegisteredResponseIsReadFromTheSharedEnvelope() throws {
        let body = #"{"success":true,"message":"Installation registered.","data":{"installation_id":"install-A","registered":true,"wake_enabled":false},"request_id":"r"}"#
        let ok = SyncHTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        XCTAssertEqual(DispatchInstallationRegistration.outcome(of: ok), .registered(wakeEnabled: false))

        let validation = SyncHTTPResponse(statusCode: 422, headers: [:], body: Data(#"{"success":false,"message":"A valid X-Device-Id header is required."}"#.utf8))
        XCTAssertEqual(DispatchInstallationRegistration.outcome(of: validation), .rejected(statusCode: 422))

        let unauthorized = SyncHTTPResponse(statusCode: 401, headers: [:], body: nil)
        XCTAssertEqual(DispatchInstallationRegistration.outcome(of: unauthorized), .rejected(statusCode: 401))
    }

    /// Same loader as the other shared-fixture tests (source-relative first, then the test bundle).
    private func fixture(_ name: String) throws -> Data {
        let candidates = [
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).json"),
            Bundle(for: DispatchWakeTests.self).url(forResource: name, withExtension: "json"),
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }
        throw XCTSkip("Fixture \(name).json not synced — run Scripts/sync-contract-fixtures.sh")
    }

    func testTheSharedRegistrationFixtureDecodes() throws {
        let response = SyncHTTPResponse(statusCode: 200, headers: [:], body: try fixture("mobile_installation_registered"))

        XCTAssertEqual(DispatchInstallationRegistration.outcome(of: response), .registered(wakeEnabled: false))
    }

    // MARK: - Recognising a silent Dispatch wake

    func testADispatchWakeIsRecognisedWithItsRevision() {
        let userInfo: [AnyHashable: Any] = [
            "type": "dispatch_changed",
            "dispatch_revision": "abc123",
            "aps": ["content-available": 1],
            "gcm.message_id": "1:23",
        ]

        XCTAssertEqual(DispatchWake.revision(fromPushUserInfo: userInfo), "abc123")
        XCTAssertTrue(DispatchWake.isDispatchWake(userInfo))
    }

    func testOtherPushesAreNotDispatchWakes() {
        XCTAssertNil(DispatchWake.revision(fromPushUserInfo: ["order_unique_id": "ORD-1", "aps": ["alert": "New order"]]))
        XCTAssertFalse(DispatchWake.isDispatchWake(["type": "wait_list_match"]))
        XCTAssertFalse(DispatchWake.isDispatchWake([:]))
    }

    func testAWakeWithoutARevisionIsStillAWake() {
        // The payload is only a hint; reconciliation always reads the live manifest.
        XCTAssertTrue(DispatchWake.isDispatchWake(["type": "dispatch_changed"]))
        XCTAssertEqual(DispatchWake.revision(fromPushUserInfo: ["type": "dispatch_changed"]), "")
    }

    func testAWakeIsNeverVisibleAndReportsTheReconciliation() {
        // Handling a Dispatch wake never touches the badge or presents anything. Since Phase 3
        // it reconciles and reports newData / noData / failed from that reconciliation.
        XCTAssertEqual(DispatchWake.handling, .init(adjustsBadge: false, presentsUI: false, reportsReconciliationResult: true))
    }

    // MARK: - Phase 3: wake → reconciliation trigger

    func testAWakeBecomesAReconciliationTriggerCarryingItsRevision() {
        let revision = String(repeating: "a", count: 64)
        XCTAssertEqual(DispatchWake.trigger(fromPushUserInfo: ["type": "dispatch_changed", "dispatch_revision": revision]),
                       .wake(revision: revision))
        XCTAssertEqual(DispatchWake.trigger(fromPushUserInfo: ["type": "dispatch_changed"]), .wake(revision: nil),
                       "a hint without a revision still reconciles")
        XCTAssertNil(DispatchWake.trigger(fromPushUserInfo: ["type": "order_update"]))
    }

    // MARK: - Phase 3: the background completion handler

    private final class ManualClock {
        var scheduled: [(TimeInterval, () -> Void)] = []
        func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) { scheduled.append((delay, work)) }
        func fire() { scheduled.forEach { $0.1() } }
    }

    func testTheCompletionHandlerIsCalledExactlyOnceWithTheReconciliationResult() {
        let clock = ManualClock()
        var delivered: [DispatchOfflineBackgroundResult] = []
        let completion = DispatchWakeCompletion(deadline: DispatchWake.backgroundDeadline, schedule: clock.schedule) { delivered.append($0) }

        completion.finish(.newData)
        completion.finish(.failed)
        clock.fire()

        XCTAssertEqual(delivered, [.newData])
        XCTAssertEqual(clock.scheduled.first?.0, 25)
    }

    func testTheDeadlineAnswersFailedWhenNothingChangedYet() {
        let clock = ManualClock()
        var delivered: [DispatchOfflineBackgroundResult] = []
        let completion = DispatchWakeCompletion(deadline: 25, schedule: clock.schedule) { delivered.append($0) }

        clock.fire()           // iOS is about to suspend us
        completion.finish(.noData)

        XCTAssertEqual(delivered, [.failed])
    }

    func testTheDeadlineAnswersNewDataWhenACommitAlreadyChangedTheSet() {
        let clock = ManualClock()
        var delivered: [DispatchOfflineBackgroundResult] = []
        let completion = DispatchWakeCompletion(deadline: 25, schedule: clock.schedule) { delivered.append($0) }

        completion.noteChanged() // the first batch committed before the deadline
        clock.fire()

        XCTAssertEqual(delivered, [.newData])
    }
}
