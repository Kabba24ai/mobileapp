//
//  DriverChecklistSyncHandler.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  The PROOF operation for the Sync Engine: a driver checklist step
//  (Ready to Go / On My Way / Arrived, fuel, keys, call-customer) submitted to
//  POST orders/schedules/driver-checklist.
//
//  Why this operation: it is state-changing, already lived in an offline queue
//  that dead-lettered after 5 rejections, it is NOT the customer checklist (so
//  it does not pre-empt the Phase 3 checklist-contract redesign), the payload
//  is six strings, and a duplicate "no answer" retry used to text the customer
//  twice — exactly what idempotency fixes. The server side is idempotent via
//  X-Operation-Id and honours captured_at.
//

import Foundation

struct DriverChecklistSyncHandler: SyncOperationHandler {

    static let operationType = "driver_checklist.update"
    static let path = "orders/schedules/driver-checklist"

    /// Whether a session exists (token + base URL). When false the engine pauses for authentication.
    let hasSession: () -> Bool

    init(hasSession: @escaping () -> Bool) {
        self.hasSession = hasSession
    }

    var operationType: String { DriverChecklistSyncHandler.operationType }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        guard var body = operation.payload.objectValue,
              body["order_product_unique_id"]?.stringValue?.isEmpty == false,
              body["checklist_type"]?.stringValue?.isEmpty == false else {
            throw SyncHandlerError.invalidPayload("Driver checklist payload is missing its order product or checklist type")
        }

        // The idempotency key and the real capture time ride in the body as well as the header,
        // so a multipart-capable server path could read them the same way.
        body["operation_id"] = .string(operation.id)
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))

        return SyncHTTPRequest(method: "POST",
                               path: DriverChecklistSyncHandler.path,
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id)
    }

    /// Builds and durably enqueues one driver checklist step. Returns after the record is on disk.
    @discardableResult
    static func enqueue(into engine: SyncEngine,
                        orderProductUniqueId: String,
                        orderUniqueId: String?,
                        equipmentFuel: String,
                        callCustomer: String,
                        equipmentKeyLocation: String,
                        equipmentDriverStatus: String,
                        checklistType: String,
                        capturedAt: Date = Date(),
                        operationId: String = UUID().uuidString) throws -> SyncOperation {
        var payload: [String: JSONValue] = [
            "order_product_unique_id": .string(orderProductUniqueId),
            "checklist_type": .string(checklistType),
        ]
        // Empty strings are what the legacy queue sent; the server treats them as "no change"
        // for nullable fields, so keep them out of the payload instead of sending "".
        if !equipmentFuel.isEmpty { payload["equipment_fuel"] = .string(equipmentFuel) }
        if !equipmentKeyLocation.isEmpty { payload["equipment_key_location"] = .string(equipmentKeyLocation) }
        if !equipmentDriverStatus.isEmpty { payload["equipment_driver_status"] = .string(equipmentDriverStatus) }
        if !callCustomer.isEmpty { payload["call_customer"] = .string(callCustomer) }

        return try engine.enqueue(type: operationType,
                                  payload: .object(payload),
                                  identity: SyncBusinessIdentity(orderUniqueId: orderUniqueId,
                                                                 orderProductUniqueId: orderProductUniqueId),
                                  capturedAt: capturedAt,
                                  displayTitle: displayTitle(status: equipmentDriverStatus, checklistType: checklistType),
                                  operationId: operationId)
    }

    static func displayTitle(status: String, checklistType: String) -> String {
        let leg = checklistType.isEmpty ? "" : " (\(checklistType))"
        return "Driver checklist · \(status.isEmpty ? "update" : status)\(leg)"
    }
}
