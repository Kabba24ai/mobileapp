//
//  DispatchOfflineFieldBridgeHostedTests.swift
//  RentnKingHostedTests — runs inside the RentnKing app (Simulator or device)
//
//  Dispatch offline Phase 4 through the REAL app pieces: a stored mission
//  package (the shared Laravel fixture) is bridged by the Core field bridge
//  into the caches the existing screens read — MMKV Order Details +
//  checklist order (ObjectMapper models), the Assembly Review cache and the
//  checklist context store — and the offline screens' reads work with no
//  network at all. Company boundary (Amendment B): A → B → A on the same
//  phone, legacy unscoped records never read and never deleted. Also the
//  Order Details / T&C offline states (P4-D7, P4-D8).
//
//  No real server: tenants are *.invalid hosts and the checklist client's
//  session answers every request with "not connected to the internet".
//

import XCTest
import Foundation
import ObjectMapper
@testable import RentnKing

final class DispatchOfflineFieldBridgeHostedTests: XCTestCase {

    private let urlA = "https://tenant-a.invalid/api/admin/v1/"
    private let urlB = "https://tenant-b.invalid/api/admin/v1/"
    private var tenantA: String { DispatchOfflineTenant.key(baseURL: URL(string: urlA)!) }
    private var tenantB: String { DispatchOfflineTenant.key(baseURL: URL(string: urlB)!) }

    private let orderUid = "ORD-BJVZ-CSDO"        // the fixture's order
    private let opuid = "ORD-SCH-P8KU-S6A9"        // the fixture's mission line
    private var savedBaseURL: String?
    private var savedUser: User?
    private var root: URL!

    override func setUp() {
        super.setUp()
        savedBaseURL = UserDefaults.standard.baseURL
        savedUser = UserDefaults.standard.user
        root = FileManager.default.temporaryDirectory.appendingPathComponent("p4-hosted-\(UUID().uuidString)", isDirectory: true)
        signIn(urlA)
    }

    override func tearDown() {
        for url in [urlA, urlB] {
            signIn(url)
            SDKUserDefault.remove(for: [OrderDetailsCache.detailsKey(orderUid), OrderDetailsCache.checklistKey(orderUid),
                                        OrderDetailsCache.detailsKey(legacyUid), kFileStorageName.kEquipmentList.rawValue,
                                        kFileStorageName.kEmployesList.rawValue, kFileStorageName.kStoreList.rawValue,
                                        kFileStorageName.kPriceList.rawValue, kFileStorageName.kProductSettings.rawValue,
                                        kFileStorageName.kOrderDetailUserData.rawValue, jobSlot, manualSlot])
            KabbaAssemblySync.clearCache(orderUniqueId: orderUid)
        }
        SDKUserDefault.save("", for: OrderDetailsCache.detailsKey(legacyUid)) // neutralize the raw legacy record
        UserDefaults.standard.removeObject(forKey: "kQueueLineAssembly_\(legacyUid)")
        UserDefaults.standard.baseURL = savedBaseURL
        UserDefaults.standard.user = savedUser
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private let legacyUid = "ORD-P4-LEGACY-HOSTED"
    private let jobSlot = "kDispatchJobList_Delivery_2026-09-25_7"
    private let manualSlot = "kDispatchManualList_2026-09-25_7"

    private func signIn(_ url: String?) { UserDefaults.standard.baseURL = url }

    // MARK: Fixture → a stored, ready mission for company A

    private func fixturePackage() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KabbaSyncCore/Fixtures/dispatch_offline_packages.json")
        let root = try XCTUnwrap(JSONValue.parse(try Data(contentsOf: url)))
        return try XCTUnwrap(root["data"]?["packages"]?.arrayValue?.first)
    }

    private struct Harness {
        let store: DispatchOfflineMissionStore
        let contexts: ChecklistContextStore
        let bridge: DispatchOfflineFieldBridge
        let entry: DispatchOfflineIndex.Entry
    }

