//
//  TermsAgreementStore.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Dispatch offline Phase 5. The orders' frozen Terms & Conditions agreements
//  this phone holds, so the T&C screen can show — and a customer can sign —
//  a never-opened Delivery mission's agreement with no connection:
//
//    <KabbaSync>/terms-agreements/<tenantKey>/<orderUid>/<identity>.json
//    <KabbaSync>/terms-agreements/<tenantKey>/<orderUid>/current.json   (the newest copy)
//
//  • VERIFIED agreements only: an agreement is stored only when its identity
//    recomputes from its own payload and it belongs to the order.
//  • Tenant-scoped (Amendment B): every read and write names a company; the
//    signed-in company for the screens, an explicit one for the bridge and
//    for a live answer captured under a known company.
//  • Retained: every identity ever stored stays (no pruning in Phase 5), so the
//    agreement a signature names is still on the phone as local evidence.
//  • Freshness (newest request wins) is decided by the caller through the
//    field ledger's `terms` stamp — the bridge and saveLiveCopy — not here.
//

import Foundation

enum TermsAgreementStoreError: Error, Equatable {
    case noTenant
    /// Refused: the payload does not verify, or names another order.
    case unverified
}

final class TermsAgreementStore {

    let directory: URL
    private let currentTenant: () -> String?
    private let fileManager: FileManager
    private let encoder = KabbaISO8601.makeEncoder()
    private let decoder = KabbaISO8601.makeDecoder()
    private let lock = NSLock()

    init(rootDirectory: URL, tenantKey: @escaping () -> String?, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.currentTenant = tenantKey
        self.directory = rootDirectory.appendingPathComponent("terms-agreements", isDirectory: true)
        try FileSyncOperationStore.ensureProtectedDirectory(directory, fileManager: fileManager)
    }

    var currentTenantKey: String? { currentTenant() }

    // MARK: Signed-in company (the screens)

    /// The newest verified agreement this phone holds for the order, for the signed-in company.
    func current(orderUniqueId: String) -> TermsAgreement? {
        guard let tenant = currentTenant() else { return nil }
        return current(orderUniqueId: orderUniqueId, tenantKey: tenant)
    }

    func agreement(orderUniqueId: String, identity: String) -> TermsAgreement? {
        guard let tenant = currentTenant() else { return nil }
        return agreement(orderUniqueId: orderUniqueId, identity: identity, tenantKey: tenant)
    }

    // MARK: A named company

    func save(_ agreement: TermsAgreement, tenantKey: String) throws {
        guard agreement.isVerified(forOrder: agreement.orderUniqueId) else { throw TermsAgreementStoreError.unverified }
        let data = try encoder.encode(agreement)
        let dir = try orderDirectory(tenantKey, agreement.orderUniqueId, create: true)
        try lock.withLock {
            try FileSyncOperationStore.writeProtected(data, to: dir.appendingPathComponent(Self.fileName(agreement.identity)))
            try FileSyncOperationStore.writeProtected(data, to: dir.appendingPathComponent("current.json"))
        }
    }

    func current(orderUniqueId: String, tenantKey: String) -> TermsAgreement? {
        read(orderUniqueId: orderUniqueId, tenantKey: tenantKey, file: "current.json")
    }

    func agreement(orderUniqueId: String, identity: String, tenantKey: String) -> TermsAgreement? {
        read(orderUniqueId: orderUniqueId, tenantKey: tenantKey, file: Self.fileName(identity))
    }

    // MARK: Helpers

    /// Re-verified on every read: a damaged or foreign file is never served.
    private func read(orderUniqueId: String, tenantKey: String, file: String) -> TermsAgreement? {
        guard let dir = try? orderDirectory(tenantKey, orderUniqueId, create: false) else { return nil }
        return lock.withLock {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
                  let agreement = try? decoder.decode(TermsAgreement.self, from: data),
                  agreement.isVerified(forOrder: orderUniqueId) else { return nil }
            return agreement
        }
    }

    private static func fileName(_ identity: String) -> String {
        sanitized(identity.replacingOccurrences(of: ":", with: "-")) + ".json"
    }

    private func orderDirectory(_ tenantKey: String, _ orderUniqueId: String, create: Bool) throws -> URL {
        let tenant = Self.sanitized(tenantKey)
        let order = Self.sanitized(orderUniqueId)
        guard !tenant.isEmpty, !order.isEmpty else { throw TermsAgreementStoreError.noTenant }
        let dir = directory.appendingPathComponent(tenant, isDirectory: true).appendingPathComponent(order, isDirectory: true)
        if create {
            try FileSyncOperationStore.ensureProtectedDirectory(directory.appendingPathComponent(tenant, isDirectory: true), fileManager: fileManager)
            try FileSyncOperationStore.ensureProtectedDirectory(dir, fileManager: fileManager)
        }
        return dir
    }

    private static func sanitized(_ text: String) -> String {
        let safe = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        return String(String.UnicodeScalarView(safe))
    }
}
