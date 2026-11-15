//
//  OrderDetailsEntry.swift
//  RentnKing — Sync App
//
//  Mobile issue #9 (2026-11-14): Order Details opened from a Kabba push behaved
//  differently from Home → Orders → Order Details. The push handler built its
//  own screen (unique_id and id only: no order number, no Orders list to report
//  back to) and presented it in a separate full-screen navigation controller,
//  over whatever was on screen. Everything Order Details does afterwards —
//  the heading, the checklist / media / license / terms flows and where they
//  return, the Orders list update on the way back — depends on how it was
//  opened, so the two entries drifted apart.
//
//  Now there is ONE entry:
//  • `OrderDetailsEntry.make` configures Order Details for an order's stable
//    identity, for the Orders list and for a notification alike;
//  • a notification opens it in the Home tab's own stack — Home → Orders →
//    Order Details — so Back, the sub-flows' returns and the Orders list
//    refresh are the ones an employee gets by hand;
//  • `OrderNotificationRouter` decides WHEN (OrderOpenPolicy, Sync Core): it
//    waits for sign-in, never replaces another workflow (Dispatch, a checklist,
//    an upload, Place Order…), never stacks the same order twice, and drops a
//    tap that belongs to another company.
//

import UIKit

enum OrderDetailsEntry {

    /// Order Details for `request`, configured the same way for every entry. `ordersList` (when
    /// the Orders list is beneath) gets the order back by its stable id when Order Details closes.
    /// `listRow` is the row the employee tapped — only the Orders list knows it; a notification
    /// passes nil (it never guesses a row: the list may not hold the order, or may be refreshing).
    static func make(_ request: OrderOpenRequest, ordersList: OrderListViewController?, listRow: Int? = nil) -> OrderDetailsViewController? {
        let storyBoard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        guard let details = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController else {
            return nil
        }
        details.strOrderUniqueId = request.orderUniqueId
        details.strOrderID = request.orderNumber ?? ""
        details.OrderID = request.orderId ?? ""
        details.delegate = ordersList
        details.selectIndex = listRow ?? -1
        return details
    }

    /// Home → Orders → tap a row.
    static func openFromOrdersList(_ list: OrderListViewController, order: OrdersListModel, row: Int) {
        guard let request = OrderOpenRequest(orderUniqueId: order.unique_id,
                                             orderId: order.id.map { String($0) },
                                             orderNumber: order.order_number,
                                             tenantKey: KabbaTenantScope.currentKey),
              let details = make(request, ordersList: list, listRow: row) else { return }
        list.navigationController?.pushViewController(details, animated: true)
    }

    /// Shows `request` in the Home tab's stack: up to the Orders list at `ordersListIndex`, then
    /// Order Details; with no Orders list, Home → Orders → Order Details. The Orders list built
    /// here loads its first page when it first appears, like one opened from Home.
    @discardableResult
    static func show(_ request: OrderOpenRequest, in nav: UINavigationController, ordersListIndex: Int?, animated: Bool) -> OrderDetailsViewController? {
        guard let home = nav.viewControllers.first else { return nil }
        let list: OrderListViewController
        var stack: [UIViewController]
        if let index = ordersListIndex, index < nav.viewControllers.count,
           let existing = nav.viewControllers[index] as? OrderListViewController {
            list = existing
            stack = Array(nav.viewControllers[0...index])
        } else {
            let storyBoard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            guard let fresh = storyBoard.instantiateViewController(withIdentifier: "OrderListViewController") as? OrderListViewController else {
                return nil
            }
            list = fresh
            stack = [home, fresh]
        }
        guard let details = make(request, ordersList: list) else { return nil }
        stack.append(details)
        nav.setViewControllers(stack, animated: animated)
        return details
    }
}

// MARK: - Notification taps

final class OrderNotificationRouter {

    static let shared = OrderNotificationRouter()

    /// The tap still waiting to open (the newest tap wins).
    private(set) var pending: OrderOpenRequest?
    private var retry: DispatchWorkItem?
    private var retries = 0
    private var noticeShownFor: OrderOpenRequest?
    private var observer: NSObjectProtocol?

    // Seams (hosted tests replace them).
    var window: () -> UIWindow? = { GlobalMainConstants.appDelegate?.window }
    var rootViewController: () -> UIViewController? = { GlobalMainConstants.appDelegate?.window?.rootViewController }
    var hasSession: () -> Bool = {
        UserDefaults.standard.user != nil
            && !(UserDefaults.standard.accessToken ?? "").isEmpty
            && !(UserDefaults.standard.baseURL ?? "").isEmpty
    }
    var tenantKey: () -> String? = { KabbaTenantScope.currentKey }
    var now: () -> Date = { Date() }
    var animated = true
    /// Tells the employee a tap will open once they are done (an alert; tests capture it).
    var showWaitingNotice: (OrderOpenRequest, UIViewController) -> Void = OrderNotificationRouter.presentWaitingNotice

