//
//  CheckListViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 10/09/24.
//

import UIKit

protocol  CheckListDelegate : NSObject {
    func UpdateCheckListProduct(selectIndex: Int, arrUpdateCheckList : [NoteModel])
}

class CheckListViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: CheckListDelegate?

    @IBOutlet weak var tblView: UITableView!
    @IBOutlet weak var con_tableView: NSLayoutConstraint!
    @IBOutlet weak var con_Submit: NSLayoutConstraint!
    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!
    @IBOutlet weak var con_SubmitBottom : NSLayoutConstraint!

    @IBOutlet weak var lblTotalChargeTitle: UILabel!
    @IBOutlet weak var lblTotalCharge: UILabel!

   

    //LOADING
    let machinePlaceholderMarker = Placeholder()

    //OTHER
    var isLoading : Bool = true

    
    var objOrderData : OrdersModel!
    var arrProductList : [ProductModel] = []
    var arrEmployesList : [EmployeesModel] = []
    var arrOtherData : [NoteModel] = []
    var objCheckListPrice : CheckListPriceModel!
    var arrMachineList : [MachineModel] = []
    var arrAllMachineList : [MachineModel] = []
    var arrCategoryList : [CategoryModel] = []
    var arrStoreList :[StoreModel] = []

    var selectIndex : Int = -1
    var strOrderID : String = ""
    var strProductID : String = ""

    var strTotalCharge : Float = 0.0
    var isDeliveryType : Bool = false
    var selectEmployessID : String = ""
    var deliveryIndex : Int = 0
    var isOrderDetailsView : Bool = false
    var isUpdateMachineId : Bool = false
    var isUpdateMachineIdFirstTime : Bool = true

    override func viewDidLoad() {
        super.viewDidLoad()
//        setupCutomeKeyboard()
        // Do any additional setup after loading the view.
        setupKeyboard(false)

        
        //CALL API
        self.viewSubmit.isHidden = true
        self.getEmployeesListAPI()
        
        self.getMachineListAPI()
        self.getCategorys()
        self.getStoreAddress()
        
        //KEYBOARD METHOD
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification , object:nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification , object:nil)

    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        //SET PORTRAIT MODE
        AppUtility.PortraitMode()

        
        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true
        
        //SET NAVIGATION BAR
        setNavigationBarFor(controller: self, title: "Check List - \(self.isDeliveryType ? "Delivered" : "Returned")", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)
            
            
        } rightActionHandler: {
            
            
        }
        
        self.con_tableView.constant = checkDeviceiPad() ? manageWidth(size: 450) : GlobalMainConstants.windowWidth
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        setupKeyboard(true)
    }
    
    func setTheView(){
        self.isLoading = false
        indicatorHide()
        self.stopLoading()

        //SET SUBMIT
        self.viewSubmit.isHidden = false
        self.con_Submit.constant = manageWidth(size: 45.0)
        self.viewSubmit.backgroundColor = .secondaryTextView
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strNext)
        
        self.lblTotalChargeTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strTotalCheckList)
        self.lblTotalCharge.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "\(Application.currency)\(self.strTotalCharge)")
        
        self.lblTotalChargeTitle.isHidden = false
        self.lblTotalCharge.isHidden = false
        if self.isDeliveryType{
            self.lblTotalChargeTitle.isHidden = true
            self.lblTotalCharge.isHidden = true
        }
        
        //UPDATE DATA
        self.setCheckListData()
        
     
        //SET HEADER
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//            //SET TABLE HEADER
//            let vw_Table = self.tblView.tableFooterView
//            vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.lblProductTitle.frame.origin.y + self.lblProductTitle.frame.size.height)
//
//            self.tblView.tableFooterView = vw_Table
//            
//            //RELOAD TABLE
//            DispatchQueue.main.asyncAfter(deadline: .now()) {
//                self.tblView.reloadData()
//            }
//
//        }
    }
    
    func stopLoading(){
        indicatorHide()
        self.CalculatTotalCharge()
        self.tblView.reloadData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.machinePlaceholderMarker.remove()
        }
    }
    
    
    func setCheckListData(){
        for i in 0..<self.objOrderData.arrProduct.count{
            var objProduct = self.objOrderData.arrProduct[i]
            
            for j in 0..<(objProduct.checkList?.arrQuestions?.count ?? 0){
                var objQuestion = objProduct.checkList?.arrQuestions?[j]

                
                
                
                if objQuestion?.objQuestion?.checklist_type?.lowercased() == "tires"{
                    if objQuestion?.objQuestion?.returned == 2{
                        objQuestion?.objQuestion?.customerOwes = self.objCheckListPrice.tire_repair
                    }
                    else if objQuestion?.objQuestion?.returned == 3{
                        objQuestion?.objQuestion?.customerOwes = self.objCheckListPrice.tire_10_ply
                    }
                    else if objQuestion?.objQuestion?.returned == 4{
                        objQuestion?.objQuestion?.customerOwes = self.objCheckListPrice.tire_14_ply
                    }
                }
                else if objQuestion?.objQuestion?.checklist_type?.lowercased() == "fuel"{
                    var price : Float = 0.0
                    if objQuestion?.objQuestion?.fuel_type == 1{
                        price = Float(self.objCheckListPrice.diesel_price ?? "") ?? 0.0
                    }
                    else if objQuestion?.objQuestion?.fuel_type == 2{
                        price = Float(self.objCheckListPrice.gas_price ?? "") ?? 0.0
                    }
                    else if objQuestion?.objQuestion?.fuel_type == 3{
                        price = Float(self.objCheckListPrice.def_price ?? "") ?? 0.0
                    }
                    
                    
                    let getFuelData = self.FuelCalulateTotalCharge(total: objQuestion?.objQuestion?.question_value ?? 0.0, dSelect: objQuestion?.objQuestion?.delivered ?? 0.0, rSelect: objQuestion?.objQuestion?.returned ?? 0.0)

                    //SET DATA
                    objQuestion?.objQuestion?.balance = getFuelData >= 0 ? getFuelData : 0.0
                    objQuestion?.objQuestion?.customerOwes = getFuelData >= 0 ? getFuelData * price : 0.0
                }
                else if objQuestion?.objQuestion?.checklist_type?.lowercased() == "cleaning"{
                    //SET DATA
                    var deliveryPrice : Float = 0.0
                    var returnPrice : Float = 0.0

                    //GET DELIVERY DATA
                    if objQuestion?.objQuestion?.delivered != 0 && objQuestion?.objQuestion?.delivered != -1{
                        let strReturnKey : String = "\(Int(objQuestion?.objQuestion?.delivered ?? 0))"
                        let strValue = objQuestion?.objQuestion?.clean_delivered_values[strReturnKey]
                        if strValue == "Pre-Paid" || strValue == "Std. Clean Req."{
                            deliveryPrice = Float(objQuestion?.objQuestion?.sd_clean_price ?? "") ?? 0.0
                        }
                    }
                    
                    
                    //GET RETURN DATA
                    if objQuestion?.objQuestion?.returned != 0 && objQuestion?.objQuestion?.returned != -1{
                        let strReturnKey : String = "\(Int(objQuestion?.objQuestion?.returned ?? 0))"
                        let strValue = objQuestion?.objQuestion?.clean_returned_values[strReturnKey]
                        if strValue == "Std. Clean Req."{
                            returnPrice = Float(objQuestion?.objQuestion?.sd_clean_price ?? "") ?? 0.0
                        }
                        else if strValue == "Ext. Clean Req."{
                            returnPrice = Float(objQuestion?.objQuestion?.ex_clean_price ?? "") ?? 0.0
                        }

                    }
                   
                    let strPayPrive = returnPrice - deliveryPrice
                    objQuestion?.objQuestion?.customerOwes = strPayPrive >= 0 ? strPayPrive : 0.0

                }
                else if objQuestion?.objQuestion?.checklist_type?.lowercased() == "default" && objQuestion?.objQuestion?.arrAnswer.count != 0{
                
                                        
                    //GET DATA
                    var deliveryPrice : Float = 0.0
                    var returnPrice : Float = 0.0
                    
                    //GET DELIVERY DATA
                    let strDeliveryId = objQuestion?.objQuestion?.delivered
                    if strDeliveryId != 0{
                        let MenuID = objQuestion?.objQuestion?.arrAnswer.map{$0.id}
                        if let index = MenuID?.firstIndex(of: Int(strDeliveryId ?? 0)){
                            deliveryPrice = objQuestion?.objQuestion?.arrAnswer[index].answer_value ?? 0
                        }
                    }
                    
                    //GET RETURN DATA
                    let strReturId = objQuestion?.objQuestion?.returned
                    if strReturId != 0{
                        let MenuID = objQuestion?.objQuestion?.arrAnswer.map{$0.id}
                        if let index = MenuID?.firstIndex(of: Int(strReturId ?? 0)){
                            returnPrice = objQuestion?.objQuestion?.arrAnswer[index].answer_value ?? 0
                        }
                    }
                    
                    let strPayPrive = returnPrice - deliveryPrice
                    objQuestion?.objQuestion?.customerOwes = strPayPrive >= 0 ? strPayPrive : 0.0
                 
                }
                
                else{
                    //GET BALANCE
                    var balance = (objQuestion?.objQuestion?.delivered ?? 0.0) - (objQuestion?.objQuestion?.returned ?? 0.0)
                    if balance < 0{
                        balance = 0.0
                    }

                    //GET CUSTOMER OWES
                    var customerOwes = balance * (objQuestion?.objQuestion?.question_value ?? 0)
                    if customerOwes < 0{
                        customerOwes = 0.0
                    }
                    //SET DATA
                    objQuestion?.objQuestion?.balance = balance
                    objQuestion?.objQuestion?.customerOwes = customerOwes

                }

                
                //UPDATE DATA
                objProduct.checkList?.arrQuestions?.remove(at: j)
                objProduct.checkList?.arrQuestions?.insert(objQuestion!, at: j)
            }
            
            //UPDATE DATA
            self.objOrderData.arrProduct.remove(at: i)
            self.objOrderData.arrProduct.insert(objProduct, at: i)
        }
        
        //RELOAD TABLE
        DispatchQueue.main.asyncAfter(deadline: .now()){
            self.CalculatTotalCharge()
            self.tblView.reloadData()
        }
        
    }
    
    

    
    
    
    
    func checkDeliveryPickupStatus(isDeliveryType : Bool) -> (String, Bool, Int){
        if self.objOrderData == nil{
            return ("icon_delivery_pending", false, 0)
        }
        
        
        var strImg : String = "icon_delivery_pending"
        if self.objOrderData.arrDeliveryStatus.count != 0{
            
            for obj in self.objOrderData.arrDeliveryStatus{
                if isDeliveryType{
                    //GET IMAGE
                    if obj.customer_delivery == 2{
                        strImg = "icon_delivery_pending"
                    }
                    else{
                        strImg = "icon_store"
                    }
                    
                    //CHECK STATUS
                    if obj.delivery_status?.value != "2"{
                        return (strImg, false, obj.product_id ?? 0)
                    }
                    else{
                        return (strImg, true, obj.product_id ?? 0)
                    }
                }
                else{
                    //GET IMAGE
                    if obj.customer_pickup == 2{
                        strImg = "icon_delivery_pending"
                    }
                    else{
                        strImg = "icon_store"
                    }
                    
                    //CHECK STATUS
                    if obj.pickup_status?.value != "2"{
                        return (strImg, false, obj.product_id ?? 0)
                    }
                    else{
                        return (strImg, true, obj.product_id ?? 0)
                    }
                }
            }
        }
        else{
            return (strImg, false, 0)
        }
        
        return (strImg, true, 0)
    }
}



