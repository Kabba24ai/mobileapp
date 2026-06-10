//
//  CheckListUpdateModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 04/09/25.
//

import Foundation
import ObjectMapper
import UIKit



extension CheckListUpdateViewController :WebServiceHelperDelegate{
//    func getOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater){
//        guard let parameater = try? OrdersDetailsParameater.asDictionary() else {
//            showAlertMessage(strMessage: str.invalidRequestParamater)
//            return
//        }
//
//        //Declaration URL
//        let strURL = "\(Url.orderDetails.absoluteString!)"
//        
//       
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "orderDetails"
//        webHelper.methodType = "post"
//        webHelper.strURL = strURL
//        webHelper.dictType = parameater
//        webHelper.dictHeader = NSDictionary()
//        webHelper.delegateWeb = self
//        webHelper.showLogForCallingAPI = true
//        webHelper.serviceWithAlert = true
//        webHelper.indicatorShowOrHide = false
//        webHelper.callAPI()
//    }
    
//    func getEmployeesListAPI(CatrgoryParameater : CatrgoryParameater){
//        
//        guard let parameater = try? CatrgoryParameater.asDictionary() else {
//            showAlertMessage(strMessage: str.invalidRequestParamater)
//            return
//        }
//        
//        //Declaration URL
//        let strURL = "\(Url.employeesList.absoluteString!)"
//        
//       
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "employeesList"
//        webHelper.methodType = "post"
//        webHelper.strURL = strURL
//        webHelper.dictType = parameater
//        webHelper.dictHeader = NSDictionary()
//        webHelper.delegateWeb = self
//        webHelper.showLogForCallingAPI = true
//        webHelper.serviceWithAlert = true
//        webHelper.indicatorShowOrHide = false
//        webHelper.callAPI()
//    }
    
       
       func getCheckListPriceAPI(CheckListParameater : CheckListParameater, index : Int){
           guard let parameater = try? CheckListParameater.asDictionary() else {
               showAlertMessage(strMessage: str.invalidRequestParamater)
               return
           }
           
           //Declaration URL
           let strURL = "\(Url.customerCheckList.absoluteString!)"
           
          
           //Create object for webservicehelper and start to call method
           let webHelper = WebServiceHelper()
           webHelper.strMethodName = "customerCheckList"
           webHelper.methodType = "post"
           webHelper.strURL = strURL
           webHelper.dictType = parameater
           webHelper.selectIndex = index
           webHelper.dictHeader = NSDictionary()
           webHelper.delegateWeb = self
           webHelper.showLogForCallingAPI = true
           webHelper.serviceWithAlert = true
           webHelper.indicatorShowOrHide = false
           webHelper.callAPI()
       }


    
    func getUploadedFiles() -> [[String : Any]]{
        //SET IMAGE
        var arr_Mutlipleimages : [[String : Any]] = []
        for obj in self.arrOtherData{
            if (self.isDeliveryType ? obj.dSignature : obj.rSignature) != UIImage(){
                let dicData = ["img": (self.isDeliveryType ? obj.dSignature : obj.rSignature) ?? UIImage() ,
                               "name": "\(Date().timeIntervalSince1970).jpeg",
                               "key": "signature_media"] as [String : Any]
                arr_Mutlipleimages.append(dicData)
            }
        }
        
        return arr_Mutlipleimages
    }
  
