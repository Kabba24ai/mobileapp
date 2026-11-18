//
//  OrderNotificationEntryHostedTests.swift
//  RentnKingHostedTests — mobile issue #9 (2026-11-14)
//
//  Runs inside the app so the real storyboard screens are exercised. A tapped
//  order notification and a tap in Home → Orders now go through ONE entry
//  (OrderDetailsEntry): same Order Details configuration, opened in the Home
//  tab's own stack (Home → Orders → Order Details, never a separate modal),
//  never stacked twice, never over another workflow, and the Orders list hears
//  about the order by its stable id when Order Details leaves.
//

import XCTest
import ObjectMapper
@testable import RentnKing

final class OrderNotificationEntryHostedTests: XCTestCase {

    private let tenant = "order-entry.invalid"
    private var savedBaseURL: String?
    private var router: OrderNotificationRouter!
    private var tabs: UITabBarController!
    private var homeNav: UINavigationController!
    private var notices: [OrderOpenRequest] = []
    private var signedIn = true
    private var currentTenant: String?

    private let push: [AnyHashable: Any] = ["order_id": "93", "order_unique_id": "ORD-ENTRY-93", "order_number": "9661"]

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedBaseURL = UserDefaults.standard.baseURL
        // No real server: every request these screens might send fails fast.
        UserDefaults.standard.baseURL = "https://order-entry.invalid/api/admin/v1/"
        currentTenant = tenant
        signedIn = true
        notices = []