//MARK: - BUTTON ACTION
extension CheckListViewController : EPSignatureDelegate{
    
    func epSignature(_: EPSignatureViewController, didCancel error : NSError) {
        print("User canceled")
        //SET PORTRAIT MODE
        AppUtility.PortraitMode()

    }
    
    func epSignature(_: EPSignatureViewController, didSign signatureImage : UIImage, boundingRect: CGRect, strIndex : Int) {
        //SET PORTRAIT MODE
        AppUtility.PortraitMode()

        print(signatureImage)
        
        //UPDATE SIGNATURE ARRAY
        let obj = self.arrOtherData[strIndex]
        if self.isDeliveryType{
            obj.dSignature = signatureImage
        }
        else{
            obj.rSignature = signatureImage
        }
        
        self.arrOtherData.remove(at: strIndex)
        self.arrOtherData.insert(obj, at: strIndex)
        
        //RELOAD
        self.tblView.reloadData()
    }

    

    
    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        if self.checkMachineData() == false{
            return
        }
        else if self.checkQustions() == false{
            return

        }
        else if self.checkOtherData() == false{
            return
        }
        else{
            
            //MOVE CHECKLIST
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListUpdateViewController") as? CheckListUpdateViewController{
                newViewController.isDeliveryType = self.isDeliveryType
                newViewController.objOrderData = self.objOrderData
                newViewController.arrOtherData = self.arrOtherData
                newViewController.objCheckListPrice = self.objCheckListPrice
                newViewController.selectIndex = self.selectIndex
                newViewController.strOrderID = self.strOrderID
                newViewController.isOrderDetailsView = self.isOrderDetailsView
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
            
        }
     
        
//        var arrData : [[String : Any]] = []
//        for obj in self.objOrderData.arrProduct{
//            
//            for objChecklist in obj.checkList?.arrQuestions ?? []{
//                
//                let dic : [String : Any] = ["order_id" : self.strOrderID,
//                                          "product_id" : "\(obj.product_id ?? 0)",
//                                            "question_id" : "\(objChecklist.objQuestion?.id ?? 0)",
//                                            "in" : "\(objChecklist.objQuestion?.delivered ?? 0)",
//                                            "out" :"\(objChecklist.objQuestion?.returned ?? 0)",
//                                            "value" :"\(objChecklist.objQuestion?.question_value ?? 0)"]
//                arrData.append(dic)
//
//            }
//
//        }
//        
//        
//        //OTHER DATA
//        for obj in self.arrOtherData{
//            let dic : [String : Any] = ["order_id" : self.strOrderID,
//                                      "product_id" : obj.productID,
//                                        "note" : self.isDeliveryType ? obj.dNote : obj.rNote,
//                                        "employee_id" : self.isDeliveryType ? obj.dEmplayessId : obj.rEmplayessId,
//                                        "machine_id" : obj.machine_id,
//                                        "type" :self.isDeliveryType ? "Delivery" : "Return"]
//            
//            arrData.append(dic)
//            
//        }
//        
//
//        
//        //UPDATE CHECK LIST
//        self.updateCheckList(arrCheckList: arrData)
//        
        
        
    

        
        
//        let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.orderID ?? "", strType: objData.type ?? "")
//
//        self.updateCheckList(strOrderID: objData.orderID ?? "", arrCheckList: self.getCheckListArray(strOrderID: objData.orderID ?? "", arrData: arrData))
//
//        
//        
//        //GET HORES DATA
//        let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderID, strType: uploadType.checkList.rawValue)
//        if arrData.count != 0{
//            CoreDBManager.sharedDatabase.deleteUploadData(strOrderID: self.strOrderID, strType: uploadType.checkList.rawValue) { isSave in
//                if isSave{
//                    //SAVE IN TABLE
//                    self.saveChecklistData(arrProduct: self.objOrderData.arrProduct)
//                }
//            }
//        }
//        else{
//            //SAVE IN TABLE
//            self.saveChecklistData(arrProduct: self.objOrderData.arrProduct)
//        }
    }
    
//    func saveChecklistData(arrProduct : [ProductModel]){
//        let arrData = arrProduct
//        if arrData.count != 0{
//            let objData = arrData[0]
//            
//            //SAVE IN DATA BASE
//            self.saveCheckList(arrProduct: arrProduct, arrQustion: objData.checkList?.arrQuestions ?? [], productID: "\(objData.product_id ?? 0)")
//
//        }
//        else{
//            //SUCCESS m,m
//            if self.selectIndex != -1{
//                self.delegate?.UpdateCheckListProduct(selectIndex: self.selectIndex, arrUpdateProduct: self.objOrderData.arrProduct)
//            }
//            
//            //UPLOAD LOCAL DATA
//            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0){
//                GlobalMainConstants.appDelegate?.uploadAllData()
//            }
//            
//            self.navigationController?.popViewController(animated: true)
//
//
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
//                showAlertMessage(strMessage: "CheckList update successfully")
//            }
//        }
//    }
    
    
//    func saveCheckList(arrProduct : [ProductModel], arrQustion : [QuestionsListModel], productID : String){
//        var arrProduct = arrProduct
//        var arrData = arrQustion
//        if arrData.count != 0{
//            let objData = arrData[0]
//            
//            
//            //SAVE IN DATA BASE
//            CoreDBManager.sharedDatabase.saveUploadDataList(objSaveData: SaveImageVideoParameater(orderID: self.strOrderID, type: uploadType.checkList.rawValue, isImage: false, name: "", productID: productID, qustion_id: "\(objData.objQuestion?.id ?? 0)" , checklist_delivered: "\(objData.objQuestion?.delivered ?? 0)", checklist_returned: "\(objData.objQuestion?.returned ?? 0)", checklist_Value: "\(objData.objQuestion?.question_value ?? 0)")) { isSave in
//                if isSave{
//                    arrData.remove(at: 0)
//                    self.saveCheckList(arrProduct: arrProduct, arrQustion: arrData, productID: productID)
//                }
//                else{
//                    showAlertMessage(strMessage: "CheckList not update")
//                }
//            }
//        }
//        else{
//            arrProduct.remove(at: 0)
//            self.saveChecklistData(arrProduct: arrProduct)
//        }
//    }
    
    func checkQustions() -> Bool{
        
        for i in 0..<self.objOrderData.arrProduct.count{
            let objProduct = self.objOrderData.arrProduct[i]
            
            for j in 0..<(objProduct.checkList?.arrQuestions?.count ?? 0){
                let objQuestions = objProduct.checkList?.arrQuestions?[j]
                
                if objQuestions?.objQuestion?.checklist_type?.lowercased() != "default" || objQuestions?.objQuestion?.arrAnswer.count != 0 || objQuestions?.objQuestion?.checklist_type?.lowercased() == "tires"{
                    
                    if self.isDeliveryType{
                        if objQuestions?.objQuestion?.checklist_type?.lowercased() == "fuel"{
                            if objQuestions?.objQuestion?.delivered == -1.0{
                                showAlertMessage(strMessage: "Please select delivered option")
                                return false
                            }
                        }
                        else{
                            if objQuestions?.objQuestion?.delivered == 0 || objQuestions?.objQuestion?.delivered == -1.0 || objQuestions?.objQuestion?.delivered == 0.0 {
                                showAlertMessage(strMessage: "Please select delivered option")
                                return false
                            }

                        }
                    }
                    else{
                        if objQuestions?.objQuestion?.checklist_type?.lowercased() == "fuel"{
                            if objQuestions?.objQuestion?.returned == -1.0{
                                showAlertMessage(strMessage: "Please select returned option")
                                return false
                            }
                        }
                        else{
                            if objQuestions?.objQuestion?.returned == 0 || objQuestions?.objQuestion?.returned == -1.0 || objQuestions?.objQuestion?.returned == 0.0 {
                                showAlertMessage(strMessage: "Please select returned option")
                                return false
                            }

                        }
                    }
                }
            }
        }
        
        return true
    }
    
    func checkMachineData() -> Bool{
        for objData in self.objOrderData.arrProduct{
            if objData.objMachine == nil{
                showAlertMessage(strMessage: "Please select machine id")
                return false
            }
        }
        return true
    }
    
    func checkOtherData() -> Bool{
        for obj in self.arrOtherData{
            if self.isDeliveryType{
                if obj.dEmplayessId == "" || obj.dEmplayessId == "0"{
                    showAlertMessage(strMessage: "Please select delivered by")
                    return false
                }
                
//                if obj.dSignature == UIImage() && obj.dSignatureUrl == ""{
//                    showAlertMessage(strMessage: "Customer signature is required")
//                    return false
//                }
            }
            else{
                if obj.rEmplayessId == "" ||  obj.rEmplayessId == "0"{
                    showAlertMessage(strMessage: "Please select returnd by")
                    return false
                }
                else if obj.rStoreId == ""{
                    showAlertMessage(strMessage: "Please select location")
                    return false
                }
                
//                if obj.rSignature == UIImage() && obj.rSignatureUrl == ""{
//                    showAlertMessage(strMessage: "Customer signature is required")
//                    return false
//                }
            }
        }
        
        return true
    }
}



