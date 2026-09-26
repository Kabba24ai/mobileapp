//
//  DispatchOfflineTermsHostedTests.swift
//  RentnKingHostedTests — runs inside the RentnKing app (Simulator or device)
//
//  Dispatch offline Phase 5 through the REAL app pieces: a stored Delivery
//  package (the shared Laravel fixture) is bridged into the real
//  TermsAgreementStore; the real Terms & Conditions screen, offline, renders
//  the order's frozen agreement as an inert local page in its WKWebView; the
//  customer signs through the page; the signature is durable in the real Sync
//  Engine before the screen advances; relaunch, reopen and completion rules
//  all hold; and the page is inert (no script, handler, javascript: URL,
//  frame, object, remote load or navigation from the agreement).
//
//  No real server: tenants are *.invalid hosts; the screen is told it is
//  offline through its reachability seam.
//

import XCTest
import WebKit
import UIKit
@testable import RentnKing

final class DispatchOfflineTermsHostedTests: XCTestCase {

    private let urlA = "https://tenant-a.invalid/api/admin/v1/"
    private let urlB = "https://tenant-b.invalid/api/admin/v1/"
    private var tenantA: String { DispatchOfflineTenant.key(baseURL: URL(string: urlA)!) }

    private let orderUid = "ORD-BJVZ-CSDO"        // the fixture's order
    private let opuid = "ORD-SCH-P8KU-S6A9"        // the fixture's mission line
    private var savedBaseURL: String?
    private var root: URL!
    private var window: UIWindow?
    private var createdOperations: [String] = []

    override func setUp() {
        super.setUp()
        savedBaseURL = UserDefaults.standard.baseURL
        root = FileManager.default.temporaryDirectory.appendingPathComponent("p5-hosted-\(UUID().uuidString)", isDirectory: true)
        UserDefaults.standard.baseURL = urlA
        discardFixtureSignings() // a test that failed mid-way must never leak a signing into the next one
    }

    /// Every terms.sign / terms.accept this suite's fixture order could have left in the app's real engine.
    private func discardFixtureSignings() {
        for op in KabbaSync.engine?.snapshot() ?? []
        where (op.type == "terms.sign" || op.type == "terms.accept") && op.identity.orderUniqueId == orderUid {
            try? KabbaSync.engine?.discard(operationId: op.id)
        }
    }

    override func tearDown() {
        for id in createdOperations { try? KabbaSync.engine?.discard(operationId: id) }
        discardFixtureSignings()
        if let agreements = KabbaSync.termsAgreements {
            for tenant in [tenantA, DispatchOfflineTenant.key(baseURL: URL(string: urlB)!)] {
                try? FileManager.default.removeItem(at: agreements.directory.appendingPathComponent(tenant, isDirectory: true))
            }
        }
        window?.isHidden = true
        window = nil
        UserDefaults.standard.baseURL = savedBaseURL
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    // MARK: - Fixture → a stored, ready Delivery mission for company A

    private func fixturePackage() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KabbaSyncCore/Fixtures/dispatch_offline_packages.json")
        let root = try XCTUnwrap(JSONValue.parse(try Data(contentsOf: url)))
        return try XCTUnwrap(root["data"]?["packages"]?.arrayValue?.first)
    }

