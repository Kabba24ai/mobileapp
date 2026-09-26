//
//  TermsScreenPresentation.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Dispatch offline Phase 5. What the (one, app-owned, local-first) Terms &
//  Conditions screen shows for an order, decided in ONE pure function:
//
//    • the order's terms are Exempt / Accepted → say so;
//    • a healthy terms.sign for this order at the verified identity →
//      "Signed on this phone" (the engine never deduplicates: no second capture);
//    • a VERIFIED agreement — the live copy when the phone is online, else the
//      stored one → the local signing page;
//    • an agreement that does not verify (its identity does not recompute, or
//      it is another order's) → "Unable to Verify Order Terms — Refresh the
//      Order Before Signing" — nothing is rendered or signable;
//    • the order has no trustworthy stored agreement → say so (never rebuilt) —
//      online from the live answer, offline from the server's last report;
//    • nothing held: offline → "not downloaded yet"; online and the server has
//      no agreement endpoint (an older server) → the hosted page, as before.
//

import Foundation

enum TermsScreenPresentation: Equatable {
    case notRequired
    case alreadyAccepted
    case signedOnThisPhone(SyncState)
    case document(TermsAgreement)
    case unableToVerify
    case agreementUnavailable
    case notDownloaded
    case couldNotLoad
    case hostedPage(URL)
    case unavailable

    /// The screen's live GET orders/terms/{order}, when one was made.
    enum Live: Equatable {
        case block(TermsBlock)
        /// The server has no agreement endpoint (a pre-Phase-5 server).
        case unsupported
        /// Transport or server failure.
        case failed
    }

    struct Inputs {
        var orderUniqueId: String
        /// The order's terms_status as the calling screen knows it ("Pending", "Accepted", "Exempt").
        var knownTermsStatus: String
        /// nil = no live request was made (offline).
        var live: Live?
        /// The newest VERIFIED agreement this phone holds for the order (TermsAgreementStore).
        var stored: TermsAgreement?
        /// The server's last word (a package or a live answer) is that the order has NO trustworthy
        /// agreement to sign (TermsAgreementStore.isUnavailable).
        var storedUnavailable: Bool = false
        var operations: [SyncOperation]
        var signUrl: String
    }

    static func resolve(_ inputs: Inputs) -> TermsScreenPresentation {
        var liveBlock: TermsBlock?
        if case .block(let block)? = inputs.live { liveBlock = block }

        let status = (liveBlock?.status).flatMap { $0.isEmpty ? nil : $0 } ?? inputs.knownTermsStatus
        if status == "Exempt" { return .notRequired }
        if status == "Accepted" { return .alreadyAccepted }

        // The agreement to show: the live one when the server answered, else the stored copy.
        let agreement: TermsAgreement?
        if let block = liveBlock {
            switch block.agreementStatus {
            case .available?:
                guard let live = block.agreement, live.isVerified(forOrder: inputs.orderUniqueId) else { return .unableToVerify }
                agreement = live
            case .unavailable?, .notSignable?:
                return .agreementUnavailable
            case .notRequired?:
                return .alreadyAccepted
            case nil:
                agreement = inputs.stored
            }
        } else {
            agreement = inputs.stored
        }

        if let verified = agreement, !verified.isVerified(forOrder: inputs.orderUniqueId) { return .unableToVerify }

        let signed = EffectiveFieldState.healthyTermsSignatures(in: inputs.operations, orderUniqueId: inputs.orderUniqueId,
                                                                termsIdentity: agreement?.identity ?? "")
        if let newest = signed.max(by: { $0.queuedAt < $1.queuedAt }) { return .signedOnThisPhone(newest.state) }

        if let verified = agreement { return .document(verified) }
        // Not "not downloaded": there is none. An older server's hosted page (.unsupported) still wins.
        if inputs.storedUnavailable, inputs.live != .unsupported { return .agreementUnavailable }

        switch inputs.live {
        case nil:
            return .notDownloaded
        case .failed?:
            return .couldNotLoad
        case .unsupported?:
            return hostedURL(inputs.signUrl).map { .hostedPage($0) } ?? .unavailable
        case .block?:
            return .couldNotLoad
        }
    }

    /// A usable hosted signing link (the pre-Phase-5 page), never a force-unwrap.
    static func hostedURL(_ signUrl: String) -> URL? {
        let trimmed = signUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false else { return nil }
        return url
    }
}
