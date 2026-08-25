//
//  MediaOperations.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Phase 4 — media + driver's-license offline sync on the Sync Engine.
//
//  One operation per FILE:
//
//    delivery_media.upload  → POST orders/media  type=delivery  (photo / video)
//    return_media.upload    → POST orders/media  type=pickup    (photo / video)
//    license_media.upload   → POST orders/media  type=license   (front / back)
//
//  Every capture gets ONE client_media_id at capture time (the SyncAsset's id).
//  It never changes across retries, relaunches or a lost response; Laravel
//  keeps it UNIQUE, so a retry can only ever converge on the same record.
//
//  The file itself lives in the protected assets directory (Data Protection,
//  excluded from backup) from the moment the employee is told it was saved,
//  and is removed only after Laravel acknowledged THIS operation
//  (MediaCleanupPolicy) or the employee explicitly discards it.
//

import Foundation

enum MediaKind: String, Codable, Equatable, CaseIterable {
    case delivery
    case pickup
    case license

    var operationType: String {
        switch self {
        case .delivery: return "delivery_media.upload"
        case .pickup:   return "return_media.upload"
        case .license:  return "license_media.upload"
        }
    }

    var leg: ChecklistLeg? {
        switch self {
        case .delivery: return .delivery
        case .pickup:   return .return
        case .license:  return nil
        }
    }

    static func from(operationType: String) -> MediaKind? {
        allCases.first { $0.operationType == operationType }
    }

    static var operationTypes: [String] { allCases.map { $0.operationType } }
}

/// One captured file and the business record it belongs to.
struct MediaCapture: Equatable {
    var kind: MediaKind
    var orderUniqueId: String
    /// Required for delivery / pickup; nil for the driver's license (order-level).
    var orderProductUniqueId: String?
    /// The Phase 3 checklist execution the evidence belongs to, when known.
    var checklistExecutionId: String?
    var equipmentUniqueId: String?
    /// License only: "front" | "back".
    var side: String?
    /// License only: yyyy-MM-dd, when the auto-inject flow captured it.
    var licenseExpiryDate: String?
    /// License only: the employee id attributed by the auto-inject flow.
    var autoInjectBy: String?
    /// Non-sensitive label for the Sync Status list (product / order number). Never the customer.
    var label: String = ""
    var capturedAt: Date = Date()
    /// The durable protected file (fieldName "media"). Its clientMediaId IS the media identity.
    var asset: SyncAsset

    var clientMediaId: String { asset.clientMediaId }
    var isVideo: Bool { asset.mimeType.hasPrefix("video/") }

    func localValidationProblems() -> [String] {
        var problems: [String] = []
        if orderUniqueId.isEmpty { problems.append("Missing order") }
        if kind != .license && (orderProductUniqueId ?? "").isEmpty { problems.append("Missing order item") }
        if kind == .license && !["front", "back"].contains(side ?? "") { problems.append("License side must be front or back") }
        if asset.relativePath.isEmpty { problems.append("Missing file") }
        return problems
    }
}

enum MediaOperationBuilder {

    static let fieldName = "media"

    static func payload(_ capture: MediaCapture) -> JSONValue {
        var body: [String: JSONValue] = [
            "client_media_id": .string(capture.clientMediaId),
            "order_unique_id": .string(capture.orderUniqueId),
            "type": .string(capture.kind.rawValue),
        ]
        if let product = capture.orderProductUniqueId, !product.isEmpty { body["order_product_unique_id"] = .string(product) }
        if let execution = capture.checklistExecutionId, !execution.isEmpty { body["checklist_execution_id"] = .string(execution) }
        if let side = capture.side, !side.isEmpty { body["side"] = .string(side) }
        if let expiry = capture.licenseExpiryDate, !expiry.isEmpty { body["license_expiry_date"] = .string(expiry) }
        if let by = capture.autoInjectBy, !by.isEmpty { body["auto_inject_by"] = .string(by) }
        return .object(body)
    }

