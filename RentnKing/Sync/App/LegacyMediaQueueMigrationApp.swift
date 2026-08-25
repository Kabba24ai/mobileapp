//
//  LegacyMediaQueueMigrationApp.swift
//  RentnKing — Sync App layer (CoreData)
//
//  Phase 4, Step 24 — moves every still-Pending row of the legacy Core Data upload
//  queue (photos, videos, licence images) into per-file Sync Engine operations.
//  The pure conversion lives in Sync/Core/LegacyMediaQueueMigration.swift; this
//  file only reads Core Data, moves files and stamps row statuses. Rows are NEVER
//  deleted: MIGRATED or QUARANTINED.
//

import Foundation
import CoreData

// MARK: - Legacy Core Data upload queue → Sync Engine (Step 24)

/// Status stamped on legacy rows whose file was moved into the engine. Never deleted.
let kLegacyMediaMigratedStatus = "MIGRATED"
/// Status stamped on legacy rows that could not be converted (file missing, no product…). Never deleted.
let kLegacyMediaQuarantinedStatus = "QUARANTINED"

/// Converts every still-Pending `UploadData` row into a durable per-file media operation.
/// Idempotent per launch: rows are re-stamped MIGRATED / QUARANTINED, so a second pass finds
/// nothing Pending. Must run on the main thread (Core Data view context) and only after the
/// legacy BackgroundUploader reported no in-flight tasks — otherwise a legacy upload that is
/// about to succeed would be uploaded twice.
func migrateLegacyMediaQueueIntoSyncEngine() {
    guard let engine = KabbaSync.engine else { return }
    let rows = CoreDBManager.sharedDatabase.getAllUploadDATA(status: "Pending")
    guard !rows.isEmpty else { return }

    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    var migrated = 0
    var quarantined = 0

    for row in rows {
        let record = LegacyUploadRecord(orderID: row.orderID ?? "",
                                        type: row.type ?? "",
                                        videoType: row.videoType ?? "",
                                        productID: row.productID ?? "",
                                        name: row.name ?? "",
                                        isImage: row.isImage,
                                        imageSide: row.image_side ?? "",
                                        licenseExpiryDate: row.license_expiry_date ?? "",
                                        autoInjectBy: row.auto_inject_by ?? "",
                                        status: row.status ?? "")

        switch LegacyMediaQueueMigration.convert(record) {
        case .failure:
            row.status = kLegacyMediaQuarantinedStatus
            quarantined += 1

        case .success(let plan):
            let source = documents.appendingPathComponent(plan.legacyRelativePath)
            guard FileManager.default.fileExists(atPath: source.path) else {
                row.status = kLegacyMediaQuarantinedStatus
                quarantined += 1
                continue
            }
            let modified = (try? FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate] as? Date) ?? Date()
            do {
                let asset = try SyncAssetWriter.importFile(at: source,
                                                           in: engine.store.assetsDirectory,
                                                           scope: plan.orderProductUniqueId ?? ("license-" + plan.orderUniqueId),
                                                           fieldName: MediaOperationBuilder.fieldName,
                                                           mimeType: plan.mimeType,
                                                           fileExtension: plan.fileExtension)
                _ = try MediaOperationBuilder.enqueue(LegacyMediaQueueMigration.capture(for: plan, asset: asset, capturedAt: modified), into: engine)
                row.status = kLegacyMediaMigratedStatus
                migrated += 1
            } catch {
                row.status = kLegacyMediaQuarantinedStatus
                quarantined += 1
            }
        }
    }

    CoreDBManager.sharedDatabase.saveContext()
    debugPrint("Media queue: migrated \(migrated) legacy file(s) into the Sync Engine, quarantined \(quarantined)")
}
