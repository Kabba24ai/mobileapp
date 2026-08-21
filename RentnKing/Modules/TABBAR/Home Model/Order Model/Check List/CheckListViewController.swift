//
//  CheckListViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 10/09/24.
//

import UIKit
import ObjectMapper
import IQKeyboardManagerSwift
import IQKeyboardCore

protocol  CheckListDelegate : NSObject {
    func UpdateCheckListProduct(selectIndex: Int, arrUpdateCheckList : [NoteModel])
}

struct FuleTypes {
    let id: Int
    let name: String
}

let arrFlueDelivery : [FuleTypes] = [
    FuleTypes(id: 9, name: "Full"),
    FuleTypes(id: 8, name: "7/8"),
    FuleTypes(id: 7, name: "3/4"),
    FuleTypes(id: 6, name: "5/8"),
    FuleTypes(id: 5, name: "1/2"),
    FuleTypes(id: 4, name: "3/8"),
    FuleTypes(id: 3, name: "1/4"),
    FuleTypes(id: 2, name: "1/8"),
    FuleTypes(id: 1, name: "Empty")]

let arrCleaningDelivery : [FuleTypes] = [
    FuleTypes(id: 2, name: "Clean"),
    FuleTypes(id: 1, name: "Pre-Paid")
]

let arrCleaningReturn : [FuleTypes] = [
    FuleTypes(id: 5, name: "Extreme Clean"),
    FuleTypes(id: 4, name: "Moderate Clean"),
    FuleTypes(id: 3, name: "Std Clean"),
    FuleTypes(id: 2, name: "Clean"),
    FuleTypes(id: 1, name: "Pre-Paid")]


func getFlueName(strId : String) -> String{
    let MenuID = arrFlueDelivery.map{$0.id}
    if let index = MenuID.firstIndex(of: Int(strId) ?? 0){
        return arrFlueDelivery[index].name
    }
    return "Select"
}

