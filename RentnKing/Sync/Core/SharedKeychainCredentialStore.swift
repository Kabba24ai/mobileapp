//
//  SharedKeychainCredentialStore.swift
//  RentnKing — Sync Core (Foundation only; also compiled into RentnKinExtension)
//
//  Phase 6A — the policy behind the ONE shared Keychain item that holds the
//  bearer token. KabbaSessionKeychain (App layer) supplies the actual
//  Security.framework calls through `KeychainItemBackend`; everything that
//  decides *what* to call, *in which order*, and *what to fall back to* lives
//  here so it is unit-tested on macOS / the Simulator and exercised for real
//  on the phone by the hosted RentnKingHostedTests target.
//
//  Why the ordering matters (the Phase 6A device blocker): Phase 5 wrote the
//  item into the app-group access group and THEN deleted "the app-private
//  copy" with a query that named no access group. Per SecItem.h, naming
//  kSecAttrAccessGroup in a copy / update / delete LIMITS that call to the
//  named group — leaving it out spans every group the process can reach. On
//  a real iPhone (where the app-group write succeeds) that delete erased the
//  token just stored; the next request left without an Authorization header
//  and Laravel answered 401 with error.reason "missing". The Simulator never
//  showed it because no login ever ran there. Here the unqualified delete
//  runs BEFORE the write, never after it.
//
//  Diagnostics are sanitized by construction: operation names, the group a
//  call named (or "unqualified") and OSStatus values. Never a stored value.
//

import Foundation

/// OSStatus values the store reasons about (Security/SecBase.h), declared here so the
/// Foundation-only core — and its tests — never import Security.
enum KeychainStatus {
    static let success: Int32            = 0        // errSecSuccess
    static let param: Int32              = -50      // errSecParam
    static let noAccessForItem: Int32    = -25243   // errSecNoAccessForItem
    static let duplicateItem: Int32      = -25299   // errSecDuplicateItem
    static let itemNotFound: Int32       = -25300   // errSecItemNotFound
    static let missingEntitlement: Int32 = -34018   // errSecMissingEntitlement

    /// The shared access group cannot be used by this process (entitlement / environment):
    /// fall back to the app-private group instead of failing the write.
    static func meansGroupUnavailable(_ status: Int32) -> Bool {
        status == missingEntitlement || status == param || status == noAccessForItem
    }
}

/// The Security.framework surface the store needs, over generic-password items of ONE
/// service. `accessGroup == nil` means "no kSecAttrAccessGroup in the query", i.e.
///   • add                  → the process's DEFAULT access group
///   • copy / update / delete → EVERY access group the process can reach
protocol KeychainItemBackend: AnyObject {
    func add(_ value: Data, key: String, accessGroup: String?) -> Int32
    func update(_ value: Data, key: String, accessGroup: String?) -> Int32
    func copy(key: String, accessGroup: String?) -> (status: Int32, value: Data?)
    func delete(key: String, accessGroup: String?) -> Int32
}

/// Where a credential ended up after a write.
enum KeychainCredentialLocation: String, Equatable {
    case sharedGroup = "shared_group"
    case appPrivate  = "app_private"
}

/// One Security call, sanitized: what was asked, of which group, and the OSStatus. Never a value.
struct KeychainStep: Equatable, CustomStringConvertible {
    let operation: String
    /// nil = the query named no access group.
    let accessGroup: String?
    let status: Int32

    var description: String { "\(operation)(\(accessGroup ?? "unqualified"))=\(status)" }
}

/// The sanitized trace of the most recent operation.
struct KeychainDiagnostics: Equatable, CustomStringConvertible {
    var operation: String
    var steps: [KeychainStep] = []
    var storedIn: KeychainCredentialLocation?
    var readBackMatched: Bool?
    var succeeded: Bool = true

    var description: String {
        var parts: [String] = ["keychain.\(operation)", succeeded ? "ok" : "FAILED"]
        if let storedIn { parts.append("stored_in=\(storedIn.rawValue)") }
        if let readBackMatched { parts.append("readback=\(readBackMatched ? "match" : "MISMATCH")") }
        parts.append(contentsOf: steps.map(\.description))
        return parts.joined(separator: " ")
    }
}

enum KeychainCredentialStoreError: Error, Equatable {
    case osStatus(Int32)
    /// The write reported success but the value could not be read straight back.
    case readBackFailed
}

final class SharedKeychainCredentialStore {

    let sharedAccessGroup: String
    private let backend: KeychainItemBackend
    private let lock = NSLock()
    private var groupUsable = true
    private var last: KeychainDiagnostics?

    /// Sanitized trace sink (DEBUG console). Receives `KeychainDiagnostics.description` only —
    /// writes, removes, self-tests and reads that found NOTHING are reported; successful reads
    /// (one per request) are not.
    var logger: ((String) -> Void)?

    init(backend: KeychainItemBackend, sharedAccessGroup: String) {
        self.backend = backend
        self.sharedAccessGroup = sharedAccessGroup
    }

    /// False once the shared group has answered "unavailable" in this process; writes then go
    /// to the app-private group. Reads keep trying the shared group first.
    var sharedGroupUsable: Bool { lock.withLock { groupUsable } }

    var lastDiagnostics: KeychainDiagnostics? { lock.withLock { last } }

    // MARK: - Credential API (shape of Sync Core's SessionCredentialStore)

