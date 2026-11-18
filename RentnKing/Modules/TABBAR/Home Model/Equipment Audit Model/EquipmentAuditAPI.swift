//
//  EquipmentAuditAPI.swift
//  RentnKing
//
//  The mobile Equipment Audit's ONE network path (2026-10-05): reads and
//  writes against api/admin/v1/equipment-audits through the canonical
//  KabbaAPIClient (real HTTP status, X-Request-Id, 401/426 handling).
//
//  ONLINE ONLY, on purpose. An audit verification is recorded against the
//  unit's movement episode at the moment it is written; queued offline and
//  written later, it could count against an episode nobody looked at. So a
//  write never enters the Sync Engine: offline it fails at once with a plain
//  "nothing was recorded", and a dropped connection mid-request is retried
//  ONCE with the same operation id — Laravel replays it if it had landed.
//

import Foundation

/// Why an audit request did not succeed, in the employee's terms.
struct EquipmentAuditFailure: Error {
    let message: String
    let code: String?
    let statusCode: Int?
    let isOffline: Bool
    let validationErrors: [String: [String]]
    let context: JSONValue?

    /// Kabba's record of the unit changed since the list loaded — refresh, decide again.
    var isStale: Bool { code == "STALE_SCREEN" || code == "UNIT_NOT_IN_AUDIT" }
    var isAuditClosed: Bool { code == "AUDIT_NOT_ACTIVE" || code == "AUDIT_NOT_FOUND" }
    var isForbidden: Bool { statusCode == 403 }
    var isValidation: Bool { statusCode == 422 && !validationErrors.isEmpty }

    static let offline = EquipmentAuditFailure(message: EquipmentAuditPresentation.offlineMessage, code: nil, statusCode: nil,
                                               isOffline: true, validationErrors: [:], context: nil)

    static func from(_ error: APIError) -> EquipmentAuditFailure {
        if error.isTransportFailure {
            return EquipmentAuditFailure(message: EquipmentAuditPresentation.failureMessage(statusCode: nil, transport: error.transport ?? .other, serverMessage: ""),
                                         code: nil, statusCode: nil, isOffline: true, validationErrors: [:], context: nil)
        }
        if error.statusCode == 403 {
            return EquipmentAuditFailure(message: "Your account does not have permission for this Equipment Audit action.",
                                         code: error.code, statusCode: 403, isOffline: false, validationErrors: [:], context: nil)
        }
        let first = error.validationErrors.values.first?.first
        let serverMessage = (error.statusCode == 422 ? first : nil) ?? error.message
        return EquipmentAuditFailure(message: EquipmentAuditPresentation.failureMessage(statusCode: error.statusCode, transport: nil, serverMessage: serverMessage),
                                     code: error.code, statusCode: error.statusCode, isOffline: false,
                                     validationErrors: error.validationErrors, context: error.details?["context"])
    }

    static func decoding(_ description: String) -> EquipmentAuditFailure {
        EquipmentAuditFailure(message: "Kabba answered in an unexpected format. Pull to refresh and try again.",
                              code: "DECODING", statusCode: nil, isOffline: false, validationErrors: [:], context: .string(description))
    }
}

final class EquipmentAuditAPI {

    static let shared = EquipmentAuditAPI()

    /// Seam for tests.
    var clientProvider: () -> KabbaAPIClient? = { KabbaSync.client }

    // MARK: Reads

    func loadIndex(_ completion: @escaping (Result<EquipmentAuditIndex, EquipmentAuditFailure>) -> Void) {
        get(EquipmentAuditCommands.indexPath, as: EquipmentAuditIndex.self, completion)
    }

    func loadBoard(audit: String, _ completion: @escaping (Result<EquipmentAuditBoard, EquipmentAuditFailure>) -> Void) {
        get(EquipmentAuditCommands.boardPath(audit), as: EquipmentAuditBoard.self, completion)
    }

    func loadOffSiteOptions(audit: String, equipment: String, _ completion: @escaping (Result<EquipmentAuditOffSiteOptions, EquipmentAuditFailure>) -> Void) {
        get(EquipmentAuditCommands.offSiteOptionsPath(audit, equipment: equipment), as: EquipmentAuditOffSiteOptions.self, completion)
    }

    // MARK: Writes