func FuelCalulateTotalCharge(total : Float, dSelect : Float , rSelect : Float) -> Float{
    if dSelect != 10 && dSelect != 0 && rSelect != 0{
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

func getCleaning(strId : String, isReturn : Bool) -> String{
    
    let arrData : [FuleTypes] = isReturn ? arrCleaningReturn : arrCleaningDelivery
    let MenuID = arrData.map{$0.id}
    if let index = MenuID.firstIndex(of: Int(strId) ?? 0){
        return isReturn ? arrCleaningReturn[index].name : arrCleaningDelivery[index].name
    }
    return "Select"
}


class CheckListViewController: UIViewController, UIGestureRecognizerDelegate, UIPickerViewDataSource, UIPickerViewDelegate{
    weak var delegate: CheckListDelegate?
    
    @IBOutlet weak var tblView: UITableView!
    @IBOutlet weak var con_tableView: NSLayoutConstraint!
    @IBOutlet weak var con_Submit: NSLayoutConstraint!
    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!
    @IBOutlet weak var viewSave: UIView!
    @IBOutlet weak var lblSave: UILabel!

    @IBOutlet weak var con_SubmitBottom : NSLayoutConstraint!
    
    @IBOutlet weak var lblTotalChargeTitle: UILabel!
    @IBOutlet weak var lblTotalCharge: UILabel!
    @IBOutlet weak var lblCombine: UILabel!
    @IBOutlet weak var objCombineSwitch: UISwitch!
    @IBOutlet weak var con_table: NSLayoutConstraint!
    
    var isCombineChecklist: Bool = true
    
    
    
    //LOADING
    let machinePlaceholderMarker = Placeholder()
    
    //OTHER
    var isLoading : Bool = true
    var isMachineUpdate : Bool = false
    
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
    var arrProductSettingList : [PriceListModel] = []
    
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
    var isQueueLine : Bool = false
    var strSelectCategoty : String = ""
    var strSelectEquipment : String = ""
    var fromCheckListScreen: Bool = false
    
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
    /// Table scroll position captured when an equipment pick is applied, so the reloads that
    /// follow don't jump the screen up. Only set during the picker flow (nil for the keyboard).
    private var pickerSavedOffset: CGPoint?
    /// Guards one-time installation of the delivery-only "Save" (prepare) button.
    private var didInstallSaveButton = false

    override func viewDidLoad() {
        super.viewDidLoad()
        //        setupCutomeKeyboard()
        // Do any additional setup after loading the view.
        setupKeyboard(false)
        
        
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
        
        //GET Equipment LIST DATA
        getEquipmentList { arr_data in
            self.arrMachineList = arr_data
            self.arrAllMachineList = self.arrMachineList
            
            //SET DATA
            self.setPickerData()
            self.getLocalOrderDetailData()
            
        }
        
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
        
        getProductSettingList(completion: { arr_data in
            self.arrProductSettingList = arr_data
            
        })
    }
    
    // MARK: - GET LOCAL ORDER DETAILS DATA
    func getLocalOrderDetailData() {
        
        // Always show existing local data immediately
        //        if let localData = self.getOrderDetailData() {
        //            self.objOrderData = localData
        //            
        //            var arrProduct : [ProductModel] = []
        //            for obj in self.objOrderData.arrProduct{
        //                if obj.objProductData?.product_type != "Retail"{
        //                    arrProduct.append(obj)
        //                }
        //            }
        //            
        //            //UPDATE DATA
        //            self.objOrderData.arrProduct = arrProduct
        //            self.setupStaticData()
        //            self.setTheView()
        //        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(unique_id: self.strOrderUniqueId)) { dicData in
                if dicData != nil{
                    
                    self.objOrderData = dicData
                    self.isLoading = false
                    
                    var arrProduct : [ProductModel] = []
                    for obj in self.objOrderData.arrProduct{
                        if obj.objProductData?.product_type != "Retail"{
                            arrProduct.append(obj)
                        }
                    }
                    
//                    var arrProduct : [ProductModel] = []
//                    for obj in self.objOrderData.arrProduct{
//                        if obj.objProductData?.product_type != "Retail"{
//                            var product = obj
//                            // Feed the UI's arrQuestions from the delivery or return set based on the flow.
//                            product.arrQuestions = self.isDeliveryType ? product.arrQuestionsDelivery : product.arrQuestionsReturn
//                            arrProduct.append(product)
//                        }
//                    }
                    
                    //UPDATE DATA
                    self.objOrderData.arrProduct = arrProduct
                    self.setupStaticData()
                    self.setTheView()
                    self.prefillPendingCheckListIfNeeded()

                }
                
            }
        }
    }

    // MARK: - Prefill from pending draft
    private func prefillPendingCheckListIfNeeded() {
        guard isDeliveryType,
              let pending = getPendingCheckList(orderUniqueId: self.strOrderUniqueId, isDelivery: true) else { return }
        self.objOrderData.arrProduct = pending.order.arrProduct
        self.arrOtherData = pending.other
        self.viewSave.isHidden = !self.isQueueLine
        self.CalculatTotalCharge()
        self.tblView.reloadData()
    }
    
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        //SET PORTRAIT MODE
        AppUtility.PortraitMode()
        
        DispatchQueue.main.async {
            self.setupPickerHost()
        }
        
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
        
        
        indicatorHide()
        self.stopLoading()
        
        //SET SUBMIT
        self.viewSubmit.isHidden = false
        self.con_Submit.constant = manageWidth(size: 45.0)
        self.viewSubmit.backgroundColor = .secondaryTextView
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strNext)
        
        self.viewSave.isHidden = !isQueueLine
        self.viewSave.backgroundColor = .secondatyBtn
        self.lblSave.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Save")

        self.lblTotalChargeTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strTotalCheckList)
        self.lblTotalCharge.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "\(Application.currency)\(self.strTotalCharge)")
        
        self.lblTotalChargeTitle.isHidden = false
        self.lblTotalCharge.isHidden = false
        if self.isDeliveryType{
            self.lblTotalChargeTitle.isHidden = true
            self.lblTotalCharge.isHidden = true
        }
        
        
        //COMBINE SWITCH EVENT
        self.objCombineSwitch.removeTarget(self, action: #selector(combineSwitchChanged(_:)), for: .valueChanged)
        self.objCombineSwitch.addTarget(self, action: #selector(combineSwitchChanged(_:)), for: .valueChanged)
        
        
        self.lblCombine.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "Combine Delivery Checklist")
        self.objCombineSwitch.isHidden = false
        self.con_table.constant = 50
        self.isCombineChecklist = true
        if self.objOrderData.arrProduct.count == 1{
            self.lblCombine.text = ""
            self.objCombineSwitch.isHidden = true
            self.con_table.constant = 16
            self.isCombineChecklist = false
        }
    }
    
    @objc func combineSwitchChanged(_ sender: UISwitch) {
        self.isCombineChecklist = sender.isOn
        self.tblView.reloadData()
        
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
        picker.dataSource = self
        picker.delegate = self
        picker.backgroundColor = .white
        
        hiddenField.translatesAutoresizingMaskIntoConstraints = false
        hiddenField.isHidden = true
        // This field only hosts the equipment picker (inputView). It must NOT trigger
        // IQKeyboardManager's keyboard-avoidance, otherwise the view slides up when the
        // picker opens (most visible on the 2nd+ selection). Exclude it explicitly.
        hiddenField.iq.enableMode = .disabled
        view.addSubview(hiddenField)
        
        let pickerHeight: CGFloat = 260
        let headerHeight: CGFloat = 56
        
        let host = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: headerHeight + pickerHeight))
        host.backgroundColor = .black
        host.isOpaque = true
        
        let header = buildPickerHeader(title: "Select Equipment ID")
        header.frame.origin = .zero
        
        picker.frame = CGRect(x: 0, y: headerHeight, width: host.bounds.width, height: pickerHeight)
        picker.autoresizingMask = [.flexibleWidth]
        picker.backgroundColor = .white
        picker.roundCornersView(onTopLeft: true, topRight: true, bottomLeft: false, bottomRight: false, radius: 15)
        
        host.addSubview(header)
        host.addSubview(picker)
        
        hiddenField.inputAccessoryView = nil
        hiddenField.inputView = host
    }
    
    
    private func buildPickerHeader(title: String) -> UIView {
        let h: CGFloat = 56
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: h))
        header.backgroundColor = .clear
        header.autoresizingMask = [.flexibleWidth]
        
        let pillH: CGFloat = 38
        let y = (h - pillH) / 2
        
        // Left: Cancel pill
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cancel.backgroundColor = UIColor(white: 0.16, alpha: 1.0)
        cancel.layer.cornerRadius = pillH / 2
        cancel.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        cancel.frame = CGRect(x: 14, y: y, width: 88, height: pillH)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        
        // Right: Select pill
        let select = UIButton(type: .system)
        select.setTitle("Select", for: .normal)
        select.setTitleColor(.white, for: .normal)
        select.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        select.backgroundColor = UIColor.systemBlue
        select.layer.cornerRadius = pillH / 2
        select.contentEdgeInsets = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        select.frame = CGRect(x: header.bounds.width - 14 - 92, y: y, width: 92, height: pillH)
        select.autoresizingMask = [.flexibleLeftMargin]
        select.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        
        // Middle: Title pill (disabled look)
        let titleBtn = UIButton(type: .system)
        titleBtn.setTitle(title, for: .normal)
        titleBtn.setTitleColor(UIColor(white: 0.65, alpha: 1.0), for: .normal)
        titleBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        titleBtn.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        titleBtn.layer.cornerRadius = pillH / 2
        titleBtn.isUserInteractionEnabled = false
        
        let leftMaxX = cancel.frame.maxX + 12
        let rightMinX = select.frame.minX - 12
        let midW = max(0, rightMinX - leftMaxX)
        titleBtn.frame = CGRect(x: leftMaxX, y: y, width: midW, height: pillH)
        titleBtn.autoresizingMask = [.flexibleWidth]
        
        header.addSubview(cancel)
        header.addSubview(titleBtn)
        header.addSubview(select)
        
        return header
    }
    
    
    
    // MARK: - Actions
    func openPicker() {
        picker.reloadAllComponents()
        // Preselect current value when reopening (clamp so it can never be out of range).
        if !pickerData.isEmpty {
            let safeIndex = min(max(selectedIndex, 0), pickerData.count - 1)
            selectedIndex = safeIndex
            picker.selectRow(safeIndex, inComponent: 0, animated: false)
        }
        hiddenField.becomeFirstResponder()  // shows picker + toolbar
    }
    
    @objc private func cancelTapped() {
        hiddenField.resignFirstResponder()  // dismiss without applying
    }
    
    @objc private func doneTapped() {
        selectedIndex = picker.selectedRow(inComponent: 0)
        hiddenField.resignFirstResponder()  // apply & dismiss

        if self.pickerData.indices.contains(selectedIndex){
            let input = self.pickerData[selectedIndex]
            // Ignore section headers ("Section: Available") — they aren't selectable equipment.
            if input.hasPrefix("Section:") { return }
            if let code = input.components(separatedBy: "||").last?.trimmingCharacters(in: .whitespaces) {
                print(code) // ATMQ-1234
                
                let MenuID = self.arrMachineList.map{$0.equipment_id}
                if let index = MenuID.firstIndex(of: code){
                    
                    let objMachineList = self.arrMachineList[index]
                    if objMachineList.status == "Damaged" || objMachineList.status == "Maint. Hold"{
                        //                        {Maint. Hold}
                        let alert = UIAlertController(title: Application.appName, message: "This equipment is currently marked as \(objMachineList.status ?? ""). Do you want to automatically change its status to Available and assign it to this order?", preferredStyle: .alert)
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
                        let alert = UIAlertController(title: Application.appName, message: "This equipment is currently rented and is not available to be assigned to this order.", preferredStyle: .alert)
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

        // Applying a pick changes the rows below — remember the scroll position so the
        // follow-up reloads don't push the screen up.
        self.pickerSavedOffset = self.tblView.contentOffset

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
        
        self.setUpTheEqupmentData(objEquipment: self.arrMachineList[index], index: self.selectProductIndex)
        
        //        self.getCheckListPriceAPI(CheckListParameater: CheckListParameater(equipment_unique_id: self.arrMachineList[index].unique_id ?? "", type: self.isDeliveryType ? "delivery" : "return", order_product_unique_id: self.objOrderData.arrProduct[self.selectProductIndex].unique_id ?? ""), index: self.selectProductIndex)
    }
    
    // MARK: - UIPickerViewDataSource/Delegate
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 44 }
    
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return pickerData.count
    }
    
    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        guard row >= 0, row < pickerData.count else {
            return nil
        }
        
        let text = pickerData[row]
        
        // If it's a "section" row
        if text.hasPrefix("Section:") {
            return NSAttributedString(string: text.replacingOccurrences(of: "Section:", with: ""), attributes: [
                .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Light, size: 8),
                .foregroundColor:   UIColor.gray.withAlphaComponent(0.5)
                
            ])
        }
        
        return NSAttributedString(string: text, attributes: [
            .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 14),
            .foregroundColor: UIColor.background
        ])
    }
    
    // Prevent selecting section rows
    //    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
    //        
    //        if pickerData[row].hasPrefix("Section:") {
    //            // Jump to next selectable row
    //            pickerView.selectRow(row + 1, inComponent: component, animated: true)
    //        }
    //    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        
        guard pickerData.indices.contains(row) else { return }
        
        let selectedText = pickerData[row]
        
        // Prevent selecting section rows
        guard selectedText.hasPrefix("Section:") else { return }
        
        // Find next non-section row
        var nextRow = row + 1
        while pickerData.indices.contains(nextRow),
              pickerData[nextRow].hasPrefix("Section:") {
            nextRow += 1
        }
        
        // If found valid selectable row, move to it
        if pickerData.indices.contains(nextRow) {
            pickerView.selectRow(nextRow, inComponent: component, animated: true)
        } else {
            // Optional: move back to previous valid selectable row
            var previousRow = row - 1
            while pickerData.indices.contains(previousRow),
                  pickerData[previousRow].hasPrefix("Section:") {
                previousRow -= 1
            }
            
            if pickerData.indices.contains(previousRow) {
                pickerView.selectRow(previousRow, inComponent: component, animated: true)
            }
        }
    }
}



