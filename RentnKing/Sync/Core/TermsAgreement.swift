//
//  TermsAgreement.swift
//  RentnKing — Sync Core (Foundation + CryptoKit; no UIKit)
//
//  Dispatch offline Phase 5. An order's FROZEN Terms & Conditions agreement,
//  exactly as Laravel issues it (GET orders/terms/{order}, and the `terms`
//  block of a Delivery mission package): the standard terms and the original
//  products' addenda frozen on the order at creation, plus the customer
//  substitution, bound to the order by its identity.
//
//  The agreement belongs to the order. Nothing on this phone ever rebuilds it
//  from templates; a template edit never changes an existing order's
//  agreement, so a correctly captured signature never goes stale.
//
//  Identity (kabba-order-terms v1 — the same bytes as
//  app/Services/Terms/TermsAgreement.php; both pinned by the shared vectors in
//  terms_agreement_identity.json):
//
//    identity = "v1:" + lowercase-hex(SHA-256(canonical bytes))
//
//    kabba-order-terms:v1
//    order:<L>:<order unique_id>
//    customer_name:<L>:<customer name>
//    entries:<N>
//    entry:<i> / is_global:<1|0> / content:<L>:… / signature_block:<L>:…
//
//  <L> is the UTF-8 BYTE length. Line endings are normalized (CRLF and lone
//  CR → LF) for hashing only; nothing else is normalized. The phone VERIFIES
//  an agreement — recomputes its identity from the payload it will render —
//  before showing or signing it. The identity never depends on rendered HTML.
//

import Foundation
import CryptoKit

struct TermsAgreement: Codable, Equatable {

    struct Entry: Codable, Equatable {
        var isGlobal: Bool
        var content: String
        var signatureBlock: String

        enum CodingKeys: String, CodingKey {
            case isGlobal = "is_global", content, signatureBlock = "signature_block"
        }
    }

    static let identityPrefix = "v1:"
    static let canonicalHeader = "kabba-order-terms:v1"
    /// What becomes a required approval checkbox (non-global entries only).
    static let approvalPlaceholder = "[customer_approval][/customer_approval]"

    var identity: String
    var orderUniqueId: String
    /// Presentation only — not part of the identity.
    var orderNumber: String
    var customerName: String
    var approvalsRequired: Int
    var entries: [Entry]

    enum CodingKeys: String, CodingKey {
        case identity, orderUniqueId = "order_unique_id", orderNumber = "order_number",
             customerName = "customer_name", approvalsRequired = "approvals_required", entries
    }

    // MARK: - Decoding (the server's `agreement` object)

    /// nil when the object is not an agreement (missing keys / wrong types). Decoding never
    /// verifies — call `isVerified(forOrder:)` before showing or signing.
    static func decode(_ value: JSONValue?) -> TermsAgreement? {
        guard let value = value, case .object = value,
              let identity = value["identity"]?.stringValue,
              let order = value["order_unique_id"]?.stringValue, !order.isEmpty,
              let name = value["customer_name"]?.stringValue,
              let approvals = value["approvals_required"]?.intValue, approvals >= 0,
              let list = value["entries"]?.arrayValue else { return nil }
        var entries: [Entry] = []
        for item in list {
            guard case .object = item, case .bool(let isGlobal)? = item["is_global"] else { return nil }
            entries.append(Entry(isGlobal: isGlobal,
                                 content: item["content"]?.stringValue ?? "",
                                 signatureBlock: item["signature_block"]?.stringValue ?? ""))
        }
        return TermsAgreement(identity: identity, orderUniqueId: order, orderNumber: value["order_number"]?.stringValue ?? "",
                              customerName: name, approvalsRequired: approvals, entries: entries)
    }

    // MARK: - Identity

