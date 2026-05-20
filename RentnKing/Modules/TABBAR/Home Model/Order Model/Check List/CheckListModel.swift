//
//  CheckListModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 10/09/24.
//

import Foundation
import ObjectMapper
import UIKit

class NoteModel: NSObject{
    var dNote: String = ""
    var rNote: String = ""

    var rStoreId: String = ""
    var rStore: String = ""

    var dEmplayess: String = ""
    var dEmplayessId: String = ""
    var rEmplayess: String = ""
    var rEmplayessId: String = ""
    
    var dSignature: UIImage?
    var rSignature: UIImage?
    
    var inTime: String = ""
    var outTime: String = ""
    
    var dSignatureUrl: String = ""
    var rSignatureUrl: String = ""

    var productID: Int = 0
    var machine_id: Int = 0
    
    init(dNote: String, rNote: String, rStoreId: String, rStore: String, dEmplayess: String, dEmplayessId: String, rEmplayess: String, rEmplayessId: String, dSignature: UIImage?, rSignature: UIImage?, productID: Int, machine_id: Int, dSignatureUrl: String, rSignatureUrl: String, inTime: String, outTime: String) {
        self.dNote = dNote
        self.rNote = rNote
        self.rStore = rStore
        self.rStoreId = rStoreId
        self.dEmplayess = dEmplayess
        self.dEmplayessId = dEmplayessId
        self.rEmplayess = rEmplayess
        self.rEmplayessId = rEmplayessId
        self.dSignature = dSignature
        self.rSignature = rSignature
        self.productID = productID
        self.machine_id = machine_id
        self.dSignatureUrl = dSignatureUrl
        self.rSignatureUrl = rSignatureUrl
        self.inTime = inTime
        self.outTime = outTime
    }
}

struct CheckListPriceModel: Mappable{
    internal var def_price: String?
    internal var diesel_price: String?
    internal var gas_price: String?
    internal var tire_repair: Float?
    internal var tire_10_ply: Float?
    internal var tire_14_ply: Float?

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        def_price <- map["def_price"]
        diesel_price <- map["diesel_price"]
        gas_price <- map["gas_price"]
        tire_repair <- map["tire_repair"]
        tire_10_ply <- map["tire_10_ply"]
        tire_14_ply <- map["tire_14_ply"]
    }
}


extension CheckListViewController :WebServiceHelperDelegate{
 