        let home = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "HomeViewController") as? HomeViewController)
        homeNav = UINavigationController(rootViewController: home)
        tabs = UITabBarController()
        tabs.viewControllers = [homeNav, UINavigationController(rootViewController: UIViewController())]

        router = OrderNotificationRouter()
        router.window = { nil }
        router.rootViewController = { [unowned self] in self.tabs }
        router.hasSession = { [unowned self] in self.signedIn }
        router.tenantKey = { [unowned self] in self.currentTenant }
        router.animated = false
        router.showWaitingNotice = { [unowned self] request, _ in self.notices.append(request) }
    }

    override func tearDown() {
        UserDefaults.standard.baseURL = savedBaseURL
        router = nil
        super.tearDown()
    }

    // MARK: - Builders

    private func ordersList(rows: [[String: Any]] = []) throws -> OrderListViewController {
        let list = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "OrderListViewController") as? OrderListViewController)
        list.arrOrderList = rows.compactMap { OrdersListModel(JSON: $0) }
        list.arrMainOrderList = list.arrOrderList
        return list
    }

    private func types(_ nav: UINavigationController) -> [String] {
        nav.viewControllers.map { String(describing: type(of: $0)) }
    }

    private var topDetails: OrderDetailsViewController? { homeNav.topViewController as? OrderDetailsViewController }

    // MARK: - One configuration for both entries

    func testANotificationAndAnOrdersListTapConfigureOrderDetailsTheSameWay() throws {
        // Organic: Home → Orders → tap the row.
        let organicList = try ordersList(rows: [["id": 92, "unique_id": "ORD-OTHER", "order_number": "9660"],
                                                ["id": 93, "unique_id": "ORD-ENTRY-93", "order_number": "9661"]])
        let organicNav = UINavigationController(rootViewController: UIViewController())
        organicNav.pushViewController(organicList, animated: false)
        OrderDetailsEntry.openFromOrdersList(organicList, order: organicList.arrOrderList[1], row: 1)
        let organic = try XCTUnwrap(organicNav.topViewController as? OrderDetailsViewController)

        // Notification, app open on Home.
        router.handleTap(userInfo: push)
        let tapped = try XCTUnwrap(topDetails)

        XCTAssertEqual(tapped.strOrderUniqueId, organic.strOrderUniqueId)
        XCTAssertEqual(tapped.strOrderID, "9661", "the heading is the order number before the order even loads")
        XCTAssertEqual(tapped.strOrderID, organic.strOrderID)
        XCTAssertEqual(tapped.OrderID, organic.OrderID)
        XCTAssertEqual(tapped.isPresent, organic.isPresent)
        XCTAssertFalse(tapped.isPresent, "never a separate full-screen modal")
        XCTAssertEqual(tapped.isOrderScreen, organic.isOrderScreen)
        XCTAssertEqual(tapped.fromCheckListScreen, organic.fromCheckListScreen)
        XCTAssertTrue(organic.delegate === organicList)
        XCTAssertTrue(tapped.delegate is OrderListViewController, "the Orders list beneath hears about the order")
        XCTAssertEqual(organic.selectIndex, 1)
        XCTAssertEqual(tapped.selectIndex, -1, "a notification never guesses a list row")
    }

    // MARK: - Where a notification opens

    func testATapOnHomeOpensHomeOrdersOrderDetailsInTheHomeTab() throws {
        tabs.selectedIndex = 1   // on Settings: switching tabs keeps Settings' own stack
        router.handleTap(userInfo: push)
        XCTAssertEqual(types(homeNav), ["HomeViewController", "OrderListViewController", "OrderDetailsViewController"])
        XCTAssertTrue(tabs.selectedViewController === homeNav)
        XCTAssertNil(tabs.presentedViewController, "nothing is presented over the app")
        XCTAssertNil(router.pending)
    }

    func testTheOrdersListAlreadyOpenIsKept() throws {
        let list = try ordersList(rows: [["id": 1, "unique_id": "ORD-OTHER", "order_number": "1"]])
        homeNav.pushViewController(list, animated: false)
        router.handleTap(userInfo: push)
        XCTAssertEqual(homeNav.viewControllers.count, 3)
        XCTAssertTrue(homeNav.viewControllers[1] === list)
        XCTAssertTrue(topDetails?.delegate === list)
        XCTAssertEqual(topDetails?.selectIndex, -1, "the order is not in this list: no row")
    }

    func testTheSameOrderIsNeverStackedTwice() throws {
        router.handleTap(userInfo: push)
        let first = try XCTUnwrap(topDetails)
        XCTAssertEqual(router.attempt(), nil, "nothing waiting")
        router.handleTap(userInfo: push)
        XCTAssertEqual(homeNav.viewControllers.count, 3)
        XCTAssertTrue(topDetails === first, "the same screen stays; it is refreshed, not pushed again")
    }

    func testAnotherOrderReplacesTheOneOnTopAboveTheSameList() throws {
        router.handleTap(userInfo: push)
        let list = homeNav.viewControllers[1]
        router.handleTap(userInfo: ["order_id": "94", "order_unique_id": "ORD-ENTRY-94", "order_number": "9662"])
        XCTAssertEqual(types(homeNav), ["HomeViewController", "OrderListViewController", "OrderDetailsViewController"])
        XCTAssertTrue(homeNav.viewControllers[1] === list)
        XCTAssertEqual(topDetails?.strOrderUniqueId, "ORD-ENTRY-94")
    }

    // MARK: - Never over other work

    func testAnotherWorkflowIsNotReplacedAndTheTapOpensWhenTheEmployeeIsBack() throws {
        let workInProgress = UIViewController()   // a checklist, an upload, Place Order, Queue Line…
        homeNav.pushViewController(workInProgress, animated: false)
        router.handleTap(userInfo: push)
        XCTAssertTrue(homeNav.topViewController === workInProgress, "nothing is closed")
        XCTAssertEqual(homeNav.viewControllers.count, 2)
        XCTAssertEqual(router.pending?.orderUniqueId, "ORD-ENTRY-93")
        XCTAssertEqual(notices.count, 1, "the employee is told it will open later")

        router.resume()
        XCTAssertEqual(notices.count, 1, "told once")
        XCTAssertTrue(homeNav.topViewController === workInProgress)

        homeNav.popViewController(animated: false)   // back on Home
        router.resume()
        XCTAssertEqual(types(homeNav), ["HomeViewController", "OrderListViewController", "OrderDetailsViewController"])
        XCTAssertNil(router.pending)
    }

    func testADispatchMissionHubIsNotReplaced() throws {
        let hub = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController)
        hub.strOrderUniqueId = "ORD-MISSION"
        hub.fromCheckListScreen = true   // reached through the driver road
        homeNav.pushViewController(hub, animated: false)
        router.handleTap(userInfo: push)
        XCTAssertTrue(homeNav.topViewController === hub)
        XCTAssertNotNil(router.pending)
    }

    func testAFullWindowPopUpIsWorkInProgressButATransientToastIsNot() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        router.window = { window }
        XCTAssertFalse(OrderNotificationRouter.hasOverlay(in: window))

        let toast = PopUpProbe(frame: CGRect(x: 95, y: 700, width: 200, height: 44))   // the Sync Engine's toast
        window.addSubview(toast)
        XCTAssertFalse(OrderNotificationRouter.hasOverlay(in: window), "a toast blocks nothing")

        let popUp = PopUpProbe(frame: window.bounds)   // Add Note / Payment are sized to the window
        window.addSubview(popUp)
        XCTAssertTrue(OrderNotificationRouter.hasOverlay(in: window))
        router.handleTap(userInfo: push)
        XCTAssertEqual(homeNav.viewControllers.count, 1, "a note being written is never covered or closed")
        XCTAssertNotNil(router.pending)

        popUp.removeFromSuperview()
        router.resume()
        XCTAssertEqual(topDetails?.strOrderUniqueId, "ORD-ENTRY-93")
    }

    // MARK: - Sign-in and company

    func testASignedOutTapWaitsForSignInThenOpens() throws {
        signedIn = false
        currentTenant = nil
        let login = UINavigationController(rootViewController: UIViewController())
        router.rootViewController = { login }
        router.handleTap(userInfo: push)
        XCTAssertEqual(login.viewControllers.count, 1, "nothing opens over Login")
        XCTAssertNotNil(router.pending)

        signedIn = true
        currentTenant = tenant
        router.rootViewController = { [unowned self] in self.tabs }
        router.resume()   // Home appears after sign-in
        XCTAssertEqual(topDetails?.strOrderUniqueId, "ORD-ENTRY-93")
    }

    func testATapForAnotherCompanyIsNeverOpened() throws {
        homeNav.pushViewController(UIViewController(), animated: false)   // busy: the tap waits
        router.handleTap(userInfo: push)
        XCTAssertNotNil(router.pending)
        homeNav.popToRootViewController(animated: false)
        currentTenant = "another-company.invalid"   // session expired, signed in to another company
        router.resume()
        XCTAssertNil(router.pending)
        XCTAssertEqual(homeNav.viewControllers.count, 1)
    }

    func testSigningOutForgetsAWaitingTap() throws {
        homeNav.pushViewController(UIViewController(), animated: false)
        router.handleTap(userInfo: push)
        router.sessionEnded()
        homeNav.popToRootViewController(animated: false)
        router.resume()
        XCTAssertEqual(homeNav.viewControllers.count, 1)
    }

    func testAPushThatNamesNoOrderDoesNothing() throws {
        router.handleTap(userInfo: ["dispatch_wake": "1"])
        XCTAssertNil(router.pending)
        XCTAssertEqual(homeNav.viewControllers.count, 1)
    }

    // MARK: - The Orders list, by stable id

    func testLeavingOrderDetailsUpdatesTheOrdersRowByItsStableId() throws {
        let list = try ordersList()
        list.loadViewIfNeeded()
        list.arrOrderList = [OrdersListModel(JSON: ["id": 92, "unique_id": "ORD-OTHER", "customer_name": "Other"])!,
                             OrdersListModel(JSON: ["id": 93, "unique_id": "ORD-ENTRY-93", "customer_name": "Before"])!]
        list.arrMainOrderList = list.arrOrderList
        homeNav.pushViewController(list, animated: false)
        router.handleTap(userInfo: push)
        let details = try XCTUnwrap(topDetails)
        details.objOrderData = OrdersListModel(JSON: ["id": 93, "unique_id": "ORD-ENTRY-93", "customer_name": "After"])

        homeNav.popViewController(animated: false)   // Back (or a swipe, or a flow popping past it)

        XCTAssertEqual(list.arrOrderList.map { $0.customer_name ?? "" }, ["Other", "After"], "the row found by unique_id, not by position")
        XCTAssertEqual(list.arrMainOrderList[1].customer_name, "After")
    }

    func testAnOrderTheListDoesNotHoldRefreshesTheList() throws {
        let list = try ordersList()
        list.loadViewIfNeeded()
        list.arrOrderList = [OrdersListModel(JSON: ["id": 92, "unique_id": "ORD-OTHER", "customer_name": "Other"])!]
        homeNav.pushViewController(list, animated: false)
        router.handleTap(userInfo: push)
        topDetails?.objOrderData = OrdersListModel(JSON: ["id": 93, "unique_id": "ORD-ENTRY-93"])
        list.pageCount = 7

        homeNav.popViewController(animated: false)

        XCTAssertEqual(list.pageCount, 1, "the list reloads from its first page")
        XCTAssertFalse(list.arrOrderList.contains { $0.unique_id == "ORD-ENTRY-93" && $0.customer_name == nil },
                       "the closed order is never written over another row")
    }

    // MARK: - Read receipt and unknown orders

    func testTheReadReceiptWaitsForTheOrdersIdInsteadOfMarkingEverythingRead() throws {
        let details = try XCTUnwrap(OrderDetailsEntry.make(try XCTUnwrap(OrderOpenRequest(orderUniqueId: "ORD-ENTRY-93", orderId: nil,
                                                                                            orderNumber: nil, tenantKey: nil)),
                                                           ordersList: nil))
        details.acknowledgeNotifications()
        XCTAssertNil(details.acknowledgedOrderId, "no order_id yet: nothing is sent (an empty one marks every notification read)")
        details.objOrderData = OrdersListModel(JSON: ["id": 93, "unique_id": "ORD-ENTRY-93"])
        details.acknowledgeNotifications()
        XCTAssertEqual(details.acknowledgedOrderId, "93")
    }

    func testKabbaSayingNoReadsAsUnavailableAndALostConnectionAsNotDownloaded() {
        XCTAssertTrue(OrderDetailsViewController.kabbaDeclined(answer: ["success": false, "message": "The selected unique id is invalid."], error: nil))
        XCTAssertTrue(OrderDetailsViewController.kabbaDeclined(answer: nil, error: APIErrorClassifier.classify(statusCode: 422, body: nil)))
        XCTAssertTrue(OrderDetailsViewController.kabbaDeclined(answer: nil, error: APIErrorClassifier.classify(statusCode: 404, body: nil)))
        XCTAssertFalse(OrderDetailsViewController.kabbaDeclined(answer: nil, error: APIError.transport(.other, description: "offline")))
        XCTAssertFalse(OrderDetailsViewController.kabbaDeclined(answer: nil, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
        XCTAssertFalse(OrderDetailsViewController.kabbaDeclined(answer: nil, error: APIErrorClassifier.classify(statusCode: 500, body: nil)))
    }
}

/// An app view added straight to the window (its class name is not UIKit's). Private on purpose:
/// a private Swift class's runtime name starts with "_Tt", which must still count as the app's.
private final class PopUpProbe: UIView {}
