//
//  SyncRecordResolutionTests.swift
//  KabbaSyncCoreTests
//
//  MOBILE-QUALITY-01 items 01/02: permanently rejected records are explained,
//  reviewed and removed one at a time by a person; Sync Now reports what it did.
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class SyncRecordResolutionTests: XCTestCase {

    private var dir: URL!
    private var client: FakeSyncHTTPClient!

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
        client = FakeSyncHTTPClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func store() throws -> FileSyncOperationStore { try FileSyncOperationStore(rootDirectory: dir) }

    private func enqueue(_ engine: SyncEngine, product: String = "ORD-SCH-1", title: String = "Driver checklist · On My Way") throws -> SyncOperation {
        try engine.enqueue(type: TestOperationHandler.type,
                           payload: Fixtures.payload,
                           identity: SyncBusinessIdentity(orderUniqueId: "ORD-1", orderProductUniqueId: product),
                           capturedAt: Date(timeIntervalSince1970: 1_790_000_000),
                           displayTitle: title)
    }

    /// Waits for one Sync Now and returns its report.
    private func syncNow(_ engine: SyncEngine) -> SyncPassReport? {
        var report: SyncPassReport?
        engine.syncNow(reason: "test") { report = $0 }
        waitUntil("sync now report") { report != nil }
        return report
    }

    // MARK: - The five records on the owner's phone

    func testAReassignedDispatchIsExplainedAndMayBeRetriedOnceAssignedBack() throws {
        client.enqueue(Fixtures.failure(409, code: "DISPATCH_ASSIGNMENT_CHANGED", retryable: false,
                                        message: "This dispatch is no longer assigned to you."))
        let engine = makeEngine(store: try store(), client: client)
        let op = try enqueue(engine)
        waitUntil { engine.operation(id: op.id)?.state == .needsAttention }

        let review = SyncRecordReview.of(engine.operation(id: op.id)!)
        XCTAssertEqual(review.problem, .rejected)
        XCTAssertEqual(review.explanation?.headline, "This job was reassigned")
        XCTAssertEqual(review.explanation?.retryMayHelp, true)
        XCTAssertEqual(review.errorCode, "DISPATCH_ASSIGNMENT_CHANGED")
        XCTAssertTrue(review.canRemove)
        XCTAssertTrue(review.canRetry)
        XCTAssertFalse(review.officeSees, "a driver step is not on the office's Mobile Sync Issues list")
    }

    func testAChecklistQuestionMismatchSaysTheSameCopyWillNeverBeAccepted() {
        var op = SyncOperation(type: "return_checklist.complete", capturedAt: Date(), payload: .object([
            "answers": .array([
                .object(["question_id": .string("q1"), "answer_id": .string("a1")]),
                .object(["question_id": .string("q2"), "answer_id": .string("a2")]),
                .object(["question_id": .string("q3"), "answer_id": .string("")]),
            ]),
            "end_hours": .string("412"),
            "note": .string("Scratch on drum"),
        ]), assets: [SyncAsset(relativePath: "exec/sig.jpg", mimeType: "image/jpeg", fieldName: "signature_media")],
            displayTitle: "Return checklist · 56\" Single Drum Compactor")
        op.state = .needsAttention
        op.attempts.lastStatusCode = 422
        op.attempts.lastErrorCode = "CHECKLIST_QUESTION_MISMATCH"

        let review = SyncRecordReview.of(op)
        XCTAssertEqual(review.explanation?.retryMayHelp, false)
        XCTAssertTrue(review.explanation?.headline.contains("don't match") == true)
        XCTAssertTrue(review.officeSees, "a terminal checklist rejection is on the office's Mobile Sync Issues list")
        XCTAssertEqual(review.contents.answers, 2, "an unanswered question is not captured work")
        XCTAssertTrue(review.contents.readings)
        XCTAssertTrue(review.contents.note)
        XCTAssertTrue(review.contents.signature)
        XCTAssertEqual(review.contents.summary, "2 checklist answers · hours / fuel readings · a note · a signature")
        XCTAssertEqual(review.removalConsequence, "This phone will show the return checklist as not completed.")
        XCTAssertEqual(review.knowledge, .refused)
    }

    func testEveryKnownServerCodeHasItsOwnExplanationAndUnknownCodesAreNeverCalledAccepted() {
        let codes = ["DISPATCH_ASSIGNMENT_CHANGED", "QUEUE_ASSIGNMENT_CHANGED", "CHECKLIST_QUESTION_MISMATCH", "DELIVERY_DEPARTED",
                     "CHECKLIST_ALREADY_COMPLETED", "CHECKLIST_EXECUTION_SUPERSEDED", "CHECKLIST_NOT_DELIVERED", "REQUIRED_ANSWERS_MISSING",
                     "EQUIPMENT_IS_RENTED", "QUEUE_ITEM_DELIVERED", "QUEUE_AVAILABILITY_BLOCKED", "ORDER_NOT_FOUND", "FORBIDDEN",
                     "MEDIA_TYPE_INVALID", "TERMS_IDENTITY_MISMATCH", "OPERATION_ID_CONFLICT", "ROUTE_RETIRED"]
        let generic = SyncRejectionCatalog.explain(code: "SOMETHING_NEW", statusCode: 422, serverMessage: "Nope.")
        for code in codes {
            XCTAssertNotEqual(SyncRejectionCatalog.explain(code: code, statusCode: 409, serverMessage: nil).headline, generic.headline, code)
        }
        XCTAssertEqual(generic.headline, "Kabba refused this record")
        XCTAssertEqual(generic.detail, "Nope.", "an unknown refusal shows Kabba's own words")
        XCTAssertFalse(generic.retryMayHelp)
        let local = SyncRejectionCatalog.explain(code: nil, statusCode: nil, serverMessage: "No handler")
        XCTAssertEqual(local.headline, "This phone couldn't send this record")
        // Lower-case / padded codes are the same code.
        XCTAssertEqual(SyncRejectionCatalog.explain(code: " dispatch_assignment_changed ", statusCode: 409, serverMessage: nil).headline,
                       "This job was reassigned")
    }

    func testProblemKindsSeparateRetryableFromPermanent() {
        func op(_ state: SyncState, _ disposition: RetryDisposition?, transport: TransportFailure? = nil) -> SyncOperation {
            var o = SyncOperation(type: "x", capturedAt: Date(), payload: .object([:]))
            o.state = state
            o.attempts.lastDisposition = disposition
            o.attempts.lastTransportFailure = transport
            return o
        }
        XCTAssertEqual(SyncRecordProblem.of(op(.pending, nil)), .waiting)
        XCTAssertEqual(SyncRecordProblem.of(op(.pending, .retry, transport: .offline)), .waitingForConnection)
        XCTAssertEqual(SyncRecordProblem.of(op(.pending, .retry)), .temporaryFailure)
        XCTAssertEqual(SyncRecordProblem.of(op(.pending, .waitForAuthentication)), .paused)
        var refused = op(.needsAttention, .needsAttention)
        refused.attempts.lastStatusCode = 409
        XCTAssertEqual(SyncRecordProblem.of(refused), .rejected)
        XCTAssertEqual(SyncRecordProblem.of(op(.needsAttention, .needsAttention)), .parkedOnPhone, "no answer from Kabba")
        XCTAssertEqual(SyncRecordProblem.of(op(.syncing, nil)), .waiting)
        XCTAssertEqual(SyncRecordProblem.of(op(.synced, nil)), .none)
        XCTAssertEqual(SyncRecordProblem.of(op(.superseded, nil)), .none)
    }

    func testMediaAndLicenseContentsAreCountedFromTheirFiles() {
        let media = SyncOperation(type: "delivery_media.upload", capturedAt: Date(), payload: .object([:]), assets: [
            SyncAsset(relativePath: "p/1.jpg", mimeType: "image/jpeg", fieldName: "media"),
            SyncAsset(relativePath: "p/2.mov", mimeType: "video/quicktime", fieldName: "media"),
        ])
        XCTAssertEqual(SyncRecordContents.of(media).photos, 1)
        XCTAssertEqual(SyncRecordContents.of(media).videos, 1)

        let license = SyncOperation(type: "license_media.upload", capturedAt: Date(),
                                    payload: .object(["license_expiry_date": .string("2028-04-01"), "side": .string("front")]),
                                    assets: [SyncAsset(relativePath: "license-ORD/1.jpg", mimeType: "image/jpeg", fieldName: "media")])
        let c = SyncRecordContents.of(license)
        XCTAssertTrue(c.licenseImage)
        XCTAssertEqual(c.photos, 0, "a license image is not a delivery photo")
        XCTAssertEqual(c.summary, "a driver's license image and expiration date")
        XCTAssertTrue(c.holdsCapturedWork)

        let tap = SyncOperation(type: "manual_dispatch.update_status", capturedAt: Date(), payload: .object(["status": .string("Completed")]))
        XCTAssertFalse(SyncRecordContents.of(tap).holdsCapturedWork)
        XCTAssertEqual(SyncRecordContents.of(tap).summary, "")
    }

    // MARK: - Removal

    func testRemovingOneRejectedRecordLeavesEveryOtherRecordAlone() throws {
        client.enqueue(Fixtures.failure(409, code: "DISPATCH_ASSIGNMENT_CHANGED", retryable: false))
        let engine = makeEngine(store: try store(), client: client)
        let rejected = try enqueue(engine, product: "ORD-SCH-A")
        waitUntil { engine.operation(id: rejected.id)?.state == .needsAttention }

        // Another record for ANOTHER line stays pending (offline) — untouched by the removal.
        let other = try enqueue(engine, product: "ORD-SCH-B")
        waitUntil { engine.operation(id: other.id)?.attempts.attemptCount == 1 }

        let removed = try engine.remove(operationId: rejected.id)
        XCTAssertEqual(removed.id, rejected.id)
        XCTAssertEqual(removed.state, .needsAttention, "the caller learns what was removed")
        XCTAssertNil(engine.operation(id: rejected.id))
        XCTAssertNil(try store().load(id: rejected.id), "gone from disk too")
        let survivor = engine.operation(id: other.id)
        XCTAssertEqual(survivor?.state, .pending)
        XCTAssertEqual(survivor?.payload, Fixtures.payload)
        XCTAssertNotNil(try store().load(id: other.id))
    }

    func testHistoryAndInFlightRecordsCannotBeRemoved() throws {
        let s = try store()
        var synced = SyncOperation(type: TestOperationHandler.type, capturedAt: Date(), payload: Fixtures.payload)
        synced.state = .synced
        var superseded = SyncOperation(type: TestOperationHandler.type, capturedAt: Date(), payload: Fixtures.payload)
        superseded.state = .superseded
        try s.save(synced)
        try s.save(superseded)
        let engine = makeEngine(store: s, client: client)

        XCTAssertThrowsError(try engine.remove(operationId: synced.id)) { error in
            XCTAssertEqual(error as? SyncEngineError, .notRemovable(synced.id, .synced))
        }
        XCTAssertThrowsError(try engine.remove(operationId: superseded.id))
        XCTAssertThrowsError(try engine.remove(operationId: "missing"))
        XCTAssertNotNil(engine.operation(id: synced.id))
        XCTAssertNotNil(engine.operation(id: superseded.id))

        // In flight (a background transfer holds it): could still land → not removable.
        var held = SyncOperation(type: TestOperationHandler.type, capturedAt: Date(), payload: Fixtures.payload)
        held.state = .pending
        try s.save(held)
        let engine2 = makeEngine(store: try store(), client: client)
        engine2.holdForExternalTransfer(operationId: held.id)
        waitUntil { engine2.operation(id: held.id)?.state == .syncing }
        XCTAssertThrowsError(try engine2.remove(operationId: held.id))
        XCTAssertEqual(engine2.operation(id: held.id)?.state, .syncing)
    }

    func testRemovingARecordDeletesOnlyFilesNoOtherRecordUses() throws {
        let s = try store()
        let own = try SyncAssetWriter.store(Data([1, 2, 3]), in: s.assetsDirectory, scope: "exec-1",
                                            fieldName: "signature_media", mimeType: "image/jpeg", fileExtension: "jpg")
        let shared = try SyncAssetWriter.store(Data([4, 5, 6]), in: s.assetsDirectory, scope: "exec-1",
                                               fieldName: "media", mimeType: "image/jpeg", fileExtension: "jpg")
        var rejected = SyncOperation(type: TestOperationHandler.type, capturedAt: Date(), payload: Fixtures.payload, assets: [own, shared])
        rejected.state = .needsAttention
        var keeper = SyncOperation(type: TestOperationHandler.type, capturedAt: Date(), payload: Fixtures.payload, assets: [shared])
        keeper.state = .needsAttention
        try s.save(rejected)
        try s.save(keeper)
        let engine = makeEngine(store: s, client: client)

        try engine.remove(operationId: rejected.id)

        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: SyncAssetWriter.url(of: own, in: s.assetsDirectory).path), "its own file is deleted")
        XCTAssertTrue(fm.fileExists(atPath: SyncAssetWriter.url(of: shared, in: s.assetsDirectory).path),
                      "a file another record still uses is kept")
        XCTAssertEqual(engine.operation(id: keeper.id)?.assets, [shared])
    }

    func testPruningAnOldSyncedRecordAlsoRemovesItsLeftoverSignatureFile() throws {
        let s = try store()
        let signature = try SyncAssetWriter.store(Data([9]), in: s.assetsDirectory, scope: "exec-2",
                                                  fieldName: "signature_media", mimeType: "image/jpeg", fileExtension: "jpg")
        var synced = SyncOperation(type: "delivery_checklist.complete", capturedAt: Date(), payload: Fixtures.payload, assets: [signature])
        synced.state = .synced
        synced.acknowledgment = SyncAcknowledgment(acknowledgedAt: Date(timeIntervalSinceNow: -30 * 86_400), statusCode: 200,
                                                   requestId: nil, replayed: false, serverReceivedAt: nil, data: nil)
        try s.save(synced)
        let engine = makeEngine(store: s, client: client)

        engine.pruneSynced()
        waitUntil { engine.operation(id: synced.id) == nil }
        XCTAssertFalse(FileManager.default.fileExists(atPath: SyncAssetWriter.url(of: signature, in: s.assetsDirectory).path))
    }

    // MARK: - Removed-record trace

    func testTheRemovalTraceKeepsCountsNotContentAndExpires() throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let log = SyncRemovedRecordLog(directory: dir, clock: { now })
        var op = SyncOperation(type: "return_checklist.complete", capturedAt: now.addingTimeInterval(-3600), payload: .object([
            "answers": .array([.object(["question_id": .string("q1"), "answer_id": .string("a1")])]),
            "note": .string("Customer says the drum was already scratched"),
        ]), displayTitle: "Return checklist · Compactor")
        op.state = .needsAttention
        op.attempts.lastErrorCode = "CHECKLIST_QUESTION_MISMATCH"
        op.attempts.lastRequestId = "req-1"

        try log.append(SyncRemovedRecord.of(op, removedAt: now, byUserId: "7", byName: "Gary J"))
        let entry = try XCTUnwrap(log.entries().first)
        XCTAssertEqual(entry.operationId, op.id)
        XCTAssertEqual(entry.contentsSummary, "1 checklist answer · a note")
        XCTAssertEqual(entry.removedByName, "Gary J")
        XCTAssertEqual(entry.errorCode, "CHECKLIST_QUESTION_MISMATCH")

        let onDisk = try String(contentsOf: dir.appendingPathComponent("removed-records.json"))
        XCTAssertFalse(onDisk.contains("scratched"), "the note itself is never kept")
        XCTAssertFalse(onDisk.contains("a1"), "nor the answers")

        // A fresh log instance (relaunch) reads the same trace; after 30 days it is gone.
        XCTAssertEqual(SyncRemovedRecordLog(directory: dir, clock: { now }).entries().count, 1)
        now = now.addingTimeInterval(31 * 86_400)
        XCTAssertTrue(log.entries().isEmpty)
    }

    // MARK: - Sync Now

    func testSyncNowWithOnlyRejectedRecordsSaysSoAndResendsNothing() throws {
        client.enqueue(Fixtures.failure(409, code: "DISPATCH_ASSIGNMENT_CHANGED", retryable: false),
                       Fixtures.failure(422, code: "CHECKLIST_QUESTION_MISMATCH", retryable: false))
        let engine = makeEngine(store: try store(), client: client)
        let a = try enqueue(engine, product: "A")
        let b = try enqueue(engine, product: "B")
        waitUntil { engine.operation(id: a.id)?.state == .needsAttention && engine.operation(id: b.id)?.state == .needsAttention }
        let sentBefore = client.requestCount

        let report = try XCTUnwrap(syncNow(engine))
        XCTAssertEqual(client.requestCount, sentBefore, "Sync Now never resends a permanent rejection")
        XCTAssertTrue(report.nothingToSend)
        XCTAssertEqual(report.needsAttention, 2)
        XCTAssertEqual(report.headline, "Nothing new to send.")
        XCTAssertEqual(report.lines(timeFormatter: { _ in "" }).last,
                       "2 records need your attention. Sync Now does not resend them — a person decides. Tap a record to review it.")
    }

    func testSyncNowReportsWhatWasSentAndWhatKabbaRefusedDuringThisPass() throws {
        let engine = makeEngine(store: try store(), client: client, backoff: [60])      // offline first, no timer retries
        let a = try enqueue(engine, product: "A")
        let b = try enqueue(engine, product: "B")
        waitUntil { engine.operation(id: a.id)?.attempts.attemptCount == 1 && engine.operation(id: b.id)?.attempts.attemptCount == 1 }

        client.enqueue(Fixtures.ok(), Fixtures.failure(409, code: "DISPATCH_ASSIGNMENT_CHANGED", retryable: false))
        let report = try XCTUnwrap(syncNow(engine))
        XCTAssertEqual(report.sent, 1)
        XCTAssertEqual(report.rejectedNow, 1)
        XCTAssertEqual(report.needsAttention, 1)
        XCTAssertEqual(report.waiting, 0)
        XCTAssertEqual(report.headline, "Sent 1 record to Kabba.")
        XCTAssertEqual(report.lines(timeFormatter: { _ in "" }).first, "Kabba refused 1 record during this sync.")
        XCTAssertEqual(engine.operation(id: b.id)?.state, .needsAttention)
    }

    func testSyncNowOfflineSaysTheRecordsAreWaitingForAConnection() throws {
        let engine = makeEngine(store: try store(), client: client, backoff: [60])   // stays offline
        let a = try enqueue(engine, product: "A")
        let b = try enqueue(engine, product: "B")
        waitUntil { engine.operation(id: a.id)?.attempts.attemptCount == 1 && engine.operation(id: b.id)?.attempts.attemptCount == 1 }

        let report = try XCTUnwrap(syncNow(engine))
        XCTAssertEqual(report.sent, 0)
        XCTAssertEqual(report.waitingForConnection, 2, "the record queued behind the failure waits for the same connection")
        XCTAssertEqual(report.stillQueued, 0)
        XCTAssertEqual(report.headline, "Couldn't reach Kabba.")
        XCTAssertNotNil(report.nextRetryAt)
        XCTAssertEqual(report.lines(timeFormatter: { _ in "" }).first,
                       "2 records waiting for a connection. They are saved on this phone and will send automatically.")
    }

    func testSyncNowDuringAServerOutageSaysItRetriesAutomatically() throws {
        client.defaultResult = Fixtures.failure(503, code: "SERVICE_UNAVAILABLE", retryable: true)
        let engine = makeEngine(store: try store(), client: client, backoff: [60])
        let a = try enqueue(engine)
        waitUntil { engine.operation(id: a.id)?.attempts.attemptCount == 1 }

        let report = try XCTUnwrap(syncNow(engine))
        XCTAssertEqual(report.temporaryFailures, 1)
        XCTAssertEqual(report.headline, "Kabba is temporarily unavailable.")
        XCTAssertEqual(report.lines(timeFormatter: { _ in "3:42 PM" }).first,
                       "1 record failed temporarily and will retry automatically (next try 3:42 PM).")
    }

    func testSyncNowWhileSignedOutSaysSendingIsPaused() throws {
        var signedIn = false
        let engine = makeEngine(store: try store(), client: client, handler: TestOperationHandler(authenticated: { signedIn }))
        _ = try enqueue(engine)
        waitUntil { engine.pause == .authentication }

        let report = try XCTUnwrap(syncNow(engine))
        XCTAssertEqual(report.pause, .authentication)
        XCTAssertEqual(report.headline, "Sync is paused — sign in again to send.")
        signedIn = true
    }

    func testSyncNowWithAnEmptyQueueSaysEverythingIsSynced() throws {
        let engine = makeEngine(store: try store(), client: client)
        let report = try XCTUnwrap(syncNow(engine))
        XCTAssertTrue(report.nothingToSend)
        XCTAssertEqual(report.headline, "Nothing waiting to send — everything is synced.")
        XCTAssertTrue(report.lines(timeFormatter: { _ in "" }).isEmpty)
    }

    func testTwoSyncNowCallsDuringOnePassAreBothAnswered() throws {
        client.latency = 0.2
        client.defaultResult = Fixtures.ok()
        let engine = makeEngine(store: try store(), client: client)
        _ = try enqueue(engine)
        var first: SyncPassReport?
        var second: SyncPassReport?
        engine.syncNow(reason: "one") { first = $0 }
        engine.syncNow(reason: "two") { second = $0 }
        waitUntil { first != nil && second != nil }
        XCTAssertEqual(client.requestCount, 1, "the second Sync Now joins the running pass instead of sending twice")
    }

    // MARK: - Capture order survives a relaunch (found while verifying item 05)

    func testRecordsForOneLineQueuedInTheSameSecondAreSentInCaptureOrderAfterARelaunch() throws {
        let offline = makeEngine(store: try store(), client: client, backoff: [60])
        var ids: [String] = []
        for step in 0..<6 {
            ids.append(try offline.enqueue(type: TestOperationHandler.type,
                                           payload: .object(["order_product_unique_id": .string("ORD-SCH-1"), "step": .number(Double(step))]),
                                           identity: SyncBusinessIdentity(orderProductUniqueId: "ORD-SCH-1"),
                                           capturedAt: Date(timeIntervalSince1970: 1_790_000_000)).id)
        }
        waitUntil { offline.operation(id: ids[0])?.attempts.attemptCount == 1 }

        let online = FakeSyncHTTPClient()
        online.defaultResult = Fixtures.ok()
        let relaunched = makeEngine(store: try store(), client: online)
        relaunched.kick(reason: "relaunch", ignoreBackoff: true)
        waitUntil { ids.allSatisfy { relaunched.operation(id: $0)?.state == .synced } }
        XCTAssertEqual(online.recorded.map(\.operationId), ids, "same line → sent in the order captured, never reshuffled by a relaunch")
    }

    func testRecordsStoredWithWholeSecondTimesStillLoad() throws {
        let s = try store()
        let op = SyncOperation(id: "OLD-1", type: TestOperationHandler.type, capturedAt: Date(timeIntervalSince1970: 1_790_000_000),
                               queuedAt: Date(timeIntervalSince1970: 1_790_000_000), payload: Fixtures.payload)
        var json = try XCTUnwrap(String(data: KabbaISO8601.makeEncoder().encode(op), encoding: .utf8))
        XCTAssertTrue(json.contains("."), "new records keep milliseconds")
        // Rewrite as an older build stored it: whole seconds.
        json = json.replacingOccurrences(of: #"\.\d{3}"#, with: "", options: .regularExpression)
        let decoded = try KabbaISO8601.makeDecoder().decode(SyncOperation.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.queuedAt.timeIntervalSince1970, 1_790_000_000, accuracy: 0.001)
        _ = s
    }

    // MARK: - Honest wording (independent review)

    func testWhatIsSaidAboutKabbaFollowsTheRecordsOwnHistory() {
        func op(_ state: SyncState, attempts: Int, status: Int? = nil, transport: TransportFailure? = nil, disposition: RetryDisposition? = nil) -> SyncOperation {
            var o = SyncOperation(type: "x", capturedAt: Date(), payload: .object([:]))
            o.state = state
            o.attempts.attemptCount = attempts
            o.attempts.lastStatusCode = status
            o.attempts.lastTransportFailure = transport
            o.attempts.lastDisposition = disposition
            return o
        }
        XCTAssertEqual(SyncKabbaKnowledge.of(op(.needsAttention, attempts: 1, status: 409, disposition: .needsAttention)), .refused)
        XCTAssertEqual(SyncKabbaKnowledge.of(op(.needsAttention, attempts: 1, disposition: .needsAttention)), .notReceived, "parked on this phone")
        XCTAssertEqual(SyncKabbaKnowledge.of(op(.pending, attempts: 0)), .notReceived)
        XCTAssertEqual(SyncKabbaKnowledge.of(op(.pending, attempts: 2, transport: .offline, disposition: .retry)), .notReceived)
        XCTAssertEqual(SyncKabbaKnowledge.of(op(.pending, attempts: 1, transport: .timeout, disposition: .retry)), .uncertain,
                       "a timeout after sending may have been applied by Kabba")
        XCTAssertEqual(SyncKabbaKnowledge.of(op(.pending, attempts: 1, status: 503, disposition: .retry)), .uncertain)
        XCTAssertTrue(SyncKabbaKnowledge.uncertain.sentence.contains("Check the order before removing it"))
        XCTAssertEqual(SyncRecordProblem.of(op(.needsAttention, attempts: 1, disposition: .needsAttention)), .parkedOnPhone)
    }

    func testARecordThisPhoneCouldNotSendIsNeverReportedAsRefusedByKabba() throws {
        // No handler for the type: the engine parks it without Kabba ever answering.
        let engine = makeEngine(store: try store(), client: client)
        let op = try engine.enqueue(type: "unknown.type", payload: Fixtures.payload, capturedAt: Date())
        waitUntil { engine.operation(id: op.id)?.state == .needsAttention }
        XCTAssertNil(engine.operation(id: op.id)?.attempts.lastStatusCode)

        let review = SyncRecordReview.of(try XCTUnwrap(engine.operation(id: op.id)))
        XCTAssertEqual(review.problem, .parkedOnPhone)
        XCTAssertEqual(review.knowledge, .notReceived)
        XCTAssertEqual(review.explanation?.headline, "This phone couldn't send this record")

        let report = SyncPassReport.make(before: [op.id: .pending], after: [try XCTUnwrap(engine.operation(id: op.id))], pause: .none)
        XCTAssertEqual(report.parkedNow, 1)
        XCTAssertEqual(report.rejectedNow, 0)
        XCTAssertEqual(report.headline, "This phone could not send 1 record.")
    }

    func testABackgroundUploadFinishingMidPassDoesNotEndSyncNowEarly() throws {
        let s = try store()
        var held = SyncOperation(type: TestOperationHandler.type, capturedAt: Date(),
                                 identity: SyncBusinessIdentity(orderProductUniqueId: "HELD"), payload: Fixtures.payload)
        held.state = .pending
        try s.save(held)
        client.latency = 0.4
        client.defaultResult = Fixtures.ok()
        let engine = makeEngine(store: s, client: client, backoff: [60])
        engine.holdForExternalTransfer(operationId: held.id)
        waitUntil { engine.operation(id: held.id)?.state == .syncing }

        let slow = try engine.enqueue(type: TestOperationHandler.type, payload: Fixtures.payload,
                                      identity: SyncBusinessIdentity(orderProductUniqueId: "SLOW"), capturedAt: Date())
        var report: SyncPassReport?
        engine.syncNow(reason: "test") { report = $0 }
        // The held background upload fails while the slow record is still in flight.
        engine.completeExternalTransfer(operationId: held.id, result: .failure(APIError.transport(.timeout, description: "bg timeout")))
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        XCTAssertNil(report, "the pass is still sending — its report must wait for it")

        waitUntil { report != nil }
        XCTAssertEqual(engine.operation(id: slow.id)?.state, .synced)
        XCTAssertEqual(report?.sent, 1, "the record this pass sent is in its report")
    }
}
