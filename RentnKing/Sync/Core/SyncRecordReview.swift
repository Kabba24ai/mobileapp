//
//  SyncRecordReview.swift
//  RentnKing — Sync Core (Foundation only)
//
//  What an employee needs to decide about ONE record in Settings → Sync
//  (MOBILE-QUALITY-01, items 01/02):
//
//    • which kind of problem it is — rejected by Kabba (a person must decide),
//      waiting for a connection, or failing temporarily (retries by itself);
//    • why Kabba refused it, in plain words, and what to do about it;
//    • what the record holds that may exist ONLY on this phone (inspection
//      answers, photos, signatures, a driver's license image, readings, notes);
//    • what this phone will show differently once the record is removed.
//
//  Pure and deterministic: no UIKit, no network, no file access. The server's
//  validation is never second-guessed here — a rejection is explained, never
//  reclassified as accepted, and nothing in this file can make a parked record
//  sendable again (only a person's Try Again does that, through the engine).
//

import Foundation

// MARK: - Problem kind

/// How a record that has not reached Kabba should be treated.
enum SyncRecordProblem: Equatable {
    /// Nothing wrong — it reached Kabba (synced) or was retired as history (superseded).
    case none
    /// Not sent yet; nothing has failed (or it is being sent right now).
    case waiting
    /// The last attempt could not reach Kabba (offline, timeout, dropped connection).
    case waitingForConnection
    /// Kabba (or the network) failed temporarily — the engine retries by itself.
    case temporaryFailure
    /// Sending is paused until someone signs in again / updates the app.
    case paused
    /// Kabba refused it permanently. It is never retried automatically; a person decides.
    case rejected

    static func of(_ op: SyncOperation) -> SyncRecordProblem {
        switch op.state {
        case .synced, .superseded:
            return .none
        case .needsAttention:
            return .rejected
        case .syncing:
            return .waiting
        case .pending:
            switch op.attempts.lastDisposition {
            case .waitForAuthentication?, .waitForAppUpdate?:
                return .paused
            case .retry?:
                if op.attempts.lastTransportFailure != nil { return .waitingForConnection }
                return .temporaryFailure
            case .needsAttention?, nil:
                // Never tried, or put back by Try Again: simply queued.
                return .waiting
            }
        }
    }
}

// MARK: - Why Kabba refused it

struct SyncRejectionExplanation: Equatable {
    /// One line: what happened ("This job was reassigned").
    let headline: String
    /// Why Kabba refused it.
    let detail: String
    /// What the employee can do.
    let advice: String
    /// True when the situation can change on Kabba's side so that Try Again may
    /// succeed (e.g. the office assigns the job back). False when the same copy
    /// will be refused again whatever happens.
    let retryMayHelp: Bool
}

enum SyncRejectionCatalog {

    /// Operation types whose terminal rejection Laravel also records for the office
    /// (MobileSyncIssue::ACTIONABLE_OPERATION_TYPES — Manage Schedule Conflicts →
    /// Mobile Sync Issues). Removing the phone's copy does not close that issue: the
    /// office's row resolves when the business outcome is reached.
    static let officeTrackedTypes: Set<String> = [
        "delivery_checklist.complete", "return_checklist.complete",
        "delivery_checklist.prepare", "return_checklist.prepare",
        "fulfillment_inputs.update",
        "delivery_media.upload", "return_media.upload", "license_media.upload",
        "terms.accept", "terms.sign",
    ]

    static func officeSees(_ op: SyncOperation) -> Bool {
        // Only a rejection the SERVER answered is on its ledger; a record this phone
        // could not even build never reached Laravel.
        op.state == .needsAttention && op.attempts.lastStatusCode != nil && officeTrackedTypes.contains(op.type)
    }

    static func explain(_ op: SyncOperation) -> SyncRejectionExplanation {
        explain(code: op.attempts.lastErrorCode, statusCode: op.attempts.lastStatusCode, serverMessage: op.attempts.lastErrorMessage)
    }

