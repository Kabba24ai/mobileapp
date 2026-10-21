//
//  QueueLineBoardHostedTests.swift
//  RentnKingHostedTests — MOBILE-QUALITY-01 items 07 and 08 on the real Queue Line board:
//  every card shows exactly Paid or Pending beside the equipment's availability (with or
//  without equipment, on a new or an older board), and the order number opens that order's
//  existing Order Details, with Back returning to the same tab and scroll position.
//

import XCTest
import UIKit
import ObjectMapper
@testable import RentnKing

final class QueueLineBoardHostedTests: XCTestCase {

    private var remembered: (id: String?, name: String?) = (nil, nil)

    override func setUp() {
        super.setUp()
        remembered = QueueLineStoreMemory.remembered()
        QueueLineStoreMemory.remember(storeUniqueId: nil, name: QueueLineStoreMemory.allName)   // All stores
    }

    override func tearDown() {
        QueueLineStoreMemory.remember(storeUniqueId: remembered.id, name: remembered.name ?? QueueLineStoreMemory.allName)
        super.tearDown()
    }

    private func item(_ n: Int, payment: [String: Any]?, legacy: String? = "No Payment Recorded", equipment: Bool = true,
                      urgency: String = "today", date: String = "2026-10-20") -> QueueLineModel {
        var json: [String: Any] = [
            "order_product_unique_id": "ORD-SCH-MQ01-\(n)",
            "order_unique_id": "ORD-MQ01-\(n)",
            "order_number": "#\(5090 + n)",
            "customer_name": "Customer \(n)",
            "status": "pending",
            "urgency": urgency,
            "store": ["unique_id": "STR-NORTH", "name": "North Store"],
            "product": ["unique_id": "PRD-\(n)", "name": "Skid Steer \(n)"],
            "delivery": ["type_label": "Delivery", "transport_mode": "Truck", "date": date, "time": "09:00"],
        ]
        if let legacy { json["payment_label"] = legacy }
        if let payment { json["payment"] = payment }
        if equipment {
            json["equipment"] = ["unique_id": "EQP-\(n)", "display_id": "SS-\(n)", "name": "Skid \(n)", "status": "available", "rental_ready": "Rental Ready"]
        }
        return QueueLineModel(JSON: json)!
    }

    private func board(_ items: [QueueLineModel]) -> (UINavigationController, QueueLineViewController) {
        let screen = QueueLineViewController()
        let nav = UINavigationController(rootViewController: screen)
        screen.loadViewIfNeeded()
        screen.view.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        screen.arrQueueLine = items
        screen.renderLanes()
        screen.view.layoutIfNeeded()
        return (nav, screen)
    }

    private func find<T: UIView>(_ type: T.Type, id: String, in view: UIView) -> T? {
        if let match = view as? T, match.accessibilityIdentifier == id { return match }
        for sub in view.subviews { if let hit = find(type, id: id, in: sub) { return hit } }
        return nil
    }

    private func texts(in view: UIView) -> [String] {
        var out: [String] = []
        if let label = view as? UILabel, let text = label.text { out.append(text) }
        for sub in view.subviews { out += texts(in: sub) }
        return out
    }

    private func scroller(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, !(scroll is UITableView) { return scroll }
        for sub in view.subviews { if let hit = scroller(in: sub) { return hit } }
        return nil
    }

    // MARK: - Item 08

    func testEveryCardShowsExactlyPaidOrPendingBesideItsAvailability() throws {
        let paid = item(1, payment: ["status": "paid", "label": "Paid", "basis": "on_account", "needs_review": false])
        let review = item(2, payment: ["status": "pending", "label": "Pending", "basis": "needs_review", "needs_review": true,
                                       "review_reason": "Marked On Account, but the customer has no approved credit account."])
        let olderBoard = item(3, payment: nil, legacy: "Account")          // a board served before the classification
        let noEquipment = item(4, payment: ["status": "pending", "label": "Pending", "basis": "unpaid", "needs_review": false], equipment: false)
        let (_, screen) = board([paid, review, olderBoard, noEquipment])

        func badge(_ model: QueueLineModel) throws -> UIView {
            try XCTUnwrap(find(UIView.self, id: "queueLine.payment.\(model.itemOrderProductUniqueId)", in: screen.view))
        }
        XCTAssertEqual(texts(in: try badge(paid)), ["Paid"])
        XCTAssertEqual(texts(in: try badge(review)), ["Pending ⚠︎"])
        XCTAssertEqual(try badge(review).accessibilityLabel,
                       "Payment Pending, needs review: Marked On Account, but the customer has no approved credit account.")
        XCTAssertEqual(texts(in: try badge(olderBoard)), ["Pending"], "an older board never reads On Account as Paid")
        XCTAssertEqual(texts(in: try badge(noEquipment)), ["Pending"], "a card without equipment still shows its classification")

        // Beside the availability badge, on the same row.
        let row = try XCTUnwrap(try badge(paid).superview as? UIStackView)
        XCTAssertEqual(row.axis, .horizontal)
        XCTAssertTrue(row.arrangedSubviews.contains { texts(in: $0) == ["Available"] }, "Paid sits beside Available")
    }

