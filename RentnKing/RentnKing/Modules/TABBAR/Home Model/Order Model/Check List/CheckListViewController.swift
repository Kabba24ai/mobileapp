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

struct FuleTypes {
    let id: Int
    let name: String
}

let arrFlueDelivery : [FuleTypes] = [FuleTypes(id: 10, name: "Prepaid"),
                                     FuleTypes(id: 9, name: "Full"),
                                     FuleTypes(id: 8, name: "7/8"),
                                     FuleTypes(id: 7, name: "3/4"),
                                     FuleTypes(id: 6, name: "5/8"),
                                     FuleTypes(id: 5, name: "1/2"),
                                     FuleTypes(id: 4, name: "3/8"),
                                     FuleTypes(id: 3, name: "1/4"),
                                     FuleTypes(id: 2, name: "1/8"),
                                     FuleTypes(id: 1, name: "Empty")]


func getFlueName(strId : String) -> String{
    let MenuID = arrFlueDelivery.map{$0.id}
    if let index = MenuID.firstIndex(of: Int(strId) ?? 0){
        return arrFlueDelivery[index].name
    }
    return "Select"
}

func FuelCalulateTotalCharge(total : Float, dSelect : Float , rSelect : Float) -> Float{
    if dSelect != 99 || rSelect != 99{
        let value = (dSelect - rSelect)
        if value > 0{
            return (total/8) * value
        }
        else{
            return 0
        }
    }
   
    return 0
}



class CheckListViewController: UIViewController, UIGestureRecognizerDelegate, UIPickerViewDataSource, UIPickerViewDelegate{
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
//    var arrProductList : [ProductModel] = []
    var arrEmployesList : [EmployeesModel] = []
    var arrOtherData : [NoteModel] = []
    var arrMachineList : [MachineModel] = []
    var arrAllMachineList : [MachineModel] = []
    var arrCategoryList : [CategoryModel] = []
    var arrStoreList :[StoreModel] = []
    var sortedMachineList : [String : [MachineModel]] = [:]
    var arrPriceList : [PriceListModel] = []
    
//    var objCheckListPrice : CheckListPriceModel!
    
    
    var selectIndex : Int = -1
    var strOrderID : String = ""
    var strOrderUniqueId : String = ""
    var strProductID : String = ""

    var strTotalCharge : Float = 0.0
    var isDeliveryType : Bool = false
    var selectEmployessID : String = ""
    var deliveryIndex : Int = 0
    var isOrderDetailsView : Bool = false
    var isUpdateMachineId : Bool = false
    var isUpdateMachineIdFirstTime : Bool = true

