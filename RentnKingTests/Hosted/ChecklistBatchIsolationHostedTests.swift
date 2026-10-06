import XCTest
import UIKit
import ObjectMapper
@testable import RentnKing

final class ChecklistBatchIsolationHostedTests: XCTestCase {
    private final class PreviewWithoutNetwork: CheckListUpdateViewController {
        override func viewDidLoad() {}
    }
    private var savedBaseURL: String?
    private var orderUid = ""

    override func setUp() {
        super.setUp()
        savedBaseURL = UserDefaults.standard.baseURL
        UserDefaults.standard.baseURL = "https://checklist-batch.invalid/api/admin/v1/"
        orderUid = "BATCH-\(UUID().uuidString)"
    }

    override func tearDown() {
        for delivery in [false, true] {
            clearPendingCheckList(orderUniqueId: orderUid, isDelivery: delivery)
            let type = delivery ? "Delivery" : "Return"
            SDKUserDefault.remove(for: "\(kFileStorageName.kCheckListOrderDetailsData.rawValue)_\(type)_\(orderUid)")
            SDKUserDefault.remove(for: "\(kFileStorageName.kCheckListOtherData.rawValue)_\(type)_\(orderUid)")
        }
        UserDefaults.standard.baseURL = savedBaseURL
        super.tearDown()
    }

    private func product(_ index: Int, answered: Bool, delivery: Bool) -> ProductModel {
        var product = ProductModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        product.id = index + 1
        product.unique_id = "P\(index)"
        var question = CustomerCheckListModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        question.type = "choice"
        if answered {
            let answer = AnswerCheckListModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
            if delivery { question.deliverAnswer = answer } else { question.returnAnswer = answer }
        }
        product.arrQuestions = [question]
        return product
    }

    private func order(_ count: Int, delivery: Bool) -> OrdersModel {
        var order = OrdersModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        order.arrProduct = (0..<3).map { product($0, answered: $0 < count, delivery: delivery) }
        return order
    }

    private func notes() -> [NoteModel] {
        (0..<3).map { index in
            let note = NoteModel()
            note.productID = index + 1
            note.dEmplayessId = "D\(index)"
            note.rEmplayessId = "R\(index)"
            return note
        }
    }

    func testScopeIsIndependentOfCombineAndKeepsArraysAligned() {
        for delivery in [false, true] {
            for combine in [false, true] {
                for count in 0...3 {
                    let screen = CheckListViewController()
                    screen.isDeliveryType = delivery
                    screen.isCombineChecklist = combine
                    var scoped: OrdersModel? = order(count, delivery: delivery)
                    var other = notes()
                    screen.removeBlankProducts(objOrderData: &scoped, arrOtherData: &other)
                    XCTAssertEqual(scoped?.arrProduct.compactMap(\.unique_id), (0..<count).map { "P\($0)" })
                    XCTAssertEqual(other.map(\.productID), (0..<count).map { $0 + 1 })
                }
            }
        }
    }

    func testRemovingFirstAndMiddleBlankItemsKeepsTheirOwnNotes() {
        let screen = CheckListViewController()
        screen.isDeliveryType = true
        var scoped: OrdersModel? = order(0, delivery: true)
        scoped?.arrProduct[2] = product(2, answered: true, delivery: true)
        var other = notes()
        screen.removeBlankProducts(objOrderData: &scoped, arrOtherData: &other)
        XCTAssertEqual(scoped?.arrProduct.compactMap(\.unique_id), ["P2"])
        XCTAssertEqual(other.map(\.productID), [3])
    }

    func testPrefilledOperationalDefaultsDoNotSelectAnUntouchedSibling() {
        for delivery in [false, true] {
            let screen = CheckListViewController()
            screen.isDeliveryType = delivery
            var p = product(0, answered: false, delivery: delivery)
            p.start_hours = 100; p.end_hours = 110
            p.fuel_initial_reading = "8"; p.fuel_final_reading = "7"
            var hours = CustomerCheckListModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
            hours.type = "text"; hours.startHours = 100; hours.endHours = 110
            var fuel = CustomerCheckListModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
            fuel.type = "fuel"; fuel.selectFuleDelivery = "8"; fuel.selectFuleReturn = "7"
            p.arrQuestions += [hours, fuel]
            let note = NoteModel()
            XCTAssertFalse(screen.hasChecklistWork(product: p, other: note))
            if delivery { note.deliveryInputEntered = true } else { note.returnInputEntered = true }
            XCTAssertTrue(screen.hasChecklistWork(product: p, other: note), "an explicit edit to a default still counts")
            let restored = NoteModel.fromDict(note.toDict())
            XCTAssertTrue(screen.hasChecklistWork(product: p, other: restored), "scope survives closing/reopening the draft")
        }
    }

