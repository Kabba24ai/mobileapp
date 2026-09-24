//
//  DispatchOfflineTestSupport.swift
//  KabbaSyncCoreTests — Dispatch offline Phase 3
//
//  Every package and manifest entry a test uses is CLONED from the shared
//  Laravel fixtures (dispatch_offline_packages.json / _manifest.json) with
//  only identity fields substituted — no parallel JSON shape is invented.
//  FakeDispatchServer answers the two offline endpoints from that data.
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

enum DispatchOfflineFixtures {

    static func data(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures").appendingPathComponent(name + ".json")
        guard let data = try? Data(contentsOf: url) else {
            fatalError("Shared fixture \(name).json missing — copy it from the Laravel repo")
        }
        return data
    }

    static var packageTemplate: JSONValue {
        JSONValue.parse(data("dispatch_offline_packages"))!["data"]!["packages"]!.arrayValue![0]
    }

    static var manifestEntryTemplate: JSONValue {
        JSONValue.parse(data("dispatch_offline_manifest"))!["data"]!["missions"]!.arrayValue![0]
    }

    /// A deterministic 64-hex revision for a seed ("r1", "gary-v2", …).
    static func revision(_ seed: String) -> String {
        (0..<4).map { String(format: "%016llx", fnv1a64(seed + "#\($0)")) }.joined()
    }

    private static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    struct Mission {
        var opuid: String
        var leg: ChecklistLeg = .delivery
        var revision: String
        var effectiveDate: String = "2026-09-22"
        var deliveryDriverId: Int? = 4
        var pickupDriverId: Int? = nil
        var categoryIds: [Int] = []
        var priority: Int = 1

        var key: String { "\(opuid):\(leg.rawValue)" }
    }

    static func manifestEntry(_ m: Mission) -> JSONValue {
        var e = manifestEntryTemplate
        e = e.setting(["mission_key"], .string(m.key))
        e = e.setting(["order_product_unique_id"], .string(m.opuid))
        e = e.setting(["leg"], .string(m.leg.rawValue))
        e = e.setting(["effective_date"], .string(m.effectiveDate))
        return e.setting(["revision"], .string(m.revision))
    }

    static func package(_ m: Mission) -> JSONValue {
        var p = packageTemplate
        p = p.setting(["mission_key"], .string(m.key))
        p = p.setting(["revision"], .string(m.revision))
        p = p.setting(["order_product_unique_id"], .string(m.opuid))
        p = p.setting(["leg"], .string(m.leg.rawValue))
        p = p.setting(["dispatch", "order_product_unique_id"], .string(m.opuid))
        p = p.setting(["dispatch", "leg"], .string(m.leg.rawValue))
        p = p.setting(["dispatch", "row", "unique_id"], .string(m.opuid))
        p = p.setting(["dispatch", "row", "fulfillment_leg"], .string(m.leg.rawValue))
        p = p.setting(["dispatch", "row", "dispatch_item_id"], .string("order:\(m.opuid):\(m.leg.rawValue)"))
        p = p.setting(["dispatch", "row", "sort_key"], .string(m.effectiveDate + "|" + String(format: "%05d", m.priority)))
        p = p.setting(["dispatch", "row", "is_delivered"], .bool(m.leg == .return))
        p = p.setting(["dispatch", "row", "delivery_status"], .string(m.leg == .return ? "Completed" : "Pending"))
        p = p.setting(["dispatch", "row", "category_ids"], .array(m.categoryIds.map { .number(Double($0)) }))
        p = p.setting(["dispatch", "row", "delivery_employee"], employee(m.deliveryDriverId))
        p = p.setting(["dispatch", "row", "pickup_employee"], employee(m.pickupDriverId))
        p = p.setting(["checklist_context", "identity", "order_product_unique_id"], .string(m.opuid))
        return p.setting(["checklist_context", "identity", "leg"], .string(m.leg.rawValue))
    }

    private static func employee(_ id: Int?) -> JSONValue {
        guard let id = id else { return .null }
        return .object(["id": .number(Double(id)), "unique_id": .string("PER-\(id)"), "full_name": .string("Driver \(id)"),
                        "email": .string(""), "status": .string("Active")])
    }

    static func manifestBody(_ missions: [Mission], revision: String? = nil, throughDate: String = "2026-09-24") -> Data {
        let manifestRevision = revision ?? DispatchOfflineFixtures.revision(missions.map { $0.key + $0.revision }.joined(separator: ","))
        let body: JSONValue = .object([
            "success": .bool(true), "message": .string("Dispatch offline manifest."),
            "data": .object([
                "revision": .string(manifestRevision),
                "generated_at": .string("2026-09-22T14:00:00.000000Z"),
                "horizon": .object(["includes_open_overdue": .bool(true), "through_date": .string(throughDate)]),
                "missions": .array(missions.map(manifestEntry)),
            ]),
            "request_id": .string("srv-manifest"),
        ])
        return try! body.serialized()
    }

    static func manifestRevision(_ missions: [Mission]) -> String {
        revision(missions.map { $0.key + $0.revision }.joined(separator: ","))
    }

