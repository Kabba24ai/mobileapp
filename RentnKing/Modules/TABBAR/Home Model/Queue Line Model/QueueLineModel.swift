//
//  QueueLineModel.swift
//  RentnKing
//
//  Model + API for the Queue Line board (GET api/admin/v1/queue-line).
//

import Foundation
import ObjectMapper
import UIKit

// MARK: - Item

struct QueueLineModel: Mappable {
    internal var order_product_unique_id: String?
    internal var order_unique_id: String?
    internal var order_number: String?
    internal var customer_name: String?

    internal var store: QueueLineStore?
    internal var product: QueueLineProduct?
    internal var delivery: QueueLineDelivery?
    internal var equipment: QueueLineEquipment?
    internal var equipment_collection: MachineModel?
    internal var available_actions: QueueLineActions?

    internal var urgency: String?
    internal var assignment_state: String?
    internal var options_count: Int?
    internal var payment_label: String?
    internal var status: String?        // "pending" | "staged" | "completed"
    internal var staged: Bool?
    internal var completed: Bool?
    internal var readiness: String?
    internal var staged_by: String?     // employee whose checklist Save staged it
    internal var staged_at: String?     // timestamp it was staged
    internal var is_fast_track: Bool?   // FAST TRACK tag (shown on Completed cards)
    // Checklist-driven Queue Line (2026-09): derived dispatch On My Way state.
    internal var in_transit: Bool?
    internal var on_my_way_at: String?

    // Phase 4 — canonical item identity + delivery-checklist state (additive server fields).
    internal var identity: QueueLineIdentity?
    internal var checklist: QueueLineChecklist?
    internal var fulfillment_leg: String?

    // Assembly Review (2026-09-14) — additive: the canonical four-stage
    // classifier, the Queue Line entity this line belongs to (a dependent
    // assembly or the line on its own), the parent line's effective
    // availability and the gate blockers. Product Options stay on the
    // Assembly Review screen; the board only knows they exist.
    internal var lifecycle_stage: String?
    internal var assembly: QueueLineAssemblyInfo?
    internal var availability_effective_state: String?
    internal var stage_blocker_labels: [String] = []
    internal var product_option_names: [String] = []

    init?(map: Map) { mapping(map: map) }

    mutating func mapping(map: Map) {
        order_product_unique_id <- map["order_product_unique_id"]
        order_unique_id         <- map["order_unique_id"]
        order_number            <- map["order_number"]
        customer_name           <- map["customer_name"]

        store             <- map["store"]
        product           <- map["product"]
        delivery          <- map["delivery"]
        equipment         <- map["equipment"]
        equipment_collection <- map["equipment_collection"]
        available_actions <- map["available_actions"]

        urgency          <- map["urgency"]
        assignment_state <- map["assignment_state"]
        options_count    <- map["options_count"]
        payment_label    <- map["payment_label"]
        status           <- map["status"]
        staged           <- map["staged"]
        completed        <- map["completed"]
        in_transit       <- map["in_transit"]
        on_my_way_at     <- map["on_my_way_at"]
        readiness        <- map["readiness"]
        staged_by        <- map["staged_by"]
        staged_at        <- map["staged_at"]
        is_fast_track    <- map["is_fast_track"]
        identity         <- map["identity"]
        checklist        <- map["checklist"]
        fulfillment_leg  <- map["fulfillment_leg"]
        lifecycle_stage  <- map["lifecycle_stage"]
        assembly         <- map["assembly"]
        availability_effective_state <- map["availability.effective_state"]
        var blockers: [[String: Any]]?
        blockers <- map["stage_blockers"]
        stage_blocker_labels = (blockers ?? []).compactMap { $0["label"] as? String }
        var options: [[String: Any]]?
        options <- map["product_options"]
        product_option_names = (options ?? []).compactMap { $0["name"] as? String }
    }

