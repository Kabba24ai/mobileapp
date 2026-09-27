import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Driver Delivery Process Flow (2026-09-27), spec §10 — ONE pure router for the
/// customer-site screens. Main Order is the hub; every step returns there or to
/// the next missing step; nothing after departure ever returns to the Assembly
/// Review; the yard band (before departure, Delivery) keeps today's review rule.
final class CustomerSiteRouterTests: XCTestCase {

    private func route(_ step: CustomerSiteStep, stage: DeliveryWorkflowStage = .arrived, isDeliveryLeg: Bool = true,
                       videoMet: Bool = true, checklistComplete: Bool = true) -> CustomerSiteRoute {
        CustomerSiteRouter.afterStep(step, stage: stage, isDeliveryLeg: isDeliveryLeg,
                                     videoRequirementMet: videoMet, checklistComplete: checklistComplete)
    }

    // MARK: - §10.2 the matrix, stage ≥ On My Way

    func testLicenseAndTermsReturnToMainOrder() {
        for stage in [DeliveryWorkflowStage.onMyWay, .arrived] {
            XCTAssertEqual(route(.license, stage: stage, videoMet: false, checklistComplete: false), .mainOrder)
            XCTAssertEqual(route(.terms, stage: stage, videoMet: false, checklistComplete: false), .mainOrder)
        }
    }

    func testChecklistSaveGoesToVideoOnlyWhileTheVideoIsMissing() {
        XCTAssertEqual(route(.checklistPrepared, videoMet: false), .video)
        XCTAssertEqual(route(.checklistPrepared, videoMet: true), .mainOrder)
        XCTAssertEqual(route(.checklistPrepared, stage: .onMyWay, videoMet: false, checklistComplete: false), .video)
    }

    func testChecklistSubmitGoesToVideoOnlyWhileTheVideoIsMissing() {
        XCTAssertEqual(route(.checklistCompleted, videoMet: false), .video)
        XCTAssertEqual(route(.checklistCompleted, videoMet: true), .mainOrder)
    }

    func testVideoReturnsToTheChecklistOnlyWhileItIsIncomplete() {
        XCTAssertEqual(route(.video, checklistComplete: false), .checklist)
        XCTAssertEqual(route(.video, checklistComplete: true), .mainOrder)
    }

    func testNothingAfterDepartureRoutesToTheReview() {
        for stage in [DeliveryWorkflowStage.onMyWay, .arrived, .delivered] {
            for step in [CustomerSiteStep.license, .terms, .checklistPrepared, .checklistCompleted, .video] {
                for videoMet in [false, true] {
                    for complete in [false, true] {
                        XCTAssertNotEqual(route(step, stage: stage, videoMet: videoMet, checklistComplete: complete), .assemblyReview,
                                          "stage=\(stage) step=\(step) video=\(videoMet) complete=\(complete)")
                    }
                }
            }
        }
    }

    // MARK: - The yard band (before departure, Delivery): today's rule, untouched

    func testBeforeDepartureEveryDeliveryStepKeepsTheReviewRule() {
        for stage in [DeliveryWorkflowStage.assemblyReview, .driverChecklist] {
            for step in [CustomerSiteStep.license, .terms, .checklistPrepared, .checklistCompleted, .video] {
                XCTAssertEqual(route(step, stage: stage, videoMet: false, checklistComplete: false), .assemblyReview, "stage=\(stage) step=\(step)")
            }
        }
    }

    // MARK: - Return (§13): no review, same Video ↔ Checklist hop, Main Order otherwise

    func testReturnNeverUsesTheReviewAndFollowsTheSameHop() {
        for stage in [DeliveryWorkflowStage.assemblyReview, .driverChecklist, .onMyWay, .arrived] {
            XCTAssertEqual(route(.checklistPrepared, stage: stage, isDeliveryLeg: false, videoMet: false), .video, "stage=\(stage)")
            XCTAssertEqual(route(.checklistPrepared, stage: stage, isDeliveryLeg: false, videoMet: true), .mainOrder)
            XCTAssertEqual(route(.checklistCompleted, stage: stage, isDeliveryLeg: false, videoMet: false), .video)
            XCTAssertEqual(route(.checklistCompleted, stage: stage, isDeliveryLeg: false, videoMet: true), .mainOrder)
            XCTAssertEqual(route(.video, stage: stage, isDeliveryLeg: false, checklistComplete: false), .checklist)
            XCTAssertEqual(route(.video, stage: stage, isDeliveryLeg: false, checklistComplete: true), .mainOrder)
            XCTAssertNotEqual(route(.license, stage: stage, isDeliveryLeg: false), .assemblyReview)
        }
    }

    // MARK: - Loop check (§10.2): every hop consumes a requirement

    func testTheVideoChecklistHopTerminates() {
        // Save (video missing) → Video → (checklist not complete) → Checklist → Submit → Main Order.
        var videoMet = false
        var checklistComplete = false
        var trail: [CustomerSiteRoute] = []

        var next = route(.checklistPrepared, videoMet: videoMet, checklistComplete: checklistComplete)
        trail.append(next)                       // .video
        videoMet = true                          // the driver films it
        next = route(.video, videoMet: videoMet, checklistComplete: checklistComplete)
        trail.append(next)                       // .checklist
        checklistComplete = true                 // the driver submits
        next = route(.checklistCompleted, videoMet: videoMet, checklistComplete: checklistComplete)
        trail.append(next)                       // .mainOrder

        XCTAssertEqual(trail, [.video, .checklist, .mainOrder])
    }
}
