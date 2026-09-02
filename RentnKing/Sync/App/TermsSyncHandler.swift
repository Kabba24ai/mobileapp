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
}