    func testPartiallyAnsweredItemRemainsInValidation() {
        let screen = CheckListViewController()
        screen.isDeliveryType = true
        var scoped: OrdersModel? = order(1, delivery: true)
        var partial = product(1, answered: true, delivery: true)
        partial.arrQuestions += product(1, answered: false, delivery: true).arrQuestions
        scoped?.arrProduct[1] = partial
        var other = notes()
        screen.removeBlankProducts(objOrderData: &scoped, arrOtherData: &other)
        XCTAssertEqual(scoped?.arrProduct.count, 2)
        XCTAssertEqual(screen.checkQuestions(objOrderData: scoped!), [IndexPath(row: 1, section: 1)])
    }

    /// A unit pick is the line's own input only as a FIRST selection (the caller marks it).
    /// A reassignment restarts the line — its flag is cleared — and applying the replacement
    /// unit must not re-enrol it: a restarted sibling with no answers stays out of the batch.
    func testApplyingAUnitDoesNotEnrolARestartedLine() {
        for delivery in [false, true] {
            let screen = CheckListViewController()
            let table = UITableView()                     // tblView is weak: keep it alive
            screen.tblView = table
            screen.isDeliveryType = delivery
            screen.objOrderData = order(0, delivery: delivery)
            screen.arrOtherData = notes()
            screen.arrMachineList = [MachineModel(map: Map(mappingType: .fromJSON, JSON: ["id": 7, "unique_id": "EQ-7"]))!]
            screen.selectProductIndex = 1

            screen.callCheckListAPI(index: 0)
            // The pick reloads the table 0.5 s later; let that finish while the table is alive.
            RunLoop.current.run(until: Date().addingTimeInterval(0.7))

            XCTAssertEqual(screen.objOrderData.arrProduct[1].objMachine?.unique_id, "EQ-7")
            let flag = delivery ? screen.arrOtherData[1].deliveryInputEntered : screen.arrOtherData[1].returnInputEntered
            XCTAssertFalse(flag, "applying a unit leaves the line's input flag as the caller set it")
            XCTAssertFalse(screen.hasChecklistWork(product: screen.objOrderData.arrProduct[1], other: screen.arrOtherData[1]))
            var scoped: OrdersModel? = screen.objOrderData
            var other = screen.arrOtherData
            screen.removeBlankProducts(objOrderData: &scoped, arrOtherData: &other)
            XCTAssertEqual(scoped?.arrProduct.count, 0, "a restarted line with only a unit is not part of the batch")
            withExtendedLifetime(table) {}
        }
    }

    /// Problems found in the batch point at the ORIGINAL line on screen: only C entered,
    /// no unit → C's own section; a missing shared employee/location → the footer that
    /// shows it (Combine: under the last line).
    func testValidationFocusMapsTheBatchLineBackToItsScreenSection() {
        for combine in [false, true] {
            let screen = CheckListViewController()
            screen.isDeliveryType = false
            screen.isCombineChecklist = combine
            var full = order(0, delivery: false)
            full.arrProduct[2] = product(2, answered: true, delivery: false)   // only C has work
            screen.objOrderData = full
            var scoped: OrdersModel? = full
            var other = notes()
            screen.removeBlankProducts(objOrderData: &scoped, arrOtherData: &other)
            XCTAssertEqual(scoped?.arrProduct.compactMap(\.unique_id), ["P2"])
            let batchLine = scoped!.arrProduct[0]
            XCTAssertNil(batchLine.objMachine, "C has answers but no unit: Preview must block on C")
            XCTAssertEqual(screen.focusSection(productUniqueId: batchLine.unique_id, inFooter: false), 2)
            XCTAssertEqual(screen.focusSection(productUniqueId: "P0", inFooter: true), combine ? 2 : 0)
            XCTAssertNil(screen.focusSection(productUniqueId: "UNKNOWN", inFooter: false))
        }
    }

