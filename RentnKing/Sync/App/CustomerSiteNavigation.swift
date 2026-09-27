//
//  CustomerSiteNavigation.swift
//  RentnKing — Sync App
//
//  Driver Delivery Process Flow (2026-09-27), spec §10: the customer-site
//  screens (Main Order, the equipment checklist, the checklist Submit, the
//  Photo/Video upload, License, Terms) share ONE idea of where they are —
//  `CustomerSiteRouter` decides the next screen from the mission's stage — and
//  ONE way of getting there: "go to X" pops to X when it is on the stack and
//  pushes it otherwise, so the stack stays finite (Main Order → Checklist →
//  Video → (pop) Checklist → Submit → (pop) Main Order). Before departure the
//  yard's `ChecklistEntry.returnToReview` rule is untouched.
//

import UIKit

enum CustomerSiteNavigation {

    /// Off-screen stacks (tests, background) move at once; on screen the pop animates.
    static func animated(_ nav: UINavigationController?) -> Bool {
        guard let nav = nav, nav.isViewLoaded else { return false }
        return nav.view.window != nil
    }

    /// Pops to the NEAREST view controller of `type` beneath the top. False when none.
    @discardableResult
    static func popToNearest<T: UIViewController>(_ type: T.Type, on nav: UINavigationController?) -> Bool {
        guard let nav = nav, let target = nav.viewControllers.dropLast().last(where: { $0 is T }) else { return false }
        nav.popToViewController(target, animated: animated(nav))
        return true
    }

    /// Main Order: the Order Details that pushed the screen (the nearest one beneath) —
    /// never the Orders list further down; without one, the Orders list; without that,
    /// one pop (a screen that had no hub beneath it keeps its old exit).
    static func goToMainOrder(on nav: UINavigationController?) {
        guard let nav = nav else { return }
        if popToNearest(OrderDetailsViewController.self, on: nav) { return }
        if popToNearest(OrderListViewController.self, on: nav) { return }
        nav.popViewController(animated: animated(nav))
    }

    /// The customer-site band: from On My Way on, and every Return step (§10.2 / §13).
    static func isCustomerSite(stage: DeliveryWorkflowStage, isDeliveryLeg: Bool) -> Bool {
        !isDeliveryLeg || stage >= .onMyWay
    }

    /// The mission's stage for a screen that has no Dispatch row: what the opener knew
    /// (`floor`, handed down screen to screen) under the phone's own durable steps and
    /// the cached gate — the same builder every driver screen uses.
    static func stage(orderProductUniqueId: String, isDeliveryLeg: Bool, floor: DeliveryWorkflowStage?,
                      review: AssemblyReview?, operations: [SyncOperation]) -> DeliveryWorkflowStage {
        guard !orderProductUniqueId.isEmpty else { return floor ?? .assemblyReview }
        let local = DriverMissionStage.stage(
            DriverMissionStage.Inputs(orderProductUniqueId: orderProductUniqueId, isDeliveryLeg: isDeliveryLeg),
            review: review, operations: operations)
        return max(floor ?? .assemblyReview, local)
    }

    /// The driver's trip stage the preparation rules read (`PreparationPolicy.block(for:tripStage:)`).
    static func tripStage(for stage: DeliveryWorkflowStage) -> DriverTripStage {
        switch stage {
        case .arrived, .delivered: return .arrived
        case .onMyWay: return .onMyWay
        case .assemblyReview, .driverChecklist: return .notStarted
        }
    }