    var strSelectCategoty : String = ""
    var strSelectEquipment : String = ""

    
    //PICKER VIEW
    private let hiddenField = UITextField(frame: .zero)     // host for inputView/accessory
    private let picker = UIPickerView()
    private var selectedIndex: Int = 1
//    let data = [
//          ("Section: Cutting", ["Brush cutting"]),
//          ("Section: Boom", ["Boom - Skid", "Boom-2"])
//      ]
    
    
   
    
    var pickerData: [String] = []
    var selectProductIndex : Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        setupCutomeKeyboard()
        // Do any additional setup after loading the view.
        setupKeyboard(false)
        self.setupPickerHost()
        
        
        //CALL API
        self.viewSubmit.isHidden = true
        //TEMP COMMENT//self.getEmployeesListAPI(CatrgoryParameater: CatrgoryParameater())
        //TEMP COMMENT//self.getEquipmentListAPI(EquipmentParameater: EquipmentParameater())
//        self.getCategorys(CatrgoryParameater: CatrgoryParameater())
        //TEMP COMMENT//self.getStoreAddress()
//
        //KEYBOARD METHOD
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification , object:nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification , object:nil)

        
        //GET CATEGORY DATA
        getCategoryList { arr_data in
            self.arrCategoryList = arr_data
        }
        
        //CALL API FOR EMPLOYEE LIST AND CHEKC LOCAL
        //GET EMPLOYEE LIST DATA
        getEmployeeList { arr_data in
            self.arrEmployesList = arr_data
            self.getLocalOrderDetailData()
           //self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(unique_id: self.strOrderUniqueId, product_id: self.strProductID))
        }
        
        //CALL API FOR Equipment LIST AND CHEKC LOCAL
        //GET Equipment LIST DATA
        getEquipmentList { arr_data in
            self.arrMachineList = arr_data
            self.arrAllMachineList = self.arrMachineList

            //SET DATA
            self.setPickerData()
        }
        
        
        //GET STORE LIST DATA FROM LOCAL
        getStoreList { arr_data in
            self.arrStoreList = arr_data.map { obj in
                var updatedObj = obj
                updatedObj.fullAddress = [
                    obj.address,
                    obj.city,
                    obj.state,
                    obj.zip_code
                ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                return updatedObj
            }
        }
        
        //GET PRICE LIST
        getPriceList { arr_data in
            self.arrPriceList = arr_data
        }
    }
    
    // MARK: - GET LOCAL ORDER DETAILS DATA
    func getLocalOrderDetailData() {
        
        // Always show existing local data immediately
        if let localData = self.getOrderDetailData() {
            self.objOrderData = localData

            var arrProduct : [ProductModel] = []
            for obj in self.objOrderData.arrProduct{
                if obj.objProductData?.product_type != "Retail"{
                    arrProduct.append(obj)
                }
            }
            
            //UPDATE DATA
            self.objOrderData.arrProduct = arrProduct
            self.setupStaticData()
            self.setTheView()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.fetchOrdersDetails(OrdersDetailsParameater: OrdersDetailsParameater(unique_id: self.strOrderUniqueId, product_id: self.strProductID))
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

    }
    
    func stopLoading(){
        indicatorHide()
        self.CalculatTotalCharge()
        self.tblView.reloadData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.machinePlaceholderMarker.remove()
        }
    }
    
    private func setupPickerHost() {
     
        // Picker
        picker.dataSource = self
        picker.delegate = self
        
        // Hidden text field as first responder host
        hiddenField.translatesAutoresizingMaskIntoConstraints = false
        hiddenField.backgroundColor = .white
        hiddenField.isHidden = true
        view.addSubview(hiddenField)
        
        // Input view & accessory (toolbar)
        hiddenField.inputView = picker
        hiddenField.inputAccessoryView = makeToolbar()
    }
    
    private func makeToolbar() -> UIToolbar {
        let bar = UIToolbar()
        bar.sizeToFit()

        let cancel = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        let flex   = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let title  = UIBarButtonItem(title: "Select Equipment ID", style: .plain, target: nil, action: nil)
        title.isEnabled = false
        let done   = UIBarButtonItem(title: "Select", style: .done, target: self, action: #selector(doneTapped))

        bar.items = [cancel, flex, title, flex, done]
        return bar
    }

    // MARK: - Actions
    func openPicker() {
        // Preselect current value when reopening
        picker.selectRow(selectedIndex, inComponent: 0, animated: false)
        hiddenField.becomeFirstResponder()  // shows picker + toolbar
    }

    @objc private func cancelTapped() {
        hiddenField.resignFirstResponder()  // dismiss without applying
    }

    @objc private func doneTapped() {
        selectedIndex = picker.selectedRow(inComponent: 0)
        hiddenField.resignFirstResponder()  // apply & dismiss

        if self.pickerData.count != 0{
            let input = self.pickerData[selectedIndex]
            if let code = input.components(separatedBy: "||").last?.trimmingCharacters(in: .whitespaces) {
                print(code) // ATMQ-1234
                
                let MenuID = self.arrMachineList.map{$0.equipment_id}
                if let index = MenuID.firstIndex(of: code){
                    
                    let objMachineList = self.arrMachineList[index]
                    if objMachineList.status == "Damaged" || objMachineList.status == "Maint. Hold"{
//                        {Maint. Hold}
                        let alert = UIAlertController(title: Application.appName, message: "This item is currently marked as \(objMachineList.status ?? ""), do you want to automatically change the status to Available and assign to this Order?", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                            self.cancelTapped()
                            self.callCheckListAPI(index: index)
                            
                        }))
                        alert.addAction(UIAlertAction(title: str.no, style: .default,handler: { (Action) in
                            self.cancelTapped()
                        }))
                        self.present(alert, animated: true)
                    }
                    else if objMachineList.status == "Available"{
                        self.callCheckListAPI(index: index)
                    }
                    else if objMachineList.status == "Rented"{
                        let alert = UIAlertController(title: Application.appName, message: "This item is currently Rented. so can't be assigned to this Order", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: str.ok, style: .default,handler: { (Action) in
                            self.selectedIndex = 1
                            self.cancelTapped()
                        }))
                        self.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    func callCheckListAPI(index : Int){
        self.cancelTapped()

        var objProductDetails = self.objOrderData.arrProduct[self.selectProductIndex]
        objProductDetails.objMachine = self.arrMachineList[index]
        
//        self.powerSourceType = self.arrMachineList[index].powerSourceType
//        self.hasDEF = self.arrMachineList[index].hasDEF
        
        //UPDATE ARRAY
        self.objOrderData.arrProduct.remove(at: self.selectProductIndex)
        self.objOrderData.arrProduct.insert(objProductDetails, at: self.selectProductIndex)

    
        //UPDATE DATA
        let obj = self.arrOtherData[self.selectProductIndex]
        obj.machine_id = self.arrMachineList[index].id ?? 0
        self.arrOtherData.remove(at: self.selectProductIndex)
        self.arrOtherData.insert(obj, at: self.selectProductIndex)
        
        //CALL API
        self.getCheckListPriceAPI(CheckListParameater: CheckListParameater(equipment_unique_id: self.arrMachineList[index].unique_id ?? "", type: self.isDeliveryType ? "delivery" : "return", order_product_unique_id: self.objOrderData.arrProduct[self.selectProductIndex].unique_id ?? ""), index: self.selectProductIndex)
    }
    
    // MARK: - UIPickerViewDataSource/Delegate
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 44 }
    
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return pickerData.count
    }
    
    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        let text = pickerData[row]
        
        // If it's a "section" row
        if text.hasPrefix("Section:") {
            return NSAttributedString(string: text.replacingOccurrences(of: "Section:", with: ""), attributes: [
                .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Light, size: 8),
                .foregroundColor: UIColor.gray.withAlphaComponent(0.5)
                
            ])
        }
        
        return NSAttributedString(string: text, attributes: [
            .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 14),
            .foregroundColor: UIColor.background
        ])
    }
    
    // Prevent selecting section rows
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerData[row].hasPrefix("Section:") {
            // Jump to next selectable row
            pickerView.selectRow(row + 1, inComponent: component, animated: true)
        }
    }
}



