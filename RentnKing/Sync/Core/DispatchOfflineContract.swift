//
//  DispatchOfflineContract.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Dispatch offline mission cache — Phase 3. The two read contracts from
//  Laravel (Phase 1, extended by Phase 3 B0 with `dispatch.row`):
//
//    GET  dispatch/offline/manifest   the COMPLETE company-wide working set
//                                     (open overdue + today + next two days,
//                                     every driver): mission key + revision.
//    POST dispatch/offline/packages   1–100 missions per request → packages
//                                     + not_active.
//
//  Validation is strict and per package: one bad package is rejected on its
//  own, never the batch. checklist_context and terms are kept OPAQUE here —
//  Phase 4/5 decode them from the stored raw package.
//

import Foundation

enum DispatchOfflineContractError: Error, Equatable {
    case notJSON
    case missingData
    case invalidManifest(String)
}

enum DispatchOfflineValidation {
    /// Laravel revisions are sha256 hex digests.
    static func isRevision(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// "YYYY-MM-DD".
    static func isDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    static func missionKey(orderProductUniqueId: String, leg: ChecklistLeg) -> String {
        "\(orderProductUniqueId):\(leg.rawValue)"
    }
}

// MARK: - Manifest

struct DispatchOfflineManifest: Equatable {
    struct Entry: Codable, Equatable {
        let missionKey: String
        let orderProductUniqueId: String
        let leg: ChecklistLeg
        let effectiveDate: String
        let revision: String
    }

    let revision: String
    let generatedAt: String
    let includesOpenOverdue: Bool
    let throughDate: String
    let missions: [Entry]

    /// Decodes `{"success":true,"data":{…}}`. Any malformed entry rejects the WHOLE
    /// manifest: it is the complete truth for the horizon, so a partial read could
    /// wrongly remove missions from the phone.
    static func decode(envelope body: Data?) throws -> DispatchOfflineManifest {
        guard let root = JSONValue.parse(body) else { throw DispatchOfflineContractError.notJSON }
        guard let data = root["data"], case .object = data else { throw DispatchOfflineContractError.missingData }

        guard let revision = data["revision"]?.stringValue, DispatchOfflineValidation.isRevision(revision) else {
            throw DispatchOfflineContractError.invalidManifest("revision")
        }
        guard let throughDate = data["horizon"]?["through_date"]?.stringValue, DispatchOfflineValidation.isDate(throughDate) else {
            throw DispatchOfflineContractError.invalidManifest("horizon.through_date")
        }
        guard let list = data["missions"]?.arrayValue else { throw DispatchOfflineContractError.invalidManifest("missions") }

        var seen = Set<String>()
        var entries: [Entry] = []
        entries.reserveCapacity(list.count)
        for item in list {
            guard let key = item["mission_key"]?.stringValue,
                  let opuid = item["order_product_unique_id"]?.stringValue, !opuid.isEmpty,
                  let legRaw = item["leg"]?.stringValue, let leg = ChecklistLeg(rawValue: legRaw),
                  let date = item["effective_date"]?.stringValue, DispatchOfflineValidation.isDate(date),
                  let rev = item["revision"]?.stringValue, DispatchOfflineValidation.isRevision(rev),
                  key == DispatchOfflineValidation.missionKey(orderProductUniqueId: opuid, leg: leg) else {
                throw DispatchOfflineContractError.invalidManifest("mission \(item["mission_key"]?.stringValue ?? "?")")
            }
            guard seen.insert(key).inserted else { throw DispatchOfflineContractError.invalidManifest("duplicate \(key)") }
            entries.append(Entry(missionKey: key, orderProductUniqueId: opuid, leg: leg, effectiveDate: date, revision: rev))
        }

        return DispatchOfflineManifest(
            revision: revision,
            generatedAt: data["generated_at"]?.stringValue ?? "",
            includesOpenOverdue: data["horizon"]?["includes_open_overdue"]?.boolValue ?? true,
            throughDate: throughDate,
            missions: entries
        )
    }
}

// MARK: - Packages

struct DispatchOfflinePackage: Equatable {
    let missionKey: String
    let revision: String
    let orderProductUniqueId: String
    let leg: ChecklistLeg
    /// `dispatch.row` — the live Dispatch feed's row for this order product.
    let row: JSONValue
    /// The package exactly as received (checklist_context / terms are decoded by later phases).
    let object: JSONValue

