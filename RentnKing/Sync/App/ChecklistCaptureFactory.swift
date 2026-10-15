//
//  ChecklistCaptureFactory.swift
//  RentnKing — Sync App layer (app-specific glue)
//
//  Bridges the existing checklist UI models (ProductModel / NoteModel /
//  CustomerCheckListModel) and the canonical Sync Core types. This is the ONLY
//  place that knows both worlds, so the screens stay visually unchanged while
//  the data crossing the wire is the Phase 3 contract.
//

import UIKit
import ObjectMapper

enum ChecklistCaptureFactory {

    /// One capture = one order product, its OWN answers, employee, fields and signature.
    static func make(context: ChecklistContext,
                     product: ProductModel,
                     other: NoteModel,
                     isDelivery: Bool,
                     charges: ChecklistLineCharge) -> ChecklistCapture {
        var answers: [String: String] = [:]
        var amounts: [String: String] = [:]
        for question in product.arrQuestions where question.type != "text" && question.type != "fuel" && question.type != "cleaning" {
            guard let questionId = question.unique_id, !questionId.isEmpty else { continue }
            let selected: AnswerCheckListModel? = isDelivery ? question.deliverAnswer : question.returnAnswer
            guard let answerId = selected?.unique_id, !answerId.isEmpty else { continue }
            answers[questionId] = answerId
            let amount = isDelivery ? (selected?.delivery_amt ?? 0) : (selected?.return_amt ?? 0)
            if amount != 0 { amounts[questionId] = String(format: "%.2f", amount) }
        }

        var capture = ChecklistCapture(context: context,
                                       answers: answers,
                                       amounts: amounts,
                                       employeeUserId: Int(isDelivery ? other.dEmplayessId : other.rEmplayessId) ?? 0,
                                       equipmentUniqueId: product.objMachine?.unique_id ?? context.equipment.equipmentUniqueId)
        capture.note = isDelivery ? other.dNote : other.rNote
        capture.storeId = isDelivery ? nil : Int(other.rStoreId)
        if isDelivery {
            capture.startHours = other.startHours == 0 ? "" : "\(other.startHours)"
            capture.fuelInitialReading = other.selectFuleDelivery
            capture.defInitialReading = defReading(product: product, value: other.selectDefDelivery)
            capture.deliveryCleanOption = getCleaning(strId: other.selectCleaningDelivery, isReturn: false)
            capture.deliveryCleanId = other.selectCleaningDelivery
        } else {
            capture.endHours = other.endHours == 0 ? "" : "\(other.endHours)"
            capture.fuelFinalReading = other.selectFuleReturn
            capture.defFinalReading = defReading(product: product, value: other.selectDefReturn)
            capture.fuelTotalCharge = charges.fuelString
            capture.totalCharge = charges.totalString
            capture.returnCleanOption = getCleaning(strId: other.selectCleaningReturn, isReturn: true)
            capture.returnCleanId = other.selectCleaningReturn
            capture.totalCleanCharge = charges.cleaningString
        }
        return capture
    }

    /// A DEF reading is sent only for a product whose checklist shows the DEF row.
    private static func defReading(product: ProductModel, value: String) -> String {
        product.arrQuestions.contains(where: { $0.isDEFRow }) ? value : ""
    }

