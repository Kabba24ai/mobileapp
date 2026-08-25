//
//  LegacyChecklistQueueMigration.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Pure transformation of the pre-Phase-3 MMKV queue item (`kSaveCheckList`)
//  into Sync Engine operations of type `legacy_customer_checklist.submit`.
//
//  The legacy item already speaks the LEGACY id spaces (template ids for
//  delivery, ORD-QUE/ORD-ANS for return) and targets the legacy endpoints, so
//  the migration does NOT reinterpret ids — it preserves the exact legacy
//  payload, moves the base64 signature into a protected asset file, and hands
//  the submission to the durable engine where it can never be dead-lettered.
//  Anything that cannot be parsed is reported for quarantine, never dropped.
//

import Foundation

enum LegacyChecklistQueueMigration {

    static let operationType = "legacy_customer_checklist.submit"

    struct Converted: Equatable {
        let payload: JSONValue
        let signatureJPEG: Data?
        let identity: SyncBusinessIdentity
        let capturedAt: Date
        let displayTitle: String
        let leg: ChecklistLeg
    }

    enum Problem: Error, Equatable {
        case missingOrderProduct
        case missingType
        case invalidChecklistJSON
    }

    /// Fields the legacy uploader sent as form fields (everything except the images).
    static let legacyFieldKeys: [String] = [
        "order_product_unique_id", "order_unique_id", "equipment_unique_id", "checklist[]",
        "delivery_clean_option", "delivery_clean_id", "return_clean_option", "return_clean_id", "total_clean_charge",
        "start_hours", "end_hours", "user_id", "note", "total_charge", "store_id",
        "fuel_initial_reading", "fuel_final_reading", "fuel_total_charge", "type", "version",
    ]

    /// Converts one legacy queue dictionary (as persisted: signatures already base64 strings).
    static func convert(_ item: [String: Any], now: Date = Date()) -> Result<Converted, Problem> {
        guard let productId = item["order_product_unique_id"] as? String, !productId.isEmpty else {
            return .failure(.missingOrderProduct)
        }
        guard let type = item["type"] as? String, let leg = (type.lowercased() == "delivery" ? ChecklistLeg.delivery : (type.lowercased() == "return" ? .return : nil)) else {
            return .failure(.missingType)
        }

        var fields: [String: JSONValue] = [:]
        for key in legacyFieldKeys {
            guard let raw = item[key] else { continue }
            if let s = raw as? String {
                fields[key] = .string(s)
            } else if let v = JSONValue(any: raw) {
                fields[key] = v
            }
        }

        // The legacy body carried checklist[] as a JSON STRING; keep it verbatim but make
        // sure it is at least parseable so the server's repair branch is not needed.
        if case .string(let checklistJSON)? = fields["checklist[]"], !checklistJSON.isEmpty {
            if JSONValue.parse(Data(checklistJSON.utf8)) == nil {
                return .failure(.invalidChecklistJSON)
            }
        }

        let signatureKey = leg.isDelivery ? "dSignature" : "rSignature"
        var jpeg: Data?
        if let base64 = item[signatureKey] as? String, !base64.isEmpty, let data = Data(base64Encoded: base64), !data.isEmpty {
            jpeg = data
        }

        let identity = SyncBusinessIdentity(orderUniqueId: item["order_unique_id"] as? String,
                                            orderProductUniqueId: productId,
                                            equipmentUniqueId: item["equipment_unique_id"] as? String,
                                            employeeId: item["user_id"] as? String)

        return .success(Converted(payload: .object(fields),
                                  signatureJPEG: jpeg,
                                  identity: identity,
                                  capturedAt: now,
                                  displayTitle: "\(leg.isDelivery ? "Delivery" : "Return") checklist (legacy) · \(productId)",
                                  leg: leg))
    }

    /// Durably enqueues a converted legacy item: signature → protected asset, payload verbatim.
    @discardableResult
    static func enqueue(_ converted: Converted, into engine: SyncEngine, operationId: String = UUID().uuidString) throws -> SyncOperation {
        var assets: [SyncAsset] = []
        if let jpeg = converted.signatureJPEG {
            assets = [try SyncAssetWriter.store(jpeg,
                                                in: engine.store.assetsDirectory,
                                                scope: "legacy-" + (converted.identity.orderProductUniqueId ?? "unknown"),
                                                fieldName: "signature_media",
                                                mimeType: "image/jpeg",
                                                fileExtension: "jpg")]
        }
        return try engine.enqueue(type: operationType,
                                  payload: converted.payload,
                                  identity: converted.identity,
                                  capturedAt: converted.capturedAt,
                                  assets: assets,
                                  displayTitle: converted.displayTitle,
                                  operationId: operationId)
    }

    /// Legacy endpoint path for a converted item.
    static func path(for leg: ChecklistLeg) -> String {
        leg.isDelivery ? "orders/customer-checklists/save-delivery" : "orders/customer-checklists/save-return"
    }

    /// Multipart request against the LEGACY endpoint, with X-Operation-Id for tracing.
    static func request(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard let type = operation.payload["type"]?.stringValue else {
            throw SyncHandlerError.invalidPayload("Legacy checklist operation has no type")
        }
        let leg: ChecklistLeg = type.lowercased() == "delivery" ? .delivery : .return
        var body = operation.payload.objectValue ?? [:]
        body["operation_id"] = .string(operation.id)
        return SyncHTTPRequest(method: "POST",
                               path: path(for: leg),
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id,
                               attachments: operation.assets)
    }
}
