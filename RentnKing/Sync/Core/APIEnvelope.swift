//
//  APIEnvelope.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Parses BOTH the canonical envelope (success/data/error/errors/request_id) and
//  the legacy shapes still emitted by un-migrated endpoints (`success:"1"`,
//  `status:true`). The HTTP status stays authoritative; this only reads WHAT the
//  server said.
//

import Foundation

struct APIEnvelope: Equatable {
    let raw: JSONValue

    /// `success` (Bool / "1" / 1 / "true") or, when absent, legacy `status` (Bool / "1").
    var declaredSuccess: Bool? {
        if let s = raw["success"], let b = s.boolValue { return b }
        if let st = raw["status"] {
            // Legacy `status: true/false` or "1"/"0". A NUMERIC http-status-like value
            // (e.g. 404 from ApiResponseHelper::error) is not a success flag.
            if case .bool(let b) = st { return b }
            if case .string(let s) = st, ["1", "0", "true", "false"].contains(s.lowercased()) { return st.boolValue }
            if case .number(let n) = st, n == 0 || n == 1 { return n == 1 }
        }
        return nil
    }

    var message: String? { raw["message"]?.stringValue }
    var data: JSONValue? { raw["data"] }
    var requestId: String? { raw["request_id"]?.stringValue }
    var replayed: Bool { raw["replayed"]?.boolValue ?? false }
    var originalRequestId: String? { raw["original_request_id"]?.stringValue }

    var errorCode: String? {
        raw["error"]?["code"]?.stringValue ?? raw["error_code"]?.stringValue
    }

    var errorMessage: String? {
        raw["error"]?["message"]?.stringValue
    }

    var retryable: Bool? {
        raw["error"]?["retryable"]?.boolValue
    }

    var validationErrors: [String: [String]] {
        guard let errors = raw["errors"]?.objectValue else { return [:] }
        var out: [String: [String]] = [:]
        for (field, value) in errors {
            if let list = value.arrayValue {
                out[field] = list.compactMap { $0.stringValue }
            } else if let single = value.stringValue {
                out[field] = [single]
            }
        }
        return out
    }

    static func parse(_ data: Data?) -> APIEnvelope? {
        guard let value = JSONValue.parse(data), case .object = value else { return nil }
        return APIEnvelope(raw: value)
    }
}
