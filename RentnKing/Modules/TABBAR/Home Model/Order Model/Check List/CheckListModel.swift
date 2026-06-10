//
//  CheckListModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 10/09/24.
//

import Foundation
import ObjectMapper
import UIKit

//class NoteModel: NSObject{
////    var orderProductId: String = ""
////    var equipmentId: String = ""
////    var checklistData: String = ""
////    
//    var startHours: Float = 0.0
//    var endHours: Float = 0.0
//
//    var dNote: String = ""
//    var rNote: String = ""
//
//    var rStoreId: String = ""
//    var rStore: String = ""
//
//    var dEmplayess: String = ""
//    var dEmplayessId: String = ""
//    var rEmplayess: String = ""
//    var rEmplayessId: String = ""
//    
//    var dSignature: UIImage?
//    var rSignature: UIImage?
//    
//    var inTime: String = ""
//    var outTime: String = ""
//    
//    var dSignatureUrl: String = ""
//    var rSignatureUrl: String = ""
//
//    var productID: Int = 0
//    var machine_id: Int = 0
//    
//    var selectFuleDelivery: String = ""
//    var selectFuleReturn: String = ""
//
//    
//    init(startHours: Float, endHours: Float, dNote: String, rNote: String, rStoreId: String, rStore: String, dEmplayess: String, dEmplayessId: String, rEmplayess: String, rEmplayessId: String, dSignature: UIImage?, rSignature: UIImage?, productID: Int, machine_id: Int, dSignatureUrl: String, rSignatureUrl: String, inTime: String, outTime: String, selectFuleDelivery: String, selectFuleReturn: String) {
//        self.startHours = startHours
//        self.endHours = endHours
//        self.dNote = dNote
//        self.rNote = rNote
//        self.rStore = rStore
//        self.rStoreId = rStoreId
//        self.dEmplayess = dEmplayess
//        self.dEmplayessId = dEmplayessId
//        self.rEmplayess = rEmplayess
//        self.rEmplayessId = rEmplayessId
//        self.dSignature = dSignature
//        self.rSignature = rSignature
//        self.productID = productID
//        self.machine_id = machine_id
//        self.dSignatureUrl = dSignatureUrl
//        self.rSignatureUrl = rSignatureUrl
//        self.inTime = inTime
//        self.outTime = outTime
//        self.selectFuleDelivery = selectFuleDelivery
//        self.selectFuleReturn = selectFuleReturn
//    }
//}


// MARK: - NoteModel
final class NoteModel: NSObject {
    
    var orderProductId: String = ""
    var equipmentId: String = ""
    var checklistData: String = ""
    
    var startHours: Float = 0.0
    var endHours: Float = 0.0
    
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
    
    var selectFuleDelivery: String = ""
    var selectFuleReturn: String = ""
    
    override init() {
        super.init()
    }
    
    init(startHours: Float,
         endHours: Float,
         dNote: String,
         rNote: String,
         rStoreId: String,
         rStore: String,
         dEmplayess: String,
         dEmplayessId: String,
         rEmplayess: String,
         rEmplayessId: String,
         dSignature: UIImage?,
         rSignature: UIImage?,
         productID: Int,
         machine_id: Int,
         dSignatureUrl: String,
         rSignatureUrl: String,
         inTime: String,
         outTime: String,
         selectFuleDelivery: String,
         selectFuleReturn: String) {
        
        self.startHours = startHours
        self.endHours = endHours
        self.dNote = dNote
        self.rNote = rNote
        self.rStoreId = rStoreId
        self.rStore = rStore
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
        self.selectFuleDelivery = selectFuleDelivery
        self.selectFuleReturn = selectFuleReturn
    }
    
    // MARK: - JSON Safe Dict
    func toDict(imageQuality: CGFloat = 0.8) -> [String: Any] {
        var dict: [String: Any] = [
            "orderProductId": orderProductId,
            "equipmentId": equipmentId,
            "checklistData": checklistData,
            "startHours": startHours,
            "endHours": endHours,
            "dNote": dNote,
            "rNote": rNote,
            "rStoreId": rStoreId,
            "rStore": rStore,
            "dEmplayess": dEmplayess,
            "dEmplayessId": dEmplayessId,
            "rEmplayess": rEmplayess,
            "rEmplayessId": rEmplayessId,
            "inTime": inTime,
            "outTime": outTime,
            "dSignatureUrl": dSignatureUrl,
            "rSignatureUrl": rSignatureUrl,
            "productID": productID,
            "machine_id": machine_id,
            "selectFuleDelivery": selectFuleDelivery,
            "selectFuleReturn": selectFuleReturn
        ]
        
        // Only store base64 if image is real (prevents UIImage() empty)
        if let img = dSignature, img.hasValidData, let b64 = img.toBase64String(compressionQuality: imageQuality) {
            dict["dSignature_base64"] = b64
        }
        if let img = rSignature, img.hasValidData, let b64 = img.toBase64String(compressionQuality: imageQuality) {
            dict["rSignature_base64"] = b64
        }
        
        return dict
    }
    