    init() {
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        }
    }

    /// The employee tapped a notification (foreground, background or a cold launch).
    func handleTap(userInfo: [AnyHashable: Any]) {
        guard let request = OrderOpenRequest(pushUserInfo: userInfo,
                                             tenantKey: hasSession() ? tenantKey() : nil,
                                             requestedAt: now()) else { return }
        pending = request
        noticeShownFor = nil
        retries = 0
        attempt()
    }

    /// Home and the Orders list call this when they appear (sign-in completes on Home);
    /// returning to the foreground does too.
    func resume() {
        guard pending != nil else { return }
        attempt()
    }

    /// Signing out forgets a waiting tap (a new sign-in never inherits it).
    func sessionEnded() {
        pending = nil
        noticeShownFor = nil
        retry?.cancel()
        retry = nil
    }

    @discardableResult
    func attempt() -> OrderOpenDecision? {
        guard let request = pending else { return nil }
        let (surface, tabs, homeNav) = currentSurface()
        let decision = OrderOpenPolicy.decide(request, on: surface, now: now())
        switch decision {
        case .discard:
            pending = nil
        case .waitForSignIn:
            break
        case .waitUntilIdle:
            if surface.isTransitioning {
                scheduleRetry()
            } else if noticeShownFor != request, let top = topViewController(), !(top is UIAlertController) {
                noticeShownFor = request
                showWaitingNotice(request, top)
            }
        case .alreadyShowing:
            pending = nil
            (homeNav?.topViewController as? OrderDetailsViewController)?.reloadForNotification(request)
        case .open(let ordersListIndex):
            pending = nil
            guard let tabs = tabs, let nav = homeNav else { break }
            if tabs.selectedViewController !== nav { tabs.selectedViewController = nav }
            let onScreen = animated && nav.isViewLoaded && nav.view.window != nil
            OrderDetailsEntry.show(request, in: nav, ordersListIndex: ordersListIndex, animated: onScreen)
        }
        return decision
    }

    // MARK: Reading the screen

    func currentSurface() -> (OrderOpenSurface, UITabBarController?, UINavigationController?) {
        let window = self.window()
        // Signed in, the root is the tab interface (TabbarViewController); Splash and Login are not.
        let tabs = rootViewController() as? UITabBarController
        let homeNav = tabs?.viewControllers?.first(where: {
            ($0 as? UINavigationController)?.viewControllers.first is HomeViewController
        }) as? UINavigationController
        let stack: [OrderOpenSurface.Screen] = homeNav?.viewControllers.map(Self.screen(of:)) ?? []
        let surface = OrderOpenSurface(
            signedIn: hasSession() && tabs != nil && homeNav != nil,
            tenantKey: tenantKey(),
            homeStack: stack,
            somethingPresented: tabs?.presentedViewController != nil || Self.hasOverlay(in: window),
            isEditing: Self.isEditing(in: window),
            isTransitioning: tabs?.transitionCoordinator != nil || homeNav?.transitionCoordinator != nil
        )
        return (surface, tabs, homeNav)
    }

    static func screen(of controller: UIViewController) -> OrderOpenSurface.Screen {
        switch controller {
        case is HomeViewController:
            return .home
        case is OrderListViewController:
            return .ordersList
        case let details as OrderDetailsViewController:
            // A Dispatch mission hub or a just-placed order is its own workflow.
            if details.isOrderScreen || details.fromCheckListScreen || details.isPresent || details.strOrderUniqueId.isEmpty {
                return .other
            }
            return .orderDetails(orderUniqueId: details.strOrderUniqueId)
        default:
            return .other
        }
    }

    /// Order Details (Add Note, Payment), Checkout and CRM add their pop-ups straight to the
    /// window, sized to cover it. A small transient toast (the Sync Engine's) is not a pop-up.
    static func hasOverlay(in window: UIWindow?) -> Bool {
        guard let window = window else { return false }
        let root = window.rootViewController?.view
        let bounds = window.bounds
        return window.subviews.contains { view in
            guard view !== root, !view.isHidden, view.alpha > 0.01 else { return false }
            let name = NSStringFromClass(type(of: view))
            guard !name.hasPrefix("UI"), !name.hasPrefix("_") else { return false }
            return view.frame.width >= bounds.width * 0.9 && view.frame.height >= bounds.height * 0.9
        }
    }

    static func isEditing(in window: UIWindow?) -> Bool {
        guard let window = window else { return false }
        return firstResponder(in: window) != nil
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder, view is UITextInput { return view }
        for sub in view.subviews {
            if let found = firstResponder(in: sub) { return found }
        }
        return nil
    }

    private func topViewController() -> UIViewController? {
        guard let root = rootViewController() else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        if let nav = top as? UINavigationController { return nav.visibleViewController ?? nav }
        if let tabs = top as? UITabBarController {
            let selected = tabs.selectedViewController
            return (selected as? UINavigationController)?.visibleViewController ?? selected ?? tabs
        }
        return top
    }

    private func scheduleRetry() {
        guard retries < 20 else { return }
        retries += 1
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.attempt() }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private static func presentWaitingNotice(_ request: OrderOpenRequest, on top: UIViewController) {
        let title = request.orderNumber.map { "New order \($0)" } ?? "New order"
        let alert = UIAlertController(title: title,
                                      message: "It will open when you go back to Orders or Home. Nothing on this screen is closed.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        alert.view.accessibilityIdentifier = "orderNotification.waiting"
        top.present(alert, animated: true)
    }
}
