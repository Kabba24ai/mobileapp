//
//  TermsOperations.swift
//  RentnKing — Sync Core (Foundation only)
//
//  terms.accept — durable local evidence that the customer signed the Terms &
//  Conditions for an order.
//
//  AUDIT (2026-09): in the ORDER workflow the signature itself is captured and
//  submitted BY the hosted signing web page (front POST
//  terms-and-conditions/{order}/sign) inside TermsAndConditionViewController's
//  WKWebView — by the time the app sees the "thank-you" redirect, Laravel has
//  ALREADY durably recorded terms_status=Accepted + signature_image. The app
//  never possesses the signature bytes, so there is nothing left to transport.
//  What CAN be lost is the phone's own knowledge of the acceptance: an
//  in-memory flip (termsSucess) dies with a force-quit and a stale cached feed
//  then produces a FALSE exception on Complete Delivery. This operation is
//  that knowledge, made durable (EffectiveFieldState.termsSatisfied).
//
//  On drain it posts the SAME canonical, idempotent mobile record the Driver
//  Override T&C path uses:
//
//    terms.accept → POST orders/schedules/update-delivery-pickup-inputs
//                   (tnc_status="accepted", complete_leg=false — recording
//                    only; NEVER a completion claim, per DeprecatedEndpoints)
//
//  It deliberately does NOT replay the front /sign endpoint: that write
//  requires the signature string (web page only), unconditionally overwrites
//  signature_image and re-fires OrderTermsSignedEvent — replaying it would
//  corrupt the legally signed record. A future NATIVE signature pad can attach
//  its image as an engine asset here (signatureJPEG), exactly like the
//  checklist signature.
//

import Foundation

/// What the phone observed: T&C for this order were accepted (signed) during
/// the given delivery/return leg of one order product.
struct TermsAcceptCapture: Equatable {
    var orderUniqueId: String
    /// The order product whose fulfillment workflow surfaced the signing
    /// (update-delivery-pickup-inputs is product-scoped). Terms themselves are
    /// an ORDER-level fact — satisfaction matches on the order.
    var orderProductUniqueId: String
    var leg: ChecklistLeg = .delivery
    /// The signed-in employee who ran the flow (0 = unknown; key omitted).
    var employeeUserId: Int = 0
    /// Display only (Sync Status list). Never the customer.
    var orderNumber: String = ""
    var capturedAt: Date = Date()

    func localValidationProblems() -> [String] {
        var problems: [String] = []
        if orderUniqueId.isEmpty { problems.append("Missing order") }
        if orderProductUniqueId.isEmpty { problems.append("Missing order item") }
        return problems
    }
}

enum TermsOperationBuilder {

    static let operationType = "terms.accept"
    /// The recorded status value — mirrors the Driver Override's completed value.
    static let acceptedStatus = "accepted"

    /// The JSON payload. A native signature travels as an asset, never inline.
    static func payload(_ capture: TermsAcceptCapture, signatureClientMediaId: String? = nil) -> JSONValue {
        var body: [String: JSONValue] = [
            "order_unique_id": .string(capture.orderUniqueId),
            "order_product_unique_id": .string(capture.orderProductUniqueId),
            "type": .string(capture.leg.isDelivery ? "delivery" : "pickup"),
            "tnc_status": .string(acceptedStatus),
            // Recording only — an inputs update must NEVER claim leg completion
            // (checklist-less completion door, audit P0-3 / DeprecatedEndpoints).
            "complete_leg": .bool(false),
        ]
        if capture.employeeUserId > 0 { body["user_id"] = .number(Double(capture.employeeUserId)) }
        if let sig = signatureClientMediaId { body["signature_client_media_id"] = .string(sig) }
        return .object(body)
    }

    static func identity(_ capture: TermsAcceptCapture) -> SyncBusinessIdentity {
        SyncBusinessIdentity(orderUniqueId: capture.orderUniqueId,
                             orderProductUniqueId: capture.orderProductUniqueId,
                             employeeId: capture.employeeUserId > 0 ? String(capture.employeeUserId) : nil)
    }

    static func displayTitle(_ capture: TermsAcceptCapture) -> String {
        let order = capture.orderNumber.isEmpty ? capture.orderUniqueId : "#\(capture.orderNumber)"
        return "Terms & Conditions · accepted · \(order)"
    }

    /// Durably enqueues ONE acceptance record for ONE signing event. A native
    /// signature image (when a future pad captures one) is written to the
    /// protected assets directory first; the operation references it — the
    /// webview flow passes nil because the signing page owns the signature.
    @discardableResult
    static func enqueueAccept(_ capture: TermsAcceptCapture,
                              signatureJPEG: Data? = nil,
                              into engine: SyncEngine,
                              operationId: String = UUID().uuidString) throws -> SyncOperation {
        var assets: [SyncAsset] = []
        var signatureId: String?
        if let jpeg = signatureJPEG, !jpeg.isEmpty {
            let asset = try SyncAssetWriter.store(jpeg,
                                                  in: engine.store.assetsDirectory,
                                                  scope: "terms-" + capture.orderUniqueId,
                                                  fieldName: "signature_media",
                                                  mimeType: "image/jpeg",
                                                  fileExtension: "jpg")
            assets = [asset]
            signatureId = asset.clientMediaId
        }

        return try engine.enqueue(type: operationType,
                                  payload: payload(capture, signatureClientMediaId: signatureId),
                                  identity: identity(capture),
                                  capturedAt: capture.capturedAt,
                                  assets: assets,
                                  displayTitle: displayTitle(capture),
                                  operationId: operationId)
    }
}

/// The request shape for the terms.accept handler (app layer wires the session check).
enum TermsAcceptRequestFactory {
    /// Same canonical inputs recorder the Driver Override T&C path uses.
    static let path = "orders/schedules/update-delivery-pickup-inputs"

    static func request(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard var body = operation.payload.objectValue,
              body["order_product_unique_id"]?.stringValue?.isEmpty == false,
              body["tnc_status"]?.stringValue?.isEmpty == false,
              body["type"]?.stringValue?.isEmpty == false else {
            throw SyncHandlerError.invalidPayload("Terms acceptance payload is missing its order product, type or status")
        }
        // Belt and braces: whatever was stored, the wire request is recording-only.
        body["complete_leg"] = .bool(false)
        body["operation_id"] = .string(operation.id)
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))
        return SyncHTTPRequest(method: "POST",
                               path: path,
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id,
                               attachments: operation.assets)
    }
}