    /// The pre-Phase-3 form-field shape for ONE product with ITS OWN otherData (no cross product).
    /// Used only when no canonical context exists for the product.
    static func legacyItem(product: ProductModel,
                           other: NoteModel,
                           isDelivery: Bool,
                           orderUniqueId: String,
                           charges: ChecklistLineCharge) -> [String: Any] {
        var arrData: [[String: Any]] = []
        for question in product.arrQuestions where question.type != "text" && question.type != "fuel" && question.type != "cleaning" {
            arrData.append([
                "question_unique_id": question.unique_id ?? "",
                "answer_unique_id": isDelivery ? (question.deliverAnswer?.unique_id ?? "") : (question.returnAnswer?.unique_id ?? ""),
            ])
        }
        let checklistJSON = (try? JSONSerialization.data(withJSONObject: arrData, options: [])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let signature = (isDelivery ? other.dSignature : other.rSignature)?.jpegData(compressionQuality: 0.7)?.base64EncodedString() ?? ""

        return [
            "order_product_unique_id": product.unique_id ?? "",
            "order_unique_id": orderUniqueId,
            "equipment_unique_id": product.objMachine?.unique_id ?? "",
            "checklist[]": checklistJSON,
            "delivery_clean_option": isDelivery ? getCleaning(strId: other.selectCleaningDelivery, isReturn: false) : "",
            "delivery_clean_id": isDelivery ? other.selectCleaningDelivery : "",
            "return_clean_option": isDelivery ? "" : getCleaning(strId: other.selectCleaningReturn, isReturn: true),
            "return_clean_id": isDelivery ? "" : other.selectCleaningReturn,
            "total_clean_charge": isDelivery ? "" : charges.cleaningString,
            "start_hours": isDelivery ? "\(other.startHours)" : "",
            "end_hours": isDelivery ? "" : "\(other.endHours)",
            "user_id": isDelivery ? other.dEmplayessId : other.rEmplayessId,
            "note": isDelivery ? other.dNote : other.rNote,
            "total_charge": isDelivery ? "" : charges.totalString,
            "store_id": isDelivery ? "" : other.rStoreId,
            "fuel_initial_reading": other.selectFuleDelivery,
            "fuel_final_reading": other.selectFuleReturn,
            "fuel_total_charge": isDelivery ? "" : charges.fuelString,
            "def_initial_reading": isDelivery ? defReading(product: product, value: other.selectDefDelivery) : "",
            "def_final_reading": isDelivery ? "" : defReading(product: product, value: other.selectDefReturn),
            "dSignature": isDelivery ? signature : "",
            "rSignature": isDelivery ? "" : signature,
            "type": isDelivery ? "Delivery" : "Return",
            "version": AppReleaseInfo.versionDisplay,
        ]
    }

    /// Context questions → the UI's question model (canonical ids), keeping any selection the
    /// employee already made for the same question id.
    static func questionModels(from context: ChecklistContext, isDelivery: Bool, preserving existing: [String: CustomerCheckListModel]) -> [CustomerCheckListModel] {
        context.questions.map { question -> CustomerCheckListModel in
            var json: [String: Any] = [
                "id": question.index,
                "unique_id": question.questionId,
                "question_name": question.questionName,
                "question_delivery_text": question.deliveryText,
                "question_return_text": question.returnText,
                "answers": question.answers.map { answer -> [String: Any] in
                    [
                        "id": answer.index,
                        "unique_id": answer.answerId,
                        "answer_delivery_text": answer.deliveryText,
                        "answer_return_text": answer.returnText,
                        "delivery_amt": answer.deliveryAmount,
                        "return_amt": answer.returnAmount,
                    ]
                },
            ]
            // Return leg: show what was chosen at delivery.
            if !isDelivery, let previous = question.previousAnswerId, let answer = question.answers.first(where: { $0.answerId == previous }) {
                json["deliverAnswer"] = ["id": answer.index, "unique_id": answer.answerId, "answer_delivery_text": answer.deliveryText,
                                         "answer_return_text": answer.returnText, "delivery_amt": answer.deliveryAmount, "return_amt": answer.returnAmount]
            }
            var model = CustomerCheckListModel(map: Map(mappingType: .fromJSON, JSON: json))!
            if let kept = existing[question.questionId] {
                if isDelivery, let picked = kept.deliverAnswer, question.answers.contains(where: { $0.answerId == picked.unique_id }) { model.deliverAnswer = picked }
                if !isDelivery, let picked = kept.returnAnswer, question.answers.contains(where: { $0.answerId == picked.unique_id }) { model.returnAnswer = picked }
            } else if isDelivery, let prepared = question.preparedAnswerId, let answer = model.arrAnswer.first(where: { $0.unique_id == prepared }) {
                model.deliverAnswer = answer
            }
            return model
        }
    }

    /// A minimal MachineModel for a unit the office assigned that the local fleet cache does not hold.
    static func machine(from context: ChecklistContext) -> MachineModel? {
        let e = context.equipment
        guard let uid = e.equipmentUniqueId else { return nil }
        let json: [String: Any] = [
            "unique_id": uid,
            "equipment_id": e.equipmentCode ?? "",
            "equipment_name": e.equipmentName ?? "",
            "current_status": e.currentStatus ?? "",
            "power_source_type": e.powerSourceType ?? "",
            "has_def": e.hasDef ?? "",
            "is_tracked": e.hourTracking ?? "",
            "overage_rate": e.overageRate ?? "",
            "diesel_tank_capacity": e.dieselTankCapacity ?? "",
            "gas_tank_capacity": e.gasTankCapacity ?? "",
            "def_tank_capacity": e.defTankCapacity ?? "",
            "equipment_hours": e.equipmentHours ?? "",
        ]
        return MachineModel(map: Map(mappingType: .fromJSON, JSON: json))
    }
}

/// What the preview screen decided to submit for one product.
enum ChecklistSubmissionPlan {
    case canonical(ChecklistCapture, signature: Data?)
    case legacy([String: Any])

