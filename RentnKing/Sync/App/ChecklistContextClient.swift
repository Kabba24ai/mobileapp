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
    func load(orderProductUniqueId: String,
              leg: ChecklistLeg,
              equipmentUniqueId: String? = nil,
              completion: @escaping (Result<ChecklistContext, ChecklistContextError>, _ fromCache: Bool) -> Void) {
        var path = "orders/checklists/context/\(orderProductUniqueId)/\(leg.rawValue)"
        if let unit = equipmentUniqueId, !unit.isEmpty,
           let encoded = unit.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?equipment_unique_id=\(encoded)"
        }

        client.send(method: "GET", path: path) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                if error.isTransportFailure, let cached = self.store.load(orderProductUniqueId: orderProductUniqueId, leg: leg) {
                    completion(.success(cached), true)
                } else {
                    completion(.failure(.api(error)), false)
                }
            case .success(let response):
                guard response.isSuccessStatus else {
                    let error = APIErrorClassifier.classify(statusCode: response.statusCode, body: response.body, headers: response.headers)
                    if let cached = self.store.load(orderProductUniqueId: orderProductUniqueId, leg: leg), error.isServerFailure {
                        completion(.success(cached), true)
                    } else {
                        completion(.failure(.api(error)), false)
                    }
                    return
                }
                do {
                    let context = try ChecklistContext.decode(envelopeData: response.body ?? Data())
                    try? self.store.save(context)
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
