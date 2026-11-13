//
//  SupplierDirectoryAPI.swift
//  RentnKing
//
//  The Supplier Directory's ONE network path (2026-11-13): api/admin/v1/suppliers
//  through the canonical KabbaAPIClient (real HTTP status, X-Request-Id, the
//  signed-in session, 401/426 handling).
//
//  Reads are online first; every supplier Kabba returns is also kept as a
//  read-only copy on this phone (company-scoped), which the screens show when
//  there is no connection. Adding a supplier is ONLINE ONLY — it never enters the
//  Sync Engine: offline it fails at once ("nothing was saved"); a connection that
//  drops mid-request is retried ONCE with the same operation id, which Laravel
//  replays instead of adding the supplier twice.
//

import Foundation

/// Why a Supplier Directory request did not succeed, in the employee's terms.
struct SupplierDirectoryFailure: Error {
    let message: String
    let code: String?
    let statusCode: Int?
    let isOffline: Bool
    let validationErrors: [String: [String]]
    /// The likely duplicates a 409 SUPPLIER_POSSIBLE_DUPLICATE carried.
    let duplicates: [SupplierDuplicate]

    var isForbidden: Bool { statusCode == 403 }
    var isNotFound: Bool { statusCode == 404 }
    var isPossibleDuplicate: Bool { code == "SUPPLIER_POSSIBLE_DUPLICATE" }

    static let offline = SupplierDirectoryFailure(message: "No connection to Kabba.", code: nil, statusCode: nil,
                                                  isOffline: true, validationErrors: [:], duplicates: [])

    static func from(_ error: APIError, body: Data? = nil) -> SupplierDirectoryFailure {
        if error.isTransportFailure {
            let message = [.timeout, .connectionLost].contains(error.transport ?? .other)
                ? "The connection dropped before Kabba answered."
                : "No connection to Kabba."
            return SupplierDirectoryFailure(message: message, code: nil, statusCode: nil, isOffline: true, validationErrors: [:], duplicates: [])
        }
        if error.statusCode == 403 {
            return SupplierDirectoryFailure(message: SupplierDirectoryPresentation.forbidden, code: error.code, statusCode: 403,
                                            isOffline: false, validationErrors: [:], duplicates: [])
        }
        let first = error.validationErrors.values.first?.first
        var message = (error.statusCode == 422 ? first : nil) ?? error.message
        if let status = error.statusCode, status >= 500 || status == 429 {
            message = "Kabba couldn't answer right now. Nothing was changed — try again in a moment."
        }
        return SupplierDirectoryFailure(message: message, code: error.code, statusCode: error.statusCode, isOffline: false,
                                        validationErrors: error.validationErrors,
                                        duplicates: SupplierDirectoryDecoding.duplicates(fromErrorBody: body))
    }

    static func decoding(_ description: String) -> SupplierDirectoryFailure {
        SupplierDirectoryFailure(message: "Kabba answered in an unexpected format. Pull to refresh and try again.",
                                 code: "DECODING", statusCode: nil, isOffline: false, validationErrors: [:], duplicates: [])
    }
}

extension SupplierDirectoryOfflineCopy {
    /// The phone's copy in MMKV, under the signed-in company (DispatchOfflineTenantStorage).
    static let phone = SupplierDirectoryOfflineCopy(
        read: { key in
            guard let scoped = SDKUserDefault.scopedKey(key) else { return nil }
            return SDKUserDefault.getData(for: scoped)
        },
        write: { key, data in
            guard let data else { return SDKUserDefault.remove(for: key) }   // remove(for:) scopes the key itself
            guard let scoped = SDKUserDefault.scopedKey(key) else { return }
            SDKUserDefault.save(data, for: scoped)
        })
}

final class SupplierDirectoryAPI {

    static let shared = SupplierDirectoryAPI()

    /// Seams for tests.
    var clientProvider: () -> KabbaAPIClient? = { KabbaSync.client }
    var offlineCopy: SupplierDirectoryOfflineCopy = .phone

    // MARK: Reads

