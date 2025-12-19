//
//  CheckListUpdateViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 06/01/25.
//

import UIKit


//protocol  CheckListDelegate : NSObject {
//    func UpdateCheckListProduct(selectIndex: Int, arrUpdateCheckList : [NoteModel])
//}

class CheckListUpdateViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: CheckListDelegate?

    @IBOutlet weak var tblView: UITableView!
    @IBOutlet weak var con_tableView: NSLayoutConstraint!

    @IBOutlet weak var con_Submit: NSLayoutConstraint!
    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!

    @IBOutlet weak var lblTotalChargeTitle: UILabel!
    @IBOutlet weak var lblTotalCharge: UILabel!

   

    //LOADING
    let machinePlaceholderMarker = Placeholder()

    //OTHER
    var isLoading : Bool = false

    
    var objOrderData : OrdersModel!
    var arrProductList : [ProductModel] = []
    var arrEmployesList : [EmployeesModel] = []
    var arrOtherData : [NoteModel] = []
    var objCheckListPrice : CheckListPriceModel!
    var arrMachineList : [MachineModel] = []
    var arrPriceList : [PriceListModel] = []

    var selectIndex : Int = -1
    var strOrderID : String = ""
    var strOrderUniqueId : String = ""
    var strProductID : String = ""

    var strTotalCharge : Float = 0.0
    var isDeliveryType : Bool = false
    var selectEmployessID : String = ""
    var deliveryIndex : Int = 0
    var isOrderDetailsView : Bool = false
    var isUpdateData : Bool = false
    var isDeleteChecklist : Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        setupCutomeKeyboard()
        // Do any additional setup after loading the view.
        setupKeyboard(false)

        //CALL API
        self.viewSubmit.isHidden = true
        if self.isUpdateData{
            self.isLoading = true
            self.getEmployeesListAPI(CatrgoryParameater: CatrgoryParameater())
        }
        else{
            self.setTheView()
        }
        
        //KEYBOARD METHOD
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification , object:nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification , object:nil)

        //GET PRICE LIST
        getPriceList { arr_data in
            self.arrPriceList = arr_data
        }
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
        self.viewSubmit.backgroundColor = self.isDeleteChecklist ? .redText : .secondaryTextView
        self.lblSubmit.configureLable(textColor: self.isDeleteChecklist ? .primary : .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.isDeleteChecklist ? str.strRemoveChecklist : str.strSubmit)
        
        if self.checkCheckListStatus(isDelivery: true) && self.checkCheckListStatus(isDelivery: false){
            self.viewSubmit.isHidden = true
        }
        
        self.lblTotalChargeTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strTotalCheckList)
        self.lblTotalChargeTitle.isHidden = false
        self.lblTotalCharge.isHidden = false
        if self.isDeliveryType{
            self.lblTotalChargeTitle.isHidden = self.checkCheckListStatus(isDelivery: true) ? false : true
            self.lblTotalCharge.isHidden = self.checkCheckListStatus(isDelivery: true) ? false : true
        }
        
        //UPDATE DATA
//        self.setCheckListData()
        
     
        //SET HEADER
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            //SET TABLE HEADER
            let vw_Table = self.tblView.tableFooterView
            vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.viewSubmit.frame.origin.y + self.viewSubmit.frame.size.height)

            self.tblView.tableFooterView = vw_Table

            //RELOAD TABLE
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                self.tblView.reloadData()
            }

        }
    }
    
    func stopLoading(){
        indicatorHide()
        self.CalculatTotalCharge()
        self.tblView.reloadData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.machinePlaceholderMarker.remove()
        }
    }
    
    func checkCheckListStatus(isDelivery : Bool) -> Bool{
        //GET DATA
        if self.objOrderData == nil{
            return false
        }

        for obj in self.objOrderData.arrProduct{
            if isDelivery {
                return obj.is_delivered ?? false

            }
            else{
                return obj.is_returned ?? false
            }
        }
        return false
    }
  
}



