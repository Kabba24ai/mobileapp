//
//  TermsAgreementClient.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Dispatch offline Phase 5. The one live read the Terms & Conditions screen
//  makes when it opens with a connection — GET orders/terms/{order}, the
//  order's FROZEN agreement (the same builder a Delivery package carries). It
//  replaces the hosted page's load; nothing polls. A verified answer is saved
//  for the company that was signed in when the request was SENT, and only when
//  no newer copy is already on this phone (field ledger `terms` stamp).
//

import Foundation

enum TermsAgreementClient {

    static func fetch(orderUniqueId: String, completion: @escaping (TermsScreenPresentation.Live) -> Void) {
        guard let client = KabbaSync.client else { completion(.failed); return }
        let tenant = KabbaSync.termsAgreements?.currentTenantKey
        let askedAt = Date()
        let encoded = orderUniqueId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? orderUniqueId

        client.send(method: "GET", path: "orders/terms/\(encoded)") { result in
            let answer: TermsScreenPresentation.Live
            switch result {
            case .failure:
                answer = .failed
            case .success(let response) where response.isSuccessStatus:
                guard let block = TermsBlock.decode(JSONValue.parse(response.body)?["data"]) else { answer = .failed; break }
                if let agreement = block.agreement, agreement.isVerified(forOrder: orderUniqueId),
                   let tenant = tenant, let store = KabbaSync.termsAgreements {
                    DispatchOfflineSync.saveLiveCopy(.terms, orderUniqueId: orderUniqueId, askedAt: askedAt, tenantKey: tenant) {
                        (try? store.save(agreement, tenantKey: tenant)) != nil
                    }
                } else if block.agreementStatus == .unavailable || block.agreementStatus == .notSignable,
                          let tenant = tenant, let store = KabbaSync.termsAgreements {
                    // Remembered, so offline later the screen still says "Terms are unavailable".
                    DispatchOfflineSync.saveLiveCopy(.terms, orderUniqueId: orderUniqueId, askedAt: askedAt, tenantKey: tenant) {
                        (try? store.recordUnavailable(orderUniqueId: orderUniqueId, tenantKey: tenant)) != nil
                    }
                }
                answer = .block(block)
            case .success(let response):
                let error = APIErrorClassifier.classify(statusCode: response.statusCode, body: response.body, headers: response.headers)
                // A 404 that is not "this order does not exist" is a server without the endpoint.
                answer = response.statusCode == 404 && error.code != "ORDER_NOT_FOUND" ? .unsupported : .failed
            }
            DispatchQueue.main.async { completion(answer) }
        }
    }
}
