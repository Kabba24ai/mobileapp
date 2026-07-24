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
    internal var fuel: QueueLineFuel?
    internal var key: QueueLineKey?
    internal var available_actions: QueueLineActions?

    internal var urgency: String?
    internal var assignment_state: String?
    internal var options_count: Int?
    internal var payment_label: String?
    internal var status: String?        // "pending" | "staged" | "completed"
    internal var staged: Bool?
    internal var fully_staged: Bool?
    internal var completed: Bool?
    internal var readiness: String?
    internal var staged_by: String?     // employee who staged it (Entered By)
    internal var staged_at: String?     // timestamp it was staged

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
        fuel              <- map["fuel"]
        key               <- map["key"]
        available_actions <- map["available_actions"]

        urgency          <- map["urgency"]
        assignment_state <- map["assignment_state"]
        options_count    <- map["options_count"]
        payment_label    <- map["payment_label"]
        status           <- map["status"]
        staged           <- map["staged"]
        fully_staged     <- map["fully_staged"]
        completed        <- map["completed"]
        readiness        <- map["readiness"]
        staged_by        <- map["staged_by"]
        staged_at        <- map["staged_at"]
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

struct QueueLineFuel: Mappable {
    internal var state: String?
    internal var verified_by: String?
    internal var verified_at: String?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        state       <- map["state"]
        verified_by <- map["verified_by"]
        verified_at <- map["verified_at"]
    }
}

struct QueueLineKey: Mappable {
    internal var state: String?
    internal var confirmed_by: String?
    internal var confirmed_at: String?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        state        <- map["state"]
        confirmed_by <- map["confirmed_by"]
        confirmed_at <- map["confirmed_at"]
    }
}

struct QueueLineActions: Mappable {
    internal var assign_equipment: Bool?
    internal var switch_equipment: Bool?
    internal var mark_staged: Bool?
    internal var return_to_pending: Bool?
    internal var view_history: Bool?
    init?(map: Map) { mapping(map: map) }
    mutating func mapping(map: Map) {
        assign_equipment  <- map["assign_equipment"]
        switch_equipment  <- map["switch_equipment"]
        mark_staged       <- map["mark_staged"]
        return_to_pending <- map["return_to_pending"]
        view_history      <- map["view_history"]
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
                completion(false)
                return
            }

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
