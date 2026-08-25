//
//  ChecklistSyncHandlers.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Sync Engine handlers for the canonical checklist contract and the two
//  migrations that retire the last legacy dead-letter queues:
//
//    delivery_checklist.complete / return_checklist.complete  → canonical complete (multipart)
//    delivery_checklist.prepare  / return_checklist.prepare   → canonical prepare  (JSON)
//    legacy_customer_checklist.submit                          → legacy save-delivery/save-return
//                                                                (migrated kSaveCheckList items only)
//    fulfillment_inputs.update                                 → orders/schedules/update-delivery-pickup-inputs
//

import Foundation

struct ChecklistCompleteSyncHandler: SyncOperationHandler {
    let leg: ChecklistLeg
    let hasSession: () -> Bool

    var operationType: String { ChecklistOperationBuilder.completeType(leg) }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        return try ChecklistRequestFactory.completeRequest(for: operation)
    }
}

struct ChecklistPrepareSyncHandler: SyncOperationHandler {
    let leg: ChecklistLeg
    let hasSession: () -> Bool

    var operationType: String { ChecklistOperationBuilder.prepareType(leg) }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        return try ChecklistRequestFactory.prepareRequest(for: operation)
    }
}

/// Migrated legacy queue items — identical legacy payload, durable transport.
struct LegacyChecklistSubmitSyncHandler: SyncOperationHandler {
    let hasSession: () -> Bool

    var operationType: String { LegacyChecklistQueueMigration.operationType }
    /// Category D adapter: drains items an OLD build queued in its legacy wire format. It is the
    /// ONLY handler allowed to target save-delivery / save-return; nothing new is enqueued as this type.
    var mayUseDeprecatedEndpoint: Bool { true }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        return try LegacyChecklistQueueMigration.request(for: operation)
    }
}

/// Driver Override inputs (T&C / licence / video / checklist reasons). New captures send
/// complete_leg=false — recording only; completion flows through the canonical checklist.
struct FulfillmentInputsSyncHandler: SyncOperationHandler {
    static let operationType = "fulfillment_inputs.update"
    static let path = "orders/schedules/update-delivery-pickup-inputs"

    let hasSession: () -> Bool

    var operationType: String { FulfillmentInputsSyncHandler.operationType }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        guard var body = operation.payload.objectValue,
              body["order_product_unique_id"]?.stringValue?.isEmpty == false,
              body["type"]?.stringValue?.isEmpty == false else {
            throw SyncHandlerError.invalidPayload("Fulfillment inputs payload is missing its order product or type")
        }
        body["operation_id"] = .string(operation.id)
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))
        return SyncHTTPRequest(method: "POST",
                               path: FulfillmentInputsSyncHandler.path,
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id)
    }

    /// Enqueues one inputs update. `completeLeg:false` for new captures (Phase 3);
    /// `true` only for migrated legacy items whose original intent was completion.
    @discardableResult
    static func enqueue(into engine: SyncEngine,
                        orderProductUniqueId: String,
                        type: String,
                        inputsDate: String,
                        tncStatus: String,
                        driversLicenseStatus: String,
                        videoStatus: String,
                        checklistStatus: String,
                        completeLeg: Bool,
                        capturedAt: Date = Date(),
                        operationId: String = UUID().uuidString) throws -> SyncOperation {
        var payload: [String: JSONValue] = [
            "order_product_unique_id": .string(orderProductUniqueId),
            "type": .string(type),
            "complete_leg": .bool(completeLeg),
        ]
        if !inputsDate.isEmpty { payload["inputs_date"] = .string(inputsDate) }
        if !tncStatus.isEmpty { payload["tnc_status"] = .string(tncStatus) }
        if !driversLicenseStatus.isEmpty { payload["drivers_license_status"] = .string(driversLicenseStatus) }
        if !videoStatus.isEmpty { payload["video_status"] = .string(videoStatus) }
        if !checklistStatus.isEmpty { payload["checklist_status"] = .string(checklistStatus) }

        return try engine.enqueue(type: operationType,
                                  payload: .object(payload),
                                  identity: SyncBusinessIdentity(orderProductUniqueId: orderProductUniqueId),
                                  capturedAt: capturedAt,
                                  displayTitle: "\(type == "pickup" ? "Return" : "Delivery") override inputs\(completeLeg ? " (legacy completion)" : "")",
                                  operationId: operationId)
    }
}