    static func fromDict(_ dict: [String: Any]) -> NoteModel {
        let note = NoteModel()
        
        note.orderProductId = dict["orderProductId"] as? String ?? ""
        note.equipmentId = dict["equipmentId"] as? String ?? ""
        note.checklistData = dict["checklistData"] as? String ?? ""
        
        note.startHours = (dict["startHours"] as? NSNumber)?.floatValue
        ?? (dict["startHours"] as? Float)
        ?? 0.0
        
        note.endHours = (dict["endHours"] as? NSNumber)?.floatValue
        ?? (dict["endHours"] as? Float)
        ?? 0.0
        
        note.dNote = dict["dNote"] as? String ?? ""
        note.rNote = dict["rNote"] as? String ?? ""
        
        note.rStoreId = dict["rStoreId"] as? String ?? ""
        note.rStore = dict["rStore"] as? String ?? ""
        
        note.dEmplayess = dict["dEmplayess"] as? String ?? ""
        note.dEmplayessId = dict["dEmplayessId"] as? String ?? ""
        note.rEmplayess = dict["rEmplayess"] as? String ?? ""
        note.rEmplayessId = dict["rEmplayessId"] as? String ?? ""
        
        note.inTime = dict["inTime"] as? String ?? ""
        note.outTime = dict["outTime"] as? String ?? ""
        
        note.dSignatureUrl = dict["dSignatureUrl"] as? String ?? ""
        note.rSignatureUrl = dict["rSignatureUrl"] as? String ?? ""
        
        note.productID = dict["productID"] as? Int ?? (dict["productID"] as? NSNumber)?.intValue ?? 0
        note.machine_id = dict["machine_id"] as? Int ?? (dict["machine_id"] as? NSNumber)?.intValue ?? 0
        
        note.selectFuleDelivery = dict["selectFuleDelivery"] as? String ?? ""
        note.selectFuleReturn = dict["selectFuleReturn"] as? String ?? ""
        
        if let b64 = dict["dSignature_base64"] as? String {
            note.dSignature = UIImage.fromBase64String(b64)
        }
        if let b64 = dict["rSignature_base64"] as? String {
            note.rSignature = UIImage.fromBase64String(b64)
        }
        
        return note
    }
}


extension UIImage {
    func toBase64String(compressionQuality: CGFloat = 0.8) -> String? {
        guard let data = self.jpegData(compressionQuality: compressionQuality) else { return nil }
        return data.base64EncodedString()
    }

    static func fromBase64String(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    /// Returns true if image can produce data (prevents UIImage() empty images)
    var hasValidData: Bool {
        return self.pngData() != nil || self.jpegData(compressionQuality: 1.0) != nil
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


struct CustomerCheckListModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var question_name: String?
    internal var question_delivery_text: String?
    internal var question_return_text: String?
    internal var sync_texts: Bool?

    
    internal var startHours: Float = 0.0
    internal var endHours: Float = 0.0

    internal var additinal: Int?
    internal var total: Float = 0.0
    internal var total_cost: Float = 0.0
    internal var hour_rate : Float = 0.0
    
    internal var deliverAnswer: AnswerCheckListModel!
    internal var returnAnswer: AnswerCheckListModel!

    internal var arrAnswer: [AnswerCheckListModel] = []
    internal var type: String?

    internal var fuleType: String?
    internal var isDEF: String?

    internal var selectFuleDelivery: String?
    internal var selectFuleReturn: String?

    internal var gas_tank_capacity: String?
    internal var def_tank_capacity: String?
    internal var diesel_tank_capacity: String?

    internal var objEquipment : MachineModel?
    
    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        question_name <- map["question_name"]
        question_delivery_text <- map["question_delivery_text"]
        question_return_text <- map["question_return_text"]
        sync_texts <- map["sync_texts"]
        
        startHours <- map["startHours"]
        endHours <- map["endHours"]
        
        additinal <- map["additinal"]
        total <- map["total"]
        total_cost <- map["total_cost"]
        hour_rate <- map["hour_rate"]
        
        deliverAnswer <- map["deliverAnswer"]
        returnAnswer <- map["returnAnswer"]

        arrAnswer <- map["answers"]
        type <- map["type"]
        
        fuleType <- map["fuleType"]
        isDEF <- map["isDEF"]
        
        selectFuleDelivery <- map["selectFuleDelivery"]
        selectFuleReturn <- map["selectFuleReturn"]
        
        gas_tank_capacity <- map["gas_tank_capacity"]
        def_tank_capacity <- map["def_tank_capacity"]
        diesel_tank_capacity <- map["diesel_tank_capacity"]
        
      
        objEquipment <- map["equipment"]
      
    }
}


struct PriceListModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var setting_name: String?
    internal var setting_value: String?

    
    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        setting_name <- map["setting_name"]
        setting_value <- map["setting_value"]
    }
}