    func search(_ term: String, scope: SupplierSearchScope, status: SupplierStatusFilter, page: Int,
                _ completion: @escaping (Result<SupplierPage, SupplierDirectoryFailure>) -> Void) {
        let path = SupplierDirectoryPaths.list(search: term, scope: scope, status: status, page: page)
        get(path, as: SupplierPage.self) { [weak self] result in
            // The plain Active list's first page is what the directory shows offline.
            if case .success(let page) = result, page.pagination.currentPage == 1, status == .active,
               term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self?.offlineCopy.saveList(page.suppliers)
            }
            completion(result)
        }
    }

    func detail(_ uniqueId: String, _ completion: @escaping (Result<SupplierDetailEnvelope, SupplierDirectoryFailure>) -> Void) {
        get(SupplierDirectoryPaths.detail(uniqueId), as: SupplierDetailEnvelope.self) { [weak self] result in
            if case .success(let envelope) = result { self?.offlineCopy.saveDetail(envelope) }
            completion(result)
        }
    }

    func options(_ completion: @escaping (Result<SupplierOptions, SupplierDirectoryFailure>) -> Void) {
        get(SupplierDirectoryPaths.options, as: SupplierOptions.self, completion)
    }

    // MARK: Writes

    func duplicates(for draft: SupplierDraft, _ completion: @escaping (Result<[SupplierDuplicate], SupplierDirectoryFailure>) -> Void) {
        post(SupplierDirectoryPaths.duplicateCheck, body: draft.duplicateCheckBody, operationId: nil, retriesLeft: 0,
             as: SupplierDuplicates.self) { completion($0.map(\.duplicates)) }
    }

    /// Adds the supplier. A 409 with likely duplicates comes back as a failure carrying them.
    func create(_ draft: SupplierDraft, acknowledgeDuplicates: Bool, operationId: String,
                _ completion: @escaping (Result<SupplierDetailEnvelope, SupplierDirectoryFailure>) -> Void) {
        post(SupplierDirectoryPaths.create, body: draft.body(acknowledgeDuplicates: acknowledgeDuplicates), operationId: operationId,
             retriesLeft: 1, as: SupplierDetailEnvelope.self) { [weak self] result in
            if case .success(let envelope) = result { self?.offlineCopy.saveDetail(envelope) }
            completion(result)
        }
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ path: String, as type: T.Type, _ completion: @escaping (Result<T, SupplierDirectoryFailure>) -> Void) {
        guard let client = clientProvider() else { return finish(completion, .failure(.offline)) }
        client.send(method: "GET", path: path) { [weak self] result in
            self?.finish(completion, Self.decode(result, as: type))
        }
    }

    private func post<T: Decodable>(_ path: String, body: JSONValue, operationId: String?, retriesLeft: Int, as type: T.Type,
                                    _ completion: @escaping (Result<T, SupplierDirectoryFailure>) -> Void) {
        guard let client = clientProvider() else { return finish(completion, .failure(.offline)) }
        client.send(method: "POST", path: path, jsonBody: body, operationId: operationId) { [weak self] result in
            if case .failure(let error) = result, retriesLeft > 0, operationId != nil, error.isTransportFailure,
               [.timeout, .connectionLost].contains(error.transport ?? .other) {
                // It may have reached Kabba: the same operation id makes the retry a replay.
                self?.post(path, body: body, operationId: operationId, retriesLeft: retriesLeft - 1, as: type, completion)
                return
            }
            self?.finish(completion, Self.decode(result, as: type))
        }
    }

    private static func decode<T: Decodable>(_ result: Result<SyncHTTPResponse, APIError>, as type: T.Type) -> Result<T, SupplierDirectoryFailure> {
        switch result {
        case .failure(let error):
            return .failure(.from(error))
        case .success(let response):
            guard response.isSuccessStatus else {
                let error = APIErrorClassifier.classify(statusCode: response.statusCode, body: response.body, headers: response.headers)
                return .failure(.from(error, body: response.body))
            }
            do {
                return .success(try SupplierDirectoryDecoding.decode(type, envelope: response.body ?? Data()))
            } catch {
                return .failure(.decoding(error.localizedDescription))
            }
        }
    }

    private func finish<T>(_ completion: @escaping (Result<T, SupplierDirectoryFailure>) -> Void, _ result: Result<T, SupplierDirectoryFailure>) {
        if Thread.isMainThread { completion(result) } else { DispatchQueue.main.async { completion(result) } }
    }
}
