//
//  TermsSyncHandler.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  terms.accept on the Sync Engine: durable local evidence that the customer
//  signed the Terms & Conditions for an order (see TermsOperations.swift for
//  the audit — the signature itself is captured and submitted by the hosted
//  signing web page; this operation makes the phone's knowledge of that
//  acceptance durable and reconciles the same per-product tnc record the
//  Driver Override writes, recording-only, idempotent via X-Operation-Id).
//

import Foundation

struct TermsAcceptSyncHandler: SyncOperationHandler {
    let hasSession: () -> Bool

    var operationType: String { TermsOperationBuilder.operationType }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        return try TermsAcceptRequestFactory.request(for: operation)
    }
}

/// terms.sign (Dispatch offline Phase 5): a signature captured on this phone for the order's
/// frozen agreement → POST orders/terms/{order}/accept, idempotent via X-Operation-Id.
struct TermsSignSyncHandler: SyncOperationHandler {
    let hasSession: () -> Bool

    var operationType: String { TermsSignOperationBuilder.operationType }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        return try TermsSignRequestFactory.request(for: operation)
    }
}

/// Screen-facing helper over the engine for T&C acceptance (SyncDriverChecklist pattern:
/// engine-first, durable before returning; the caller keeps its legacy in-memory flip as
/// the engine-unavailable fallback).
enum KabbaTermsSync {

    /// Durably records "T&C accepted for this order" the moment the signing page
    /// reached its thank-you step. Returns the operation id for the status toast,
    /// or nil when the engine is unavailable / the context is incomplete — in
    /// which case the caller's existing in-session behaviour stands alone.
    @discardableResult
    static func recordAccepted(orderUniqueId: String,
                               orderProductUniqueId: String,
                               isReturnLeg: Bool,
                               orderNumber: String = "") -> String? {
        guard let engine = KabbaSync.engine else { return nil }
        var capture = TermsAcceptCapture(orderUniqueId: orderUniqueId,
                                         orderProductUniqueId: orderProductUniqueId,
                                         leg: isReturnLeg ? .return : .delivery,
                                         orderNumber: orderNumber)
        capture.employeeUserId = Int(UserDefaults.standard.user?.id ?? "") ?? 0
        guard capture.localValidationProblems().isEmpty else { return nil }
        do {
            let operation = try TermsOperationBuilder.enqueueAccept(capture, into: engine)
            return operation.id
        } catch {
            debugPrint("Terms accept: sync engine enqueue failed (\(error)) — in-session flip only")
            return nil
        }
    }

    /// Dispatch offline Phase 5: durably records the customer's signature of the order's VERIFIED
    /// frozen agreement (terms.sign). Returns the operation id once the signature and the operation
    /// are on disk, or nil — in which case nothing was recorded and the caller must not advance.
    static func recordSigned(agreement: TermsAgreement,
                             orderProductUniqueId: String,
                             isReturnLeg: Bool,
                             approvalsConfirmed: Int,
                             signaturePNG: Data) -> String? {
        guard let engine = KabbaSync.engine else { return nil }
        var capture = TermsSignCapture(orderUniqueId: agreement.orderUniqueId,
                                       termsIdentity: agreement.identity,
                                       approvalsConfirmed: approvalsConfirmed)
        capture.orderProductUniqueId = orderProductUniqueId
        capture.leg = isReturnLeg ? .return : .delivery
        capture.employeeUserId = Int(UserDefaults.standard.user?.id ?? "") ?? 0
        capture.orderNumber = agreement.orderNumber.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard capture.localValidationProblems().isEmpty else { return nil }
        do {
            return try TermsSignOperationBuilder.enqueue(capture, signaturePNG: signaturePNG, into: engine).id
        } catch {
            debugPrint("Terms sign: sync engine enqueue failed (\(error)) — nothing recorded")
            return nil
        }
    }
}
