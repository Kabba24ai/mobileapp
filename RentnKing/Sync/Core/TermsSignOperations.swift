//
//  TermsSignOperations.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Dispatch offline Phase 5 — terms.sign: the customer signed the order's
//  FROZEN Terms & Conditions agreement on this phone. Local-first: the
//  signature (PNG, the web pad's format) and the agreement's identity are
//  durable the moment enqueue returns; T&C counts as satisfied from then on
//  (EffectiveFieldState), and the operation syncs later, idempotently:
//
//    terms.sign → POST orders/terms/{order}/accept (multipart)
//
//  Laravel records it on the order only when `terms_identity` equals the
//  identity of the agreement frozen on that order. A mismatch is a
//  verification / data-integrity failure (TERMS_IDENTITY_MISMATCH, 409, not
//  retryable): the operation parks in Needs Attention with its signature kept
//  until a person discards it — never relabelled, never accepted against
//  another document.
//
//  A separate type from terms.accept, which records (recording-only) that the
//  HOSTED signing page already stored an acceptance server-side.
//

import Foundation

struct TermsSignCapture: Equatable {
    var orderUniqueId: String
    /// The identity of the verified agreement the customer saw and signed.
    var termsIdentity: String
    var approvalsConfirmed: Int
    /// The line whose workflow surfaced the signing (records its tnc status). Empty = none.
    var orderProductUniqueId: String = ""
    var leg: ChecklistLeg = .delivery
    /// The signed-in employee who ran the flow (0 = unknown; key omitted).
    var employeeUserId: Int = 0
    /// Display only (Sync Status list).
    var orderNumber: String = ""
    /// Device signing time → captured_at (customer-action metadata on the server).
    var capturedAt: Date = Date()

    func localValidationProblems() -> [String] {
        var problems: [String] = []
        if orderUniqueId.isEmpty { problems.append("Missing order") }
        if !TermsAgreement.isIdentity(termsIdentity) { problems.append("Missing terms identity") }
        if approvalsConfirmed < 0 { problems.append("Invalid approvals") }
        return problems
    }
}

enum TermsSignOperationBuilder {

    static let operationType = "terms.sign"

    static func payload(_ capture: TermsSignCapture, signatureClientMediaId: String?) -> JSONValue {
        var body: [String: JSONValue] = [
            "order_unique_id": .string(capture.orderUniqueId),
            "terms_identity": .string(capture.termsIdentity),
            "approvals_confirmed": .number(Double(capture.approvalsConfirmed)),
            "leg": .string(capture.leg.rawValue),
        ]
        if !capture.orderProductUniqueId.isEmpty { body["order_product_unique_id"] = .string(capture.orderProductUniqueId) }
        if capture.employeeUserId > 0 { body["user_id"] = .number(Double(capture.employeeUserId)) }
        if let sig = signatureClientMediaId { body["signature_client_media_id"] = .string(sig) }
        return .object(body)
    }

    static func identity(_ capture: TermsSignCapture) -> SyncBusinessIdentity {
        SyncBusinessIdentity(orderUniqueId: capture.orderUniqueId,
                             orderProductUniqueId: capture.orderProductUniqueId.isEmpty ? nil : capture.orderProductUniqueId,
                             employeeId: capture.employeeUserId > 0 ? String(capture.employeeUserId) : nil)
    }

    static func displayTitle(_ capture: TermsSignCapture) -> String {
        let order = capture.orderNumber.isEmpty ? capture.orderUniqueId : "#\(capture.orderNumber)"
        return "Terms & Conditions · signed · \(order)"
    }

    /// Durably enqueues ONE signing: the PNG is written to the protected assets directory first,
    /// then the operation that references it. Returns only once both are on disk.
    @discardableResult
    static func enqueue(_ capture: TermsSignCapture,
                        signaturePNG: Data,
                        into engine: SyncEngine,
                        operationId: String = UUID().uuidString) throws -> SyncOperation {
        let asset = try SyncAssetWriter.store(signaturePNG,
                                              in: engine.store.assetsDirectory,
                                              scope: "terms-" + capture.orderUniqueId,
                                              fieldName: "signature_media",
                                              mimeType: "image/png",
                                              fileExtension: "png")
        return try engine.enqueue(type: operationType,
                                  payload: payload(capture, signatureClientMediaId: asset.clientMediaId),
                                  identity: identity(capture),
                                  capturedAt: capture.capturedAt,
                                  assets: [asset],
                                  displayTitle: displayTitle(capture),
                                  operationId: operationId)
    }

    /// The identity a terms.sign operation names.
    static func termsIdentity(of operation: SyncOperation) -> String? {
        operation.payload["terms_identity"]?.stringValue
    }
}

enum TermsSignRequestFactory {

    static func path(orderUniqueId: String) -> String {
        let encoded = orderUniqueId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? orderUniqueId
        return "orders/terms/\(encoded)/accept"
    }

    static func request(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard var body = operation.payload.objectValue,
              let order = body["order_unique_id"]?.stringValue, !order.isEmpty,
              let identity = body["terms_identity"]?.stringValue, TermsAgreement.isIdentity(identity),
              body["approvals_confirmed"]?.intValue != nil,
              !operation.assets.isEmpty else {
            throw SyncHandlerError.invalidPayload("Terms signature is missing its order, terms identity, approvals or signature")
        }
        // The order is the URL; everything else travels as multipart fields beside the signature.
        body["order_unique_id"] = nil
        body["operation_id"] = .string(operation.id)
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))
        return SyncHTTPRequest(method: "POST",
                               path: path(orderUniqueId: order),
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id,
                               attachments: operation.assets)
    }
}
