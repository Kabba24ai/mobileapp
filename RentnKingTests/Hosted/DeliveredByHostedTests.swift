//
//  DeliveredByHostedTests.swift
//  RentnKingHostedTests — Delivered By / Returned By on the customer checklist (2026-11-23)
//
//  Rent 'n King order #5657: a combined delivery checklist for a cab skid steer (driver Mike, #44)
//  and a grapple with no driver. The combined Delivered By took the grapple's blank, Preview
//  refused, and opened from Dispatch the picker did nothing. These drive the real screen code:
//  the defaults (ChecklistEmployeeDefault), the picker's own completion, Combine on/off, and the
//  rows Preview hands on for submission.
//

import XCTest
import UIKit
import ObjectMapper
@testable import RentnKing

final class DeliveredByHostedTests: XCTestCase {

    private var savedUser: User?
    private var savedBaseURL: String?
    private var offered: [String] = []
    private var pickIndex: Int?

    override func setUp() {
        super.setUp()
        savedUser = UserDefaults.standard.user
        savedBaseURL = UserDefaults.standard.baseURL
        UserDefaults.standard.baseURL = "https://delivered-by.invalid/api/admin/v1/"
        UserDefaults.standard.user = nil
        offered = []
        pickIndex = nil
    }

    override func tearDown() {
        UserDefaults.standard.user = savedUser
        UserDefaults.standard.baseURL = savedBaseURL
        super.tearDown()
    }

    // MARK: - Fixtures

    private func employee(_ id: Int, _ name: String) -> EmployeesModel {
        EmployeesModel(map: Map(mappingType: .fromJSON, JSON: ["id": id, "unique_id": "PER-\(id)", "full_name": name]))!
    }

    private var staff: [EmployeesModel] { [employee(21, "Amber S."), employee(44, "Mike H."), employee(7, "Bob T.")] }

    private func line(_ uid: String, deliveryBy: Int, pickupBy: Int = 0, answer: String) -> ProductModel {
        var product = ProductModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        product.unique_id = uid
        product.product_name = uid
        product.delivery_emp = deliveryBy
        product.returned_emp = pickupBy
        product.objMachine = MachineModel(map: Map(mappingType: .fromJSON, JSON: ["id": 1, "unique_id": "EQP-\(uid)"]))
        var question = CustomerCheckListModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        question.type = "choice"
        question.unique_id = "CAQST-\(uid)"
        question.deliverAnswer = AnswerCheckListModel(map: Map(mappingType: .fromJSON, JSON: ["unique_id": answer]))
        product.arrQuestions = [question]
        return product
    }

    /// The screen exactly as setupStaticData / setTheView leave it for #5657 (08:36): one row per
    /// line from `delivery_by` (the grapple's is 0), the combined row copied from the LAST line.
    private func screen5657(combined: Bool, delivery: Bool = true, signedIn: String? = nil) -> (CheckListViewController, UITableView, UILabel) {
        let screen = CheckListViewController()
        let table = UITableView()
        let total = UILabel()                          // outlets are weak: the caller keeps them alive
        screen.tblView = table
        screen.lblTotalCharge = total
        screen.isDeliveryType = delivery
        screen.fromCheckListScreen = true              // opened from Dispatch, where the picker used to do nothing
        screen.isCombineChecklist = combined
        var order = OrdersModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        order.arrProduct = [line("ORD-SCH-SKID", deliveryBy: 44, pickupBy: 44, answer: "CAANS-SKID-OK"),
                            line("ORD-SCH-GRAPPLE", deliveryBy: 0, answer: "CAANS-GRAPPLE-OK")]
        screen.objOrderData = order
        screen.arrOtherData = order.arrProduct.map { product in
            let note = NoteModel()
            note.dEmplayessId = "\(product.delivery_emp)"
            note.rEmplayessId = "\(product.returned_emp)"
            return note
        }
        screen.combinedOtherData = screen.arrOtherData.last!.batchCopy()
        screen.arrEmployesList = staff
        if let signedIn = signedIn {
            let user = User()
            user.id = signedIn
            user.full_name = "Signed In"
            UserDefaults.standard.user = user
        }
        screen.presentEmployeeChoices = { [unowned self] _, names, _, picked in
            self.offered = names
            if let index = self.pickIndex { picked(index, names[index]) }
        }
        return (screen, table, total)
    }