    static func explain(code rawCode: String?, statusCode: Int?, serverMessage: String?) -> SyncRejectionExplanation {
        let code = rawCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let usual = "Open the order to check what Kabba has now. If the work is already recorded there, this copy can be removed."

        switch code {
        case "DISPATCH_ASSIGNMENT_CHANGED":
            return .init(headline: "This job was reassigned",
                         detail: "Kabba refused it because the delivery or return was no longer assigned to you when this phone sent it — the office had reassigned it.",
                         advice: "If you did this work, tell the office so they can record it. If the job is assigned back to you, tap Try Again.",
                         retryMayHelp: true)
        case "QUEUE_ASSIGNMENT_CHANGED":
            return .init(headline: "The equipment on this line changed",
                         detail: "The office assigned a different unit to this order line after you recorded this.",
                         advice: "Check the line's current equipment. A decision about the old unit no longer applies and can be removed.",
                         retryMayHelp: false)
        case "CHECKLIST_QUESTION_MISMATCH":
            return .init(headline: "The answers don't match this equipment's checklist",
                         detail: "Kabba refused it because at least one answer belongs to a different checklist than the one this equipment uses now — for example after the equipment or its checklist changed.",
                         advice: "Kabba will not accept this copy. Check the order: if the checklist is not recorded yet, complete it again from Order Details, then remove this copy.",
                         retryMayHelp: false)
        case "DELIVERY_DEPARTED":
            return .init(headline: "The delivery had already left",
                         detail: "The equipment on a delivery is locked from On My Way until it is completed or the office recalls it.",
                         advice: "Ask the office to recall the delivery if this change is still needed, then tap Try Again.",
                         retryMayHelp: true)
        case "CHECKLIST_ALREADY_COMPLETED", "CHECKLIST_ALREADY_SUBMITTED":
            return .init(headline: "Already completed on Kabba",
                         detail: "This checklist was completed before this copy arrived — from another phone or by the office.",
                         advice: usual,
                         retryMayHelp: false)
        case "CHECKLIST_EXECUTION_SUPERSEDED":
            return .init(headline: "A newer checklist replaced this one",
                         detail: "The checklist was restarted, or the equipment was changed, after this was saved.",
                         advice: usual,
                         retryMayHelp: false)
        case "CHECKLIST_EXECUTION_NOT_FOUND", "NO_CHECKLIST_FOUND", "NO_QUESTIONS_FOUND":
            return .init(headline: "Kabba no longer has this checklist",
                         detail: "The checklist this was recorded against does not exist on Kabba any more.",
                         advice: usual,
                         retryMayHelp: false)
        case "CHECKLIST_NOT_DELIVERED":
            return .init(headline: "The delivery isn't complete on Kabba",
                         detail: "A return can only be recorded after its delivery is complete.",
                         advice: "Ask the office to complete the delivery, then tap Try Again.",
                         retryMayHelp: true)
        case "CHECKLIST_LEG_INVALID":
            return .init(headline: "Wrong delivery or return step",
                         detail: "Kabba refused it because the order line is not at the delivery or return step this was recorded for.",
                         advice: usual,
                         retryMayHelp: false)
        case "REQUIRED_ANSWERS_MISSING", "SIGNATURE_REQUIRED", "EQUIPMENT_REQUIRED",
             "CHECKLIST_INCOMPLETE_FOR_STAGING", "CHECKLIST_INCOMPLETE_IN_TRANSIT", "VALIDATION_FAILED":
            return .init(headline: "Something required was missing",
                         detail: "Kabba refused it because a required answer, signature or piece of equipment was missing or not valid.",
                         advice: "Open the order and complete it again with everything required, then remove this copy.",
                         retryMayHelp: false)
        case "EQUIPMENT_ASSIGNMENT_CONFLICT", "EQUIPMENT_IS_RENTED", "EQUIPMENT_CURRENTLY_RENTED", "INVALID_EQUIPMENT_STATUS":
            return .init(headline: "The equipment's status didn't allow this",
                         detail: "The unit was rented, assigned elsewhere or in a status that does not allow this change.",
                         advice: "Check the unit with the office. Tap Try Again once its status is corrected.",
                         retryMayHelp: true)
        case "QUEUE_ITEM_IN_TRANSIT", "QUEUE_ITEM_DELIVERED":
            return .init(headline: "The equipment had already left the yard",
                         detail: "A yard change cannot be recorded once the equipment is on its way or delivered.",
                         advice: usual,
                         retryMayHelp: false)
        case "QUEUE_AVAILABILITY_BLOCKED":
            return .init(headline: "Equipment marked Not Available",
                         detail: "The assigned unit or an option on this line is marked Not Available.",
                         advice: "Resolve the availability in the yard, then tap Try Again.",
                         retryMayHelp: true)
        case "ORDER_NOT_FOUND", "ORDER_PRODUCT_NOT_FOUND", "EQUIPMENT_NOT_FOUND", "NOT_FOUND":
            return .init(headline: "Kabba couldn't find the order or equipment",
                         detail: "The order, the order line or the equipment no longer exists on Kabba (for example it was cancelled or removed).",
                         advice: usual,
                         retryMayHelp: false)
        case "FORBIDDEN":
            return .init(headline: "Your account isn't allowed to do this",
                         detail: "Kabba refused it for the account that sent it.",
                         advice: "Ask the office to check your access. Tap Try Again once it is fixed.",
                         retryMayHelp: true)
        case "MEDIA_CLIENT_ID_CONFLICT", "MEDIA_ASSOCIATION_INVALID", "MEDIA_TYPE_INVALID":
            return .init(headline: "Kabba couldn't attach this file",
                         detail: "The file did not match the order line it was taken for, or its type is not accepted.",
                         advice: usual,
                         retryMayHelp: false)
        case "TERMS_IDENTITY_MISMATCH", "TERMS_AGREEMENT_UNAVAILABLE":
            return .init(headline: "The terms on this order don't match",
                         detail: "The signature was recorded against an agreement that is not the one stored on this order.",
                         advice: "Ask the office to check the order's Terms & Conditions.",
                         retryMayHelp: false)
        case "OPERATION_ID_CONFLICT":
            return .init(headline: "Kabba already has a different record with this ID",
                         detail: "Kabba refused this copy to avoid recording something twice.",
                         advice: usual,
                         retryMayHelp: false)
        case "ROUTE_RETIRED":
            return .init(headline: "This app version can't send this record",
                         detail: "The record uses a route Kabba no longer accepts.",
                         advice: "Update the app from the App Store, then tap Try Again.",
                         retryMayHelp: true)
        default:
            if statusCode == nil {
                // Parked by THIS phone before any answer from Kabba (no handler, unbuildable payload).
                return .init(headline: "This phone couldn't send this record",
                             detail: "The record could not be prepared for Kabba on this phone.",
                             advice: "Send the operation id to support. Remove it once the work is confirmed another way.",
                             retryMayHelp: false)
            }
            let message = serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .init(headline: "Kabba refused this record",
                         detail: message.isEmpty ? "Kabba refused it and will not accept the same copy again." : message,
                         advice: usual,
                         retryMayHelp: false)
        }
    }
}