struct AnswerCheckListModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var answer_delivery_text: String?
    internal var answer_return_text: String?
    internal var isSelected: Bool = false

    internal var delivery_amt: Float = 0.0
    internal var return_amt: Float = 0.0

    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        answer_delivery_text <- map["answer_delivery_text"]
        answer_return_text <- map["answer_return_text"]

        delivery_amt <- map["delivery_amt"]
        return_amt <- map["return_amt"]

    }
}

struct CheckListParameater: Codable {
    var equipment_unique_id : String
    var type : String //delivery return
    var order_product_unique_id: String
}


//MARK: - API CALL
extension CheckListViewController :WebServiceHelperDelegate {
 
   
    
  

//    func getCheckListPriceAPI(CheckListParameater : CheckListParameater, index : Int){
//        guard let parameater = try? CheckListParameater.asDictionary() else {
//            showAlertMessage(strMessage: str.invalidRequestParamater)
//            return
//        }
//        
//        //Declaration URL
//        let strURL = "\(Url.customerCheckList.absoluteString!)"
//        
//       
//        //Create object for webservicehelper and start to call method
//        let webHelper = WebServiceHelper()
//        webHelper.strMethodName = "customerCheckList"
//        webHelper.methodType = "post"
//        webHelper.strURL = strURL
//        webHelper.dictType = parameater
//        webHelper.selectIndex = index
//        webHelper.dictHeader = NSDictionary()
//        webHelper.delegateWeb = self
//        webHelper.showLogForCallingAPI = true
//        webHelper.serviceWithAlert = true
//        webHelper.indicatorShowOrHide = true
//        webHelper.callAPI()
//    }
    
    func callAPIforGetOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater, completion: @escaping (Bool) -> Void) {
        guard let parameater = try? OrdersDetailsParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.orderDetails.absoluteString!)"
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPIwithCompletation { dic, arr, isSuccess, errorr in
            indicatorHide()

            if dic?.getStringForID(key: "success") == "1" {
                
                if let dicData = dic?["order"] as? NSDictionary {
                    
                    //SET DATA
                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
                    let arr_data = OrdersModel(map: map)
                    
                    //SET DATA IN LOCAL
                    SDKUserDefault.saveMappableObject(arr_data!, for: "\(kFileStorageName.kOrderDetailsData.rawValue)_\(OrdersDetailsParameater.unique_id)")
                    completion(true)
                }
                else {
                    completion(false)
                }
            }
            else {
                completion(false)
            }
                    
        }
    }

    
    
    
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
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

                        if objEquipment?.hour_tracking == "Yes"{
                            //ADD START HOUR
                            let map = Map(mappingType: .fromJSON, JSON: [:])
                            var objCheckList = CustomerCheckListModel(map: map)
                            objCheckList?.type = "text"
                            objCheckList?.question_delivery_text = "Start Hours"
                            objCheckList?.question_return_text = "End Hours"
                            objCheckList?.startHours = objProduct.start_hours
                            objCheckList?.endHours = objProduct.end_hours
                            objCheckList?.hour_rate = Float(objEquipment?.overage_rate ?? "") ?? 0

                            objProduct.arrQuestions.insert(objCheckList!, at: 0)
                            

                            
                            if objEquipment != nil{
                                if objEquipment?.powerSourceType != ""{
                                    //SET FULE
                                    let map = Map(mappingType: .fromJSON, JSON: [:])
                                    var objCheckListFule = CustomerCheckListModel(map: map)
                                    objCheckListFule?.type = "fuel"
                                    objCheckListFule?.question_delivery_text = "Fuel (\(objEquipment?.powerSourceType.capitalizingFirstLetter() ?? ""))"
                                    objCheckListFule?.question_return_text = "Fuel (\(objEquipment?.powerSourceType.capitalizingFirstLetter() ?? ""))"
                                    objCheckListFule?.fuleType = objEquipment?.powerSourceType
                                    objCheckListFule?.isDEF = objEquipment?.hasDEF
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
                                    objCheckListFule?.fuleType = objEquipment?.powerSourceType
                                    objCheckListFule?.isDEF = objEquipment?.hasDEF
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
        if self.arrEmployesList.count != 0{
            let MenuID = self.arrEmployesList.map{$0.id}
            if let index = MenuID.firstIndex(of: emp_id){
                return self.arrEmployesList[index].name ?? ""
            }
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