    func read(_ key: String) -> String? {
        let (value, diag): (String?, KeychainDiagnostics) = lock.withLock {
            var diag = KeychainDiagnostics(operation: "read")
            if groupUsable {
                let shared = backend.copy(key: key, accessGroup: sharedAccessGroup)
                diag.steps.append(KeychainStep(operation: "copy", accessGroup: sharedAccessGroup, status: shared.status))
                if shared.status == KeychainStatus.success, let value = decode(shared.value) {
                    diag.storedIn = .sharedGroup
                    last = diag
                    return (value, diag)
                }
            }
            let any = backend.copy(key: key, accessGroup: nil)
            diag.steps.append(KeychainStep(operation: "copy", accessGroup: nil, status: any.status))
            guard any.status == KeychainStatus.success, let value = decode(any.value) else {
                diag.succeeded = false
                last = diag
                return (nil, diag)
            }
            last = diag
            return (value, diag)
        }
        if value == nil { logger?(diag.description) }
        return value
    }

    /// Store `value` so that exactly ONE copy exists afterwards — in the shared group when this
    /// process can use it, otherwise app-private — and prove it by reading it straight back.
    func write(_ value: String, key: String) throws {
        let data = Data(value.utf8)
        let outcome: Result<Void, KeychainCredentialStoreError>
        let diag: KeychainDiagnostics
        (outcome, diag) = lock.withLock {
            var diag = KeychainDiagnostics(operation: "write")

            // 1. Remove EVERY existing copy first. This query names no access group on purpose:
            //    an access group in the query LIMITS the delete to that group (SecItem.h), so an
            //    unqualified delete spans all the groups this process can reach. It has to run
            //    BEFORE the shared write — run afterwards it deletes the item just written.
            diag.steps.append(KeychainStep(operation: "delete", accessGroup: nil,
                                           status: backend.delete(key: key, accessGroup: nil)))

            // 2. The shared group, when this process can use it.
            if groupUsable {
                let status = upsert(data, key: key, accessGroup: sharedAccessGroup, into: &diag)
                if status == KeychainStatus.success {
                    diag.storedIn = .sharedGroup
                    return finishWrite(&diag, key: key, expected: data, accessGroup: sharedAccessGroup)
                }
                if KeychainStatus.meansGroupUnavailable(status) {
                    groupUsable = false
                } else {
                    diag.succeeded = false
                    last = diag
                    return (.failure(.osStatus(status)), diag)
                }
            }

            // 3. App-private fallback (the share extension will not see this session).
            let status = upsert(data, key: key, accessGroup: nil, into: &diag)
            guard status == KeychainStatus.success else {
                diag.succeeded = false
                last = diag
                return (.failure(.osStatus(status)), diag)
            }
            diag.storedIn = .appPrivate
            return finishWrite(&diag, key: key, expected: data, accessGroup: nil)
        }
        logger?(diag.description)
        try outcome.get()
    }

    func remove(_ key: String) {
        let diag: KeychainDiagnostics = lock.withLock {
            var diag = KeychainDiagnostics(operation: "remove")
            diag.steps.append(KeychainStep(operation: "delete", accessGroup: sharedAccessGroup,
                                           status: backend.delete(key: key, accessGroup: sharedAccessGroup)))
            diag.steps.append(KeychainStep(operation: "delete", accessGroup: nil,
                                           status: backend.delete(key: key, accessGroup: nil)))
            last = diag
            return diag
        }
        logger?(diag.description)
    }

    /// Round-trips a throwaway value under a probe key (never the token) and reports the whole
    /// sanitized trace: the launch-time proof that THIS signed build can persist a credential on
    /// THIS device. Leaves nothing behind.
    @discardableResult
    func selfTest(probeKey: String = "kabba_keychain_probe") -> KeychainDiagnostics {
        let probe = UUID().uuidString
        var diag = KeychainDiagnostics(operation: "self_test")
        let logger = self.logger
        self.logger = nil            // one consolidated line instead of three
        defer { self.logger = logger }

        do { try write(probe, key: probeKey) } catch { diag.succeeded = false }
        if let written = lastDiagnostics {
            diag.steps.append(contentsOf: written.steps)
            diag.storedIn = written.storedIn
        }
        let back = read(probeKey)
        if let readSteps = lastDiagnostics?.steps { diag.steps.append(contentsOf: readSteps) }
        diag.readBackMatched = back == probe
        if back != probe { diag.succeeded = false }
        remove(probeKey)
        if let removeSteps = lastDiagnostics?.steps { diag.steps.append(contentsOf: removeSteps) }
        if read(probeKey) != nil { diag.succeeded = false }

        lock.withLock { last = diag }
        logger?(diag.description)
        return diag
    }

    // MARK: - Plumbing (called with the lock held)

    private func upsert(_ data: Data, key: String, accessGroup: String?, into diag: inout KeychainDiagnostics) -> Int32 {
        var status = backend.add(data, key: key, accessGroup: accessGroup)
        diag.steps.append(KeychainStep(operation: "add", accessGroup: accessGroup, status: status))
        if status == KeychainStatus.duplicateItem {
            // An older copy the unqualified delete could not reach — overwrite it in place.
            status = backend.update(data, key: key, accessGroup: accessGroup)
            diag.steps.append(KeychainStep(operation: "update", accessGroup: accessGroup, status: status))
        }
        return status
    }

    private func finishWrite(_ diag: inout KeychainDiagnostics, key: String, expected: Data,
                             accessGroup: String?) -> (Result<Void, KeychainCredentialStoreError>, KeychainDiagnostics) {
        let back = backend.copy(key: key, accessGroup: accessGroup)
        diag.steps.append(KeychainStep(operation: "copy", accessGroup: accessGroup, status: back.status))
        diag.readBackMatched = back.status == KeychainStatus.success && back.value == expected
        if diag.readBackMatched == true {
            last = diag
            return (.success(()), diag)
        }
        diag.succeeded = false
        last = diag
        return (.failure(.readBackFailed), diag)
    }

    private func decode(_ data: Data?) -> String? {
        guard let data, let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }
}