    /// After a partial batch the leg already counts as done (one line is), yet the other lines
    /// are still in this phone's pending draft: Order Details must open the checklist flow, not
    /// the completed report that would hide them. With nothing pending, the report opens again.
    func testAPartialBatchKeepsTheRemainingLinesReachableFromOrderDetails() {
        for delivery in [false, true] {
            let details = OrderDetailsViewController()
            details.strOrderUniqueId = orderUid
            var full = OrdersListModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
            full.unique_id = orderUid
            full.arrProduct = order(3, delivery: delivery).arrProduct
            for index in full.arrProduct.indices { full.arrProduct[index].is_delivered = !delivery || index == 0 }
            if !delivery { full.arrProduct[0].is_returned = true }
            details.objOrderData = full

            XCTAssertTrue(details.effectiveLegCompleted(isDelivery: delivery), "one line done: the leg has started")
            XCTAssertTrue(details.legOpensCompletedReport(isDelivery: delivery), "nothing pending on this phone: the report")
            savePendingCheckList(orderUniqueId: orderUid, isDelivery: delivery, objOrderData: order(3, delivery: delivery), arrOtherData: notes())
            XCTAssertFalse(details.legOpensCompletedReport(isDelivery: delivery), "B/C still in the draft: the checklist flow")
            clearPendingCheckList(orderUniqueId: orderUid, isDelivery: delivery)
            XCTAssertTrue(details.legOpensCompletedReport(isDelivery: delivery))
        }
    }

    func testSharedConvenienceFieldsOnlyAffectDetachedBatchCopies() {
        for delivery in [false, true] {
            for combine in [false, true] {
                let screen = CheckListViewController()
                screen.isDeliveryType = delivery
                screen.isCombineChecklist = combine
                screen.combinedOtherData.dEmplayessId = "SHARED"
                screen.combinedOtherData.rEmplayessId = "SHARED"
                screen.combinedOtherData.rStoreId = "STORE"
                let original = notes()
                let batch = screen.batchOtherData(Array(original.prefix(2)))
                XCTAssertEqual(batch.count, 2)
                XCTAssertEqual(original.map(\.dEmplayessId), ["D0", "D1", "D2"])
                XCTAssertEqual(original.map(\.rEmplayessId), ["R0", "R1", "R2"])
                for (index, note) in batch.enumerated() {
                    XCTAssertFalse(note === original[index])
                    XCTAssertEqual(delivery ? note.dEmplayessId : note.rEmplayessId,
                                   combine ? "SHARED" : "\(delivery ? "D" : "R")\(index)")
                }
                XCTAssertEqual(original[2].rStoreId, "")
                XCTAssertEqual(batch[0].rStoreId, combine && !delivery ? "STORE" : "")
            }
        }
    }

    private func preview(delivery: Bool, combine: Bool) -> CheckListUpdateViewController {
        let preview = PreviewWithoutNetwork()
        // Retain weak outlets without loading the network-backed storyboard lifecycle.
        preview.view = UIView()
        let table = UITableView(); let submit = UIView(); let label = UILabel()
        preview.view.addSubview(table); preview.view.addSubview(submit); submit.addSubview(label)
        preview.tblView = table; preview.viewSubmit = submit; preview.lblSubmit = label
        preview.isDeliveryType = delivery; preview.isCombineChecklist = combine
        preview.objOrderData = order(3, delivery: delivery); preview.arrOtherData = notes()
        return preview
    }

