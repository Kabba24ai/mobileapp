import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Mobile issue #9 — one way to open Order Details. A notification tap names the order by its
/// stable identity and opens it in the Home → Orders stack only when that replaces nothing the
/// employee is working on; otherwise it waits (sign-in, other work) or is dropped (another
/// company, too old). The read receipt is always for ONE order.
final class OrderOpeningTests: XCTestCase {

    private let push: [AnyHashable: Any] = ["order_id": "9661", "order_unique_id": "ORD-UID-9661", "order_number": "9661",
                                            "gcm.message_id": "1", "aps": ["alert": ["title": "New Order Placed 9661"]]]
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func request(_ uid: String = "ORD-UID-9661", tenant: String? = "rentnking", at: Date? = nil) -> OrderOpenRequest {
        OrderOpenRequest(orderUniqueId: uid, orderId: "9661", orderNumber: "9661", tenantKey: tenant, requestedAt: at ?? t0)!
    }

    private func surface(_ stack: [OrderOpenSurface.Screen] = [.home], signedIn: Bool = true, tenant: String? = "rentnking",
                         presented: Bool = false, editing: Bool = false, moving: Bool = false) -> OrderOpenSurface {
        OrderOpenSurface(signedIn: signedIn, tenantKey: tenant, homeStack: stack,
                         somethingPresented: presented, isEditing: editing, isTransitioning: moving)
    }

    private func decide(_ r: OrderOpenRequest, _ s: OrderOpenSurface, after seconds: TimeInterval = 1) -> OrderOpenDecision {
        OrderOpenPolicy.decide(r, on: s, now: t0.addingTimeInterval(seconds))
    }

    // MARK: - The request

    func testAKabbaNewOrderPushNamesTheOrderByItsStableIdentity() throws {
        let r = try XCTUnwrap(OrderOpenRequest(pushUserInfo: push, tenantKey: "rentnking", requestedAt: t0))
        XCTAssertEqual(r.orderUniqueId, "ORD-UID-9661")
        XCTAssertEqual(r.orderId, "9661")
        XCTAssertEqual(r.orderNumber, "9661")
        XCTAssertEqual(r.tenantKey, "rentnking")
    }

    func testNumericPayloadValuesAreAccepted() throws {
        let r = try XCTUnwrap(OrderOpenRequest(pushUserInfo: ["order_unique_id": "U1", "order_id": NSNumber(value: 42),
                                                             "order_number": NSNumber(value: 1042)], tenantKey: nil))
        XCTAssertEqual(r.orderId, "42")
        XCTAssertEqual(r.orderNumber, "1042")
        XCTAssertNil(r.tenantKey, "a tap made while signed out names no company")
    }

    func testAPushThatNamesNoOrderOpensNothing() {
        XCTAssertNil(OrderOpenRequest(pushUserInfo: ["order_id": "12"], tenantKey: "x"))
        XCTAssertNil(OrderOpenRequest(pushUserInfo: ["order_unique_id": "  "], tenantKey: "x"))
        XCTAssertNil(OrderOpenRequest(pushUserInfo: ["order_unique_id": "null"], tenantKey: "x"))
        XCTAssertNil(OrderOpenRequest(pushUserInfo: ["dispatch_wake": "1"], tenantKey: "x"), "a silent Dispatch wake is not an order tap")
    }

    func testMissingIdAndNumberStayUnknownRatherThanEmpty() throws {
        let r = try XCTUnwrap(OrderOpenRequest(pushUserInfo: ["order_unique_id": "U1", "order_id": "", "order_number": "0"], tenantKey: nil))
        XCTAssertNil(r.orderId)
        XCTAssertNil(r.orderNumber)
    }

    // MARK: - Where a tap may open

    func testOnHomeItOpensAsHomeOrdersOrderDetails() {
        XCTAssertEqual(decide(request(), surface([.home])), .open(ordersListIndex: nil))
    }

