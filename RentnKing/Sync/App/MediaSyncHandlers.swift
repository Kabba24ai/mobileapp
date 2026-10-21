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

    enum Failure: Error {
        case engineUnavailable
        case encodingFailed
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
    }

    /// The license screens' one Save. Queues only the sides that need it (a changed image, or
    /// license details the side's copy does not carry yet); a copy of the same side still
    /// WAITING to send is replaced by the new one instead of uploaded twice. The new copy is
    /// durable before the old one is retired. Throws when the phone could not store it —
    /// nothing may be called saved then.
    static func saveLicense(orderUniqueId: String,
                            changedSides: Set<String>,
                            licenseExpiryDate: String? = nil,
                            autoInjectBy: String? = nil,
                            jpeg: (String) -> Data?) throws -> LicenseSave {
        guard let engine = engine else { throw Failure.engineUnavailable }
        let before = engine.snapshot()
        let existing = LocalLicense.sides(orderUniqueId: orderUniqueId, operations: before)
        let sides = LocalLicense.sidesToQueue(changed: changedSides, expiryDate: licenseExpiryDate,
                                              autoInjectBy: autoInjectBy, existing: existing)
        // Encode every side first: a side that cannot be stored stops the save before anything is queued.
        var bytes: [String: Data] = [:]
        for side in sides {
            guard let data = jpeg(side), !data.isEmpty else { throw Failure.encodingFailed }
            bytes[side] = data
        }
        var ids: [String] = []
        for side in sides {
            let replaced = LocalLicense.replacedBy(side: side, orderUniqueId: orderUniqueId, operations: before)
            let op = try enqueueLicense(jpeg: bytes[side]!, side: side, orderUniqueId: orderUniqueId,
                                        licenseExpiryDate: licenseExpiryDate, autoInjectBy: autoInjectBy)
            ids.append(op.id)
            // An older copy already being sent stays (Laravel keeps the last image per side).
            for id in replaced { _ = try? engine.remove(operationId: id) }
        }
        if !ids.isEmpty { NotificationCenter.default.post(name: .kabbaSyncQueueChanged, object: nil) }
        return LicenseSave(queuedSides: sides, operationIds: ids)
    }

    /// The confirmation a license save shows (non-blocking, ~1 s): it never says Kabba has it.
    static func licenseSavedMessage(_ save: LicenseSave) -> String {
        save.queuedSides.isEmpty
            ? "Driver's license already saved on this phone."
            : "Driver's license saved on this phone. Will sync when available."
    }
}
