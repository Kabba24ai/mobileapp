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

    // MARK: Order-wide entry — Order Details and the Orders list (ChecklistLegCompletion)

    /// A three-line order as the order feed reports it: `delivered` / `returned` are Laravel's
    /// per-product leg flags (index → flag).
    private func feedOrder(delivered: Set<Int>, returned: Set<Int> = [], retail: Set<Int> = []) -> OrdersListModel {
        var order = OrdersListModel(map: Map(mappingType: .fromJSON, JSON: [:]))!
        order.unique_id = orderUid
        order.arrProduct = (0..<3).map { index in
            var line = product(index, answered: false, delivery: true)
            line.is_delivered = delivered.contains(index)
            line.is_returned = returned.contains(index)
            if retail.contains(index) {
                line.objProductData = ProductDataModel(map: Map(mappingType: .fromJSON, JSON: ["product_type": "Retail"]))
            }
            return line
        }
        return order
    }

    private func details(_ order: OrdersListModel, operations: [SyncOperation] = []) -> OrderDetailsViewController {
        let details = OrderDetailsViewController()
        details.strOrderUniqueId = orderUid
        details.objOrderData = order
        details.operationsSnapshot = { operations }
        return details
    }

    private func completion(_ leg: ChecklistLeg, line index: Int, execution: String? = nil) -> SyncOperation {
        var op = SyncOperation(type: ChecklistLegCompletion.completionType(leg), capturedAt: Date(),
                               identity: SyncBusinessIdentity(orderUniqueId: orderUid, orderProductUniqueId: "P\(index)",
                                                              checklistExecutionId: execution),
                               payload: .object([:]))
        op.state = .pending
        return op
    }

    /// Reproduced on a fresh phone: one line delivered (or returned) made the WHOLE leg open the
    /// completed report — with no draft on that phone the unfinished siblings were unreachable.
    /// Every permutation now keeps unfinished equipment reachable; the report needs all of it.
    func testOrderDetailsOpensTheReportOnlyWhenEveryEligibleLineIsComplete() {
        for mask in 0..<8 {
            let done = Set((0..<3).filter { mask & (1 << $0) != 0 })
            let delivery = details(feedOrder(delivered: done))
            XCTAssertEqual(delivery.legOpensCompletedReport(isDelivery: true), mask == 7, "delivered \(done.sorted())")
            let allOut = details(feedOrder(delivered: [0, 1, 2], returned: done))
            XCTAssertEqual(allOut.legOpensCompletedReport(isDelivery: false), mask == 7, "returned \(done.sorted())")
        }
        // Only the third line done — the first two stay reachable on both legs.
        XCTAssertFalse(details(feedOrder(delivered: [2])).legOpensCompletedReport(isDelivery: true))
        XCTAssertFalse(details(feedOrder(delivered: [0, 1, 2], returned: [2])).legOpensCompletedReport(isDelivery: false))
    }

    /// Drafts keep entered values; they never decide what is finished — in either direction.
    func testADraftNeitherHidesNorRevealsUnfinishedEquipment() {
        for delivery in [false, true] {
            let partial = delivery ? feedOrder(delivered: [0]) : feedOrder(delivered: [0, 1, 2], returned: [0])
            let complete = delivery ? feedOrder(delivered: [0, 1, 2]) : feedOrder(delivered: [0, 1, 2], returned: [0, 1, 2])
            XCTAssertFalse(details(partial).legOpensCompletedReport(isDelivery: delivery), "no draft on this phone: still reachable")
            savePendingCheckList(orderUniqueId: orderUid, isDelivery: delivery, objOrderData: order(3, delivery: delivery), arrOtherData: notes())
            XCTAssertFalse(details(partial).legOpensCompletedReport(isDelivery: delivery))
            XCTAssertTrue(details(complete).legOpensCompletedReport(isDelivery: delivery), "a stale draft never holds back a finished leg")
            clearPendingCheckList(orderUniqueId: orderUid, isDelivery: delivery)
        }
    }

    /// Completed only on this phone (a durable completion op, not yet on the server): that line
    /// counts, its siblings stay reachable; a delivery op never completes the return.
    func testADurableLocalCompletionCountsForItsOwnLineAndLegOnly() {
        let a = [completion(.delivery, line: 0)]
        XCTAssertFalse(details(feedOrder(delivered: []), operations: a).legOpensCompletedReport(isDelivery: true))
        let all = (0..<3).map { completion(.delivery, line: $0) }
        XCTAssertTrue(details(feedOrder(delivered: []), operations: all).legOpensCompletedReport(isDelivery: true))
        let deliveredByOps = details(feedOrder(delivered: []), operations: all)
        XCTAssertTrue(deliveredByOps.returnChecklistAvailable(), "delivered offline: Return opens")
        XCTAssertFalse(deliveredByOps.legOpensCompletedReport(isDelivery: false), "...but nothing is returned yet")
        let returnedA = details(feedOrder(delivered: [0, 1, 2]), operations: [completion(.return, line: 0)])
        XCTAssertFalse(returnedA.legOpensCompletedReport(isDelivery: false))
    }

    /// Equipment that takes no checklist (Retail) never holds the report back; Return opens only
    /// once something is out — never from the first line's flag or an order-level marker.
    func testEligibilityAndTheReturnGate() {
        XCTAssertTrue(details(feedOrder(delivered: [0, 1], retail: [2])).legOpensCompletedReport(isDelivery: true))
        XCTAssertFalse(details(feedOrder(delivered: [])).returnChecklistAvailable())
        XCTAssertTrue(details(feedOrder(delivered: [2])).returnChecklistAvailable(), "the THIRD line out opens Return")
        // An order-level local report alone (the old marker) never completes the leg.
        SDKUserDefault.saveMappableObject(order(3, delivery: true), for: "\(kFileStorageName.kCheckListOrderDetailsData.rawValue)_Delivery_\(orderUid)")
        XCTAssertFalse(details(feedOrder(delivered: [0])).legOpensCompletedReport(isDelivery: true))
    }

    /// The Orders list tile follows the same rule (no draft on this phone).
    func testTheOrdersListTileFollowsTheSameRule() {
        let list = OrderListViewController()
        list.operationsSnapshot = { [] }
        list.arrOrderList = [feedOrder(delivered: [0]), feedOrder(delivered: [0, 1, 2]),
                             feedOrder(delivered: [0, 1, 2], returned: [1]), feedOrder(delivered: [])]
        XCTAssertFalse(list.checkListOpensReport(selectIndex: 0, isDelivery: true), "A delivered, B/C owed")
        XCTAssertTrue(list.checkListOpensReport(selectIndex: 1, isDelivery: true))
        XCTAssertFalse(list.checkListOpensReport(selectIndex: 2, isDelivery: false), "B returned, A/C owed")
        XCTAssertTrue(list.returnCheckListAvailable(selectIndex: 0))
        XCTAssertFalse(list.returnCheckListAvailable(selectIndex: 3), "nothing out yet")
    }

    /// This phone completed A and it SYNCED; the office then REOPENED A's delivery (a new cycle).
    /// An order copy asked after Laravel acknowledged that completion still says A is not
    /// delivered — so A is owed again, on Order Details and the Orders list alike. A copy of
    /// unknown age (offline) keeps the synced completion as the bridge until it is refreshed.
    func testALegReopenedAfterThisPhoneSyncedItIsOwedAgain() {
        var synced = completion(.delivery, line: 0, execution: "EXEC-A1")
        synced.state = .synced
        synced.acknowledgment = SyncAcknowledgment(acknowledgedAt: Date(timeIntervalSinceNow: -60), statusCode: 200,
                                                   requestId: nil, replayed: false, serverReceivedAt: nil, data: nil)
        let ops = [synced, completion(.delivery, line: 1), completion(.delivery, line: 2)]   // B, C still offline
        let fresh = details(feedOrder(delivered: []), operations: ops)
        fresh.orderCopyAsOf = Date()
        XCTAssertFalse(fresh.legOpensCompletedReport(isDelivery: true), "A was reopened since: owed again")
        let older = details(feedOrder(delivered: []), operations: ops)
        older.orderCopyAsOf = Date(timeIntervalSinceNow: -600)
        XCTAssertTrue(older.legOpensCompletedReport(isDelivery: true), "the copy predates the completion: it still counts")
        XCTAssertTrue(details(feedOrder(delivered: []), operations: ops).legOpensCompletedReport(isDelivery: true), "age unknown")

        let list = OrderListViewController()
        list.operationsSnapshot = { ops }
        list.arrOrderList = [feedOrder(delivered: [])]
        XCTAssertTrue(list.checkListOpensReport(selectIndex: 0, isDelivery: true), "cached list, age unknown")
        list.orderCopyAsOf[orderUid] = Date()
        XCTAssertFalse(list.checkListOpensReport(selectIndex: 0, isDelivery: true), "refreshed list: A owed again")
    }

    /// The checklist opened for the order shows the equipment still owed and never re-enrols a
    /// line completed elsewhere, even when its loaded answers look like entered work.
    func testTheChecklistShowsOnlyOwedEquipmentAndNeverReEnrolsACompletedLine() {
        let screen = CheckListViewController()
        screen.isDeliveryType = true
        var loaded = order(3, delivery: true)          // every line carries answers
        loaded.arrProduct[0].is_delivered = true        // A finished on another phone
        screen.objOrderData = loaded
        screen.arrOtherData = notes()
        XCTAssertFalse(screen.hasChecklistWork(product: loaded.arrProduct[0], other: screen.arrOtherData[0]))
        XCTAssertTrue(screen.hasChecklistWork(product: loaded.arrProduct[1], other: screen.arrOtherData[1]))
        screen.dropLinesAlreadyComplete()
        XCTAssertEqual(screen.objOrderData.arrProduct.compactMap(\.unique_id), ["P1", "P2"])
        XCTAssertEqual(screen.arrOtherData.map(\.productID), [2, 3], "notes stay aligned")
        // Nothing owed (opened from a finished line): the screen keeps what it was given.
        for index in 0..<2 { screen.objOrderData.arrProduct[index].is_delivered = true }
        screen.dropLinesAlreadyComplete()
        XCTAssertEqual(screen.objOrderData.arrProduct.count, 2)
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
