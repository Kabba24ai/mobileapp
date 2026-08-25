//
//  InstallationIdentity.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The value sent as X-Device-Id: a UUID minted on first use and kept in the
//  protected KabbaSync directory. It identifies THIS INSTALL of the app for
//  operational diagnostics ("which phone's queue is stuck") and nothing else:
//  not IDFA/IDFV, not a hardware fingerprint, not shared with other apps, and
//  it resets when the app is deleted.
//

import Foundation

final class InstallationIdentity {
    static let filename = "installation_id"

    let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var cached: String?

    init(directory: URL, fileManager: FileManager = .default) {
        self.fileURL = directory.appendingPathComponent(InstallationIdentity.filename)
        self.fileManager = fileManager
    }

    /// "install-<UUID>" — matches the server's X-Device-Id whitelist ([A-Za-z0-9._:-]{8,128}).
    func identifier() -> String {
        lock.withLock {
            if let cached = cached { return cached }
            if let data = try? Data(contentsOf: fileURL),
               let existing = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               InstallationIdentity.isValid(existing) {
                cached = existing
                return existing
            }
            let fresh = "install-" + UUID().uuidString
            try? FileSyncOperationStore.ensureProtectedDirectory(fileURL.deletingLastPathComponent(), fileManager: fileManager)
            try? FileSyncOperationStore.writeProtected(Data(fresh.utf8), to: fileURL)
            cached = fresh
            return fresh
        }
    }

    static func isValid(_ value: String) -> Bool {
        guard (8...128).contains(value.count) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:-"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