    struct Outcome {
        var queued: Int = 0
        var failed: Int = 0
        var firstOperationId: String?
        var usedEngine: Bool = false
    }

    /// Durably enqueues every plan. Without the engine (bootstrap failed) the legacy MMKV queue is
    /// used — still one item per product, never a cross product.
    static func enqueueAll(_ plans: [ChecklistSubmissionPlan]) -> Outcome {
        var outcome = Outcome()
        guard let engine = KabbaSync.engine else {
            let items: [[String: Any]] = plans.compactMap {
                if case .legacy(let item) = $0 { return item }
                if case .canonical(let capture, let signature) = $0 {
                    return ChecklistCaptureFactory.legacyFallback(capture, signature: signature)
                }
                return nil
            }
            appendChecklistData(items)
            outcome.queued = items.count
            return outcome
        }

        outcome.usedEngine = true
        for plan in plans {
            do {
                let operation: SyncOperation
                switch plan {
                case .canonical(let capture, let signature):
                    operation = try ChecklistOperationBuilder.enqueueCompletion(capture, signatureJPEG: signature, into: engine)
                case .legacy(let item):
                    switch LegacyChecklistQueueMigration.convert(item) {
                    case .success(let converted): operation = try LegacyChecklistQueueMigration.enqueue(converted, into: engine)
                    case .failure(let problem): throw problem
                    }
                }
                outcome.queued += 1
                if outcome.firstOperationId == nil { outcome.firstOperationId = operation.id }
            } catch {
                outcome.failed += 1
                debugPrint("Checklist submission could not be queued: \(error)")
            }
        }
        return outcome
    }
}

extension ChecklistCaptureFactory {
    /// Engine unavailable: express a canonical capture in the legacy shape (ids are template ids
    /// for delivery — the legacy endpoint's own id space; for return the server context ids are
    /// template ids too, which the legacy return endpoint does NOT accept, so return falls back
    /// only when there was never a context — this path is delivery-safe, return best-effort).
    static func legacyFallback(_ capture: ChecklistCapture, signature: Data?) -> [String: Any] {
        let arrData = capture.answers.keys.sorted().map { ["question_unique_id": $0, "answer_unique_id": capture.answers[$0] ?? ""] }
        let checklistJSON = (try? JSONSerialization.data(withJSONObject: arrData, options: [])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let isDelivery = capture.leg.isDelivery
        return [
            "order_product_unique_id": capture.context.identity.orderProductUniqueId,
            "order_unique_id": capture.context.identity.orderUniqueId,
            "equipment_unique_id": capture.equipmentUniqueId ?? "",
            "checklist[]": checklistJSON,
            "delivery_clean_option": capture.deliveryCleanOption, "delivery_clean_id": capture.deliveryCleanId,
            "return_clean_option": capture.returnCleanOption, "return_clean_id": capture.returnCleanId,
            "total_clean_charge": capture.totalCleanCharge,
            "start_hours": capture.startHours, "end_hours": capture.endHours,
            "user_id": "\(capture.employeeUserId)", "note": capture.note,
            "total_charge": capture.totalCharge, "store_id": capture.storeId.map { "\($0)" } ?? "",
            "fuel_initial_reading": capture.fuelInitialReading, "fuel_final_reading": capture.fuelFinalReading,
            "fuel_total_charge": capture.fuelTotalCharge,
            "def_initial_reading": capture.defInitialReading, "def_final_reading": capture.defFinalReading,
            "dSignature": isDelivery ? (signature?.base64EncodedString() ?? "") : "",
            "rSignature": isDelivery ? "" : (signature?.base64EncodedString() ?? ""),
            "type": isDelivery ? "Delivery" : "Return",
            "version": AppReleaseInfo.versionDisplay,
        ]
    }
}

/// Each order product's OWN Return charges, from the preview's question rows.
///
/// The rules are the checklist's existing ones — hours overage (ChecklistHoursMath × the
/// unit's overage rate), cleaning (price × the line's prepaid-cleaning units, prepaid cleaning
/// covers all but Extreme), damage/answer amounts (return − delivery when positive) — plus
/// fuel from FuelChargeCalculator (primary fuel + DEF). What changed in 1.0.26 is the SCOPE:
/// every amount belongs to the product whose rows produced it; nothing is shared across lines.
enum ChecklistLineCharges {

