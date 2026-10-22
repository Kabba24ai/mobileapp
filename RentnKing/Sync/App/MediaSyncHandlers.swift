//
//  MediaSyncHandlers.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Phase 4 — delivery / return media and driver's-license images on the Sync
//  Engine. One handler per media kind; the file is a protected SyncAsset, the
//  operation carries the explicit business association, the transfer goes
//  through the background uploader, and the local file is deleted only after
//  Laravel acknowledged the operation (MediaCleanupPolicy).
//

import Foundation

struct MediaUploadSyncHandler: SyncOperationHandler {
    let kind: MediaKind
    let hasSession: () -> Bool

    var operationType: String { kind.operationType }
    var removesAssetsAfterAcknowledgment: Bool { MediaCleanupPolicy.deleteAssetsAfterAcknowledgment }

    func makeRequest(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard hasSession() else { throw SyncHandlerError.notAuthenticated("No active session") }
        return try MediaRequestFactory.uploadRequest(for: operation)
    }
}

/// One locally captured file still owned by the phone, for screens that show
/// "what you took" before the server has it.
struct KabbaPendingMedia: Equatable {
    let operationId: String
    let clientMediaId: String
    let kind: MediaKind
    let orderUniqueId: String
    let orderProductUniqueId: String?
    let side: String?
    let isVideo: Bool
    let fileURL: URL
    let state: SyncState
    let attentionReason: String?
}

/// Screen-facing helpers over the engine for media.
enum KabbaMediaSync {

    enum Failure: Error, Equatable {
        case engineUnavailable
        case encodingFailed
        /// A license side must be re-sent (new details) but this phone has no trustworthy image
        /// of it: not saved here, and the order's image never loaded on screen.
        case imageNotAvailable(side: String)
    }

    private static var engine: SyncEngine? { KabbaSync.engine }

    /// Imports an on-disk file (compressed photo / exported video) into protected storage and
    /// durably enqueues its upload. Returns only after both are on disk. The source file is
    /// MOVED — the operation's asset is the one durable copy from now on.
    @discardableResult
    static func enqueueFile(at source: URL,
                            kind: MediaKind,
                            orderUniqueId: String,
                            orderProductUniqueId: String?,
                            checklistExecutionId: String? = nil,
                            equipmentUniqueId: String? = nil,
                            mimeType: String,
                            label: String = "",
                            capturedAt: Date = Date()) throws -> SyncOperation {
        guard let engine = engine else { throw Failure.engineUnavailable }
        let asset = try SyncAssetWriter.importFile(at: source,
                                                   in: engine.store.assetsDirectory,
                                                   scope: orderProductUniqueId ?? orderUniqueId,
                                                   fieldName: MediaOperationBuilder.fieldName,
                                                   mimeType: mimeType)
        let capture = MediaCapture(kind: kind,
                                   orderUniqueId: orderUniqueId,
                                   orderProductUniqueId: orderProductUniqueId,
                                   checklistExecutionId: checklistExecutionId,
                                   equipmentUniqueId: equipmentUniqueId,
                                   label: label,
                                   capturedAt: capturedAt,
                                   asset: asset)
        return try MediaOperationBuilder.enqueue(capture, into: engine)
    }

    /// Driver's license side: JPEG bytes → protected asset → durable upload operation.
    @discardableResult
    static func enqueueLicense(jpeg: Data,
                               side: String,
                               orderUniqueId: String,
                               licenseExpiryDate: String? = nil,
                               autoInjectBy: String? = nil,
                               capturedAt: Date = Date()) throws -> SyncOperation {
        guard let engine = engine else { throw Failure.engineUnavailable }
        guard !jpeg.isEmpty else { throw Failure.encodingFailed }
        let asset = try SyncAssetWriter.store(jpeg,
                                              in: engine.store.assetsDirectory,
                                              scope: "license-" + orderUniqueId,
                                              fieldName: MediaOperationBuilder.fieldName,
                                              mimeType: "image/jpeg",
                                              fileExtension: "jpg")
        let capture = MediaCapture(kind: .license,
                                   orderUniqueId: orderUniqueId,
                                   orderProductUniqueId: nil,
                                   side: side,
                                   licenseExpiryDate: licenseExpiryDate,
                                   autoInjectBy: autoInjectBy,
                                   capturedAt: capturedAt,
                                   asset: asset)
        return try MediaOperationBuilder.enqueue(capture, into: engine)
    }