    func testTheOrdersListOnScreenIsKeptBeneathOrderDetails() {
        XCTAssertEqual(decide(request(), surface([.home, .ordersList])), .open(ordersListIndex: 1))
    }

    func testAnotherOrderOnTopIsReplacedAboveTheSameOrdersList() {
        XCTAssertEqual(decide(request("B"), surface([.home, .ordersList, .orderDetails(orderUniqueId: "A")])),
                       .open(ordersListIndex: 1))
    }

    func testTheSameOrderOnTopIsNeverStackedAgain() {
        XCTAssertEqual(decide(request(), surface([.home, .ordersList, .orderDetails(orderUniqueId: "ORD-UID-9661")])),
                       .alreadyShowing)
    }

    func testAnotherWorkflowIsNeverReplaced() {
        // Dispatch / a mission hub, a checklist above an Order Details, Place Order, Queue Line…
        XCTAssertEqual(decide(request(), surface([.home, .other])), .waitUntilIdle)
        XCTAssertEqual(decide(request(), surface([.home, .ordersList, .orderDetails(orderUniqueId: "A"), .other])), .waitUntilIdle)
        XCTAssertEqual(decide(request(), surface([.home, .other, .orderDetails(orderUniqueId: "A")])), .waitUntilIdle)
    }

    func testASheetAPopUpTypingOrAMovingScreenWaits() {
        XCTAssertEqual(decide(request(), surface(presented: true)), .waitUntilIdle)
        XCTAssertEqual(decide(request(), surface(editing: true)), .waitUntilIdle)
        XCTAssertEqual(decide(request(), surface(moving: true)), .waitUntilIdle)
    }

    func testAStackThatIsNotHomeWaits() {
        XCTAssertEqual(decide(request(), surface([])), .waitUntilIdle)
        XCTAssertEqual(decide(request(), surface([.ordersList])), .waitUntilIdle)
    }

    // MARK: - Sign-in, company, age

    func testSignedOutTheTapWaitsForSignIn() {
        XCTAssertEqual(decide(request(tenant: nil), surface(signedIn: false, tenant: nil)), .waitForSignIn)
    }

    func testATapMadeWhileSignedOutOpensAfterSignInUnderThatSession() {
        // Kabba scopes the lookup to the session; an order of another company is answered "isn't available".
        XCTAssertEqual(decide(request(tenant: nil), surface([.home], tenant: "rentnking")), .open(ordersListIndex: nil))
    }

    func testATapForAnotherCompanyIsNeverShown() {
        XCTAssertEqual(decide(request(tenant: "company-a"), surface([.home], tenant: "company-b")), .discard)
        XCTAssertEqual(decide(request(tenant: "company-a"), surface([.home], tenant: nil)), .discard)
    }

    func testATapThatWaitedTooLongIsDropped() {
        XCTAssertEqual(decide(request(), surface([.home]), after: OrderOpenPolicy.maximumWait - 1), .open(ordersListIndex: nil))
        XCTAssertEqual(decide(request(), surface([.home]), after: OrderOpenPolicy.maximumWait + 1), .discard)
        XCTAssertEqual(decide(request(), surface(signedIn: false), after: OrderOpenPolicy.maximumWait + 1), .discard)
    }

    // MARK: - The read receipt

    func testTheReadReceiptIsAlwaysForOneOrderNeverAll() {
        XCTAssertEqual(OrderNotificationAcknowledgement.orderId(known: "9661", loaded: nil), "9661")
        XCTAssertEqual(OrderNotificationAcknowledgement.orderId(known: "", loaded: 93), "93", "Order Details opened by unique_id only acknowledges once loaded")
        XCTAssertEqual(OrderNotificationAcknowledgement.orderId(known: " 9661 ", loaded: 93), "9661")
        XCTAssertNil(OrderNotificationAcknowledgement.orderId(known: "", loaded: nil), "an empty order_id would mark every notification read")
        XCTAssertNil(OrderNotificationAcknowledgement.orderId(known: "0", loaded: 0))
    }
}