// MARK: - What the record holds

/// What a record carries that may exist only on this phone. Counts and kinds only —
/// never the answers, notes or images themselves.
struct SyncRecordContents: Equatable {
    var answers = 0
    var photos = 0
    var videos = 0
    var signature = false
    var licenseImage = false
    var licenseExpiry = false
    var readings = false
    var note = false
    var callSteps = false

    /// True when the record holds work a person captured (anything besides a status tap).
    var holdsCapturedWork: Bool {
        answers > 0 || photos > 0 || videos > 0 || signature || licenseImage || readings || note || callSteps
    }

    /// "12 checklist answers · 3 photos · a signature" — empty when there is nothing besides the action itself.
    var summary: String {
        items.joined(separator: " · ")
    }

    var items: [String] {
        var parts: [String] = []
        if answers > 0 { parts.append("\(answers) checklist answer\(answers == 1 ? "" : "s")") }
        if readings { parts.append("hours / fuel readings") }
        if note { parts.append("a note") }
        if callSteps { parts.append("customer call steps") }
        if photos > 0 { parts.append("\(photos) photo\(photos == 1 ? "" : "s")") }
        if videos > 0 { parts.append("\(videos) video\(videos == 1 ? "" : "s")") }
        if licenseImage { parts.append(licenseExpiry ? "a driver's license image and expiration date" : "a driver's license image") }
        if signature { parts.append("a signature") }
        return parts
    }

    static let readingKeys: Set<String> = [
        "start_hours", "end_hours",
        "fuel_initial_reading", "fuel_final_reading",
        "def_initial_reading", "def_final_reading",
        "equipment_fuel",
    ]