extension CheckListViewController:  UITextViewDelegate{
   
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
 
        let newText = (textView.text as NSString).replacingCharacters(in: range, with: text)
        
        let obj = self.arrOtherData[textView.tag]
        if self.isDeliveryType{
            obj.dNote = newText
        }
        else{
            obj.rNote = newText
        }
        
        //UPDATE
        self.arrOtherData.remove(at: textView.tag)
        self.arrOtherData.insert(obj, at: textView.tag)
        
        return true
        
    }
    
    
    func textViewShouldReturn(_ textView: UITextView) -> Bool {
          textView.resignFirstResponder() // Dismiss the keyboard
          return true
      }
}

//MARK: -- UITEXTFIELD DELEGATE
extension CheckListViewController : UITextFieldDelegate{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool{
        
        //RELOAD TABLE
        self.CalculatTotalCharge()
        self.tblView.reloadData()
        
        return true
    }
    

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        if textField.tag == 100 || textField.tag == 101{
            let inverseSet = NSCharacterSet(charactersIn:"0123456789").inverted
            let components = string.components(separatedBy: inverseSet)
            let filtered = components.joined(separator: "")
            
            if filtered == string {
                guard let text = textField.text else { return false }
                var newString = (text as NSString).replacingCharacters(in: range, with: string)
                newString = newString.replacingOccurrences(of: "\(Application.currency)", with: "")
                

                let countdots = newString.components(separatedBy: ".").count - 1
                if countdots <= 1
                {
                    let section : Int = Int(textField.accessibilityValue ?? "") ?? 0
                    let index : Int = Int(textField.accessibilityLanguage ?? "") ?? 0

                    var objProduct = self.objOrderData.arrProduct[section]
                    var objdata = objProduct.checkList?.arrQuestions?[index]
                    
                    if textField.tag == 100{
                        objdata?.objQuestion?.delivered = Float(newString) ?? 0.0
                    }
                    else{
                        objdata?.objQuestion?.returned = Float(newString) ?? 0.0
                    }

                    //GET BALANCE
                    var balance = (objdata?.objQuestion?.delivered ?? 0.0) - (objdata?.objQuestion?.returned ?? 0.0)
                    if balance < 0{
                        balance = 0.0
                    }

                    //GET CUSTOMER OWES
                    var customerOwes = balance * (objdata?.objQuestion?.question_value ?? 0)
                    if customerOwes < 0{
                        customerOwes = 0.0
                    }
                    
                    
                    //SET DATA
                    objdata?.objQuestion?.balance = balance
                    objdata?.objQuestion?.customerOwes = customerOwes
                    
                    
                    //UPDATE
                    objProduct.checkList?.arrQuestions?.remove(at: index)
                    objProduct.checkList?.arrQuestions?.insert(objdata!, at: index)
                    
                    //UPDATE ARRAY
                    self.objOrderData.arrProduct.remove(at: section)
                    self.objOrderData.arrProduct.insert(objProduct, at: section)
                    
                    //UPDATE DATA
                    
                    //RELOAD TABLE
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                        self.CalculatTotalCharge()
                    }
                }
                else{
                    return false
                }
                
                
                return true
                
            } else {
                return false
            }
        }
        else{
            return true
        }
    }
    
    func CalculatTotalCharge(){
        self.strTotalCharge = 0.0
        if self.objOrderData == nil { return }

        for i in 0..<self.objOrderData.arrProduct.count{
            let objProduct = self.objOrderData.arrProduct[i]
            
            for j in 0..<(objProduct.checkList?.arrQuestions?.count ?? 0){
                let objQuestion = objProduct.checkList?.arrQuestions?[j]
                
                //SET TOTAL CHARGE
                self.strTotalCharge = self.strTotalCharge + (objQuestion?.objQuestion?.customerOwes ?? 0.0)
                
            }
        }
        
        //RELOAD TABLE
        self.lblTotalCharge.text = "\(Application.currency)\(self.strTotalCharge)"
    }
}




//MARK: -- UITABEL CELL --
class ProductCheckListCell : UITableViewCell{

    @IBOutlet weak var con_imgHeight: NSLayoutConstraint!
    @IBOutlet weak var imgProduct: UIImageView!

    @IBOutlet weak var lblProduct: UILabel!
    @IBOutlet weak var lblDateDelivery: UILabel!
    @IBOutlet weak var lblDateReturn: UILabel!

    @IBOutlet weak var lblDelivered: UILabel!
    @IBOutlet weak var lblReturned: UILabel!


    @IBOutlet weak var lblTitleCategoryId: UILabel!
    @IBOutlet weak var lblCategoryId: UILabel!
    @IBOutlet weak var viewCategoryId: UIView!
    @IBOutlet weak var btnCategoryId: UIButton!
    @IBOutlet weak var imgCategoryId: UIImageView!

    
    @IBOutlet weak var lblTitleMachineId: UILabel!
    @IBOutlet weak var lblMachineId: UILabel!
    @IBOutlet weak var viewMachineId: UIView!
    @IBOutlet weak var btnMachineId: UIButton!
    @IBOutlet weak var imgMachineId: UIImageView!

   
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            imgProduct,
            lblProduct,
            lblDateDelivery,
            lblDateReturn
            
        ]
    }
}

class FooterCheckListCell : UITableViewCell{

    @IBOutlet weak var lblNote: UILabel!
    @IBOutlet weak var lblNoteDetails: UILabel!
    @IBOutlet weak var viewNote: UIView!
    @IBOutlet weak var txtNote: UITextView!
    @IBOutlet weak var con_Note : NSLayoutConstraint!
    @IBOutlet weak var con_NoteTop : NSLayoutConstraint!

    @IBOutlet weak var lblEmployee: UILabel!
    @IBOutlet weak var viewEmployee: UIView!
    @IBOutlet weak var txtSelctEmployee: UITextField!
    @IBOutlet weak var btnSelctEmployee: UIButton!
//    @IBOutlet weak var btnComplate: UIButton!

    @IBOutlet weak var lblLocation: UILabel!
    @IBOutlet weak var viewLocation: UIView!
    @IBOutlet weak var txtSelctLocation: UITextField!
    @IBOutlet weak var btnSelctLocation: UIButton!

    
    @IBOutlet weak var con_Bottom : NSLayoutConstraint!
    @IBOutlet weak var viewSignature: UIView!
    @IBOutlet weak var lblSignature: UILabel!
    @IBOutlet weak var imgSignature: UIImageView!
    @IBOutlet weak var con_imgSignature : NSLayoutConstraint!
    @IBOutlet weak var btnSignature: UIButton!

//    @IBOutlet weak var lblProductStatus: UILabel!
//    @IBOutlet weak var imgProductStatus: UIImageView!
   
//    func getAnimableSubviews() -> [UIView] {
//        return [UIView](getAllSubviews())
//    }
//    
//    private func getAllSubviews() -> [UIView] {
//        return [
//            imgProduct,
//            lblProduct,
//            lblDate
//            
//        ]
//    }
}