    /// Nil reason = valid. `requested` guards against a package nobody asked for.
    static func validate(_ value: JSONValue, requested: Set<String>) -> Result<DispatchOfflinePackage, DispatchOfflinePackagesResponse.Rejection> {
        let key = value["mission_key"]?.stringValue
        func reject(_ reason: String) -> Result<DispatchOfflinePackage, DispatchOfflinePackagesResponse.Rejection> {
            .failure(.init(missionKey: key, reason: reason))
        }

        guard let key = key, requested.contains(key) else { return reject("not requested") }
        guard let opuid = value["order_product_unique_id"]?.stringValue, !opuid.isEmpty else { return reject("order_product_unique_id") }
        guard let legRaw = value["leg"]?.stringValue, let leg = ChecklistLeg(rawValue: legRaw) else { return reject("leg") }
        guard key == DispatchOfflineValidation.missionKey(orderProductUniqueId: opuid, leg: leg) else { return reject("mission_key ≠ id:leg") }
        guard let revision = value["revision"]?.stringValue, DispatchOfflineValidation.isRevision(revision) else { return reject("revision") }

        guard let dispatch = value["dispatch"], case .object = dispatch,
              dispatch["order_product_unique_id"]?.stringValue == opuid,
              dispatch["leg"]?.stringValue == leg.rawValue else { return reject("dispatch identity") }
        guard let row = dispatch["row"], case .object = row, row["unique_id"]?.stringValue == opuid else { return reject("dispatch.row") }

        guard let identity = value["checklist_context"]?["identity"],
              identity["order_product_unique_id"]?.stringValue == opuid,
              identity["leg"]?.stringValue == leg.rawValue else { return reject("checklist_context identity") }
        guard let terms = value["terms"], case .object = terms else { return reject("terms") }

        return .success(DispatchOfflinePackage(missionKey: key, revision: revision, orderProductUniqueId: opuid,
                                               leg: leg, row: row, object: value))
    }
}

struct DispatchOfflinePackagesResponse: Equatable {
    struct Rejection: Error, Equatable {
        let missionKey: String?
        let reason: String
    }

    let packages: [DispatchOfflinePackage]
    let rejected: [Rejection]
    /// Requested missions the server says are no longer active.
    let notActive: [String]
    /// Requested ACTIVE missions whose package the server could not build this time
    /// (mission key → stable code). Never "not active": the phone keeps any previous
    /// package for them and retries on the next reconciliation.
    let unavailable: [String: String]

    static func decode(envelope body: Data?, requested: Set<String>) throws -> DispatchOfflinePackagesResponse {
        guard let root = JSONValue.parse(body) else { throw DispatchOfflineContractError.notJSON }
        guard let data = root["data"], case .object = data, let list = data["packages"]?.arrayValue else {
            throw DispatchOfflineContractError.missingData
        }

        var packages: [DispatchOfflinePackage] = []
        var rejected: [Rejection] = []
        var seen = Set<String>()
        for item in list {
            switch DispatchOfflinePackage.validate(item, requested: requested) {
            case .success(let package) where seen.insert(package.missionKey).inserted:
                packages.append(package)
            case .success(let package):
                rejected.append(Rejection(missionKey: package.missionKey, reason: "duplicate"))
            case .failure(let rejection):
                rejected.append(rejection)
            }
        }
        let notActive = (data["not_active"]?.arrayValue ?? []).compactMap(\.stringValue).filter { requested.contains($0) }
        var unavailable: [String: String] = [:]
        for failure in data["failed"]?.arrayValue ?? [] {
            guard let opuid = failure["order_product_unique_id"]?.stringValue, !opuid.isEmpty,
                  let leg = failure["leg"]?.stringValue.flatMap(ChecklistLeg.init(rawValue:)) else { continue }
            let key = DispatchOfflineValidation.missionKey(orderProductUniqueId: opuid, leg: leg)
            // Only requested missions that did not arrive (a delivered package wins).
            guard requested.contains(key), !seen.contains(key), !notActive.contains(key) else { continue }
            unavailable[key] = failure["code"]?.stringValue ?? "unavailable"
        }
        return DispatchOfflinePackagesResponse(packages: packages, rejected: rejected, notActive: notActive,
                                               unavailable: unavailable)
    }
}

// MARK: - Requests

enum DispatchOfflineAPI {
    static let manifestPath = "dispatch/offline/manifest"
    static let packagesPath = "dispatch/offline/packages"
    /// PackagesRequest::MAX_MISSIONS on the server.
    static let maxMissionsPerRequest = 100

    /// Reads are never replayed: every request carries its own operation id.
    static func newOperationId() -> String { "op-dispatch-offline-" + UUID().uuidString.lowercased() }

    static func manifestRequest() -> SyncHTTPRequest {
        SyncHTTPRequest(method: "GET", path: manifestPath, operationId: newOperationId())
    }

    static func packagesRequests(for entries: [DispatchOfflineManifest.Entry]) -> [SyncHTTPRequest] {
        stride(from: 0, to: entries.count, by: maxMissionsPerRequest).map { start in
            let batch = entries[start..<min(start + maxMissionsPerRequest, entries.count)]
            let missions: [JSONValue] = batch.map {
                .object(["order_product_unique_id": .string($0.orderProductUniqueId), "leg": .string($0.leg.rawValue)])
            }
            return SyncHTTPRequest(method: "POST", path: packagesPath,
                                   jsonBody: .object(["missions": .array(missions)]),
                                   operationId: newOperationId())
        }
    }
}
