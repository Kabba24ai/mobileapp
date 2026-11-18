//
//  StaleAvailabilityRetirement.swift
//  RentnKing — Sync Core (Foundation only)
//
//  P10 (2026-09-29, order #6024): the driver confirmed unit A Available while the
//  phone was offline; meanwhile the office reassigned the line to unit B. When the
//  queue drained, Laravel refused the stale confirmation — 409 QUEUE_ASSIGNMENT_CHANGED,
//  retryable false, "this item now has B assigned", `current_equipment` = B — and the
//  engine parked it as Needs Attention. Correct as a verdict; wrong as a resting
//  state: the phone had already adopted B, the decision about A could never be
//  acted on again, yet it kept the line's "Sync Issue" badge lit until someone found
//  Settings › Sync and pressed Discard.
//
//  This file retires exactly that record — and nothing else. A parked unit
//  Available is SUPERSEDED (kept as history, never replayed, never evidence, never
//  an issue) only when all four proofs hold:
//    1. the rejected operation confirmed availability of one UNIT, A;
//    2. this phone's canonical assignment for the line is now a unit B;
//    3. A != B;
//    4. the server's rejection identified B — by unique id in `current_equipment`
//       (records parked by this build), or, for records parked before this build
//       kept only the sentence, by naming B's exact display name in it.
//  No proof, no retirement: an unrefreshed package (canonical still A, or unknown), a
//  package that names a THIRD unit, an option decision, another rejection code, a
//  rejected switch — all stay Needs Attention exactly as before.
//

import Foundation

/// What the server said the line has now — kept on the parked operation so the
/// decision can be judged later, when the phone has refreshed the line.
struct SyncAssignmentChange: Codable, Equatable {
    let currentEquipmentUniqueId: String
    let currentEquipmentName: String?
    let receivedAt: Date

    init(currentEquipmentUniqueId: String, currentEquipmentName: String?, receivedAt: Date) {
        self.currentEquipmentUniqueId = currentEquipmentUniqueId
        self.currentEquipmentName = currentEquipmentName
        self.receivedAt = receivedAt
    }

    /// Only a QUEUE_ASSIGNMENT_CHANGED rejection that names the current machine yields a verdict.
    init?(error: APIError, now: Date) {
        guard error.code == StaleAvailabilityRetirement.assignmentChangedCode,
              let current = error.details?["current_equipment"],
              let unit = current["unique_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !unit.isEmpty else { return nil }
        self.init(currentEquipmentUniqueId: unit,
                  currentEquipmentName: current["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
                  receivedAt: now)
    }
}

/// Why a record was retired, and by what. Written once, when the state becomes `.superseded`.
struct SyncSupersession: Codable, Equatable {
    enum Proof: String, Codable, Equatable {
        /// The rejection carried `current_equipment.unique_id` and it equals the canonical unit.
        case serverVerdict = "server_verdict"
        /// A record parked before verdicts were kept: the rejection's sentence names the canonical
        /// unit's exact display name ("… now has <name> assigned").
        case serverMessage = "server_message"
    }

    /// The rejection code that made the decision obsolete (today only QUEUE_ASSIGNMENT_CHANGED).
    let reason: String
    /// The unit the retired decision was about (A).
    let retiredSubjectKey: String
    /// The unit the line has now (B), and its display name when the phone knows it.
    let supersededByEquipmentUniqueId: String
    let supersededByEquipmentName: String?
    let resolvedAt: Date
    let proof: Proof

    /// Employee wording for the diagnostics screen.
    var summary: String {
        "Retired: the assigned machine changed to \(supersededByEquipmentName ?? supersededByEquipmentUniqueId) before this confirmation of \(retiredSubjectKey) reached Kabba. Nothing to do."
    }
}

enum StaleAvailabilityRetirement {

    static let assignmentChangedCode = "QUEUE_ASSIGNMENT_CHANGED"

    /// The retirement decision. `canonicalEquipmentUniqueId` / `canonicalEquipmentName` are what THIS
    /// phone currently holds as the line's assigned unit (its refreshed package / Assembly Review) —
    /// nil when it holds nothing, in which case nothing is retired.
    static func supersession(for op: SyncOperation,
                             canonicalEquipmentUniqueId: String?,
                             canonicalEquipmentName: String?,
                             now: Date) -> SyncSupersession? {
        // 1. A parked availability decision about one unit.
        guard op.state == .needsAttention,
              op.type == AssemblyOperationBuilder.availabilityType,
              op.payload["subject_type"]?.stringValue == AvailabilitySubject.unit.rawValue,
              let unitA = op.payload["subject_key"]?.stringValue?.nonEmpty,
              op.attempts.lastErrorCode == assignmentChangedCode else { return nil }
        // 2. + 3. The phone knows the line's unit now, and it is a different one.
        guard let unitB = canonicalEquipmentUniqueId?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
              unitB != unitA else { return nil }
        // 4. The server identified B — consistently with what the phone holds.
        let proof: SyncSupersession.Proof
        if let verdict = op.assignmentChange {
            guard verdict.currentEquipmentUniqueId == unitB else { return nil }
            proof = .serverVerdict
        } else {
            guard let name = canonicalEquipmentName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
                  let sentence = op.attempts.lastErrorMessage,
                  sentence.contains("now has \(name) assigned") else { return nil }
            proof = .serverMessage
        }
        return SyncSupersession(reason: assignmentChangedCode, retiredSubjectKey: unitA,
                                supersededByEquipmentUniqueId: unitB,
                                supersededByEquipmentName: canonicalEquipmentName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                                    ?? op.assignmentChange?.currentEquipmentName,
                                resolvedAt: now, proof: proof)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