class CheckListCell : UITableViewCell{

    @IBOutlet weak var lblTitle: UILabel!
    @IBOutlet weak var lblTitleDelivered: UILabel!

    @IBOutlet weak var lblDelivered: UILabel!
    @IBOutlet weak var txtDelivered: UITextField!
    
    @IBOutlet weak var lblReturned: UILabel!
    @IBOutlet weak var txtReturned: UITextField!
    @IBOutlet weak var viewDeliveredMain: UIView!
    @IBOutlet weak var viewReturnedMain: UIView!

    @IBOutlet weak var viewBalance: UIView!
    @IBOutlet weak var lblBalance: UILabel!
    @IBOutlet weak var txtBalance: UITextField!

    
    @IBOutlet weak var viewValue: UIView!
    @IBOutlet weak var lblValue: UILabel!
    @IBOutlet weak var txtValue: UITextField!

    @IBOutlet weak var viewCustomerOwes: UIView!
    @IBOutlet weak var lblCustomerOwes: UILabel!
    @IBOutlet weak var txtCustomerOwes: UITextField!

    
    @IBOutlet weak var viewDeliverySelect: UIView!
    @IBOutlet weak var lblDeliverySelect: UILabel!
    @IBOutlet weak var imgDeliverySelect: UIImageView!
    @IBOutlet weak var btnDeliverySelect: UIButton!
    
    @IBOutlet weak var viewReturnSelect: UIView!
    @IBOutlet weak var lblReturnSelect: UILabel!
    @IBOutlet weak var imgReturnSelect: UIImageView!
    @IBOutlet weak var btnReturnSelect: UIButton!

    

//    @IBOutlet weak var lblHoursFee: UILabel!
//    @IBOutlet weak var txtHoursFee: UITextField!
//
//    @IBOutlet weak var lblTotalCharge: UILabel!
//    @IBOutlet weak var txtTotalCharge: UITextField!
//    @IBOutlet weak var viewTotalCharge: UIView!
//    @IBOutlet weak var viewTotalChargeLine: UIView!

    @IBOutlet weak var viewLine: UIView!

    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            lblTitle,
//            lblDelivered,
            txtDelivered,
//            lblReturned,
            txtReturned,
//            lblBalance,
//            txtBalance,
//            lblValue,
//            txtValue,
//            lblCustomerOwes,
//            txtCustomerOwes
            
        ]
    }
}


//MARK: -- UITABEL DELEGATE --

extension CheckListViewController : UITableViewDelegate, UITableViewDataSource{
    
    //HEADER SECTION
    func numberOfSections(in tableView: UITableView) -> Int {
        if self.isLoading{
            return 1
        }
        else{
            return self.objOrderData.arrProduct.count
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        //SET HEADER HEIGHT
        if let cell = tableView.dequeueReusableCell(withIdentifier: "ProductCheckListCell") as? ProductCheckListCell{
            cell.backgroundColor = UIColor.background
            
            if self.objOrderData.arrProduct.count == 0{
                return nil
            }
            
            let  objProductDetails = self.objOrderData.arrProduct[section]

            //SET PRODUCT IMAGE
            cell.con_imgHeight.constant = manageWidth(size: 70)
            cell.imgProduct.viewCorneRadius(radius: 5, isRound: false)
            cell.imgProduct.setImage(strImg: objProductDetails.product_image ?? "")
            cell.imgProduct.backgroundColor = .white
            
            
            //SET FONT
            cell.lblProduct.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "\(objProductDetails.product_name ?? "") * \(objProductDetails.qty )")
            
            //SET DATE
            cell.lblDateDelivery.isHidden = false
            cell.lblDateReturn.isHidden = false
            if self.isDeliveryType{
                cell.lblDateReturn.isHidden = true
            }
            
            cell.lblDateDelivery.text = ""
            cell.lblDateReturn.text = ""
            
            //SET DELIVER
            let strDateDeliverd = setFontAttributes(str: "Delivered Date :", fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0)
            let strTimeDeliverd : String = self.arrOtherData[section].inTime
            if strTimeDeliverd != ""{
                strDateDeliverd.append(setFontAttributes(str: " \(strTimeDeliverd)", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0))
            }
            else{
                strDateDeliverd.append(setFontAttributes(str: " \(convertDateToString(date: Date(), withFormat: Application.passServertDAte))", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0))
            }
            
            cell.lblDateDelivery.attributedText = strDateDeliverd
            
            //SET RETURN
            let strDateReturn = setFontAttributes(str: "Returned Date :", fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0)
            let strTimeReturn : String = self.arrOtherData[section].outTime
            if strTimeReturn != ""{
                strDateReturn.append(setFontAttributes(str: " \(strTimeReturn)", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0))
            }
            else{
                strDateReturn.append(setFontAttributes(str: " \(convertDateToString(date: Date(), withFormat: Application.passServertDAte))", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0))
            }
            
            cell.lblDateReturn.attributedText = strDateReturn
            
            cell.lblTitleCategoryId.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "Category ID")
            cell.lblTitleMachineId.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: self.isDeliveryType ? "Machine ID *" : "Machine ID")
            
            cell.lblDelivered.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: str.strDelivered)
            cell.lblReturned.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: str.strReturned)

            cell.lblCategoryId.configureLable(textAlignment: .center, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")
            cell.lblMachineId.configureLable(textAlignment: .center, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")
            imgColor(imgColor: cell.imgCategoryId, colorHex: .primary)
            imgColor(imgColor: cell.imgMachineId, colorHex: .primary)

            if objProductDetails.objCategory != nil{
                cell.lblCategoryId.text = objProductDetails.objCategory?.name ?? ""
            }
            
            if objProductDetails.objMachine != nil{
                self.isUpdateMachineId = true
                cell.lblMachineId.text = self.isDeliveryType ? "\(objProductDetails.objMachine?.machine_id ?? "")" : "\(objProductDetails.objMachine?.product_name ?? "")    ||    \(objProductDetails.objMachine?.machine_id ?? "")"
            }
           
            
            cell.viewCategoryId.backgroundColor = .clear
            cell.viewCategoryId.viewBorderCorneRadius(borderColour: .secondaryText)
            
            cell.viewMachineId.backgroundColor = .clear
            cell.viewMachineId.viewBorderCorneRadius(borderColour: .secondaryText)

            self.isUpdateMachineId = false
            if objProductDetails.objMachine != nil && self.isUpdateMachineIdFirstTime{
                self.isUpdateMachineId = true
            }
                
            cell.imgMachineId.isHidden = true
            cell.lblTitleCategoryId.isHidden = true
            cell.viewCategoryId.isHidden = true
            
            if self.isUpdateMachineId == false{
                cell.imgMachineId.isHidden = false
                cell.lblTitleCategoryId.isHidden = false
                cell.viewCategoryId.isHidden = false

                // BUTTON ACTION
                cell.btnCategoryId.tag = section
                cell.btnCategoryId.addTarget(self, action: #selector(self.btnCategoryIdClicked(_:)), for: .touchUpInside)

                cell.btnMachineId.tag = section
                cell.btnMachineId.addTarget(self, action: #selector(self.btnMachineIdClicked(_:)), for: .touchUpInside)

            }
           
            return cell
        }
        
        return UIView()
    }
    
  
    
    func getMachineName(id : Int) -> String{
        let MenuID = self.arrMachineList.map{$0.id}
        if let index = MenuID.firstIndex(of: id){
            return self.arrMachineList[index].machine_id ?? ""
        }
        return "Select"
    }
    
    @objc func btnCategoryIdClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        self.isUpdateMachineIdFirstTime = false
        if self.arrCategoryList.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: "Select Category ID", arrData: self.arrCategoryList.compactMap { $0.name}, selectValue: "") { index, selectValue in

            var objProductDetails = self.objOrderData.arrProduct[sender.tag]
            objProductDetails.objCategory = self.arrCategoryList[index]
            
            //UPDATE ARRAY
            self.objOrderData.arrProduct.remove(at: sender.tag)
            self.objOrderData.arrProduct.insert(objProductDetails, at: sender.tag)

            self.arrMachineList = []
            self.arrMachineList = self.arrAllMachineList
                .filter { $0.category_id == self.arrCategoryList[index].id }

            //RELAD
            self.tblView.reloadData()
            
        }
    }
    @objc func btnMachineIdClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        self.isUpdateMachineIdFirstTime = false
        
        if self.arrMachineList.count == 0{
            return
        }
        
        var arrData : [String] = []
        for obj in self.arrMachineList{
            arrData.append("\(obj.product_name ?? "")    ||    \(obj.machine_id ?? "")")
        }
        
        
        actionPicker(sender, strTitle: "Select Machine ID", arrData: arrData, selectValue: self.getMachineName(id: self.arrOtherData[sender.tag].machine_id)) { index, selectValue in

            var objProductDetails = self.objOrderData.arrProduct[sender.tag]
            objProductDetails.objMachine = self.arrMachineList[index]
            
            //UPDATE ARRAY
            self.objOrderData.arrProduct.remove(at: sender.tag)
            self.objOrderData.arrProduct.insert(objProductDetails, at: sender.tag)

        
            //UPDATE DATA
            let obj = self.arrOtherData[sender.tag]
            obj.machine_id = self.arrMachineList[index].id ?? 0
            self.arrOtherData.remove(at: sender.tag)
            self.arrOtherData.insert(obj, at: sender.tag)
            
            
            //RELAD
            self.tblView.reloadData()
            
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if self.isLoading{
            return 0
        }
        else{
            return manageWidth(size: 250)
        }
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        //SET HEADER HEIGHT
        if let cell = tableView.dequeueReusableCell(withIdentifier: "FooterCheckListCell") as? FooterCheckListCell{
            cell.backgroundColor = UIColor.clear
            
            if self.objOrderData == nil{
                return cell
            }
            
            if self.objOrderData.arrProduct.count == 0{
                return cell
            }
            
            let  objDetails = self.arrOtherData[section]

            cell.lblNote.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: self.isDeliveryType == true ? str.strDelivredNote : str.strReturnedNote, numberOfLines: 1)
            cell.lblEmployee.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: self.isDeliveryType == true ? str.strDelivredEmployess : str.strReturnedEmployess, numberOfLines: 1)
            cell.lblLocation.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: self.isDeliveryType ? "" : str.strReturnedLocation, numberOfLines: 1)

            
            cell.txtSelctEmployee.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.isDeliveryType ?  objDetails.dEmplayess :  objDetails.rEmplayess, placeholder: str.strSelectEmployess)
            cell.txtSelctLocation.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.isDeliveryType ?  objDetails.dEmplayess :  objDetails.rStore, placeholder: str.strSelectLocation)

