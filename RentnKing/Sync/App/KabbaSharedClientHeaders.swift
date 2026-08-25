//
//  KabbaSharedClientHeaders.swift
//  RentnKing + RentnKinExtension (Foundation only — compiled into BOTH targets)
//
//  Phase 5 — the request-context headers every Kabba client sends, available
//  to the share extension without pulling the Sync Core in. The main app
//  publishes its per-install identifier into the app group (it is NOT secret —
//  a random UUID minted on first launch) so the extension's requests carry the
//  same X-Device-Id and are attributed to the same install on the server.
//

import Foundation

enum KabbaSharedClientHeaders {

    static let appGroup = "group.com.RentnKingNew.shared"
    static let installationIdKey = "kabba_installation_id"

    /// X-Request-Id (new per call) + X-Mobile-Platform / -Version / -Build + X-Device-Id when known.
    static func headers(bundle: Bundle = .main, requestIdPrefix: String = "ios") -> [String: String] {
        var headers: [String: String] = [
            "X-Request-Id": requestIdPrefix + "-" + UUID().uuidString.lowercased(),
            "X-Mobile-Platform": "ios",
            "X-Mobile-Version": sanitize(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"),
            "X-Mobile-Build": sanitize(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"),
            "Accept": "application/json",
        ]
        if let id = installationId() { headers["X-Device-Id"] = id }
        return headers
    }

    static func installationId() -> String? {
        guard let value = UserDefaults(suiteName: appGroup)?.string(forKey: installationIdKey), !value.isEmpty else { return nil }
        return value
    }

    /// Main app only: mirror the Sync Core's InstallationIdentity into the app group.
    static func publishInstallationId(_ identifier: String) {
        let defaults = UserDefaults(suiteName: appGroup)
        if defaults?.string(forKey: installationIdKey) != identifier {
            defaults?.set(identifier, forKey: installationIdKey)
            defaults?.synchronize()
        }
    }

    /// Server whitelist for version/build: [0-9A-Za-z.+-]{1,32}
    static func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".+-"))
        let filtered = raw.unicodeScalars.filter { allowed.contains($0) }
        let value = String(String.UnicodeScalarView(filtered))
        return value.isEmpty ? "0" : String(value.prefix(32))
    }
}
