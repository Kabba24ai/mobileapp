//
//  CategoryListFile.swift
//  RentnKing
//
//  Created by DEEPAK JAIN on 03/10/25.
//

import UIKit
import ObjectMapper
import MMKV


func callAPIforCategoryList(CatrgoryParameater : CatrgoryParameater, completion: @escaping (Bool) -> Void) {
    
    guard let parameater = try? CatrgoryParameater.asDictionary() else {
        showAlertMessage(strMessage: str.invalidRequestParamater)
        return
    }
    let tenant = KabbaTenantScope.currentKey   // the company this request is for (Dispatch offline Phase 4, Amendment B)

    //Declaration URL
    let strURL = "\(Url.categoryList.absoluteString!)"
    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = parameater
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.serviceWithAlert = true
    webHelper.indicatorShowOrHide = false
    
    webHelper.callAPIwithCompletation { data, _, _, error in
        guard let data = data, error == nil else {
            completion(false)
            return
        }

        if data.getStringForID(key: "success") == "1"{
            if let arrData = data["product_categories"] as? NSArray {
                
                var arrCategorys = [CategoryModel]()
                var arrData = Mapper<CategoryModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                arrData = arrData.sorted(by: { $0.name ?? "" < $1.name ?? "" })
                

                for obj in arrData{
                    arrCategorys.append(obj)

                    if obj.arrChildCategories.count != 0{
                        let arrChildData = obj.arrChildCategories.sorted(by: { $0.name ?? "" < $1.name ?? "" })
                        for objChild in arrChildData{
                            var obj = objChild
                            obj.name = "--\(obj.name ?? "")"
                            arrCategorys.append(obj)
                        }
                    }
                }
                
                
                //SET EMPTY OBJECT
                var objData : CategoryModel!
                let map = Map(mappingType: .fromJSON, JSON: [:])
                objData = CategoryModel(map: map)
                objData.id = 0
                objData.name = "All"
                
                //ADD
                arrCategorys.insert(objData, at: 0)
                //SAVE ARRAY
                SDKUserDefault.saveMappableArray(arrCategorys, for: kFileStorageName.kCateoryList.rawValue, tenantKey: tenant)
                completion(true)
            }
        }
    }
    
}



func callAPIforCustomerTagList(completion: @escaping (Bool) -> Void) {

    //Declaration URL
    let strURL = "\(Url.customerTagList.absoluteString!)"
    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = [:]
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.serviceWithAlert = true
    webHelper.indicatorShowOrHide = false
    
    webHelper.callAPIwithCompletation { data, _, _, error in
        guard let data = data, error == nil else {
            completion(false)
            return
        }

        if data.getStringForID(key: "success") == "1" {
            if let arrData = data["customer_tags"] as? NSArray {
                
                var arrData = Mapper<CustomerTagModel>().mapArray(JSONArray: arrData as! [[String : Any]])

                //SET EMPTY OBJECT
                var objData : CustomerTagModel!
                let map = Map(mappingType: .fromJSON, JSON: [:])
                objData = CustomerTagModel(map: map)
                objData.id = 0
                objData.name = "All"
                
                //ADD
                arrData.insert(objData, at: 0)
                //SAVE ARRAY
                SDKUserDefault.saveMappableArray(arrData, for: kFileStorageName.kCustomerTagList.rawValue)
                completion(true)
            }
        }
    }
    
}


