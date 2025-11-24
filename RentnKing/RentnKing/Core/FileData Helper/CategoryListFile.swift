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
    } else {
        callAPIforCategoryList(CatrgoryParameater: CatrgoryParameater()) { isSaved in
            if isSaved {
                completion(getCatData())
            } else {
                completion([])
            }
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
