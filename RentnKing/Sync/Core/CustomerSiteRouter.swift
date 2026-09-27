//
//  CustomerSiteRouter.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Driver Delivery Process Flow (2026-09-27), spec §10 — ONE pure router for
//  the customer-site screens (License, Terms, Equipment Checklist, Video),
//  replacing stack inspection and the per-screen booleans. Main Order is the
//  hub: every step returns there, or to the next missing step. After departure
//  nothing ever returns to the Assembly Review (that single rule closes RC6);
//  before departure, on the Delivery leg, the yard's review rule stands.
//
//  "Go to X" means: pop to X if it is on the stack, else push it — so the stack
//  stays finite (Main Order → Checklist → Video → (pop) Checklist → Submit →
//  (pop) Main Order). The screens own that mechanic; this file owns the choice.
//

import Foundation

/// The customer-site step that just completed.
enum CustomerSiteStep: Equatable {
    case license
    case terms
    /// The equipment checklist was Saved (prepared) — the yard's staging Save on the driver road.
    case checklistPrepared
    /// The equipment checklist was Submitted (completed).
    case checklistCompleted
    /// A delivery video / photo was captured.
    case video
}

enum CustomerSiteRoute: Equatable {
    /// Order Details — the hub.
    case mainOrder
    /// The media capture screen (the delivery video is still missing).
    case video
    /// The equipment checklist (still incomplete after the video).
    case checklist
    /// Today's yard rule (`ChecklistEntry.returnToReview` with its fallbacks) — before departure only.
    case assemblyReview
}

enum CustomerSiteRouter {

    /// Where the driver goes after `step`. For a Delivery still in the yard
    /// (stage < On My Way) the review rule is untouched; from On My Way on, and
    /// for every Return step, the customer-site matrix of §10.2 applies.
    static func afterStep(_ step: CustomerSiteStep,
                          stage: DeliveryWorkflowStage,
                          isDeliveryLeg: Bool,
                          videoRequirementMet: Bool,
                          checklistComplete: Bool) -> CustomerSiteRoute {
        if isDeliveryLeg && stage < .onMyWay {
            return .assemblyReview
        }

        switch step {
        case .license, .terms:
            return .mainOrder
        case .checklistPrepared, .checklistCompleted:
            return videoRequirementMet ? .mainOrder : .video
        case .video:
            return checklistComplete ? .mainOrder : .checklist
        }
    }
}
