//
//  ChecklistContextStore.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Durable cache of ChecklistContext snapshots, keyed by order product + leg,
//  under the protected KabbaSync directory (same protection/backup policy as
//  operations). The employee loads an order while connected, loses coverage at
//  the job site, and still has identity + questions + requirements to finish.
//
//  Tenant-scoped (Dispatch offline Phase 4, Amendment B): every company has its
//  own directory, checklist-contexts/<tenantKey>/. A read or write always names
//  a company — the explicit `tenantKey:` variants (bridge, and a live response
//  captured under a known company), or the signed-in company for the screens.
//  Signed out means nothing is read or written. Files written before Phase 4
//  sit directly in checklist-contexts/ with no company: ownership cannot be
//  proven, so they are never read (and never deleted).
//

import Foundation

enum ChecklistContextStoreError: Error, Equatable {
    /// Nobody is signed in: there is no company to read or write for.
    case noTenant
}

final class ChecklistContextStore {

    /// The root of every company's contexts: <KabbaSync>/checklist-contexts/.
    let directory: URL
    private let currentTenant: () -> String?
    private let fileManager: FileManager
    private let encoder = KabbaISO8601.makeEncoder()
    private let decoder = KabbaISO8601.makeDecoder()
    private let lock = NSLock()

    /// `tenantKey` = the signed-in company (DispatchOfflineTenant.key of the login api_url), nil when signed out.
    init(rootDirectory: URL, tenantKey: @escaping () -> String?, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.currentTenant = tenantKey
        self.directory = rootDirectory.appendingPathComponent("checklist-contexts", isDirectory: true)
        try FileSyncOperationStore.ensureProtectedDirectory(directory, fileManager: fileManager)
    }

    static func key(orderProductUniqueId: String, leg: ChecklistLeg) -> String {
        sanitized(orderProductUniqueId) + "__" + leg.rawValue
    }

    /// The signed-in company, if any.
    var currentTenantKey: String? { currentTenant() }

    // MARK: Signed-in company (the screens)

    func save(_ context: ChecklistContext, cachedAt: Date = Date()) throws {
        guard let tenant = currentTenant() else { throw ChecklistContextStoreError.noTenant }
        try save(context, tenantKey: tenant, cachedAt: cachedAt)
    }

    func load(orderProductUniqueId: String, leg: ChecklistLeg) -> ChecklistContext? {
        guard let tenant = currentTenant() else { return nil }
        return load(orderProductUniqueId: orderProductUniqueId, leg: leg, tenantKey: tenant)
    }

    func remove(orderProductUniqueId: String, leg: ChecklistLeg) {
        guard let tenant = currentTenant() else { return }
        remove(orderProductUniqueId: orderProductUniqueId, leg: leg, tenantKey: tenant)
    }

    /// Every cached snapshot of the signed-in company, for diagnostics.
    func all() -> [ChecklistContext] {
        guard let tenant = currentTenant() else { return [] }
        return all(tenantKey: tenant)
    }

    // MARK: A named company

    func save(_ context: ChecklistContext, tenantKey: String, cachedAt: Date = Date()) throws {
        var copy = context
        copy.cachedAt = cachedAt
        let data = try encoder.encode(copy)
        let dir = try tenantDirectory(tenantKey, create: true)
        try lock.withLock {
            try FileSyncOperationStore.writeProtected(data, to: dir.appendingPathComponent(
                ChecklistContextStore.key(orderProductUniqueId: context.identity.orderProductUniqueId, leg: context.leg) + ".json"))
        }
    }

    func load(orderProductUniqueId: String, leg: ChecklistLeg, tenantKey: String) -> ChecklistContext? {
        guard let dir = try? tenantDirectory(tenantKey, create: false) else { return nil }
        return lock.withLock {
            let url = dir.appendingPathComponent(ChecklistContextStore.key(orderProductUniqueId: orderProductUniqueId, leg: leg) + ".json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ChecklistContext.self, from: data)
        }
    }

    func remove(orderProductUniqueId: String, leg: ChecklistLeg, tenantKey: String) {
        guard let dir = try? tenantDirectory(tenantKey, create: false) else { return }
        lock.withLock {
            try? fileManager.removeItem(at: dir.appendingPathComponent(
                ChecklistContextStore.key(orderProductUniqueId: orderProductUniqueId, leg: leg) + ".json"))
        }
    }

    func all(tenantKey: String) -> [ChecklistContext] {
        guard let dir = try? tenantDirectory(tenantKey, create: false) else { return [] }
        return lock.withLock {
            let urls = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return urls.filter { $0.pathExtension == "json" }.compactMap { url in
                (try? Data(contentsOf: url)).flatMap { try? decoder.decode(ChecklistContext.self, from: $0) }
            }
        }
    }

    // MARK: Helpers

    private func tenantDirectory(_ tenantKey: String, create: Bool) throws -> URL {
        let safe = ChecklistContextStore.sanitized(tenantKey)
        guard !safe.isEmpty else { throw ChecklistContextStoreError.noTenant }
        let dir = directory.appendingPathComponent(safe, isDirectory: true)
        if create {
            try FileSyncOperationStore.ensureProtectedDirectory(dir, fileManager: fileManager)
        }
        return dir
    }

    private static func sanitized(_ text: String) -> String {
        let safe = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        return String(String.UnicodeScalarView(safe))
    }
}
