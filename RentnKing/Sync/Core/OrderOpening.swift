//
//  OrderOpening.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Mobile issue #9 (2026-11-14): ONE way to open Order Details for an order,
//  whether the employee taps it in Home → Orders or taps its Kabba push. This
//  file owns the decisions; the screens own the mechanics
//  (RentnKing/Sync/App/OrderDetailsEntry.swift):
//
//  • `OrderOpenRequest` — the order's STABLE identity (unique_id, plus the id
//    and number the opener already knows). Never a list row.
//  • `OrderOpenPolicy` — what a notification tap may do with what the phone
//    is showing: open it in the Home → Orders stack, wait for sign-in, wait
//    until the employee finishes other work, or nothing at all (the same order
//    is already open, or the tap belongs to another company / is stale).
//  • `OrderNotificationAcknowledgement` — the read receipt is always for ONE
//    order: an empty id would mark every notification read (Kabba's
//    `user-notification/update/status` treats a missing order_id as "all").
//

import Foundation

/// The order to open, by its stable identity.
struct OrderOpenRequest: Equatable {
    /// Kabba's `orders.unique_id` — what Order Details loads by.
    let orderUniqueId: String
    /// Kabba's numeric `orders.id` (the read receipt's key), when the opener knows it.
    let orderId: String?
    /// The order number shown as the heading until the order itself loads.
    let orderNumber: String?
    /// The company signed in when the request was made; nil when nobody was signed in.
    let tenantKey: String?
    /// When the request was made (a tap left waiting too long is dropped).
    let requestedAt: Date

    init?(orderUniqueId: String?, orderId: String?, orderNumber: String?,
          tenantKey: String?, requestedAt: Date = Date()) {
        guard let uid = Self.clean(orderUniqueId) else { return nil }
        self.orderUniqueId = uid
        self.orderId = Self.clean(orderId)
        self.orderNumber = Self.clean(orderNumber)
        self.tenantKey = Self.clean(tenantKey)
        self.requestedAt = requestedAt
    }

    /// A Kabba new-order push (`SendAdminNotificationListener`): data keys `order_unique_id`,
    /// `order_id`, `order_number`, all strings (FCM data is string-valued; numbers are tolerated).
    /// Nil when the payload names no order — a push that isn't about an order opens nothing.
    init?(pushUserInfo userInfo: [AnyHashable: Any], tenantKey: String?, requestedAt: Date = Date()) {
        self.init(orderUniqueId: Self.string(userInfo["order_unique_id"]),
                  orderId: Self.string(userInfo["order_id"]),
                  orderNumber: Self.string(userInfo["order_number"]),
                  tenantKey: tenantKey,
                  requestedAt: requestedAt)
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed != "0", trimmed.lowercased() != "null" else { return nil }
        return trimmed
    }
}

/// What the phone is showing when a notification asks to open an order.
struct OrderOpenSurface: Equatable {

    /// A screen of the Home tab's navigation stack, as far as opening an order is concerned.
    enum Screen: Equatable {
        case home
        case ordersList
        case orderDetails(orderUniqueId: String)
        /// Anything else: Dispatch and its mission, a checklist, an upload, Place Order, Queue Line…
        /// It may hold work the employee hasn't saved, so a notification never replaces it.
        case other
    }

    /// Signed in, with the main tab interface on screen (not Splash or Login).
    var signedIn: Bool
    /// The company signed in now.
    var tenantKey: String?
    /// The Home tab's navigation stack, bottom → top.
    var homeStack: [Screen]
    /// Something sits above the tabs: a sheet, an alert, the camera or a picker, or one of the
    /// pop-ups Order Details adds to the window (Add Note, Payment).
    var somethingPresented: Bool
    /// The keyboard is up — someone is typing.
    var isEditing: Bool
    /// A push / pop / presentation is still animating.
    var isTransitioning: Bool
}

enum OrderOpenDecision: Equatable {
    /// Nobody is signed in yet: keep the request and open it once the main interface appears.
    case waitForSignIn
    /// The employee is busy elsewhere (unsaved work, a sheet, typing) or the screen is moving:
    /// keep the request and open it when they are back on Home or Orders.
    case waitUntilIdle
    /// That exact order is already on top: show it fresh, push nothing.
    case alreadyShowing
    /// Open it in the Home tab: keep the stack up to and including the Orders list at
    /// `ordersListIndex` and push Order Details on it; with no Orders list, build Home → Orders →
    /// Order Details, exactly the stack an employee builds by hand.
    case open(ordersListIndex: Int?)
    /// Never shown: the tap belongs to another company than the one signed in, or it waited too long.
    case discard
}

enum OrderOpenPolicy {

    /// A tap that could not open within this window is dropped rather than opened later by surprise.
    static let maximumWait: TimeInterval = 30 * 60

    static func decide(_ request: OrderOpenRequest, on surface: OrderOpenSurface, now: Date = Date()) -> OrderOpenDecision {
        if now.timeIntervalSince(request.requestedAt) > maximumWait {
            return .discard
        }
        guard surface.signedIn else { return .waitForSignIn }
        // Signed in to another company since the tap: its order is never looked up here.
        if let tapped = request.tenantKey, tapped != surface.tenantKey {
            return .discard
        }
        if surface.isTransitioning || surface.somethingPresented || surface.isEditing {
            return .waitUntilIdle
        }
        let stack = surface.homeStack
        guard stack.first == .home, !stack.contains(.other) else {
            return .waitUntilIdle
        }
        if stack.last == .orderDetails(orderUniqueId: request.orderUniqueId) {
            return .alreadyShowing
        }
        return .open(ordersListIndex: stack.firstIndex(of: .ordersList))
    }
}

/// The read receipt Order Details sends when it opens an order.
enum OrderNotificationAcknowledgement {

    /// The `order_id` to acknowledge, or nil when there is none yet. Never "": Kabba reads a
    /// missing order_id as "mark every notification read" (the Orders list's Clear All).
    static func orderId(known: String?, loaded: Int?) -> String? {
        if let known = known?.trimmingCharacters(in: .whitespacesAndNewlines), !known.isEmpty, known != "0" {
            return known
        }
        if let loaded = loaded, loaded > 0 {
            return String(loaded)
        }
        return nil
    }
}
