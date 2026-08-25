//
//  ChecklistContext.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The canonical checklist contract as decoded from
//  GET orders/checklists/context/{order_product}/{leg}. This is the OFFLINE
//  SNAPSHOT of Laravel's truth: identity (execution id), the expected unit, the
//  template + revision, questions in ONE stable id space (template
//  question/answer ids for both legs), requirements and server state.
//  It is never a second business source of truth — it is what the phone was told.
//

import Foundation

enum ChecklistLeg: String, Codable, CaseIterable {
    case delivery
    case `return`

    var isDelivery: Bool { self == .delivery }
    /// Operation type suffix used by the Sync Engine handlers.
    var operationPrefix: String { rawValue + "_checklist" }
}

struct ChecklistContext: Codable, Equatable {

    struct Identity: Codable, Equatable {
        let checklistExecutionId: String
        let cycle: Int
        var status: String
        let leg: ChecklistLeg
        let orderUniqueId: String
        let orderNumber: String
        let orderProductUniqueId: String
        let productName: String

        enum CodingKeys: String, CodingKey {
            case checklistExecutionId = "checklist_execution_id", cycle, status, leg
            case orderUniqueId = "order_unique_id", orderNumber = "order_number"
            case orderProductUniqueId = "order_product_unique_id", productName = "product_name"
        }
    }

    struct Equipment: Codable, Equatable {
        /// hard | soft | selected | none
        let assignment: String
        let equipmentUniqueId: String?
        let equipmentCode: String?
        let equipmentName: String?
        let currentStatus: String?
        let powerSourceType: String?
        let hasDef: String?
        let hourTracking: String?
        let overageRate: String?
        let dieselTankCapacity: String?
        let gasTankCapacity: String?
        let defTankCapacity: String?
        let equipmentHours: String?

        var isAssigned: Bool { assignment == "hard" || assignment == "soft" }
        var hasUnit: Bool { !(equipmentUniqueId ?? "").isEmpty }

        enum CodingKeys: String, CodingKey {
            case assignment
            case equipmentUniqueId = "equipment_unique_id", equipmentCode = "equipment_code", equipmentName = "equipment_name"
            case currentStatus = "current_status", powerSourceType = "power_source_type", hasDef = "has_def"
            case hourTracking = "hour_tracking", overageRate = "overage_rate"
            case dieselTankCapacity = "diesel_tank_capacity", gasTankCapacity = "gas_tank_capacity", defTankCapacity = "def_tank_capacity"
            case equipmentHours = "equipment_hours"
        }
    }

    struct Template: Codable, Equatable {
        let templateId: String?
        let templateName: String?
        let revision: String?
        /// equipment_template | order_rows | none
        let questionSource: String

        enum CodingKeys: String, CodingKey {
            case templateId = "template_id", templateName = "template_name", revision, questionSource = "question_source"
        }
    }

    struct Requirements: Codable, Equatable {
        let signatureRequired: Bool
        let employeeRequired: Bool
        let storeRequired: Bool
        let equipmentRequired: Bool
        let requiredQuestionIds: [String]

        enum CodingKeys: String, CodingKey {
            case signatureRequired = "signature_required", employeeRequired = "employee_required"
            case storeRequired = "store_required", equipmentRequired = "equipment_required"
            case requiredQuestionIds = "required_question_ids"
        }
    }

    struct Category: Codable, Equatable {
        let categoryId: String
        let categoryName: String

        enum CodingKeys: String, CodingKey {
            case categoryId = "category_id", categoryName = "category_name"
        }
    }

    struct Answer: Codable, Equatable {
        /// Template answer unique_id — the ONLY answer id the phone ever sends.
        let answerId: String
        let text: String
        let deliveryText: String
        let returnText: String
        let amount: Double
        let deliveryAmount: Double
        let returnAmount: Double
        let isDamaged: Bool
        let syncTexts: Bool
        let index: Int

        enum CodingKeys: String, CodingKey {
            case answerId = "answer_id", text
            case deliveryText = "delivery_text", returnText = "return_text"
            case amount, deliveryAmount = "delivery_amount", returnAmount = "return_amount"
            case isDamaged = "is_damaged", syncTexts = "sync_texts", index
        }
    }

    struct Question: Codable, Equatable {
        /// Template question unique_id — the ONLY question id the phone ever sends.
        let questionId: String
        let questionName: String
        let text: String
        let deliveryText: String
        let returnText: String
        let category: Category?
        let required: Bool
        let answerType: String
        let index: Int
        let answers: [Answer]
        /// The delivery selection, when viewing the return leg.
        let previousAnswerId: String?
        let previousReturnAnswerId: String?
        /// The answer saved by a prepare operation.
        let preparedAnswerId: String?