//            cell.con_Bottom.constant = manageWidth(size: 45.0)
            cell.txtNote.configureText(bgColour: .clear, textColor: .primary , fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.isDeliveryType ?  objDetails.dNote :  objDetails.rNote)
            cell.txtNote.tag = section
            cell.txtNote.delegate = self

            //SET BUTTON
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            
            // Create the "Done" button (you can replace it with any action)
//            let doneButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneButtonTapped))
            
            // Create the "Flexible Space" to push the button to the right side
            let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            
            // Create the "Right Button" (for example, a "Next" button)
            let rightButton = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(rightButtonTapped))
            
            // Add the flexible space and right button to the toolbar
            toolbar.items = [flexibleSpace, rightButton]

            cell.txtNote.inputAccessoryView = toolbar

            
            cell.viewNote.setTheTextView(bgColor: .secondary )
            cell.viewEmployee.setTheTextView(bgColor: .secondary )
            cell.viewLocation.setTheTextView(bgColor: .secondary )
            cell.con_Note.constant = manageWidth(size: checkDeviceiPad() ? 150 : 100)
            
//            //SET SIGNATURE
//            cell.con_imgSignature.constant = 0
//            cell.viewSignature.backgroundColor = .secondaryTextView
//            cell.lblSignature.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Customer Signature")
//            
//            if (self.isDeliveryType ? objDetails.dSignature : objDetails.rSignature) != UIImage() || (self.isDeliveryType ? objDetails.dSignatureUrl : objDetails.rSignatureUrl) != ""{
//                cell.con_imgSignature.constant = manageWidth(size: 200.0)
//                cell.imgSignature.backgroundColor = .white
//                cell.imgSignature.viewCorneRadius(radius: 10, isRound: false)
//                if (self.isDeliveryType ? objDetails.dSignature : objDetails.rSignature) != UIImage(){
//                    cell.imgSignature.image = (self.isDeliveryType ? objDetails.dSignature : objDetails.rSignature)
//                }
//                else if (self.isDeliveryType ? objDetails.dSignatureUrl : objDetails.rSignatureUrl) != ""{
//                    cell.imgSignature.setImage(strImg: (self.isDeliveryType ? objDetails.dSignatureUrl : objDetails.rSignatureUrl))
//                }
//            }
//            
//            //PRODUCT CHECK LIST
//            cell.lblProductStatus.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: self.isDeliveryType == true ? "Delivery Completed" : "Return Completed", numberOfLines: 1)
//            cell.imgProductStatus.image = UIImage(named: "icon_unCheck")
//            if self.checkDeliveryPickupStatus(isDeliveryType: self.isDeliveryType).1 == true {
//                cell.imgProductStatus.image = UIImage(named: "icon_Check")
//            }
//            imgColor(imgColor: cell.imgProductStatus, colorHex: .secondary)
//            
//            // BUTTON ACTION
//            cell.btnSignature.tag = section
//            cell.btnSignature.addTarget(self, action: #selector(self.btnSignatureClicked(_:)), for: .touchUpInside)
//
            cell.btnSelctEmployee.tag = section
            cell.btnSelctEmployee.addTarget(self, action: #selector(self.btnSelectEmployessClicked(_:)), for: .touchUpInside)
//
//            cell.btnComplate.tag = section
//            cell.btnComplate.addTarget(self, action: #selector(self.btnComplateClicked(_:)), for: .touchUpInside)

            cell.btnSelctLocation.tag = section
            cell.btnSelctLocation.addTarget(self, action: #selector(self.btnSelctLocationClicked(_:)), for: .touchUpInside)

            cell.viewLocation.isHidden = false
            if self.isDeliveryType{
                cell.viewLocation.isHidden = true
            }
            return cell
        }
        
        return UIView()
    }
    
  
     @objc func rightButtonTapped() {
         // Action for the right button (you can customize this)
         self.view.endEditing(true)
         self.tblView.reloadData()
     }
    
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if self.isLoading{
            return 0
        }
        else{
//            let objDetails = self.arrOtherData[section]
//            if (self.isDeliveryType ? objDetails.dSignature : objDetails.rSignature) != UIImage() || (self.isDeliveryType ? objDetails.dSignatureUrl : objDetails.rSignatureUrl) != ""{
//                return manageWidth(size: 630)
//            }
//            else{
//            }
            if self.isDeliveryType{
                return manageWidth(size: checkDeviceiPad() ? 360 : 310)
            }
            else{
                return manageWidth(size: checkDeviceiPad() ? 430 : 380)
            }
        }
    }
    
    
    @objc func btnSignatureClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        //SET PORTRAIT MODE
        AppUtility.lockOrientation(.landscape)
        let value = UIInterfaceOrientation.portrait.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")

        let signatureVC = EPSignatureViewController(signatureDelegate: self, showsDate: true, showsSaveSignatureOption: true)
        signatureVC.strIndex = sender.tag
        signatureVC.titleText = self.isDeliveryType == true ? "Delivery Signature" : "Return Signature"
        let nav = UINavigationController(rootViewController: signatureVC)
        nav.modalPresentationStyle = .fullScreen //or .overFullScreen for transparency
        present(nav, animated: true, completion: nil)

    }
    
    @objc func btnComplateClicked(_ sender: UIButton) {
        
        //GET
        let getDeliveryData = checkDeliveryPickupStatus(isDeliveryType: self.isDeliveryType)
        if getDeliveryData.1 == false{
            //GET PRODUCT NAME
            
            let MenuID = self.objOrderData.arrProduct.map{$0.product_id}
            if let index = MenuID.firstIndex(of: getDeliveryData.2){
                let productName = self.objOrderData.arrProduct[index].product_name
                
                
                //CALL API
                let alert = UIAlertController(title: Application.appName, message: "Are you sure you have deliverd '\(productName ?? "")' to \(self.objOrderData.objAdress?.name ?? "" )", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                   
                    let MenuID = self.objOrderData.arrDeliveryStatus.map{$0.product_id}
                    if let index = MenuID.firstIndex(of: getDeliveryData.2){
                        self.deliveryIndex = index
                        
                        if self.isDeliveryType{
                            self.updateStatus(UpdateStatusParameater: UpdateStatusParameater(id: "\(self.objOrderData.arrDeliveryStatus[index].id ?? 0)", delivery_status: "2", pickup_status: ""), index: sender.tag)
                        }
                        else{
                            self.updateStatus(UpdateStatusParameater: UpdateStatusParameater(id: "\(self.objOrderData.arrDeliveryStatus[index].id ?? 0)", delivery_status: "", pickup_status: "2"), index: sender.tag)
                        }
                    }
               
                }))
                alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
                self.present(alert, animated: true)
            }
        }
    }
    
    @objc func btnSelectEmployessClicked(_ sender: UIButton) {
       // self.view.endEditing(true)
        
        if self.arrEmployesList.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: "Select Emplopyee", arrData: self.arrEmployesList.compactMap { $0.name}, selectValue: self.isDeliveryType ? self.arrOtherData[sender.tag].dEmplayess : self.arrOtherData[sender.tag].rEmplayess) { index, selectValue in
            
            //UPDATE DATA
            let obj = self.arrOtherData[sender.tag]
            if self.isDeliveryType{
                obj.dEmplayess = selectValue
                obj.dEmplayessId = "\(self.arrEmployesList[index].id ?? 0)"
            }
            else{
                obj.rEmplayess = selectValue
                obj.rEmplayessId = "\(self.arrEmployesList[index].id ?? 0)"
            }
            self.arrOtherData.remove(at: sender.tag)
            self.arrOtherData.insert(obj, at: sender.tag)
            
            //RELAD
            self.tblView.reloadData()
        }
    }
    
    
    @objc func btnSelctLocationClicked(_ sender: UIButton) {
        if self.isDeliveryType{
            return
        }
        
        self.view.endEditing(true)
        
        if self.arrStoreList.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: "Select Store", arrData: self.arrStoreList.compactMap { $0.fullAddress}, selectValue: self.arrOtherData[sender.tag].rStore) { index, selectValue in
           
            //UPDATE DATA
            let obj = self.arrOtherData[sender.tag]
            obj.rStore = selectValue
            obj.rStoreId = "\(self.arrStoreList[index].id ?? 0)"

            self.arrOtherData.remove(at: sender.tag)
            self.arrOtherData.insert(obj, at: sender.tag)
            
            //RELAD
            self.tblView.reloadData()
        }
        
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isLoading{
            return 10
        }
        else{
            if self.objOrderData.arrProduct.count != 0{
                return self.objOrderData.arrProduct[section].checkList?.arrQuestions?.count ?? 0
            }
            else{
                return 0
            }
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
      
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "CheckListCell") as? CheckListCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.isHidden = true
            cell.viewDeliverySelect.isHidden = true
            cell.viewReturnSelect.isHidden = true

            if isLoading {
                cell.viewLine.isHidden = true
                self.machinePlaceholderMarker.register(cell.getAnimableSubviews())
                self.machinePlaceholderMarker.startAnimation()
                return cell
            }
            
            if self.objOrderData.arrProduct.count == 0 {
                return cell
            }
            
            if self.objOrderData.arrProduct[indexPath.section].checkList?.arrQuestions?.count == 0 {
                return cell
            }
            
            let  objDetails = self.objOrderData.arrProduct[indexPath.section].checkList?.arrQuestions?[indexPath.row]
                        

            cell.lblTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "\(objDetails?.objQuestion?.question ?? "")")
            if objDetails?.objQuestion?.checklist_type?.lowercased() == "tires"{
                cell.lblTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "\(objDetails?.objQuestion?.question ?? "") (Tires)")
            }
            else if objDetails?.objQuestion?.checklist_type?.lowercased() == "fuel"{
                var strName : String = ""
                if objDetails?.objQuestion?.fuel_type == 1{
                    strName = "Diesel"
                }
                else if objDetails?.objQuestion?.fuel_type == 2{
                    strName = "Gas"
                }
                else if objDetails?.objQuestion?.fuel_type == 3{
                    strName = "DEF"
                }
                cell.lblTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "Fuel (\(strName))")

            }
            else if objDetails?.objQuestion?.checklist_type?.lowercased() == "cleaning"{
                cell.lblTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "Cleaning")
            }
            
            