    private func tap(_ screen: CheckListViewController, section: Int) {
        let button = UIButton()
        button.tag = section
        screen.btnSelectEmployessClicked(button)
    }

    // MARK: - Order #5657

    func testOrder5657CombinedNamesTheSkidSteersDriverAndPreviewNoLongerRefuses() {
        let (screen, table, total) = screen5657(combined: true)
        XCTAssertEqual(screen.combinedOtherData.dEmplayessId, "0", "the defect: the combined row copied the grapple's blank")

        screen.applyEmployeeDefaults()

        XCTAssertEqual(screen.combinedOtherData.dEmplayessId, "44")
        XCTAssertEqual(screen.combinedOtherData.dEmplayess, "Mike H.")
        XCTAssertFalse(screen.combinedOtherData.dEmplayessChosen, "a default, not a pick")
        let batch = screen.batchOtherData(screen.arrOtherData)
        XCTAssertEqual(batch.map(\.dEmplayessId), ["44", "44"], "every line submits the one Delivered By")
        XCTAssertEqual(batch.compactMap { Int($0.dEmplayessId) }, [44, 44], "as the numeric users.id")
        XCTAssertTrue(screen.checkOtherData(arrOtherData: batch), "Preview's Delivered By check passes")
        withExtendedLifetime((table, total)) {}
    }

    func testThePickerOpensFromDispatchAndAPickReachesEveryLineWithoutTouchingAnswers() {
        let (screen, table, total) = screen5657(combined: true)
        screen.applyEmployeeDefaults()
        pickIndex = 0                                  // Amber, who actually handed the equipment over

        tap(screen, section: 1)                        // the combined field sits under the last line

        XCTAssertEqual(offered, ["Amber S.", "Mike H.", "Bob T."], "every active employee is offered")
        XCTAssertEqual(screen.combinedOtherData.dEmplayessId, "21")
        XCTAssertTrue(screen.combinedOtherData.dEmplayessChosen)
        XCTAssertEqual(screen.arrOtherData.map(\.dEmplayessId), ["21", "21"], "the pick is kept on every line")
        XCTAssertEqual(screen.batchOtherData(screen.arrOtherData).map(\.dEmplayessId), ["21", "21"])
        XCTAssertEqual(screen.objOrderData.arrProduct.map { $0.arrQuestions.first?.deliverAnswer?.unique_id },
                       ["CAANS-SKID-OK", "CAANS-GRAPPLE-OK"], "answers stay on their own equipment, untouched")
        XCTAssertEqual(screen.objOrderData.arrProduct.map(\.delivery_emp), [44, 0],
                       "the dispatch assignment the screen read is not changed by a pick")
        withExtendedLifetime((table, total)) {}
    }

    func testACombinedPickSurvivesTurningCombineOff() {
        let (screen, table, total) = screen5657(combined: true)
        screen.applyEmployeeDefaults()
        pickIndex = 2
        tap(screen, section: 1)                        // Bob for the whole checklist

        screen.isCombineChecklist = false
        screen.applyEmployeeDefaults()

        XCTAssertEqual(screen.arrOtherData.map(\.dEmplayessId), ["7", "7"])
        XCTAssertEqual(screen.arrOtherData.map(\.dEmplayess), ["Bob T.", "Bob T."])
        withExtendedLifetime((table, total)) {}
    }

    func testSeparateChecklistsInheritAPickFromTheScreenBefore() {
        let (screen, table, total) = screen5657(combined: false)
        screen.applyEmployeeDefaults()
        XCTAssertEqual(screen.arrOtherData.map(\.dEmplayessId), ["44", "44"], "the grapple takes the skid steer's driver")

        pickIndex = 0
        tap(screen, section: 0)                        // Amber picked on the skid steer's screen

        XCTAssertEqual(screen.arrOtherData.map(\.dEmplayessId), ["21", "21"], "the grapple's screen follows the earlier pick")
        XCTAssertEqual(screen.arrOtherData.map(\.dEmplayessChosen), [true, false])
        XCTAssertEqual(screen.combinedOtherData.dEmplayessId, "21", "and so would the combined field")

        pickIndex = 2
        tap(screen, section: 1)                        // then Bob picked on the grapple's own screen
        XCTAssertEqual(screen.arrOtherData.map(\.dEmplayessId), ["21", "7"], "each line keeps its own pick")
        withExtendedLifetime((table, total)) {}
    }

