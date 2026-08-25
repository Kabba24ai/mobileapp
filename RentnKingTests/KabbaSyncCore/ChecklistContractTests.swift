import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Decodes the SHARED contract fixtures (tests/Fixtures/mobile-contract in the
/// Laravel repo, copied by Scripts/sync-contract-fixtures.sh) — the same bytes
/// the Laravel suite asserts the API produces.
final class ChecklistContractTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let url = dir.appendingPathComponent(name + ".json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Fixture \(name).json not synced — run Scripts/sync-contract-fixtures.sh")
        }
        return try Data(contentsOf: url)
    }

    func testDeliveryContextDecodesIntoOneStableIdSpace() throws {
        let context = try ChecklistContext.decode(envelopeData: try fixture("delivery_checklist_context"))

        XCTAssertEqual(context.leg, .delivery)
        XCTAssertTrue(context.identity.checklistExecutionId.hasPrefix("ORD-CHK-"))
        XCTAssertEqual(context.identity.cycle, 1)
        XCTAssertEqual(context.identity.status, "open")
        XCTAssertFalse(context.identity.orderProductUniqueId.isEmpty)
        XCTAssertEqual(context.equipment.assignment, "soft")
        XCTAssertTrue(context.equipment.hasUnit)
        XCTAssertTrue(context.requirements.signatureRequired)
        XCTAssertTrue(context.requirements.equipmentRequired)
        XCTAssertFalse(context.requirements.storeRequired)
        XCTAssertEqual(context.questions.count, 2)
        XCTAssertTrue(context.questions[0].required)
        XCTAssertFalse(context.questions[1].required)
        XCTAssertEqual(context.questions[0].answers.count, 2)
        XCTAssertTrue(context.questions[0].questionId.hasPrefix("CAQST-"), "template question ids")
        XCTAssertTrue(context.questions[0].answers[0].answerId.hasPrefix("CAANS-"), "template answer ids")
        XCTAssertEqual(context.requirements.requiredQuestionIds, [context.questions[0].questionId])
        XCTAssertNotNil(context.template.revision)
        XCTAssertTrue(context.serverState.canComplete)
        XCTAssertFalse(context.isCompleted)
    }

    func testReturnContextCarriesPreviousDeliveryAnswersInTheSameIdSpace() throws {
        let context = try ChecklistContext.decode(envelopeData: try fixture("return_checklist_context"))

        XCTAssertEqual(context.leg, .return)
        XCTAssertEqual(context.equipment.assignment, "hard")
        XCTAssertTrue(context.requirements.storeRequired)
        XCTAssertTrue(context.serverState.isDelivered)
        XCTAssertEqual(context.template.questionSource, "order_rows")
        let first = context.questions[0]
        XCTAssertNotNil(first.previousAnswerId)
        XCTAssertTrue(first.answers.contains { $0.answerId == first.previousAnswerId }, "previous selection resolves to a template answer id")
        XCTAssertTrue(first.answers.contains { $0.isDamaged })
        XCTAssertEqual(first.text, first.returnText)
    }

    func testCompletionSuccessAndReplayAreAcknowledgments() throws {
        let now = Date()
        let ok = SyncResponseInterpreter.interpret(SyncHTTPResponse(statusCode: 200, headers: [:], body: try fixture("delivery_checklist_completion_success")), now: now)
        guard case .acknowledged(let ack) = ok else { return XCTFail("success fixture must acknowledge") }
        XCTAssertFalse(ack.replayed)
        XCTAssertEqual(ack.data?["status"]?.stringValue, "completed")
        XCTAssertEqual(ack.data?["leg"]?.stringValue, "delivery")
        XCTAssertNotNil(ack.serverReceivedAt)
        XCTAssertNotNil(ack.data?["captured_at"]?.stringValue.flatMap(KabbaISO8601.date(from:)))

        let replay = SyncResponseInterpreter.interpret(SyncHTTPResponse(statusCode: 200, headers: ["X-Idempotent-Replay": "true"], body: try fixture("checklist_completion_idempotent_replay")), now: now)
        guard case .acknowledged(let replayAck) = replay else { return XCTFail("replay fixture must acknowledge") }
        XCTAssertTrue(replayAck.replayed)
        XCTAssertNotNil(replayAck.requestId)

        let returnOk = SyncResponseInterpreter.interpret(SyncHTTPResponse(statusCode: 200, headers: [:], body: try fixture("return_checklist_completion_success")), now: now)
        guard case .acknowledged(let returnAck) = returnOk else { return XCTFail("return success fixture must acknowledge") }
        XCTAssertEqual(returnAck.data?["leg"]?.stringValue, "return")
    }

    func testValidationFailureBecomesNeedsAttentionWithUsefulInformation() throws {
        let outcome = SyncResponseInterpreter.interpret(SyncHTTPResponse(statusCode: 422, headers: [:], body: try fixture("checklist_validation_failure")), now: Date())
        guard case .failed(let error) = outcome else { return XCTFail() }
        XCTAssertEqual(error.statusCode, 422)
        XCTAssertEqual(error.disposition, .needsAttention)
        XCTAssertNotNil(error.code)
        XCTAssertFalse(error.message.isEmpty)
        XCTAssertNotNil(error.requestId)
    }

    func testEquipmentAssignmentConflictIsPermanent() {
        do {
            let outcome = SyncResponseInterpreter.interpret(SyncHTTPResponse(statusCode: 409, headers: [:], body: try fixture("checklist_equipment_assignment_conflict")), now: Date())
            guard case .failed(let error) = outcome else { return XCTFail() }
            XCTAssertEqual(error.code, "EQUIPMENT_ASSIGNMENT_CONFLICT")
            XCTAssertEqual(error.serverRetryable, false)
            XCTAssertEqual(error.disposition, .needsAttention)
        } catch is XCTSkip {
            // fixture not synced yet
        } catch {
            XCTFail("\(error)")
        }
    }

    func testPreparedAcknowledgmentDecodes() throws {
        let outcome = SyncResponseInterpreter.interpret(SyncHTTPResponse(statusCode: 200, headers: [:], body: try fixture("delivery_checklist_prepared")), now: Date())
        guard case .acknowledged(let ack) = outcome else { return XCTFail() }
        XCTAssertEqual(ack.data?["status"]?.stringValue, "prepared")
    }
}
