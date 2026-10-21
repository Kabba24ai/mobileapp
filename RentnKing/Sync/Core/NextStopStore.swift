//
//  NextStopStore.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Durable home of the shop stop (NextStopState), under its OWN directory in
//  the protected KabbaSync root:
//
//      <KabbaSync>/next-stop/<tenantKey>/state.json
//
//  Deliberately separate from operations/, checklist-contexts/, terms/ and the
//  Dispatch offline packages. This store never reads or writes any of those —
//  a driver's parked Needs Attention work is not this file's business, and a
//  damaged state.json must cost nothing but the shop stop.
//
//  Tenant-scoped (Dispatch offline Phase 4, Amendment B): a read or write
//  always names a company. Signed out, a read is `.idle` and a write is
//  refused — the same fail-closed rule the other tenant-scoped stores use, so
//  a shop stop can never leak between companies on a shared phone.
//
//  Same protection and atomicity as the operation store: the write lands whole
//  or not at all, because the next thing the driver does is leave the app for
//  Maps.
//

import Foundation

public enum NextStopStoreError: Error, Equatable {
    /// Nobody is signed in: there is no company to read or write for.
    case noTenant
}

public final class NextStopStore {

    /// The root of every company's shop stop: <KabbaSync>/next-stop/.
    public let directory: URL

    private let currentTenant: () -> String?
    private let fileManager: FileManager
    private let encoder = KabbaISO8601.makeEncoder()
    private let decoder = KabbaISO8601.makeDecoder()
    private let lock = NSLock()

    private static let fileName = "state.json"

    /// `tenantKey` = the signed-in company (KabbaTenantScope.currentKey), nil when signed out.
    public init(rootDirectory: URL,
                tenantKey: @escaping () -> String?,
                fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.currentTenant = tenantKey
        self.directory = rootDirectory.appendingPathComponent("next-stop", isDirectory: true)
        try FileSyncOperationStore.ensureProtectedDirectory(directory, fileManager: fileManager)
    }

    /// The signed-in company's shop stop. `.idle` when signed out, when nothing
    /// was ever saved, or when what is on disk cannot be read.
    public func load() -> NextStopState {
        guard let url = try? stateURL(create: false) else { return .idle }
        return lock.withLock {
            guard let data = try? Data(contentsOf: url),
                  let state = try? decoder.decode(NextStopState.self, from: data) else { return .idle }
            return state
        }
    }

    /// Persists the shop stop. MUST complete before navigation is launched.
    public func save(_ state: NextStopState) throws {
        let url = try stateURL(create: true)
        let data = try encoder.encode(state)
        try lock.withLock {
            try FileSyncOperationStore.writeProtected(data, to: url)
        }
    }

    /// Ends the shop stop. Refused when signed out, so a sign-out can never be
    /// mistaken for "the driver finished their shop stop".
    public func clear() throws {
        let url = try stateURL(create: false)
        lock.withLock {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: Helpers

    private func stateURL(create: Bool) throws -> URL {
        guard let tenant = currentTenant() else { throw NextStopStoreError.noTenant }
        let safe = NextStopStore.sanitized(tenant)
        guard !safe.isEmpty else { throw NextStopStoreError.noTenant }

        let dir = directory.appendingPathComponent(safe, isDirectory: true)
        if create {
            try FileSyncOperationStore.ensureProtectedDirectory(dir, fileManager: fileManager)
        }
        return dir.appendingPathComponent(NextStopStore.fileName)
    }

    /// Whose shop stop this is: the signed-in DRIVER of the company (2026-10-21). On a phone
    /// drivers share, one driver's trip is never shown to, continued or confirmed by another
    /// (an arrival is recorded under whoever taps it). nil — no company, or nobody signed
    /// in — means there is no shop stop. A stop saved before this rule (company only) is
    /// simply not found: at worst one old shop stop is forgotten once.
    public static func scopeKey(tenant: String?, driverId: String?) -> String? {
        guard let tenant = tenant, !tenant.isEmpty,
              let driver = driverId?.trimmingCharacters(in: .whitespacesAndNewlines), !driver.isEmpty else { return nil }
        return "\(tenant)-driver-\(driver)"
    }

    private static func sanitized(_ text: String) -> String {
        let safe = text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        return String(String.UnicodeScalarView(safe))
    }
}
