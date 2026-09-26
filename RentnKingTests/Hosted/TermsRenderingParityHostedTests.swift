//
//  TermsRenderingParityHostedTests.swift
//  RentnKingHostedTests — runs inside the RentnKing app (Simulator or device)
//
//  Dispatch offline Phase 5 hardening: a customer must never sign an agreement
//  whose contractual text the phone silently failed to show. The shared fixture
//  (terms_rendering_parity.json — Laravel pins its web half) is an awkward
//  frozen agreement: nested forms, buttons, a submit input, links (one
//  javascript:), SVG text, scripts, handlers, an iframe, an object, a template,
//  noscript, and approvals inside a link, a form and a button.
//
//  In the same WebKit, side by side:
//    • the WEB page's render (Laravel's own HTML, scripts blocked by CSP);
//    • the PHONE's inert local page (TermsSigningShell, the real page).
//  The phone shows every phrase the web shows, runs nothing, renders the same
//  approvals — each one hit-testable and tickable — and signs the unchanged
//  frozen identity.
//

import XCTest
import WebKit
import UIKit
@testable import RentnKing

final class TermsRenderingParityHostedTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    private func fixture() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KabbaSyncCore/Fixtures/terms_rendering_parity.json")
        return try XCTUnwrap(JSONValue.parse(try Data(contentsOf: url)))
    }

    private func strings(_ value: JSONValue?) -> [String] { (value?.arrayValue ?? []).compactMap { $0.stringValue } }

    private final class Recorder: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var messages: [Any] = []
        var navigations: [String] = []
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) { messages.append(message.body) }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            navigations.append(action.request.url?.absoluteString ?? "")
            decisionHandler(action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }

    @discardableResult
    private func js(_ webView: WKWebView, _ script: String, file: StaticString = #filePath, line: UInt = #line) -> Any? {
        let done = expectation(description: "js")
        var out: Any?
        webView.evaluateJavaScript(script) { value, error in
            if let error = error { XCTFail("JS failed: \(error) — \(script.prefix(120))", file: file, line: line) }
            out = value
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return out
    }

    private func load(_ html: String, recorder: Recorder, in window: UIWindow, x: CGFloat) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(recorder, name: TermsSigningShell.messageHandlerName)
        let webView = WKWebView(frame: CGRect(x: x, y: 0, width: 390, height: 800), configuration: configuration)
        webView.navigationDelegate = recorder
        window.addSubview(webView)
        webView.loadHTMLString(html, baseURL: nil)
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if (js(webView, "document.readyState === 'complete' && !!document.getElementById('terms-dynamic-content')") as? Bool) == true { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return webView
    }

    /// What a reader sees in `root`: its rendered text plus the labels of button/text inputs
    /// (innerText leaves form-control values out). One function for both pages.
    private let visibleTextJS = """
        (function (root) {
          var parts = [root.innerText];
          root.querySelectorAll('input').forEach(function (i) {
            var t = (i.getAttribute('type') || 'text').toLowerCase();
            if (['hidden', 'checkbox', 'radio', 'file', 'image', 'password'].indexOf(t) === -1 && i.getClientRects().length) {
              parts.push(i.value || i.placeholder || '');
            }
          });
          root.querySelectorAll('textarea').forEach(function (t) { if (t.getClientRects().length) { parts.push(t.value); } });
          return parts.join('\\n');
        })(document.getElementById('terms-dynamic-content'))
        """

    private func normalized(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    func testThePhoneShowsEveryContractualPhraseTheWebShowsAndTheSameUsableApprovals() throws {
        let fixture = try fixture()
        let agreement = try XCTUnwrap(TermsAgreement.decode(fixture["agreement"]))
        let identity = try XCTUnwrap(fixture["agreement"]?["identity"]?.stringValue)
        XCTAssertTrue(agreement.isVerified(forOrder: agreement.orderUniqueId), "the fixture's frozen agreement verifies")
        XCTAssertEqual(agreement.identity, identity)
        let approvals = try XCTUnwrap(fixture["agreement"]?["approvals_required"]?.intValue)
        XCTAssertEqual(TermsAgreement.countApprovals(agreement.entries), approvals)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 900))
        window.makeKeyAndVisible()
        self.window = window

        // ── The WEB page's render: Laravel's HTML in the page's own form, scripts blocked. ──
        let webHTML = "<!DOCTYPE html><html><head><meta charset=utf-8>"
            + "<meta http-equiv=\"Content-Security-Policy\" content=\"script-src 'none'; img-src data:; frame-src 'none'; object-src 'none'\">"
            + "<meta name=viewport content='width=device-width, initial-scale=1'><style>.hidden { display: none; }</style></head><body>"
            + "<form id=\"customer-order-sign-form\"><div id=\"terms-dynamic-content\">"
            + (fixture["web_content_html"]?.stringValue ?? "") + "</div></form></body></html>"
        let webRecorder = Recorder()
        let web = load(webHTML, recorder: webRecorder, in: window, x: 0)
        let webText = normalized(js(web, visibleTextJS) as? String ?? "")

        // ── The PHONE's inert local page (the real one). ──
        let phoneRecorder = Recorder()
        let phone = load(try XCTUnwrap(TermsSigningShell.html(for: agreement)), recorder: phoneRecorder, in: window, x: 400)
        let phoneText = normalized(js(phone, visibleTextJS) as? String ?? "")

        // Every phrase a reader of the web page sees is on the phone.
        for phrase in strings(fixture["visible_text"]) {
            XCTAssertTrue(webText.contains(normalized(phrase)), "the fixture is honest — visible on the web: \(phrase)")
            XCTAssertTrue(phoneText.contains(normalized(phrase)), "visible on the phone: \(phrase)")
        }
        for phrase in strings(fixture["phone_also_shows"]) {
            XCTAssertTrue(phoneText.contains(normalized(phrase)), "the phone also shows: \(phrase)")
        }
        for phrase in strings(fixture["never_visible"]) {
            XCTAssertFalse(phoneText.contains(phrase), "never visible on the phone: \(phrase)")
            XCTAssertFalse(webText.contains(phrase), "never visible on the web: \(phrase)")
        }

        // Beyond the listed phrases: every line of the web page's text is on the phone.
        let webLines = (js(web, "document.getElementById('terms-dynamic-content').innerText") as? String ?? "")
            .components(separatedBy: "\n").map(normalized).filter { !$0.isEmpty }
        for line in webLines {
            XCTAssertTrue(phoneText.contains(line), "web line missing on the phone: \(line)")
        }

        // Active content stays disabled: nothing ran, and tapping every element runs nothing either.
        let probe = try XCTUnwrap(fixture["probe"]?.stringValue)
        XCTAssertEqual(js(phone, "typeof window.\(probe)") as? String, "undefined")
        js(phone, "document.querySelectorAll('#terms-dynamic-content *:not([data-kabba-control])').forEach(function (el) { el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true})); el.dispatchEvent(new MouseEvent('mouseover', {bubbles: true})); }); true;")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(js(phone, "typeof window.\(probe)") as? String, "undefined", "no handler, script or javascript: link ran")
        XCTAssertEqual(phoneRecorder.navigations.filter { $0 != "about:blank" }, [], "no navigation")
        XCTAssertTrue(phoneRecorder.messages.isEmpty, "the agreement never posts a signing")
        XCTAssertEqual(js(phone, "document.querySelectorAll('#terms-dynamic-content a, #terms-dynamic-content area, #terms-dynamic-content form, #terms-dynamic-content svg, #terms-dynamic-content math, #terms-dynamic-content script, #terms-dynamic-content iframe, #terms-dynamic-content object, #terms-dynamic-content embed, #terms-dynamic-content template, #terms-dynamic-content button:not([data-kabba-control]), #terms-dynamic-content input:not([data-kabba-control]), #terms-dynamic-content select, #terms-dynamic-content textarea').length") as? Int, 0,
                       "nothing active or submittable is left in the agreement")

        // The same approvals, and each one usable where it sits (a link, a form, a button, plain).
        XCTAssertEqual(js(web, "document.querySelectorAll('input.customer_initials_checkbox').length") as? Int, approvals)
        XCTAssertEqual(js(phone, "document.querySelectorAll('input.customer_initials_checkbox').length") as? Int, approvals)
        let hits = js(phone, """
            JSON.stringify(Array.prototype.map.call(document.querySelectorAll('input.customer_initials_checkbox'), function (box) {
              box.scrollIntoView({block: 'center'});
              var r = box.getBoundingClientRect();
              var hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
              var label = box.closest('label');
              var ok = hit === box || (label !== null && label.contains(hit));
              if (hit) { hit.click(); }
              return [ok, box.checked, label ? label.textContent : ''];
            }));
            """) as? String ?? "[]"
        let rows = (try JSONSerialization.jsonObject(with: Data(hits.utf8))) as? [[Any]] ?? []
        XCTAssertEqual(rows.count, approvals)
        for (index, row) in rows.enumerated() {
            XCTAssertEqual(row[0] as? Bool, true, "approval \(index + 1) is what a tap at its centre reaches")
            XCTAssertEqual(row[1] as? Bool, true, "approval \(index + 1) ticks where it sits")
            XCTAssertEqual(row[2] as? String, "Customer Approved")
        }
        XCTAssertEqual(phoneRecorder.navigations.filter { $0 != "about:blank" }, [], "ticking an approval inside a link navigates nowhere")

        // …and the customer can sign: the frozen identity, unchanged by sanitizing, and every approval.
        js(phone, """
            document.getElementById('open-signature-btn').click();
            window.kabbaTerms.pad.fromData([{points: [{x: 20, y: 30, pressure: 0.5, time: 1}, {x: 90, y: 70, pressure: 0.5, time: 20},
                                                      {x: 160, y: 40, pressure: 0.5, time: 40}]}]);
            document.querySelector('#modal #save-signature').click();
            document.getElementById('submit-button').click();
            true;
            """)
        let deadline = Date().addingTimeInterval(5)
        while phoneRecorder.messages.isEmpty && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        let message = try XCTUnwrap(phoneRecorder.messages.first as? [String: Any])
        XCTAssertEqual(message["identity"] as? String, identity, "sanitizing is presentation: the identity is the frozen one")
        XCTAssertEqual((message["approvals_confirmed"] as? NSNumber)?.intValue, approvals)
    }
    /// Review fixes: nothing in the agreement can become a page overlay or be hidden by the page's own
    /// rules, blocked media leave a visible placeholder (never silently vanish), and form controls keep
    /// their meaning (which option is selected, which box is ticked) as plain text.
    func testTheInertPageKeepsMeaningAndNothingInTheAgreementCanCoverTheControls() throws {
        let content = """
            <p>Clause A (plain).</p>
            <div class="modal">Clause M (a class the page itself uses): still just text.</div>
            <p hidden style="display:block">Clause H (hidden, shown by its own style).</p>
            <img src="https://example.com/terms.png">
            <iframe src="https://example.com/embedded"></iframe>
            <video src="https://example.com/terms.mp4"></video>
            <select><option>Plan A</option><option selected>Plan B</option></select>
            <p><input type="checkbox" checked> Declines the damage waiver.</p>
            <p><input type="checkbox"> Accepts marketing.</p>
            <p><input type="radio" checked> Weekly billing.</p>
            <p><input type="submit"></p>
            [customer_approval][/customer_approval]
            """
        let entries = [TermsAgreement.Entry(isGlobal: false, content: content, signatureBlock: "")]
        let agreement = TermsAgreement(identity: TermsAgreement.computeIdentity(orderUniqueId: "ORD-MEANING", customerName: "Jane", entries: entries),
                                       orderUniqueId: "ORD-MEANING", orderNumber: "#2", customerName: "Jane", approvalsRequired: 1, entries: entries)
        XCTAssertTrue(agreement.isVerified(forOrder: "ORD-MEANING"))

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 900))
        window.makeKeyAndVisible()
        self.window = window
        let recorder = Recorder()
        let page = load(try XCTUnwrap(TermsSigningShell.html(for: agreement)), recorder: recorder, in: window, x: 0)
        let text = normalized(js(page, visibleTextJS) as? String ?? "")

        for phrase in ["Clause A (plain).", "Clause M (a class the page itself uses): still just text.",
                       "Clause H (hidden, shown by its own style).",
                       "[Image not shown on this phone]", "[Embedded content not shown on this phone]",
                       "○ Plan A", "◉ Plan B", "☑ Declines the damage waiver.", "☐ Accepts marketing.", "◉ Weekly billing.", "Submit"] {
            XCTAssertTrue(text.contains(phrase), "shown: \(phrase) — in: \(text)")
        }
        XCTAssertEqual(js(page, "getComputedStyle(document.querySelector('#terms-dynamic-content .modal')).position") as? String, "static",
                       "the agreement's own class='modal' is not the page's overlay")

        // The approval is what a tap reaches, and the page's own pad still opens as its overlay.
        let hit = js(page, """
            (function () {
              var box = document.querySelector('input.customer_initials_checkbox');
              box.scrollIntoView({block: 'center'});
              var r = box.getBoundingClientRect();
              var el = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
              return el === box || box.closest('label').contains(el);
            })()
            """) as? Bool
        XCTAssertEqual(hit, true)
        js(page, "document.getElementById('open-signature-btn').click(); true;")
        XCTAssertEqual(js(page, "getComputedStyle(document.body.querySelector(':scope > .modal')).position") as? String, "fixed")
    }
}
