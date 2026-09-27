import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Driver Delivery Process Flow (2026-09-27), spec §8 — Load Map & Go records
/// On My Way first (durable, identical online and offline) and only then
/// navigates: Apple Maps when service exists, otherwise the Service Offline
/// state in the app's own offline language. Never a pretend map, never a block.
final class LoadMapAndGoDecisionTests: XCTestCase {

    func testOnlineOpensMaps() {
        XCTAssertEqual(LoadMapAndGoDecision.outcome(reachable: true), .openMaps)
    }

    func testOfflineShowsTheServiceOfflineState() {
        XCTAssertEqual(LoadMapAndGoDecision.outcome(reachable: false), .serviceOffline)
    }

    func testTheWordingIsTheSpecsAndSaysTheStatusIsSaved() {
        XCTAssertEqual(LoadMapAndGoDecision.serviceOfflineTitle, "Service Offline")
        XCTAssertEqual(LoadMapAndGoDecision.serviceOfflineMessage,
                       "Navigation needs cellular or Wi-Fi service. Your On My Way status is saved on this phone and will sync automatically.")
    }
}
