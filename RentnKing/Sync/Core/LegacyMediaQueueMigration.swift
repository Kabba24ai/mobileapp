//
//  LegacyMediaQueueMigration.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Converts the pre-Phase-4 Core Data upload queue (`UploadData` rows: photos,
//  videos and licence images uploaded in order-level batches by
//  BackgroundUploader) into per-file Sync Engine operations.
//
//  The Core Data access and the file moves live in the app layer; this file is
//  the pure conversion so it is unit-testable:
//
//    • business association is preserved (order, order product, licence side,
//      expiry / auto-inject attribution),
//    • a fresh client_media_id is assigned (the legacy queue never had one),
//    • records that cannot be converted are reported — the caller QUARANTINES
//      them (status "QUARANTINED"), it never deletes.
//
//  A legacy upload that succeeded server-side but whose local status was never
//  flipped cannot be detected here (no client id existed); the server-side
//  duplicate guard does not apply to those and one duplicate is possible for
//  that specific interrupted case. Documented in the contract.
//

import Foundation

/// A snapshot of one legacy `UploadData` row (Core Data entity, app layer).
struct LegacyUploadRecord: Equatable {
    var orderID: String
    /// "image" (= driver's licence) | "video_image" (= delivery / pickup media)
    var type: String
    /// "delivery" | "pickup" for video_image rows
    var videoType: String
    var productID: String
    /// File name inside ImageVideo/<order>/ or LicenseUpload/
    var name: String
    var isImage: Bool
    var imageSide: String
    var licenseExpiryDate: String
    var autoInjectBy: String
    var status: String
}

enum LegacyMediaQueueMigration {

    struct Plan: Equatable {
        let kind: MediaKind
        let orderUniqueId: String
        let orderProductUniqueId: String?
        let side: String?
        let licenseExpiryDate: String?
        let autoInjectBy: String?
        let mimeType: String
        let fileExtension: String
        /// Relative to the legacy media root: "ImageVideo/<order>/<name>" or "LicenseUpload/<name>".
        let legacyRelativePath: String
    }

    enum Problem: Error, Equatable {
        case notPending
        case missingOrder
        case missingOrderProduct
        case missingFileName
        case missingSide
        case unknownType
    }

    static func convert(_ record: LegacyUploadRecord) -> Result<Plan, Problem> {
        guard record.status == "Pending" else { return .failure(.notPending) }
        guard !record.orderID.isEmpty else { return .failure(.missingOrder) }
        guard !record.name.isEmpty else { return .failure(.missingFileName) }

        switch record.type {
        case "image":
            let side = record.imageSide.lowercased()
            guard side == "front" || side == "back" else { return .failure(.missingSide) }
            return .success(Plan(kind: .license,
                                 orderUniqueId: record.orderID,
                                 orderProductUniqueId: nil,
                                 side: side,
                                 licenseExpiryDate: record.licenseExpiryDate.isEmpty ? nil : record.licenseExpiryDate,
                                 autoInjectBy: record.autoInjectBy.isEmpty ? nil : record.autoInjectBy,
                                 mimeType: "image/jpeg",
                                 fileExtension: "jpg",
                                 legacyRelativePath: "LicenseUpload/\(record.name)"))

        case "video_image":
            guard !record.productID.isEmpty else { return .failure(.missingOrderProduct) }
            let kind: MediaKind = record.videoType.lowercased() == "pickup" ? .pickup : .delivery
            let ext = (record.name as NSString).pathExtension.lowercased()
            let mime: String
            let fileExtension: String
            if record.isImage {
                mime = "image/jpeg"
                fileExtension = ext.isEmpty ? "jpg" : ext
            } else {
                mime = ext == "mp4" ? "video/mp4" : "video/quicktime"
                fileExtension = ext.isEmpty ? "mov" : ext
            }
            return .success(Plan(kind: kind,
                                 orderUniqueId: record.orderID,
                                 orderProductUniqueId: record.productID,
                                 side: nil,
                                 licenseExpiryDate: nil,
                                 autoInjectBy: nil,
                                 mimeType: mime,
                                 fileExtension: fileExtension,
                                 legacyRelativePath: "ImageVideo/\(record.orderID)/\(record.name)"))

        default:
            return .failure(.unknownType)
        }
    }

    /// Builds the capture for a converted plan once the file has been imported into the
    /// protected assets directory. `capturedAt` falls back to the file's modification date.
    static func capture(for plan: Plan, asset: SyncAsset, capturedAt: Date) -> MediaCapture {
        MediaCapture(kind: plan.kind,
                     orderUniqueId: plan.orderUniqueId,
                     orderProductUniqueId: plan.orderProductUniqueId,
                     checklistExecutionId: nil,
                     equipmentUniqueId: nil,
                     side: plan.side,
                     licenseExpiryDate: plan.licenseExpiryDate,
                     autoInjectBy: plan.autoInjectBy,
                     label: "migrated",
                     capturedAt: capturedAt,
                     asset: asset)
    }
}