    static func of(_ op: SyncOperation) -> SyncRecordContents {
        var c = SyncRecordContents()
        let payload = op.payload

        if let answers = payload["answers"]?.arrayValue {
            c.answers = answers.filter { !(($0["answer_id"]?.stringValue ?? "").isEmpty) }.count
        }
        c.readings = readingKeys.contains { !((payload[$0]?.stringValue ?? "").isEmpty) }
        c.note = ["note", "unloading_note"].contains { !((payload[$0]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        c.callSteps = ["address_verified", "equipment_verified", "unloading_situation"].contains { payload[$0] != nil }

        let isLicense = op.type == EffectiveFieldState.licenseMediaType
        for asset in op.assets {
            let mime = asset.mimeType.lowercased()
            if asset.fieldName == "signature_media" {
                c.signature = true
            } else if isLicense {
                c.licenseImage = true
            } else if mime.hasPrefix("video/") {
                c.videos += 1
            } else if mime.hasPrefix("image/") {
                c.photos += 1
            }
        }
        if isLicense {
            c.licenseExpiry = !((payload["license_expiry_date"]?.stringValue ?? "").isEmpty)
        }
        return c
    }
}

// MARK: - The review of one record

struct SyncRecordReview: Equatable {
    let operationId: String
    let title: String
    let problem: SyncRecordProblem
    /// Present only for a rejected record.
    let explanation: SyncRejectionExplanation?
    let contents: SyncRecordContents
    /// The office also sees this rejection under Mobile Sync Issues.
    let officeSees: Bool
    /// What this phone will show differently once the record is removed.
    let removalConsequence: String
    /// A person may remove it: rejected, or still waiting (never while it is being sent,
    /// never once Kabba has it or it was retired as history).
    let canRemove: Bool
    /// A person may ask for one more attempt.
    let canRetry: Bool
    /// The server's own words (sanitized), for support.
    let serverMessage: String?
    let errorCode: String?

    static func of(_ op: SyncOperation) -> SyncRecordReview {
        let problem = SyncRecordProblem.of(op)
        return SyncRecordReview(
            operationId: op.id,
            title: op.displayTitle ?? op.type,
            problem: problem,
            explanation: problem == .rejected ? SyncRejectionCatalog.explain(op) : nil,
            contents: SyncRecordContents.of(op),
            officeSees: SyncRejectionCatalog.officeSees(op),
            removalConsequence: consequence(of: op),
            canRemove: isRemovable(op),
            canRetry: op.state == .needsAttention || op.state == .pending,
            serverMessage: SyncDiagnostics.sanitize(op.attempts.lastErrorMessage),
            errorCode: op.attempts.lastErrorCode)
    }

    static func isRemovable(_ op: SyncOperation) -> Bool {
        op.state == .needsAttention || op.state == .pending
    }

    /// Plain words for the confirmation: what the phone stops treating as done.
    static func consequence(of op: SyncOperation) -> String {
        let leg: String = {
            if op.type.hasPrefix("return_") { return "return" }
            if op.type.hasPrefix("delivery_") { return "delivery" }
            return (op.payload["leg"]?.stringValue ?? op.payload["checklist_type"]?.stringValue ?? "").lowercased() == "return" ? "return" : "delivery"
        }()
        switch op.type {
        case "delivery_checklist.complete", "return_checklist.complete", "legacy_customer_checklist.submit":
            return "This phone will show the \(leg) checklist as not completed, the same as Kabba."
        case "delivery_checklist.prepare", "return_checklist.prepare":
            return "This phone will show the saved \(leg) checklist as not saved, the same as Kabba."
        case EffectiveFieldState.driverChecklistType:
            return "This phone will show this driver step (for example On My Way or Arrived) as not recorded, the same as Kabba."
        case "delivery_media.upload", "return_media.upload":
            return "The file will be deleted from this phone. Kabba does not have it."
        case EffectiveFieldState.licenseMediaType:
            return "The license image will be deleted from this phone. Kabba does not have it."
        case EffectiveFieldState.termsAcceptedType, EffectiveFieldState.termsSignedType:
            return "The customer's signature will be deleted from this phone. Kabba does not have it."
        case "fulfillment_inputs.update":
            return "These checklist inputs will not be recorded; this phone will show them as not saved."
        case "manual_dispatch.update_status":
            return "This task status change will not be recorded; this phone will show the task as Kabba has it."
        case NextStopRouteEventOperation.operationType:
            return "This Next Stop answer will not be counted in Driver Efficiency."
        case "queue_line.availability", "queue_line.switch_equipment", "delivery_checklist.reset", "return_checklist.reset":
            return "This yard change will not be recorded; this phone will show the line as Kabba has it."
        default:
            return "Kabba never received this record. Removing it deletes it from this phone."
        }
    }
}