    /// Stores the fixture package for company A and runs the real bridge into the real agreement store.
    @discardableResult
    private func bridgeFixture(sectionsTerms: String? = nil) throws -> DispatchOfflineFieldBridge.Report {
        let store = try DispatchOfflineMissionStore(rootDirectory: root, baseURL: URL(string: urlA)!)
        let contexts = try ChecklistContextStore(rootDirectory: root, tenantKey: { KabbaTenantScope.currentKey })
        let bridge = DispatchOfflineFieldBridge(store: store, contexts: contexts, agreements: KabbaSync.termsAgreements,
                                                writer: DispatchOfflineOrderBridge.shared, operations: { [] }, currentEmployee: { nil })
        let missionKey = "\(opuid):delivery"
        var value = try fixturePackage()
        if let status = sectionsTerms {
            value = value.p5Setting(["sections", "terms"], .string(status)).p5Setting(["terms", "agreement"], .null)
        }
        guard case .success(let package) = DispatchOfflinePackage.validate(value, requested: [missionKey]) else {
            throw XCTSkip("fixture package does not validate")
        }
        let file = try store.writePackage(package, cachedAt: Date(), serverObservedAt: Date())
        var index = DispatchOfflineIndex.empty(tenantKey: store.tenantKey, baseURL: DispatchOfflineTenant.normalizedBaseURL(URL(string: urlA)!))
        index.everCommitted = true
        index.entries = [.init(missionKey: missionKey, orderProductUniqueId: opuid, leg: .delivery, effectiveDate: "2026-09-25",
                               serverRevision: package.revision, readyRevision: package.revision, packageFile: file)]
        try store.commit(index)
        let report = bridge.bridge(index: store.loadIndex())
        XCTAssertEqual(bridge.isFieldReady(store.loadIndex().entry(missionKey)!), sectionsTerms == nil)
        return report
    }

    /// Polls the main run loop until `condition` holds (the web view and the engine are asynchronous).
    @discardableResult
    private func waitUntil(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line,
                           _ description: String, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail("Timed out waiting for \(description)", file: file, line: line)
        return false
    }

    // MARK: - The real screen, offline

    private final class RecordingDelegate: NSObject, TermsDelegate {
        /// The server recorded the acceptance (the hosted page's thank-you step).
        var serverAccepted = 0
        /// Signed on this phone (terms.sign) — never reported as the server's acceptance.
        var calls = 0
        var operationsAtCall: [SyncOperation] = []
        func termsSucess(selectIndex: Int) {
            serverAccepted += 1
        }
        func termsSignedOnThisPhone(selectIndex: Int) {
            calls += 1
            operationsAtCall = KabbaSync.engine?.snapshot() ?? []
        }
    }