func getPriceListAPI( completion: @escaping (Bool) -> Void) {
    let tenant = KabbaTenantScope.currentKey   // the company this request is for (Dispatch offline Phase 4, Amendment B)

    //Declaration URL
    let strURL = "\(Url.priceList.absoluteString!)"
    
   
    //Create object for webservicehelper and start to call method
    let webHelper = WebServiceHelper()
    webHelper.strMethodName = "priceList"
    webHelper.methodType = "get"
    webHelper.strURL = strURL
    webHelper.dictType = [:]
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.serviceWithAlert = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { data, _, _, error in
        guard let data = data, error == nil else {
            completion(false)
            return
        }

        if data.getStringForID(key: "success") == "1" {
                        
            if let dicData = data["configurations"] as? NSDictionary{
                if let arrData = dicData["Price Settings"] as? NSArray, let arrProduct = dicData["Product Settings"] as? NSArray{
                    let arrPriceList = Mapper<PriceListModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    let arrProductList = Mapper<PriceListModel>().mapArray(JSONArray: arrProduct as! [[String : Any]])
                    
                    // Overwrite old data
                    SDKUserDefault.saveMappableArray(arrPriceList, for: kFileStorageName.kPriceList.rawValue, tenantKey: tenant)
                    SDKUserDefault.saveMappableArray(arrProductList, for: kFileStorageName.kProductSettings.rawValue, tenantKey: tenant)
                    completion(true)
                }
            }
        } else {
            completion(false)
        }
    }    }


// MARK: - Get Categories
func getCategoryList(completion: @escaping ([CategoryModel]) -> Void) {
    if !getCatData().isEmpty {
        completion(getCatData())
    }
    
    callAPIforCategoryList(CatrgoryParameater: CatrgoryParameater()) { isSaved in
        if isSaved {
            completion(getCatData())
        } else if getCatData().isEmpty {
            // Offline / failed refresh: keep the list the caller was already given (Dispatch
            // offline Phase 4) — [] only when there is no cached list at all.
            completion([])
        }
    }

}


func getCatData() -> [CategoryModel] {
    var arrCategoryList : [CategoryModel] = []

    //GET DATA FROM MKV
    if let arr_data = SDKUserDefault.getMappableArray(CategoryModel.self, for: kFileStorageName.kCateoryList.rawValue) {
        arrCategoryList = arr_data
    }

    return arrCategoryList
}


//MARK: - FOR CUSTOMER TAG
func getCustomerTagList(completion: @escaping ([CustomerTagModel]) -> Void) {
    if !getTagData().isEmpty {
        completion(getTagData())
    }
    
    callAPIforCustomerTagList { isSaved in
        if isSaved {
            completion(getTagData())
        } else {
            completion([])
        }
    }

}


func getTagData() -> [CustomerTagModel] {
    var arrTagList : [CustomerTagModel] = []

    //GET DATA FROM MKV
    if let arr_data = SDKUserDefault.getMappableArray(CustomerTagModel.self, for: kFileStorageName.kCustomerTagList.rawValue) {
        arrTagList = arr_data
    }

    return arrTagList
}


func getPriceList(completion: @escaping ([PriceListModel]) -> Void) {
    if !getPriceData().isEmpty {
        completion(getPriceData())
    }
    
    getPriceListAPI() { isSaved in
        if isSaved {
            completion(getPriceData())
        } else if getPriceData().isEmpty {
            // Offline / failed refresh: keep the list the caller was already given (Dispatch
            // offline Phase 4) — [] only when there is no cached list at all.
            completion([])
        }
    }
}

func getProductSettingList(completion: @escaping ([PriceListModel]) -> Void) {
    if !getProductSettingData().isEmpty {
        completion(getProductSettingData())
    }
    
    getPriceListAPI() { isSaved in
        if isSaved {
            completion(getProductSettingData())
        } else if getProductSettingData().isEmpty {
            // Offline / failed refresh: keep the list the caller was already given (Dispatch
            // offline Phase 4) — [] only when there is no cached list at all.
            completion([])
        }
    }
}




func getPriceData() -> [PriceListModel] {
    var arrPriceList : [PriceListModel] = []

    //GET DATA FROM MKV
    if let arr_data = SDKUserDefault.getMappableArray(PriceListModel.self, for: kFileStorageName.kPriceList.rawValue) {
        arrPriceList = arr_data
    }

    return arrPriceList
}

func getProductSettingData() -> [PriceListModel] {
    var arrProductSettingList : [PriceListModel] = []

    //GET DATA FROM MKV
    if let arr_data = SDKUserDefault.getMappableArray(PriceListModel.self, for: kFileStorageName.kProductSettings.rawValue) {
        arrProductSettingList = arr_data
    }

    return arrProductSettingList
}