//MARK: - BUTTON ACTION
extension CheckListViewController{
    
    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        let errors = checkQuestions()
        if self.checkMachineData() == false{
            return
        }
        else if let first = errors.first {
            scrollToCell(indexPath: first, isError: true)
            return
        }
        else if self.checkOtherData() == false{
            return
        }
        else{
            
            //MOVE CHECKLIST
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListUpdateViewController") as? CheckListUpdateViewController{
                newViewController.arrPriceList = self.arrPriceList
                newViewController.isDeliveryType = self.isDeliveryType
                newViewController.objOrderData = self.objOrderData
                newViewController.arrOtherData = self.arrOtherData
                newViewController.selectIndex = self.selectIndex
                newViewController.strOrderID = self.strOrderID
                newViewController.strOrderUniqueId = self.strOrderUniqueId
                newViewController.isOrderDetailsView = self.isOrderDetailsView
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
            
        }
    }
    
//    func checkQustions() -> Bool{
//        for (section,obj) in self.objOrderData.arrProduct.enumerated(){
//            for (row,objQuestion) in obj.arrQuestions.enumerated(){
//                if self.isDeliveryType{
//                    if objQuestion.deliverAnswer == nil{
//                        self.scrollToCell(indexPath: IndexPath(row: row, column: section), isError: true)
//                        return false
//                    }
//                }
//                else{
//                    if objQuestion.returnAnswer == nil{
//                        self.scrollToCell(indexPath: IndexPath(row: row, column: section), isError: true)
//                        return false
//                    }
//                }
//            }
//        }
//        
//        return true
//    }
    
    func checkQuestions() -> [IndexPath] {
        var errorIndexPaths: [IndexPath] = []
        
        for (section, obj) in self.objOrderData.arrProduct.enumerated() {
            for (row, objQuestion) in obj.arrQuestions.enumerated() {
                let indexPath = IndexPath(row: row, section: section)
                
                if isDeliveryType {
                    if objQuestion.type == "text" {
                        if objQuestion.startHours == 0.0 {
                            errorIndexPaths.append(indexPath)
                        }
                    }
                    else if objQuestion.type == "fuel"{
                        if objQuestion.selectFuleDelivery == ""{
                            errorIndexPaths.append(indexPath)
                        }
                    }
                    else{
                        if objQuestion.deliverAnswer == nil{
                            errorIndexPaths.append(indexPath)
                        }
                    }
                   
                } else {
                    if objQuestion.type == "text" {
                        if objQuestion.endHours == 0.0 {
                            errorIndexPaths.append(indexPath)
                        }
                    }
                    else if objQuestion.type == "fuel"{
                        if objQuestion.selectFuleReturn == ""{
                            errorIndexPaths.append(indexPath)
                        }
                    }
                    else{
                        if objQuestion.returnAnswer == nil{
                            errorIndexPaths.append(indexPath)
                        }
                    }
                }
            }
        }
        
        return errorIndexPaths
    }
    
    func scrollToCell(indexPath : IndexPath, isError : Bool){
        print(indexPath)
        
        if isError{
            self.tblView.scrollSafely(to: indexPath)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let cell = self.tblView.cellForRow(at: indexPath) as? CheckListCell {
                cell.viewDeliveredMain.backgroundColor = .clear
                cell.viewReturnedMain.backgroundColor = .clear
                if self.isDeliveryType{
                    cell.viewDeliveredMain.viewBorderCorneRadius(borderColour: isError ? .red : .clear)
                }
                else{
                    cell.viewReturnedMain.viewBorderCorneRadius(borderColour: isError ? .red : .clear)
                }
            }
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
                    var objdata = objProduct.arrQuestions[index]

                    let obj = self.arrOtherData[section]
                    if textField.tag == 100{
                        obj.startHours = Float(newString) ?? 0.0
                        objdata.startHours = Float(newString) ?? 0.0
                    }
                    else{
                        obj.endHours = Float(newString) ?? 0.0
                        objdata.endHours = Float(newString) ?? 0.0
                    }

                    self.arrOtherData.remove(at: section)
                    self.arrOtherData.insert(obj, at: section)

                    //UPDATE
                    objProduct.arrQuestions.remove(at: index)
                    objProduct.arrQuestions.insert(objdata, at: index)
                    
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
            var objProduct = self.objOrderData.arrProduct[i]
            
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
                    self.strTotalCharge =  self.strTotalCharge + (Float(additionslHours) * Float(objQuestion.hour_rate))
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
                    
                }else if objQuestion.deliverAnswer != nil && objQuestion.returnAnswer != nil{
                    
                    let strPrice = Float(objQuestion.returnAnswer.return_amt) - Float(objQuestion.deliverAnswer.delivery_amt)
                    if strPrice > 0{
                        self.strTotalCharge = self.strTotalCharge + strPrice
                    }
                }
            }
            
            
            //SET TOTAL CHARGE
            //                self.strTotalCharge = self.strTotalCharge + (objQuestion?.objQuestion?.customerOwes ?? 0.0)
            
        }
        
        //RELOAD TABLE
        self.lblTotalCharge.text = "\(Application.currency)\(String(format: "%.2f", self.strTotalCharge))"
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
    

    
//    func calculateHours(index : Int){
//        var objdata = self.objOrderData.arrMachineHours[index]
//
//        //SET TOTLA HOURS
//        let hours = Float(objdata.end ?? 0) - Float(objdata.start ?? 0)
//        let totalHours = Int(hours.rounded(.up))
//        objdata.total = 0
//        if totalHours > 0{
//            //SET TOTAL HOURS
//            objdata.total = Float(totalHours)
//        }
//        
//        
//        //SET ADDITION HOURS
//        var additionslHours = totalHours - (objdata.allocated ?? 0)
//        objdata.additinal = 0
//        if additionslHours > 0{
//            //SET TOTAL HOURS
//            objdata.additinal = Int(Float(additionslHours))
//        }
//        else{
//            additionslHours = 0
//        }
//        
//        
//        //SET TOTAL CHARGE
//        let totalCharge = Float(additionslHours) * Float(objdata.price ?? 0)
//        objdata.total_cost = totalCharge
//
//        
//        //UPDATE ARRAY
//        self.objOrderData.arrMachineHours.remove(at: index)
//        self.objOrderData.arrMachineHours.insert(objdata, at: index)
//            
//        
//        //RELAOD ABLE
////        self.tblView.reloadData()
//    }
}