    private func harness(storeAt url: String, reuse: Bool = false) throws -> Harness {
        let store = try DispatchOfflineMissionStore(rootDirectory: root, baseURL: URL(string: url)!)
        let contexts = try ChecklistContextStore(rootDirectory: root, tenantKey: { KabbaTenantScope.currentKey })
        let bridge = DispatchOfflineFieldBridge(store: store, contexts: contexts, writer: DispatchOfflineOrderBridge.shared,
                                                operations: { [] }, currentEmployee: { nil })
        let missionKey = "\(opuid):delivery"
        if !reuse {
            let value = try fixturePackage()
            guard case .success(let package) = DispatchOfflinePackage.validate(value, requested: [missionKey]) else {
                throw XCTSkip("fixture package does not validate")
            }
            let file = try store.writePackage(package, cachedAt: Date(), serverObservedAt: Date())
            var index = DispatchOfflineIndex.empty(tenantKey: store.tenantKey,
                                                   baseURL: DispatchOfflineTenant.normalizedBaseURL(URL(string: url)!))
            index.everCommitted = true
            index.entries = [.init(missionKey: missionKey, orderProductUniqueId: opuid, leg: .delivery, effectiveDate: "2026-09-25",
                                   serverRevision: package.revision, readyRevision: package.revision, packageFile: file)]
            try store.commit(index)
        }
        let entry = try XCTUnwrap(store.loadIndex().entry(missionKey))
        return Harness(store: store, contexts: contexts, bridge: bridge, entry: entry)
    }