    /// The Queue Line entity this line belongs to — the server's derived key
    /// (a dependent assembly from persisted bundle / related-product edges, or
    /// the line on its own). A board served before the dependency model puts
    /// every line on its own.
    var assemblyKey: String { assembly?.key ?? "QLA-\(itemOrderProductUniqueId)" }
    var assemblyMemberCount: Int { assembly?.member_count ?? 1 }
    /// The canonical four-stage vocabulary (falls back to the three-lane status).
    var lifecycleStage: AssemblyStage {
        AssemblyStage(rawValue: lifecycle_stage ?? "")
            ?? ((status ?? "") == "completed" || completed == true ? .equipmentDelivered : ((status ?? "") == "staged" ? .staged : .pending))
    }

    /// The Queue Line item IS the order product. Prefer the explicit identity block; fall back
    /// to the top-level field for boards served before Phase 4.
    var itemOrderProductUniqueId: String { identity?.order_product_unique_id ?? order_product_unique_id ?? "" }
    var itemOrderUniqueId: String { identity?.order_unique_id ?? order_unique_id ?? "" }
    var itemEquipmentUniqueId: String? { identity?.equipment_unique_id ?? equipment?.unique_id }
    var deliveryChecklistExecutionId: String? { checklist?.delivery?.checklist_execution_id ?? identity?.checklist_execution_id }
    var deliveryChecklistStatus: String { checklist?.delivery?.status ?? "not_prepared" }
}

// MARK: - Assembly Review (2026-09-14) — the `assembly` block on a board item

struct QueueLineAssemblyInfo: Mappable {
    internal var key: String?
    internal var kind: String?          // single | dependent
    internal var stage: String?         // pending | staged | in_transit | equipment_delivered (least-advanced member)
    internal var lane: String?          // pending | staged | completed
    internal var member_count: Int?
    internal var pending_count: Int?
    internal var staged_count: Int?
    internal var in_transit_count: Int?
    internal var delivered_count: Int?
    // How this member hangs on its assembly (base | bundle_child | related_child).
    internal var dependency_role: String?
    internal var depends_on_name: String?
    // The assembly's derived STOP/GO gate (never stored).
    internal var gate_ready: Bool?
    internal var gate_required_count: Int?
    internal var gate_confirmed_count: Int?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        key              <- map["key"]
        kind             <- map["kind"]
        stage            <- map["stage"]
        lane             <- map["lane"]
        member_count     <- map["member_count"]
        pending_count    <- map["stage_counts.pending"]
        staged_count     <- map["stage_counts.staged"]
        in_transit_count <- map["stage_counts.in_transit"]
        delivered_count  <- map["stage_counts.equipment_delivered"]
        dependency_role  <- map["dependency.role"]
        depends_on_name  <- map["dependency.depends_on_name"]
        gate_ready       <- map["gate.ready"]
        gate_required_count  <- map["gate.required_count"]
        gate_confirmed_count <- map["gate.confirmed_count"]
    }
}

// MARK: - Phase 4 identity / checklist blocks

struct QueueLineIdentity: Mappable {
    internal var queue_line_item_id: String?
    internal var order_unique_id: String?
    internal var order_product_unique_id: String?
    internal var equipment_unique_id: String?
    internal var store_unique_id: String?
    internal var fulfillment_leg: String?
    internal var checklist_execution_id: String?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        queue_line_item_id      <- map["queue_line_item_id"]
        order_unique_id         <- map["order_unique_id"]
        order_product_unique_id <- map["order_product_unique_id"]
        equipment_unique_id     <- map["equipment_unique_id"]
        store_unique_id         <- map["store_unique_id"]
        fulfillment_leg         <- map["fulfillment_leg"]
        checklist_execution_id  <- map["checklist_execution_id"]
    }
}

struct QueueLineChecklist: Mappable {
    internal var delivery: QueueLineChecklistLegState?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        delivery <- map["delivery"]
    }
}

struct QueueLineChecklistLegState: Mappable {
    internal var leg: String?
    internal var checklist_execution_id: String?
    internal var status: String?          // not_prepared | prepared | completed
    internal var prepared_at: String?
    internal var completed_at: String?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        leg                    <- map["leg"]
        checklist_execution_id <- map["checklist_execution_id"]
        status                 <- map["status"]
        prepared_at            <- map["prepared_at"]
        completed_at           <- map["completed_at"]
    }
}

// MARK: - Nested

