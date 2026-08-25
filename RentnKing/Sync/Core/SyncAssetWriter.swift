//
//  SyncAssetWriter.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Durably stores a file that belongs to an operation (today: the customer
//  signature) inside the protected assets directory and returns the SyncAsset
//  record with a stable client_media_id. Bytes in, protected file out — the
//  engine never holds media in memory, and cleanup only ever follows a server
//  acknowledgment.
//

import Foundation

enum SyncAssetWriter {

    /// Writes `data` to `<assets>/<scope>/<clientMediaId>.<ext>` with Data Protection.
    static func store(_ data: Data,
                      in assetsDirectory: URL,
                      scope: String,
                      fieldName: String,
                      mimeType: String,
                      fileExtension: String,
                      clientMediaId: String = UUID().uuidString.lowercased(),
                      fileManager: FileManager = .default) throws -> SyncAsset {
        let safeScope = scope.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        let scopeDir = assetsDirectory.appendingPathComponent(String(String.UnicodeScalarView(safeScope)), isDirectory: true)
        try FileSyncOperationStore.ensureProtectedDirectory(scopeDir, fileManager: fileManager)

        let filename = "\(clientMediaId).\(fileExtension)"
        let url = scopeDir.appendingPathComponent(filename)
        try FileSyncOperationStore.writeProtected(data, to: url)

        return SyncAsset(clientMediaId: clientMediaId,
                         relativePath: scopeDir.lastPathComponent + "/" + filename,
                         mimeType: mimeType,
                         fieldName: fieldName,
                         byteCount: Int64(data.count))
    }

    /// Removes an asset file. Only call after the server acknowledged the operation.
    static func remove(_ asset: SyncAsset, in assetsDirectory: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: assetsDirectory.appendingPathComponent(asset.relativePath))
    }
}
