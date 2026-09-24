//
//  DispatchModel.swift
//  RentnKing
//

import Foundation
import ObjectMapper
import UIKit

// MARK: - Data Model

struct DispatchJobModel: Mappable {
    var id: Int?
    var unique_id: String?
    var product_name: String?
    var schedule_type: String?   // "Delivery" or "Return"
    var priority: Int?

    var date: String?
    var time: String?
    var status: String?
    var transport_mode: String?

    var start_point: String?     // store name driver departs from (Delivery only)
    var end_point: String?       // store name driver returns to (Return only)

    var customer_name: String?
    var customer_phone: String?
    var address: String?
    var address_full: String?
    var equipment_name: String?

    var order_unique_id: String?
    var order_number: String?

    init?(map: Map) { mapping(map: map) }

    mutating func mapping(map: Map) {
        id             <- map["id"]
        unique_id      <- map["unique_id"]
        product_name   <- map["product_name"]
        schedule_type  <- map["schedule_type"]
        priority       <- map["priority"]
        date           <- map["date"]
        time           <- map["time"]
        status         <- map["status"]
        transport_mode <- map["transport_mode"]
        start_point    <- map["start_point"]
        end_point      <- map["end_point"]
        customer_name  <- map["customer_name"]
        customer_phone <- map["customer_phone"]
        address        <- map["address"]
        address_full   <- map["address_full"]
        equipment_name <- map["equipment_name"]
        order_unique_id <- map["order_unique_id"]
        order_number   <- map["order_number"]
    }

    var isDelivery: Bool { schedule_type == "Delivery" }
}

// MARK: - API Parameter

struct DispatchListParameter: Codable {
    var date_filter: String   // "Today", "Tomorrow", "All"
    var driver_id: String?    // nil = self (logged-in driver); set for admin view
}

struct DispatchUpdateStatusParameter: Codable {
    var order_product_unique_id: String
    var schedule_type: String    // "Delivery" or "Return"
    var schedule_status: String  // "Completed"
}

extension DispatchListViewController.DispatchParameater {
    /// Review F4: the presentation scope this request describes.
    var feedScope: DispatchFeedScope {
        DispatchFeedScope(pending: schedule_status == "Pending", scheduleType: schedule_type, dateFilter: date_filter,
                          driverId: driver_id, categoryId: category_id, search: search, transportMode: transport_mode)
    }
}

// MARK: - API Calls (extension on DispatchListViewController)
extension DispatchListViewController :WebServiceHelperDelegate{
    