//MARK: - MANAGE API CALL AND LOCAL DATABASE MANGE

extension CheckListViewController {
    
    // MARK: - Get Employee List
    func getEmployeeList(completion: @escaping ([EmployeesModel]) -> Void) {
        if !getEmployeeData().isEmpty {
            completion(getEmployeeData())
        }
        
        CallAPIforGetEmployeesList(CatrgoryParameater: CatrgoryParameater()) { isSaved in
            if isSaved {
                completion(self.getEmployeeData())
            } else {
                completion([])
            }
        }
    }
    
    // MARK: - Get Equipment List
    func getEquipmentList(completion: @escaping ([MachineModel]) -> Void) {
        if !getEquipmentData().isEmpty {
            completion(getEquipmentData())
        }
        
        CallAPIforGetEquipmentList(EquipmentParameater: EquipmentParameater()) { isSaved in
            if isSaved {
                completion(self.getEquipmentData())
            } else {
                completion([])
            }
        }
    }
    
    // MARK: - Get Equipment List
    func getStoreList(completion: @escaping ([StoreModel]) -> Void) {
        if !getStoreListData().isEmpty {
            completion(getStoreListData())
        }
        
        CallAPIforStoreList { isSaved in
            if isSaved {
                completion(self.getStoreListData())
            } else {
                completion([])
            }
        }
    }
    
        
    // MARK: - Get Local Data
    func getEmployeeData() -> [EmployeesModel] {
        if let arr = SDKUserDefault.getMappableArray(EmployeesModel.self, for: kFileStorageName.kEmployesList.rawValue) {
            return arr
        }
        return []
    }
    
    func getEquipmentData() -> [MachineModel] {
        if let arr = SDKUserDefault.getMappableArray(MachineModel.self, for: kFileStorageName.kEquipmentList.rawValue) {
            return arr
        }
        return []
    }
    
    func getStoreListData() -> [StoreModel] {
        if let arr = SDKUserDefault.getMappableArray(StoreModel.self, for: kFileStorageName.kStoreList.rawValue) {
            return arr
        }
        return []
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


}

class CheckListCell : UITableViewCell{