    /// A checklist client whose every request fails as "not connected to the internet".
    private func offlineChecklistClient(_ store: ChecklistContextStore) -> ChecklistContextClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineURLProtocol.self]
        let client = KabbaAPIClient(configuration: KabbaAPIClientConfiguration(
            baseURL: { URL(string: UserDefaults.standard.baseURL ?? "") }, accessToken: { "hosted-test-token" },
            language: { "en" }, metadata: { MobileClientMetadata(platform: "ios", version: "0", build: "0", deviceId: "hosted") }),
            session: URLSession(configuration: config))
        return ChecklistContextClient(client: client, store: store)
    }

    private func loadContext(_ client: ChecklistContextClient, unit: String? = nil, strict: Bool = false) -> Result<ChecklistContext, ChecklistContextError> {
        let done = expectation(description: "context")
        var out: Result<ChecklistContext, ChecklistContextError>!
        client.load(orderProductUniqueId: opuid, leg: .delivery, equipmentUniqueId: unit, strictUnit: strict) { result, _ in
            out = result
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return out
    }

    // MARK: - The key scenario through the real caches

    func testANeverOpenedMissionOpensOfflineThroughTheScreensOwnCaches() throws {
        let h = try harness(storeAt: urlA)

        let report = h.bridge.bridge(index: h.store.loadIndex())
        XCTAssertEqual(report.bridgedMissionKeys, [h.entry.missionKey])
        XCTAssertTrue(h.bridge.isFieldReady(h.entry), "Delivery = base + order_details + assembly + checklist_context")

        // Order Details (OrdersListModel, the screen's cache-first path).
        let details = try XCTUnwrap(OrderDetailsCache.load(orderUniqueId: orderUid))
        XCTAssertEqual(details.unique_id, orderUid)
        XCTAssertEqual(details.order_number, "1650")
        XCTAssertTrue(details.arrProduct.contains { $0.unique_id == opuid }, "the mission line")
        // The equipment checklist's order (OrdersModel, getOrderDetails' cache).
        let checklistOrder = try XCTUnwrap(getOrderDetailData(strOrderUniqeID: orderUid))
        XCTAssertTrue(checklistOrder.arrProduct.contains { $0.unique_id == opuid })
        // Assembly Review.
        let assembly = try XCTUnwrap(KabbaAssemblySync.cached(orderUniqueId: orderUid))
        XCTAssertTrue(assembly.success)
        // The canonical checklist context, offline.
        guard case .success(let context) = loadContext(offlineChecklistClient(h.contexts)) else {
            return XCTFail("the bridged context is served offline")
        }
        XCTAssertEqual(context.executionId, "ORD-CHK-4TQ6-TKA8")
        XCTAssertEqual(ChecklistCaptureFactory.questionModels(from: context, isDelivery: true, preserving: [:]).count,
                       context.questions.count, "the canonical questions render")
        XCTAssertEqual(ChecklistCaptureFactory.machine(from: context)?.unique_id, context.equipment.equipmentUniqueId)

        // Force quit + relaunch: new instances over the same directories — nothing re-bridged, still ready.
        let relaunched = try harness(storeAt: urlA, reuse: true)
        XCTAssertEqual(relaunched.bridge.bridge(index: relaunched.store.loadIndex()).bridgedMissionKeys, [])
        XCTAssertTrue(relaunched.bridge.isFieldReady(relaunched.entry))
        XCTAssertNotNil(OrderDetailsCache.load(orderUniqueId: orderUid))
    }

    func testTheReplacedUnitsContextIsNeverServedForTheReplacement() throws {
        let h = try harness(storeAt: urlA)
        h.bridge.bridge(index: h.store.loadIndex())
        let client = offlineChecklistClient(h.contexts)

        // After an offline substitution the screen asks strictly for the replacement unit.
        XCTAssertEqual(loadContext(client, unit: "EQP-REPLACEMENT", strict: true), .failure(.unavailableOffline),
                       "This unit's checklist needs a connection")
        // A hint that matches the bridged unit is still served.
        let unit = h.contexts.load(orderProductUniqueId: opuid, leg: .delivery)?.equipment.equipmentUniqueId
        if case .success = loadContext(client, unit: unit, strict: true) {} else { XCTFail("the bridged unit is served") }
    }

    // MARK: - P4-D5: whoever is signed in NOW performs the offline work (review I-1)

    private func signInUser(id: String, uniqueId: String?, name: String) {
        let user = User()
        user.id = id
        user.unique_id = uniqueId
        user.full_name = name
        UserDefaults.standard.user = user
    }

    func testALoginKeepsTheSignedInUsersUniqueId() {
        let user = User.fromLoginResponse(["id": 77, "unique_id": "PER-SIGNED-IN", "email": "y@example.test", "full_name": "Yolanda Driver"])
        XCTAssertEqual(user.id, "77")
        XCTAssertEqual(user.unique_id, "PER-SIGNED-IN")
        XCTAssertEqual(user.full_name, "Yolanda Driver")

        UserDefaults.standard.user = user
        XCTAssertEqual(DispatchOfflineSync.signedInEmployee(),
                       ChecklistContext.Employee(userId: 77, uniqueId: "PER-SIGNED-IN", fullName: "Yolanda Driver"))
        signInUser(id: "77", uniqueId: "0", name: "Yolanda Driver") // the resource's "no unique id" value
        XCTAssertNil(DispatchOfflineSync.signedInEmployee())
        signInUser(id: "77", uniqueId: nil, name: "Yolanda Driver") // a profile saved before this change
        XCTAssertNil(DispatchOfflineSync.signedInEmployee())
    }

    func testAMissionDownloadedByOneUserIsWorkedOfflineAsTheUserSignedInNow() throws {
        let h = try harness(storeAt: urlA)
        h.bridge.bridge(index: h.store.loadIndex()) // downloaded + bridged under Gary Driver (the package's employee)
        XCTAssertEqual(h.contexts.load(orderProductUniqueId: opuid, leg: .delivery)?.employee?.uniqueId, "PER-VDKO-9765")

        // Gary logs out; Yolanda (same company) logs in on the same phone and works offline.
        signInUser(id: "77", uniqueId: "PER-SIGNED-IN", name: "Yolanda Driver")

        guard case .success(let context) = loadContext(offlineChecklistClient(h.contexts)) else {
            return XCTFail("served offline")
        }
        XCTAssertEqual(context.employee, ChecklistContext.Employee(userId: 77, uniqueId: "PER-SIGNED-IN", fullName: "Yolanda Driver"),
                       "restarts / substitutions are attributed to Yolanda, never the downloader")
        XCTAssertEqual(KabbaAssemblySync.cached(orderUniqueId: orderUid)?.meta?.employee?.uniqueId, "PER-SIGNED-IN",
                       "Assembly Review acknowledgements too")
    }

    // MARK: - P4-D4: an unassigned delivery needs a connection (review I-2)

    func testAnUnassignedDeliveryOfflineNeedsAConnection() throws {
        let package = try fixturePackage()
        let bare = try XCTUnwrap(package["checklist_context"])
        guard case .object(var object) = bare, case .object(var equipment)? = object["equipment"] else { return XCTFail("fixture") }
        equipment["assignment"] = .string("none")
        equipment["equipment_unique_id"] = .null
        object["equipment"] = .object(equipment)
        object["questions"] = .array([])
        let unassigned = try ChecklistContext.decode(envelopeData: JSONValue.object(object).serialized())
        let contexts = try ChecklistContextStore(rootDirectory: root, tenantKey: { KabbaTenantScope.currentKey })
        try contexts.save(unassigned, tenantKey: tenantA)

        XCTAssertEqual(loadContext(offlineChecklistClient(contexts)), .failure(.unavailableOffline),
                       "never a question-less checklist a local unit pick could stage")
        XCTAssertEqual(loadContext(offlineChecklistClient(contexts), unit: "EQP-PICKED-LOCALLY"), .failure(.unavailableOffline))
    }

    /// Re-review finding: one line needing a connection (e.g. an unassigned sibling) must never stop the
    /// order's OTHER lines from saving / completing offline, and is never handed to Submit (which would
    /// send a context-less product through the legacy submission).
    func testALineNeedingAConnectionIsLeftOutWhileTheOtherLinesGoAhead() throws {
        let order = try XCTUnwrap(OrdersModel(JSON: ["order_products": [
            ["unique_id": "LINE-ASSIGNED", "product_name": "Skid Steer"],
            ["unique_id": "LINE-UNASSIGNED", "product_name": "Bucket"],
            ["unique_id": "LINE-OTHER", "product_name": "Trailer"],
        ]]))
        let other = [NoteModel(), NoteModel(), NoteModel()]

        let scoped = CheckListViewController.excludingProductsNeedingConnection(order, other: other, needingConnection: ["LINE-UNASSIGNED"])

        XCTAssertEqual(scoped.order?.arrProduct.map { $0.unique_id ?? "" }, ["LINE-ASSIGNED", "LINE-OTHER"])
        XCTAssertEqual(scoped.other.count, 2)
        XCTAssertTrue(scoped.other[0] === other[0] && scoped.other[1] === other[2], "each line keeps its own employee / signature rows")
        XCTAssertEqual(scoped.excluded, ["LINE-UNASSIGNED"])

        let untouched = CheckListViewController.excludingProductsNeedingConnection(order, other: other, needingConnection: [])
        XCTAssertEqual(untouched.order?.arrProduct.count, 3)
        XCTAssertEqual(untouched.excluded, [])

        let allBlocked = CheckListViewController.excludingProductsNeedingConnection(
            order, other: other, needingConnection: ["LINE-ASSIGNED", "LINE-UNASSIGNED", "LINE-OTHER"])
        XCTAssertEqual(allBlocked.order?.arrProduct.count, 0, "nothing to submit: the screen says it needs a connection")
    }

    // MARK: - Amendment B: company A → B → A on one phone

    func testNoCompanyADataIsReadableUnderCompanyBAndAKeepsItsOwn() throws {
        let h = try harness(storeAt: urlA)
        h.bridge.bridge(index: h.store.loadIndex())
        // A's reference lists and Dispatch slots, saved the way the loaders / Dispatch save them.
        XCTAssertTrue(SDKUserDefault.saveMappableArray([MachineModel(JSON: ["unique_id": "EQ-A", "equipment_name": "A unit"])!],
                                                       for: kFileStorageName.kEquipmentList.rawValue, tenantKey: tenantA))
        XCTAssertTrue(SDKUserDefault.saveMappableArray([EmployeesModel(JSON: ["id": 1, "name": "A employee"])!],
                                                       for: kFileStorageName.kEmployesList.rawValue, tenantKey: tenantA))
        XCTAssertTrue(SDKUserDefault.saveMappableArray([StoreModel(JSON: ["id": 1, "name": "A store"])!],
                                                       for: kFileStorageName.kStoreList.rawValue, tenantKey: tenantA))
        SDKUserDefault.saveMappableArray([SchedulesModel(JSON: ["unique_id": opuid])!], for: jobSlot)
        SDKUserDefault.saveCodableArray(["A manual job"], for: manualSlot)

        // Logout → Company B, offline.
        signIn(nil)
        XCTAssertNil(OrderDetailsCache.load(orderUniqueId: orderUid), "signed out: nothing is read")
        signIn(urlB)
        XCTAssertNil(OrderDetailsCache.load(orderUniqueId: orderUid))
        XCTAssertNil(getOrderDetailData(strOrderUniqeID: orderUid))
        XCTAssertNil(KabbaAssemblySync.cached(orderUniqueId: orderUid))
        XCTAssertNil(h.contexts.load(orderProductUniqueId: opuid, leg: .delivery))
        if case .success = loadContext(offlineChecklistClient(h.contexts)) { XCTFail("no A checklist under B") }
        XCTAssertTrue(getEquipmentData().isEmpty)
        XCTAssertTrue(getEmployeeData().isEmpty)
        XCTAssertTrue(getStoreListData().isEmpty)
        XCTAssertNil(SDKUserDefault.getMappableArray(SchedulesModel.self, for: jobSlot))
        XCTAssertNil(SDKUserDefault.getCodableArray(String.self, for: manualSlot))
        // B's own session never bridges A's packages.
        let b = try DispatchOfflineMissionStore(rootDirectory: root, baseURL: URL(string: urlB)!)
        XCTAssertTrue(b.loadIndex().entries.isEmpty)

        // Back to A: everything is still there and usable offline.
        signIn(urlA)
        XCTAssertNotNil(OrderDetailsCache.load(orderUniqueId: orderUid))
        XCTAssertNotNil(getOrderDetailData(strOrderUniqeID: orderUid))
        XCTAssertNotNil(KabbaAssemblySync.cached(orderUniqueId: orderUid))
        if case .success = loadContext(offlineChecklistClient(h.contexts)) {} else { XCTFail("A's checklist is back") }
        XCTAssertEqual(getEquipmentData().first?.unique_id, "EQ-A")
        XCTAssertEqual(getEmployeeData().count, 1)
        XCTAssertEqual(getStoreListData().count, 1)
        XCTAssertEqual(SDKUserDefault.getMappableArray(SchedulesModel.self, for: jobSlot)?.count, 1)
        XCTAssertEqual(SDKUserDefault.getCodableArray(String.self, for: manualSlot), ["A manual job"])
    }

    func testALegacyUnscopedRecordIsNeverReadAndNeverDeleted() throws {
        let legacy = try XCTUnwrap(OrdersListModel(JSON: ["unique_id": legacyUid, "order_number": "9"])?.toJSONString())
        SDKUserDefault.save(legacy, for: OrderDetailsCache.detailsKey(legacyUid)) // written before Phase 4: no company
        UserDefaults.standard.set(Data("{}".utf8), forKey: "kQueueLineAssembly_\(legacyUid)")

        XCTAssertNil(OrderDetailsCache.load(orderUniqueId: legacyUid), "its company cannot be proven")
        XCTAssertNil(KabbaAssemblySync.cached(orderUniqueId: legacyUid))
        XCTAssertEqual(SDKUserDefault.getString(for: OrderDetailsCache.detailsKey(legacyUid)), legacy, "ignored, not deleted")
        XCTAssertNotNil(UserDefaults.standard.data(forKey: "kQueueLineAssembly_\(legacyUid)"))
    }

    // MARK: - Writers

    func testTheOrderDetailsWriterReappliesNotesQueuedOffline() throws {
        let order = try XCTUnwrap(OrdersListModel(JSON: ["unique_id": orderUid, "order_notes": [
            ["id": 11, "unique_id": "NOTE-SERVER-1", "note": "Gate code 4321"],
            ["id": 12, "unique_id": "NOTE-SERVER-2", "note": "Call on arrival"],
        ]]))
        let queue = [
            OrderNoteModel(JSON: ["id": 90001, "note": "Written offline", "type": "add", "status": "pending", "mainOrderUniqueID": orderUid])!,
            OrderNoteModel(JSON: ["id": 12, "unique_id": "NOTE-SERVER-2", "note": "Call 10 min before", "type": "edit", "status": "pending", "mainOrderUniqueID": orderUid])!,
            OrderNoteModel(JSON: ["id": 90002, "unique_id": "NOTE-SERVER-1", "type": "delete", "status": "pending", "mainOrderUniqueID": orderUid])!,
            OrderNoteModel(JSON: ["id": 90003, "note": "Another order's note", "type": "add", "status": "pending", "mainOrderUniqueID": "ORD-OTHER"])!,
        ]

        let notes = OrderNoteQueue.reapplied(to: order, orderUniqueId: orderUid, queue: queue).arrOrderNote.map { $0.note ?? "" }

        XCTAssertEqual(notes, ["Written offline", "Call 10 min before"], "add first, edit in place, queued delete removes the server note")
    }

    func testAnAssemblyWithoutItsDataIsNotWritten() {
        XCTAssertFalse(DispatchOfflineOrderBridge.shared.write(.assembly, payload: .object(["meta": .object([:])]),
                                                               orderUniqueId: orderUid, tenantKey: tenantA))
        XCTAssertNil(KabbaAssemblySync.cached(orderUniqueId: orderUid))
        XCTAssertFalse(DispatchOfflineOrderBridge.shared.write(.orderDetails, payload: .string("not an order"),
                                                               orderUniqueId: orderUid, tenantKey: tenantA))
    }

    func testALiveAnswerForACompanyNoLongerSignedInIsNeverSaved() throws {
        let order = try XCTUnwrap(OrdersListModel(JSON: ["unique_id": orderUid]))
        signIn(urlB) // the request went out for A; B signed in before the answer arrived
        XCTAssertFalse(OrderDetailsCache.saveLive(order, orderUniqueId: orderUid, askedAt: Date(), tenantKey: tenantA))
        signIn(urlA)
        XCTAssertNil(OrderDetailsCache.load(orderUniqueId: orderUid))
        XCTAssertTrue(OrderDetailsCache.saveLive(order, orderUniqueId: orderUid, askedAt: Date(), tenantKey: tenantA))
        XCTAssertNotNil(OrderDetailsCache.load(orderUniqueId: orderUid))
    }

    func testAListAnswerIsFiledUnderTheCompanyThatAskedAndACachedListSurvivesAFailedRefresh() throws {
        XCTAssertTrue(SDKUserDefault.saveMappableArray([MachineModel(JSON: ["unique_id": "EQ-A"])!],
                                                       for: kFileStorageName.kEquipmentList.rawValue, tenantKey: tenantA))
        XCTAssertFalse(SDKUserDefault.saveMappableArray([MachineModel(JSON: ["unique_id": "EQ-X"])!],
                                                        for: kFileStorageName.kEquipmentList.rawValue, tenantKey: nil),
                       "a request sent while signed out saves nothing")

        // The refresh fails (no such host): the cached list is served and never replaced by [].
        var answers: [[MachineModel]] = []
        let served = expectation(description: "cached list served")
        getEquipmentList { list in
            answers.append(list)
            if answers.count == 1 { served.fulfill() }
        }
        wait(for: [served], timeout: 5)
        let settle = expectation(description: "failed refresh settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { settle.fulfill() }
        wait(for: [settle], timeout: 10)
        XCTAssertEqual(answers.map { $0.map(\.unique_id) }, [["EQ-A"]], "never a second, empty answer")
    }

    // MARK: - P4-D7 Order Details / P4-D8 T&C boundaries

    func testOrderDetailsControlsNeverCrashWithNoOrderLoaded() throws {
        let vc = OrderDetailsViewController()
        vc.arrUserList = [UserListModel(JSON: [:])!] // no user fetch
        vc.isLoading = false
        XCTAssertNil(vc.objOrderData)
        for action in [vc.btnDeliveryImageVideoUploadClicked, vc.btnReturnImageVideoUploadClicked, vc.btnEditNoteClicked,
                       vc.btnCheckListDelivClicked, vc.btnCheckListRetClicked, vc.btnTermsAndConditionClicked,
                       vc.btnPaymentClicked, vc.btnLicenseClicked, vc.btnCallClicked, vc.btnMapClicked, vc.btnAddressClicked] {
            action(UIButton())
        }
        XCTAssertEqual(vc.tableView(UITableView(), numberOfRowsInSection: 0), 0)
    }

    func testTheNotDownloadedStatesSayWhatHappened() {
        let order = EmptyDataView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        order.orderNotDownloaded()
        XCTAssertTrue(labels(in: order).contains("This order isn't downloaded to this phone yet"))

        let terms = EmptyDataView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        terms.termsNeedConnection()
        XCTAssertTrue(labels(in: terms).contains("Signing Terms & Conditions needs a connection"))
    }

    func testTermsAndConditionsOfflineIsAClearStateNeverABlankPageOrACrash() {
        typealias T = TermsAndConditionViewController
        XCTAssertEqual(T.boundary(reachable: false, signUrl: "https://kabba.ai/terms/sign/abc"), .needsConnection)
        XCTAssertEqual(T.boundary(reachable: true, signUrl: ""), .unavailable, "was a URL(string:)! crash")
        XCTAssertEqual(T.boundary(reachable: true, signUrl: "not a url"), .unavailable)
        XCTAssertEqual(T.boundary(reachable: true, signUrl: " https://kabba.ai/terms/sign/abc "),
                       .load(URL(string: "https://kabba.ai/terms/sign/abc")!))
    }

    private func labels(in view: UIView) -> [String] {
        ((view as? UILabel)?.text.map { [$0] } ?? []) + view.subviews.flatMap { labels(in: $0) }
    }
}

/// Every request fails as "not connected to the internet" — the phone is offline.
private final class OfflineURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
    }
    override func stopLoading() {}
}