    static func packagesBody(_ packages: [JSONValue], notActive: [String] = []) -> Data {
        let body: JSONValue = .object([
            "success": .bool(true), "message": .string("Dispatch offline packages."),
            "data": .object(["packages": .array(packages), "not_active": .array(notActive.map { .string($0) })]),
            "request_id": .string("srv-packages"),
        ])
        return try! body.serialized()
    }
}

extension JSONValue {
    /// A copy with the value at `path` replaced (intermediate objects created as needed).
    func setting(_ path: [String], _ value: JSONValue) -> JSONValue {
        guard let head = path.first else { return value }
        var object = objectValue ?? [:]
        object[head] = (object[head] ?? .object([:])).setting(Array(path.dropFirst()), value)
        return .object(object)
    }
}

/// Answers GET dispatch/offline/manifest and POST dispatch/offline/packages from
/// in-memory missions. Every request is recorded; behavior is scriptable.
final class FakeDispatchServer: SyncHTTPClient {
    private let lock = NSLock()
    private(set) var recorded: [SyncHTTPRequest] = []

    var missions: [DispatchOfflineFixtures.Mission] = []
    /// Overrides the package served for a mission key (e.g. a newer revision, or garbage).
    var packageOverrides: [String: JSONValue] = [:]
    var notActive: Set<String> = []
    /// Requested keys the server silently omits (neither package nor not_active).
    var omitted: Set<String> = []
    var offline = false
    var manifestStatus = 200
    var packagesStatus = 200
    var manifestBodyOverride: Data?
    var packagesBodyOverride: Data?
    /// Goes offline right after answering this many manifest requests.
    var goOfflineAfterManifests: Int?
    /// Called (on the request thread) before answering — tests use it to block or mutate.
    var beforeAnswer: ((SyncHTTPRequest) -> Void)?
    var latency: TimeInterval = 0
    private var manifestsAnswered = 0

    var manifestRequests: Int { lock.withLock { recorded.filter { $0.path == DispatchOfflineAPI.manifestPath }.count } }
    var packageRequests: [SyncHTTPRequest] { lock.withLock { recorded.filter { $0.path == DispatchOfflineAPI.packagesPath } } }
    var requestCount: Int { lock.withLock { recorded.count } }

    /// Mission keys asked for across every package request, in order.
    var requestedKeys: [String] {
        packageRequests.flatMap { request -> [String] in
            (request.jsonBody?["missions"]?.arrayValue ?? []).compactMap { m in
                guard let id = m["order_product_unique_id"]?.stringValue, let leg = m["leg"]?.stringValue else { return nil }
                return "\(id):\(leg)"
            }
        }
    }

    func perform(_ request: SyncHTTPRequest, completion: @escaping (SyncHTTPResult) -> Void) {
        lock.withLock { recorded.append(request) }
        beforeAnswer?(request)
        let answer = self.answer(request)
        if latency > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + latency) { completion(answer) }
        } else {
            completion(answer)
        }
    }

    private func answer(_ request: SyncHTTPRequest) -> SyncHTTPResult {
        let state: (offline: Bool, missions: [DispatchOfflineFixtures.Mission]) = lock.withLock { (offline, missions) }
        if state.offline {
            return .failure(APIError.transport(.offline, description: "fake: offline"))
        }
        switch request.path {
        case DispatchOfflineAPI.manifestPath:
            let (status, body): (Int, Data) = lock.withLock {
                manifestsAnswered += 1
                if let after = goOfflineAfterManifests, manifestsAnswered >= after { offline = true }
                return (manifestStatus, manifestBodyOverride ?? DispatchOfflineFixtures.manifestBody(missions))
            }
            return .response(SyncHTTPResponse(statusCode: status, headers: [:], body: status == 200 ? body : Data("{\"success\":false}".utf8)))
        case DispatchOfflineAPI.packagesPath:
            let status = lock.withLock { packagesStatus }
            guard status == 200 else {
                return .response(SyncHTTPResponse(statusCode: status, headers: [:], body: Data("{\"success\":false}".utf8)))
            }
            if let override = lock.withLock({ packagesBodyOverride }) {
                return .response(SyncHTTPResponse(statusCode: 200, headers: [:], body: override))
            }
            let asked = (request.jsonBody?["missions"]?.arrayValue ?? []).compactMap { m -> String? in
                guard let id = m["order_product_unique_id"]?.stringValue, let leg = m["leg"]?.stringValue else { return nil }
                return "\(id):\(leg)"
            }
            var packages: [JSONValue] = []
            var inactive: [String] = []
            lock.withLock {
                for key in asked {
                    if notActive.contains(key) { inactive.append(key); continue }
                    if omitted.contains(key) { continue }
                    if let override = packageOverrides[key] { packages.append(override); continue }
                    if let m = state.missions.first(where: { $0.key == key }) {
                        packages.append(DispatchOfflineFixtures.package(m))
                    } else {
                        inactive.append(key)
                    }
                }
            }
            return .response(SyncHTTPResponse(statusCode: 200, headers: [:], body: DispatchOfflineFixtures.packagesBody(packages, notActive: inactive)))
        default:
            return .response(SyncHTTPResponse(statusCode: 404, headers: [:], body: nil))
        }
    }

    func setOffline(_ value: Bool) { lock.withLock { offline = value } }
    func setMissions(_ value: [DispatchOfflineFixtures.Mission]) { lock.withLock { missions = value } }
}
