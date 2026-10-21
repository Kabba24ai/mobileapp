//
//  ChecklistOwnLineHostedTests.swift
//  RentnKingHostedTests — MOBILE-QUALITY-01 item 03: every equipment checklist stays its
//  own. A checklist context lands only on the line it was loaded for; when that line is no
//  longer on screen (the order was rebuilt from another copy meanwhile) nothing is applied —
//  it used to fall back to whatever line sat at the old position and hand that line another
//  machine's questions and unit.
//

import XCTest
import UIKit
import ObjectMapper
@testable import RentnKing

final class ChecklistOwnLineHostedTests: XCTestCase {

    private var savedBaseURL: String?

    override func setUp() {
        super.setUp()
        savedBaseURL = UserDefaults.standard.baseURL
        UserDefaults.standard.baseURL = "https://checklist-own-line.invalid/api/admin/v1/"
    }

    override func tearDown() {
        UserDefaults.standard.baseURL = savedBaseURL
        super.tearDown()
    }

    private func line(_ uid: String, unit: String) -> ProductModel {
        var product = ProductModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        product.unique_id = uid
        product.product_name = uid
        product.objMachine = MachineModel(map: Map(mappingType: .fromJSON, JSON: ["id": 1, "unique_id": unit]))
        var question = CustomerCheckListModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        question.type = "choice"
        question.unique_id = "CAQST-OWN-\(uid)"
        product.arrQuestions = [question]
        return product
    }

    /// A Return context for ANOTHER line (its own unit and question).
    private func context(for product: String, unit: String, question: String) throws -> ChecklistContext {
        let json: [String: Any] = [
            "identity": ["checklist_execution_id": "ORD-CHK-\(product)", "cycle": 1, "status": "open", "leg": "return",
                         "order_unique_id": "ORD-OWN", "order_number": "5093", "order_product_unique_id": product, "product_name": "Compactor"],
            "equipment": ["assignment": "hard", "equipment_unique_id": unit, "equipment_code": "EQP-9", "equipment_name": "56\" Single Drum Compactor",
                          "current_status": "rented", "power_source_type": "diesel", "has_def": "No", "hour_tracking": "Yes"],
            "template": ["template_id": "CATQS-9", "template_name": "Compactor", "revision": "0123456789abcdef", "question_source": "order_rows"],
            "requirements": ["signature_required": true, "employee_required": true, "store_required": true, "equipment_required": false,
                             "required_question_ids": [question]],
            "questions": [
                ["question_id": question, "question_name": "Drum", "text": "Drum damage?", "delivery_text": "Drum damage?", "return_text": "Drum damage?",
                 "category": NSNull(), "required": true, "answer_type": "single_choice", "index": 1,
                 "answers": [["answer_id": "CAANS-DRUM-OK", "text": "No", "delivery_text": "No", "return_text": "No", "amount": 0, "delivery_amount": 0,
                              "return_amount": 0, "is_damaged": false, "sync_texts": false, "index": 1]],
                 "previous_answer_id": NSNull(), "previous_return_answer_id": NSNull(), "prepared_answer_id": NSNull()],
            ],
            "operational": ["hour_tracking": true, "is_product_clean": false, "rental_prepaid_cleaning": 0, "start_hours": 0, "end_hours": 0,
                            "fuel_initial_reading": "", "fuel_final_reading": "", "delivery_clean_id": "", "return_clean_id": "", "delivery_notes": "", "pickup_notes": "",
                            "delivery_by": NSNull(), "pickup_by": NSNull(), "pickup_store_id": NSNull()],
            "server_state": ["is_delivered": true, "is_returned": false, "delivery_status": "Completed", "pickup_status": "Pending",
                             "delivery_signature_present": true, "return_signature_present": false, "execution_status": "open",
                             "prepared_at": NSNull(), "completed_at": NSNull(), "captured_at": NSNull(), "can_complete": true, "blocked_reason": NSNull()],
            "employee": ["user_id": 7, "unique_id": "PER-0007", "full_name": "Field Employee"],
            "server_time": "2026-10-05T12:00:00+00:00",
        ]
        let envelope = try JSONSerialization.data(withJSONObject: ["success": true, "data": json])
        return try ChecklistContext.decode(envelopeData: envelope)
    }

    func testAContextForALineNoLongerOnScreenIsNeverAppliedToAnotherLine() throws {
        let screen = CheckListViewController()
        let table = UITableView()                      // outlets are weak: keep them alive
        let total = UILabel()
        screen.tblView = table
        screen.lblTotalCharge = total
        screen.isDeliveryType = false
        var order = OrdersModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        // The rebuilt order: the compactor's line is gone; the trailer now sits where it was.
        order.arrProduct = [line("ORD-SCH-TRAILER", unit: "EQP-TRAILER")]
        screen.objOrderData = order
        let note = NoteModel()
        screen.arrOtherData = [note]

        let compactor = try context(for: "ORD-SCH-COMPACTOR", unit: "EQP-COMPACTOR", question: "CAQST-DRUM")
        screen.applyChecklistContext(compactor, toProductWith: "ORD-SCH-COMPACTOR")
        // Applying a unit reloads the table 0.5 s later: let that finish while the outlets are alive.
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))

        let trailer = screen.objOrderData.arrProduct[0]
        XCTAssertEqual(trailer.objMachine?.unique_id, "EQP-TRAILER", "the trailer keeps its own unit")
        XCTAssertEqual(trailer.arrQuestions.compactMap(\.unique_id), ["CAQST-OWN-ORD-SCH-TRAILER"],
                       "the trailer never receives the compactor's questions")
        withExtendedLifetime((table, total)) {}
    }

    func testAContextStillLandsOnItsOwnLine() throws {
        let screen = CheckListViewController()
        let table = UITableView()
        let total = UILabel()                          // outlets are weak: keep them alive
        screen.tblView = table
        screen.lblTotalCharge = total
        screen.isDeliveryType = false
        var order = OrdersModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        order.arrProduct = [line("ORD-SCH-TRAILER", unit: "EQP-TRAILER"), line("ORD-SCH-COMPACTOR", unit: "EQP-COMPACTOR")]
        screen.objOrderData = order
        screen.arrOtherData = [NoteModel(), NoteModel()]

        screen.applyChecklistContext(try context(for: "ORD-SCH-COMPACTOR", unit: "EQP-COMPACTOR", question: "CAQST-DRUM"),
                                     toProductWith: "ORD-SCH-COMPACTOR")
        // Applying a unit reloads the table 0.5 s later: let that finish while the outlets are alive.
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))

        XCTAssertTrue(screen.objOrderData.arrProduct[1].arrQuestions.compactMap(\.unique_id).contains("CAQST-DRUM"))
        XCTAssertEqual(screen.objOrderData.arrProduct[0].arrQuestions.compactMap(\.unique_id), ["CAQST-OWN-ORD-SCH-TRAILER"])
        withExtendedLifetime((table, total)) {}
    }
}
