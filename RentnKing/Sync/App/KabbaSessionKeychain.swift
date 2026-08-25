//
//  KabbaSessionKeychain.swift
//  RentnKing + RentnKinExtension (Foundation + Security only — compiled into BOTH targets)
//
//  Phase 5 — the ONE place the bearer token lives on the phone.
//
//  A single Keychain item in the app-group access group, so the main app and
//  the share extension read the same credential without a plaintext copy in
//  app-group UserDefaults (the pre-Phase-5 arrangement). Accessible after the
//  first unlock (background sync) and never synced to iCloud / other devices.
//
//  If the access group is unavailable (some Simulator configurations answer
//  errSecMissingEntitlement) the item falls back to the app-private keychain so
//  the main app keeps working; the extension then simply sees no session.
//  The token value is never logged.
//

import Foundation
import Security

final class KabbaSessionKeychain {

    static let shared = KabbaSessionKeychain()

    static let service = "com.rentnking.auth.shared"
    /// The app group doubles as the keychain access group (no extra entitlement needed on iOS).
    static let accessGroup = "group.com.RentnKingNew.shared"
    static let accessTokenKey = "access_token"

    private let lock = NSLock()
    private var accessGroupUsable = true

    init() {}

    // MARK: - API (shape matches Sync Core's SessionCredentialStore)

    func read(_ key: String) -> String? {
        lock.withLock {
            if accessGroupUsable, let value = readItem(key, useGroup: true) { return value }
            return readItem(key, useGroup: false)
        }
    }

    func write(_ value: String, key: String) throws {
        try lock.withLock {
            if accessGroupUsable {
                let status = writeItem(value, key: key, useGroup: true)
                if status == errSecSuccess { deleteItem(key, useGroup: false); return }
                if status == errSecMissingEntitlement || status == errSecParam { accessGroupUsable = false }
                else { throw KabbaSessionKeychainError.osStatus(status) }
            }
            let status = writeItem(value, key: key, useGroup: false)
            guard status == errSecSuccess else { throw KabbaSessionKeychainError.osStatus(status) }
        }
    }

    func remove(_ key: String) {
        lock.withLock {
            deleteItem(key, useGroup: true)
            deleteItem(key, useGroup: false)
        }
    }

    // MARK: - Security plumbing

    private func baseQuery(_ key: String, useGroup: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KabbaSessionKeychain.service,
            kSecAttrAccount as String: key,
        ]
        if useGroup { query[kSecAttrAccessGroup as String] = KabbaSessionKeychain.accessGroup }
        return query
    }

    private func readItem(_ key: String, useGroup: Bool) -> String? {
        var query = baseQuery(key, useGroup: useGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func writeItem(_ value: String, key: String, useGroup: Bool) -> OSStatus {
        let data = Data(value.utf8)
        let query = baseQuery(key, useGroup: useGroup)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return status }
        if status != errSecItemNotFound { return status }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil)
    }

    private func deleteItem(_ key: String, useGroup: Bool) {
        SecItemDelete(baseQuery(key, useGroup: useGroup) as CFDictionary)
    }
}

enum KabbaSessionKeychainError: Error, Equatable {
    case osStatus(OSStatus)
}
