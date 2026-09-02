//
//  ChecklistOperations.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Builds the durable Sync Engine operations for the canonical checklist contract:
//
//    delivery_checklist.complete / return_checklist.complete
//        → POST orders/checklists/{execution}/complete   (multipart: fields + signature)
//    delivery_checklist.prepare  / return_checklist.prepare
//        → POST orders/checklists/{execution}/prepare    (JSON)
//
//  ONE operation per order product. The builder takes the product's OWN
//  context, answers, employee, fields and signature — there is no array
//  cross-product anywhere (the audit's P0).
//

import Foundation

/// What the employee captured for one order product's checklist.
struct ChecklistCapture: Equatable {
    var context: ChecklistContext
    /// template question id → template answer id
    var answers: [String: String]
    /// template question id → amount string (optional, e.g. damage amount)
    var amounts: [String: String] = [:]
    var employeeUserId: Int
    var equipmentUniqueId: String?
    var note: String = ""
    var storeId: Int?
    // Delivery leg
    var startHours: String = ""
    var fuelInitialReading: String = ""
    var deliveryCleanOption: String = ""
    var deliveryCleanId: String = ""
    // Return leg
    var endHours: String = ""
    var fuelFinalReading: String = ""
    var fuelTotalCharge: String = ""
    var totalCharge: String = ""
    var returnCleanOption: String = ""
    var returnCleanId: String = ""
    var totalCleanCharge: String = ""
    var capturedAt: Date = Date()
    /// Checklist-driven Queue Line staging (2026-09): true marks the
    /// checklist's explicit Save — the canonical Pending → Staged request.
    /// Only meaningful on the delivery leg; progress syncs leave it false.
    var markStaged: Bool = false

    var leg: ChecklistLeg { context.leg }

    /// Every required question answered — the staging precondition the phone
    /// validates before requesting Pending → Staged (Laravel re-enforces).
    var isChecklistComplete: Bool { context.missingRequiredQuestionIds(answered: answers).isEmpty }

    /// Local usability validation. Laravel re-validates the same rules on sync.
    func localValidationProblems() -> [String] {
        var problems: [String] = []
        let missing = context.missingRequiredQuestionIds(answered: answers)
        if !missing.isEmpty { problems.append("Unanswered required questions: \(missing.count)") }
        let unknown = context.unknownSelections(answered: answers)
        if !unknown.isEmpty { problems.append("Answers not in this checklist: \(unknown.count)") }
        if context.requirements.equipmentRequired && (equipmentUniqueId ?? "").isEmpty { problems.append("Equipment not selected") }
        if context.requirements.storeRequired && storeId == nil { problems.append("Return store not selected") }
        if employeeUserId <= 0 { problems.append("Employee not selected") }
        return problems
    }
}

enum ChecklistOperationBuilder {

    static func completeType(_ leg: ChecklistLeg) -> String { leg.operationPrefix + ".complete" }
    static func prepareType(_ leg: ChecklistLeg) -> String { leg.operationPrefix + ".prepare" }

    /// The JSON payload for a completion (the signature travels as an asset, never in the payload).
    static func completionPayload(_ capture: ChecklistCapture, signatureClientMediaId: String?) -> JSONValue {
        var body: [String: JSONValue] = [
            "checklist_execution_id": .string(capture.context.executionId),
            "order_product_unique_id": .string(capture.context.identity.orderProductUniqueId),
            "leg": .string(capture.leg.rawValue),
            "user_id": .number(Double(capture.employeeUserId)),
            "answers": .array(answersArray(capture)),
        ]
        if let revision = capture.context.template.revision { body["context_revision"] = .string(revision) }
        if let unit = capture.equipmentUniqueId, !unit.isEmpty { body["equipment_unique_id"] = .string(unit) }
        if let sig = signatureClientMediaId { body["signature_client_media_id"] = .string(sig) }
        if !capture.note.isEmpty { body["note"] = .string(capture.note) }
        if let store = capture.storeId { body["store_id"] = .number(Double(store)) }

        switch capture.leg {
        case .delivery:
            put(&body, "start_hours", capture.startHours)
            put(&body, "fuel_initial_reading", capture.fuelInitialReading)
            put(&body, "delivery_clean_option", capture.deliveryCleanOption)
            put(&body, "delivery_clean_id", capture.deliveryCleanId)
        case .return:
            put(&body, "end_hours", capture.endHours)
            put(&body, "fuel_final_reading", capture.fuelFinalReading)
            put(&body, "fuel_total_charge", capture.fuelTotalCharge)
            put(&body, "total_charge", capture.totalCharge)
            put(&body, "return_clean_option", capture.returnCleanOption)
            put(&body, "return_clean_id", capture.returnCleanId)
            put(&body, "total_clean_charge", capture.totalCleanCharge)
        }
        return .object(body)
    }

