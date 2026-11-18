//
//  LocalLicenseTests.swift
//  KabbaSyncCoreTests — MOBILE-QUALITY-01 item 06: the driver's license this phone saved
//  is what the license screens show (never hidden by an older server record), keeps its
//  expiration, follows its sync state, and a Save never uploads the same copy twice.
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class LocalLicenseTests: XCTestCase {

    private func license(_ side: String, order: String = "ORD-LIC", state: SyncState = .pending,
                         expiry: String? = nil, employee: String? = nil, queuedAt: TimeInterval = 0,
                         mediaURL: String? = nil) -> SyncOperation {
        var payload: [String: JSONValue] = ["side": .string(side), "type": .string("license"), "order_unique_id": .string(order)]
        if let expiry { payload["license_expiry_date"] = .string(expiry) }
        if let employee { payload["auto_inject_by"] = .string(employee) }
        var op = SyncOperation(type: EffectiveFieldState.licenseMediaType, capturedAt: Date(timeIntervalSince1970: queuedAt),
                               queuedAt: Date(timeIntervalSince1970: queuedAt),
                               identity: SyncBusinessIdentity(orderUniqueId: order),
                               payload: .object(payload),
                               assets: [SyncAsset(relativePath: "license-\(order)/\(side)-\(queuedAt).jpg", mimeType: "image/jpeg", fieldName: "media")])
        op.state = state
        if state == .synced {
            op.acknowledgment = SyncAcknowledgment(acknowledgedAt: Date(), statusCode: 200, requestId: nil, replayed: false, serverReceivedAt: nil,
                                                   data: mediaURL.map { .object(["media": .object(["url": .string($0)])]) })
        }
        return op
    }

    func testEachSideIsItsLatestLocalCopyWithItsStateAndExpiry() {
        let ops = [
            license("front", state: .synced, expiry: "2027-01-01", queuedAt: 1, mediaURL: "https://kabba/old-front.jpg"),
            license("front", state: .pending, expiry: "2028-04-01", queuedAt: 5),
            license("back", state: .needsAttention, expiry: "2028-04-01", queuedAt: 6),
            license("front", order: "ORD-OTHER", queuedAt: 9),
        ]
        let sides = LocalLicense.sides(orderUniqueId: "ORD-LIC", operations: ops)
        XCTAssertEqual(sides["front"]?.state, .pending, "the newest copy wins, never an older one")
        XCTAssertEqual(sides["front"]?.statusLabel, "Pending Sync")
        XCTAssertEqual(sides["back"]?.statusLabel, "Needs Attention", "a refused copy stays visible for review")
        XCTAssertEqual(LocalLicense.expiryDate(sides), "2028-04-01")
        XCTAssertEqual(LocalLicense.displayExpiry("2028-04-01"), "April 2028")
        XCTAssertNil(LocalLicense.displayExpiry("soon"))
    }

    func testASyncedCopyPointsAtKabbasFileAndARetiredOneNeverCounts() {
        var retired = license("back", queuedAt: 9)
        retired.state = .superseded
        let sides = LocalLicense.sides(orderUniqueId: "ORD-LIC", operations: [
            license("front", state: .synced, queuedAt: 1, mediaURL: "https://kabba/front.jpg"),
            retired,
        ])
        XCTAssertEqual(sides["front"]?.statusLabel, "Synced")
        XCTAssertEqual(sides["front"]?.serverMediaURL, "https://kabba/front.jpg")
        XCTAssertNil(sides["back"])
    }

    func testASaveQueuesOnlyWhatChanged() {
        let existing = LocalLicense.sides(orderUniqueId: "ORD-LIC", operations: [
            license("front", expiry: "2028-04-01", employee: "12", queuedAt: 1),
            license("back", expiry: "2028-04-01", employee: "12", queuedAt: 2),
        ])
        // Reopened and saved again without retaking anything: nothing new is uploaded.
        XCTAssertEqual(LocalLicense.sidesToQueue(changed: [], expiryDate: nil, autoInjectBy: nil, existing: existing), [])
        XCTAssertEqual(LocalLicense.sidesToQueue(changed: [], expiryDate: "2028-04-01", autoInjectBy: "12", existing: existing), [])
        // One side retaken.
        XCTAssertEqual(LocalLicense.sidesToQueue(changed: ["back"], expiryDate: nil, autoInjectBy: nil, existing: existing), ["back"])
        // New details: every side whose copy does not carry them.
        XCTAssertEqual(LocalLicense.sidesToQueue(changed: [], expiryDate: "2029-01-01", autoInjectBy: "12", existing: existing), ["front", "back"])
        XCTAssertEqual(LocalLicense.sidesToQueue(changed: [], expiryDate: "2028-04-01", autoInjectBy: "14", existing: existing), ["front", "back"])
        // Nothing on the phone yet (the images came from the order record): only details send them.
        XCTAssertEqual(LocalLicense.sidesToQueue(changed: [], expiryDate: nil, autoInjectBy: nil, existing: [:]), [])
        XCTAssertEqual(LocalLicense.sidesToQueue(changed: [], expiryDate: "2028-04-01", autoInjectBy: nil, existing: [:]), ["front", "back"])
    }

    func testOnlyAWaitingCopyOfTheSameSideIsReplaced() {
        let waiting = license("front", state: .pending, queuedAt: 1)
        var sending = license("front", state: .pending, queuedAt: 2)
        sending.state = .syncing
        let refused = license("front", state: .needsAttention, queuedAt: 3)
        let back = license("back", state: .pending, queuedAt: 4)
        let other = license("front", order: "ORD-OTHER", state: .pending, queuedAt: 5)
        XCTAssertEqual(LocalLicense.replacedBy(side: "front", orderUniqueId: "ORD-LIC", operations: [waiting, sending, refused, back, other]),
                       [waiting.id], "never one in flight, never a refused one, never the other side or another order")
    }
}