    @IBOutlet weak var lblTitle: UILabel!
    @IBOutlet weak var lblTitleReturn: UILabel!
//
    @IBOutlet weak var txtDelivered: UITextField!
//    
    @IBOutlet weak var txtReturned: UITextField!
    @IBOutlet weak var viewDeliveredMain: UIView!
    @IBOutlet weak var viewReturnedMain: UIView!

//    @IBOutlet weak var lblDelivered: UILabel!
    @IBOutlet weak var viewDeliverySelect: UIView!
    @IBOutlet weak var lblDeliverySelect: UILabel!
    @IBOutlet weak var imgDeliverySelect: UIImageView!
    @IBOutlet weak var btnDeliverySelect: UIButton!
    
//    @IBOutlet weak var lblReturned: UILabel!
    @IBOutlet weak var viewReturnSelect: UIView!
    @IBOutlet weak var lblReturnSelect: UILabel!
    @IBOutlet weak var imgReturnSelect: UIImageView!
    @IBOutlet weak var btnReturnSelect: UIButton!

    
    


    @IBOutlet weak var viewLine: UIView!

    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            lblTitle,
            lblTitleReturn,
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
            
            cell.lblTitleCategoryId.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "Category ID")
            cell.lblTitleMachineId.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: self.isDeliveryType ? "Equipment ID *" : "Equipment ID")
            
            cell.lblDelivered.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: str.strDelivered)
            cell.lblReturned.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: str.strReturned)

            cell.lblCategoryId.configureLable(textAlignment: .center, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")
            cell.lblMachineId.configureLable(textAlignment: .center, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")
            imgColor(imgColor: cell.imgCategoryId, colorHex: .primary)
            imgColor(imgColor: cell.imgMachineId, colorHex: .primary)

            if objProductDetails.objCategory != nil{
                cell.lblCategoryId.text = objProductDetails.objCategory?.name ?? ""
            }
            
          
            
            cell.viewCategoryId.backgroundColor = .clear
            cell.viewCategoryId.viewBorderCorneRadius(borderColour: .secondaryText)
            
            cell.viewMachineId.backgroundColor = .clear
            cell.viewMachineId.viewBorderCorneRadius(borderColour: .secondaryText)

         
            cell.lblDelivered.isEnabled = !self.isDeliveryType
            cell.lblReturned.isEnabled = !self.isDeliveryType

            cell.viewCategoryId.isHidden = false
            self.isUpdateMachineId = false
            cell.lblTitleCategoryId.isHidden = false
            cell.lblTitleMachineId.isHidden = false
            cell.imgMachineId.isHidden = false
            if objProductDetails.objMachine != nil{
                if objProductDetails.objMachine?.unique_id != ""{
                    self.isUpdateMachineId = true
                    cell.lblMachineId.text = "\(objProductDetails.objMachine?.equipment_name ?? "")    ||    \(objProductDetails.objMachine?.equipment_id ?? "")"

                    cell.lblTitleCategoryId.isHidden = true
                    cell.viewCategoryId.isHidden = true
                    cell.imgMachineId.isHidden = true
                }
            }
          
            // BUTTON ACTION
            cell.btnCategoryId.tag = section
            cell.btnCategoryId.addTarget(self, action: #selector(self.btnCategoryIdClicked(_:)), for: .touchUpInside)

            cell.btnMachineId.tag = section
            cell.btnMachineId.addTarget(self, action: #selector(self.btnMachineIdClicked(_:)), for: .touchUpInside)

            return cell
        }
        
        return UIView()
    }
    
  
    
    func getMachineName(id : Int) -> String{
        let MenuID = self.arrMachineList.map{$0.id}
        if let index = MenuID.firstIndex(of: id){
            return self.arrMachineList[index].equipment_id ?? ""
        }
        return "Select"
    }
    
    @objc func btnCategoryIdClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        self.isUpdateMachineIdFirstTime = false
        if self.arrCategoryList.count == 0 {
            return
        }
        
        actionPicker(sender, strTitle: "Select Category ID", arrData: self.arrCategoryList.compactMap { $0.name}, selectValue: self.strSelectCategoty) { index, selectValue in
            
            self.strSelectCategoty = selectValue
            var objProductDetails = self.objOrderData.arrProduct[sender.tag]
            objProductDetails.objCategory = self.arrCategoryList[index]
            
            //UPDATE ARRAY
            self.objOrderData.arrProduct.remove(at: sender.tag)
            self.objOrderData.arrProduct.insert(objProductDetails, at: sender.tag)

            self.arrMachineList = []
            if selectValue == "All"{
                self.arrMachineList = self.arrAllMachineList
            }
            else{
                self.arrMachineList = self.arrAllMachineList
                    .filter { $0.category_id == self.arrCategoryList[index].id }
            }
            
            //RELAD
            self.setPickerData()
            self.tblView.reloadData()
        }
    }
    
    func setPickerData(){
        //SHORTING ARRAY
        self.pickerData = []
        self.sortedMachineList = Dictionary(grouping: self.arrMachineList, by: { $0.status ?? "" })
        let sortedGroups = self.sortedMachineList.sorted { $0.key < $1.key }
        for (section, items) in sortedGroups {
            pickerData.append("Section: \(section)")
            var arrData : [String] = []
            for obj in items{
                arrData.append("\(obj.equipment_name ?? "")    ||    \(obj.equipment_id ?? "")")
            }
            pickerData.append(contentsOf: arrData)
        }
    }
    @objc func btnMachineIdClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        self.isUpdateMachineIdFirstTime = false
        
        if self.arrMachineList.count == 0{
            return
        }
        
        if self.pickerData.count == 0{
            return
        }
      
     
        print(pickerData)
        self.openPicker()
        
        
//        actionPicker(sender, strTitle: "Select Equipment ID", arrData: arrData, selectValue: self.getMachineName(id: self.arrOtherData[sender.tag].machine_id)) { index, selectValue in
//
//            var objProductDetails = self.objOrderData.arrProduct[sender.tag]
//            objProductDetails.objMachine = self.arrMachineList[index]
//            
//            //UPDATE ARRAY
//            self.objOrderData.arrProduct.remove(at: sender.tag)
//            self.objOrderData.arrProduct.insert(objProductDetails, at: sender.tag)
//
//        
//            //UPDATE DATA
//            let obj = self.arrOtherData[sender.tag]
//            obj.machine_id = self.arrMachineList[index].id ?? 0
//            self.arrOtherData.remove(at: sender.tag)
//            self.arrOtherData.insert(obj, at: sender.tag)
//            
//            //CALL API
//            self.getCheckListPriceAPI(CheckListParameater: CheckListParameater(equipment_unique_id: self.arrMachineList[index].unique_id ?? "", type: self.isDeliveryType ? "delivery" : "return", order_product_unique_id: self.objOrderData.arrProduct[sender.tag].unique_id ?? ""), index: sender.tag)
//        }
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

            cell.btnSelctEmployee.tag = section
            cell.btnSelctEmployee.addTarget(self, action: #selector(self.btnSelectEmployessClicked(_:)), for: .touchUpInside)

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
        
        actionPicker(sender, strTitle: "Select Store", arrData: self.arrStoreList.compactMap { $0.name}, selectValue: self.arrOtherData[sender.tag].rStore) { index, selectValue in
           
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
        if let cell = tableView.dequeueReusableCell(withIdentifier: "CheckListCell") as? CheckListCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.isHidden = true
            cell.viewDeliveredMain.backgroundColor = .clear
            cell.viewReturnedMain.backgroundColor = .clear
            cell.viewDeliveredMain.viewBorderCorneRadius(borderColour: .clear)
            cell.viewReturnedMain.viewBorderCorneRadius(borderColour: .clear)

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
                        
            cell.imgDeliverySelect.isHidden = !self.isDeliveryType
            cell.lblTitle.configureLable(textColor: self.isDeliveryType ? .primary : .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: objDetails.question_delivery_text ?? "")
            cell.lblTitleReturn.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: objDetails.question_return_text ?? "")
            cell.lblTitleReturn.isHidden = true
            if objDetails.type == "text" && self.isDeliveryType == false{
                cell.lblTitleReturn.isHidden = false
            }
            else if objDetails.question_delivery_text ?? "" != objDetails.question_return_text ?? "" && self.isDeliveryType == false{
                cell.lblTitleReturn.isHidden = false
            }

            cell.lblDeliverySelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")
            cell.lblReturnSelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")

            
            //SET BUTTON
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let rightButton = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(rightButtonTapped))
            toolbar.items = [flexibleSpace, rightButton]

            cell.txtReturned.inputAccessoryView = toolbar
            cell.txtDelivered.inputAccessoryView = toolbar


            cell.txtDelivered.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: objDetails.startHours == 0.0 ? "" : "\(objDetails.startHours)" , placeholder: "0.0")
            cell.txtDelivered.accessibilityValue = "\(indexPath.section)"
            cell.txtDelivered.tag = 100
            cell.txtDelivered.accessibilityLanguage = "\(indexPath.row)"
            cell.txtDelivered.delegate = self
            cell.txtDelivered.isUserInteractionEnabled = self.isDeliveryType