    /// D7 — the ONE delivery-video requirement for a product (spec §10.3), effective and
    /// strict: the server's cycle truth; the feed's video items only while no cycle is
    /// known; a durable video operation for this product's cycle; a legacy queued video
    /// for this product unless a later local discard retired it. Photos never count.
    static func deliveryVideoRequirementMet(product: ProductModel, context: ChecklistContext?,
                                            orderUniqueId: String, operations: [SyncOperation]) -> Bool {
        let uid = product.unique_id ?? ""
        let activeExecutionId = context?.executionId
        let feedVideo = context?.serverState.deliveryVideoPresent == nil
            && product.arrDeliveryMedia.contains { ($0.media_type ?? "").lowercased().hasPrefix("video") }

        if MediaRequirementPolicy.deliveryVideoSatisfied(serverHasVideoForCycle: context?.serverState.deliveryVideoPresent == true,
                                                         operations: operations,
                                                         orderProductUniqueId: uid,
                                                         activeExecutionId: activeExecutionId,
                                                         orderHasVideo: feedVideo) {
            return true
        }

        guard !uid.isEmpty, EffectiveFieldState.lastDiscardAt(in: operations, orderProductUniqueId: uid) == nil else { return false }
        let legacyRows = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: orderUniqueId,
                                                                          strType: uploadType.video_image.rawValue,
                                                                          strVideoType: "delivery")
        return legacyRows.contains { $0.isImage == false && ($0.productID ?? "") == uid }
    }

    /// Is THIS product's checklist complete (server ∨ a durable completion op)?
    static func checklistComplete(product: ProductModel, isDeliveryLeg: Bool, operations: [SyncOperation]) -> Bool {
        EffectiveFieldState.legSatisfied(serverCompleted: (isDeliveryLeg ? product.is_delivered : product.is_returned) ?? false,
                                         operations: operations,
                                         orderProductUniqueId: product.unique_id ?? "",
                                         isDeliveryLeg: isDeliveryLeg)
    }

    /// The Photo/Video upload for the order, built the way the checklist always built it
    /// (the cached Order Details copy, else the loaded order), anchored to the products'
    /// checklist executions and carrying the mission's focus and stage.
    static func makeMediaUpload(orderUniqueId: String, order: OrdersModel?, isDelivery: Bool, selectIndex: Int,
                                focusOrderProductUniqueId: String, executionIds: [String: String],
                                floor: DeliveryWorkflowStage?, isQueueLine: Bool) -> ImageUploadViewController? {
        var listModel = OrderDetailsCache.load(orderUniqueId: orderUniqueId)
        if listModel == nil, let order {
            var built = OrdersListModel(JSON: [:])
            built?.id = order.id
            built?.arrProduct = order.arrProduct
            listModel = built
        }
        guard let listModel else { return nil }
        let storyboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        guard let vc = storyboard.instantiateViewController(withIdentifier: "ImageUploadViewController") as? ImageUploadViewController else { return nil }
        vc.isQueueLine = isQueueLine
        vc.strType = isDelivery ? "delivery" : "pickup"
        vc.selectIndex = selectIndex
        vc.objOrderDetail = listModel
        vc.strOrderID = orderUniqueId
        vc.checklistExecutionIds = executionIds
        vc.focusOrderProductUniqueId = focusOrderProductUniqueId
        vc.driverStageFloor = floor
        return vc
    }

    /// "Go to Video": the upload already on the stack, else a fresh one.
    static func goToVideo(on nav: UINavigationController?, make: () -> ImageUploadViewController?) {
        guard let nav = nav else { return }
        if popToNearest(ImageUploadViewController.self, on: nav) { return }
        if let vc = make() { nav.pushViewController(vc, animated: animated(nav)) }
    }

    /// "Go to Checklist": the checklist already on the stack, else a fresh focused one.
    static func goToChecklist(on nav: UINavigationController?, make: () -> CheckListViewController?) {
        guard let nav = nav else { return }
        if popToNearest(CheckListViewController.self, on: nav) { return }
        if let vc = make() { nav.pushViewController(vc, animated: animated(nav)) }
    }

    /// The focused equipment checklist for the mission line, as Main Order opens it after
    /// departure (§10.2): the same screen the review's Continue builds, focused on one line.
    static func makeFocusedChecklist(orderUniqueId: String, orderNumber: String, product: ProductModel?, selectIndex: Int,
                                     floor: DeliveryWorkflowStage?, fromCheckListScreen: Bool) -> CheckListViewController? {
        let storyboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        guard let vc = storyboard.instantiateViewController(withIdentifier: "CheckListViewController") as? CheckListViewController else { return nil }
        vc.isDeliveryType = true
        vc.isOrderDetailsView = true
        vc.fromCheckListScreen = fromCheckListScreen
        vc.selectIndex = selectIndex
        vc.strOrderUniqueId = orderUniqueId
        vc.strOrderID = orderNumber
        vc.focusOrderProductUniqueId = product?.unique_id ?? ""
        vc.queueLineFocusedStaging = true
        vc.queueLineEquipmentUniqueId = product?.objMachine?.unique_id ?? ""
        vc.driverStageFloor = floor
        return vc
    }
}