    /// Files the phone still holds for an order (pending, in flight, or needing attention).
    static func pendingItems(orderUniqueId: String, kind: MediaKind? = nil) -> [KabbaPendingMedia] {
        guard let engine = engine else { return [] }
        let assetsDirectory = engine.store.assetsDirectory
        return engine.snapshot().compactMap { op -> KabbaPendingMedia? in
            guard let opKind = MediaKind.from(operationType: op.type), op.state != .synced else { return nil }
            if let kind = kind, kind != opKind { return nil }
            guard op.identity.orderUniqueId == orderUniqueId, let asset = op.assets.first else { return nil }
            let url = SyncAssetWriter.url(of: asset, in: assetsDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return KabbaPendingMedia(operationId: op.id,
                                     clientMediaId: asset.clientMediaId,
                                     kind: opKind,
                                     orderUniqueId: orderUniqueId,
                                     orderProductUniqueId: op.identity.orderProductUniqueId,
                                     side: op.payload["side"]?.stringValue,
                                     isVideo: asset.mimeType.hasPrefix("video/"),
                                     fileURL: url,
                                     state: op.state,
                                     attentionReason: op.attentionReason)
        }
    }

    static func hasPendingMedia(orderUniqueId: String, kind: MediaKind) -> Bool {
        !pendingItems(orderUniqueId: orderUniqueId, kind: kind).isEmpty
    }

    /// The pending license side still on the phone, if any (for the capture screen's preview only).
    static func pendingLicenseData(orderUniqueId: String, side: String) -> Data? {
        guard let item = pendingItems(orderUniqueId: orderUniqueId, kind: .license).last(where: { $0.side == side }) else { return nil }
        return try? Data(contentsOf: item.fileURL)
    }

    // MARK: Driver's license on this phone (MOBILE-QUALITY-01, item 06)

    /// The latest local copy of each license side for the order — what the license screens show
    /// before anything the order record says (see LocalLicense).
    static func localLicense(orderUniqueId: String) -> [String: LocalLicenseSide] {
        guard let engine = engine else { return [:] }
        return LocalLicense.sides(orderUniqueId: orderUniqueId, operations: engine.snapshot())
    }

    /// The image bytes of a local copy, while the phone still holds the file.
    static func licenseImageData(_ copy: LocalLicenseSide) -> Data? {
        guard let engine = engine, let asset = copy.asset else { return nil }
        return try? Data(contentsOf: SyncAssetWriter.url(of: asset, in: engine.store.assetsDirectory))
    }

    struct LicenseSave: Equatable {
        /// Sides queued by this save ("front" / "back"); empty = everything was already on this phone.
        let queuedSides: [String]
        let operationIds: [String]
        /// Sides whose copy on this phone Kabba refused and that this save did not replace.
        let refusedSides: [String]
    }

    /// The license screens' one Save (MOBILE-QUALITY-01, item 06).
    ///
    /// - Queues only the sides that need it: a retaken image, or license details the side's
    ///   copy does not carry yet.
    /// - The image sent for a side is the employee's new photo; for an unchanged side, the exact
    ///   file already saved on this phone; failing that, the order's own image ONLY if it was
    ///   confirmed loaded on screen (`trustedImageSides`) — never a placeholder. Otherwise the
    ///   save stops with `imageNotAvailable` and nothing is queued.
    /// - A save without license details keeps the expiration / employee already saved here.
    /// - New copies are durable before older WAITING copies of the same sides are retired
    ///   (with a removal trace); if any new copy cannot be stored, the ones already queued are
    ///   taken back and the save fails as a whole.
    static func saveLicense(orderUniqueId: String,
                            changedSides: Set<String>,
                            licenseExpiryDate: String? = nil,
                            autoInjectBy: String? = nil,
                            trustedImageSides: Set<String> = [],
                            jpeg: (String) -> Data?) throws -> LicenseSave {
        guard let engine = engine else { throw Failure.engineUnavailable }
        let before = engine.snapshot()
        let existing = LocalLicense.sides(orderUniqueId: orderUniqueId, operations: before)
        let sides = LocalLicense.sidesToQueue(changed: changedSides, expiryDate: licenseExpiryDate,
                                              autoInjectBy: autoInjectBy, existing: existing)
        let expiry = nonEmpty(licenseExpiryDate) ?? LocalLicense.expiryDate(existing)
        let employee = nonEmpty(autoInjectBy) ?? existing["front"]?.autoInjectBy ?? existing["back"]?.autoInjectBy

        var bytes: [String: Data] = [:]
        for side in sides {
            if changedSides.contains(side) {
                guard let data = jpeg(side), !data.isEmpty else { throw Failure.encodingFailed }
                bytes[side] = data
            } else if let copy = existing[side], let data = licenseImageData(copy) {
                bytes[side] = data                       // exactly what was saved — never re-encoded
            } else if trustedImageSides.contains(side), let data = jpeg(side), !data.isEmpty {
                bytes[side] = data                       // the order's own image, confirmed loaded
            } else {
                throw Failure.imageNotAvailable(side: side)
            }
        }

        var queued: [SyncOperation] = []
        do {
            for side in sides {
                queued.append(try enqueueLicense(jpeg: bytes[side]!, side: side, orderUniqueId: orderUniqueId,
                                                 licenseExpiryDate: expiry, autoInjectBy: employee))
            }
        } catch {
            for op in queued { _ = try? engine.remove(operationId: op.id) }   // all or nothing
            throw error
        }
        for side in sides {
            for id in LocalLicense.replacedBy(side: side, orderUniqueId: orderUniqueId, operations: before) {
                // An older copy already being sent stays (Laravel keeps the last image per side).
                _ = try? KabbaSync.removeRecord(id, engine: engine, reason: "Replaced by a newer copy saved on this phone.")
            }
        }
        if !queued.isEmpty { NotificationCenter.default.post(name: .kabbaSyncQueueChanged, object: nil) }
        let refused = LocalLicense.sides.filter { !sides.contains($0) && existing[$0]?.state == .needsAttention }
        return LicenseSave(queuedSides: sides, operationIds: queued.map(\.id), refusedSides: refused)
    }

    /// The confirmation a license save shows (non-blocking, ~1 s): it never says Kabba has it.
    static func licenseSavedMessage(_ save: LicenseSave) -> String {
        if !save.queuedSides.isEmpty { return "Driver's license saved on this phone. Will sync when available." }
        if !save.refusedSides.isEmpty { return "Kabba refused the license saved on this phone. Review it in Settings › Sync." }
        return "Driver's license already saved on this phone."
    }

    /// What to tell the employee when a license save could not be stored.
    static func licenseSaveFailureMessage(_ error: Error) -> String {
        if case Failure.imageNotAvailable(let side)? = error as? Failure {
            return "The \(side) of the license isn't loaded on this phone. Reconnect and open the license again, or retake the \(side)."
        }
        return "The license could not be saved on this phone. Please try again."
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }
}
