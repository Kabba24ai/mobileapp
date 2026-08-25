//
//  DeprecatedEndpoints.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Phase 5 — the legacy routes the NEW build must never call for migrated
//  workflows. Mirrors config('mobile_api.deprecated_routes') on Laravel.
//
//  The Sync Engine refuses to send a request that targets one of these unless
//  the handler explicitly declares `mayUseDeprecatedEndpoint` (the one adapter
//  that drains items an OLD build queued in its legacy format). A refused
//  operation is parked as Needs Attention — never silently dropped — so a
//  regression is visible in tests and on the phone, not in production data.
//

import Foundation

enum DeprecatedMobileEndpoints {
    /// Whole route deprecated.
    static let paths: Set<String> = [
        "orders/customer-checklists/save-delivery",
        "orders/customer-checklists/save-return",
        "orders/upload-media",
    ]

    /// Deprecated only when it carries a completion claim (complete_leg absent or true).
    static let completingBranchPath = "orders/schedules/update-delivery-pickup-inputs"
    static let completionField = "complete_leg"

    static func normalized(_ path: String) -> String {
        var p = path
        if let q = p.firstIndex(of: "?") { p = String(p[..<q]) }
        while p.hasPrefix("/") { p.removeFirst() }
        while p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func isDeprecated(path: String, jsonBody: JSONValue?) -> Bool {
        let p = normalized(path)
        if paths.contains(p) { return true }
        if p == completingBranchPath {
            // Only an explicit false is the canonical inputs-only use.
            return jsonBody?[completionField]?.boolValue != false
        }
        return false
    }

    static func isDeprecated(_ request: SyncHTTPRequest) -> Bool {
        isDeprecated(path: request.path, jsonBody: request.jsonBody)
    }
}