    /// Sends one audit action. Success carries the unit's new row, the audit's
    /// totals and Laravel's message ("TAK-SS-14 verified.").
    func perform(_ command: EquipmentAuditCommand,
                 _ completion: @escaping (Result<(EquipmentAuditActionResult, String?), EquipmentAuditFailure>) -> Void) {
        send(command, retriesLeft: 1, completion)
    }

    private func send(_ command: EquipmentAuditCommand, retriesLeft: Int,
                      _ completion: @escaping (Result<(EquipmentAuditActionResult, String?), EquipmentAuditFailure>) -> Void) {
        guard let client = clientProvider() else { return finish(completion, .failure(.offline)) }

        client.send(method: "POST", path: command.path, jsonBody: command.body, operationId: command.operationId) { [weak self] result in
            switch result {
            case .failure(let error):
                // The request may have reached Kabba before the connection dropped:
                // the same operation id makes a retry a replay, never a second record.
                if retriesLeft > 0, error.isTransportFailure,
                   [.timeout, .connectionLost].contains(error.transport ?? .other) {
                    self?.send(command, retriesLeft: retriesLeft - 1, completion)
                    return
                }
                self?.finish(completion, .failure(.from(error)))
            case .success(let response):
                guard response.isSuccessStatus else {
                    let error = APIErrorClassifier.classify(statusCode: response.statusCode, body: response.body, headers: response.headers)
                    self?.finish(completion, .failure(.from(error)))
                    return
                }
                do {
                    let body = response.body ?? Data()
                    let decoded = try EquipmentAuditDecoding.decode(EquipmentAuditActionResult.self, envelope: body)
                    self?.finish(completion, .success((decoded, APIEnvelope.parse(body)?.message)))
                } catch {
                    self?.finish(completion, .failure(.decoding(error.localizedDescription)))
                }
            }
        }
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ path: String, as type: T.Type, _ completion: @escaping (Result<T, EquipmentAuditFailure>) -> Void) {
        guard let client = clientProvider() else { return finish(completion, .failure(.offline)) }

        client.send(method: "GET", path: path) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.finish(completion, .failure(.from(error)))
            case .success(let response):
                guard response.isSuccessStatus else {
                    let error = APIErrorClassifier.classify(statusCode: response.statusCode, body: response.body, headers: response.headers)
                    self?.finish(completion, .failure(.from(error)))
                    return
                }
                do {
                    self?.finish(completion, .success(try EquipmentAuditDecoding.decode(type, envelope: response.body ?? Data())))
                } catch {
                    self?.finish(completion, .failure(.decoding(error.localizedDescription)))
                }
            }
        }
    }

    private func finish<T>(_ completion: @escaping (Result<T, EquipmentAuditFailure>) -> Void, _ result: Result<T, EquipmentAuditFailure>) {
        if Thread.isMainThread { completion(result) } else { DispatchQueue.main.async { completion(result) } }
    }
}

/// Per-audit choices this phone remembers: the working store and the filter
/// only when the employee chose them (otherwise they follow the Section
/// Auditor assignment on every refresh), and who verifies rows in sections
/// that have no Section Auditor.
enum EquipmentAuditMemory {
    private static var defaults: UserDefaults { .standard }
    private static func key(_ name: String, _ audit: String) -> String { "equipmentAudit.\(name).\(audit)" }

    static func workingStoreId(audit: String) -> Int? {
        defaults.object(forKey: key("workingStore", audit)) as? Int
    }

    static func setWorkingStoreId(_ id: Int?, audit: String) {
        if let id = id { defaults.set(id, forKey: key("workingStore", audit)) } else { defaults.removeObject(forKey: key("workingStore", audit)) }
    }

    /// nil = the default (the employee's sections, following the assignment).
    static func visibleSections(audit: String) -> [String]? {
        defaults.stringArray(forKey: key("sections", audit))
    }

    static func setVisibleSections(_ keys: [String]?, audit: String) {
        if let keys = keys { defaults.set(keys, forKey: key("sections", audit)) } else { defaults.removeObject(forKey: key("sections", audit)) }
    }

    static func verifyingAs(audit: String) -> Int? {
        defaults.object(forKey: key("verifyingAs", audit)) as? Int
    }

    static func setVerifyingAs(_ id: Int?, audit: String) {
        if let id = id { defaults.set(id, forKey: key("verifyingAs", audit)) } else { defaults.removeObject(forKey: key("verifyingAs", audit)) }
    }
}
