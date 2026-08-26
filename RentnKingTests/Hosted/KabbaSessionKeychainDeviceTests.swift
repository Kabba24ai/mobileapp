//
//  KabbaSessionKeychainDeviceTests.swift
//  RentnKingHostedTests — runs INSIDE the signed RentnKing app (Simulator or a real iPhone)
//
//  Phase 6A — the real Security framework under the app's real entitlements
//  (application-groups = group.com.RentnKingNew.shared, no keychain-access-groups).
//  The Core unit tests prove the policy against a model of Apple's semantics;
//  these prove the semantics and the App-layer adapter on the device itself:
//
//     xcodebuild test -project RentnKing.xcodeproj -scheme RentnKingHostedTests \
//                     -destination 'id=<iPhone UDID>' -allowProvisioningUpdates
//
//  Every item uses a throwaway probe key — never the token key — and is removed
//  in tearDown. Nothing here logs a stored value.
//

import XCTest
import Security
@testable import RentnKing

final class KabbaSessionKeychainDeviceTests: XCTestCase {

    private let service = KabbaSessionKeychain.service
    private let group   = KabbaSessionKeychain.accessGroup
    private var key = ""

    override func setUp() {
        super.setUp()
        key = "hosted-probe-" + UUID().uuidString
    }

    override func tearDown() {
        _ = delete(group: group)
        _ = delete(group: nil)
        super.tearDown()
    }

    // MARK: - The framework's own semantics on this device

    func testTheAppGroupIsUsableAsAKeychainAccessGroupUnderTheSignedEntitlements() throws {
        let status = add("probe", group: group)
        try XCTSkipIf(status == errSecMissingEntitlement,
                      "this environment does not honour the app group as a keychain access group (OSStatus \(status)) — the store falls back to the app-private group here")
        XCTAssertEqual(status, errSecSuccess, "SecItemAdd(kSecAttrAccessGroup = \(group)) OSStatus \(status)")
        XCTAssertEqual(copy(group: group).status, errSecSuccess)
        XCTAssertEqual(copy(group: nil).status, errSecSuccess, "an unqualified SecItemCopyMatching reaches the shared-group item")
    }

    func testAnUnqualifiedSecItemDeleteReachesTheSharedGroupItem() throws {
        try XCTSkipIf(add("probe", group: group) == errSecMissingEntitlement, "shared group unavailable here")
        XCTAssertEqual(copy(group: group).status, errSecSuccess)

        let deleted = delete(group: nil)          // no kSecAttrAccessGroup in the query

        XCTAssertEqual(deleted, errSecSuccess, "OSStatus \(deleted)")
        XCTAssertEqual(copy(group: group).status, errSecItemNotFound,
                       "SecItem.h: naming an access group LIMITS a delete to that group — an unqualified delete spans every group the app can reach")
    }

    // MARK: - The App-layer adapter, end to end

    func testWriteThenImmediateReadBackRoundTripsThroughKabbaSessionKeychain() throws {
        let keychain = KabbaSessionKeychain()      // a fresh instance, never .shared / the token key

        try keychain.write("probe-value", key: key)

        XCTAssertEqual(keychain.read(key), "probe-value", "the credential must be readable straight after it was stored")
        let inGroup = copy(group: group).status
        let anywhere = copy(group: nil).status
        XCTAssertEqual(anywhere, errSecSuccess, "no copy of the item exists anywhere (group query \(inGroup), unqualified query \(anywhere))")
    }

    func testTheStoredCopyLivesInTheSharedGroupWhenTheDeviceAllowsIt() throws {
        try XCTSkipIf(add("probe", group: group) == errSecMissingEntitlement, "shared group unavailable here")
        _ = delete(group: nil)
        let keychain = KabbaSessionKeychain()

        try keychain.write("probe-value", key: key)

        XCTAssertEqual(copy(group: group).status, errSecSuccess, "the share extension reads the shared group")
        XCTAssertEqual(keychain.read(key), "probe-value")
    }

    func testRewritingReplacesTheValue() throws {
        let keychain = KabbaSessionKeychain()
        try keychain.write("first", key: key)
        try keychain.write("second", key: key)
        XCTAssertEqual(keychain.read(key), "second")
    }

    func testRemoveClearsEveryCopy() throws {
        let keychain = KabbaSessionKeychain()
        try keychain.write("probe-value", key: key)
        _ = add("stray", group: nil)

        keychain.remove(key)

        XCTAssertNil(keychain.read(key))
        XCTAssertEqual(copy(group: nil).status, errSecItemNotFound)
    }

    func testTheSecurityConstantsTheCoreStoreReliesOnMatchTheFramework() {
        XCTAssertEqual(KeychainStatus.success, errSecSuccess)
        XCTAssertEqual(KeychainStatus.param, errSecParam)
        XCTAssertEqual(KeychainStatus.noAccessForItem, errSecNoAccessForItem)
        XCTAssertEqual(KeychainStatus.duplicateItem, errSecDuplicateItem)
        XCTAssertEqual(KeychainStatus.itemNotFound, errSecItemNotFound)
        XCTAssertEqual(KeychainStatus.missingEntitlement, errSecMissingEntitlement)
    }

    // MARK: - Direct Security calls (explicit group or none)

    private func query(group: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    private func add(_ value: String, group: String?) -> OSStatus {
        var add = query(group: group)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil)
    }

    private func copy(group: String?) -> (status: OSStatus, present: Bool) {
        var q = query(group: group)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        return (status, status == errSecSuccess && (result as? Data) != nil)
    }

    private func delete(group: String?) -> OSStatus {
        SecItemDelete(query(group: group) as CFDictionary)
    }
}
