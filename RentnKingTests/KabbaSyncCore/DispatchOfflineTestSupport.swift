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
        // Phase 4 identity knobs (nil keeps the shared fixture's value).
        var orderUid: String? = nil
        var executionId: String? = nil
        var cycle: Int? = nil
        var unit: String? = nil
        var serverTime: String? = nil
        /// An unassigned delivery (`assignment: none`): no unit, no questions.
        var unassigned = false
        // Phase 5 knobs.
        /// `sections.terms` as the server would report it; nil keeps "ok" (Delivery) / "not_applicable" (Return).
        /// "absent" removes the key (a pre-Phase-5 server).
        var termsSection: String? = nil
        /// Corrupt the packaged agreement so its identity no longer recomputes.
        var tamperedTerms = false

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
        p = p.setting(["checklist_context", "identity", "leg"], .string(m.leg.rawValue))
        if let order = m.orderUid {
            p = p.setting(["checklist_context", "identity", "order_unique_id"], .string(order))
            p = p.setting(["dispatch", "row", "order", "unique_id"], .string(order))
            p = p.setting(["dispatch", "order", "unique_id"], .string(order))
            p = p.setting(["order_details", "unique_id"], .string(order))
        }
        if let execution = m.executionId { p = p.setting(["checklist_context", "identity", "checklist_execution_id"], .string(execution)) }
        if let cycle = m.cycle { p = p.setting(["checklist_context", "identity", "cycle"], .number(Double(cycle))) }
        if let unit = m.unit { p = p.setting(["checklist_context", "equipment", "equipment_unique_id"], .string(unit)) }
        if let time = m.serverTime { p = p.setting(["checklist_context", "server_time"], .string(time)) }
        if m.unassigned {
            p = p.setting(["checklist_context", "equipment", "assignment"], .string("none"))
                .setting(["checklist_context", "equipment", "equipment_unique_id"], .null)
                .setting(["checklist_context", "questions"], .array([]))
        }
        // Phase 5: the order's frozen agreement is bound to its order — re-target it (identity
        // recomputed) whenever a test gives the mission another order.
        if let order = m.orderUid { p = retargetedTerms(p, orderUid: order) }
        if m.leg == .return {
            // Like the server: Return missions carry no Assembly Review and no agreement.
            p = p.setting(["assembly"], .null).setting(["sections", "assembly"], .string("not_applicable"))
            p = withoutAgreement(p).setting(["sections", "terms"], .string("not_applicable"))
        }
        switch m.termsSection {
        case "absent"?:
            if case .object(var sections)? = p["sections"] { sections["terms"] = nil; p = p.setting(["sections"], .object(sections)) }
            p = withoutAgreement(p)
        case let status?:
            p = p.setting(["sections", "terms"], .string(status))
            if status != "ok" {
                p = withoutAgreement(p).setting(["terms", "agreement_status"], status == "unavailable" ? .string("unavailable") : .null)
                if status == "unavailable" { p = p.setting(["terms", "unavailable_reason"], .string("no_stored_agreement")) }
            }
        case nil:
            break
        }
        if m.tamperedTerms, var entries = p["terms"]?["agreement"]?["entries"]?.arrayValue, !entries.isEmpty {
            entries[0] = entries[0].setting(["content"], .string("<p>Tampered.</p>"))
            p = p.setting(["terms", "agreement", "entries"], .array(entries))
        }
        return p
    }

    /// The package's agreement moved to `orderUid`, with its identity recomputed.
    static func retargetedTerms(_ package: JSONValue, orderUid: String) -> JSONValue {
        guard var agreement = TermsAgreement.decode(package["terms"]?["agreement"]) else { return package }
        agreement.orderUniqueId = orderUid
        agreement.identity = agreement.recomputedIdentity
        return package.setting(["terms", "agreement", "order_unique_id"], .string(orderUid))
            .setting(["terms", "agreement", "identity"], .string(agreement.identity))
    }

    /// The agreement the package carries for its order (decoded; the shared fixture's content).
    static func agreement(_ m: Mission) -> TermsAgreement {
        TermsAgreement.decode(package(m)["terms"]?["agreement"])!
    }

    private static func withoutAgreement(_ package: JSONValue) -> JSONValue {
        package.setting(["terms", "agreement"], .null)
            .setting(["terms", "offline_content_available"], .bool(false))
            .setting(["terms", "agreement_status"], .null)
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

    /// `failed` = mission keys ("opuid:leg") whose package the server could not build.
    static func packagesBody(_ packages: [JSONValue], notActive: [String] = [], failed: [String] = []) -> Data {
        let failures: [JSONValue] = failed.map { key in
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            return .object(["order_product_unique_id": .string(parts[0]), "leg": .string(parts.count > 1 ? parts[1] : ""),
                            "code": .string("package_build_failed")])
        }
        let body: JSONValue = .object([
            "success": .bool(true), "message": .string("Dispatch offline packages."),
            "data": .object(["packages": .array(packages), "not_active": .array(notActive.map { .string($0) }),
                             "failed": .array(failures)]),
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
    /// Requested keys whose package fails to BUILD on the server (reported in `failed`).
    var buildFailures: Set<String> = []
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
    /// Holds the NEXT manifest answer until the test signals it (deterministic concurrency).
    var holdNextManifest: DispatchSemaphore?
    /// Holds the NEXT packages answer until the test signals it.
    var holdNextPackages: DispatchSemaphore?
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
        let gate: DispatchSemaphore? = lock.withLock {
            if request.path == DispatchOfflineAPI.manifestPath, let g = holdNextManifest {
                holdNextManifest = nil
                return g
            }
            if request.path == DispatchOfflineAPI.packagesPath, let g = holdNextPackages {
                holdNextPackages = nil
                return g
            }
            return nil
        }
        // The answer reflects the server at the moment the request arrived; a gate only delays delivery.
        let answer = self.answer(request)
        if let gate = gate {
            DispatchQueue.global().async {
                gate.wait()
                completion(answer)
            }
            return
        }
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
            var failed: [String] = []
            lock.withLock {
                for key in asked {
                    if notActive.contains(key) { inactive.append(key); continue }
                    if omitted.contains(key) { continue }
                    if buildFailures.contains(key) { failed.append(key); continue }
                    if let override = packageOverrides[key] { packages.append(override); continue }
                    if let m = state.missions.first(where: { $0.key == key }) {
                        packages.append(DispatchOfflineFixtures.package(m))
                    } else {
                        inactive.append(key)
                    }
                }
            }
            return .response(SyncHTTPResponse(statusCode: 200, headers: [:],
                                              body: DispatchOfflineFixtures.packagesBody(packages, notActive: inactive, failed: failed)))
        default:
            return .response(SyncHTTPResponse(statusCode: 404, headers: [:], body: nil))
        }
    }

    func setOffline(_ value: Bool) { lock.withLock { offline = value } }
    func setMissions(_ value: [DispatchOfflineFixtures.Mission]) { lock.withLock { missions = value } }
}

/// Routes every request to the server of whichever tenant is signed in AT SEND TIME —
/// exactly how KabbaAPIClient re-reads the base URL + token per request.
final class TenantRoutingClient: SyncHTTPClient {
    private let lock = NSLock()
    private var servers: [String: FakeDispatchServer]
    private var signedIn: String

    init(servers: [String: FakeDispatchServer], signedIn: String) {
        self.servers = servers
        self.signedIn = signedIn
    }

    var tenant: String {
        get { lock.withLock { signedIn } }
        set { lock.withLock { signedIn = newValue } }
    }

    func perform(_ request: SyncHTTPRequest, completion: @escaping (SyncHTTPResult) -> Void) {
        let server = lock.withLock { servers[signedIn]! }
        server.perform(request, completion: completion)
    }
}

extension DispatchOfflineSession {
    /// A test session for `store`'s tenant.
    static func of(_ store: DispatchOfflineMissionStore, credential: String = "cred-1") -> DispatchOfflineSession {
        DispatchOfflineSession(tenantKey: store.tenantKey, credential: credential)
    }
}

/// The App layer's MMKV/UserDefaults writer, recorded in memory per company (Phase 4 bridge).
final class RecordingOrderCacheWriter: DispatchOfflineOrderCacheWriting {
    private let lock = NSLock()
    /// cache → tenant → order uid → payload
    private var _caches: [DispatchOfflineOrderCache: [String: [String: JSONValue]]] = [:]
    private var _writes = 0
    var failWrites = false
    /// Fail only these caches.
    var failing: Set<DispatchOfflineOrderCache> = []

    func write(_ cache: DispatchOfflineOrderCache, payload: JSONValue, orderUniqueId: String, tenantKey: String) -> Bool {
        lock.withLock {
            guard !failWrites, !failing.contains(cache) else { return false }
            _writes += 1
            _caches[cache, default: [:]][tenantKey, default: [:]][orderUniqueId] = payload
            return true
        }
    }

    func cached(_ cache: DispatchOfflineOrderCache, _ orderUniqueId: String, tenant: String) -> JSONValue? {
        lock.withLock { _caches[cache]?[tenant]?[orderUniqueId] }
    }
    func orderDetails(_ orderUniqueId: String, tenant: String) -> JSONValue? { cached(.orderDetails, orderUniqueId, tenant: tenant) }
    func checklistOrder(_ orderUniqueId: String, tenant: String) -> JSONValue? { cached(.checklistOrder, orderUniqueId, tenant: tenant) }
    func assembly(_ orderUniqueId: String, tenant: String) -> JSONValue? { cached(.assembly, orderUniqueId, tenant: tenant) }
    func everything(tenant: String) -> Int { lock.withLock { _caches.values.reduce(0) { $0 + ($1[tenant]?.count ?? 0) } } }
    var writes: Int { lock.withLock { _writes } }
}