    struct Result {
        /// The products with their hours rows' display totals filled in.
        var products: [ProductModel]
        /// order product unique_id → that line's charges.
        var charges: [String: ChecklistLineCharge]
    }

    /// - Parameters:
    ///   - completedReport: both legs are already complete — the server's own per-line
    ///     `total_charge` is shown instead of recomputing.
    ///   - cleaningPrice: the System Configuration cleaning price for a return cleaning id.
    static func compute(products: [ProductModel], completedReport: Bool, fuelPrices: FuelPrices,
                        cleaningPrice: (Int) -> Float) -> Result {
        var result = Result(products: products, charges: [:])
        for i in result.products.indices {
            var objProduct = result.products[i]
            var line = ChecklistLineCharge()

            if completedReport {
                line.total = Float(objProduct.total_charge)
            } else {
                for index in objProduct.arrQuestions.indices {
                    var objQuestion = objProduct.arrQuestions[index]
                    if objQuestion.type == "text" {
                        // Total math (ChecklistHoursMath): never traps on ±inf/NaN meter values.
                        var totalHours = ChecklistHoursMath.overageHours(start: Float(objQuestion.startHours),
                                                                         end: Float(objQuestion.endHours))
                        if objQuestion.startHours == 0.0 { totalHours = 0 }
                        objQuestion.total = 0
                        if totalHours > 0 { objQuestion.total = Float(totalHours) }

                        var additionalHours = Float(ChecklistHoursMath.additionalHours(total: totalHours,
                                                                                       allocated: objProduct.allocated_hours ?? 0))
                        objQuestion.additinal = 0
                        if additionalHours > 0 { objQuestion.additinal = Int(additionalHours) } else { additionalHours = 0 }

                        line.total = line.total + additionalHours * Float(objQuestion.hour_rate)
                        objQuestion.total_cost = additionalHours * Float(objQuestion.hour_rate)
                        objProduct.arrQuestions[index] = objQuestion
                    } else if objQuestion.type == "cleaning" {
                        let selected = Int(objQuestion.selectCleaningReturn ?? "") ?? 0
                        if objProduct.is_product_clean == true && objProduct.rental_prepaid_cleaning != 0 && selected != 0 {
                            var price = cleaningPrice(selected)
                            let selectedOptions = objProduct.objProductData?.arrProductSelectdOptions ?? []
                            if selectedOptions.contains("rental_prepaid_cleaning") && selected != 5 { price = 0 }
                            let cleaningCharge = (objProduct.rental_prepaid_cleaning ?? 0) * price
                            line.cleaning = line.cleaning + cleaningCharge
                            line.total = line.total + cleaningCharge
                        }
                    } else if objQuestion.type == "fuel" {
                        // Each fuel row prices ITS fluid — primary fuel and DEF are summed, never
                        // one replacing the other.
                        if let fuel = FuelChecklistRows.line(for: objQuestion, product: objProduct, prices: fuelPrices) {
                            line.fuel = line.fuel + fuel.amount
                            line.total = line.total + Float(FuelChargeCalculator.double(fuel.amount))
                        }
                    } else if objQuestion.deliverAnswer != nil && objQuestion.returnAnswer != nil {
                        let amount = Float(objQuestion.returnAnswer.return_amt) - Float(objQuestion.deliverAnswer.delivery_amt)
                        if amount > 0 { line.total = line.total + amount }
                    }
                }
            }

            result.products[i] = objProduct
            if let uid = objProduct.unique_id, !uid.isEmpty { result.charges[uid] = line }
        }
        return result
    }
}