        enum CodingKeys: String, CodingKey {
            case questionId = "question_id", questionName = "question_name", text
            case deliveryText = "delivery_text", returnText = "return_text"
            case category, required, answerType = "answer_type", index, answers
            case previousAnswerId = "previous_answer_id", previousReturnAnswerId = "previous_return_answer_id"
            case preparedAnswerId = "prepared_answer_id"
        }
    }

    struct Operational: Codable, Equatable {
        let hourTracking: Bool
        let isProductClean: Bool
        let rentalPrepaidCleaning: Double
        let startHours: Double
        let endHours: Double
        let fuelInitialReading: String
        let fuelFinalReading: String
        let deliveryCleanId: String
        let returnCleanId: String
        let deliveryNotes: String
        let pickupNotes: String
        let deliveryBy: JSONValue?
        let pickupBy: JSONValue?
        let pickupStoreId: JSONValue?

        enum CodingKeys: String, CodingKey {
            case hourTracking = "hour_tracking", isProductClean = "is_product_clean"
            case rentalPrepaidCleaning = "rental_prepaid_cleaning", startHours = "start_hours", endHours = "end_hours"
            case fuelInitialReading = "fuel_initial_reading", fuelFinalReading = "fuel_final_reading"
            case deliveryCleanId = "delivery_clean_id", returnCleanId = "return_clean_id"
            case deliveryNotes = "delivery_notes", pickupNotes = "pickup_notes"
            case deliveryBy = "delivery_by", pickupBy = "pickup_by", pickupStoreId = "pickup_store_id"
        }
    }

    struct ServerState: Codable, Equatable {
        let isDelivered: Bool
        let isReturned: Bool
        let deliveryStatus: String
        let pickupStatus: String
        let deliverySignaturePresent: Bool
        let returnSignaturePresent: Bool
        var executionStatus: String
        let preparedAt: String?
        let completedAt: String?
        let capturedAt: String?
        let canComplete: Bool
        let blockedReason: String?

        enum CodingKeys: String, CodingKey {
            case isDelivered = "is_delivered", isReturned = "is_returned"
            case deliveryStatus = "delivery_status", pickupStatus = "pickup_status"
            case deliverySignaturePresent = "delivery_signature_present", returnSignaturePresent = "return_signature_present"
            case executionStatus = "execution_status", preparedAt = "prepared_at", completedAt = "completed_at", capturedAt = "captured_at"
            case canComplete = "can_complete", blockedReason = "blocked_reason"
        }
    }

    struct Employee: Codable, Equatable {
        let userId: Int
        let uniqueId: String
        let fullName: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id", uniqueId = "unique_id", fullName = "full_name"
        }
    }

    var identity: Identity
    let equipment: Equipment
    let template: Template
    let requirements: Requirements
    let questions: [Question]
    let operational: Operational
    var serverState: ServerState
    let employee: Employee?
    let serverTime: String

    /// When THIS phone cached the snapshot (not part of the wire format).
    var cachedAt: Date?

    enum CodingKeys: String, CodingKey {
        case identity, equipment, template, requirements, questions, operational
        case serverState = "server_state", employee, serverTime = "server_time", cachedAt = "cached_at"
    }

    // MARK: Decoding from the canonical envelope

    /// Decodes `{"success":true,"data":{...}}` (or a bare context object).
    static func decode(envelopeData: Data) throws -> ChecklistContext {
        let decoder = JSONDecoder()
        if let value = JSONValue.parse(envelopeData), let data = value["data"], case .object = data {
            return try decoder.decode(ChecklistContext.self, from: data.serialized())
        }
        return try decoder.decode(ChecklistContext.self, from: envelopeData)
    }

    // MARK: Convenience

    var leg: ChecklistLeg { identity.leg }
    var executionId: String { identity.checklistExecutionId }
    var isCompleted: Bool { serverState.executionStatus == "completed" }
    var isPrepared: Bool { serverState.executionStatus == "prepared" }

    func question(id: String) -> Question? { questions.first { $0.questionId == id } }

    /// Local usability validation — Laravel re-validates the same rules on sync.
    func missingRequiredQuestionIds(answered: [String: String]) -> [String] {
        requirements.requiredQuestionIds.filter { (answered[$0] ?? "").isEmpty }
    }

    /// Every (question, answer) pair must exist in this snapshot.
    func unknownSelections(answered: [String: String]) -> [String] {
        answered.compactMap { questionId, answerId in
            guard let q = question(id: questionId), q.answers.contains(where: { $0.answerId == answerId }) else {
                return "\(questionId):\(answerId)"
            }
            return nil
        }
    }
}
