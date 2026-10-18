//
//  NextStopStateTests.swift
//  RentnKingTests — KabbaSyncCore (Foundation only)
//
//  The Next Stop shop transition: the ONE stop in a driver's workday that
//  Dispatch does not already model. Order legs and Manual Dispatch tasks are
//  canonical missions and keep their own records — this state exists only so a
//  trip back to the shop survives Maps, backgrounding and relaunch.
//
//  Dates round-trip through KabbaISO8601, which writes whole seconds, so the
//  fixtures below are whole-second instants on purpose.
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class NextStopStateTests: XCTestCase {

    private let shop = NextStopShop(uniqueId: "STR-BONAQUA",
                                    name: "Bon Aqua",
                                    fullAddress: "100 Yard Rd, Bon Aqua, TN, 37025")
    private let other = NextStopShop(uniqueId: "STR-WAVERLY",
                                     name: "Waverly",
                                     fullAddress: "9 Depot St, Waverly, TN, 37185")

    private let selectedAt = Date(timeIntervalSince1970: 1_792_000_000)
    private let arrivedAt  = Date(timeIntervalSince1970: 1_792_001_800)

    // MARK: Transitions

    func testSelectShopCapturesShopAndTimestamp() {
        let state = NextStopTransition.selectShop(shop, at: selectedAt)

        XCTAssertEqual(state, .shopSelected(shop: shop, selectedAt: selectedAt))
        XCTAssertEqual(state.shop, shop)
    }

    func testSelectShopReplacesAnEarlierChoiceRatherThanStacking() {
        // The driver changes their mind before leaving: one shop stop, not two.
        let first = NextStopTransition.selectShop(shop, at: selectedAt)
        let second = NextStopTransition.selectShop(other, at: arrivedAt)

        XCTAssertEqual(first.shop, shop)
        XCTAssertEqual(second, .shopSelected(shop: other, selectedAt: arrivedAt))
    }

    func testArrivePromotesSelectedShopAndPreservesSelectedAt() {
        let selected = NextStopTransition.selectShop(shop, at: selectedAt)

        let arrived = NextStopTransition.arrive(selected, at: arrivedAt)

        XCTAssertEqual(arrived, .arrivedAtShop(shop: shop, selectedAt: selectedAt, arrivedAt: arrivedAt))
        XCTAssertEqual(arrived.shop, shop, "Arriving must not forget which shop the driver drove to.")
    }

    func testArriveFromIdleIsANoop() {
        XCTAssertEqual(NextStopTransition.arrive(.idle, at: arrivedAt), .idle,
                       "There is no shop to arrive at, so arrival cannot invent one.")
    }

    func testArriveAgainKeepsTheFirstArrival() {
        let arrived = NextStopTransition.arrive(NextStopTransition.selectShop(shop, at: selectedAt), at: arrivedAt)

        let again = NextStopTransition.arrive(arrived, at: arrivedAt.addingTimeInterval(600))

        XCTAssertEqual(again, arrived, "A second Arrived tap must not move the recorded arrival.")
    }

    func testFinishShopStopReturnsIdle() {
        let selected = NextStopTransition.selectShop(shop, at: selectedAt)
        let arrived = NextStopTransition.arrive(selected, at: arrivedAt)

        XCTAssertEqual(NextStopTransition.finishShopStop(selected), .idle)
        XCTAssertEqual(NextStopTransition.finishShopStop(arrived), .idle)
        XCTAssertEqual(NextStopTransition.finishShopStop(.idle), .idle)
    }

    func testIdleHasNoShop() {
        XCTAssertNil(NextStopState.idle.shop)
    }

    // MARK: Codable

    func testEveryStateRoundTrips() throws {
        let encoder = KabbaISO8601.makeEncoder()
        let decoder = KabbaISO8601.makeDecoder()

        let states: [NextStopState] = [
            .idle,
            .shopSelected(shop: shop, selectedAt: selectedAt),
            .arrivedAtShop(shop: shop, selectedAt: selectedAt, arrivedAt: arrivedAt),
        ]

        for state in states {
            let decoded = try decoder.decode(NextStopState.self, from: try encoder.encode(state))
            XCTAssertEqual(decoded, state, "\(state) must survive a disk round trip unchanged.")
        }
    }

    func testTheEncodingCarriesAnExplicitKindDiscriminator() throws {
        // Explicit keys, not compiler-synthesized enum payload keys: this file
        // is read back by future app versions.
        let data = try KabbaISO8601.makeEncoder().encode(NextStopState.shopSelected(shop: shop, selectedAt: selectedAt))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["kind"] as? String, "shopSelected")
        XCTAssertNotNil(json["shop"])
        XCTAssertNotNil(json["selectedAt"])
    }

    func testAnUnknownFutureKindDecodesAsIdleInsteadOfThrowing() throws {
        // A downgrade must not strand the driver in an undecodable state.
        let data = Data(#"{"kind":"somethingNewer"}"#.utf8)

        XCTAssertEqual(try KabbaISO8601.makeDecoder().decode(NextStopState.self, from: data), .idle)
    }
}