    static func isIdentity(_ value: String) -> Bool {
        guard value.hasPrefix(identityPrefix) else { return false }
        let hex = value.dropFirst(identityPrefix.count)
        return hex.count == 64 && hex.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    static func canonicalBytes(orderUniqueId: String, customerName: String, entries: [Entry]) -> Data {
        var bytes = Data((canonicalHeader + "\n").utf8)
        bytes.append(field("order", orderUniqueId))
        bytes.append(field("customer_name", customerName))
        bytes.append(Data("entries:\(entries.count)\n".utf8))
        for (index, entry) in entries.enumerated() {
            bytes.append(Data("entry:\(index)\nis_global:\(entry.isGlobal ? "1" : "0")\n".utf8))
            bytes.append(field("content", entry.content))
            bytes.append(field("signature_block", entry.signatureBlock))
        }
        return bytes
    }

    static func computeIdentity(orderUniqueId: String, customerName: String, entries: [Entry]) -> String {
        let digest = SHA256.hash(data: canonicalBytes(orderUniqueId: orderUniqueId, customerName: customerName, entries: entries))
        return identityPrefix + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The identity recomputed from this payload (what the phone would render).
    var recomputedIdentity: String {
        Self.computeIdentity(orderUniqueId: orderUniqueId, customerName: customerName, entries: entries)
    }

    /// The payload is intact (its identity recomputes), it is well formed, and it is THIS order's.
    func isVerified(forOrder orderUniqueId: String) -> Bool {
        !orderUniqueId.isEmpty
            && self.orderUniqueId == orderUniqueId
            && Self.isIdentity(identity)
            && !entries.isEmpty
            && approvalsRequired == Self.countApprovals(entries)
            && recomputedIdentity == identity
    }

    static func countApprovals(_ entries: [Entry]) -> Int {
        entries.filter { !$0.isGlobal }.reduce(0) { $0 + $1.content.components(separatedBy: approvalPlaceholder).count - 1 }
    }

    // MARK: - Canonicalization helpers

    private static func field(_ name: String, _ value: String) -> Data {
        let normalized = Data(normalizedLineEndings(value).utf8)
        var data = Data("\(name):\(normalized.count):".utf8)
        data.append(normalized)
        data.append(0x0A)
        return data
    }

    /// CRLF and lone CR → LF, scalar by scalar (never grapheme-based, never Unicode-normalized).
    static func normalizedLineEndings(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var pendingCR = false
        for scalar in text.unicodeScalars {
            if pendingCR {
                out.append("\n")
                pendingCR = false
                if scalar == "\n" { continue }
            }
            if scalar == "\r" { pendingCR = true; continue }
            out.append(scalar)
        }
        if pendingCR { out.append("\n") }
        return String(out)
    }
}

// MARK: - The `terms` block (package and live endpoint)

struct TermsBlock: Equatable {
    enum AgreementStatus: String, Equatable {
        case available
        case unavailable
        case notRequired = "not_required"
        case notSignable = "not_signable"
    }

    /// The order's terms_status as the server reported it ("Pending", "Accepted", "Exempt", …).
    var status: String
    var pageUrl: String
    /// nil = the server did not report one (a failed section, a Return package, a pre-Phase-5 server).
    var agreementStatus: AgreementStatus?
    var unavailableReason: String?
    /// Decoded, NOT yet verified.
    var agreement: TermsAgreement?

    static func decode(_ value: JSONValue?) -> TermsBlock? {
        guard let value = value, case .object = value else { return nil }
        return TermsBlock(status: value["status"]?.stringValue ?? "",
                          pageUrl: value["page_url"]?.stringValue ?? "",
                          agreementStatus: value["agreement_status"]?.stringValue.flatMap(AgreementStatus.init(rawValue:)),
                          unavailableReason: value["unavailable_reason"]?.stringValue,
                          agreement: TermsAgreement.decode(value["agreement"]))
    }
}

// MARK: - Rendering (presentation only — never hashed)

/// The agreement body, built the way Laravel's TermsContentHelper builds it (the standard terms
/// with the addenda in place of `[product_terms]`, then the signature block), with INERT markers
/// where the page puts its approval checkboxes and sign button. The signing page sanitizes this
/// body and replaces the markers with the app's own controls.
enum TermsAgreementRenderer {
    static let approvalMarker = "<span data-kabba-approval></span>"
    static let signMarker = "<span data-kabba-sign></span>"

    static func bodyHTML(_ agreement: TermsAgreement) -> String {
        let global = agreement.entries.first { $0.isGlobal }
        let addenda = agreement.entries.filter { !$0.isGlobal }
            .map { $0.content.replacingOccurrences(of: TermsAgreement.approvalPlaceholder, with: approvalMarker) }
            .joined(separator: "\n")
        guard let standard = global else { return addenda }
        let body = standard.content.replacingOccurrences(of: "[product_terms][/product_terms]", with: addenda)
        let signature = standard.signatureBlock
            .replacingOccurrences(of: "[customer_name][/customer_name]", with: escape(agreement.customerName))
            .replacingOccurrences(of: "[customer_signature][/customer_signature]", with: signMarker)
        return body + signature
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
