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

    /// Moves (or copies) an existing file — a compressed photo, an exported video, a
    /// licence scan — into `<assets>/<scope>/<clientMediaId>.<ext>` with Data Protection.
    /// Used for media that is already on disk so multi-hundred-MB clips are never read
    /// into memory. The source is removed after a successful move; `copy: true` keeps it.
    static func importFile(at source: URL,
                           in assetsDirectory: URL,
                           scope: String,
                           fieldName: String,
                           mimeType: String,
                           fileExtension: String? = nil,
                           clientMediaId: String = UUID().uuidString.lowercased(),
                           copy: Bool = false,
                           fileManager: FileManager = .default) throws -> SyncAsset {
        let safeScope = scope.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        let scopeDir = assetsDirectory.appendingPathComponent(String(String.UnicodeScalarView(safeScope)), isDirectory: true)
        try FileSyncOperationStore.ensureProtectedDirectory(scopeDir, fileManager: fileManager)

        let ext = (fileExtension ?? source.pathExtension).lowercased()
        let filename = ext.isEmpty ? clientMediaId : "\(clientMediaId).\(ext)"
        let destination = scopeDir.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        if copy {
            try fileManager.copyItem(at: source, to: destination)
        } else {
            do {
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                // Cross-volume or permission edge: fall back to copy + delete.
                try fileManager.copyItem(at: source, to: destination)
                try? fileManager.removeItem(at: source)
            }
        }
        #if os(iOS) || os(tvOS) || os(watchOS)
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        #endif

        let size = (try? fileManager.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value
        return SyncAsset(clientMediaId: clientMediaId,
                         relativePath: scopeDir.lastPathComponent + "/" + filename,
                         mimeType: mimeType,
                         fieldName: fieldName,
                         byteCount: size)
    }

    /// Absolute URL of an asset file.
    static func url(of asset: SyncAsset, in assetsDirectory: URL) -> URL {
        assetsDirectory.appendingPathComponent(asset.relativePath)
    }

    static func exists(_ asset: SyncAsset, in assetsDirectory: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: url(of: asset, in: assetsDirectory).path)
    }

    /// Removes an asset file. Only call after the server acknowledged the operation
    /// (or on an explicit, person-initiated discard).
    static func remove(_ asset: SyncAsset, in assetsDirectory: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: assetsDirectory.appendingPathComponent(asset.relativePath))
    }
}