    func updateCheckList(dicCheckList : [String : Any]){
        ImpactGenerator()
       
        //Declaration URL
        var strURL = ""
        if self.isDeliveryType{
            strURL = "\(Url.updateDeliveryCheckList.absoluteString!)"
        }
        else{
            strURL = "\(Url.updateReturnCheckList.absoluteString!)"
        }
        
        print(strURL)
        
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.arr_Mutlipleimages = self.getUploadedFiles()
        webHelper.strMethodName = "updateCheckList"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = dicCheckList
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.startUploadingMultipleImages()
    }
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            print(data)
//            if strRequest == "orderDetails"{
//
//                if let dicData = data["order"] as? NSDictionary{
//                    
//                    //SET DATA
//                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
//                    self.objOrderData = OrdersModel(map: map)
//                    let arrData = self.objOrderData.arrProduct
//                    self.objOrderData.arrProduct = []
//                    
//                    //GET PRODUCT DATA
//                    for obj in arrData{
//                        if obj.objProduct?.checklist_id != 0{
//                            self.objOrderData.arrProduct.append(obj)
//                        }
//                    }
//                    
//                    //SET SIGNATURE ARRAT
//                    self.arrOtherData = []
//                    for obj in self.objOrderData.arrProduct{
//                        self.arrOtherData.append(NoteModel(dNote: obj.delivery_note, rNote: obj.returned_note, rStoreId: "", rStore: "", dEmplayess: self.getEmployeesName(emp_id: obj.delivery_emp), dEmplayessId: "\(obj.delivery_emp)", rEmplayess: self.getEmployeesName(emp_id: obj.returned_emp), rEmplayessId: "\(obj.returned_emp)", dSignature: UIImage(), rSignature: UIImage(), productID: obj.id ?? 0, machine_id: obj.machine_id ?? 0, dSignatureUrl: obj.delivery_sign, rSignatureUrl: obj.return_sign, inTime: obj.inTime, outTime: obj.outTime, selectFuleDelivery: "", selectFuleReturn: ""))
//                    }
//                    
//                    
//                    //CHECK EQUMPEMT
//                    for i in 0..<self.objOrderData.arrProduct.count{
//                        let objProduct = self.objOrderData.arrProduct[i]
//                        if objProduct.objMachine != nil{
//                            if objProduct.objMachine?.unique_id != ""{
//                                self.getCheckListPriceAPI(CheckListParameater: CheckListParameater(equipment_unique_id: objProduct.objMachine?.unique_id ?? "", type: "return", order_product_unique_id: objProduct.unique_id ?? ""), index: i)
//                            }
//                        }
//                    }
//                    
//                    //SET THE VIEW
//                    self.setTheView()
//                }
//                else{
//                    //SET THE VIEW
//                    self.setTheView()
//                }
//            }

            
            if strRequest == "customerCheckList"{
                if let arrData = data["customer_checklist_questions"] as? NSArray{
                    
                    let arrData = Mapper<CustomerCheckListModel>().mapArray(JSONArray: arrData as! [[String : Any]])

                    //GET EQUIPMENT
                    let map = Map(mappingType: .fromJSON, JSON: [:])
                    var objEquipment = MachineModel(map: map)
                    if let objData = data["equipment"] as? [String: Any] {
                        objEquipment = Mapper<MachineModel>().map(JSON: objData)
                    }
                    
                    if self.objOrderData.arrProduct.count > index{
                        var objProduct = self.objOrderData.arrProduct[index]
                        objProduct.arrQuestions = arrData

                        //ADD START HOUR
                        if objEquipment?.hour_tracking == "Yes"{
                            let map = Map(mappingType: .fromJSON, JSON: [:])
                            var objCheckList = CustomerCheckListModel(map: map)
                            objCheckList?.type = "text"
                            objCheckList?.question_delivery_text = "Start Hours"
                            objCheckList?.question_return_text = "End Hours"
                            objCheckList?.startHours = objProduct.start_hours
                            objCheckList?.endHours = objProduct.end_hours
                            objCheckList?.hour_rate = Float(objEquipment?.overage_rate ?? "") ?? 0
                            objCheckList?.total_cost = objProduct.total_charge
                            objProduct.arrQuestions.insert(objCheckList!, at: 0)
                            
                            if objEquipment != nil{
                                if objEquipment?.powerSourceType != ""{
                                    //SET FULE
                                    let map = Map(mappingType: .fromJSON, JSON: [:])
                                    var objCheckListFule = CustomerCheckListModel(map: map)
                                    objCheckListFule?.type = "fuel"
                                    objCheckListFule?.question_delivery_text = "Fuel (\(objEquipment?.powerSourceType.capitalizingFirstLetter() ?? ""))"
                                    objCheckListFule?.question_return_text = "Fuel (\(objEquipment?.powerSourceType.capitalizingFirstLetter() ?? ""))"
                                    objCheckListFule?.fuleType = objEquipment?.powerSourceType ?? ""
                                    objCheckListFule?.isDEF = objEquipment?.hasDEF ?? ""
                                    objCheckListFule?.diesel_tank_capacity = objEquipment?.diesel_tank_capacity
                                    objCheckListFule?.def_tank_capacity = objEquipment?.def_tank_capacity
                                    objCheckListFule?.gas_tank_capacity = objEquipment?.gas_tank_capacity

                                    objCheckListFule?.selectFuleDelivery = objProduct.fuel_initial_reading
                                    objCheckListFule?.selectFuleReturn = objProduct.fuel_final_reading
                                    objProduct.arrQuestions.insert(objCheckListFule!, at: 1)
                                }
                            }
    
                        }
                        else{
                            
                            
                            if objEquipment != nil{
                                if objEquipment?.powerSourceType != ""{
                                    //SET FULE
                                    let map = Map(mappingType: .fromJSON, JSON: [:])
                                    var objCheckListFule = CustomerCheckListModel(map: map)
                                    objCheckListFule?.type = "fuel"
                                    objCheckListFule?.question_delivery_text = "Fuel (\(objEquipment?.powerSourceType.capitalizingFirstLetter() ?? ""))"
                                    objCheckListFule?.question_return_text = "Fuel (\(objEquipment?.powerSourceType.capitalizingFirstLetter() ?? ""))"
                                    objCheckListFule?.fuleType = objEquipment?.powerSourceType ?? ""
                                    objCheckListFule?.isDEF = objEquipment?.hasDEF ?? ""
                                    objCheckListFule?.diesel_tank_capacity = objEquipment?.diesel_tank_capacity
                                    objCheckListFule?.def_tank_capacity = objEquipment?.def_tank_capacity
                                    objCheckListFule?.gas_tank_capacity = objEquipment?.gas_tank_capacity

                                    objCheckListFule?.selectFuleDelivery = objProduct.fuel_initial_reading
                                    objCheckListFule?.selectFuleReturn = objProduct.fuel_final_reading
                                    objProduct.arrQuestions.insert(objCheckListFule!, at: 0)
                                }
                            }
                        }                        

                        self.objOrderData.arrProduct.remove(at: index)
                        self.objOrderData.arrProduct.insert(objProduct, at: index)
                    }
                    
                    
                    //RELOAD
                    self.tblView.reloadData()
                }
            }
//            if strRequest == "employeesList"{
//                self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(unique_id: self.strOrderUniqueId, product_id: self.strProductID))
//
//                if let arrData = data["users"] as? NSArray{
//                   
//                    self.arrEmployesList = []
//                    self.arrEmployesList = Mapper<EmployeesModel>().mapArray(JSONArray: arrData as! [[String : Any]])
//                    self.arrEmployesList = self.arrEmployesList.sorted(by: { $0.name ?? "" < $1.name ?? "" })
//
//                }
//            }
//            else if strRequest == "employeesList"{
//                self.getCheckListPriceAPI()
//
//                
//                if let arrData = data["data"] as? NSArray{
//                    
//                    self.arrEmployesList = []
//                    self.arrEmployesList = Mapper<EmployeesModel>().mapArray(JSONArray: arrData as! [[String : Any]])
//                    self.arrEmployesList = self.arrEmployesList.sorted(by: { $0.name ?? "" < $1.name ?? "" })
//                    
//                }
//            }
//            else if strRequest == "scheduleUpdate"{
//                //UPDATE COUNT
//                GlobalMainConstants.appDelegate?.getScheduleCount()
//                
//                
////                //UPDATE
////                if self.objOrderData.arrDeliveryStatus.count != 0{
////                    var objDelivery = self.objOrderData.arrDeliveryStatus[self.deliveryIndex]
////
////                    if self.isDeliveryType{
////                        objDelivery.delivery_status?.value = "2"
////                    }
////                    else{
////                        objDelivery.pickup_status?.value = "2"
////                    }
////
////                    //UPDATE DATA
////                    self.objOrderData.arrDeliveryStatus.remove(at: self.deliveryIndex)
////                    self.objOrderData.arrDeliveryStatus.insert(objDelivery, at: self.deliveryIndex)
////                }
////
////
////                //RELOAD TABLE
////                self.tblView.reloadData()
//            }
            if strRequest == "updateCheckList"{
//                let arrData = self.getUploadedFiles()
//                if arrData.count != 0{
//                    self.updateCheckListImages(arrMutlipleimages: arrData)
//                }
//                else{
//                    self.delegate?.UpdateCheckListProduct(selectIndex: self.selectIndex, arrUpdateCheckList: self.arrOtherData)
                    
                NotificationCenter.default.post(name: .updateCheckList, object: nil, userInfo: ["checklist_data": self.arrOtherData, "index" : self.selectIndex, "type" : self.isDeliveryType] )

                    
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
                        showAlertMessage(strMessage: "Checklist updated successfully.", isDismiss: true)
                    }
//                }
                
            }
