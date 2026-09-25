//
//  ChecklistContextClient.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Loads the canonical checklist context for one order product + leg through
//  KabbaAPIClient and caches it durably (ChecklistContextStore) so the checklist
//  can be completed offline later. Cache-first when offline; server-first when
//  a request succeeds. The cache is a snapshot of Laravel's contract, never a
//  second source of truth.
//
//  Dispatch offline Phase 4: the cache is per company (the company signed in
//  when the request was SENT is the one its answer is saved for), and a cached
//  context is served offline only when ChecklistContextFallbackPolicy allows it —
//  never the cycle a local substitution or restart replaced. Otherwise the
//  answer is `.unavailableOffline` ("this unit's checklist needs a connection").
//

import Foundation

enum ChecklistContextError: Error, Equatable {
    case api(APIError)
    case decoding(String)
    case unavailableOffline
}

final class ChecklistContextClient {

    let client: KabbaAPIClient
    let store: ChecklistContextStore

    init(client: KabbaAPIClient, store: ChecklistContextStore) {
        self.client = client
        self.store = store
    }

    /// Fetches from the server (optionally for a chosen unit when nothing is assigned),
    /// caches on success, falls back to the cache on transport failure.
    /// - Parameter strictUnit: true when `equipmentUniqueId` comes from an action just recorded
    ///   on this phone (a substitution or restart): a cached context must then be for that unit.
    func load(orderProductUniqueId: String,
              leg: ChecklistLeg,
              equipmentUniqueId: String? = nil,
              strictUnit: Bool = false,
              completion: @escaping (Result<ChecklistContext, ChecklistContextError>, _ fromCache: Bool) -> Void) {
        let tenant = store.currentTenantKey
        var path = "orders/checklists/context/\(orderProductUniqueId)/\(leg.rawValue)"
        if let unit = equipmentUniqueId, !unit.isEmpty,
           let encoded = unit.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?equipment_unique_id=\(encoded)"
        }

        client.send(method: "GET", path: path) { [weak self] result in
            guard let self = self else { return }
            // The offline answer: a servable cached copy; `.unavailableOffline` when the cached copy is
            // a replaced cycle / another unit, or a local substitution/restart needs the server's new
            // cycle; otherwise (never cached) the caller keeps today's behavior (P4-D11).
            let offlineAnswer = { (error: APIError) -> Result<ChecklistContext, ChecklistContextError> in
                guard let tenant = tenant,
                      let cached = self.store.load(orderProductUniqueId: orderProductUniqueId, leg: leg, tenantKey: tenant) else {
                    return strictUnit ? .failure(.unavailableOffline) : .failure(.api(error))
                }
                // Served as the user signed in NOW (P4-D5): a shared phone never attributes restarts or
                // substitutions to whoever downloaded or last opened it.
                return ChecklistContextFallbackPolicy.canServeOffline(cached, equipmentHint: equipmentUniqueId, strictUnit: strictUnit,
                                                                      operations: KabbaSync.engine?.snapshot() ?? [])
                    ? .success(cached.servedTo(DispatchOfflineSync.signedInEmployee())) : .failure(.unavailableOffline)
            }
            switch result {
            case .failure(let error):
                if error.isTransportFailure {
                    let answer = offlineAnswer(error)
                    if case .success = answer { completion(answer, true) } else { completion(answer, false) }
                } else {
                    completion(.failure(.api(error)), false)
                }
            case .success(let response):
                guard response.isSuccessStatus else {
                    let error = APIErrorClassifier.classify(statusCode: response.statusCode, body: response.body, headers: response.headers)
                    // The unit hint came from this phone's cache; when the office
                    // reassigned out of band, the hint is stale and the server
                    // answers EQUIPMENT_ASSIGNMENT_CONFLICT. Never wedge on the
                    // stale unit: retry ONCE with no hint so the server resolves
                    // the CANONICAL assignment (superseding a stale prepared
                    // cycle via the openExecution backstop) and hands back the
                    // fresh truth.
                    if error.code == "EQUIPMENT_ASSIGNMENT_CONFLICT", equipmentUniqueId != nil {
                        self.load(orderProductUniqueId: orderProductUniqueId, leg: leg,
                                  equipmentUniqueId: nil, completion: completion)
                        return
                    }
                    if error.isServerFailure {
                        let answer = offlineAnswer(error)
                        if case .success = answer { completion(answer, true) } else { completion(answer, false) }
                    } else {
                        completion(.failure(.api(error)), false)
                    }
                    return
                }
                do {
                    let context = try ChecklistContext.decode(envelopeData: response.body ?? Data())
                    if let tenant = tenant { try? self.store.save(context, tenantKey: tenant) }
                    completion(.success(context), false)
                } catch {
                    completion(.failure(.decoding(error.localizedDescription)), false)
                }
            }
        }
    }

    /// The cached snapshot only (offline path).
    func cached(orderProductUniqueId: String, leg: ChecklistLeg) -> ChecklistContext? {
        store.load(orderProductUniqueId: orderProductUniqueId, leg: leg)
    }
}