    private func openTerms(delegate: RecordingDelegate? = nil, termsStatus: String = "Pending") throws -> TermsAndConditionViewController {
        let vc = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "TermsAndConditionViewController") as? TermsAndConditionViewController)
        vc.isOrderFrom = true
        vc.strOrderUniqueId = orderUid
        vc.strProductUniqueId = opuid
        vc.strOrderNumber = "1650"
        vc.strTermsStatus = termsStatus
        vc.signUrl = "https://tenant-a.invalid/terms-and-conditions/\(orderUid)/mobile"
        vc.isReachable = { false }             // completely offline
        vc.delegate = delegate
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: vc)
        window.makeKeyAndVisible()
        self.window = window
        waitUntil(timeout: 5, "the screen to resolve") { vc.presentation != nil }
        return vc
    }

    @discardableResult
    private func js(_ webView: WKWebView, _ script: String, file: StaticString = #filePath, line: UInt = #line) -> Any? {
        let done = expectation(description: "js")
        var out: Any?
        webView.evaluateJavaScript(script) { value, error in
            if let error = error { XCTFail("JS failed: \(error) — \(script)", file: file, line: line) }
            out = value
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return out
    }

    private func waitForPage(_ webView: WKWebView) {
        waitUntil(timeout: 15, "the local page") {
            var ready = false
            let done = self.expectation(description: "ready")
            webView.evaluateJavaScript("document.readyState === 'complete' && !!document.getElementById('terms-dynamic-content')") { value, _ in
                ready = (value as? Bool) == true
                done.fulfill()
            }
            self.wait(for: [done], timeout: 5)
            return ready
        }
    }

    private let signScript = """
        document.getElementById('open-signature-btn').click();
        window.kabbaTerms.pad.fromData([{points: [{x: 20, y: 30, pressure: 0.5, time: 1}, {x: 90, y: 70, pressure: 0.5, time: 20},
                                                  {x: 160, y: 40, pressure: 0.5, time: 40}, {x: 220, y: 90, pressure: 0.5, time: 60}]}]);
        document.querySelector('#modal #save-signature').click();
        document.querySelectorAll('input.customer_initials_checkbox').forEach(function (b) { b.click(); });
        document.getElementById('submit-button').click();
        true;
        """

    // MARK: - 1. Never opened online → signed offline → durable → relaunch → completion

    func testANeverOpenedMissionIsSignedOfflineDurablyAndCountsForDelivery() throws {
        try bridgeFixture()
        let stored = try XCTUnwrap(KabbaSync.termsAgreements?.current(orderUniqueId: orderUid), "bridged, verified")

        let delegate = RecordingDelegate()
        let vc = try openTerms(delegate: delegate)
        XCTAssertEqual(vc.presentation, .document(stored), "offline: the stored, verified agreement")
        waitForPage(vc.objWebKit)

        // Full terms content renders offline, with the existing approval + sign controls.
        let text = js(vc.objWebKit, "document.getElementById('terms-dynamic-content').textContent") as? String ?? ""
        XCTAssertTrue(text.contains("Standard terms."))
        XCTAssertTrue(text.contains("Addendum."))
        XCTAssertTrue(text.contains("Cody Cash"), "the frozen customer substitution")
        XCTAssertEqual(js(vc.objWebKit, "document.querySelectorAll('input.customer_initials_checkbox').length") as? Int, 1)
        XCTAssertEqual(js(vc.objWebKit, "!!document.getElementById('open-signature-btn')") as? Bool, true)

        // The screen's own page can go nowhere, and a signing naming another document is refused.
        js(vc.objWebKit, "window.location.href = 'https://example.com/elsewhere'; true;")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(vc.objWebKit.url?.absoluteString ?? "about:blank", "about:blank", "no navigation away from the agreement")
        vc.didReceiveSigning(["identity": "v1:" + String(repeating: "0", count: 64), "approvals_confirmed": 1,
                              "signature": "data:image/png;base64," + Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1]).base64EncodedString()])
        XCTAssertEqual(delegate.calls, 0, "a forged identity never records or advances")
        XCTAssertFalse(KabbaSync.engine?.snapshot().contains { $0.type == "terms.sign" && $0.identity.orderUniqueId == orderUid } ?? true)

        // Sign through the page.
        js(vc.objWebKit, signScript)
        waitUntil(timeout: 10, "termsSignedOnThisPhone") { delegate.calls == 1 }
        XCTAssertEqual(delegate.serverAccepted, 0, "a phone signature is never reported as the server's acceptance")

        // Durable BEFORE the screen advanced.
        let signed = delegate.operationsAtCall.filter { $0.type == "terms.sign" && $0.identity.orderUniqueId == orderUid }
        XCTAssertEqual(signed.count, 1)
        let op = try XCTUnwrap(signed.first)
        createdOperations.append(op.id)
        XCTAssertEqual(TermsSignOperationBuilder.termsIdentity(of: op), stored.identity)
        XCTAssertEqual(op.payload["approvals_confirmed"]?.intValue, 1)
        let assetsDirectory = try XCTUnwrap(KabbaSync.engine?.store.assetsDirectory)
        let png = try Data(contentsOf: assetsDirectory.appendingPathComponent(try XCTUnwrap(op.assets.first).relativePath))
        XCTAssertEqual(png.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]), "the web pad's PNG")
        XCTAssertNotNil(UIImage(data: png))

        // Leave and reopen: signed on this phone, no second capture.
        let reopened = try openTerms()
        if case .signedOnThisPhone? = reopened.presentation {} else { XCTFail("reopened: \(String(describing: reopened.presentation))") }

        // Force-quit / relaunch: a fresh store on the engine's folder still holds the signature.
        let reloaded = try FileSyncOperationStore(rootDirectory: assetsDirectory.deletingLastPathComponent()).loadAll()
        XCTAssertTrue(reloaded.contains { $0.id == op.id })

        // Completion follows the existing rules: T&C is satisfied, so the override never lists it.
        let inputs = LegCompletionInputs(orderUniqueId: orderUid, orderProductUniqueId: opuid, orderProductUniqueIds: [opuid],
                                         licenseConfirmed: true, deliveryMediaConfirmed: true, deliveryChecklistConfirmed: true,
                                         termsIdentity: stored.identity)
        let decision = LegCompletionEvaluator.evaluate(leg: .delivery, inputs: inputs, operations: reloaded)
        XCTAssertEqual(decision.status(.termsAndConditions), .satisfied)
        XCTAssertTrue(decision.canProceed)
        XCTAssertFalse(decision.overrideSections.terms)

        // Reconnect: ONE multipart POST with the identity, the operation id and one signature part.
        let request = try TermsSignRequestFactory.request(for: op)
        XCTAssertEqual(request.path, "orders/terms/\(orderUid)/accept")
        XCTAssertEqual(request.headers["X-Operation-Id"], op.id)
        let body = try SyncMultipartBuilder.build(fields: request.jsonBody, assets: request.attachments, assetsDirectory: assetsDirectory)
        defer { try? FileManager.default.removeItem(at: body.fileURL) }
        let multipart = String(decoding: try Data(contentsOf: body.fileURL), as: UTF8.self)
        XCTAssertEqual(multipart.components(separatedBy: "name=\"signature_media\"").count - 1, 1)
        XCTAssertTrue(multipart.contains(stored.identity))
        XCTAssertTrue(multipart.contains(op.id))
    }

    // MARK: - 2. Inert rendering

    private final class Recorder: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var messages: [Any] = []
        var navigations: [String] = []
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) { messages.append(message.body) }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            navigations.append(action.request.url?.absoluteString ?? "")
            decisionHandler(action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }

    func testTheAgreementIsRenderedInertAndSigningStillWorks() throws {
        let post = "window.webkit.messageHandlers.kabbaTermsSigned.postMessage({evil: true})"
        let hostile = """
            <p id="clause">Clause one.</p>
            <script>\(post)</script>
            <img id="remote" src="https://example.com/pixel.png" onerror="\(post)">
            <a id="jslink" href="javascript:\(post)">tap me</a>
            <a id="weblink" href="https://example.com/elsewhere">elsewhere</a>
            <div id="clicky" onclick="\(post)">click</div>
            <iframe src="https://example.com"></iframe><object data="https://example.com/x.swf"></object><embed src="https://example.com/y">
            <svg onload="\(post)"><script>\(post)</script></svg>
            <form action="https://example.com/steal"><input name="x" value="y"><button>go</button></form>
            <meta http-equiv="refresh" content="0;url=https://example.com/away"><base href="https://example.com/">
            <style>@import url(https://example.com/x.css);</style>
            <p>{{SHELL_JS}} {{PAYLOAD_JSON}} {{NONCE}}</p>
            <span data-kabba-approval="forged"></span><span data-kabba-approval></span><span data-kabba-sign></span>
            <span id="save-signature">a colliding id</span><span id="close-modal"></span>
            [customer_approval][/customer_approval]
            """
        let entries = [TermsAgreement.Entry(isGlobal: false, content: hostile, signatureBlock: "")]
        let agreement = TermsAgreement(identity: TermsAgreement.computeIdentity(orderUniqueId: "ORD-INERT", customerName: "Jane", entries: entries),
                                       orderUniqueId: "ORD-INERT", orderNumber: "#1", customerName: "Jane", approvalsRequired: 1, entries: entries)
        XCTAssertTrue(agreement.isVerified(forOrder: "ORD-INERT"))
        let html = try XCTUnwrap(TermsSigningShell.html(for: agreement))
        XCTAssertEqual(TermsSigningShell.fill("a{{X}}b{{Y}}c{{Z}}", ["X": "{{Y}}", "Y": "1"]), "a{{Y}}b1c{{Z}}",
                       "one pass: substituted text is never scanned again")

        let recorder = Recorder()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(recorder, name: TermsSigningShell.messageHandlerName)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        webView.navigationDelegate = recorder
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.addSubview(webView)
        window.makeKeyAndVisible()
        self.window = window
        webView.loadHTMLString(html, baseURL: nil)
        waitForPage(webView)

        XCTAssertEqual(js(webView, "document.getElementById('clause').textContent") as? String, "Clause one.", "the content is there")
        XCTAssertEqual(js(webView, "document.querySelectorAll('#terms-dynamic-content script, #terms-dynamic-content iframe, #terms-dynamic-content object, #terms-dynamic-content embed, #terms-dynamic-content svg, #terms-dynamic-content form, #terms-dynamic-content meta, #terms-dynamic-content base, #terms-dynamic-content button:not([data-kabba-control]), #terms-dynamic-content input:not([data-kabba-control])').length") as? Int, 0)
        XCTAssertEqual(js(webView, "document.querySelectorAll('#terms-dynamic-content [data-kabba-control]').length") as? Int, 3,
                       "only the app's own controls: one approval checkbox, the sign button, the remove-signature button")
        XCTAssertEqual(js(webView, "Array.prototype.some.call(document.querySelectorAll('#terms-dynamic-content *'), function (el) { return Array.prototype.some.call(el.attributes, function (a) { return a.name.indexOf('on') === 0; }); })") as? Bool, false, "no inline handlers")
        XCTAssertEqual(js(webView, "document.getElementById('jslink').hasAttribute('href') || document.getElementById('weblink').hasAttribute('href')") as? Bool, false, "no javascript: or web links")
        XCTAssertEqual(js(webView, "document.getElementById('remote') === null && document.querySelectorAll('#terms-dynamic-content [src]:not([src^=\"data:\"]), #terms-dynamic-content [srcset]').length === 0") as? Bool, true,
                       "no remote image (an image with no alt text and nothing to load is simply not shown)")
        XCTAssertEqual(js(webView, "document.querySelectorAll('#terms-dynamic-content style').length") as? Int, 0, "no remote stylesheet import")

        js(webView, "document.getElementById('jslink').click(); document.getElementById('weblink').click(); document.getElementById('clicky').click(); true;")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(recorder.messages.isEmpty, "the agreement can never post a signing")
        XCTAssertEqual(recorder.navigations.filter { $0 != "about:blank" }, [], "no navigation from the agreement")

        // The CSP is its own wall: a script or inline handler added to the page later still never runs.
        js(webView, "var s = document.createElement('script'); s.textContent = 'window.kabbaInjected = 1;'; document.body.appendChild(s);"
                    + "var d = document.createElement('div'); d.setAttribute('onclick', 'window.kabbaHandler = 1;'); document.body.appendChild(d); d.click(); true;")
        XCTAssertEqual(js(webView, "typeof window.kabbaInjected") as? String, "undefined", "CSP blocks an injected script")
        XCTAssertEqual(js(webView, "typeof window.kabbaHandler") as? String, "undefined", "CSP blocks inline handlers")

        // …and the customer can still sign it.
        js(webView, "document.getElementById('open-signature-btn') !== null")
        js(webView, signScript)
        waitUntil(timeout: 5, "the signing message") { !recorder.messages.isEmpty }
        let message = try XCTUnwrap(recorder.messages.first as? [String: Any])
        XCTAssertEqual(message["identity"] as? String, agreement.identity)
        XCTAssertEqual((message["approvals_confirmed"] as? NSNumber)?.intValue, 1)
        XCTAssertNotNil(TermsAndConditionViewController.signaturePNG(fromDataURL: message["signature"] as? String ?? ""))
    }

    // MARK: - 3. Verification failure, missing agreement, tenancy

    func testAnAgreementThatDoesNotVerifyIsNeverShownOrSignable() throws {
        let vc = try openTerms()
        var tampered = try XCTUnwrap(TermsAgreement.decode(try fixturePackage()["terms"]?["agreement"]))
        tampered.entries[0].content = "<p>Not what was frozen.</p>"
        let block = TermsBlock(status: "Pending", pageUrl: "", agreementStatus: .available, unavailableReason: nil, agreement: tampered)

        vc.apply(TermsScreenPresentation.resolve(vc.presentationInputs(live: .block(block))))

        XCTAssertEqual(vc.presentation, .unableToVerify)
        XCTAssertNil(vc.renderedAgreement, "nothing rendered, nothing signable")
        XCTAssertNotNil(vc.boundaryView)
        vc.didReceiveSigning(["identity": tampered.identity, "approvals_confirmed": 1, "signature": "data:image/png;base64,AAAA"])
        XCTAssertFalse(KabbaSync.engine?.snapshot().contains { $0.type == "terms.sign" && $0.identity.orderUniqueId == orderUid } ?? true)
    }

    func testAPackageWithoutAUsableAgreementSaysNotDownloadedNeverABlankPage() throws {
        try bridgeFixture(sectionsTerms: "failed")
        XCTAssertNil(KabbaSync.termsAgreements?.current(orderUniqueId: orderUid))

        let vc = try openTerms()

        XCTAssertEqual(vc.presentation, .notDownloaded)
        XCTAssertNil(vc.renderedAgreement)
        XCTAssertNotNil(vc.boundaryView, "a clear state, not a blank web view or a spinner")
    }

    /// Phase 5 hardening: offline, an order the server reported as having no trustworthy agreement
    /// says so in the office's words — never "not downloaded".
    func testAnOrderWithoutATrustworthyAgreementSaysTermsAreUnavailableOffline() throws {
        try bridgeFixture(sectionsTerms: "unavailable")
        XCTAssertNil(KabbaSync.termsAgreements?.current(orderUniqueId: orderUid))

        let vc = try openTerms()

        XCTAssertEqual(vc.presentation, .agreementUnavailable)
        XCTAssertNil(vc.renderedAgreement)
        let labels = (vc.boundaryView.map { Self.labels(in: $0) } ?? []).compactMap { $0.text }
        XCTAssertTrue(labels.contains("Terms are unavailable for this order."), "\(labels)")
        XCTAssertTrue(labels.contains("Please contact the office."), "\(labels)")
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("download") }, "never 'not downloaded'")
    }

    private static func labels(in view: UIView) -> [UILabel] {
        ((view as? UILabel).map { [$0] } ?? []) + view.subviews.flatMap { labels(in: $0) }
    }

    // MARK: - 4. A phone signature never becomes an in-memory "Accepted" (Phase 5 hardening)

    /// Order Details and Order List keep the order's server status after a phone signing: the Sync
    /// Engine's operation alone decides, so a signature the server later refuses can never stay
    /// visible — or count for completion — as "Accepted".
    func testAPhoneSigningLeavesTheServerStatusSoARefusalCanNeverStayAccepted() throws {
        let details = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController)
        details.objOrderData = try XCTUnwrap(OrdersListModel(JSON: ["unique_id": orderUid, "terms_status": "Pending"]))
        details.termsSignedOnThisPhone(selectIndex: 0)
        XCTAssertEqual(details.objOrderData.terms_status, "Pending", "Order Details: no in-memory Accepted")

        let list = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "OrderListViewController") as? OrderListViewController)
        list.arrOrderList = [try XCTUnwrap(OrdersListModel(JSON: ["unique_id": orderUid, "terms_status": "Pending"]))]
        list.termsSignedOnThisPhone(selectIndex: 0)
        XCTAssertEqual(list.arrOrderList[0].terms_status, "Pending", "Order List: no in-memory Accepted")
    }

    func testCompanyBNeverSeesCompanyAsAgreementAndAKeepsIt() throws {
        try bridgeFixture()

        UserDefaults.standard.baseURL = urlB
        XCTAssertEqual(try openTerms().presentation, .notDownloaded, "no Company A agreement under Company B")

        UserDefaults.standard.baseURL = urlA
        if case .document? = try openTerms().presentation {} else { XCTFail("back to A: usable offline") }
    }
}

private extension JSONValue {
    func p5Setting(_ path: [String], _ value: JSONValue) -> JSONValue {
        guard let head = path.first else { return value }
        var object = objectValue ?? [:]
        object[head] = (object[head] ?? .object([:])).p5Setting(Array(path.dropFirst()), value)
        return .object(object)
    }
}
