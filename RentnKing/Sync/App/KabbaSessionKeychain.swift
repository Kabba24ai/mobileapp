//
//  KabbaSessionKeychain.swift
//  RentnKing + RentnKinExtension (Foundation + Security — compiled into BOTH targets)
//
//  Phase 5 — the ONE place the bearer token lives on the phone.
//  Phase 6A — the ordering / fallback policy moved into Sync Core
//  (SharedKeychainCredentialStore: unit-tested against a model of Apple's
//  access-group semantics, and exercised for real on the phone by the hosted
//  RentnKingHostedTests target). This file is the Security.framework adapter
//  plus the app-facing constants.
//
//  One generic-password item (service com.rentnking.auth.shared) in the
//  app-group access group: on iOS an app group listed in the signed
//  com.apple.security.application-groups entitlement IS a keychain access
//  group (no keychain-access-groups entitlement is needed), so the main app
//  and the share extension read the same credential without a plaintext copy
//  in app-group UserDefaults. After first unlock, this device only, never
//  synced. If the group is unusable (some Simulator configurations answer
//  errSecMissingEntitlement) the item falls back to the app-private group and
//  the extension simply sees no session.
//
//  Never logs a value: diagnostics are operation names + OSStatus only.
//

import Foundation
import Security

/// Security.framework over generic-password items of ONE service.
/// `accessGroup == nil` ⇒ no kSecAttrAccessGroup in the query (add → default group;
/// copy / update / delete → every group this process can reach — SecItem.h).
final class SecurityKeychainBackend: KeychainItemBackend {

    let service: String

    init(service: String) {
        self.service = service
    }

    func add(_ value: Data, key: String, accessGroup: String?) -> Int32 {
        var attributes = query(key: key, accessGroup: accessGroup)
        attributes[kSecValueData as String] = value
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(_ value: Data, key: String, accessGroup: String?) -> Int32 {
        let update: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemUpdate(query(key: key, accessGroup: accessGroup) as CFDictionary, update as CFDictionary)
    }

    func copy(key: String, accessGroup: String?) -> (status: Int32, value: Data?) {
        var query = query(key: key, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, status == errSecSuccess ? result as? Data : nil)
    }

    func delete(key: String, accessGroup: String?) -> Int32 {
        SecItemDelete(query(key: key, accessGroup: accessGroup) as CFDictionary)
    }

    private func query(key: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}

final class KabbaSessionKeychain {

    static let shared = KabbaSessionKeychain()

    static let service = "com.rentnking.auth.shared"
    /// The app group doubles as the keychain access group (iOS; no extra entitlement needed).
    static let accessGroup = "group.com.RentnKingNew.shared"
    static let accessTokenKey = "access_token"

    let store: SharedKeychainCredentialStore

    init(backend: KeychainItemBackend = SecurityKeychainBackend(service: KabbaSessionKeychain.service),
         accessGroup: String = KabbaSessionKeychain.accessGroup) {
        store = SharedKeychainCredentialStore(backend: backend, sharedAccessGroup: accessGroup)
    }

    /// Sanitized trace sink (operation names + OSStatus; never a value). Set from DEBUG builds.
    var logger: ((String) -> Void)? {
        get { store.logger }
        set { store.logger = newValue }
    }

    var lastDiagnostics: KeychainDiagnostics? { store.lastDiagnostics }

    // MARK: - API (shape matches Sync Core's SessionCredentialStore)

    func read(_ key: String) -> String? { store.read(key) }

    func write(_ value: String, key: String) throws { try store.write(value, key: key) }

    func remove(_ key: String) { store.remove(key) }

    /// Round-trips a throwaway probe (never the token) — the launch-time proof that this signed
    /// build can persist a credential on this device.
    @discardableResult
    func selfTest() -> KeychainDiagnostics { store.selfTest() }
}
