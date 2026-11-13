//
//  SupplierDirectoryHostedTests.swift
//  RentnKingHostedTests — Supplier Directory (2026-11-13)
//
//  The real screens against Laravel's own responses (the captured
//  supplier_directory_*.json fixtures), served through a stubbed URLSession
//  behind the canonical KabbaAPIClient — so the envelope, the status codes and
//  the decoding are exactly what the phone meets in production.
//

import XCTest
@testable import RentnKing

final class SupplierDirectoryHostedTests: XCTestCase {

    // MARK: Harness

    private var storage: [String: Data] = [:]
    private var opened: [URL] = []

    override func setUp() {
        super.setUp()
        SupplierStubProtocol.reset()
        storage = [:]
        opened = []
    }

    override func tearDown() {
        SupplierStubProtocol.reset()
        super.tearDown()
    }

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KabbaSyncCore/Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }

    private func api() -> SupplierDirectoryAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SupplierStubProtocol.self]
        let client = KabbaAPIClient(configuration: KabbaAPIClientConfiguration(
            baseURL: { URL(string: "https://suppliers.invalid/api/admin/v1/") }, accessToken: { "hosted-test-token" },
            language: { "en" }, metadata: { MobileClientMetadata(platform: "ios", version: "0", build: "0", deviceId: "hosted") }),
            session: URLSession(configuration: config))
        let api = SupplierDirectoryAPI()
        api.clientProvider = { client }
        api.offlineCopy = SupplierDirectoryOfflineCopy(read: { [unowned self] in self.storage[$0] },
                                                       write: { [unowned self] key, data in self.storage[key] = data })
        return api
    }

    private func wait(_ timeout: TimeInterval = 5, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    private func labels(in view: UIView) -> [String] {
        ((view as? UILabel)?.text.map { [$0] } ?? []) + view.subviews.flatMap { labels(in: $0) }
    }

    private func find<T: UIView>(_ id: String, in view: UIView, as type: T.Type = T.self) -> T? {
        if view.accessibilityIdentifier == id, let match = view as? T { return match }
        for sub in view.subviews { if let match = find(id, in: sub, as: type) { return match } }
        return nil
    }

    // MARK: Home

    func testHomeOffersSuppliersInTheFreeSlotBesideEquipmentAudit() throws {
        let home = try XCTUnwrap(UIStoryboard(name: "Home", bundle: nil).instantiateViewController(withIdentifier: "HomeViewController") as? HomeViewController)
        let nav = UINavigationController(rootViewController: home)
        home.loadViewIfNeeded()
        let tile = try XCTUnwrap(find("home.suppliers.tile", in: home.view))
        let row = try XCTUnwrap(tile.superview as? UIStackView)
        XCTAssertEqual(row.arrangedSubviews.count, 2)
        XCTAssertTrue(row.arrangedSubviews.first === home.viewInventory, "beside Equipment Audit; every storyboard tile keeps its place")
        XCTAssertTrue(labels(in: tile).contains("Suppliers"))
        home.installSupplierDirectoryTile()
        XCTAssertEqual(row.arrangedSubviews.count, 2, "installing twice changes nothing")

        let button = try XCTUnwrap(find("home.suppliers", in: tile, as: UIButton.self))
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(nav.topViewController is SupplierListViewController)
    }

    // MARK: Directory

    func testTheDirectoryListsSearchesFiltersAndOffersAddSupplier() throws {
        let list = try fixture("supplier_directory_list")
        SupplierStubProtocol.handler = { _ in (200, list) }
        let screen = SupplierListViewController(api: api())
        let nav = UINavigationController(rootViewController: screen)
        screen.loadViewIfNeeded()
        wait { !screen.suppliers.isEmpty }

        XCTAssertEqual(screen.suppliers.map(\.name), ["Midway Parts", "Smoky Mountain Hydraulics"])
        XCTAssertEqual(screen.table.numberOfRows(inSection: 0), 2)
        XCTAssertFalse(screen.addButton.isHidden, "the server says this account may add suppliers")
        XCTAssertEqual(SupplierStubProtocol.requests.last?.url?.query, "status=active&page=1&per_page=25")

        screen.applySearch("dana")
        wait { SupplierStubProtocol.requests.count >= 2 }
        XCTAssertEqual(SupplierStubProtocol.requests.last?.url?.query, "search=dana&status=active&page=1&per_page=25")

        screen.setStatus(.inactive)
        wait { SupplierStubProtocol.requests.count >= 3 }
        XCTAssertTrue(SupplierStubProtocol.requests.last?.url?.query?.contains("status=inactive") == true, "inactive suppliers on request")

        screen.tableView(screen.table, didSelectRowAt: IndexPath(row: 1, section: 0))
        XCTAssertTrue(nav.topViewController is SupplierDetailViewController)
        nav.popViewController(animated: false)
        screen.addSupplier()
        XCTAssertTrue(nav.topViewController is SupplierAddViewController)
    }

    func testWithoutAConnectionTheDirectoryShowsSuppliersSavedOnThisPhone() throws {
        let api = self.api()
        api.offlineCopy.saveDetail(try SupplierDirectoryDecoding.decode(SupplierDetailEnvelope.self, envelope: try fixture("supplier_directory_detail")))
        SupplierStubProtocol.handler = { _ in nil }          // offline
        let screen = SupplierListViewController(api: api)
        _ = UINavigationController(rootViewController: screen)
        screen.loadViewIfNeeded()
        wait { screen.isShowingOfflineCopy }

        XCTAssertEqual(screen.suppliers.map(\.name), ["Smoky Mountain Hydraulics"])
        let banner = try XCTUnwrap(find("suppliers.offline", in: screen.view, as: UILabel.self))
        XCTAssertFalse(banner.isHidden)
        XCTAssertEqual(banner.text, SupplierDirectoryPresentation.offlineList)
    }

    func testAnAccountOutsideTheEmployeePolicyIsToldSoAndCannotAdd() throws {
        let forbidden = try fixture("supplier_directory_forbidden")
        SupplierStubProtocol.handler = { _ in (403, forbidden) }
        let screen = SupplierListViewController(api: api())
        _ = UINavigationController(rootViewController: screen)
        screen.loadViewIfNeeded()
        wait { screen.failure != nil }

        XCTAssertTrue(screen.failure?.isForbidden == true)
        XCTAssertTrue(screen.addButton.isHidden)
        XCTAssertTrue(labels(in: screen.table.backgroundView ?? UIView()).contains(SupplierDirectoryPresentation.forbidden))
    }

    func testAnOlderKabbaWithoutTheDirectoryIsExplainedNotShownAsAnError() throws {
        // One app serves every Kabba customer; a customer on an older Kabba has no suppliers route.
        let missing = Data(#"{"success":false,"message":"Not found.","error":{"code":"NOT_FOUND","message":"Not found.","retryable":false},"errors":{},"error_code":"NOT_FOUND"}"#.utf8)
        SupplierStubProtocol.handler = { _ in (404, missing) }
        let screen = SupplierListViewController(api: api())
        _ = UINavigationController(rootViewController: screen)
        screen.loadViewIfNeeded()
        wait { screen.failure != nil }
        XCTAssertTrue(screen.failure?.isUnavailable == true)
        XCTAssertTrue(screen.addButton.isHidden, "nothing to add to")
        XCTAssertTrue(labels(in: screen.table.backgroundView ?? UIView()).contains(SupplierDirectoryPresentation.unavailable))

        let detail = SupplierDetailViewController(uniqueId: "SUP-ANY", api: api())
        _ = UINavigationController(rootViewController: detail)
        detail.loadViewIfNeeded()
        wait { detail.failure != nil }
        XCTAssertTrue(labels(in: detail.view).contains(SupplierDirectoryPresentation.unavailable), "not \"no longer in Kabba\"")
    }

    // MARK: Detail

    func testTheDetailOffersCallEmailWebsiteAndDirectionsAndOnlyWhatIsOnFile() throws {
        let detail = try fixture("supplier_directory_detail")
        SupplierStubProtocol.handler = { _ in (200, detail) }
        let screen = SupplierDetailViewController(uniqueId: "SUP-PP8E-0MKW", api: api())
        screen.openURL = { [unowned self] in self.opened.append($0) }
        _ = UINavigationController(rootViewController: screen)
        screen.loadViewIfNeeded()
        wait { screen.envelope != nil }

        let links = Dictionary(uniqueKeysWithValues: screen.actionLinks.map { ($0.id, $0.url.absoluteString) })
        XCTAssertEqual(links["suppliers.detail.phone"], "tel:8655550100")
        XCTAssertEqual(links["suppliers.detail.email"], "mailto:sales@smh.example")
        XCTAssertEqual(links["suppliers.detail.website"], "https://smh.example")
        XCTAssertEqual(links["suppliers.detail.address"], "https://maps.apple.com/?daddr=12%20Main%20St,%20Knoxville,%20TN%2037902")
        XCTAssertEqual(links["suppliers.detail.primary_contact.phone"], "tel:8655550101")
        XCTAssertEqual(links["suppliers.detail.technical_support.phone"], "tel:8655550199")
        XCTAssertNil(links["suppliers.detail.inside_sales.phone"], "no inside sales contact on file — none invented")

        let call = try XCTUnwrap(find("suppliers.detail.phone", in: screen.view, as: UIButton.self))
        call.sendActions(for: .touchUpInside)
        let directions = try XCTUnwrap(find("suppliers.detail.address", in: screen.view, as: UIButton.self))
        directions.sendActions(for: .touchUpInside)
        XCTAssertEqual(opened.map(\.absoluteString), ["tel:8655550100", "https://maps.apple.com/?daddr=12%20Main%20St,%20Knoxville,%20TN%2037902"])

        let text = labels(in: screen.view)
        XCTAssertTrue(text.contains("Company Information") && text.contains("Contacts") && text.contains("Other Information"))
        XCTAssertTrue(text.contains("Hose Kit"))
        XCTAssertNil(find("suppliers.detail.paymentTerms", in: screen.view), "payment terms are accounts-payable data")
        XCTAssertNotNil(storage[SupplierDirectoryOfflineCopy.detailPrefix + "SUP-PP8E-0MKW"], "kept as the read-only copy")
    }

    func testPaymentTermsAppearForTheAccountsPayableAuthority() throws {
        let detail = try fixture("supplier_directory_detail_ap")
        SupplierStubProtocol.handler = { _ in (200, detail) }
        let screen = SupplierDetailViewController(uniqueId: "SUP-PP8E-0MKW", api: api())
        _ = UINavigationController(rootViewController: screen)
        screen.loadViewIfNeeded()
        wait { screen.envelope != nil }
        let terms = try XCTUnwrap(find("suppliers.detail.paymentTerms", in: screen.view))
        XCTAssertTrue(labels(in: terms).contains("Net 30"))
    }

    func testOfflineTheDetailShowsTheSavedCopyMarkedAsPossiblyOutOfDate() throws {
        let api = self.api()
        api.offlineCopy.saveDetail(try SupplierDirectoryDecoding.decode(SupplierDetailEnvelope.self, envelope: try fixture("supplier_directory_detail")))
        SupplierStubProtocol.handler = { _ in nil }
        let screen = SupplierDetailViewController(uniqueId: "SUP-PP8E-0MKW", api: api)
        _ = UINavigationController(rootViewController: screen)
        screen.loadViewIfNeeded()
        wait { screen.cachedAt != nil }
        XCTAssertNotNil(find("suppliers.detail.offline", in: screen.view))
        XCTAssertTrue(labels(in: screen.view).contains("Smoky Mountain Hydraulics"))
    }

    // MARK: Add Supplier

    private func form(_ api: SupplierDirectoryAPI) -> (SupplierAddViewController, UINavigationController, SupplierListViewController) {
        let list = SupplierListViewController(api: api)
        let nav = UINavigationController(rootViewController: list)
        let form = SupplierAddViewController(api: api)
        nav.pushViewController(form, animated: false)
        form.loadViewIfNeeded()
        return (form, nav, list)
    }

    func testTheCompanyNameIsRequiredBeforeAnythingIsSent() throws {
        let options = try fixture("supplier_directory_options")
        SupplierStubProtocol.handler = { _ in (200, options) }
        let (form, _, _) = form(api())
        wait { form.options != nil }
        let before = SupplierStubProtocol.requests.count
        form.save()
        XCTAssertEqual(SupplierStubProtocol.requests.count, before, "nothing sent")
        let error = try XCTUnwrap(find("suppliers.add.error.name", in: form.view, as: UILabel.self))
        XCTAssertFalse(error.isHidden)
        XCTAssertEqual(error.text, "Enter the supplier company name.")
    }

    func testAddingASupplierChecksForDuplicatesCreatesItAndOpensTheRecord() throws {
        let options = try fixture("supplier_directory_options")
        let none = Data(#"{"success":true,"data":{"duplicates":[]},"request_id":null}"#.utf8)
        let created = try fixture("supplier_directory_created")
        SupplierStubProtocol.handler = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", let p) where p.hasSuffix("/suppliers/options"): return (200, options)
            case ("POST", let p) where p.hasSuffix("/suppliers/duplicate-check"): return (200, none)
            case ("POST", let p) where p.hasSuffix("/suppliers"): return (201, created)
            default: return (200, Data(#"{"success":true,"data":{"suppliers":[],"pagination":{"current_page":1,"last_page":1,"per_page":25,"total":0},"can":{"view":true,"create":true,"view_payment_terms":false}}}"#.utf8))
            }
        }
        let (form, nav, _) = form(api())
        var announced: SupplierDetailEnvelope?
        form.onCreated = { announced = $0 }
        form.presentSheet = { _ in }
        form.fields["name"]?.text = "Cumberland Tool Rental"
        form.fields["phone"]?.text = "615-555-0123"
        form.fields["primary_contact_name"]?.text = "Pat Quinn"
        form.save()
        wait { announced != nil }

        let create = try XCTUnwrap(SupplierStubProtocol.requests.last { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/suppliers") == true })
        XCTAssertNotNil(create.value(forHTTPHeaderField: "X-Operation-Id"), "a retried create is a replay, never a second supplier")
        let body = try XCTUnwrap(SupplierStubProtocol.body(of: create))
        XCTAssertEqual(body["name"] as? String, "Cumberland Tool Rental")
        XCTAssertEqual(body["primary_contact_name"] as? String, "Pat Quinn")
        XCTAssertNil(body["acknowledge_duplicates"])
        XCTAssertNil(body["payment_terms"])

        XCTAssertEqual(announced?.supplier.name, "Cumberland Tool Rental", "the directory reloads, so it is searchable at once")
        let detail = try XCTUnwrap(nav.topViewController as? SupplierDetailViewController, "the new record opens")
        XCTAssertEqual(detail.envelope?.supplier.status, "Active")
        XCTAssertFalse(nav.viewControllers.contains { $0 is SupplierAddViewController }, "Back returns to the directory, not the form")
    }

    func testALikelyDuplicateOffersTheExistingRecordOrConfirmation() throws {
        let duplicates = try fixture("supplier_directory_duplicates")
        SupplierStubProtocol.handler = { request in
            request.url?.path.hasSuffix("/duplicate-check") == true ? (200, duplicates) : (200, Data(#"{"success":true,"data":{}}"#.utf8))
        }
        let (form, _, _) = form(api())
        var shown: [UIViewController] = []
        form.presentSheet = { shown.append($0) }
        form.fields["name"]?.text = "Smoky Mountain Hydraulics Inc"
        form.save()
        wait { shown.contains { $0 is UIAlertController } }

        let sheet = try XCTUnwrap(shown.compactMap { $0 as? UIAlertController }.first)
        XCTAssertEqual(sheet.title, "This supplier may already be in Kabba")
        XCTAssertTrue(sheet.message?.contains("Smoky Mountain Hydraulics — Knoxville, TN") == true, sheet.message ?? "")
        XCTAssertEqual(sheet.actions.map(\.title), ["Open Smoky Mountain Hydraulics", "Add as a Different Supplier", "Keep Editing"])
        XCTAssertFalse(SupplierStubProtocol.requests.contains { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/suppliers") == true },
                       "nothing is created until the employee decides")
    }

    func testTheServersDuplicateRefusalAlsoReachesTheEmployee() throws {
        let none = Data(#"{"success":true,"data":{"duplicates":[]}}"#.utf8)
        let refused = try fixture("supplier_directory_duplicate_409")
        SupplierStubProtocol.handler = { request in
            if request.url?.path.hasSuffix("/duplicate-check") == true { return (200, none) }
            if request.httpMethod == "POST" { return (409, refused) }
            return (200, Data(#"{"success":true,"data":{}}"#.utf8))
        }
        let (form, _, _) = form(api())
        var shown: [UIViewController] = []
        form.presentSheet = { shown.append($0) }
        form.fields["name"]?.text = "Smoky Mountain Hydraulics LLC"
        form.save()
        wait { !shown.isEmpty }
        XCTAssertEqual((shown.first as? UIAlertController)?.actions.first?.title, "Open Smoky Mountain Hydraulics")
    }

    func testOfflineNothingIsSavedAndTheFormSaysSo() throws {
        SupplierStubProtocol.handler = { _ in nil }
        let (form, nav, _) = form(api())
        form.fields["name"]?.text = "Offline Supply Co"
        form.save()
        let general = try XCTUnwrap(find("suppliers.add.error.general", in: form.view, as: UILabel.self))
        wait { !general.isHidden }
        XCTAssertEqual(general.text, SupplierDirectoryPresentation.offlineAdd)
        XCTAssertTrue(nav.topViewController === form, "the employee keeps what they typed")
        XCTAssertFalse(SupplierStubProtocol.requests.contains { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/suppliers") == true })
    }
}

/// Serves canned responses; nil = the phone is offline. Records every request.
private final class SupplierStubProtocol: URLProtocol {
    static var handler: (URLRequest) -> (Int, Data)? = { _ in nil }
    private(set) static var requests: [URLRequest] = []
    private static var bodies: [String: Data] = [:]
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        handler = { _ in nil }
        requests = []
        bodies = [:]
    }

    static func body(of request: URLRequest) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        guard let key = request.value(forHTTPHeaderField: "X-Stub-Id"), let data = bodies[key] else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        let id = UUID().uuidString
        recorded.setValue(id, forHTTPHeaderField: "X-Stub-Id")
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            body = data
        }
        Self.lock.lock()
        Self.requests.append(recorded)
        if let body { Self.bodies[id] = body }
        let handler = Self.handler
        Self.lock.unlock()

        guard let (status, data) = handler(request), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
