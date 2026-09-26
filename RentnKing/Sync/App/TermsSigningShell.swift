//
//  TermsSigningShell.swift
//  RentnKing — Sync App layer
//
//  Dispatch offline Phase 5. Builds the local page the existing Terms &
//  Conditions screen shows for an order's VERIFIED frozen agreement — online
//  and offline alike — from bundled resources (TermsSigning/): the page, its
//  style, its script and the site's own signature pad (signature_pad 5.0.10,
//  MIT, LICENSE-signature_pad.txt). No network, no remote assets.
//
//  The agreement body (TermsAgreementRenderer, inert markers) travels as a
//  JSON string the page sanitizes before inserting; a fresh CSP nonce per
//  load means only the page's own two scripts can run.
//

import Foundation

enum TermsSigningShell {

    /// The WKScriptMessageHandler name the page posts a signing to.
    static let messageHandlerName = "kabbaTermsSigned"

    enum Resource: String, CaseIterable {
        case page = "terms-signing.html"
        case style = "terms-signing.css"
        case script = "terms-signing.js"
        case signaturePad = "signature_pad.umd.min.js"
    }

    /// nil when a bundled resource is missing (the screen then says the terms can't be shown).
    static func html(for agreement: TermsAgreement, bundle: Bundle = .main, nonce: String = newNonce()) -> String? {
        var parts: [Resource: String] = [:]
        for resource in Resource.allCases {
            let name = (resource.rawValue as NSString).deletingPathExtension
            let ext = (resource.rawValue as NSString).pathExtension
            guard let url = bundle.url(forResource: name, withExtension: ext),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            parts[resource] = text
        }
        guard let page = parts[.page], let css = parts[.style], let js = parts[.script], let pad = parts[.signaturePad],
              let payload = scriptSafeJSON([
                  "body": TermsAgreementRenderer.bodyHTML(agreement),
                  "identity": agreement.identity,
                  "approvals_required": agreement.approvalsRequired,
              ]) else { return nil }

        return page
            .replacingOccurrences(of: "{{NONCE}}", with: nonce)
            .replacingOccurrences(of: "{{CSS}}", with: css.replacingOccurrences(of: "</", with: "<\\/"))
            .replacingOccurrences(of: "{{ORDER_NUMBER}}", with: TermsAgreementRenderer.escape(agreement.orderNumber))
            .replacingOccurrences(of: "{{SIGNATURE_PAD}}", with: scriptSafe(withoutSourceMap(pad)))
            .replacingOccurrences(of: "{{PAYLOAD_JSON}}", with: payload)
            .replacingOccurrences(of: "{{SHELL_JS}}", with: scriptSafe(js))
    }

    static func newNonce() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    /// JSON that cannot end its <script> element or break a JavaScript string.
    static func scriptSafeJSON(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return scriptSafe(json)
    }

    private static func scriptSafe(_ text: String) -> String {
        text.replacingOccurrences(of: "</", with: "<\\/")
            .replacingOccurrences(of: "<!--", with: "<\\!--")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private static func withoutSourceMap(_ js: String) -> String {
        js.components(separatedBy: "\n").filter { !$0.hasPrefix("//# sourceMappingURL") }.joined(separator: "\n")
    }
}