//MARK: - BUTTON ACTION
extension CheckListViewController{
    
    /// Removes products whose questions are all blank from both parallel arrays.
    /// If EVERY product is blank, the first product is kept.
    func removeBlankProducts(objOrderData: inout OrdersModel?, arrOtherData: inout [NoteModel]) {
        guard let products = objOrderData?.arrProduct, !products.isEmpty else { return }
        
        // Indexes of products whose questions are all blank
        var blankIndexes = products.indices.filter { checkQuestionsIsBlank(objProduct: products[$0]) }
        
        // If every product is blank, keep the first one
        if blankIndexes.count == products.count {
            blankIndexes.removeAll { $0 == 0 }
        }
        
        // Remove from the highest index down so earlier indexes stay valid
        for index in blankIndexes.sorted(by: >) {
            objOrderData?.arrProduct.remove(at: index)
            if index < arrOtherData.count {
                arrOtherData.remove(at: index)
            }
        }
    }
    


    /// Saves the current checklist as a PENDING draft (local only) — no signature, no upload, no
    /// completion — then opens Delivery Image/Video Upload. Stays put if the save fail
    /// s.
    @IBAction private func btnSavePendingClicked(_ sender: UIButton) {
        guard isDeliveryType else { return }
        self.view.endEditing(true)

        // SAME data prep + validation as Preview (btnSubmitClicked). Instead of moving to
        // CheckListUpdateViewController, we SAVE this prepared data as a PENDING draft (local only).
        var objTempOrderData = self.objOrderData
        var arrTempOtherData = self.arrOtherData
        for i in 0..<self.objOrderData.arrProduct.count{
            let obj = self.objOrderData.arrProduct[i]
            if obj.objMachine == nil{
                objTempOrderData?.arrProduct.remove(at: i)
                arrTempOtherData.remove(at: i)
            }
        }

        //CHECK IF NOT AVALIBEL THEN IT"S REMOVE — drop all-blank products (keep first if every product is blank)
        if self.isCombineChecklist == false{
            self.removeBlankProducts(objOrderData: &objTempOrderData, arrOtherData: &arrTempOtherData)
        }

        let errors = checkQuestions(objOrderData: objTempOrderData!)
        if self.checkMachineData(objOrderData: objTempOrderData!) == false{
            return
        }
        else if let first = errors.first {
            scrollToCell(indexPath: first, isError: true)
            return
        }
        else if self.checkOtherData(arrOtherData: arrTempOtherData) == false{
            return
        }
        else{
            // Persist the SAME prepared data that Preview would pass onward — as a PENDING draft.
            // No signature, no upload queue, no completion side effects. No forward navigation.
            let saved = savePendingCheckList(orderUniqueId: self.strOrderUniqueId, isDelivery: true,
                                             objOrderData: objTempOrderData, arrOtherData: arrTempOtherData)
            guard saved else {
                showAlertMessage(strMessage: "Could not save the checklist. Please try again.")
                return
            }
            self.openDeliveryMediaUpload()
        }
    }

