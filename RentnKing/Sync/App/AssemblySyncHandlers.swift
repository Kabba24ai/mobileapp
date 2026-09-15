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

    // MARK: Cached Assembly Review (one JSON blob per order, like the board list)

    private static func cacheKey(orderUniqueId: String) -> String { "kQueueLineAssembly_\(orderUniqueId)" }

    static func cache(_ envelopeData: Data, orderUniqueId: String) {
        UserDefaults.standard.set(envelopeData, forKey: cacheKey(orderUniqueId: orderUniqueId))
    }

    static func cached(orderUniqueId: String) -> AssemblyReviewEnvelope? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(orderUniqueId: orderUniqueId)) else { return nil }
        return try? AssemblyReviewEnvelope.decode(data)
    }

    static func clearCache(orderUniqueId: String) {
        UserDefaults.standard.removeObject(forKey: cacheKey(orderUniqueId: orderUniqueId))
    }
}