struct QueueLineStore: Mappable {
    internal var unique_id: String?
    internal var name: String?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        unique_id <- map["unique_id"]
        name      <- map["name"]
    }
}

struct QueueLineProduct: Mappable {
    internal var unique_id: String?
    internal var name: String?
    internal var image_url: String?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        unique_id <- map["unique_id"]
        name      <- map["name"]
        image_url <- map["image_url"]
    }
}

struct QueueLineDelivery: Mappable {
    internal var type_label: String?
    internal var transport_mode: String?
    internal var date: String?
    internal var dispatch_date: String?
    internal var time: String?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        type_label     <- map["type_label"]
        transport_mode <- map["transport_mode"]
        date           <- map["date"]
        dispatch_date  <- map["dispatch_date"]
        time           <- map["time"]
    }
}

struct QueueLineEquipment: Mappable {
    internal var unique_id: String?
    internal var display_id: String?
    internal var name: String?
    internal var assigned_product_name: String?
    internal var status: String?
    internal var status_label: String?
    internal var rental_ready: String?
    internal var location: String?
    internal var wrong_location: Bool?
    internal var power_source_type: String?
    internal var is_fuel: Bool?
    internal var key_starting_mechanism: String?
    internal var is_key: Bool?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        unique_id             <- map["unique_id"]
        display_id            <- map["display_id"]
        name                  <- map["name"]
        assigned_product_name <- map["assigned_product_name"]
        status                <- map["status"]
        status_label          <- map["status_label"]
        rental_ready          <- map["rental_ready"]
        location              <- map["location"]
        wrong_location        <- map["wrong_location"]
        power_source_type     <- map["power_source_type"]
        is_fuel               <- map["is_fuel"]
        key_starting_mechanism <- map["key_starting_mechanism"]
        is_key                <- map["is_key"]
    }
}

// (QueueLineFuel / QueueLineKey retired 2026-09 with the fuel/key
//  mini-checklist — staging is checklist-driven; the ledgers remain
//  server-side history only.)

struct QueueLineActions: Mappable {
    internal var assign_equipment: Bool?
    internal var switch_equipment: Bool?
    internal var open_delivery_checklist: Bool?
    internal var view_history: Bool?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        assign_equipment        <- map["assign_equipment"]
        switch_equipment        <- map["switch_equipment"]
        open_delivery_checklist <- map["open_delivery_checklist"]
        view_history            <- map["view_history"]
    }
}

// MARK: - API

extension QueueLineViewController {

    /// GET api/admin/v1/queue-line → maps the items, persists them locally
    /// (like the Schedule list), and reports success.
    func callQueueLineAPI(completion: @escaping (_ success: Bool) -> Void) {
        let strURL = "\(Url.queueLine.absoluteString ?? "")"

        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "queueLine"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false

        webHelper.callAPIwithCompletation { data, _, _, error in
            indicatorHide()
            guard error == nil, let data = data,
                  data.getStringForID(key: "success") == "1",
                  let dataDic = data["data"] as? NSDictionary,
                  let itemsDic = dataDic["items"] as? NSDictionary else {
                // Phase 4: remember that the cached list is now STALE — the board says so.
                KabbaQueueLineSync.recordServerRefresh(succeeded: false)
                completion(false)
                return
            }
            KabbaQueueLineSync.recordServerRefresh(succeeded: true)

            // "items" is now grouped: { pending: [...], staged: [...], completed: [...] }
            func mapGroup(_ key: String) -> [QueueLineModel] {
                guard let arr = itemsDic[key] as? [[String: Any]] else { return [] }
                return Mapper<QueueLineModel>().mapArray(JSONArray: arr)
            }
            var list = mapGroup("pending")
            list.append(contentsOf: mapGroup("staged"))
            list.append(contentsOf: mapGroup("completed"))

            SDKUserDefault.saveMappableArray(list, for: kFileStorageName.kQueueLineList.rawValue)
            completion(true)
        }
    }

    /// Reads the locally persisted queue-line items.
    func getQueueLineData() -> [QueueLineModel] {
        return SDKUserDefault.getMappableArray(QueueLineModel.self, for: kFileStorageName.kQueueLineList.rawValue) ?? []
    }
}