    /// Opens the existing Delivery Image/Video Upload for this order. It needs an OrdersListModel;
    /// prefer the local cache, else build one from the loaded order data so we always navigate
    /// (and never crash its force-unwrapped datasource with a nil).
    private func openDeliveryMediaUpload() {
        var listModel = SDKUserDefault.getMappableObject(
            OrdersListModel.self,
            for: "\(kFileStorageName.kOrderDetailData.rawValue)_\(self.strOrderUniqueId)")
        if listModel == nil, let obj = self.objOrderData {
            var built = OrdersListModel(JSON: [:])
            built?.id = obj.id
            built?.arrProduct = obj.arrProduct   // same ProductModel type; drives the upload table
            listModel = built
        }
        guard let listModel = listModel else { return }

        let storyBoard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let vc = storyBoard.instantiateViewController(withIdentifier: "ImageUploadViewController") as? ImageUploadViewController {
            vc.isQueueLine = self.isQueueLine
            vc.strType = "delivery"
            vc.selectIndex = self.selectIndex
            vc.objOrderDetail = listModel
            vc.strOrderID = self.strOrderUniqueId
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }

    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        //CEHCK DATA
        var objTempOrderData = self.objOrderData
        var arrTempOtherData = self.arrOtherData
        for i in 0..<self.objOrderData.arrProduct.count{
            let obj = self.objOrderData.arrProduct[i]
            if obj.objMachine == nil{
                objTempOrderData?.arrProduct.remove(at: i)
                arrTempOtherData.remove(at: i)
            }
        }
        
        //CHECK IF NOT AVALIBEL THEN IT"S REMOVE — drop all-blank products (keep first if every product is blank)
        if self.isCombineChecklist == false{
            self.removeBlankProducts(objOrderData: &objTempOrderData, arrOtherData: &arrTempOtherData)
        }
        
        
        let errors = checkQuestions(objOrderData: objTempOrderData!)
        if self.checkMachineData(objOrderData: objTempOrderData!) == false{
            return
        }
        else if let first = errors.first {
            scrollToCell(indexPath: first, isError: true)
            return
        }
        else if self.checkOtherData(arrOtherData: arrTempOtherData) == false{
            return
        }
        else{
            
            //MOVE CHECKLIST
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListUpdateViewController") as? CheckListUpdateViewController{
                newViewController.arrPriceList = self.arrPriceList
                newViewController.arrProductSettingList = self.arrProductSettingList
                newViewController.isDeliveryType = self.isDeliveryType
                newViewController.objOrderData = objTempOrderData
                newViewController.arrOtherData = arrTempOtherData
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
    
    func checkQuestions(objOrderData : OrdersModel) -> [IndexPath] {
        var errorIndexPaths: [IndexPath] = []
        
        for (section, obj) in objOrderData.arrProduct.enumerated() {
            for (row, objQuestion) in obj.arrQuestions.enumerated() {
                let indexPath = IndexPath(row: row, section: section)
                
                if isDeliveryType {
                    if objQuestion.type == "text" {
                        if objQuestion.startHours == 0.0 {
                            errorIndexPaths.append(indexPath)
                        }
                    }
                    else if objQuestion.type == "cleaning" {
                        if objQuestion.startCleaning == "" {
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
                    else if objQuestion.type == "cleaning" {
                        if objQuestion.endCleaning == "" {
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
    
    func checkQuestionsIsBlank(objProduct : ProductModel?) -> Bool {
        // Returns true only when EVERY question is blank; false if any is filled.
        for objQuestion in objProduct?.arrQuestions ?? [] {
            var isBlank = false
            
            if isDeliveryType {
                if objQuestion.type == "text" {
                    isBlank = objQuestion.startHours == 0.0
                }
                else if objQuestion.type == "cleaning" {
                    isBlank = objQuestion.startCleaning == ""
                }
                else if objQuestion.type == "fuel"{
                    isBlank = objQuestion.selectFuleDelivery == ""
                }
                
                else{
                    isBlank = objQuestion.deliverAnswer == nil
                }
            } else {
                if objQuestion.type == "text" {
                    isBlank = objQuestion.endHours == 0.0
                }
                else if objQuestion.type == "cleaning" {
                    isBlank = objQuestion.endCleaning == ""
                }
                else if objQuestion.type == "fuel"{
                    isBlank = objQuestion.selectFuleReturn == ""
                }
                else{
                    isBlank = objQuestion.returnAnswer == nil
                }
            }
            
            // Any filled question → not all blank
            if !isBlank {
                return false
            }
        }
        
        // All questions were blank
        return true
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
    
    func checkMachineData(objOrderData : OrdersModel) -> Bool{
        for objData in objOrderData.arrProduct{
            if objData.objMachine == nil{
                showAlertMessage(strMessage: "Please select an equipment ID.")
                return false
            }
        }
        return true
    }
    
    func checkOtherData(arrOtherData : [NoteModel]) -> Bool{
        for obj in arrOtherData{
            if self.isDeliveryType{
                if obj.dEmplayessId == "" || obj.dEmplayessId == "0"{
                    showAlertMessage(strMessage: "Please select who delivered the equipment.")
                    return false
                }
                
                //                if obj.dSignature == UIImage() && obj.dSignatureUrl == ""{
                //                    showAlertMessage(strMessage: "Customer signature is required")
                //                    return false
                //                }
            }
            else{
                if obj.rEmplayessId == "" ||  obj.rEmplayessId == "0"{
                    showAlertMessage(strMessage: "Please select who returned the equipment.")
                    return false
                }
                else if obj.rStoreId == ""{
                    showAlertMessage(strMessage: "Please select a location.")
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
            let inverseSet = NSCharacterSet(charactersIn:"0123456789.").inverted
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
                    var hours = Float(objQuestion.endHours) - Float(objQuestion.startHours)
                    if objProduct.is_delivered == true && objQuestion.startHours == 0.0{
                        hours = 0
                    }
                    
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
                    
                    print(strTotalCharge)
                    //UPDATE
                    objProduct.arrQuestions.remove(at: index)
                    objProduct.arrQuestions.insert(objQuestion, at: index)
                    
                    //UPDATE ARRAY
                    self.objOrderData.arrProduct.remove(at: i)
                    self.objOrderData.arrProduct.insert(objProduct, at: i)
                    
                }
                else if objQuestion.type == "cleaning"{
                    //JIGAR
                    if objProduct.is_product_clean == true && objProduct.rental_prepaid_cleaning != 0 && Int(objQuestion.selectCleaningReturn ?? "") ?? 0 != 0{
                        
                        var price = self.getCleanigPrice(selectID: Int(objQuestion.selectCleaningReturn ?? "") ?? 0)
                        
                        let selectedOptions = objProduct.objProductData?.arrProductSelectdOptions ?? []
                        if selectedOptions.contains("rental_prepaid_cleaning") {
                            if Int(objQuestion.selectCleaningReturn ?? "") != 5{
                                price = 0
                            }
                        }
                        
                        let strCleaningCharge = (objProduct.rental_prepaid_cleaning ?? 0) * price
                        
                        self.strTotalCharge = self.strTotalCharge + strCleaningCharge
                        
                    }
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
                    
                    //SET FULE IS ADMIN OVERRIDE
                    var strDeliveredFule : String = getFlueName(strId: objQuestion.selectFuleDelivery ?? "")
                    if objProduct.is_delivered == true{
                        strDeliveredFule = strDeliveredFule == "Select" ? "Admin Override" : strDeliveredFule
                    }
                    
                    var strFuleTotalCharge = FuelCalulateTotalCharge(total: totalPrice, dSelect: strDeliveredFule == "Admin Override" ?  9 : Float(objQuestion.selectFuleDelivery ?? "") ?? 0, rSelect: Float(objQuestion.selectFuleReturn ?? "") ?? 0)
                    
                    //CHECK PREPAID FULE
                    let selectedOptions = objProduct.objProductData?.arrProductSelectdOptions ?? []
                    if selectedOptions.contains("rental_prepaid_fuel") {
                        // Option exists
                        strFuleTotalCharge = 0
                    }
                    
                    
                    
                    self.strTotalCharge = self.strTotalCharge + strFuleTotalCharge
                    
                    
                }
                
                else if objQuestion.deliverAnswer != nil && objQuestion.returnAnswer != nil{
                    
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
    
    
    func getCleanigPrice(selectID : Int) -> Float{
        let MenuID = self.arrProductSettingList.map{$0.setting_name}
        
        if selectID == 5{
            if let index = MenuID.firstIndex(of: "extreme_clean_req"){
                if let price = Float(self.arrProductSettingList[index].setting_value ?? "0") {
                    return price
                }
            }
        }
        else if selectID == 4{
            if let index = MenuID.firstIndex(of: "moderate_clean_req"){
                if let price = Float(self.arrProductSettingList[index].setting_value ?? "0") {
                    return price
                }
            }
        }
        else if selectID == 3{
            if let index = MenuID.firstIndex(of: "std_clean_req"){
                if let price = Float(self.arrProductSettingList[index].setting_value ?? "0") {
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


//MARK: -- UITABEL CELL --
class ProductCheckListCell : UITableViewCell{
    
    @IBOutlet weak var con_imgHeight: NSLayoutConstraint!
    @IBOutlet weak var imgProduct: UIImageView!
    
    @IBOutlet weak var lblProduct: UILabel!
    @IBOutlet weak var lblDateDelivery: UILabel!
    @IBOutlet weak var lblDateReturn: UILabel!
    
    @IBOutlet weak var lblDelivered: UILabel!
    @IBOutlet weak var lblReturned: UILabel!
    
    
    @IBOutlet weak var viewCategoryMain: UIView!
    @IBOutlet weak var lblTitleCategoryId: UILabel!
    @IBOutlet weak var lblCategoryId: UILabel!
    @IBOutlet weak var viewCategoryId: UIView!
    @IBOutlet weak var btnCategoryId: UIButton!
    @IBOutlet weak var imgCategoryId: UIImageView!
    
    
    @IBOutlet weak var viewMachineMain: UIView!
    @IBOutlet weak var lblTitleMachineId: UILabel!
    @IBOutlet weak var lblMachineId: UILabel!
    @IBOutlet weak var btnMachineUpdate: UIButton!
    @IBOutlet weak var viewMachineId: UIView!
    @IBOutlet weak var btnMachineId: UIButton!
    @IBOutlet weak var imgMachineId: UIImageView!
    
    @IBOutlet weak var lblMachineChange: UILabel!
    @IBOutlet weak var btnMachineChange: UIButton!

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
    
    @IBOutlet weak var viewReturnEmployee: UIView!
    @IBOutlet weak var lblReturnEmployee: UILabel!
    @IBOutlet weak var txtSelctReturnEmployee: UITextField!
    
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
    @IBOutlet weak var viewTitleReturn: UIView!
    
    @IBOutlet weak var viewPrepaid: UIView!
    @IBOutlet weak var lblPrepaid: UILabel!
    @IBOutlet weak var viewPrepaidReturn: UIView!
    @IBOutlet weak var lblPrepaidReturn: UILabel!
    
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
            if self.objOrderData != nil{
                return self.objOrderData.arrProduct.count
            }
            else{
                return 0
            }
            
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
            cell.lblMachineChange.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 12.0, text: "Change")
            cell.lblTitleMachineId.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: self.isDeliveryType ? "Equipment ID *" : "Equipment ID")
            cell.btnMachineUpdate.configureLable(bgColour: .clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "")
            
            
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
            cell.btnMachineUpdate.isHidden = true
            cell.viewMachineMain.isHidden = false
            cell.viewCategoryMain.isHidden = false
            cell.lblMachineChange.isHidden = true
            cell.btnMachineChange.isHidden = true

            if objProductDetails.objMachine != nil && self.isMachineUpdate == false{
                if objProductDetails.objMachine?.unique_id != ""{
                    self.isUpdateMachineId = true
                    cell.viewCategoryMain.isHidden = true
                    cell.lblMachineId.text = "\(objProductDetails.objMachine?.equipment_name ?? "")    ||    \(objProductDetails.objMachine?.equipment_id ?? "")"
                    
                    cell.lblMachineChange.isHidden = false
                    cell.btnMachineChange.isHidden = false
                    cell.btnMachineUpdate.isHidden = false
                    cell.lblTitleCategoryId.isHidden = true
                    cell.viewCategoryId.isHidden = true
                    cell.imgMachineId.isHidden = true
                }
            }
            
            
            //SET MACHINE NAME
            if objProductDetails.objMachine != nil{
                if objProductDetails.objMachine?.unique_id != ""{
                    cell.lblMachineId.text = "\(objProductDetails.objMachine?.equipment_name ?? "")    ||    \(objProductDetails.objMachine?.equipment_id ?? "")"
                }
            }
            
            
            if self.isDeliveryType == false{
                cell.btnMachineUpdate.isHidden = true
            }
            
            // BUTTON ACTION
            cell.btnMachineChange.tag = section
            cell.btnMachineChange.addTarget(self, action: #selector(self.btnMachineUpdateClicked(_:)), for: .touchUpInside)

            cell.btnMachineUpdate.tag = section
            cell.btnMachineUpdate.addTarget(self, action: #selector(self.btnMachineUpdateClicked(_:)), for: .touchUpInside)
            
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
    
    
    @objc func btnMachineUpdateClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        self.isMachineUpdate = true
        
        //UPDATE
        if let obj = self.objOrderData.arrProduct[sender.tag].objCategory{
            self.updateEqupmentData(selectValue: "", categoryId: obj.id ?? 0)
        }
        
        //RELOAD TABLE
        self.tblView.reloadData()
    }
    
    @objc func btnCategoryIdClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        self.isUpdateMachineIdFirstTime = false
        if self.arrCategoryList.count == 0 {
            return
        }

        guard sender.tag < self.objOrderData.arrProduct.count else { return }

        // Preselect THIS row's own category (each product tracks its own), not a shared value.
        let currentCategory = self.objOrderData.arrProduct[sender.tag].objCategory?.name ?? self.strSelectCategoty

        actionPicker(sender, strTitle: "Select Category ID", arrData: self.arrCategoryList.compactMap { $0.name}, selectValue: currentCategory) { index, selectValue in

            self.selectedIndex = 1
            self.strSelectCategoty = selectValue
            var objProductDetails = self.objOrderData.arrProduct[sender.tag]
            objProductDetails.objCategory = self.arrCategoryList[index]
            objProductDetails.objMachine = nil
            objProductDetails.arrQuestions = []
            
            //UPDATE ARRAY
            self.objOrderData.arrProduct.remove(at: sender.tag)
            self.objOrderData.arrProduct.insert(objProductDetails, at: sender.tag)
            
            //UPDATE
            self.updateEqupmentData(selectValue: selectValue, categoryId: self.arrCategoryList[index].id ?? 0)
          
        }
    }
    
    /// Returns the equipment scoped to a category. `nil` category id (or "All") → the full list.
    func machineList(forCategoryId categoryId: Int?, selectValue: String = "") -> [MachineModel] {
        guard let categoryId = categoryId, selectValue != "All" else {
            return self.arrAllMachineList
        }
        return self.arrAllMachineList.filter { $0.category_id == categoryId }
    }

    func updateEqupmentData(selectValue: String, categoryId : Int){
        indicatorShow()

        self.arrMachineList = self.machineList(forCategoryId: categoryId, selectValue: selectValue)

        //RELAD
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            indicatorHide()
            self.setPickerData()
            self.tblView.reloadData()
        })

    }
    
    func setPickerData(){
        //SHORTING ARRAY
        self.pickerData.removeAll()
        
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
        if self.isDeliveryType == false{
            return
        }

        self.isUpdateMachineIdFirstTime = false

        guard sender.tag < self.objOrderData.arrProduct.count else { return }

        // Equipment list still loading — nothing to show yet.
        if self.arrAllMachineList.isEmpty {
            return
        }

        // Scope the equipment to THIS row's selected category so the picker shows the right units.
        // Passing the category name lets "All" fall through to the full list.
        let objCategory = self.objOrderData.arrProduct[sender.tag].objCategory
        self.arrMachineList = self.machineList(forCategoryId: objCategory?.id, selectValue: objCategory?.name ?? "")
        self.setPickerData()

        if self.arrMachineList.isEmpty || self.pickerData.isEmpty {
            showAlertMessage(strMessage: "No equipment found for the selected category.")
            return
        }

        // Land on the first real row (skip the section header). Reset when switching products
        // or when the previous selection no longer fits the freshly-built list.
        if sender.tag != self.selectProductIndex || self.selectedIndex >= self.pickerData.count {
            self.selectedIndex = self.pickerData.firstIndex(where: { !$0.hasPrefix("Section:") }) ?? 0
        }
        self.selectProductIndex = sender.tag
        self.openPicker()
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if self.isLoading{
            return 0
        }
        else{
            
            let  objProductDetails = self.objOrderData.arrProduct[section]
            if objProductDetails.objMachine == nil || self.isMachineUpdate == true{
                return manageWidth(size: 320)
            }
            else{
                return manageWidth(size: 250)
            }
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
            
            
            cell.viewEmployee.isHidden = false
            if self.isCombineChecklist{
                // When combined, show the employee view only on the last product; hide on the others.
                let lastSection = (self.objOrderData?.arrProduct.count ?? 0) - 1
                cell.viewEmployee.isHidden = (section != lastSection)
            }
            
            // Hide the employee title label when the selector is showing → only the name is shown.
            cell.lblEmployee.isHidden = cell.viewEmployee.isHidden
            
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
            var size: CGFloat = self.isDeliveryType ? (checkDeviceiPad() ? 360 : 310)
            : (checkDeviceiPad() ? 430 : 380)
            
            // When combined, the employee view is hidden on all but the last product → reduce height by that row.
            if self.isCombineChecklist {
                let lastSection = (self.objOrderData?.arrProduct.count ?? 0) - 1
                if section != lastSection {
                    size -= 70   // employee row height (matches the location-row delta)
                }
            }
            
            return manageWidth(size: size)
        }
    }
    
    
    
    @objc func btnSelectEmployessClicked(_ sender: UIButton) {
        // self.view.endEditing(true)
        if self.fromCheckListScreen == true{
            return
        }
        
        if self.arrEmployesList.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: "Select Employee", arrData: self.arrEmployesList.compactMap { $0.name}, selectValue: self.isDeliveryType ? self.arrOtherData[sender.tag].dEmplayess : self.arrOtherData[sender.tag].rEmplayess) { index, selectValue in
            
            let empId = "\(self.arrEmployesList[index].id ?? 0)"
            
            //UPDATE DATA — when combined, apply the same employee to every product
            let targets = self.isCombineChecklist ? self.arrOtherData : [self.arrOtherData[sender.tag]]
            for obj in targets {
                if self.isDeliveryType{
                    obj.dEmplayess = selectValue
                    obj.dEmplayessId = empId
                }
                else{
                    obj.rEmplayess = selectValue
                    obj.rEmplayessId = empId
                }
            }
            
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
            
            //UPDATE DATA — when combined, apply the same employee to every product
            let targets = self.isCombineChecklist ? self.arrOtherData : [self.arrOtherData[sender.tag]]
            for obj in targets {
                obj.rStore = selectValue
                obj.rStoreId = "\(self.arrStoreList[index].id ?? 0)"
            }
            
            //RELAD
            self.tblView.reloadData()
            
            
            //            //UPDATE DATA
            //            let obj = self.arrOtherData[sender.tag]
            //
            //            self.arrOtherData.remove(at: sender.tag)
            //            self.arrOtherData.insert(obj, at: sender.tag)
            //            
            //            //RELAD
            //            self.tblView.reloadData()
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
            cell.viewPrepaid.isHidden = true
            cell.viewPrepaidReturn.isHidden = true
            cell.lblPrepaid.configureLable(textAlignment: .right, textColor: .green, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: "Prepaid")
            cell.lblPrepaid.configureLable(textAlignment: .right, textColor: .green, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: "Prepaid")
            
            if isLoading {
                cell.viewLine.isHidden = true
                self.machinePlaceholderMarker.register(cell.getAnimableSubviews())
                self.machinePlaceholderMarker.startAnimation()
                return cell
            }
            
            if self.objOrderData.arrProduct.count == 0 {
                return cell
            }
            
            if self.objOrderData.arrProduct[indexPath.section].arrQuestions.count == 0 || self.objOrderData.arrProduct[indexPath.section].arrQuestions.count <= indexPath.row  {
                return cell
            }
            
            let  objDetails = self.objOrderData.arrProduct[indexPath.section].arrQuestions[indexPath.row]
            
            cell.imgDeliverySelect.isHidden = !self.isDeliveryType
            cell.lblTitle.configureLable(textColor: self.isDeliveryType ? .primary : .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: objDetails.question_delivery_text ?? "")
            cell.lblTitleReturn.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: objDetails.question_return_text ?? "")
            cell.lblTitleReturn.isHidden = true
            cell.viewTitleReturn.isHidden = true
            if objDetails.type == "text" && self.isDeliveryType == false{
                cell.lblTitleReturn.isHidden = false
                cell.viewTitleReturn.isHidden = false
            }
            else if objDetails.question_delivery_text ?? "" != objDetails.question_return_text ?? "" && self.isDeliveryType == false{
                cell.lblTitleReturn.isHidden = false
                cell.viewTitleReturn.isHidden = true
            }
            
            cell.lblDeliverySelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")
            cell.lblReturnSelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")
            
            var strDeliveredHours : String = objDetails.startHours == 0.0 ? "" : "\(objDetails.startHours)"
            var strDeliveredFule : String = getFlueName(strId: objDetails.selectFuleDelivery ?? "")
            var strDeliveredCleaning : String = getCleaning(strId: objDetails.selectCleaningDelivery ?? "", isReturn: false)
            if self.objOrderData.arrProduct[indexPath.section].is_delivered == true{
                strDeliveredHours = objDetails.startHours == 0.0 ? "Admin Override" : "\(objDetails.startHours)"
                strDeliveredFule = strDeliveredFule == "Select" ? "Admin Override" : strDeliveredFule
                strDeliveredCleaning = strDeliveredCleaning == "Select" ? "Admin Override" : strDeliveredCleaning
                cell.lblDeliverySelect.text = "Admin Override"
            }
            
            if self.objOrderData.arrProduct[indexPath.section].is_returned == true{
                cell.lblReturnSelect.text = "Admin Override"
            }
            
            
            //SET BUTTON
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let rightButton = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(rightButtonTapped))
            toolbar.items = [flexibleSpace, rightButton]
            
            cell.txtReturned.inputAccessoryView = toolbar
            cell.txtDelivered.inputAccessoryView = toolbar
            
            
            cell.txtDelivered.configureText(textAlignment: .center, keyboardTye: .decimalPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: strDeliveredHours , placeholder: "0.0")
            cell.txtDelivered.accessibilityValue = "\(indexPath.section)"
            cell.txtDelivered.tag = 100
            cell.txtDelivered.accessibilityLanguage = "\(indexPath.row)"
            cell.txtDelivered.delegate = self
            cell.txtDelivered.isUserInteractionEnabled = self.isDeliveryType
            //            cell.viewDeliveredMain.isHidden = !self.isDeliveryType
            
            cell.txtReturned.configureText(textAlignment: .center, keyboardTye: .decimalPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: objDetails.endHours == 0.0 ? "" : "\(objDetails.endHours)", placeholder: "0.0")
            cell.txtReturned.accessibilityValue = "\(indexPath.section)"
            cell.txtReturned.tag = 101
            cell.txtReturned.accessibilityLanguage = "\(indexPath.row)"
            cell.txtReturned.delegate = self
            cell.txtReturned.isUserInteractionEnabled = !self.isDeliveryType
            cell.viewReturnedMain.isHidden = self.isDeliveryType
            
            if objDetails.type == "fuel"{
                cell.lblDeliverySelect.text = strDeliveredFule
                cell.lblReturnSelect.text = getFlueName(strId: objDetails.selectFuleReturn ?? "")
                
                let selectedOptions = self.objOrderData
                    .arrProduct[indexPath.section]
                    .objProductData?
                    .arrProductSelectdOptions ?? []
                
                cell.viewPrepaid.isHidden = true
                cell.viewPrepaidReturn.isHidden = true
                if selectedOptions.contains("rental_prepaid_fuel") {
                    // Option exists
                    if self.isDeliveryType{
                        cell.viewPrepaid.isHidden = false
                        cell.viewPrepaidReturn.isHidden = true
                    }
                    else{
                        cell.viewPrepaid.isHidden = false
                        cell.viewPrepaidReturn.isHidden = false
                    }
                }
            }
            else if objDetails.type == "cleaning"{
                cell.lblDeliverySelect.text = strDeliveredCleaning
                cell.lblReturnSelect.text = getCleaning(strId: objDetails.selectCleaningReturn ?? "", isReturn: true)
                
                let selectedOptions = self.objOrderData
                    .arrProduct[indexPath.section]
                    .objProductData?
                    .arrProductSelectdOptions ?? []
                
                cell.viewPrepaid.isHidden = true
                cell.viewPrepaidReturn.isHidden = true
                if selectedOptions.contains("rental_prepaid_cleaning") {
                    // Option exists
                    if self.isDeliveryType{
                        cell.viewPrepaid.isHidden = false
                        cell.viewPrepaidReturn.isHidden = true
                    }
                    else{
                        cell.viewPrepaid.isHidden = false
                        cell.viewPrepaidReturn.isHidden = false
                    }
                }
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
        else if objDetails.type == "cleaning"{
            actionPicker(sender, strTitle: "", arrData: arrCleaningDelivery.compactMap { $0.name}, selectValue: "") { index, selectValue in
                
                
                //SET IN OTHER DATA
                let objDate = self.arrOtherData[section]
                objDate.selectCleaningDelivery = "\(arrCleaningDelivery[index].id)"
                
                //UPDATE DATA
                self.arrOtherData.remove(at: section)
                self.arrOtherData.insert(objDate, at: section)
                
                
                var objProduct = self.objOrderData.arrProduct[section]
                var objdata = objProduct.arrQuestions[sender.tag]
                objdata.startCleaning = "\(arrCleaningDelivery[index].name)"
                objdata.selectCleaningDelivery = "\(arrCleaningDelivery[index].id)"
                
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
        if objDetails.type == "cleaning"{
            actionPicker(sender, strTitle: "", arrData: arrCleaningReturn.compactMap { $0.name}, selectValue: "") { index, selectValue in
                
                //SET IN OTHER DATA
                let objDate = self.arrOtherData[section]
                objDate.selectCleaningReturn = "\(arrCleaningReturn[index].id)"
                
                //UPDATE DATA
                self.arrOtherData.remove(at: section)
                self.arrOtherData.insert(objDate, at: section)
                
                
                var objProduct = self.objOrderData.arrProduct[section]
                var objdata = objProduct.arrQuestions[sender.tag]
                objdata.endCleaning = "\(arrCleaningReturn[index].name)"
                objdata.selectCleaningReturn = "\(arrCleaningReturn[index].id)"
                
                
                
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
        let keyboardHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height ?? 0
        print(keyboardHeight)
        //        self.con_SubmitBottom.constant = (keyboardHeight - GetBottomSafeAreaHeight()) + 16
        self.con_SubmitBottom.constant = 16.0
        
    }
    
    @objc func keyboardWillHide(notification: NSNotification) {
        let keyboardHeight = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height ?? 0
        print(keyboardHeight)
        self.con_SubmitBottom.constant = 16.0

        //RELOAD TABLE
        self.CalculatTotalCharge()
        self.tblView.reloadData()

        // If this hide is from applying an equipment pick, keep the table where it was.
        if let off = self.pickerSavedOffset {
            self.tblView.layoutIfNeeded()
            self.tblView.setContentOffset(off, animated: false)
        }
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
        for i in 0..<self.objOrderData.arrProduct.count{
            let  obj = self.objOrderData.arrProduct[i]
            
            self.arrOtherData.append(NoteModel(startHours: 0.0, endHours: 0.0, dNote: obj.delivery_note, rNote: obj.returned_note, rStoreId: "", rStore: "", dEmplayess: self.getEmployeesName(emp_id: obj.delivery_emp), dEmplayessId: "\(obj.delivery_emp)", rEmplayess: self.getEmployeesName(emp_id: obj.returned_emp), rEmplayessId: "\(obj.returned_emp)", dSignature: UIImage(), rSignature: UIImage(), productID: obj.id ?? 0, machine_id: obj.machine_id ?? 0, dSignatureUrl: obj.delivery_sign, rSignatureUrl: obj.return_sign, inTime: obj.inTime, outTime: obj.outTime, selectFuleDelivery:  obj.fuel_initial_reading , selectFuleReturn:  obj.fuel_final_reading , selectCleaningDelivery: "\(obj.startCleaning ?? 0)", selectCleaningReturn: "\(obj.endCleaning ?? 0)"))
            
            
            if obj.objMachine != nil{
                self.setUpTheEqupmentData(objEquipment: obj.objMachine, index: i)

                
//                var objEquipment : MachineModel?
//                
//                //GET EQUPMENT DATA
//                if self.arrMachineList.count != 0{
//                    let MenuID = self.arrMachineList.compactMap { $0.unique_id }
//                    if let index = MenuID.firstIndex(of: obj.objMachine?.unique_id ?? ""){
//                        objEquipment = self.arrMachineList[index]
//                        
//                        //SET DATA
//                        if objEquipment != nil{
//                            self.setUpTheEqupmentData(objEquipment: objEquipment, index: i)
//                        }
//                    }
//                }
            }
        }
    }
    
    
    func setUpTheEqupmentData(objEquipment : MachineModel?, index : Int){
        var objProduct = self.objOrderData.arrProduct[index]
//        objProduct.arrQuestions = objEquipment?.arrAnswerCheckList ?? []
        
        // Build the optional rows independently, then prepend them in a FIXED priority order:
        // text → cleaning → fuel (whichever of them are available), followed by the base questions.
        
        //TEXT (Start/End Hours) — only when hour tracking is on
        var textItem: CustomerCheckListModel?
        if objEquipment?.hour_tracking == "Yes"{
            let map = Map(mappingType: .fromJSON, JSON: [:])
            var objCheckList = CustomerCheckListModel(map: map)
            objCheckList?.type = "text"
            objCheckList?.question_delivery_text = "Start Hours"
            objCheckList?.question_return_text = "End Hours"
            objCheckList?.startHours = objProduct.start_hours
            objCheckList?.endHours = objProduct.end_hours
            objCheckList?.hour_rate = Float(objEquipment?.overage_rate ?? "") ?? 0
            textItem = objCheckList
        }
        
        //CLEANING
        var cleaningItem: CustomerCheckListModel?
        if objProduct.is_product_clean == true && objProduct.rental_prepaid_cleaning != 0{
            let map = Map(mappingType: .fromJSON, JSON: [:])
            var objCheckList = CustomerCheckListModel(map: map)
            objCheckList?.type = "cleaning"
            objCheckList?.question_delivery_text = "Cleaning"
            objCheckList?.question_return_text = "Cleaning"
            objCheckList?.selectCleaningDelivery = "\(objProduct.startCleaning ?? 0)"
            objCheckList?.selectCleaningReturn = "\(objProduct.endCleaning ?? 0)"
            objCheckList?.startCleaning = "\(objProduct.startCleaning ?? 0)"
            objCheckList?.endCleaning = "\(objProduct.endCleaning ?? 0)"
            objCheckList?.cleaningCharge = 0
            cleaningItem = objCheckList
        }
        
        //FUEL — only when the equipment has a power source
        var fuelItem: CustomerCheckListModel?
        if objEquipment != nil, objEquipment?.powerSourceType != ""{
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
            fuelItem = objCheckListFule
        }
        
        // Insert at index 0 in REVERSE priority so the final order is text, cleaning, fuel.
        for item in [fuelItem, cleaningItem, textItem] {
            if let item = item {
                objProduct.arrQuestions.insert(item, at: 0)
            }
        }
        
        self.objOrderData.arrProduct.remove(at: index)
        self.objOrderData.arrProduct.insert(objProduct, at: index)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            self.tblView.reloadData()
            // Restore the scroll position captured when the pick was applied, then clear it.
            if let off = self.pickerSavedOffset {
                self.tblView.layoutIfNeeded()
                self.tblView.setContentOffset(off, animated: false)
                self.pickerSavedOffset = nil
            }
        })
    }

}


