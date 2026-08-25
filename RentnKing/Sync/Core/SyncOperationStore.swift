//
//  SyncOperationStore.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Durable persistence for SyncOperation records: one JSON file per operation,
//  written atomically, under the app's Application Support directory with iOS
//  Data Protection (readable after first unlock so background sync works) and
//  excluded from iCloud/iTunes backup (the records are transient and may carry
//  signatures / licence evidence later).
//
//  Why files and not MMKV: MMKV is one memory-mapped blob — fine for small
//  preferences, wrong for growing payloads and for media that must sit next to
//  its record. A per-operation file survives app kill / OS termination / reboot,
//  is cheap to inspect, and a corrupt record is QUARANTINED, never deleted.
//

import Foundation

protocol SyncOperationStore: AnyObject {
    /// Durably persists the record. Returns only after the bytes are on disk.
    func save(_ operation: SyncOperation) throws
    func load(id: String) throws -> SyncOperation?
    func loadAll() throws -> [SyncOperation]
    func delete(id: String) throws
    /// Where operation assets (photos, videos, signatures) live; SyncAsset.relativePath is relative to this.
    var assetsDirectory: URL { get }
}

enum SyncStoreError: Error, Equatable {
    case directoryUnavailable(String)
}

final class FileSyncOperationStore: SyncOperationStore {

    let rootDirectory: URL
    let operationsDirectory: URL
    let assetsDirectory: URL
    /// Undecodable records are moved here (with their original bytes) for a human to inspect.
    let quarantineDirectory: URL

    /// Records that failed to decode during this process's lifetime.
    private(set) var quarantined: [URL] = []

    private let fileManager: FileManager
    private let encoder = KabbaISO8601.makeEncoder()
    private let decoder = KabbaISO8601.makeDecoder()
    private let lock = NSLock()

    /// `<Application Support>/KabbaSync` — created on demand.
    static func defaultRootDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SyncStoreError.directoryUnavailable("Application Support")
        }
        return base.appendingPathComponent("KabbaSync", isDirectory: true)
    }

    init(rootDirectory: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory
        self.operationsDirectory = rootDirectory.appendingPathComponent("operations", isDirectory: true)
        self.assetsDirectory = rootDirectory.appendingPathComponent("assets", isDirectory: true)
        self.quarantineDirectory = rootDirectory.appendingPathComponent("quarantine", isDirectory: true)

        for dir in [rootDirectory, operationsDirectory, assetsDirectory, quarantineDirectory] {
            try FileSyncOperationStore.ensureProtectedDirectory(dir, fileManager: fileManager)
        }

        // Transient-but-sensitive: keep it off iCloud / local backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = rootDirectory
        try? root.setResourceValues(values)
    }

    // MARK: SyncOperationStore

    func save(_ operation: SyncOperation) throws {
        let data = try encoder.encode(operation)
        try lock.withLock {
            try FileSyncOperationStore.writeProtected(data, to: url(for: operation.id))
        }
    }

    func load(id: String) throws -> SyncOperation? {
        try lock.withLock {
            let url = self.url(for: id)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return try decodeOrQuarantine(at: url)
        }
    }

    func loadAll() throws -> [SyncOperation] {
        try lock.withLock {
            let urls = try fileManager.contentsOfDirectory(at: operationsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            var out: [SyncOperation] = []
            out.reserveCapacity(urls.count)
            for url in urls {
                if let op = try decodeOrQuarantine(at: url) {
                    out.append(op)
                }
            }
            return out.sorted { $0.queuedAt < $1.queuedAt }
        }
    }

    func delete(id: String) throws {
        try lock.withLock {
            let url = self.url(for: id)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: Internals

    private func url(for id: String) -> URL {
        // Operation ids are UUID-like; strip anything that is not filename-safe.
        let safe = id.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        return operationsDirectory.appendingPathComponent(String(String.UnicodeScalarView(safe)) + ".json")
    }

    private func decodeOrQuarantine(at url: URL) throws -> SyncOperation? {
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(SyncOperation.self, from: data)
        } catch {
            // Never destroy field evidence because a record is unreadable: move it aside.
            let target = quarantineDirectory.appendingPathComponent(url.lastPathComponent + "." + String(Int(Date().timeIntervalSince1970)) + ".corrupt")
            try? fileManager.moveItem(at: url, to: target)
            quarantined.append(target)
            return nil
        }
    }

    static func ensureProtectedDirectory(_ url: URL, fileManager: FileManager) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS) || os(tvOS) || os(watchOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
        }
    }

    /// Atomic write (temp file + rename) with iOS Data Protection.
    static func writeProtected(_ data: Data, to url: URL) throws {
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS) || os(tvOS) || os(watchOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: url, options: options)
    }
}

/// Test double / preview store. Not durable — never use it in the app.
final class InMemorySyncOperationStore: SyncOperationStore {
    private var records: [String: SyncOperation] = [:]
    private let lock = NSLock()
    let assetsDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("KabbaSyncInMemoryAssets", isDirectory: true)

    init() {}

    func save(_ operation: SyncOperation) throws {
        lock.withLock { records[operation.id] = operation }
    }

    func load(id: String) throws -> SyncOperation? {
        lock.withLock { records[id] }
    }

    func loadAll() throws -> [SyncOperation] {
        lock.withLock { records.values.sorted { $0.queuedAt < $1.queuedAt } }
    }

    func delete(id: String) throws {
        lock.withLock { records[id] = nil }
    }
}

extension NSLock {
    @inline(__always)
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
