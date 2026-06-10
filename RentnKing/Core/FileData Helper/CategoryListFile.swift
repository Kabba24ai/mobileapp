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
                SDKUserDefault.saveMappableArray(arrCategorys, for: kFileStorageName.kCateoryList.rawValue)
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
                if let arrData = dicData["Price Settings"] as? NSArray{
                    let arrPriceList = Mapper<PriceListModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    // Overwrite old data
                    SDKUserDefault.saveMappableArray(arrPriceList, for: kFileStorageName.kPriceList.rawValue)
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
        } else {
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
        } else {
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




// MARK: - Get Employee List
func getEmployeeList(completion: @escaping ([EmployeesModel]) -> Void) {
    if !getEmployeeData().isEmpty {
        completion(getEmployeeData())
    }
    
    CallAPIforGetEmployeesList(CatrgoryParameater: CatrgoryParameater()) { isSaved in
        if isSaved {
            completion(getEmployeeData())
        } else {
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

func CallAPIforGetEmployeesList(CatrgoryParameater : CatrgoryParameater, completion: @escaping (Bool) -> Void) {
    
    guard let parameater = try? CatrgoryParameater.asDictionary() else {
        showAlertMessage(strMessage: str.invalidRequestParamater)
        return
    }
    
    //Declaration URL
    let strURL = "\(Url.employeesList.absoluteString!)"
    
    //Create object for webservicehelper and start to call method
    let webHelper = WebServiceHelper()
    webHelper.methodType = "post"
    webHelper.strURL = strURL
    webHelper.dictType = parameater
    webHelper.dictHeader = NSDictionary()
    webHelper.showLogForCallingAPI = true
    webHelper.serviceWithAlert = true
    webHelper.indicatorShowOrHide = false
    webHelper.callAPIwithCompletation { data, arr, isDic, error in
        
        if data?.getStringForID(key: "success") == "1" {
            if let arrData = data?["users"] as? NSArray {
                
                var arrData = Mapper<EmployeesModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                arrData = arrData.sorted(by: { $0.name ?? "" < $1.name ?? "" })
                
                //SAVE ARRAY
                SDKUserDefault.saveMappableArray(arrData, for: kFileStorageName.kEmployesList.rawValue)
                completion(true)
            }
        }
    }
}
