//
//  DispatchOfflineMissionStore.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Dispatch offline mission cache — Phase 3. The phone's DURABLE copy of the
//  company-wide Dispatch working set, per tenant (the login's api_url):
//
//    <KabbaSync>/dispatch-offline/v1/<tenantKey>/
//        index.json            the ACTIVE index — replaced atomically
//        packages/*.json       one IMMUTABLE file per (mission, revision)
//        quarantine/           undecodable files moved aside (newest 20)
//
//  Same protection as the Sync Engine (completeUntilFirstUserAuthentication,
//  so a background wake after first unlock can read and write; the KabbaSync
//  root is excluded from backup). A new revision is always a NEW file, so a
//  failed or partial replacement can never destroy the previous valid
//  package; the index only ever points at files already on disk.
//
//  Cleanup (D7) only ever touches this store's own packages/ directory: a file
//  no longer referenced by the active index is RETIRED, and purged only after
//  a 7-day grace AND once no Sync Engine operation references its order
//  product. Sync Engine operations, media, signatures, checklist answers and
//  ChecklistContextStore are never read or written here.
//

import Foundation

enum DispatchOfflineTenant {
    /// scheme://host[:port]/path — scheme and host lowercased, no trailing slash.
    static func normalizedBaseURL(_ url: URL) -> String {
        let scheme = (url.scheme ?? "https").lowercased()
        let host = (url.host ?? "").lowercased()
        let port = url.port.map { ":\($0)" } ?? ""
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return "\(scheme)://\(host)\(port)\(path)"
    }

    static func key(baseURL: URL) -> String {
        String(format: "%016llx", fnv1a64(normalizedBaseURL(baseURL)))
    }

    static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }
}

struct DispatchOfflineIndex: Codable, Equatable {
    static let currentSchema = 1

    struct Entry: Codable, Equatable {
        var missionKey: String
        var orderProductUniqueId: String
        var leg: ChecklistLeg
        var effectiveDate: String
        /// The revision the latest manifest reported.
        var serverRevision: String
        /// The revision of the package on disk (nil = not downloaded yet).
        var readyRevision: String?
        var packageFile: String?
        /// When the server was last asked for this mission and answered with exactly the ready
        /// revision (a manifest confirming it, or its package download) — its content is server
        /// truth at least that new, even when the file on disk is older (review 3 #2).
        var confirmedAt: Date? = nil

        var isReady: Bool { readyRevision != nil && packageFile != nil }
        /// Presented from an older package while the newer one could not be downloaded yet.
        var isStale: Bool { isReady && readyRevision != serverRevision }
        var isCurrent: Bool { isReady && readyRevision == serverRevision }

        enum CodingKeys: String, CodingKey {
            case missionKey = "mission_key", orderProductUniqueId = "order_product_unique_id", leg
            case effectiveDate = "effective_date", serverRevision = "server_revision"
            case readyRevision = "ready_revision", packageFile = "package_file", confirmedAt = "confirmed_at"
        }
    }

    struct Retired: Codable, Equatable {
        var packageFile: String
        var orderProductUniqueId: String
        /// When the file first stopped being referenced by the active index.
        var retiredAt: Date

        enum CodingKeys: String, CodingKey {
            case packageFile = "package_file", orderProductUniqueId = "order_product_unique_id", retiredAt = "retired_at"
        }
    }

    var schema: Int
    var tenantKey: String
    var baseURL: String
    /// The manifest revision last applied.
    var manifestRevision: String?
    var throughDate: String?
    /// Last successful manifest fetch (the "list saved at" time).
    var lastManifestAt: Date?
    /// The manifest time of the last run that left EVERY active mission at its manifest
    /// revision — the only marker that makes a later foreground / Dispatch open "fresh".
    /// A partial or failed run never advances it (review F1).
    var lastCurrentAt: Date?
    var committedAt: Date?
    /// True once a reconciliation has committed at least once for this tenant.
    var everCommitted: Bool
    var entries: [Entry]
    var retired: [Retired]

    static func empty(tenantKey: String, baseURL: String) -> DispatchOfflineIndex {
        DispatchOfflineIndex(schema: currentSchema, tenantKey: tenantKey, baseURL: baseURL, manifestRevision: nil,
                             throughDate: nil, lastManifestAt: nil, lastCurrentAt: nil, committedAt: nil, everCommitted: false,
                             entries: [], retired: [])
    }

    func entry(_ missionKey: String) -> Entry? { entries.first { $0.missionKey == missionKey } }

    /// Every entry presentable with its latest revision.
    var isFullyCurrent: Bool { entries.allSatisfy(\.isCurrent) }

    /// What the Dispatch screen can show: (mission, package revision) of every ready entry.
    var presentableSignature: [String] {
        entries.filter(\.isReady).map { "\($0.missionKey)@\($0.readyRevision ?? "")" }.sorted()
    }

