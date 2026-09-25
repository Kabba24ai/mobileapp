//
//  AssemblySyncHandlers.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Queue Line Assembly Review (2026-09-14):
//
//    queue_line.availability   → POST queue-line/{order_product}/availability
//
//  Thin: the ledger, the unstage-on-Not-Available, the dependency-derived
//  grouping and the STOP/GO gate all live in Laravel. The phone records the
//  technician's confirmation durably (identity = the member's order product,
//  so it stays in FIFO with that line's own checklist operations), overlays
//  it locally until acknowledged, and parks a terminal refusal as Needs
//  Attention through the existing engine rules — never a second queue.
//  There is no grouping operation: true dependencies cannot be unbundled.
//

import Foundation

struct AvailabilitySyncHandler: SyncOperationHandler {
    let hasSession: () -> Bool

    var operationType: String { AssemblyOperationBuilder.availabilityType }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        return try AssemblyRequestFactory.availabilityRequest(for: operation)
    }
}

/// App-side conveniences for the Assembly Review screen and the board.
enum KabbaAssemblySync {

    /// The current overlay from the engine snapshot (never stored).
    static func overlay() -> AssemblyLocalOverlay {
        guard let engine = KabbaSync.engine else { return AssemblyLocalOverlay() }
        return AssemblyLocalOverlay.from(engine.snapshot())
    }

    /// Records a confirmation (Available) or a reversal (Not Available)
    /// durably. Returns the operation id on success (nil when the engine is
    /// unavailable or the write failed — the caller must not claim success).
    @discardableResult
    static func acknowledge(_ capture: AvailabilityCapture) -> String? {
        guard let engine = KabbaSync.engine else { return nil }
        return (try? AssemblyOperationBuilder.enqueueAvailability(capture, into: engine))?.id
    }

    // MARK: Cached Assembly Review (one JSON blob per order, per company — Phase 4 Amendment B)

    /// nil when signed out: nothing is read or written.
    private static func cacheKey(orderUniqueId: String, tenantKey: String? = nil) -> String? {
        DispatchOfflineTenantStorage.storageKey("kQueueLineAssembly_\(orderUniqueId)",
                                                tenantKey: tenantKey ?? KabbaTenantScope.currentKey)
    }

    /// For a NAMED company (the offline bridge writes for its own company, whoever is signed in).
    @discardableResult
    static func cache(_ envelopeData: Data, orderUniqueId: String, tenantKey: String) -> Bool {
        guard let key = cacheKey(orderUniqueId: orderUniqueId, tenantKey: tenantKey) else { return false }
        UserDefaults.standard.set(envelopeData, forKey: key)
        return true
    }

    /// A live Assembly Review answer to a request SENT at `askedAt` for `tenantKey`: not saved when
    /// a newer copy (a package asked later) is already on this phone (Dispatch offline Phase 4 §4.3).
    @discardableResult
    static func saveLive(_ envelopeData: Data, orderUniqueId: String, askedAt: Date, tenantKey: String?) -> Bool {
        guard let tenant = tenantKey else { return false }
        return DispatchOfflineSync.saveLiveCopy(.assembly, orderUniqueId: orderUniqueId, askedAt: askedAt, tenantKey: tenant) {
            cache(envelopeData, orderUniqueId: orderUniqueId, tenantKey: tenant)
        }
    }

    /// The cached review, served as the user signed in NOW (its `meta.employee` performs the
    /// acknowledgements — Dispatch offline P4-D5), for the signed-in company only.
    static func cached(orderUniqueId: String) -> AssemblyReviewEnvelope? {
        guard let key = cacheKey(orderUniqueId: orderUniqueId),
              let data = UserDefaults.standard.data(forKey: key),
              let envelope = try? AssemblyReviewEnvelope.decode(data) else { return nil }
        let signedIn = DispatchOfflineSync.signedInEmployee()
        return envelope.servedTo(signedIn.map { AssemblyReviewEnvelope.Employee(uniqueId: $0.uniqueId, fullName: $0.fullName) })
    }

    static func clearCache(orderUniqueId: String) {
        guard let key = cacheKey(orderUniqueId: orderUniqueId) else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }
}
