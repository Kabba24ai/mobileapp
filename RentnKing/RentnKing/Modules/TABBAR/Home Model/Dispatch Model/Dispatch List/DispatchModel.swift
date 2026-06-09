//
//  DispatchModel.swift
//  RentnKing
//

import Foundation
import ObjectMapper

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

// MARK: - API Calls (extension on DispatchListViewController)

extension DispatchListViewController: WebServiceHelperDelegate {

    func callAPIforGetDispatchList(params: DispatchListParameter, completion: @escaping (Bool) -> Void) {
        guard let parameters = try? params.asDictionary() else {
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
            indicatorHide()
            self.isLoading = false

            guard error == nil else { completion(false); return }

            if data?.getStringForID(key: "success") == "1",
               let arrData = data?["jobs"] as? [[String: Any]] {
                let jobs = Mapper<DispatchJobModel>().mapArray(JSONArray: arrData)
                SDKUserDefault.saveMappableArray(jobs, for: "\(kFileStorageName.kDispatchJobList.rawValue)_\(params.date_filter)")
                completion(true)
            } else {
                completion(false)
            }
        }
    }

    func updateDispatchStatus(params: DispatchUpdateStatusParameter, index: Int) {
        guard let parameters = try? params.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        let strURL = "\(Url.dispatchUpdateStatus.absoluteString!)"
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "dispatchUpdateStatus"
        webHelper.methodType = "post"
        webHelper.selectIndex = index
        webHelper.strURL = strURL
        webHelper.dictType = parameters
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }

    func getLocalDispatchJobs(dateFilter: String) -> [DispatchJobModel] {
        return SDKUserDefault.getMappableArray(DispatchJobModel.self,
            for: "\(kFileStorageName.kDispatchJobList.rawValue)_\(dateFilter)") ?? []
    }

    // MARK: - WebServiceHelperDelegate

    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String) {
        indicatorHide()
        isLoading = false
        objRefresh?.endRefreshing()

        if data.getStringForID(key: "success") == "1" {
            if strRequest == "dispatchUpdateStatus" {
                if arrDispatchJobs.indices.contains(index) {
                    arrDispatchJobs.remove(at: index)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.tblView.reloadData()
                }
            }
        } else {
            setTheView()
            showAlertMessage(strMessage: str.somethingWentWrong)
        }
    }

    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {}

    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        isLoading = false
        emptyDataView.isHidden = false
        showAlertMessage(strMessage: str.somethingWentWrong)
    }
}