    static func preparePayload(_ capture: ChecklistCapture) -> JSONValue {
        var body: [String: JSONValue] = [
            "checklist_execution_id": .string(capture.context.executionId),
            "order_product_unique_id": .string(capture.context.identity.orderProductUniqueId),
            "leg": .string(capture.leg.rawValue),
            "answers": .array(answersArray(capture)),
        ]
        // Prepare may happen before the delivering employee is chosen.
        if capture.employeeUserId > 0 { body["user_id"] = .number(Double(capture.employeeUserId)) }
        if let revision = capture.context.template.revision { body["context_revision"] = .string(revision) }
        // The explicit Save → Pending → Staged request (delivery leg only —
        // the return leg has no queue semantics).
        if capture.markStaged && capture.leg.isDelivery { body["mark_staged"] = .bool(true) }
        return .object(body)
    }

    static func identity(_ capture: ChecklistCapture) -> SyncBusinessIdentity {
        SyncBusinessIdentity(orderUniqueId: capture.context.identity.orderUniqueId,
                             orderProductUniqueId: capture.context.identity.orderProductUniqueId,
                             equipmentUniqueId: capture.equipmentUniqueId ?? capture.context.equipment.equipmentUniqueId,
                             checklistExecutionId: capture.context.executionId,
                             employeeId: String(capture.employeeUserId))
    }

    static func displayTitle(_ capture: ChecklistCapture, prepare: Bool) -> String {
        let leg = capture.leg.isDelivery ? "Delivery" : "Return"
        let product = capture.context.identity.productName.isEmpty ? capture.context.identity.orderProductUniqueId : capture.context.identity.productName
        return "\(leg) checklist · \(prepare ? "prepared" : "complete") · \(product)"
    }

    /// Durably enqueues ONE completion operation for ONE order product. The signature bytes
    /// are written to the protected assets directory first; the operation references them.
    @discardableResult
    static func enqueueCompletion(_ capture: ChecklistCapture,
                                  signatureJPEG: Data?,
                                  into engine: SyncEngine,
                                  operationId: String = UUID().uuidString) throws -> SyncOperation {
        var assets: [SyncAsset] = []
        var signatureId: String?
        if let jpeg = signatureJPEG, !jpeg.isEmpty {
            let asset = try SyncAssetWriter.store(jpeg,
                                                  in: engine.store.assetsDirectory,
                                                  scope: capture.context.executionId,
                                                  fieldName: "signature_media",
                                                  mimeType: "image/jpeg",
                                                  fileExtension: "jpg")
            assets = [asset]
            signatureId = asset.clientMediaId
        }

        return try engine.enqueue(type: completeType(capture.leg),
                                  payload: completionPayload(capture, signatureClientMediaId: signatureId),
                                  identity: identity(capture),
                                  capturedAt: capture.capturedAt,
                                  assets: assets,
                                  displayTitle: displayTitle(capture, prepare: false),
                                  operationId: operationId)
    }

    @discardableResult
    static func enqueuePrepare(_ capture: ChecklistCapture,
                               into engine: SyncEngine,
                               operationId: String = UUID().uuidString) throws -> SyncOperation {
        try engine.enqueue(type: prepareType(capture.leg),
                           payload: preparePayload(capture),
                           identity: identity(capture),
                           capturedAt: capture.capturedAt,
                           displayTitle: displayTitle(capture, prepare: true),
                           operationId: operationId)
    }

    // MARK: Helpers

    private static func answersArray(_ capture: ChecklistCapture) -> [JSONValue] {
        capture.answers.keys.sorted().map { questionId in
            var item: [String: JSONValue] = [
                "question_id": .string(questionId),
                "answer_id": .string(capture.answers[questionId] ?? ""),
            ]
            if let amount = capture.amounts[questionId], !amount.isEmpty { item["amount"] = .string(amount) }
            return .object(item)
        }
    }

    private static func put(_ body: inout [String: JSONValue], _ key: String, _ value: String) {
        if !value.isEmpty { body[key] = .string(value) }
    }
}

/// The request shape shared by the completion handlers (app layer wires the session check).
enum ChecklistRequestFactory {
    static func completeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard let executionId = operation.payload["checklist_execution_id"]?.stringValue, !executionId.isEmpty else {
            throw SyncHandlerError.invalidPayload("Checklist operation has no execution id")
        }
        var body = operation.payload.objectValue ?? [:]
        body["operation_id"] = .string(operation.id)
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))
        return SyncHTTPRequest(method: "POST",
                               path: "orders/checklists/\(executionId)/complete",
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id,
                               attachments: operation.assets)
    }

    static func prepareRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard let executionId = operation.payload["checklist_execution_id"]?.stringValue, !executionId.isEmpty else {
            throw SyncHandlerError.invalidPayload("Checklist operation has no execution id")
        }
        var body = operation.payload.objectValue ?? [:]
        body["operation_id"] = .string(operation.id)
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))
        return SyncHTTPRequest(method: "POST",
                               path: "orders/checklists/\(executionId)/prepare",
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id)
    }
}