//MARK: - BUTTON ACTION
extension CheckListUpdateViewController : EPSignatureDelegate{
    
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
        if self.isDeleteChecklist{
            //REMOVE CHECKLIST
            //CALL API
            let alert = UIAlertController(title: Application.appName, message: "Are you sure you want to replace or delete this Equipment?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                
                
            }))
            
            
            alert.addAction(UIAlertAction(title: str.no, style: .default,handler: { (Action) in
            }))
            
            self.present(alert, animated: true)
        }
        else{
           
            if self.checkMachineData() == false{
                return
            }
            
            if self.checkOtherData() == false{
                return
            }
         
            if self.checkCustomerSignature() == false{
                return
            }
            
            
            var dicData : [String : Any] = [:]
//            var arrCheckListData: [[String: Any]] = []
            for obj in self.objOrderData.arrProduct{
                var arrData : [[String : Any]] = []
                for objChecklist in obj.arrQuestions{
                    if objChecklist.type != "text" && objChecklist.type != "fuel"{
                        let dic : [String : Any] = ["question_unique_id" : objChecklist.unique_id ?? "",
                                                    "answer_unique_id" : self.isDeliveryType ? objChecklist.deliverAnswer.unique_id ?? "" : objChecklist.returnAnswer.unique_id ?? ""]
                        arrData.append(dic)
                    }
                }
                
                
                //CONVERT CHECKLIST DATA IN STRING
                var strCheckList : String = ""
//                var jsonObject : Any?
                do {

                    
                    let jsonData = try JSONSerialization.data(withJSONObject: arrData, options: [])
                    
//                    jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
//                    print(jsonObject) // Array of dictionaries

                    // If you want a String for debugging
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        strCheckList = jsonString
                    }
                } catch {
                    print("Error serializing JSON:", error)
                }
                                
                //OTHER DATA
                for objOther in self.arrOtherData{
                    
                    dicData = [
                        "order_product_unique_id": obj.unique_id ?? "",
                        "equipment_unique_id": obj.objMachine?.unique_id ?? "",
                        "checklist[]": strCheckList,

                        "start_hours": self.isDeliveryType ? "\(objOther.startHours)" : "",
                        "end_hours": self.isDeliveryType ? "" : "\(objOther.endHours)",
                        "user_id": self.isDeliveryType ? objOther.dEmplayessId : objOther.rEmplayessId,
                        "note": self.isDeliveryType ? objOther.dNote : objOther.rNote,
                        "total_charge": self.isDeliveryType ? "" : "\(self.strTotalCharge)",
                        "store_id": self.isDeliveryType ? "" : objOther.rStoreId,
                        "fuel_initial_reading": objOther.selectFuleDelivery,
                        "fuel_final_reading": objOther.selectFuleReturn,
                        "dSignature": (objOther.dSignature ?? UIImage()),
                        "rSignature": (objOther.rSignature ?? UIImage()),
                        "type": self.isDeliveryType ? "Delivery" : "Return"
                    ]
//                    arrCheckListData.append(dicData)
                }
            }
           

            //CALL API
            let alert = UIAlertController(title: Application.appName, message: "Are you sure you're ready to Submit this report?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                
                //UPDATE CHECK LIST
//                self.saveArrayWithImages(arrCheckListData, forKey: kFileStorageName.kSaveCheckList.rawValue)
                self.updateCheckList(dicCheckList: dicData)
    //            self.updateStatus()
                
            }))
            
            
            alert.addAction(UIAlertAction(title: str.no, style: .default,handler: { (Action) in
            }))
            
            self.present(alert, animated: true)
        }
    }
    

    func saveArrayWithImages(_ array: [[String: Any]], forKey key: String) {
        var processedArray = [[String: Any]]()
        
        for var dict in array {
            if let image = dict["image"] as? UIImage {
                // Convert image to JPEG or PNG
                if let imgData = image.jpegData(compressionQuality: 0.8) {
                    dict["image"] = imgData  // replace UIImage with Data
                }
            }
            processedArray.append(dict)
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: processedArray, options: [])
            SDKUserDefault.save(data, for: key)
        } catch {
            print("❌ Error saving:", error)
        }
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
                if obj.dEmplayessId == ""{
                    showAlertMessage(strMessage: "Please select delivered by")
                    return false
                }
                
