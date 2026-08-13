//
//  ManualDispatchModel.swift
//  RentnKing
//
//  Model + API for the Manual Dispatch board (order-free driver tasks).
//  Endpoints (admin/v1): POST dispatch/manual, POST dispatch/manual/update-status.
//
//  Manual Dispatch is a SIBLING module to Queue Line — it deliberately does NOT
//  reuse the order/schedule DTOs (SchedulesModel) because a manual task has no
//  order, product, equipment or checklist. It maps the server's clean, flat
//  "jobs" payload from the /dispatch/manual endpoint.
//

import Foundation
import ObjectMapper
import UIKit

// MARK: - Status

/// The Manual Dispatch lifecycle, mirroring the server enum
/// (App\Enums\Dispatch\ManualDispatchStatus). Values are the human labels the
/// API sends/accepts verbatim.
enum ManualDispatchStatus {
    static let pending   = "Pending"
    static let assigned  = "Assigned"
    static let onMyWay   = "On My Way"
    static let arrived   = "Arrived"
    static let completed = "Completed"
    static let cancelled = "Cancelled"

    /// The single forward action offered on a card, given the current status.
    /// Pending advances by being assigned a driver on the web side, so the app
    /// only progresses Assigned → On My Way → Arrived → Completed.
    static func next(after status: String?) -> String? {
        switch status {
        case assigned: return onMyWay
        case onMyWay:  return arrived
        case arrived:  return completed
        default:       return nil
        }
    }

    /// A non-terminal task can still be cancelled.
    static func isTerminal(_ status: String?) -> Bool {
        return status == completed || status == cancelled
    }
}

// MARK: - Item

struct ManualDispatchModel: Mappable {
    internal var unique_id: String?
    internal var is_manual: Bool?
    internal var type: String?            // e.g. "Equipment Pickup" (type_label)
    internal var description: String?     // task / description snapshot
    internal var status: String?          // Pending | Assigned | On My Way | Arrived | Completed | Cancelled
    internal var priority: Int?

    internal var date: String?            // formatted dispatch date
    internal var time: String?            // dispatch time (nullable)

    internal var location_name: String?
    internal var address: String?         // full address (server: full_address)
    internal var city: String?
    internal var state: String?
    internal var zip_code: String?
    internal var contact_name: String?
    internal var phone: String?
    internal var instructions: String?
    internal var store: String?           // originating store name

    init?(map: Map) { mapping(map: map) }

    mutating func mapping(map: Map) {
        unique_id     <- map["unique_id"]
        is_manual     <- map["is_manual"]
        type          <- map["type"]
        description   <- map["description"]
        status        <- map["status"]
        priority      <- map["priority"]
        date          <- map["date"]
        time          <- map["time"]
        location_name <- map["location_name"]
        address       <- map["address"]
        city          <- map["city"]
        state         <- map["state"]
        zip_code      <- map["zip_code"]
        contact_name  <- map["contact_name"]
        phone         <- map["phone"]
        instructions  <- map["instructions"]
        store         <- map["store"]
    }

    /// "City, ST" convenience for card subtitles.
    var locationLine: String {
        return [city, state].compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: ", ")
    }
}

// MARK: - API Parameters

struct ManualDispatchListParameter: Codable {
    var date_filter: String   // "Today" | "Tomorrow" | "All"
}

struct ManualDispatchUpdateStatusParameter: Codable {
    var manual_dispatch_task_unique_id: String
    var status: String
}

// MARK: - API (extension on the VC, mirroring QueueLine)

extension ManualDispatchViewController {

    /// POST dispatch/manual → maps the flat "jobs" array, persists it locally
    /// (offline cache like Queue Line), and reports success. Scoped server-side
    /// to the logged-in driver via the Bearer token — no driver_id is sent.
    func callManualDispatchListAPI(completion: @escaping (_ success: Bool) -> Void) {
        let params = ManualDispatchListParameter(date_filter: self.dateFilter)
        guard let parameters = try? params.asDictionary() else {
            completion(false)
            return
        }

        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "manualDispatchList"
        webHelper.methodType = "post"
        webHelper.strURL = "\(Url.manualDispatchList.absoluteString ?? "")"
        webHelper.dictType = parameters
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false

        webHelper.callAPIwithCompletation { data, _, _, error in
            indicatorHide()
            guard error == nil, let data = data,
                  data.getStringForID(key: "success") == "1",
                  let arr = data["jobs"] as? [[String: Any]] else {
                completion(false)
                return
            }

            let list = Mapper<ManualDispatchModel>().mapArray(JSONArray: arr)
            SDKUserDefault.saveMappableArray(list, for: kFileStorageName.kManualDispatchList.rawValue)
            completion(true)
        }
    }

    /// Reads the locally persisted manual-dispatch tasks (offline cache).
    func getManualDispatchData() -> [ManualDispatchModel] {
        return SDKUserDefault.getMappableArray(ManualDispatchModel.self, for: kFileStorageName.kManualDispatchList.rawValue) ?? []
    }
}

/// POST dispatch/manual/update-status. Free function so BOTH the board and the
/// detail screen can trigger a transition. On success the caller refetches the
/// list (no optimistic local mutation), mirroring Queue Line.
func updateManualDispatchStatus(uniqueId: String, status: String, completion: @escaping (_ success: Bool) -> Void) {
    let params = ManualDispatchUpdateStatusParameter(manual_dispatch_task_unique_id: uniqueId, status: status)
    guard let parameters = try? params.asDictionary() else {
        completion(false)
        return
    }

    let webHelper = WebServiceHelper()
    webHelper.strMethodName = "manualDispatchUpdateStatus"
    webHelper.methodType = "post"
    webHelper.strURL = "\(Url.manualDispatchUpdateStatus.absoluteString ?? "")"
    webHelper.dictType = parameters
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.serviceWithAlert = true
    webHelper.indicatorShowOrHide = true

    webHelper.callAPIwithCompletation { data, _, _, error in
        indicatorHide()
        let ok = (error == nil) && (data?.getStringForID(key: "success") == "1")
        completion(ok)
    }
}