    func getOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater){
        guard let parameater = try? OrdersDetailsParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.orderDetails.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "orderDetails"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
    }
    
    
    func getCheckListPriceAPI(){
        
        //Declaration URL
        let strURL = "\(Url.checkListPrice.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "checkListPrice"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
    }
    
    
    func getEmployeesListAPI(){
        
        //Declaration URL
        let strURL = "\(Url.employeesList.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "employeesList"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
    }
    
    
    func getCategorys(){
    
        //Declaration URL
        let strURL = "\(Url.categorys.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "categorys"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
    }
    
    
    func getMachineListAPI(){
        
        //Declaration URL
        let strURL = "\(Url.machineList.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "machineList"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
    }
    
    func getStoreAddress(){
       
        //Declaration URL
        let strURL = "\(Url.getStores.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "getStores"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
    }
    
    func updateStatus(UpdateStatusParameater : UpdateStatusParameater, index : Int){
       
        guard let parameater = try? UpdateStatusParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.scheduleUpdate.absoluteString!)"

       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "scheduleUpdate"
        webHelper.methodType = "post"
        webHelper.selectIndex = index
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }
    
    func updateCheckList(arrCheckList : [[String : Any]]){
    
        print(arrCheckList)

        
        //Declaration URL
        let strURL = "\(Url.updateCheckList.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "updateCheckList"
        webHelper.methodType = "post"
        webHelper.selectIndex = 0
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.arryType = arrCheckList
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI2()
    }
    
    
    func updateCheckListImages(arrMutlipleimages : [[String : Any]]){
        
   
        //Declaration URL
        let strURL = "\(Url.updateCheckListImages.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "updateCheckListImages"
        webHelper.methodType = "post"
        webHelper.selectIndex = 0
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.arr_Mutlipleimages = arrMutlipleimages
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callCheckListAPI()
    }
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "orderDetails"{
                print(data)

                
                if let dicData = data["data"] as? NSDictionary{
                   
                    
                    //SET DATA
                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
                    self.objOrderData = OrdersModel(map: map)
                    let arrData = self.objOrderData.arrProduct
                    self.objOrderData.arrProduct = []
                    
                    //GET PRODUCT DATA
                    for obj in arrData{
                        if obj.objProduct?.checklist_id != 0{
                            self.objOrderData.arrProduct.append(obj)
                        }
                    }

                    
                    //SET SIGNATURE ARRAT
                    for obj in self.objOrderData.arrProduct{
                        self.arrOtherData.append(NoteModel(dNote: obj.delivery_note, rNote: obj.returned_note, rStoreId: "", rStore: "", dEmplayess: self.getEmployeesName(emp_id: obj.delivery_emp), dEmplayessId: "\(obj.delivery_emp)", rEmplayess: self.getEmployeesName(emp_id: obj.returned_emp), rEmplayessId: "\(obj.returned_emp)", dSignature: UIImage(), rSignature: UIImage(), productID: obj.product_id ?? 0, machine_id: obj.machine_id ?? 0, dSignatureUrl: obj.delivery_sign, rSignatureUrl: obj.return_sign, inTime: obj.inTime, outTime: obj.outTime))
                    }

                    //SET THE VIEW
                    self.setTheView()
                }
                else{
                    //SET THE VIEW
                    self.setTheView()
                }
            }
            else if strRequest == "categorys"{
                if let arrData = data["data"] as? NSArray{
                    
                    self.arrCategoryList = []
                    self.arrCategoryList = Mapper<CategoryModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrCategoryList = self.arrCategoryList.sorted(by: { $0.name ?? "" < $1.name ?? "" })
                    
                }
            }
            else if strRequest == "machineList"{
                if let arrData = data["data"] as? NSArray{
                   
                    self.arrMachineList = []
                    self.arrAllMachineList = []
                    self.arrMachineList = Mapper<MachineModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrMachineList = self.arrMachineList.sorted(by: { $0.machine_id ?? "" < $1.machine_id ?? "" })
                    self.arrAllMachineList = self.arrMachineList

                }
            }
            else if strRequest == "checkListPrice"{
                self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID, product_id: self.strProductID))

                if let dicData = data["data"] as? NSDictionary{
                    
                    //SET DATA
                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
                    self.objCheckListPrice = CheckListPriceModel(map: map)
                    
                }
            }
            else if strRequest == "employeesList"{
                self.getCheckListPriceAPI()


                if let arrData = data["data"] as? NSArray{
                   
                    self.arrEmployesList = []
                    self.arrEmployesList = Mapper<EmployeesModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrEmployesList = self.arrEmployesList.sorted(by: { $0.name ?? "" < $1.name ?? "" })

                }
            }
            else if strRequest == "getStores"{
                if let arrData = data["data"] as? NSArray{
                    
                    let arr = Mapper<StoreModel>().mapArray(JSONArray: arrData as! [[String : Any]])

                    self.arrStoreList = []
                    for obj in arr{
                        let address = "\(obj.address ?? ""), \(obj.city ?? ""), \(obj.state ?? ""), \(obj.zip_code ?? "")"
                        
                        var objData = obj
                        objData.fullAddress = address
                        self.arrStoreList.append(objData)
                    }
                }
            }
            else if strRequest == "scheduleUpdate"{
                //UPDATE COUNT
                GlobalMainConstants.appDelegate?.getScheduleCount()
                
                print(data)

                
                //UPDATE
                if self.objOrderData.arrDeliveryStatus.count != 0{
                    var objDelivery = self.objOrderData.arrDeliveryStatus[self.deliveryIndex]
                    
                    if self.isDeliveryType{
                        objDelivery.delivery_status?.value = "2"
                    }
                    else{
                        objDelivery.pickup_status?.value = "2"
                    }
                    
                    //UPDATE DATA
                    self.objOrderData.arrDeliveryStatus.remove(at: self.deliveryIndex)
                    self.objOrderData.arrDeliveryStatus.insert(objDelivery, at: self.deliveryIndex)
                }
                
                
                //RELOAD TABLE
                self.tblView.reloadData()
            }
            else if strRequest == "updateCheckList"{
                let arrData = self.getUploadedFiles()
                if arrData.count != 0{
                    self.updateCheckListImages(arrMutlipleimages: arrData)
                }
                else{
//                    self.delegate?.UpdateCheckListProduct(selectIndex: self.selectIndex, arrUpdateCheckList: self.arrOtherData)
                    NotificationCenter.default.post(name: .updateCheckList, object: nil, userInfo: ["checklist_data": self.arrOtherData, "index" : self.selectIndex] )

                    self.navigationController?.popViewController(animated: true)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                        showAlertMessage(strMessage: "Checklist Successfully Updated")
                    }
                }
                
            }
            else if strRequest == "updateCheckListImages"{
                
//                self.delegate?.UpdateCheckListProduct(selectIndex: self.selectIndex, arrUpdateCheckList: self.arrOtherData)
                NotificationCenter.default.post(name: .updateCheckList, object: nil, userInfo: ["checklist_data": self.arrOtherData, "index" : self.selectIndex] )

                self.navigationController?.popViewController(animated: true)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                    showAlertMessage(strMessage: "Checklist Successfully Updated")
                }
            }
        }
     
        else{
            indicatorHide()
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
            }
        }
    }
    
    func getUploadedFiles() -> [[String : Any]]{
        //SET IMAGE
        var arr_Mutlipleimages : [[String : Any]] = []
        for obj in self.arrOtherData{
            if (self.isDeliveryType ? obj.dSignature : obj.rSignature) != UIImage(){
                let dicData = ["img": (self.isDeliveryType ? obj.dSignature : obj.rSignature) ?? UIImage() ,
                               "name": "\(self.strOrderID)_\(obj.productID)_\(self.isDeliveryType ? "delivery" : "return").jpeg",
                               "type": "img",
                               "key": "file[]"] as [String : Any]
                arr_Mutlipleimages.append(dicData)
            }
        }
        
        return arr_Mutlipleimages
        
    }
    
    func getEmployeesName(emp_id : Int) -> String{
        if self.arrEmployesList.count == 0{
            return ""
        }
        
        let MenuID = self.arrEmployesList.map{$0.id}
        if let index = MenuID.firstIndex(of: emp_id){
            return self.arrEmployesList[index].name ?? ""
        }
        return ""
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        

        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}