    //LOADER
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            lblDelivery,
            lblPickup
        ]
    }
    
    
    struct DispatchParameater: Codable {
        var page : String
        var per_page : String = "\(Application.PageLimit)"
        var schedule_type : String //All,Delivery,Return
        var schedule_status : String  // 1 = pending , 2 = completed
        var category_id : String

        var search : String = ""
        var transport_mode : String  //ALll, Truck, Store
        var date_filter : String //= "Today" //Today, All
        var driver_id : String
        // Dispatch parity (Phase 6A) — opt into the mixed contract: the
        // response carries manual_jobs (page 1) and the server scopes a
        // missing driver_id to the authenticated driver.
        var include_manual : String = "1"
    }

    /// `ticket` binds the answer to the scope that asked (review F4): an obsolete answer writes
    /// nothing — no order slot, no manual list, no pagination — and completes as not saved.
    func callAPIforGetDispatchList(DispatchParameater: DispatchParameater, ticket: DispatchFeedRequests.Ticket,
                                   completion: @escaping (Bool) -> Void) {
        
        guard let parameters = try? DispatchParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            completion(false)
            return
        }
        
        let strURL = "\(Url.dispatchList.absoluteString!)"
        
        let webHelper = WebServiceHelper()
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameters
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        
        webHelper.callAPIwithCompletation { [weak self] data, arr, isDic, error in
            guard let self = self else { return }
            guard self.isCurrent(ticket) else {
                completion(false)
                return
            }

            indicatorHide()
            self.isLoading = false
            
            guard error == nil else {
                completion(false)
                return
            }
            
            print("API URL====>>\(strURL)\n\nParams:===>\(parameters)\n\nResponse:====>>\(data)")
            
            if data?.getStringForID(key: "success") == "1",
               let arrData = data?["orders"] as? [[String: Any]] {

                let newOrders = Mapper<SchedulesModel>().mapArray(JSONArray: arrData)

                // Dispatch parity (Phase 6A) — the server's pagination block is
                // authoritative for "is there another page": the old heuristic
                // (accumulated cache count vs a mismatched threshold) locked the
                // screen into an append-only merge that never removed rows.
                if let pagination = data?["pagination"] as? [String: Any] {
                    self.serverLastPage = (pagination["last_page"] as? Int) ?? 1
                } else {
                    self.serverLastPage = newOrders.isEmpty ? self.pageCount : self.pageCount + 1
                }

                // Manage local storage
                if DispatchParameater.page == "1" {
                    // Overwrite old data — a fresh page-1 snapshot REPLACES the
                    // cached server truth (jobs reassigned away disappear here).
                    SDKUserDefault.saveMappableArray(newOrders, for: "\(kFileStorageName.kDispatchJobList.rawValue)_\(DispatchParameater.schedule_type)_\(DispatchParameater.date_filter)_\(DispatchParameater.driver_id)")

                    // Manual Dispatch tasks ride along on page 1 (mixed
                    // contract). The server snapshot replaces the cached one;
                    // an absent key (older server) clears rather than
                    // resurrects state the server no longer vouches for. A
                    // Return-only request deliberately carries no manual jobs
                    // (web-board rule: manual lives in the Deliveries column),
                    // so it must not wipe the cache either.
                    if DispatchParameater.schedule_type != "Return" {
                        let manualSnapshot = (data?["manual_jobs"] as? [[String: Any]]).map(DispatchManualJob.decodeList(fromJSONArray:))
                        let key = self.manualCacheKey(dateFilter: DispatchParameater.date_filter, driverId: DispatchParameater.driver_id)
                        let reconciled = DispatchWorkload.reconciledManualList(
                            cached: self.getDispatchManualData(key: key),
                            serverSnapshot: manualSnapshot
                        )
                        SDKUserDefault.saveCodableArray(reconciled, for: key)
                    }

                    self.lastDispatchServerSyncAt = Date()
                } else {
                    // Append to local
                    var existing = self.getDispatchOrderData(schedule_type: DispatchParameater.schedule_type)

                    // Avoid duplicates
                    let filteredNew = newOrders.filter { newItem in
                        !existing.contains(where: { $0.id == newItem.id })
                    }

                    existing.append(contentsOf: filteredNew)
                    SDKUserDefault.saveMappableArray(existing, for: "\(kFileStorageName.kDispatchJobList.rawValue)_\(DispatchParameater.schedule_type)_\(DispatchParameater.date_filter)_\(DispatchParameater.driver_id)")

                }

                completion(true)
            } else {
                completion(false)
            }
        }
    }
    
 
    
   

    /// Dispatch offline (Phase 3, D4): when the durable offline cache supplies the order legs,
    /// only the live feed's page-1 Manual Dispatch rider is fetched (per_page=1; its order row
    /// is ignored and never written to the order cache slot). Manual tasks stay on the existing
    /// feed + per-driver cache — best effort, NOT part of the guaranteed offline working set.
    func callAPIforDispatchManualRider(DispatchParameater: DispatchParameater, ticket: DispatchFeedRequests.Ticket,
                                       completion: @escaping (Bool) -> Void) {
        var params = DispatchParameater
        params.page = "1"
        params.per_page = "1"
        // Web-board rule: manual tasks live in the Deliveries column — Return-only carries none.
        guard params.schedule_type != "Return", let parameters = try? params.asDictionary() else {
            completion(false)
            return
        }

        let webHelper = WebServiceHelper()
        webHelper.methodType = "post"
        webHelper.strURL = "\(Url.dispatchList.absoluteString!)"
        webHelper.dictType = parameters
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = false
        webHelper.indicatorShowOrHide = false

        webHelper.callAPIwithCompletation { [weak self] data, arr, isDic, error in
            // Review F4: an answer for a scope the screen has left is discarded unwritten.
            guard let self = self, self.isCurrent(ticket), error == nil, data?.getStringForID(key: "success") == "1" else {
                completion(false)
                return
            }
            let manualSnapshot = (data?["manual_jobs"] as? [[String: Any]]).map(DispatchManualJob.decodeList(fromJSONArray:))
            // Written under the REQUEST's driver + day, never whichever the screen shows now.
            let key = self.manualCacheKey(dateFilter: params.date_filter, driverId: params.driver_id)
            let reconciled = DispatchWorkload.reconciledManualList(cached: self.getDispatchManualData(key: key), serverSnapshot: manualSnapshot)
            SDKUserDefault.saveCodableArray(reconciled, for: key)
            completion(true)
        }
    }

    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
        indicatorHide()
        self.isLoading = false
        self.stopAnimatingView()
        self.objRefresh?.endRefreshing()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "scheduleUpdate"{
                

                print(data)
                if self.arrDispatchList.count != 0, index < self.arrDispatchList.count {

                    //UPDATE ARRAY — persist + re-weave so the cached snapshot
                    //agrees with the screen (Dispatch parity, Phase 6A).
                    self.rememberOfflineEdit(self.arrDispatchList[index], removed: true)
                    self.arrDispatchList.remove(at: index)
                    self.persistOrderListAndRebuild()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                        //RELOAD TABLE
                        self.tblView.reloadData()
                    }
                }
            }
        }
        else{
            print(strRequest)
            print(data)

            indicatorHide()
            //SET THE VIEW
            self.setTheView()
            if strRequest != "scheduleList"{
                showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")

            }
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        self.isLoading = false
        self.setTheView()
        
        //NO DATA
        self.emptyDataView.isHidden = false

        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}