//            else if strRequest == "updateCheckListImages"{
//                
////                self.delegate?.UpdateCheckListProduct(selectIndex: self.selectIndex, arrUpdateCheckList: self.arrOtherData)
//                NotificationCenter.default.post(name: .updateCheckList, object: nil, userInfo: ["checklist_data": self.arrOtherData, "index" : self.selectIndex] )
//
//                if self.isOrderDetailsView{
//                    if let targetViewController = self.navigationController?.viewControllers.first(where: { $0 is OrderDetailsViewController  }) {
//                        navigationController?.popToViewController(targetViewController, animated: true)
//                    }
//                }
//                else{
//                    if let targetViewController = self.navigationController?.viewControllers.first(where: { $0 is OrderListViewController }) {
//                        navigationController?.popToViewController(targetViewController, animated: true)
//                    }
//                }
//                
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
//                    showAlertMessage(strMessage: "Checklist Successfully Updated")
//                }
//            }
        }
     
        else{
            indicatorHide()
//            //BACK SCREE
//            self.navigationController?.popViewController(animated: true)

//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
//                if data.getStringForID(key: "message") != ""{
//                    showAlertMessage(strMessage: data.getStringForID(key: "message"))
//                }
//                else{
//                    showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
//                }
//                
//            }
        }
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