    enum CodingKeys: String, CodingKey {
        case schema, tenantKey = "tenant_key", baseURL = "base_url", manifestRevision = "manifest_revision"
        case throughDate = "through_date", lastManifestAt = "last_manifest_at", lastCurrentAt = "last_current_at"
        case committedAt = "committed_at"
        case everCommitted = "ever_committed", entries, retired
    }
}

struct DispatchOfflineStoredPackage: Codable, Equatable {
    static let currentSchema = 1

    let schema: Int
    let tenantKey: String
    let missionKey: String
    let revision: String
    let orderProductUniqueId: String
    let leg: ChecklistLeg
    let cachedAt: Date
    /// When the server was ASKED for this package: its server truth is at least that new.
    /// A driver action the server confirmed after this moment is not reflected in it yet
    /// (review F2). nil for files written before the field existed.
    let serverObservedAt: Date?
    /// The package exactly as Laravel served it.
    let package: JSONValue

    var row: JSONValue? { package["dispatch"]?["row"] }

    enum CodingKeys: String, CodingKey {
        case schema, tenantKey = "tenant_key", missionKey = "mission_key", revision
        case orderProductUniqueId = "order_product_unique_id", leg, cachedAt = "cached_at"
        case serverObservedAt = "server_observed_at", package
    }
}

enum DispatchOfflineStoreError: Error, Equatable {
    case injectedFailure(String)
}

final class DispatchOfflineMissionStore {
    static let graceInterval: TimeInterval = 7 * 86_400
    static let quarantineLimit = 20

    let rootDirectory: URL
    let tenantKey: String
    let baseURL: String
    let directory: URL
    let packagesDirectory: URL
    let quarantineDirectory: URL
    let indexURL: URL

    /// Test seams: make the next write fail as a crash / full disk would.
    var failNextIndexCommit = false
    var failNextPackageWrite = false

    private let fileManager: FileManager
    private let encoder = KabbaISO8601.makeEncoder()
    private let decoder = KabbaISO8601.makeDecoder()
    private let lock = NSLock()
    /// Package files are immutable, so a decoded file can be cached by name.
    private var decoded: [String: DispatchOfflineStoredPackage] = [:]

    init(rootDirectory: URL, baseURL: URL, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory
        self.tenantKey = DispatchOfflineTenant.key(baseURL: baseURL)
        self.baseURL = DispatchOfflineTenant.normalizedBaseURL(baseURL)
        self.directory = rootDirectory.appendingPathComponent("dispatch-offline", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent(tenantKey, isDirectory: true)
        self.packagesDirectory = directory.appendingPathComponent("packages", isDirectory: true)
        self.quarantineDirectory = directory.appendingPathComponent("quarantine", isDirectory: true)
        self.indexURL = directory.appendingPathComponent("index.json")
        for dir in [directory, packagesDirectory, quarantineDirectory] {
            try FileSyncOperationStore.ensureProtectedDirectory(dir, fileManager: fileManager)
        }
    }

    // MARK: - Index

    /// The active index. Missing, unreadable, another schema or another tenant → "no cache yet".
    func loadIndex() -> DispatchOfflineIndex {
        lock.withLock {
            let empty = DispatchOfflineIndex.empty(tenantKey: tenantKey, baseURL: baseURL)
            guard let data = try? Data(contentsOf: indexURL) else { return empty }
            guard let index = try? decoder.decode(DispatchOfflineIndex.self, from: data) else {
                quarantineLocked(indexURL)
                return empty
            }
            guard index.schema == DispatchOfflineIndex.currentSchema, index.tenantKey == tenantKey, index.baseURL == baseURL else {
                return empty
            }
            return index
        }
    }

    /// Atomic replace (temp file + rename): readers see the old index or the new one, never a mix.
    func commit(_ index: DispatchOfflineIndex) throws {
        var copy = index
        copy.schema = DispatchOfflineIndex.currentSchema
        copy.tenantKey = tenantKey
        copy.baseURL = baseURL
        copy.entries.sort { $0.missionKey < $1.missionKey }
        let data = try encoder.encode(copy)
        try lock.withLock {
            if failNextIndexCommit {
                failNextIndexCommit = false
                throw DispatchOfflineStoreError.injectedFailure("index commit")
            }
            try FileSyncOperationStore.writeProtected(data, to: indexURL)
        }
    }

    // MARK: - Packages

    static func packageFileName(orderProductUniqueId: String, leg: ChecklistLeg, revision: String) -> String {
        let safe = String(String.UnicodeScalarView(orderProductUniqueId.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }))
        return "\(safe)__\(leg.rawValue)__\(revision).json"
    }