//            cell.lblDelivered.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: "")
            cell.lblDeliverySelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")
            cell.lblReturnSelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")

            cell.txtDelivered.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: objDetails?.objQuestion?.delivered ?? 0 <= 0 ? "" : "\(objDetails?.objQuestion?.delivered ?? 0.0)", placeholder: "0.0")
            cell.txtDelivered.accessibilityValue = "\(indexPath.section)"
            cell.txtDelivered.tag = 100
            cell.txtDelivered.accessibilityLanguage = "\(indexPath.row)"
            cell.txtDelivered.delegate = self
            cell.txtDelivered.isUserInteractionEnabled = self.isDeliveryType
            cell.viewDeliveredMain.isHidden = !self.isDeliveryType
            
//            cell.lblReturned.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: "")
            cell.txtReturned.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: objDetails?.objQuestion?.returned ?? 0 <= 0 ? "" : "\(objDetails?.objQuestion?.returned ?? 0)", placeholder: "0.0")
            cell.txtReturned.accessibilityValue = "\(indexPath.section)"
            cell.txtReturned.tag = 101
            cell.txtReturned.accessibilityLanguage = "\(indexPath.row)"
            cell.txtReturned.delegate = self
            cell.txtReturned.isUserInteractionEnabled = !self.isDeliveryType
            cell.viewReturnedMain.isHidden = self.isDeliveryType
            
            //SET BUTTON
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let rightButton = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(rightButtonTapped))
            toolbar.items = [flexibleSpace, rightButton]

            cell.txtReturned.inputAccessoryView = toolbar
            cell.txtDelivered.inputAccessoryView = toolbar
            
            if objDetails?.objQuestion?.checklist_type?.lowercased() == "default" && objDetails?.objQuestion?.arrAnswer.count != 0{
                if objDetails?.objQuestion?.delivered != 0 && objDetails?.objQuestion?.delivered != -1{
                    let MenuID = objDetails?.objQuestion?.arrAnswer.map{$0.id}
                    if let arrIndex = MenuID?.firstIndex(of: Int(objDetails?.objQuestion?.delivered ?? 0)){
                        cell.lblDeliverySelect.text = objDetails?.objQuestion?.arrAnswer[arrIndex].answer ?? ""
                    }
                }
                
                if objDetails?.objQuestion?.returned != 0 && objDetails?.objQuestion?.returned != -1{
                    let MenuID = objDetails?.objQuestion?.arrAnswer.map{$0.id}
                    if let arrIndex = MenuID?.firstIndex(of: Int(objDetails?.objQuestion?.returned ?? 0)){
                        cell.lblReturnSelect.text = objDetails?.objQuestion?.arrAnswer[arrIndex].answer ?? ""
                    }
                }
            }
            else if objDetails?.objQuestion?.checklist_type?.lowercased() == "tires"{
                if objDetails?.objQuestion?.returned != 0 && objDetails?.objQuestion?.returned != -1{
                    let strKey : String = "\(Int(objDetails?.objQuestion?.returned ?? 0))"
                    cell.lblReturnSelect.text = objDetails?.objQuestion?.tires_values[strKey]
                }
            }
            else if objDetails?.objQuestion?.checklist_type?.lowercased() == "cleaning"{
                if objDetails?.objQuestion?.delivered != 0 && objDetails?.objQuestion?.delivered != -1{
                    let strKey : String = "\(Int(objDetails?.objQuestion?.delivered ?? 0))"
                    cell.lblDeliverySelect.text = objDetails?.objQuestion?.clean_delivered_values[strKey]
                }
                
                if objDetails?.objQuestion?.returned != 0 && objDetails?.objQuestion?.returned != -1{
                    let strKey : String = "\(Int(objDetails?.objQuestion?.returned ?? 0))"
                    cell.lblReturnSelect.text = objDetails?.objQuestion?.clean_returned_values[strKey]
                }
            }
            else if objDetails?.objQuestion?.checklist_type?.lowercased() == "fuel"{
                if objDetails?.objQuestion?.delivered != -1{
                    let strKey : String = "\(Int(objDetails?.objQuestion?.delivered ?? 0))"
                    if objDetails?.objQuestion?.fuel_type == 2{
                        cell.lblDeliverySelect.text = objDetails?.objQuestion?.fuel_values_with_no_guage[strKey]
                    }
                    else{
                        cell.lblDeliverySelect.text = objDetails?.objQuestion?.fuel_values_with_guage[strKey]
                    }
                }
                
                
                if objDetails?.objQuestion?.returned != 0 && objDetails?.objQuestion?.returned != -1{
                    let strKey : String = "\(Int(objDetails?.objQuestion?.returned ?? 0))"
                    if objDetails?.objQuestion?.fuel_type == 2{
                        cell.lblReturnSelect.text = objDetails?.objQuestion?.fuel_values_with_no_guage[strKey]
                    }
                    else{
                        cell.lblReturnSelect.text = objDetails?.objQuestion?.fuel_values_with_guage[strKey]
                    }
                }
            }
            
            