// MARK: - Get Employee List
func getEmployeeList(completion: @escaping ([EmployeesModel]) -> Void) {
    if !getEmployeeData().isEmpty {
        completion(getEmployeeData())
    }
    
    CallAPIforGetEmployeesList(CatrgoryParameater: CatrgoryParameater()) { isSaved in
        if isSaved {
            completion(getEmployeeData())
        } else if getEmployeeData().isEmpty {
            // Offline / failed refresh: keep the list the caller was already given (Dispatch
            // offline Phase 4) — [] only when there is no cached list at all.
            completion([])
        }
    }
}
func getEmployeeData() -> [EmployeesModel] {
    if let arr = SDKUserDefault.getMappableArray(EmployeesModel.self, for: kFileStorageName.kEmployesList.rawValue) {
        return arr
    }
    return []
}

func getDriverEmployeeList(completion: @escaping ([EmployeesModel]) -> Void) {
    if !getDriverEmployeeData().isEmpty {
        completion(getDriverEmployeeData())
    }
    
    CallAPIforGetEmployeesList(CatrgoryParameater: CatrgoryParameater(is_driver: true)) { isSaved in
        if isSaved {
            completion(getDriverEmployeeData())
        } else if getDriverEmployeeData().isEmpty {
            // Offline / failed refresh: keep the list the caller was already given (Dispatch
            // offline Phase 4) — [] only when there is no cached list at all.
            completion([])
        }
    }
}

func getDriverEmployeeData() -> [EmployeesModel] {
    if let arr = SDKUserDefault.getMappableArray(EmployeesModel.self, for: "\(kFileStorageName.kEmployesList.rawValue)_Driver") {
        return arr
    }
    return []
}



func CallAPIforGetEmployeesList(CatrgoryParameater : CatrgoryParameater, completion: @escaping (Bool) -> Void) {
    let tenant = KabbaTenantScope.currentKey   // the company this request is for (Dispatch offline Phase 4, Amendment B)
    fetchEmployeesPage(CatrgoryParameater, page: 1, collected: [], tenant: tenant, completion: completion)
}

/// Reads EVERY page of `POST users` (2026-11-23): the phone used to keep page 1 only, so on a
/// Kabba with more active employees than one page the rest could never be picked as Delivered By
/// / Returned By. The cached list is replaced only when every page arrived; a failed page keeps
/// the list the phone already has and reports `false` (it used to report nothing at all).
private func fetchEmployeesPage(_ parameters: CatrgoryParameater, page: Int, collected: [EmployeesModel],
                                tenant: String?, completion: @escaping (Bool) -> Void) {
    var request = parameters
    request.page = "\(page)"
    guard let parameater = try? request.asDictionary() else {
        showAlertMessage(strMessage: str.invalidRequestParamater)
        completion(false)
        return
    }

    //Create object for webservicehelper and start to call method
    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = "\(Url.employeesList.absoluteString!)"
    webHelper.dictType = parameater
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.serviceWithAlert = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { data, arr, isDic, error in
        guard data?.getStringForID(key: "success") == "1", let rows = data?["users"] as? [[String: Any]] else {
            completion(false)
            return
        }
        let all = collected + Mapper<EmployeesModel>().mapArray(JSONArray: rows)
        let lastPage = EmployeeDirectoryPaging.lastPage(in: data?["pagination"] as? [String: Any])
        if let next = EmployeeDirectoryPaging.nextPage(after: page, lastPage: lastPage) {
            fetchEmployeesPage(parameters, page: next, collected: all, tenant: tenant, completion: completion)
            return
        }

        // Newest-first pages shift when someone is added mid-read: keep each employee once.
        var seen = Set<Int>()
        let unique = all.filter { employee in
            guard let id = employee.id else { return true }
            return seen.insert(id).inserted
        }
        let sorted = unique.sorted(by: { $0.name ?? "" < $1.name ?? "" })

        //SAVE ARRAY
        let key = parameters.is_driver ? "\(kFileStorageName.kEmployesList.rawValue)_Driver" : kFileStorageName.kEmployesList.rawValue
        SDKUserDefault.saveMappableArray(sorted, for: key, tenantKey: tenant)
        completion(true)
    }
}