    @discardableResult
    func writePackage(_ package: DispatchOfflinePackage, cachedAt: Date, serverObservedAt: Date? = nil) throws -> String {
        let name = DispatchOfflineMissionStore.packageFileName(orderProductUniqueId: package.orderProductUniqueId,
                                                               leg: package.leg, revision: package.revision)
        let stored = DispatchOfflineStoredPackage(schema: DispatchOfflineStoredPackage.currentSchema, tenantKey: tenantKey,
                                                  missionKey: package.missionKey, revision: package.revision,
                                                  orderProductUniqueId: package.orderProductUniqueId, leg: package.leg,
                                                  cachedAt: cachedAt, serverObservedAt: serverObservedAt, package: package.object)
        let data = try encoder.encode(stored)
        try lock.withLock {
            if failNextPackageWrite {
                failNextPackageWrite = false
                throw DispatchOfflineStoreError.injectedFailure("package write")
            }
            try FileSyncOperationStore.writeProtected(data, to: packagesDirectory.appendingPathComponent(name))
            decoded[name] = stored
        }
        return name
    }

    /// The decoded file, or nil when it is missing; an undecodable file is quarantined.
    func loadPackage(file: String) -> DispatchOfflineStoredPackage? {
        lock.withLock { loadLocked(file) }
    }

    /// The entry's package, only when it is exactly that mission at that revision.
    func readyPackage(for entry: DispatchOfflineIndex.Entry) -> DispatchOfflineStoredPackage? {
        guard let file = entry.packageFile, let revision = entry.readyRevision,
              let stored = loadPackage(file: file),
              stored.missionKey == entry.missionKey, stored.revision == revision, stored.tenantKey == tenantKey else {
            return nil
        }
        return stored
    }

    /// A valid file already on disk for (mission, revision) — e.g. left by an interrupted run.
    func validPackageFile(missionKey: String, orderProductUniqueId: String, leg: ChecklistLeg, revision: String) -> String? {
        let name = DispatchOfflineMissionStore.packageFileName(orderProductUniqueId: orderProductUniqueId, leg: leg, revision: revision)
        guard let stored = loadPackage(file: name), stored.missionKey == missionKey, stored.revision == revision,
              stored.tenantKey == tenantKey else { return nil }
        return name
    }

    // MARK: - Cleanup (D7)

    /// Retires newly unreferenced files and purges retired files whose grace has passed
    /// and whose order product has no Sync Engine operation. Returns the updated index
    /// (the caller commits it). Only this store's packages/ directory is touched.
    func collectGarbage(_ index: DispatchOfflineIndex, retainingOrderProducts retained: Set<String>, now: Date) -> DispatchOfflineIndex {
        lock.withLock {
            var index = index
            let onDisk = Set(((try? fileManager.contentsOfDirectory(atPath: packagesDirectory.path)) ?? [])
                .filter { $0.hasSuffix(".json") })
            let referenced = Set(index.entries.compactMap(\.packageFile))

            // Referenced again, or already gone → no longer retired.
            index.retired.removeAll { referenced.contains($0.packageFile) || !onDisk.contains($0.packageFile) }

            // Newly unreferenced (a removed mission, a superseded revision, or an orphan) → retired now.
            let known = Set(index.retired.map(\.packageFile))
            for file in onDisk.subtracting(referenced).subtracting(known).sorted() {
                guard let stored = loadLocked(file) else { continue } // undecodable → quarantined
                index.retired.append(.init(packageFile: file, orderProductUniqueId: stored.orderProductUniqueId, retiredAt: now))
            }

            index.retired.removeAll { retiredFile in
                guard now.timeIntervalSince(retiredFile.retiredAt) >= DispatchOfflineMissionStore.graceInterval,
                      !retained.contains(retiredFile.orderProductUniqueId) else { return false }
                try? fileManager.removeItem(at: packagesDirectory.appendingPathComponent(retiredFile.packageFile))
                decoded[retiredFile.packageFile] = nil
                return true
            }
            index.retired.sort { $0.packageFile < $1.packageFile }
            return index
        }
    }

    // MARK: - Internals (lock held)

    private func loadLocked(_ file: String) -> DispatchOfflineStoredPackage? {
        if let hit = decoded[file] { return hit }
        let url = packagesDirectory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let stored = try? decoder.decode(DispatchOfflineStoredPackage.self, from: data),
              stored.schema == DispatchOfflineStoredPackage.currentSchema else {
            quarantineLocked(url)
            return nil
        }
        decoded[file] = stored
        return stored
    }

    private func quarantineLocked(_ url: URL) {
        let target = quarantineDirectory.appendingPathComponent(
            url.lastPathComponent + "." + String(Int(Date().timeIntervalSince1970 * 1000)) + ".corrupt")
        try? fileManager.moveItem(at: url, to: target)
        decoded[url.lastPathComponent] = nil

        let files = ((try? fileManager.contentsOfDirectory(at: quarantineDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da == db ? a.lastPathComponent < b.lastPathComponent : da < db
            }
        for old in files.dropLast(DispatchOfflineMissionStore.quarantineLimit) {
            try? fileManager.removeItem(at: old)
        }
    }
}