//            cell.lblBalance.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strBalance)
//            cell.txtBalance.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(objDetails?.objQuestion?.balance ?? 0) \(objDetails?.objQuestion?.checklist_type?.lowercased() == "fuel" ? "Gallons" : "")", placeholder: "0.0")
//            cell.txtBalance.delegate = self
//
//
//            cell.lblValue.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strValue)
//            cell.txtValue.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(objDetails?.objQuestion?.question_value ?? 0)", placeholder: "0")
//            cell.txtValue.delegate = self
//            if objDetails?.objQuestion?.checklist_type?.lowercased() == "fuel"{
//                cell.txtValue.text = "\(objDetails?.objQuestion?.fuel_type == 1 ? "$\(self.objCheckListPrice.diesel_price ?? "")/Gallon" : "$\(self.objCheckListPrice.gas_price ?? "")/Gallon")"
//            }
//
//
//            cell.lblCustomerOwes.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strCustomerOwes)
//            cell.txtCustomerOwes.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(Application.currency)\(objDetails?.objQuestion?.customerOwes ?? 0)", placeholder: "0")
//            cell.txtCustomerOwes.delegate = self
            
            
            //SET TYPE
            imgColor(imgColor: cell.imgDeliverySelect, colorHex: .primary)
            imgColor(imgColor: cell.imgReturnSelect, colorHex: .primary)
            cell.viewDeliverySelect.isHidden = true
            cell.viewReturnSelect.isHidden = true
            cell.txtDelivered.isHidden = false
            cell.txtReturned.isHidden = false
            if objDetails?.objQuestion?.checklist_type?.lowercased() != "default" || objDetails?.objQuestion?.arrAnswer.count != 0{
                cell.viewDeliverySelect.isHidden = false
                cell.viewReturnSelect.isHidden = false
                cell.txtDelivered.isHidden = true
                cell.txtReturned.isHidden = true
                
                if objDetails?.objQuestion?.checklist_type?.lowercased() == "tires"{
                    cell.viewDeliverySelect.isHidden = true
                    cell.txtDelivered.isHidden = false
                }
            }

            
            //BUTTON ACTION
            cell.btnDeliverySelect.tag = indexPath.row
            cell.btnDeliverySelect.accessibilityValue = "\(indexPath.section)"
            cell.btnDeliverySelect.addTarget(self, action: #selector(self.btnDeliverySelectClicked(_:)), for: .touchUpInside)

            cell.btnReturnSelect.tag = indexPath.row
            cell.btnReturnSelect.accessibilityValue = "\(indexPath.section)"
            cell.btnReturnSelect.addTarget(self, action: #selector(self.btnReturnSelectClicked(_:)), for: .touchUpInside)

            
            //
//            cell.viewTotalCharge.viewBorderCorneRadius(borderColour: .clear)
//            cell.viewTotalChargeLine.isHidden = false
//            cell.txtTotalCharge.textColor = .primary
//            if objDetails.total_cost ?? 0 > 0{
//                cell.viewTotalChargeLine.isHidden = true
//                cell.viewTotalCharge.viewBorderCorneRadius(borderColour: .redText)
//                cell.txtTotalCharge.textColor = .redText
//            }
//            else{
//                cell.viewTotalChargeLine.isHidden = false
//                cell.viewTotalCharge.viewBorderCorneRadius(borderColour: .clear)
//                cell.txtTotalCharge.text = "\(Application.currency)0"
//                cell.txtTotalCharge.textColor = .primary
//            }
            return cell
        }

        return UITableViewCell()
        
    }
    

    @objc func btnDeliverySelectClicked(_ sender: UIButton) {
        if !self.isDeliveryType{
            return
        }
            
        let section : Int = Int(sender.accessibilityValue ?? "") ?? 0

        if self.objOrderData.arrProduct.count == 0 {
            return
        }
        
        if self.objOrderData.arrProduct[section].checkList?.arrQuestions?.count == 0 {
            return
        }
        
        let  objDetails = self.objOrderData.arrProduct[section].checkList?.arrQuestions?[sender.tag]
                 
        
        if objDetails?.objQuestion?.checklist_type?.lowercased() == "default" && objDetails?.objQuestion?.arrAnswer.count != 0{
            actionPicker(sender, strTitle: "Select", arrData: objDetails?.objQuestion?.arrAnswer.compactMap { $0.answer} ?? [], selectValue: "") { index, selectValue in
                
                
                var objProduct = self.objOrderData.arrProduct[section]
                var objdata = objProduct.checkList?.arrQuestions?[sender.tag]
                objdata?.objQuestion?.delivered = Float(objDetails?.objQuestion?.arrAnswer[index].id ?? 0)
                
                //SET DATA
                var deliveryPrice : Float = 0.0
                var returnPrice : Float = 0.0
                
                //GET DELIVERY DATA
                if objdata?.objQuestion?.delivered != 0 && objdata?.objQuestion?.delivered != -1{
                    deliveryPrice = objDetails?.objQuestion?.arrAnswer[index].answer_value ?? 0
                }
                
                
                //GET RETURN DATA
                let strReturId = objdata?.objQuestion?.returned
                if strReturId != 0 && strReturId != -1{
                    let MenuID = objDetails?.objQuestion?.arrAnswer.map{$0.id}
                    if let index = MenuID?.firstIndex(of: Int(strReturId ?? 0)){
                        returnPrice = objDetails?.objQuestion?.arrAnswer[index].answer_value ?? 0
                    }
                }
                
                let strPayPrive = returnPrice - deliveryPrice
                objdata?.objQuestion?.customerOwes = strPayPrive >= 0 ? strPayPrive : 0.0
                
                
                //UPDATE
                objProduct.checkList?.arrQuestions?.remove(at: sender.tag)
                objProduct.checkList?.arrQuestions?.insert(objdata!, at: sender.tag)
                
                //UPDATE ARRAY
                self.objOrderData.arrProduct.remove(at: section)
                self.objOrderData.arrProduct.insert(objProduct, at: section)
                
                //RELOAD TABLE
                self.tblView.reloadData()
                
                
                //RELOAD TABLE
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                    self.CalculatTotalCharge()
                }                
            }
        }
        else{
            var arrData : [String : String] = [:]
            if objDetails?.objQuestion?.checklist_type?.lowercased() == "tires"{
                arrData = objDetails?.objQuestion?.tires_values ?? [:]
            }
            else if objDetails?.objQuestion?.checklist_type?.lowercased() == "fuel"{
                if objDetails?.objQuestion?.fuel_type == 2{
                    arrData = objDetails?.objQuestion?.fuel_values_with_no_guage  ?? [:]
                }
                else{
                    arrData = objDetails?.objQuestion?.fuel_values_with_guage ?? [:]
                }

            }
            else if objDetails?.objQuestion?.checklist_type?.lowercased() == "cleaning"{
                arrData = objDetails?.objQuestion?.clean_delivered_values ?? [:]

            }
            
            let strKey : String = "\(Int(objDetails?.objQuestion?.delivered ?? 0))"
            actionPicker(sender, strTitle: "Select", arrData: arrData.sorted { $0.key > $1.key }.compactMap { $0.value}, selectValue: arrData[strKey] ?? "") { index, selectValue in

                print(index)
                print(selectValue)
                
                if let key = arrData.first(where: { $0.value == selectValue })?.key {
                    var objProduct = self.objOrderData.arrProduct[section]
                    var objdata = objProduct.checkList?.arrQuestions?[sender.tag]
                    
                    objdata?.objQuestion?.delivered = Float(key) ?? 0.0

                    if objDetails?.objQuestion?.checklist_type?.lowercased() == "cleaning"{
                        
                        //SET DATA
                        var deliveryPrice : Float = 0.0
                        var returnPrice : Float = 0.0

                        //GET DELIVERY DATA
                        if objdata?.objQuestion?.delivered != 0 && objdata?.objQuestion?.delivered != -1{
                            let strReturnKey : String = "\(Int(objdata?.objQuestion?.delivered ?? 0))"
                            let strValue = objdata?.objQuestion?.clean_delivered_values[strReturnKey]
                            if strValue == "Pre-Paid" || strValue == "Std. Clean Req."{
                                deliveryPrice = Float(objdata?.objQuestion?.sd_clean_price ?? "") ?? 0.0
                            }
                        }
                        
                        
                        //GET RETURN DATA
                        if objdata?.objQuestion?.returned != 0 && objdata?.objQuestion?.returned != -1{
                            let strReturnKey : String = "\(Int(objdata?.objQuestion?.returned ?? 0))"
                            let strValue = objdata?.objQuestion?.clean_returned_values[strReturnKey]
                            if strValue == "Std. Clean Req."{
                                returnPrice = Float(objdata?.objQuestion?.sd_clean_price ?? "") ?? 0.0
                            }
                            else if strValue == "Ext. Clean Req."{
                                returnPrice = Float(objdata?.objQuestion?.ex_clean_price ?? "") ?? 0.0
                            }

                        }
                       
                        let strPayPrive = returnPrice - deliveryPrice
                        objdata?.objQuestion?.customerOwes = strPayPrive >= 0 ? strPayPrive : 0.0
                    }
                    else if objDetails?.objQuestion?.checklist_type?.lowercased() == "fuel"{
                        var price : Float = 0.0
                        if objDetails?.objQuestion?.fuel_type == 1{
                            price = Float(self.objCheckListPrice.diesel_price ?? "") ?? 0.0
                        }
                        else if objDetails?.objQuestion?.fuel_type == 2{
                            price = Float(self.objCheckListPrice.gas_price ?? "") ?? 0.0
                        }
                        else if objDetails?.objQuestion?.fuel_type == 3{
                            price = Float(self.objCheckListPrice.def_price ?? "") ?? 0.0
                        }
                        
                        let getFuelData = self.FuelCalulateTotalCharge(total: objdata?.objQuestion?.question_value ?? 0.0, dSelect: objdata?.objQuestion?.delivered ?? 0.0, rSelect: objdata?.objQuestion?.returned ?? 0.0)

                        //SET DATA
                        objdata?.objQuestion?.balance = getFuelData >= 0 ? getFuelData : 0.0
                        objdata?.objQuestion?.customerOwes = getFuelData >= 0 ? getFuelData * price : 0.0
                        
                    }

                    
                    
                  
                    //UPDATE
                    objProduct.checkList?.arrQuestions?.remove(at: sender.tag)
                    objProduct.checkList?.arrQuestions?.insert(objdata!, at: sender.tag)
                    
                    //UPDATE ARRAY
                    self.objOrderData.arrProduct.remove(at: section)
                    self.objOrderData.arrProduct.insert(objProduct, at: section)
                    
                    //RELOAD TABLE
                    self.tblView.reloadData()

                    
                    //RELOAD TABLE
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                        self.CalculatTotalCharge()
                    }
                    
                    
                }
            
            }
        }
    }


    @objc func btnReturnSelectClicked(_ sender: UIButton) {
        if self.isDeliveryType{
            return
        }
        
        let section : Int = Int(sender.accessibilityValue ?? "") ?? 0

        if self.objOrderData.arrProduct.count == 0 {
            return
        }
        
        if self.objOrderData.arrProduct[section].checkList?.arrQuestions?.count == 0 {
            return
        }
        
        let  objDetails = self.objOrderData.arrProduct[section].checkList?.arrQuestions?[sender.tag]
                 
        
        if objDetails?.objQuestion?.checklist_type?.lowercased() == "default" && objDetails?.objQuestion?.arrAnswer.count != 0{
            
            
            actionPicker(sender, strTitle: "Select", arrData: objDetails?.objQuestion?.arrAnswer.compactMap { $0.answer} ?? [], selectValue: "") { index, selectValue in
                
                var objProduct = self.objOrderData.arrProduct[section]
                var objdata = objProduct.checkList?.arrQuestions?[sender.tag]
                objdata?.objQuestion?.returned = Float(objDetails?.objQuestion?.arrAnswer[index].id ?? 0)
                
                //SET DATA
                var deliveryPrice : Float = 0.0
                var returnPrice : Float = 0.0
                
                //GET RETURN DATA
                if objdata?.objQuestion?.returned != 0{
                    returnPrice = objDetails?.objQuestion?.arrAnswer[index].answer_value ?? 0
                }
                
                
                //GET DELIVERY DATA
                let strReturId = objdata?.objQuestion?.delivered
                if strReturId != 0{
                    let MenuID = objDetails?.objQuestion?.arrAnswer.map{$0.id}
                    if let index = MenuID?.firstIndex(of: Int(strReturId ?? 0)){
                        deliveryPrice = objDetails?.objQuestion?.arrAnswer[index].answer_value ?? 0
                    }
                }
                
                let strPayPrive = returnPrice - deliveryPrice
                objdata?.objQuestion?.customerOwes = strPayPrive >= 0 ? strPayPrive : 0.0
                
                
                //UPDATE
                objProduct.checkList?.arrQuestions?.remove(at: sender.tag)
                objProduct.checkList?.arrQuestions?.insert(objdata!, at: sender.tag)
                
                //UPDATE ARRAY
                self.objOrderData.arrProduct.remove(at: section)
                self.objOrderData.arrProduct.insert(objProduct, at: section)
                
                //RELOAD TABLE
                self.tblView.reloadData()
                
                
                //RELOAD TABLE
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                    self.CalculatTotalCharge()
                }                        }
        }
        else{
            var arrData : [String : String] = [:]
            if objDetails?.objQuestion?.checklist_type?.lowercased() == "tires"{
                arrData = objDetails?.objQuestion?.tires_values ?? [:]
            }
            else if objDetails?.objQuestion?.checklist_type?.lowercased() == "fuel"{
                if objDetails?.objQuestion?.fuel_type == 2{
                    arrData = objDetails?.objQuestion?.fuel_values_with_no_guage ?? [:]
                }
                else{
                    arrData = objDetails?.objQuestion?.fuel_values_with_guage ?? [:]
                }

            }
            else if objDetails?.objQuestion?.checklist_type?.lowercased() == "cleaning"{
                arrData = objDetails?.objQuestion?.clean_returned_values ?? [:]

            }
            
            let strKey : String = "\(Int(objDetails?.objQuestion?.returned ?? 0))"
            actionPicker(sender, strTitle: "Select", arrData: arrData.sorted { $0.key < $1.key }.compactMap { $0.value}, selectValue: arrData[strKey] ?? "") { index, selectValue in

                print(index)
                print(selectValue)
                
                if let key = arrData.first(where: { $0.value == selectValue })?.key {
                    var objProduct = self.objOrderData.arrProduct[section]
                    var objdata = objProduct.checkList?.arrQuestions?[sender.tag]
                    
                    objdata?.objQuestion?.returned = Float(key) ?? 0.0

                    
                    if objDetails?.objQuestion?.checklist_type?.lowercased() == "tires"{
                        if key == "2"{
                            objdata?.objQuestion?.customerOwes = self.objCheckListPrice.tire_repair
                        }
                        else if key == "3"{
                            objdata?.objQuestion?.customerOwes = self.objCheckListPrice.tire_10_ply
                        }
                        else if key == "4"{
                            objdata?.objQuestion?.customerOwes = self.objCheckListPrice.tire_14_ply
                        }
                    }
                    else if objDetails?.objQuestion?.checklist_type?.lowercased() == "cleaning"{
                        
                        //SET DATA
                        var deliveryPrice : Float = 0.0
                        var returnPrice : Float = 0.0

                        //GET DELIVERY DATA
                        if objdata?.objQuestion?.delivered != 0 && objdata?.objQuestion?.delivered != -1{
                            let strReturnKey : String = "\(Int(objdata?.objQuestion?.delivered ?? 0))"
                            let strValue = objdata?.objQuestion?.clean_delivered_values[strReturnKey]
                            if strValue == "Pre-Paid" || strValue == "Std. Clean Req."{
                                deliveryPrice = Float(objdata?.objQuestion?.sd_clean_price ?? "") ?? 0.0
                            }
                        }
                        
                        
                        //GET RETURN DATA
                        if objdata?.objQuestion?.returned != 0 && objdata?.objQuestion?.returned != -1{
                            let strReturnKey : String = "\(Int(objdata?.objQuestion?.returned ?? 0))"
                            let strValue = objdata?.objQuestion?.clean_returned_values[strReturnKey]
                            if strValue == "Std. Clean Req."{
                                returnPrice = Float(objdata?.objQuestion?.sd_clean_price ?? "") ?? 0.0
                            }
                            else if strValue == "Ext. Clean Req."{
                                returnPrice = Float(objdata?.objQuestion?.ex_clean_price ?? "") ?? 0.0
                            }

                        }
                       
                        let strPayPrive = returnPrice - deliveryPrice
                        objdata?.objQuestion?.customerOwes = strPayPrive >= 0 ? strPayPrive : 0.0
                    }
                    else if objDetails?.objQuestion?.checklist_type?.lowercased() == "fuel"{
                        var price : Float = 0.0
                        if objDetails?.objQuestion?.fuel_type == 1{
                            price = Float(self.objCheckListPrice.diesel_price ?? "") ?? 0.0
                        }
                        else if objDetails?.objQuestion?.fuel_type == 2{
                            price = Float(self.objCheckListPrice.gas_price ?? "") ?? 0.0
                        }
                        else if objDetails?.objQuestion?.fuel_type == 3{
                            price = Float(self.objCheckListPrice.def_price ?? "") ?? 0.0
                        }
                        
                        let getFuelData = self.FuelCalulateTotalCharge(total: objdata?.objQuestion?.question_value ?? 0.0, dSelect: objdata?.objQuestion?.delivered ?? 0.0, rSelect: objdata?.objQuestion?.returned ?? 0.0)

                        //SET DATA
                        objdata?.objQuestion?.balance = getFuelData >= 0 ? getFuelData : 0.0
                        objdata?.objQuestion?.customerOwes = getFuelData >= 0 ? getFuelData * price : 0.0
                    }

                    
                    
                  
                    //UPDATE
                    objProduct.checkList?.arrQuestions?.remove(at: sender.tag)
                    objProduct.checkList?.arrQuestions?.insert(objdata!, at: sender.tag)
                    
                    //UPDATE ARRAY
                    self.objOrderData.arrProduct.remove(at: section)
                    self.objOrderData.arrProduct.insert(objProduct, at: section)
                    
                    //RELOAD TABLE
                    self.tblView.reloadData()

                    //RELOAD TABLE
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                        self.CalculatTotalCharge()
                    }
                    
                    
                }
            
            }
        }

    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
      
    }
    
    
 
    func FuelCalulateTotalCharge(total : Float, dSelect : Float , rSelect : Float) -> Float{
        if dSelect <= 0 || rSelect <= 0{
            return 0
        }
        return (total/8) * (dSelect - rSelect)
    }
    
    func CalculatChecklistTotalCharge(){
        if self.isDeliveryType {
            return
        }
        
        self.strTotalCharge = 0.0
        
        for i in 0..<self.objOrderData.arrProduct.count{
            let objProduct = self.objOrderData.arrProduct[i]
            
            for j in 0..<(objProduct.checkList?.arrQuestions?.count ?? 0){
                let objQuestion = objProduct.checkList?.arrQuestions?[j]
                
                //SET TOTAL CHARGE
                self.strTotalCharge = self.strTotalCharge + (objQuestion?.objQuestion?.customerOwes ?? 0.0)
                
            }
        }
        
        //RELOAD TABLE
        self.lblTotalCharge.text = "\(Application.currency)\(self.strTotalCharge)"
        
        
    }
}





//MARK: - KEYBORD DELEGATE
extension CheckListViewController {
    
    @objc func keyboardWillShow(notification: NSNotification) {
       let keyboardHeight = (notification.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height
       print(keyboardHeight)
//        self.con_SubmitBottom.constant = (keyboardHeight - GetBottomSafeAreaHeight()) + 16
        self.con_SubmitBottom.constant = 16.0

    }

    @objc func keyboardWillHide(notification: NSNotification) {
       let keyboardHeight = (notification.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height
       print(keyboardHeight)
        self.con_SubmitBottom.constant = 16.0

        //RELOAD TABLE
        self.CalculatTotalCharge()
        self.tblView.reloadData()

    }
}