    static func identity(_ capture: MediaCapture) -> SyncBusinessIdentity {
        SyncBusinessIdentity(orderUniqueId: capture.orderUniqueId,
                             orderProductUniqueId: capture.orderProductUniqueId,
                             equipmentUniqueId: capture.equipmentUniqueId,
                             checklistExecutionId: capture.checklistExecutionId)
    }

    /// e.g. "Delivery photo · Skid Steer", "Return video · #7701", "Driver's license · front".
    /// Deliberately carries no customer identity and never previews the file.
    static func displayTitle(_ capture: MediaCapture) -> String {
        switch capture.kind {
        case .license:
            return "Driver's license · \(capture.side ?? "image")"
        case .delivery, .pickup:
            let noun = capture.isVideo ? "video" : "photo"
            let leg = capture.kind == .delivery ? "Delivery" : "Return"
            return capture.label.isEmpty ? "\(leg) \(noun)" : "\(leg) \(noun) · \(capture.label)"
        }
    }

    /// Durably enqueues ONE upload for ONE file. The asset must already be in the
    /// protected assets directory (SyncAssetWriter) — the operation only references it.
    @discardableResult
    static func enqueue(_ capture: MediaCapture,
                        into engine: SyncEngine,
                        operationId: String = UUID().uuidString) throws -> SyncOperation {
        try engine.enqueue(type: capture.kind.operationType,
                           payload: payload(capture),
                           identity: identity(capture),
                           capturedAt: capture.capturedAt,
                           assets: [capture.asset],
                           displayTitle: displayTitle(capture),
                           operationId: operationId)
    }

    static func isMediaOperation(_ type: String) -> Bool { MediaKind.from(operationType: type) != nil }
}

enum MediaRequestFactory {
    static let path = "orders/media"

    static func uploadRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard var body = operation.payload.objectValue,
              body["client_media_id"]?.stringValue?.isEmpty == false,
              body["order_unique_id"]?.stringValue?.isEmpty == false,
              let type = body["type"]?.stringValue, MediaKind(rawValue: type) != nil else {
            throw SyncHandlerError.invalidPayload("Media upload is missing its client id, order or type")
        }
        guard let asset = operation.assets.first else {
            throw SyncHandlerError.invalidPayload("Media upload has no file attached")
        }
        if type != MediaKind.license.rawValue, body["order_product_unique_id"]?.stringValue?.isEmpty != false {
            throw SyncHandlerError.invalidPayload("Delivery/return media must name its order item")
        }
        body["operation_id"] = .string(operation.id)
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))

        // The server reads the file from the `media` field whatever the asset was recorded under.
        let attachment = SyncAsset(clientMediaId: asset.clientMediaId, relativePath: asset.relativePath, mimeType: asset.mimeType,
                                   fieldName: MediaOperationBuilder.fieldName, byteCount: asset.byteCount, sha256: asset.sha256,
                                   acknowledgedAt: asset.acknowledgedAt)

        return SyncHTTPRequest(method: "POST",
                               path: path,
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id,
                               attachments: [attachment],
                               prefersBackgroundTransfer: true)
    }
}

/// The ONE local-cleanup rule for media evidence (Step 18).
///
///  • A file is eligible for deletion ONLY after Laravel acknowledged the operation
///    that carries it (2xx, canonical envelope). The engine deletes it at that moment
///    for media operations (`removesAssetsAfterAcknowledgment`), so a driver's-license
///    image never outlives its successful upload on the phone.
///  • A lost acknowledgment keeps the file: the operation is still pending, the retry
///    converges on the server's existing record (client_media_id), and THEN the file goes.
///  • Needs Attention keeps the file and the operation until a person retries or discards.
///  • An explicit Discard (Settings › Sync Status) removes the operation AND its file.
///  • Pruning of acknowledged operation RECORDS (7 days) never touches files — they are
///    already gone.
enum MediaCleanupPolicy {
    static let deleteAssetsAfterAcknowledgment = true
}
