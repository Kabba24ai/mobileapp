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
}