    func testAPickIsNotReplacedWhenTheEmployeeListRefreshes() {
        let (screen, table, total) = screen5657(combined: true)
        screen.applyEmployeeDefaults()
        pickIndex = 2
        tap(screen, section: 1)

        screen.arrEmployesList = [employee(44, "Mike H."), employee(7, "Bob Tanner"), employee(21, "Amber S.")]
        screen.applyEmployeeDefaults()                 // what the list-refresh callback runs

        XCTAssertEqual(screen.combinedOtherData.dEmplayessId, "7")
        XCTAssertEqual(screen.combinedOtherData.dEmplayess, "Bob Tanner", "only the name follows the refreshed list")
        withExtendedLifetime((table, total)) {}
    }

    // MARK: - Other paths

    func testWithNoDriverAnywhereTheSignedInEmployeeIsSuggested() {
        let (screen, table, total) = screen5657(combined: true, signedIn: "21")
        screen.objOrderData.arrProduct[0].delivery_emp = 0
        screen.arrOtherData[0].dEmplayessId = "0"
        screen.applyEmployeeDefaults()
        XCTAssertEqual(screen.combinedOtherData.dEmplayessId, "21")
        XCTAssertEqual(screen.combinedOtherData.dEmplayess, "Amber S.")
        withExtendedLifetime((table, total)) {}
    }

    func testReturnedByFollowsThePickupDriver() {
        let (screen, table, total) = screen5657(combined: true, delivery: false)
        screen.applyEmployeeDefaults()
        XCTAssertEqual(screen.combinedOtherData.rEmplayessId, "44", "the skid steer's pickup driver, though the grapple has none")
        XCTAssertEqual(screen.batchOtherData(screen.arrOtherData).map(\.rEmplayessId), ["44", "44"])
        withExtendedLifetime((table, total)) {}
    }

    func testOfflineWithoutAnEmployeeListTheDriverIsStillNamed() {
        let (screen, table, total) = screen5657(combined: true)
        screen.arrEmployesList = []                    // never fetched on this phone, and offline
        screen.applyEmployeeDefaults()
        XCTAssertEqual(screen.combinedOtherData.dEmplayessId, "44")
        XCTAssertEqual(screen.combinedOtherData.dEmplayess, "Employee #44", "who will be submitted is still shown")
        withExtendedLifetime((table, total)) {}
    }

    func testASingleLineKeepsItsDriver() {
        let (screen, table, total) = screen5657(combined: false)
        screen.objOrderData.arrProduct.removeLast()
        screen.arrOtherData.removeLast()
        screen.applyEmployeeDefaults()
        XCTAssertEqual(screen.arrOtherData.map(\.dEmplayessId), ["44"])
        XCTAssertEqual(screen.arrOtherData.map(\.dEmplayess), ["Mike H."])
        withExtendedLifetime((table, total)) {}
    }

    // MARK: - Drafts

    func testAPickSurvivesTheDraftAndOldDraftsKeepWhatTheyShowed() {
        let note = NoteModel()
        note.dEmplayessId = "21"
        note.dEmplayess = "Amber S."
        note.dEmplayessChosen = true
        XCTAssertTrue(NoteModel.fromDict(note.toDict()).dEmplayessChosen)
        XCTAssertTrue(note.batchCopy().dEmplayessChosen, "Preview's copies keep it too")

        var legacy = note.toDict()
        legacy.removeValue(forKey: "dEmplayessChosen")  // a draft saved by 1.0.30
        XCTAssertTrue(NoteModel.fromDict(legacy).dEmplayessChosen, "an employee an old draft named stays as it was shown")
        legacy["dEmplayessId"] = "0"
        XCTAssertFalse(NoteModel.fromDict(legacy).dEmplayessChosen, "an old draft's blank gets a default")
    }
}