//                if obj.dSignature == UIImage() && obj.dSignatureUrl == ""{
//                    showAlertMessage(strMessage: "Customer signature is required")
//                    return false
//                }
            }
            else{
                if obj.rEmplayessId == ""{
                    showAlertMessage(strMessage: "Please select returnd by")
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
    
    func checkCustomerSignature() -> Bool{
        if self.arrOtherData.count != 0{
            let obj = self.arrOtherData.last
            
            if self.isDeliveryType{
                if obj?.dSignature == UIImage() && obj?.dSignatureUrl == ""{
                    showAlertMessage(strMessage: "Customer signature is required")
                    return false
                }
            }
            else{
                if obj?.rSignature == UIImage() && obj?.rSignatureUrl == ""{
                    showAlertMessage(strMessage: "Customer signature is required")
                    return false
                }
            }
        }
       

        return true
    }
}



extension CheckListUpdateViewController:  UITextViewDelegate{
   
    
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
extension CheckListUpdateViewController : UITextFieldDelegate{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool{
        
        //RELOAD TABLE
        self.CalculatTotalCharge()
        self.tblView.reloadData()
        
        return true
    }
    

    
    func CalculatTotalCharge(){
        self.strTotalCharge = 0.0
        if self.objOrderData == nil { return }
        
        for i in 0..<self.objOrderData.arrProduct.count{
            var objProduct = self.objOrderData.arrProduct[i]
            
            if self.checkCheckListStatus(isDelivery: true) && self.checkCheckListStatus(isDelivery: false){
                self.strTotalCharge = self.strTotalCharge + Float(objProduct.total_charge)
            }
            else{
                for (index,obj) in objProduct.arrQuestions.enumerated(){
                    var objQuestion = obj
                    if objQuestion.type == "text"{
                        let hours = Float(objQuestion.endHours) - Float(objQuestion.startHours)
                        let totalHours = Int(hours.rounded(.up))
                        objQuestion.total = 0
                        if totalHours > 0{
                            //SET TOTAL HOURS
                            objQuestion.total = Float(totalHours)
                        }
                        
                        
                        //SET ADDITION HOURS
                        var additionslHours = Float(totalHours) - (objProduct.allocated_hours ?? 0)
                        objQuestion.additinal = 0
                        if additionslHours > 0{
                            //SET TOTAL HOURS
                            objQuestion.additinal = Int(Float(additionslHours))
                        }
                        else{
                            additionslHours = 0
                        }
                        
                        //SET TOTAL CHARGE
                        self.strTotalCharge =  self.strTotalCharge + Float(additionslHours) * Float(objQuestion.hour_rate)
                        objQuestion.total_cost = self.strTotalCharge
                        
                        
                        //UPDATE
                        objProduct.arrQuestions.remove(at: index)
                        objProduct.arrQuestions.insert(objQuestion, at: index)
                        
                        //UPDATE ARRAY
                        self.objOrderData.arrProduct.remove(at: i)
                        self.objOrderData.arrProduct.insert(objProduct, at: i)
                        
                    }
                    else if objQuestion.type == "fuel"{
                        
                        let price = self.getPrice(strFuleType: objQuestion.fuleType ?? "", isDef: objQuestion.isDEF ?? "")
                        var totalPrice  : Float = 0.0
                        if objQuestion.isDEF == "Yes"{
                            totalPrice = price * (Float(objQuestion.def_tank_capacity ?? "") ?? 0)
                        }
                        else if objQuestion.fuleType == "diesel"{
                            totalPrice = price * (Float(objQuestion.diesel_tank_capacity ?? "") ?? 0)
                        }
                        else if objQuestion.fuleType == "gas"{
                            totalPrice = price * (Float(objQuestion.gas_tank_capacity ?? "") ?? 0)
                        }
                        
                        self.strTotalCharge = self.strTotalCharge + FuelCalulateTotalCharge(total: totalPrice, dSelect: Float(objQuestion.selectFuleDelivery ?? "") ?? 0, rSelect: Float(objQuestion.selectFuleReturn ?? "") ?? 0)
                        
                    }
                    
                    else if objQuestion.deliverAnswer != nil && objQuestion.returnAnswer != nil{
                        let strPrice = Float(objQuestion.returnAnswer.return_amt) - Float(objQuestion.deliverAnswer.delivery_amt)
                        if strPrice > 0{
                            self.strTotalCharge = self.strTotalCharge + strPrice
                        }
                    }
                }
            }
        }
        
        
        //RELOAD TABLE
        print("\(Application.currency)\(String(format: "%.2f", self.strTotalCharge))")
        self.lblTotalCharge.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "\(Application.currency)\(String(format: "%.2f", self.strTotalCharge))")
        print(self.lblTotalCharge.text ?? "")

    }
    
    func getPrice(strFuleType : String, isDef : String) -> Float{
        if isDef == "Yes"{
            let MenuID = self.arrPriceList.map{$0.setting_name}
            if let index = MenuID.firstIndex(of: "def_price_per_gallon"){
                if let price = Float(self.arrPriceList[index].setting_value ?? "0") {
                    return price
                }
            }
        }
        else if strFuleType == "gas"{
            let MenuID = self.arrPriceList.map{$0.setting_name}
            if let index = MenuID.firstIndex(of: "gas_price_per_gallon"){
                if let price = Float(self.arrPriceList[index].setting_value ?? "0") {
                    return price
                }
            }
        }
        else if strFuleType == "diesel"{
            let MenuID = self.arrPriceList.map{$0.setting_name}
            if let index = MenuID.firstIndex(of: "diesel_price_per_gallon"){
                if let price = Float(self.arrPriceList[index].setting_value ?? "0") {
                    return price
                }
            }
        }
        
        return 0
    }
    
}



class CheckListUpdateCell : UITableViewCell{

    @IBOutlet weak var lblTitle: UILabel!

    @IBOutlet weak var viewDeliveredMain: UIView!
    @IBOutlet weak var viewReturnedMain: UIView!

    @IBOutlet weak var lblDelivered: UILabel!
    @IBOutlet weak var viewDeliverySelect: UIView!
    @IBOutlet weak var lblDeliverySelect: UILabel!
    @IBOutlet weak var imgDeliverySelect: UIImageView!
    @IBOutlet weak var btnDeliverySelect: UIButton!
    
    @IBOutlet weak var lblReturned: UILabel!
    @IBOutlet weak var viewReturnSelect: UIView!
    @IBOutlet weak var lblReturnSelect: UILabel!
    @IBOutlet weak var imgReturnSelect: UIImageView!
    @IBOutlet weak var btnReturnSelect: UIButton!

    
    
    
    @IBOutlet weak var lblTitleDelivered: UILabel!

        
    
    @IBOutlet weak var viewBalance: UIView!
    @IBOutlet weak var lblBalance: UILabel!
    @IBOutlet weak var txtBalance: UITextField!
//
//
    
    @IBOutlet weak var viewAdditional: UIView!
    @IBOutlet weak var lblAdditional: UILabel!
    @IBOutlet weak var txtAdditional: UITextField!
//
    
    @IBOutlet weak var viewHourlyFee: UIView!
    @IBOutlet weak var lblHourlyFee: UILabel!
    @IBOutlet weak var txtHourlyFee: UITextField!
//
    
    @IBOutlet weak var viewValue: UIView!
    @IBOutlet weak var lblValue: UILabel!
    @IBOutlet weak var txtValue: UITextField!

    @IBOutlet weak var viewCustomerOwes: UIView!
    @IBOutlet weak var lblCustomerOwes: UILabel!
    @IBOutlet weak var txtCustomerOwes: UITextField!
    @IBOutlet weak var viewCustomerOwesLine: UIView!


    @IBOutlet weak var viewLine: UIView!

    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            lblTitle,
//            lblDelivered,
            viewDeliveredMain,
//            lblReturned,
            viewReturnedMain,
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

extension CheckListUpdateViewController : UITableViewDelegate, UITableViewDataSource{
    
    //HEADER SECTION
    func numberOfSections(in tableView: UITableView) -> Int {
        if self.isLoading{
            return 1
        }
        else{
            if objOrderData != nil{
                return self.objOrderData.arrProduct.count
            }
            return 0
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
            cell.imgProduct.backgroundColor = .white
            if let strImg = objProductDetails.objProductData?.product_image_url{
                cell.imgProduct.setImage(strImg: strImg)
            }

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

    
            
//            cell.lblTitleCategoryId.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "Category ID *")
            cell.lblTitleMachineId.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "Machine ID")
//            cell.lblCategoryId.configureLable(textAlignment: .center, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")
            cell.lblMachineId.configureLable(textAlignment: .center, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")
//            imgColor(imgColor: cell.imgCategoryId, colorHex: .primary)
//            imgColor(imgColor: cell.imgMachineId, colorHex: .primary)

//            if objProductDetails.objCategory != nil{
//                cell.lblCategoryId.text = objProductDetails.objCategory?.name ?? ""
//            }
            
            if objProductDetails.objMachine != nil{
                cell.lblMachineId.text = "\(objProductDetails.objMachine?.equipment_name ?? "")    ||    \(objProductDetails.objMachine?.equipment_id ?? "")"
            }
           
            
//            cell.viewCategoryId.backgroundColor = .clear
//            cell.viewCategoryId.viewBorderCorneRadius(borderColour: .secondaryText)
            
            cell.viewMachineId.backgroundColor = .clear
            cell.viewMachineId.viewBorderCorneRadius(borderColour: .secondaryText)


            return cell
        }
        
        return UIView()
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
            cell.backgroundColor = UIColor.background
            
            if self.objOrderData == nil{
                return cell
            }
            
            if self.objOrderData.arrProduct.count == 0{
                return cell
            }
            
            let  objDetails = self.arrOtherData[section]

            cell.lblNote.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: self.isDeliveryType == true ? str.strDelivredNote : str.strReturnedNote, numberOfLines: 1)
            cell.lblEmployee.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: self.isDeliveryType == true ? str.strDelivredEmployess : str.strReturnedEmployess, numberOfLines: 1)
            
            cell.txtSelctEmployee.configureText(textAlignment: .right ,bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.isDeliveryType ?  objDetails.dEmplayess :  objDetails.rEmplayess, placeholder: str.strSelectEmployess)

            cell.con_Bottom.constant = manageWidth(size: 45.0)
            
            cell.lblNote.text = ""
            cell.lblNoteDetails.text = ""
            cell.con_NoteTop.constant = -30
            let strNote = self.isDeliveryType ?  objDetails.dNote :  objDetails.rNote
            if strNote != "" {
                cell.con_NoteTop.constant = 8
                cell.lblNote.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "\(self.isDeliveryType == true ? str.strDelivredNote : str.strReturnedNote):", numberOfLines: 1)
                cell.lblNoteDetails.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: strNote, numberOfLines: 0)
            }
            
            
            //SET SIGNATURE
            cell.con_imgSignature.constant = 0
            cell.viewSignature.backgroundColor = .secondaryTextView?.withAlphaComponent(0.7)
            cell.lblSignature.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Customer Signature")
            
            if (self.isDeliveryType ? objDetails.dSignature : objDetails.rSignature) != UIImage() || (self.isDeliveryType ? objDetails.dSignatureUrl : objDetails.rSignatureUrl) != ""{
                if self.isUpdateData{
                    cell.con_Bottom.constant = manageWidth(size: 0)
                }

                cell.con_imgSignature.constant = manageWidth(size: 200.0)
                cell.imgSignature.backgroundColor = .white
                cell.imgSignature.viewCorneRadius(radius: 10, isRound: false)
                if (self.isDeliveryType ? objDetails.dSignature : objDetails.rSignature) != UIImage(){
                    cell.imgSignature.image = (self.isDeliveryType ? objDetails.dSignature : objDetails.rSignature)
                }
                else if (self.isDeliveryType ? objDetails.dSignatureUrl : objDetails.rSignatureUrl) != ""{
                    cell.imgSignature.setImage(strImg: (self.isDeliveryType ? objDetails.dSignatureUrl : objDetails.rSignatureUrl))
                }
            }
            
            //SET VIEW
            cell.viewSignature.isHidden = true
            if  self.objOrderData.arrProduct.count - 1 <= section{
                cell.viewSignature.isHidden = false
            }

            // BUTTON ACTION
            cell.btnSignature.tag = section
            cell.btnSignature.addTarget(self, action: #selector(self.btnSignatureClicked(_:)), for: .touchUpInside)

            return cell
        }
        
        return UIView()
    }

    
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if self.isLoading{
            return 0
        }
        else{
            
            let objDetails = self.arrOtherData[section]
            
            var noteHeight: CGFloat = 0
            let strNote = self.isDeliveryType ?  objDetails.dNote :  objDetails.rNote
            if strNote != "" {
                let lblTitle = UILabel(frame: CGRect.zero)
                lblTitle.frame.size.width = (tableView.frame.size.width - 50)
                lblTitle.numberOfLines = 0
                lblTitle.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: strNote, numberOfLines: 0)
                lblTitle.sizeToFit()
                noteHeight = lblTitle.frame.height + 60
            }
            
            if (self.isDeliveryType ? objDetails.dSignature : objDetails.rSignature) != UIImage() || (self.isDeliveryType ? objDetails.dSignatureUrl : objDetails.rSignatureUrl) != ""{
                return manageWidth(size: 350 + noteHeight)
            }
            else{
                return manageWidth(size: 150 + noteHeight)
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

  
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isLoading{
            return 2
        }
        else{
            if self.objOrderData.arrProduct.count != 0{
                return self.objOrderData.arrProduct[section].arrQuestions.count
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
        if let cell = tableView.dequeueReusableCell(withIdentifier: "CheckListUpdateCell") as? CheckListUpdateCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.isHidden = true
            cell.viewBalance.isHidden = true
            cell.viewValue.isHidden = true
            cell.viewCustomerOwes.isHidden = true
            cell.viewDeliveredMain.isHidden = true
            cell.viewReturnedMain.isHidden = true
            cell.viewAdditional.isHidden = true
            cell.viewHourlyFee.isHidden = true
            cell.viewLine.alpha = 0

            if isLoading {
                cell.viewLine.isHidden = true
                self.machinePlaceholderMarker.register(cell.getAnimableSubviews())
                self.machinePlaceholderMarker.startAnimation()
                return cell
            }
            
            if self.objOrderData.arrProduct.count == 0 {
                return cell
            }
            
            if self.objOrderData.arrProduct[indexPath.section].arrQuestions.count == 0 {
                return cell
            }
            
            let  objDetails = self.objOrderData.arrProduct[indexPath.section].arrQuestions[indexPath.row]
                        

            cell.lblTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: self.isDeliveryType ? objDetails.question_delivery_text ?? "" : objDetails.question_return_text ?? "")
            cell.lblTitleDelivered.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "")

            if objDetails.type == "text"{
                cell.lblTitleDelivered.text = "\(objDetails.startHours)"
            }
            else if objDetails.type == "fuel"{
                cell.lblTitleDelivered.text = getFlueName(strId: self.isDeliveryType == false ? objDetails.selectFuleReturn ?? "" : objDetails.selectFuleDelivery ?? "")
            }
            else{
                if objDetails.deliverAnswer != nil{
                    cell.lblTitleDelivered.text = objDetails.deliverAnswer.answer_delivery_text ?? ""
                }
            }
            
            
            
            
            
            
            if objDetails.type == "text" && self.isDeliveryType == false{
                if objDetails.total_cost != 0.0{
                    cell.lblTitle.text = str.strMachineHours
                    cell.viewDeliveredMain.isHidden = false
                    cell.viewReturnedMain.isHidden = false
                    cell.viewValue.isHidden = false
                    cell.viewBalance.isHidden = false
                    cell.viewCustomerOwes.isHidden = false
                    cell.viewAdditional.isHidden = false
                    cell.viewHourlyFee.isHidden = false
                    cell.lblTitleDelivered.text = ""

                    cell.lblDelivered.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: objDetails.question_delivery_text ?? "")
                    cell.lblValue.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strAllocatedHourse)
                    cell.lblReturned.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: objDetails.question_return_text ?? "")

                    cell.lblBalance.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strTotalHourse)
                    cell.lblAdditional.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strAdditionalHourse)
                    cell.lblHourlyFee.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strHourseFee)

                    cell.lblCustomerOwes.configureLable(textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strTotalCharge)

                    
                    
                    cell.lblDeliverySelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "\(objDetails.startHours)")
                    cell.lblReturnSelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "\(objDetails.endHours)")
                    cell.txtValue.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(self.objOrderData.arrProduct[indexPath.section].allocated_hours ?? 0.0)", placeholder: "0.0")
                    cell.txtBalance.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(objDetails.total)", placeholder: "0.0")
                    cell.txtAdditional.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(objDetails.additinal ?? 0)", placeholder: "0.0")
                    cell.txtHourlyFee.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(objDetails.hour_rate)", placeholder: "0.0")
                    cell.txtCustomerOwes.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\((String(format: "%.2f", objDetails.total_cost)) )", placeholder: "0.0")

                }
            }
            else if objDetails.type == "fuel" && self.isDeliveryType == false{
                let price = self.getPrice(strFuleType: objDetails.fuleType ?? "", isDef: objDetails.isDEF ?? "")
                var totalPrice  : Float = 0.0
                if objDetails.isDEF == "Yes"{
                    totalPrice = price * (Float(objDetails.def_tank_capacity ?? "") ?? 0)
                }
                else if objDetails.fuleType == "diesel"{
                    totalPrice = price * (Float(objDetails.diesel_tank_capacity ?? "") ?? 0)
                }
                else if objDetails.fuleType == "gas"{
                    totalPrice = price * (Float(objDetails.gas_tank_capacity ?? "") ?? 0)
                }
                
                let totalCharge = FuelCalulateTotalCharge(total: totalPrice, dSelect: Float(objDetails.selectFuleDelivery ?? "") ?? 0, rSelect: Float(objDetails.selectFuleReturn ?? "") ?? 0)
                          
                if totalCharge != 0{
                    cell.viewDeliveredMain.isHidden = false
                    cell.viewReturnedMain.isHidden = false
                    cell.lblTitleDelivered.text = ""
                    cell.viewCustomerOwes.isHidden = false
                    
                    cell.lblDelivered.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strDelivered)
                    cell.lblReturned.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strReturned)
                    
                    cell.lblDeliverySelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: getFlueName(strId: objDetails.selectFuleDelivery ?? ""))
                    cell.lblReturnSelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: getFlueName(strId: objDetails.selectFuleReturn ?? ""))
                    
                    
                    
                        
                    cell.lblCustomerOwes.configureLable(textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strCustomerOwes)
                    cell.txtCustomerOwes.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(String(format: "%.2f", totalCharge))", placeholder: "0.0")

                }

            }
            else{
                if objDetails.deliverAnswer != nil && objDetails.returnAnswer != nil{
                    if objDetails.deliverAnswer.unique_id != objDetails.returnAnswer.unique_id{
                        cell.viewDeliveredMain.isHidden = false
                        cell.viewReturnedMain.isHidden = false
                        cell.lblTitleDelivered.text = ""
                        cell.viewCustomerOwes.isHidden = false
                        
                        cell.lblDelivered.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strDelivered)
                        cell.lblReturned.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strReturned)
                        
                        cell.lblDeliverySelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: objDetails.deliverAnswer.answer_delivery_text ?? "")
                        cell.lblReturnSelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: objDetails.returnAnswer.answer_return_text ?? "")
                        
                        
                        let totalCharge = Float(objDetails.deliverAnswer.delivery_amt) + Float(objDetails.returnAnswer.return_amt)
                        
                        cell.lblCustomerOwes.configureLable(textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strCustomerOwes)
                        cell.txtCustomerOwes.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(String(format: "%.2f", totalCharge))", placeholder: "0.0")
//                        cell.viewCustomerOwesLine.backgroundColor = .redText
                    }
                }
            }
            
            
            
            
            if objDetails.deliverAnswer != nil{
                cell.lblDeliverySelect.text = objDetails.deliverAnswer.answer_delivery_text ?? ""
            }
            if objDetails.returnAnswer != nil{
                cell.lblReturnSelect.text = objDetails.returnAnswer.answer_return_text ?? ""
            }

            
            
    
            return cell
        }

        return UITableViewCell()
        
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}
    
    
}





//MARK: - KEYBORD DELEGATE
extension CheckListUpdateViewController {
    
    @objc func keyboardWillShow(notification: NSNotification) {
       let keyboardHeight = (notification.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height
       print(keyboardHeight)

    }

    @objc func keyboardWillHide(notification: NSNotification) {
       let keyboardHeight = (notification.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height
       print(keyboardHeight)

        //RELOAD TABLE
        self.CalculatTotalCharge()
        self.tblView.reloadData()

    }
}

