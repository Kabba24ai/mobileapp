//
//  ChecklistEntry.swift
//  RentnKing
//
//  The ONE road into the outbound (Delivery-leg) equipment checklist (2026-09-14):
//
//      entry point → Assembly Review → Delivery Checklist → Assembly Review → entry point
//
//  whatever the entry point — a Queue Line card, the Orders list, Order Details
//  (and so everything that reaches Order Details: Schedule, Dispatch's driver
//  flow, the notification deep link, Machine Profile). Assembly Review verifies
//  that the ordered physical configuration is present — the machine, bundled
//  and related products, every frozen Product Option; the checklist verifies the
//  machine itself. Two responsibilities, one fixed order — even for a single-line
//  order with no options, so the yard learns exactly one workflow.
//
//  Nothing here stages: the review only decides whether a checklist may begin,
//  the checklist's explicit Save stays the sole Pending → Staged trigger, and
//  every checklist entered this way is FOCUSED on one member — its siblings
//  never receive staging intent from that Save.
//
//  The Return leg is inbound and untouched: Assembly Review is the outbound
//  assembly gate, exactly the scope of the server's staging gate.
//

import UIKit

enum ChecklistEntry {

    /// Where the technician came from — carried through the review into the
    /// checklist so its downstream behaviour (the list row refresh, pop targets,
    /// the driver-completion flags) stays exactly what that entry point had.
    struct Origin: Equatable {
        enum Kind: Equatable { case queueLine, orderList, orderDetails }
        var kind: Kind
        /// The caller's row index (Order List / Order Details `selectIndex`).
        var selectIndex: Int = 0
        /// Order Details reached through Dispatch's driver flow.
        var fromCheckListScreen: Bool = false

        static let queueLine = Origin(kind: .queueLine)
    }

    /// Pushes the order's Assembly Review — focused on one member / entity when
    /// the caller names one, otherwise every entity of the order, each with its
    /// own STOP / GO. One review at a time: a second tap while this order's
    /// review is already on top pushes nothing (returns nil), so a double-tap
    /// never stacks two reviews.
    @discardableResult
    static func openAssemblyReview(on nav: UINavigationController?, orderUniqueId: String, orderNumber: String,
                                   focusOrderProductUniqueId: String? = nil, focusAssemblyKey: String? = nil,
                                   origin: Origin, animated: Bool = true) -> AssemblyReviewViewController? {
        guard let nav = nav, !orderUniqueId.isEmpty else { return nil }
        if let top = nav.topViewController as? AssemblyReviewViewController, top.orderUniqueId == orderUniqueId { return nil }
        let vc = AssemblyReviewViewController()
        vc.orderUniqueId = orderUniqueId
        vc.orderNumber = orderNumber
        vc.focusOrderProductUniqueId = focusOrderProductUniqueId
        vc.focusAssemblyKey = focusAssemblyKey
        vc.origin = origin
        nav.pushViewController(vc, animated: animated)
        return vc
    }

    /// The Delivery Checklist for ONE member of a GO assembly — built for the
    /// review only. The same storyboard screen and identity payload for every
    /// origin; only the origin flags differ. Focused: this member alone may
    /// receive staging intent from the Save.
    static func makeChecklist(for member: AssemblyMember, origin: Origin, equipmentUniqueId: String? = nil) -> CheckListViewController? {
        let storyBoard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        guard let vc = storyBoard.instantiateViewController(withIdentifier: "CheckListViewController") as? CheckListViewController else { return nil }
        vc.isDeliveryType = true
        vc.isQueueLine = origin.kind == .queueLine
        vc.isOrderDetailsView = origin.kind == .orderDetails
        vc.fromCheckListScreen = origin.fromCheckListScreen
        vc.selectIndex = origin.selectIndex
        vc.strOrderUniqueId = member.orderUniqueId
        vc.strOrderID = member.orderNumber
        vc.focusOrderProductUniqueId = member.orderProductUniqueId
        vc.queueLineFocusedStaging = true
        vc.queueLineEquipmentUniqueId = equipmentUniqueId ?? member.identity.equipmentUniqueId ?? member.equipment?.uniqueId ?? ""
        vc.queueLineChecklistExecutionId = member.checklist.delivery.checklistExecutionId ?? member.identity.checklistExecutionId ?? ""
        return vc
    }

    /// After the checklist — its Save, the finalization Submit, the media
    /// upload: back to the Assembly Review beneath FIRST, whatever the origin
    /// (it refreshes availability, assignment, options, checklist state,
    /// lifecycle and STOP / GO), and only then, by the technician's own Back,
    /// to the screen the review was opened from. With no review on the stack
    /// (a legacy entry) `fallback` performs the caller's original navigation.
    /// Returns true when a review was returned to.
    @discardableResult
    static func returnToReview(on nav: UINavigationController?, animated: Bool = true, fallback: () -> Void) -> Bool {
        if let nav = nav, let review = nav.viewControllers.last(where: { $0 is AssemblyReviewViewController }) {
            nav.popToViewController(review, animated: animated)
            return true
        }
        fallback()
        return false
    }
}
