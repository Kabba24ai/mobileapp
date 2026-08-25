//
//  ClientMetadata.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Phase 5 — what the phone tells Laravel about itself on every request
//  (X-Mobile-Platform / X-Mobile-Version / X-Mobile-Build / X-Device-Id) and
//  the ONE build-number comparison the client uses to decide whether a stored
//  "update required" verdict still applies to the build that is running.
//

import Foundation

struct MobileClientMetadata: Equatable {
    let platform: String
    let version: String
    let build: String
    let deviceId: String

    static func current(installation: InstallationIdentity, bundle: Bundle = .main) -> MobileClientMetadata {
        MobileClientMetadata(
            platform: "ios",
            version: sanitize(bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"),
            build: sanitize(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"),
            deviceId: installation.identifier()
        )
    }

    var headers: [String: String] {
        [
            "X-Mobile-Platform": platform,
            "X-Mobile-Version": version,
            "X-Mobile-Build": build,
            "X-Device-Id": deviceId,
        ]
    }

    /// Server whitelist for version/build: [0-9A-Za-z.+-]{1,32}
    static func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".+-"))
        let filtered = raw.unicodeScalars.filter { allowed.contains($0) }
        let value = String(String.UnicodeScalarView(filtered))
        return value.isEmpty ? "0" : String(value.prefix(32))
    }
}

/// Mirrors App\Support\Mobile\BuildNumber: segment-wise, numeric where both
/// segments are numeric, missing segments are zero, non-numeric segments fall
/// back to a string comparison. "1000" < "1001", "999" < "1000", "1.0.17" < "1.0.18".
enum BuildNumber {
    static func compare(_ a: String, _ b: String) -> Int {
        let left = segments(a), right = segments(b)
        for i in 0..<max(left.count, right.count) {
            let l = i < left.count ? left[i] : "0"
            let r = i < right.count ? right[i] : "0"
            let cmp: Int
            if let ln = Int(l), let rn = Int(r) {
                cmp = ln == rn ? 0 : (ln < rn ? -1 : 1)
            } else {
                cmp = l == r ? 0 : (l < r ? -1 : 1)
            }
            if cmp != 0 { return cmp }
        }
        return 0
    }

    static func isBelow(_ build: String, _ minimum: String) -> Bool { compare(build, minimum) < 0 }
    static func isAtLeast(_ build: String, _ minimum: String) -> Bool { compare(build, minimum) >= 0 }

    private static func segments(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ["0"] }
        return trimmed.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "+" || $0 == "-" }
            .map { $0.isEmpty ? "0" : String($0) }
    }
}