    func testSignatureCaptureAndSubmitGuardArePerEquipment() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        for delivery in [false, true] {
            for combine in [false, true] {
                let screen = preview(delivery: delivery, combine: combine)
                let pad = EPSignatureViewController(signatureDelegate: screen, showsDate: true, showsSaveSignatureOption: true)
                screen.epSignature(pad, didSign: image, boundingRect: .zero, strIndex: 1)
                for (index, note) in screen.arrOtherData.enumerated() {
                    XCTAssertEqual(screen.hasSignature(note), combine || index == 1)
                    XCTAssertNil(delivery ? note.rSignature : note.dSignature)
                }
                XCTAssertEqual(screen.hasCustomerSignature(), combine)
                if !combine {
                    for index in [0, 2] { screen.epSignature(pad, didSign: image, boundingRect: .zero, strIndex: index) }
                    XCTAssertTrue(screen.hasCustomerSignature())
                }
            }
        }
    }

    func testOneStoredSignatureDoesNotSatisfyUnsignedSiblings() {
        let screen = preview(delivery: true, combine: false)
        screen.arrOtherData[2].dSignatureUrl = "https://signatures.invalid/last.jpg"
        XCTAssertTrue(screen.hasSignature(screen.arrOtherData[2]))
        XCTAssertFalse(screen.hasCustomerSignature())
        screen.arrOtherData[0].dSignature = UIImage()
        XCTAssertFalse(screen.hasSignature(screen.arrOtherData[0]))
    }

    func testPartialSubmissionKeepsOtherEquipmentDraftAndCache() {
        for delivery in [false, true] {
            let full = order(3, delivery: delivery)
            let other = notes()
            XCTAssertTrue(savePendingCheckList(orderUniqueId: orderUid, isDelivery: delivery, objOrderData: full, arrOtherData: other))
            let screen = CheckListUpdateViewController()
            screen.isDeliveryType = delivery; screen.strOrderUniqueId = orderUid
            var batch = full; batch.arrProduct = [full.arrProduct[0]]
            screen.objOrderData = batch; screen.arrOtherData = [other[0].batchCopy()]
            screen.cacheCompletedBatch(); screen.preserveUnsubmittedDraft()
            let pending = getPendingCheckList(orderUniqueId: orderUid, isDelivery: delivery)
            XCTAssertEqual(pending?.order.arrProduct.compactMap(\.unique_id), ["P1", "P2"])
            XCTAssertEqual(pending?.other.map(\.productID), [2, 3])
            XCTAssertEqual(pending?.other[0].dEmplayessId, "D1")
            let type = delivery ? "Delivery" : "Return"
            XCTAssertEqual(getChecklistOrderDetailData(strOrderUniqeID: "\(type)_\(orderUid)")?.arrProduct.compactMap(\.unique_id), ["P0"])
            batch.arrProduct = [full.arrProduct[1], full.arrProduct[2]]
            screen.objOrderData = batch; screen.arrOtherData = [other[1], other[2]]
            screen.cacheCompletedBatch(); screen.preserveUnsubmittedDraft()
            XCTAssertFalse(hasPendingCheckList(orderUniqueId: orderUid, isDelivery: delivery))
            XCTAssertEqual(getChecklistOtherData(strOrderUniqeID: "\(type)_\(orderUid)")?.map(\.productID), [1, 2, 3])
        }
    }

    func testDraftRestoresSharedSelectionWithoutChangingPerItemNotes() {
        for delivery in [false, true] {
            let shared = NoteModel()
            shared.dEmplayessId = "SHARED-D"; shared.rEmplayessId = "SHARED-R"
            shared.rStoreId = "SHARED-STORE"
            let original = notes()
            savePendingCheckList(orderUniqueId: orderUid, isDelivery: delivery,
                                 objOrderData: order(1, delivery: delivery), arrOtherData: original)
            for combine in [false, true] {
                savePendingCheckListConvenience(orderUniqueId: orderUid, isDelivery: delivery, combine: combine, other: shared)
                let loaded = getPendingCheckListConvenience(orderUniqueId: orderUid, isDelivery: delivery)
                XCTAssertEqual(loaded?.combine, combine)
                XCTAssertEqual(delivery ? loaded?.other.dEmplayessId : loaded?.other.rEmplayessId,
                               delivery ? "SHARED-D" : "SHARED-R")
                XCTAssertEqual(getPendingCheckList(orderUniqueId: orderUid, isDelivery: delivery)?.other.map(\.dEmplayessId), ["D0", "D1", "D2"])
            }
            clearPendingCheckList(orderUniqueId: orderUid, isDelivery: delivery)
            XCTAssertNil(getPendingCheckListConvenience(orderUniqueId: orderUid, isDelivery: delivery))
        }
    }
}