extension CheckListUpdateViewController :WebServiceHelperDelegate{
    func getOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater){
        guard let parameater = try? OrdersDetailsParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.orderDetails.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "orderDetails"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
    }
    
    
    func getCheckListPriceAPI(){
        
        //Declaration URL
        let strURL = "\(Url.checkListPrice.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "checkListPrice"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
    }
    
    
    func getEmployeesListAPI(){
        
        //Declaration URL
        let strURL = "\(Url.employeesList.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "employeesList"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
    }
    
 
  
    func updateStatus(UpdateStatusParameater : UpdateStatusParameater, index : Int){
       
        guard let parameater = try? UpdateStatusParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.scheduleUpdate.absoluteString!)"

       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "scheduleUpdate"
        webHelper.methodType = "post"
        webHelper.selectIndex = index
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }
    
    func updateCheckList(arrCheckList : [[String : Any]]){
    
        print(arrCheckList)

        
        //Declaration URL
        let strURL = "\(Url.updateCheckList.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "updateCheckList"
        webHelper.methodType = "post"
        webHelper.selectIndex = 0
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.arryType = arrCheckList
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI2()
    }
    
    
    func updateCheckListImages(arrMutlipleimages : [[String : Any]]){
        
   
        //Declaration URL
        let strURL = "\(Url.updateCheckListImages.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "updateCheckListImages"
        webHelper.methodType = "post"
        webHelper.selectIndex = 0
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.arr_Mutlipleimages = arrMutlipleimages
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callCheckListAPI()
    }
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            print(data)
            if strRequest == "orderDetails"{
                
                
                if let dicData = data["data"] as? NSDictionary{
                    
                    //SET DATA
                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
                    self.objOrderData = OrdersModel(map: map)
                    let arrData = self.objOrderData.arrProduct
                    self.objOrderData.arrProduct = []
                    
                    //GET PRODUCT DATA
                    for obj in arrData{
                        if obj.objProduct?.checklist_id != 0{
                            self.objOrderData.arrProduct.append(obj)
                        }
                    }
                    
                    //SET SIGNATURE ARRAT
                    for obj in self.objOrderData.arrProduct{
                        self.arrOtherData.append(NoteModel(dNote: obj.delivery_note, rNote: obj.returned_note, rStoreId: "", rStore: "", dEmplayess: self.getEmployeesName(emp_id: obj.delivery_emp), dEmplayessId: "\(obj.delivery_emp)", rEmplayess: self.getEmployeesName(emp_id: obj.returned_emp), rEmplayessId: "\(obj.returned_emp)", dSignature: UIImage(), rSignature: UIImage(), productID: obj.product_id ?? 0, machine_id: obj.machine_id ?? 0, dSignatureUrl: obj.delivery_sign, rSignatureUrl: obj.return_sign, inTime: obj.inTime, outTime: obj.outTime))
                    }
                    
                    //SET THE VIEW
                    self.setTheView()
                }
                else{
                    //SET THE VIEW
                    self.setTheView()
                }
            }
            
            else if strRequest == "checkListPrice"{
                self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID, product_id: self.strProductID))

                if let dicData = data["data"] as? NSDictionary{
                    
                    //SET DATA
                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
                    self.objCheckListPrice = CheckListPriceModel(map: map)
                    
                }
            }
            else if strRequest == "employeesList"{
                self.getCheckListPriceAPI()

                
                if let arrData = data["data"] as? NSArray{
                    
                    self.arrEmployesList = []
                    self.arrEmployesList = Mapper<EmployeesModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    self.arrEmployesList = self.arrEmployesList.sorted(by: { $0.name ?? "" < $1.name ?? "" })
                    
                }
            }
            else if strRequest == "scheduleUpdate"{
                //UPDATE COUNT
                GlobalMainConstants.appDelegate?.getScheduleCount()
                
                
//                //UPDATE
//                if self.objOrderData.arrDeliveryStatus.count != 0{
//                    var objDelivery = self.objOrderData.arrDeliveryStatus[self.deliveryIndex]
//                    
//                    if self.isDeliveryType{
//                        objDelivery.delivery_status?.value = "2"
//                    }
//                    else{
//                        objDelivery.pickup_status?.value = "2"
//                    }
//                    
//                    //UPDATE DATA
//                    self.objOrderData.arrDeliveryStatus.remove(at: self.deliveryIndex)
//                    self.objOrderData.arrDeliveryStatus.insert(objDelivery, at: self.deliveryIndex)
//                }
//                
//                
//                //RELOAD TABLE
//                self.tblView.reloadData()
            }
            else if strRequest == "updateCheckList"{
                let arrData = self.getUploadedFiles()
                if arrData.count != 0{
                    self.updateCheckListImages(arrMutlipleimages: arrData)
                }
                else{
//                    self.delegate?.UpdateCheckListProduct(selectIndex: self.selectIndex, arrUpdateCheckList: self.arrOtherData)
                    
                    NotificationCenter.default.post(name: .updateCheckList, object: nil, userInfo: ["checklist_data": self.arrOtherData, "index" : self.selectIndex] )

                    
                    if self.isOrderDetailsView{
                        if let targetViewController = self.navigationController?.viewControllers.first(where: { $0 is OrderDetailsViewController  }) {
                            navigationController?.popToViewController(targetViewController, animated: true)
                        }
                    }
                    else{
                        if let targetViewController = self.navigationController?.viewControllers.first(where: { $0 is OrderListViewController }) {
                            navigationController?.popToViewController(targetViewController, animated: true)
                        }
                    }
                    
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                        showAlertMessage(strMessage: "Checklist Successfully Updated")
                    }
                }
                
            }
            else if strRequest == "updateCheckListImages"{
                
//                self.delegate?.UpdateCheckListProduct(selectIndex: self.selectIndex, arrUpdateCheckList: self.arrOtherData)
                NotificationCenter.default.post(name: .updateCheckList, object: nil, userInfo: ["checklist_data": self.arrOtherData, "index" : self.selectIndex] )

                if self.isOrderDetailsView{
                    if let targetViewController = self.navigationController?.viewControllers.first(where: { $0 is OrderDetailsViewController  }) {
                        navigationController?.popToViewController(targetViewController, animated: true)
                    }
                }
                else{
                    if let targetViewController = self.navigationController?.viewControllers.first(where: { $0 is OrderListViewController }) {
                        navigationController?.popToViewController(targetViewController, animated: true)
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                    showAlertMessage(strMessage: "Checklist Successfully Updated")
                }
            }
        }
     
        else{
            indicatorHide()
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
            }
        }
    }
    
    func getUploadedFiles() -> [[String : Any]]{
        //SET IMAGE
        var arr_Mutlipleimages : [[String : Any]] = []
        for obj in self.arrOtherData{
            if (self.isDeliveryType ? obj.dSignature : obj.rSignature) != UIImage(){
                let dicData = ["img": (self.isDeliveryType ? obj.dSignature : obj.rSignature) ?? UIImage() ,
                               "name": "\(self.strOrderID)_\(obj.productID)_\(self.isDeliveryType ? "delivery" : "return").jpeg",
                               "type": "img",
                               "key": "file[]"] as [String : Any]
                arr_Mutlipleimages.append(dicData)
            }
        }
        
        return arr_Mutlipleimages
        
    }
    
    func getEmployeesName(emp_id : Int) -> String{
        if self.arrEmployesList.count == 0{
            return ""
        }
        
        let MenuID = self.arrEmployesList.map{$0.id}
        if let index = MenuID.firstIndex(of: emp_id){
            return self.arrEmployesList[index].name ?? ""
        }
        return ""
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        

        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}