    /// Owner decision 2026-10-21: Kabba orders the board — scheduled date first, then Paid before
    /// Pending on the same date. The phone draws the cards in exactly that order and never
    /// regroups them by payment.
    func testCardsKeepKabbasDateFirstOrderAndAreNeverRegroupedByPayment() throws {
        func paid(_ yes: Bool) -> [String: Any] { ["status": yes ? "paid" : "pending", "label": yes ? "Paid" : "Pending", "needs_review": false] }
        let feed = [
            item(1, payment: paid(false), urgency: "overdue", date: "2026-10-17"),
            item(2, payment: paid(true), urgency: "overdue", date: "2026-10-19"),
            item(3, payment: paid(false), urgency: "overdue", date: "2026-10-19"),
            item(4, payment: paid(true), urgency: "today", date: "2026-10-20"),
            item(5, payment: paid(false), urgency: "today", date: "2026-10-20"),
            item(6, payment: paid(true), urgency: "tomorrow", date: "2026-10-21"),
            item(7, payment: paid(false), urgency: "rush", date: "2026-10-21"),
        ]
        let (_, screen) = board(feed)
        let tops = try feed.map { model -> CGFloat in
            let link = try XCTUnwrap(find(UIButton.self, id: "queueLine.order.\(model.itemOrderProductUniqueId)", in: screen.view))
            return link.convert(CGPoint.zero, to: screen.view).y
        }
        XCTAssertEqual(tops, tops.sorted(), "cards appear in Kabba's order")
        XCTAssertEqual(Set(tops).count, tops.count, "one card per line")
    }

    // MARK: - Item 07

    func testTheOrderNumberOpensOrderDetailsAndBackReturnsToTheSamePlace() throws {
        let items = (1...14).map { item($0, payment: ["status": $0 % 2 == 0 ? "paid" : "pending", "label": "x", "needs_review": false]) }
        let (nav, screen) = board(items)
        let scroll = try XCTUnwrap(scroller(in: screen.view))
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height, "the board must scroll for this test")
        let deep = CGPoint(x: 0, y: min(600, scroll.contentSize.height - scroll.bounds.height))
        scroll.setContentOffset(deep, animated: false)

        let target = items[9]
        let link = try XCTUnwrap(find(UIButton.self, id: "queueLine.order.\(target.itemOrderProductUniqueId)", in: screen.view))
        XCTAssertEqual(link.attributedTitle(for: .normal)?.string, "#5100")
        XCTAssertEqual(link.accessibilityLabel, "Open order #5100")
        link.sendActions(for: .touchUpInside)
        link.sendActions(for: .touchUpInside)       // a double tap
        XCTAssertEqual(nav.viewControllers.count, 2, "a double tap opens Order Details once")

        let details = try XCTUnwrap(nav.topViewController as? OrderDetailsViewController, "the app's own Order Details, never a browser")
        XCTAssertEqual(details.strOrderUniqueId, "ORD-MQ01-10")
        XCTAssertEqual(details.strOrderID, "#5100")
        XCTAssertTrue(nav.viewControllers.first === screen, "the board stays underneath")

        // Back, then the refresh that follows the return rebuilds the cards.
        nav.popViewController(animated: false)
        scroll.setContentOffset(.zero, animated: false)          // what a rebuild can do to the offset
        screen.renderLanes()
        XCTAssertEqual(scroll.contentOffset.y, deep.y, accuracy: 0.5, "same place on the same tab")
    }

    func testTheUpdateButtonStillOpensAssemblyReviewNotOrderDetails() throws {
        let (nav, screen) = board([item(1, payment: ["status": "paid", "label": "Paid", "needs_review": false])])
        let update = try XCTUnwrap(findUpdate(in: screen.view))
        update.sendActions(for: .touchUpInside)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(nav.topViewController is OrderDetailsViewController, "Update keeps its own destination")
    }

    private func findUpdate(in view: UIView) -> QueueLineUpdateButton? {
        if let button = view as? QueueLineUpdateButton { return button }
        for sub in view.subviews { if let hit = findUpdate(in: sub) { return hit } }
        return nil
    }
}