//            cell.viewDeliveredMain.isHidden = !self.isDeliveryType
            
            cell.txtReturned.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: objDetails.endHours == 0.0 ? "" : "\(objDetails.endHours)", placeholder: "0.0")
            cell.txtReturned.accessibilityValue = "\(indexPath.section)"
            cell.txtReturned.tag = 101
            cell.txtReturned.accessibilityLanguage = "\(indexPath.row)"
            cell.txtReturned.delegate = self
            cell.txtReturned.isUserInteractionEnabled = !self.isDeliveryType
            cell.viewReturnedMain.isHidden = self.isDeliveryType
            
            if objDetails.type == "fuel"{
                cell.lblDeliverySelect.text = getFlueName(strId: objDetails.selectFuleDelivery ?? "")
                cell.lblReturnSelect.text = getFlueName(strId: objDetails.selectFuleReturn ?? "")
            }
            else{
                if objDetails.deliverAnswer != nil{
                    cell.lblDeliverySelect.text = objDetails.deliverAnswer.answer_delivery_text ?? ""
                }
                
                if objDetails.returnAnswer != nil{
                    cell.lblReturnSelect.text = objDetails.returnAnswer.answer_return_text ?? ""
                }
            }
            
           
            //SET TYPE
            imgColor(imgColor: cell.imgDeliverySelect, colorHex: .primary)
            imgColor(imgColor: cell.imgReturnSelect, colorHex: .primary)
            cell.viewDeliverySelect.isHidden = true
            cell.viewReturnSelect.isHidden = true
            cell.txtDelivered.isHidden = false
            cell.txtReturned.isHidden = false

            if objDetails.type != "text" {
                cell.viewDeliverySelect.isHidden = false
                cell.viewReturnSelect.isHidden = false
                cell.txtDelivered.isHidden = true
                cell.txtReturned.isHidden = true
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
        
        if self.objOrderData.arrProduct[section].arrQuestions.count == 0 {
            return
        }
        
        let  objDetails = self.objOrderData.arrProduct[section].arrQuestions[sender.tag]
                 
        if objDetails.type == "fuel"{
            actionPicker(sender, strTitle: "", arrData: arrFlueDelivery.compactMap { $0.name}, selectValue: "") { index, selectValue in
                
                
                //SET IN OTHER DATA
                let objDate = self.arrOtherData[section]
                objDate.selectFuleDelivery = "\(arrFlueDelivery[index].id)"

                //UPDATE DATA
                self.arrOtherData.remove(at: section)
                self.arrOtherData.insert(objDate, at: section)

                
                var objProduct = self.objOrderData.arrProduct[section]
                var objdata = objProduct.arrQuestions[sender.tag]
                objdata.selectFuleDelivery = "\(arrFlueDelivery[index].id)"
                
        
                
                //UPDATE
                objProduct.arrQuestions.remove(at: sender.tag)
                objProduct.arrQuestions.insert(objdata, at: sender.tag)
                
                //UPDATE ARRAY
                self.objOrderData.arrProduct.remove(at: section)
                self.objOrderData.arrProduct.insert(objProduct, at: section)
                
                //RELOAD TABLE
                self.tblView.reloadData()
   
            }
        }
        else{
            if  objDetails.arrAnswer.count != 0{
                actionPicker(sender, strTitle: "", arrData: objDetails.arrAnswer.compactMap { $0.answer_delivery_text}, selectValue: "") { index, selectValue in
                    
                    
                    var objProduct = self.objOrderData.arrProduct[section]
                    var objdata = objProduct.arrQuestions[sender.tag]
                    objdata.deliverAnswer = objdata.arrAnswer[index]

                    
                    //UPDATE
                    objProduct.arrQuestions.remove(at: sender.tag)
                    objProduct.arrQuestions.insert(objdata, at: sender.tag)
                    
                    //UPDATE ARRAY
                    self.objOrderData.arrProduct.remove(at: section)
                    self.objOrderData.arrProduct.insert(objProduct, at: section)
                    
                    //RELOAD TABLE
                    self.tblView.reloadData()
                    

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
        
        if self.objOrderData.arrProduct[section].arrQuestions.count == 0 {
            return
        }
        
        let  objDetails = self.objOrderData.arrProduct[section].arrQuestions[sender.tag]
                 
        if objDetails.type == "fuel"{
            let arrFuleReturn : [FuleTypes] = arrFlueDelivery.reversed()
            actionPicker(sender, strTitle: "", arrData: arrFuleReturn.compactMap { $0.name}, selectValue: "") { index, selectValue in
                
                //SET IN OTHER DATA
                let objDate = self.arrOtherData[section]
                objDate.selectFuleReturn = "\(arrFuleReturn[index].id)"

                //UPDATE DATA
                self.arrOtherData.remove(at: section)
                self.arrOtherData.insert(objDate, at: section)

                
                var objProduct = self.objOrderData.arrProduct[section]
                var objdata = objProduct.arrQuestions[sender.tag]
                objdata.selectFuleReturn = "\(arrFuleReturn[index].id)"
                
        
                
                //UPDATE
                objProduct.arrQuestions.remove(at: sender.tag)
                objProduct.arrQuestions.insert(objdata, at: sender.tag)
                
                //UPDATE ARRAY
                self.objOrderData.arrProduct.remove(at: section)
                self.objOrderData.arrProduct.insert(objProduct, at: section)
                
                //RELOAD TABLE
                self.tblView.reloadData()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                    self.CalculatTotalCharge()
                }
            }
        }
        else{
            
            if  objDetails.arrAnswer.count != 0{
                actionPicker(sender, strTitle: "Select", arrData: objDetails.arrAnswer.compactMap { $0.answer_return_text}, selectValue: "") { index, selectValue in

                    
                    var objProduct = self.objOrderData.arrProduct[section]
                    var objdata = objProduct.arrQuestions[sender.tag]
                    objdata.returnAnswer = objdata.arrAnswer[index]


                    
                    //UPDATE
                    objProduct.arrQuestions.remove(at: sender.tag)
                    objProduct.arrQuestions.insert(objdata, at: sender.tag)
                    
                    //UPDATE ARRAY
                    self.objOrderData.arrProduct.remove(at: section)
                    self.objOrderData.arrProduct.insert(objProduct, at: section)
                    
                    //RELOAD TABLE
                    self.tblView.reloadData()
                    
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                        self.CalculatTotalCharge()
                    }
                }
            }
        }

    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
      
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



extension UITableView {
    func scrollSafely(to indexPath: IndexPath,
                      position: UITableView.ScrollPosition = .middle,
                      animated: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Validate section/row
            guard indexPath.section >= 0,
                  indexPath.section < self.numberOfSections,
                  indexPath.row >= 0,
                  indexPath.row < self.numberOfRows(inSection: indexPath.section) else { return }

            // Make sure layout/contentSize are ready
            self.layoutIfNeeded()
            self.scrollToRow(at: indexPath, at: position, animated: animated)
        }
    }
}




//MARK: - LOCAL DATABASE MANAGE
extension CheckListViewController{
    
    // MARK: - Fetch Orders (Main Controller)
    func fetchOrdersDetails(OrdersDetailsParameater : OrdersDetailsParameater) {

        let params = OrdersDetailsParameater

        callAPIforGetOrderDetails(OrdersDetailsParameater: params) { [weak self] isSaved in
            guard let self = self else { return }

            if isSaved {
                
                if let localData = self.getOrderDetailData() {
                    self.objOrderData = localData

                    var arrProduct : [ProductModel] = []
                    for obj in self.objOrderData.arrProduct{
                        if obj.objProductData?.product_type != "Retail"{
                            arrProduct.append(obj)
                        }
                    }
                    
                    //UPDATE DATA
                    self.objOrderData.arrProduct = arrProduct
                    self.setupStaticData()
                }
                
            }
            
            DispatchQueue.main.async {
                self.setTheView()
            }
        }
    }
    
    func setupStaticData() {
        
        let arrData = self.objOrderData.arrProduct
        self.objOrderData.arrProduct = []
        
        //GET PRODUCT DATA
        for obj in arrData{
            if obj.objProduct?.checklist_id != 0{
                self.objOrderData.arrProduct.append(obj)
            }
        }
        
        //SET SIGNATURE ARRAT
        self.self.arrOtherData = []
        for obj in self.objOrderData.arrProduct{
            self.arrOtherData.append(NoteModel(dNote: obj.delivery_note, rNote: obj.returned_note, rStoreId: "", rStore: "", dEmplayess: self.getEmployeesName(emp_id: obj.delivery_emp), dEmplayessId: "\(obj.delivery_emp)", rEmplayess: self.getEmployeesName(emp_id: obj.returned_emp), rEmplayessId: "\(obj.returned_emp)", dSignature: UIImage(), rSignature: UIImage(), productID: obj.id ?? 0, machine_id: obj.machine_id ?? 0, dSignatureUrl: obj.delivery_sign, rSignatureUrl: obj.return_sign, inTime: obj.inTime, outTime: obj.outTime, selectFuleDelivery:  obj.fuel_initial_reading , selectFuleReturn:  obj.fuel_final_reading ))
        }
        
        
        //CHECK EQUMPEMT
        for i in 0..<self.objOrderData.arrProduct.count{
            let objProduct = self.objOrderData.arrProduct[i]
            if objProduct.objMachine != nil{
                if objProduct.objMachine?.unique_id != ""{
                    self.getCheckListPriceAPI(CheckListParameater: CheckListParameater(equipment_unique_id: objProduct.objMachine?.unique_id ?? "", type: self.isDeliveryType ? "delivery" : "return", order_product_unique_id: objProduct.unique_id ?? ""), index: i)
                }
            }
        }
    }
        
    // MARK: - Get Local Data
    func getOrderDetailData() -> OrdersModel? {
        if let dic = SDKUserDefault.getMappableObject(OrdersModel.self, for: "\(kFileStorageName.kOrderDetailsData.rawValue)_\(self.strOrderUniqueId)_\(self.strProductID)") {
            return dic
        }
        return nil
    }
}
