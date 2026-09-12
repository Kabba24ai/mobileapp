//
//  CheckListUpdateViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 06/01/25.
//

import UIKit
import ObjectMapper


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
    var arrPriceList : [PriceListModel] = []
    var arrProductSettingList : [PriceListModel] = []

    var selectIndex : Int = -1
    var strOrderID : String = ""
    var strOrderUniqueId : String = ""
    var strProductID : String = ""

    var strTotalCharge : Float = 0.0
    var strFuleTotalCharge : Float = 0.0
    var strCleaningCharge : Float = 0.0
    var isDeliveryType : Bool = false
    var selectEmployessID : String = ""
    var deliveryIndex : Int = 0
    var isOrderDetailsView : Bool = false
    var isUpdateData : Bool = false
    var isDeleteChecklist : Bool = false

    /// Phase 3 — canonical contexts handed over by CheckListViewController (order_product_unique_id → context).
    var checklistContexts: [String: ChecklistContext] = [:]

    // MARK: Finalization footer (signature → Submit row + Total Charge panel)
    //
    // Built once from the storyboard's footer pieces (viewSubmit / lblSubmit /
    // lblTotalChargeTitle / lblTotalCharge) and rendered ONLY by
    // renderFinalizationState() from ChecklistFinalizationPresentation.
    private var finalizationFooter: UIView?
    private let finalizationRow = UIStackView()
    private let btnCustomerSignature = UIButton(type: .custom)
    private let viewTotalCharge = UIView()
    /// The storyboard's Submit control inside viewSubmit (wired to btnSubmitClicked).
    private var btnSubmit: UIButton? { viewSubmit.subviews.compactMap { $0 as? UIButton }.first }
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        setupCutomeKeyboard()
        // Do any additional setup after loading the view.
        setupKeyboard(false)

        //GET PRICE LIST
        getPriceList { arr_data in
            self.arrPriceList = arr_data
        }
        
        
        getProductSettingList(completion: { arr_data in
            self.arrProductSettingList = arr_data
        })

        
        //CALL API
        self.viewSubmit.isHidden = true
        if self.isUpdateData{
            self.isLoading = true

            //GET EMPLOYEE LIST DATA
            getEmployeeList { arr_data in
                self.arrEmployesList = arr_data
            }
         
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(unique_id: self.strOrderUniqueId)) { dicData in
                    if dicData != nil{
                        self.objOrderData = dicData
                        
                        let checklistType = self.isDeliveryType ? "Delivery" : "Return"
                        if let obj = getChecklistOrderDetailData(strOrderUniqeID: "\(checklistType)_\(self.strOrderUniqueId)"){
                            self.objOrderData = obj
                        }

                        //UPDATE ONLY SIGNATURE (delivery_sign & return_sign) FROM SERVER DATA
                        if let arrServerProduct = dicData?.arrProduct {
                            for i in 0..<self.objOrderData.arrProduct.count {
                                let productId = self.objOrderData.arrProduct[i].id
                                if let serverObj = arrServerProduct.first(where: { $0.id == productId }) {
                                    self.objOrderData.arrProduct[i].returned_emp = serverObj.returned_emp
                                    self.objOrderData.arrProduct[i].delivery_emp = serverObj.delivery_emp

                                    self.objOrderData.arrProduct[i].delivery_sign = serverObj.delivery_sign
                                    self.objOrderData.arrProduct[i].return_sign = serverObj.return_sign
                                }
                            }
                        }

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
        else{
            self.setTheView()
        }
        
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

        //SET SUBMIT — the signature → Submit row and the Total Charge panel are
        //ONE footer rendered from ChecklistFinalizationPresentation (never from
        //whichever button was tapped last).
        self.installFinalizationFooterIfNeeded()
        self.viewSubmit.isHidden = false
        self.con_Submit.constant = manageWidth(size: 45.0)
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.isDeleteChecklist ? str.strRemoveChecklist : str.strSubmit)
        
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
        
        self.renderFinalizationState()

        //SET FOOTER
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.layoutFinalizationFooter()

            //RELOAD TABLE
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                self.tblView.reloadData()
            }

        }
    }

    // MARK: - Finalization footer

    /// Moves the storyboard footer pieces into the approved layout once:
    ///
    ///     [ Customer Signature ]   [ Submit ]
    ///     ┌────────────────────────────────┐
    ///     │ Total Charge            $0.00  │
    ///     └────────────────────────────────┘
    ///
    /// Auto Layout throughout (equal-width buttons, 16pt margins); the footer's
    /// height is measured, never hard-coded per screen size.
    private func installFinalizationFooterIfNeeded() {
        guard finalizationFooter == nil, let viewSubmit = self.viewSubmit,
              let lblTitle = self.lblTotalChargeTitle, let lblAmount = self.lblTotalCharge else { return }

        let footer = UIView()
        footer.backgroundColor = .clear

        // Signature action — the same pad the signature cell opens.
        btnCustomerSignature.translatesAutoresizingMaskIntoConstraints = false
        btnCustomerSignature.titleLabel?.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 16.0)
        btnCustomerSignature.titleLabel?.adjustsFontSizeToFitWidth = true
        btnCustomerSignature.titleLabel?.minimumScaleFactor = 0.8
        btnCustomerSignature.layer.cornerRadius = 10
        btnCustomerSignature.layer.masksToBounds = true
        btnCustomerSignature.accessibilityIdentifier = "checklist.customerSignature"
        btnCustomerSignature.addTarget(self, action: #selector(btnCustomerSignatureTapped), for: .touchUpInside)

        // Submit — reuse the storyboard control; drop its old 40:9 aspect so it
        // can share the row equally with the signature button.
        viewSubmit.removeFromSuperview()
        viewSubmit.translatesAutoresizingMaskIntoConstraints = false
        viewSubmit.constraints
            .filter { $0.firstItem === viewSubmit && $0.firstAttribute == .width && $0.secondAttribute == .height }
            .forEach { $0.isActive = false }
        viewSubmit.layer.cornerRadius = 10
        viewSubmit.layer.masksToBounds = true
        btnSubmit?.accessibilityIdentifier = "checklist.submit"

        finalizationRow.axis = .horizontal
        finalizationRow.distribution = .fillEqually
        finalizationRow.alignment = .fill
        finalizationRow.spacing = 12
        finalizationRow.translatesAutoresizingMaskIntoConstraints = false
        finalizationRow.addArrangedSubview(btnCustomerSignature)
        finalizationRow.addArrangedSubview(viewSubmit)
        btnCustomerSignature.heightAnchor.constraint(equalTo: viewSubmit.heightAnchor).isActive = true

        // Total Charge panel — one bordered unit spanning the content width.
        lblTitle.removeFromSuperview()
        lblAmount.removeFromSuperview()
        lblTitle.translatesAutoresizingMaskIntoConstraints = false
        lblAmount.translatesAutoresizingMaskIntoConstraints = false
        lblAmount.textAlignment = .right
        lblAmount.setContentCompressionResistancePriority(.required, for: .horizontal)
        viewTotalCharge.translatesAutoresizingMaskIntoConstraints = false
        viewTotalCharge.layer.cornerRadius = 10
        viewTotalCharge.layer.borderWidth = 1.5
        viewTotalCharge.backgroundColor = .clear
        viewTotalCharge.accessibilityIdentifier = "checklist.totalCharge"
        viewTotalCharge.addSubview(lblTitle)
        viewTotalCharge.addSubview(lblAmount)

        let column = UIStackView(arrangedSubviews: [finalizationRow, viewTotalCharge])
        column.axis = .vertical
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(column)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: footer.topAnchor, constant: 16),
            column.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
            column.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -16),

            viewTotalCharge.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            lblTitle.leadingAnchor.constraint(equalTo: viewTotalCharge.leadingAnchor, constant: 16),
            lblTitle.centerYAnchor.constraint(equalTo: viewTotalCharge.centerYAnchor),
            lblTitle.topAnchor.constraint(greaterThanOrEqualTo: viewTotalCharge.topAnchor, constant: 12),
            lblAmount.trailingAnchor.constraint(equalTo: viewTotalCharge.trailingAnchor, constant: -16),
            lblAmount.centerYAnchor.constraint(equalTo: viewTotalCharge.centerYAnchor),
            lblAmount.leadingAnchor.constraint(greaterThanOrEqualTo: lblTitle.trailingAnchor, constant: 12),
        ])

        finalizationFooter = footer
        layoutFinalizationFooter()
    }

    /// Sizes the footer with Auto Layout and installs it as the table footer.
    private func layoutFinalizationFooter() {
        guard let footer = finalizationFooter else { return }
        let width = tblView.bounds.width > 0 ? tblView.bounds.width : GlobalMainConstants.windowWidth
        let height = footer.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                    withHorizontalFittingPriority: .required,
                                                    verticalFittingPriority: .fittingSizeLevel).height
        footer.frame = CGRect(x: 0, y: 0, width: width, height: ceil(height))
        tblView.tableFooterView = footer
    }

    /// ONE definition of "this product carries a customer signature for the
    /// current leg": an image drawn on this phone, or a signature already stored
    /// on the server (a nil image is never a signature). The submit guard, the
    /// signature preview and the section-footer height all read this — none
    /// keeps a second answer.
    func hasSignature(_ obj: NoteModel) -> Bool {
        let image = self.isDeliveryType ? obj.dSignature : obj.rSignature
        let url = self.isDeliveryType ? obj.dSignatureUrl : obj.rSignatureUrl
        guard let image = image else { return false }
        return image != UIImage() || url != ""
    }

    /// The canonical "a customer signature exists" fact — the same test the
    /// submit guard uses (drawn on this phone, or already stored on the server).
    func hasCustomerSignature() -> Bool {
        guard let obj = self.arrOtherData.last else { return false }
        return hasSignature(obj)
    }

    /// ONE renderer: signature button, Submit and the Total Charge panel all
    /// derive from ChecklistFinalizationPresentation.
    func renderFinalizationState() {
        let state = ChecklistFinalizationPresentation(hasSignature: hasCustomerSignature(),
                                                      totalCharge: Double(self.strTotalCharge),
                                                      isDeleteMode: self.isDeleteChecklist)

        // Signature action (delete mode has no signature step).
        btnCustomerSignature.setTitle(state.signatureTitle, for: .normal)
        apply(state.signatureTone, background: btnCustomerSignature, title: btnCustomerSignature)
        btnCustomerSignature.isHidden = self.isDeleteChecklist
        btnCustomerSignature.accessibilityLabel = state.signatureTitle

        // Submit — genuinely non-interactive until signed.
        if let viewSubmit = self.viewSubmit {
            apply(state.submitTone, background: viewSubmit, title: lblSubmit)
            viewSubmit.isUserInteractionEnabled = state.submitIsEnabled
            viewSubmit.alpha = state.submitIsEnabled ? 1.0 : 0.85
        }
        btnSubmit?.isEnabled = state.submitIsEnabled
        btnSubmit?.accessibilityLabel = self.isDeleteChecklist ? "Delete" : "Submit"
        btnSubmit?.accessibilityHint = state.submitIsEnabled ? nil : "Capture the customer signature first"
        finalizationRow.isHidden = self.viewSubmit?.isHidden ?? true

        // Total Charge panel.
        let accent: UIColor
        switch state.chargeAccent {
        case .green:   accent = hexStringToUIColor(hex: "3DDC6E")
        case .red:     accent = .redText
        case .neutral: accent = .primary.withAlphaComponent(0.4)
        }
        viewTotalCharge.layer.borderColor = accent.cgColor
        lblTotalChargeTitle?.textColor = .primary
        lblTotalCharge?.textColor = state.chargeAccent == .neutral ? .primary : accent
        viewTotalCharge.isHidden = lblTotalCharge?.isHidden ?? true
        viewTotalCharge.accessibilityLabel = "\(str.strTotalCheckList) \(lblTotalCharge?.text ?? "")"
    }

    private func apply(_ tone: ChecklistFinalizationPresentation.ButtonTone, background: UIView, title: UIView?) {
        let bg: UIColor
        let fg: UIColor
        switch tone {
        case .activeYellow:   bg = .secondaryTextView ?? .systemYellow; fg = .backgroundView ?? .black
        case .completedGray:  bg = .darkGray; fg = .primary
        case .disabledGray:   bg = .darkGray; fg = .primary.withAlphaComponent(0.7)
        case .destructiveRed: bg = .redText; fg = .primary
        }
        background.backgroundColor = bg
        if let button = title as? UIButton {
            button.setTitleColor(fg, for: .normal)
            button.setTitleColor(fg, for: .disabled)
        } else if let label = title as? UILabel {
            label.textColor = fg
        }
    }

    /// Opens the same signature pad the signature cell opens (last product's index).
    @objc private func btnCustomerSignatureTapped() {
        btnCustomerSignature.tag = max(0, (self.objOrderData?.arrProduct.count ?? 1) - 1)
        self.btnSignatureClicked(btnCustomerSignature)
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
        
        //UPDATE SIGNATURE ARRAY — apply the same signature to every product
        for obj in self.arrOtherData {
            if self.isDeliveryType{
                obj.dSignature = signatureImage
            }
            else{
                obj.rSignature = signatureImage
            }
        }

        //RELOAD — the footer flips to "✓ Customer Signed" / Submit active from state.
        self.renderFinalizationState()
        self.tblView.reloadData()
    }

    

    
    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        if self.isDeleteChecklist{
            //REMOVE CHECKLIST
            //CALL API
            let alert = UIAlertController(title: Application.appName, message: "Are you sure you want to replace or delete this equipment?", preferredStyle: .alert)
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
            
            
            // Phase 3 — ONE submission per order product. arrOtherData is built index-aligned with
            // arrProduct (CheckListViewController.setupStaticData); the pre-Phase-3 nested loop
            // (for product { for otherData { … } }) produced product × otherData submissions and
            // handed Product B Product A's signature and employee. A misaligned pair is a bug, so
            // it is refused instead of guessed.
            guard self.arrOtherData.count == self.objOrderData.arrProduct.count else {
                showAlertMessage(strMessage: "The checklist data is out of sync. Please go back and open the checklist again.")
                return
            }

            var submissions: [ChecklistSubmissionPlan] = []
            for (index, obj) in self.objOrderData.arrProduct.enumerated() {
                let objOther = self.arrOtherData[index]
                guard let productUid = obj.unique_id, !productUid.isEmpty else { continue }

                if let context = self.checklistContexts[productUid] {
                    // Canonical: template ids, execution identity, signature as a durable asset.
                    let capture = ChecklistCaptureFactory.make(context: context, product: obj, other: objOther,
                                                               isDelivery: self.isDeliveryType,
                                                               totalCharge: self.strTotalCharge,
                                                               fuelTotalCharge: self.strFuleTotalCharge,
                                                               cleaningCharge: self.strCleaningCharge)
                    let signature = (self.isDeliveryType ? objOther.dSignature : objOther.rSignature)?.jpegData(compressionQuality: 0.7)
                    submissions.append(.canonical(capture, signature: signature))
                } else {
                    // No context (never loaded while connected): the legacy shape for THIS product
                    // only, carried by the durable engine (no dead-letter) to the legacy endpoint.
                    submissions.append(.legacy(ChecklistCaptureFactory.legacyItem(product: obj, other: objOther,
                                                                                  isDelivery: self.isDeliveryType,
                                                                                  orderUniqueId: self.strOrderUniqueId,
                                                                                  totalCharge: self.strTotalCharge,
                                                                                  fuelTotalCharge: self.strFuleTotalCharge,
                                                                                  cleaningCharge: self.strCleaningCharge)))
                }
            }

            //CALL API
            let alert = UIAlertController(title: Application.appName, message: "Are you sure you're ready to submit this report?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                
                indicatorShow()

                // Durable, idempotent, one operation per product — persisted BEFORE the UI moves on.
                let queued = ChecklistSubmissionPlan.enqueueAll(submissions)
                if queued.failed > 0 {
                    indicatorHide()
                    showAlertMessage(strMessage: "The checklist could not be saved on this phone (\(queued.failed) of \(submissions.count)). Nothing was sent. Please try again.")
                    return
                }
                KabbaSync.showStatusToast(for: queued.firstOperationId)
                
                //SET DATA IN LOCAL
                let checklistType = self.isDeliveryType ? "Delivery" : "Return"
                SDKUserDefault.saveMappableObject(self.objOrderData, for: "\(kFileStorageName.kCheckListOrderDetailsData.rawValue)_\(checklistType)_\(self.strOrderUniqueId)")
                SDKUserDefault.saveNSObjectArray(self.arrOtherData, key: "\(kFileStorageName.kCheckListOtherData.rawValue)_\(checklistType)_\(self.strOrderUniqueId)")

                // This checklist is now finalized — clear any PENDING (prepared) draft so it is
                // never reloaded as pending after completion. (No-op if none / for Return.)
                clearPendingCheckList(orderUniqueId: self.strOrderUniqueId, isDelivery: self.isDeliveryType)
              
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
                    
                    NotificationCenter.default.post(name: .updateCheckList, object: nil, userInfo: ["checklist_data": self.arrOtherData, "index" : self.selectIndex, "type" : self.isDeliveryType] )

                    if self.isOrderDetailsView{
                        if let targetViewController = self.navigationController?.viewControllers.first(where: { $0 is OrderDetailsViewController  }) {
                            self.navigationController?.popToViewController(targetViewController, animated: true)
                        }
                    }
                    else{
                        if let targetViewController = self.navigationController?.viewControllers.first(where: { $0 is OrderListViewController }) {
                            self.navigationController?.popToViewController(targetViewController, animated: true)
                        }
                    }
                    
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1){
                        indicatorHide()
                        // Honest wording: the work is safely on the phone; Kabba confirms it on sync.
                        showAlertMessage(strMessage: queued.usedEngine ? "Checklist saved on this phone · Pending Sync" : "Checklist updated successfully.", isDismiss: true)
                    }
                })
                                
            }))
            
            
            alert.addAction(UIAlertAction(title: str.no, style: .default,handler: { (Action) in
            }))
            
            self.present(alert, animated: true)
        }
    }
    
  
    func checkMachineData() -> Bool{
        for objData in self.objOrderData.arrProduct{
            if objData.objMachine == nil{
                showAlertMessage(strMessage: "Please select an equipment ID.")
                return false
            }
        }
        return true
    }
    
    func checkOtherData() -> Bool{
        for obj in self.arrOtherData{
            if self.isDeliveryType{
                if obj.dEmplayessId == ""{
                    showAlertMessage(strMessage: "Please select who delivered the equipment.")
                    return false
                }
                
//                if obj.dSignature == UIImage() && obj.dSignatureUrl == ""{
//                    showAlertMessage(strMessage: "Customer signature is required")
//                    return false
//                }
            }
            else{
                if obj.rEmplayessId == ""{
                    showAlertMessage(strMessage: "Please select who returned the equipment.")
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
        // Defence in depth behind the disabled Submit: the same canonical fact.
        if self.arrOtherData.count != 0 && !self.hasCustomerSignature() {
            showAlertMessage(strMessage: "Customer signature is required")
            return false
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
                        // Total math (ChecklistHoursMath): never traps on ±inf/NaN meter values.
                        var totalHours = ChecklistHoursMath.overageHours(start: Float(objQuestion.startHours),
                                                                         end: Float(objQuestion.endHours))
                        if objQuestion.startHours == 0.0{
                            totalHours = 0
                        }
                        objQuestion.total = 0
                        if totalHours > 0{
                            //SET TOTAL HOURS
                            objQuestion.total = Float(totalHours)
                        }


                        //SET ADDITION HOURS
                        var additionslHours = Float(ChecklistHoursMath.additionalHours(total: totalHours,
                                                                                       allocated: objProduct.allocated_hours ?? 0))
                        objQuestion.additinal = 0
                        if additionslHours > 0{
                            //SET TOTAL HOURS
                            objQuestion.additinal = Int(additionslHours)
                        }
                        else{
                            additionslHours = 0
                        }
                        
                        //SET TOTAL CHARGE
                        self.strTotalCharge =  self.strTotalCharge + Float(additionslHours) * Float(objQuestion.hour_rate)
                        objQuestion.total_cost = Float(additionslHours) * Float(objQuestion.hour_rate)
                        
                        
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

                            self.strCleaningCharge = (objProduct.rental_prepaid_cleaning ?? 0) * price
                            self.strTotalCharge = self.strTotalCharge + self.strCleaningCharge

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
                        

                        self.strFuleTotalCharge = FuelCalulateTotalCharge(total: totalPrice, dSelect: strDeliveredFule == "Admin Override" ?  9 : Float(objQuestion.selectFuleDelivery ?? "") ?? 0, rSelect: Float(objQuestion.selectFuleReturn ?? "") ?? 0)
                                                
                        //CHECK PREPAID FULE
                        let selectedOptions = objProduct.objProductData?.arrProductSelectdOptions ?? []
                        if selectedOptions.contains("rental_prepaid_fuel") {
                            // Option exists
                            self.strFuleTotalCharge = 0
                        }
                        
                        self.strTotalCharge = self.strTotalCharge + self.strFuleTotalCharge
                        
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
        
        
        //RELOAD TABLE — same "$%.2f" presentation; the panel's colour comes from state.
        self.lblTotalCharge.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0,
                                           text: ChecklistFinalizationPresentation.formattedCharge(Double(self.strTotalCharge), currency: Application.currency))
        self.renderFinalizationState()

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
}



class CheckListUpdateCell : UITableViewCell{

    @IBOutlet weak var lblTitle: UILabel!
    @IBOutlet weak var lblTitleReturn: UILabel!
    @IBOutlet weak var viewTitleReturn: UIView!
    
    @IBOutlet weak var viewPrepaid: UIView!
    @IBOutlet weak var lblPrepaid: UILabel!
    @IBOutlet weak var viewPrepaidReturn: UIView!
    @IBOutlet weak var lblPrepaidReturn: UILabel!
    
    
    @IBOutlet weak var viewDeliveredMain: UIView!
    @IBOutlet weak var viewReturnedMain: UIView!

    @IBOutlet weak var lblDeliverySelect: UILabel!
//    @IBOutlet weak var imgDeliverySelect: UIImageView!
//    @IBOutlet weak var btnDeliverySelect: UIButton!
    
    @IBOutlet weak var lblReturnSelect: UILabel!
//    @IBOutlet weak var imgReturnSelect: UIImageView!
//    @IBOutlet weak var btnReturnSelect: UIButton!

    
    
    
//    @IBOutlet weak var lblTitleDelivered: UILabel!

        
    
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
            cell.lblTitleMachineId.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "Equipment ID")
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
            cell.lblEmployee.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: str.strDelivredEmployess, numberOfLines: 1)
            cell.lblReturnEmployee.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: str.strReturnedEmployess, numberOfLines: 1)

            cell.txtSelctEmployee.configureText(textAlignment: .left ,bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: objDetails.dEmplayess, placeholder: str.strSelectEmployess)
            cell.txtSelctReturnEmployee.configureText(textAlignment: .right ,bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: objDetails.rEmplayess, placeholder: str.strSelectEmployess)

            
            cell.viewEmployee.isHidden = false
            cell.viewReturnEmployee.isHidden = false
            if self.isDeliveryType == true{
                cell.viewReturnEmployee.isHidden = true
            }
            
            // The legacy signature button under the preview is retired: the ONE
            // signature action is the Customer Signature button in the
            // finalization footer (renderFinalizationState). con_Bottom is that
            // button's height.
            cell.con_Bottom.constant = 0
            cell.viewSignature.isHidden = true
            
            cell.lblNote.text = ""
            cell.lblNoteDetails.text = ""
            cell.con_NoteTop.constant = -30
            let strNote = self.isDeliveryType ?  objDetails.dNote :  objDetails.rNote
            if strNote != "" {
                cell.con_NoteTop.constant = 8
                cell.lblNote.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "\(self.isDeliveryType == true ? str.strDelivredNote : str.strReturnedNote):", numberOfLines: 1)
                cell.lblNoteDetails.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: strNote, numberOfLines: 0)
            }
            
            
            //SET SIGNATURE PREVIEW (the captured signature, same fact as the submit guard)
            cell.con_imgSignature.constant = 0
            
            if self.hasSignature(objDetails) {
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
            
            // Employees block, then the 200pt signature preview when one exists.
            // (The old "!= UIImage()" test counted a nil image as signed, which
            // reserved the tall layout for every unsigned checklist.)
            if self.hasSignature(objDetails) {
                return manageWidth(size: 315 + noteHeight)
            }
            else{
                return manageWidth(size: 115 + noteHeight)
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
            cell.viewReturnedMain.isHidden = true
            cell.viewAdditional.isHidden = true
            cell.viewHourlyFee.isHidden = true
            cell.viewLine.alpha = 0
            cell.viewReturnedMain.isHidden = self.isDeliveryType
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
            
            if self.objOrderData.arrProduct[indexPath.section].arrQuestions.count == 0 {
                return cell
            }
            
            let  objDetails = self.objOrderData.arrProduct[indexPath.section].arrQuestions[indexPath.row]
                        

            cell.lblTitle.configureLable(textColor: self.isDeliveryType ? .primary : .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: objDetails.question_delivery_text ?? "")
            cell.lblTitleReturn.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: objDetails.question_return_text ?? "")
            cell.lblTitleReturn.isHidden = true
            cell.viewTitleReturn.isHidden = true
            if objDetails.type == "text" && self.isDeliveryType == false{
                cell.lblTitleReturn.isHidden = false
                cell.viewTitleReturn.isHidden = false
            }
            else if objDetails.question_delivery_text ?? "" != objDetails.question_return_text ?? "" && self.isDeliveryType == false{
                cell.lblTitleReturn.isHidden = false
                cell.viewTitleReturn.isHidden = false
            }

            cell.lblDeliverySelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Admin Override")
            cell.lblReturnSelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Admin Override")
            if objDetails.type == "text"{
                cell.lblDeliverySelect.text = objDetails.startHours == 0 ? "Admin Override" : "\(objDetails.startHours)"
                
                if self.objOrderData.arrProduct[indexPath.section].is_delivered == true{
                    cell.lblReturnSelect.text = objDetails.endHours == 0 ? "Admin Override" : "\(objDetails.endHours)"
                }
            }
           
            
            if objDetails.type == "text" && self.isDeliveryType == false{
                if objDetails.total_cost != 0.0{
                    cell.lblTitle.text = str.strMachineHours
                    cell.viewValue.isHidden = false
                    cell.viewBalance.isHidden = false
                    cell.viewCustomerOwes.isHidden = false
                    cell.viewAdditional.isHidden = false
                    cell.viewHourlyFee.isHidden = false
                    cell.lblDeliverySelect.text = ""

                    cell.lblValue.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strAllocatedHourse)
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
                    cell.txtCustomerOwes.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "$\((String(format: "%.2f", objDetails.total_cost)) )", placeholder: "0.0")

                }
            }            
            else if objDetails.type == "cleaning"{
                cell.lblDeliverySelect.text = getCleaning(strId: objDetails.selectCleaningDelivery ?? "", isReturn: false)
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
                
            
                if self.objOrderData.arrProduct[indexPath.section].is_product_clean == true && self.objOrderData.arrProduct[indexPath.section].rental_prepaid_cleaning != 0 && Int(objDetails.selectCleaningReturn ?? "") ?? 0 != 0{
                    
                    var price = self.getCleanigPrice(selectID: Int(objDetails.selectCleaningReturn ?? "") ?? 0)
                    if selectedOptions.contains("rental_prepaid_cleaning") {
                        if Int(objDetails.selectCleaningReturn ?? "") != 5{
                            price = 0
                        }
                    }

                    let totalCharge = (self.objOrderData.arrProduct[indexPath.section].rental_prepaid_cleaning ?? 0) * price
                    if totalCharge != 0{
                        cell.viewCustomerOwes.isHidden = false
                        
                        cell.lblCustomerOwes.configureLable(textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strCustomerOwes)
                        cell.txtCustomerOwes.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "$\(String(format: "%.2f", totalCharge))", placeholder: "0.0")
                    }
                }
            }
            
            else if objDetails.type == "fuel" {
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
                
                
                //SET FULE IS ADMIN OVERRIDE
                var strDeliveredFule : String = getFlueName(strId: objDetails.selectFuleDelivery ?? "")
                if self.objOrderData.arrProduct[indexPath.section].is_delivered == true{
                    strDeliveredFule = strDeliveredFule == "Select" ? "Admin Override" : strDeliveredFule
                }
                
                let totalCharge = FuelCalulateTotalCharge(total: totalPrice, dSelect: strDeliveredFule == "Admin Override" ? 9 : Float(objDetails.selectFuleDelivery ?? "") ?? 0, rSelect: Float(objDetails.selectFuleReturn ?? "") ?? 0)

                //SET DATA
                let strFule = getFlueName(strId: objDetails.selectFuleDelivery ?? "")
                cell.lblDeliverySelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: strFule == "Select" ? "Admin Override" : strFule)
                
                let strFuleReturn = getFlueName(strId: objDetails.selectFuleReturn ?? "")
                cell.lblReturnSelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: strFuleReturn == "Select" ? "Admin Override" : strFuleReturn)
                if self.objOrderData.arrProduct[indexPath.section].is_delivered == true{
                    let strReturnFule = getFlueName(strId: objDetails.selectFuleReturn ?? "")
                    cell.lblReturnSelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: strReturnFule == "Select" ? "Admin Override" : strReturnFule)
                }


                if totalCharge != 0{
                    cell.viewCustomerOwes.isHidden = false
                    
                    cell.lblCustomerOwes.configureLable(textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strCustomerOwes)
                    cell.txtCustomerOwes.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "$\(String(format: "%.2f", totalCharge))", placeholder: "0.0")

                }

                
                //SET
                let selectedOptions = self.objOrderData
                    .arrProduct[indexPath.section]
                    .objProductData?
                    .arrProductSelectdOptions ?? []

                cell.viewPrepaid.isHidden = true
                cell.viewPrepaidReturn.isHidden = true
                if selectedOptions.contains("rental_prepaid_fuel") {
                    cell.viewCustomerOwes.isHidden = true
                    
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
                    cell.lblDeliverySelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: objDetails.deliverAnswer.answer_delivery_text ?? "")
                    cell.lblDeliverySelect.numberOfLines = 2
                }
                
                if objDetails.returnAnswer != nil{
                    cell.lblReturnSelect.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: objDetails.returnAnswer.answer_return_text ?? "")
                    cell.lblReturnSelect.numberOfLines = 2
                }

                
                
                if objDetails.deliverAnswer != nil && objDetails.returnAnswer != nil{
                    let strPrice = Float(objDetails.returnAnswer.return_amt) - Float(objDetails.deliverAnswer.delivery_amt)
                    if objDetails.deliverAnswer.unique_id != objDetails.returnAnswer.unique_id && strPrice > 0{
                        cell.viewCustomerOwes.isHidden = false
                        
                        
                        let totalCharge = Float(objDetails.deliverAnswer.delivery_amt) + Float(objDetails.returnAnswer.return_amt)
                        
                        cell.lblCustomerOwes.configureLable(textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strCustomerOwes)
                        cell.txtCustomerOwes.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "$\(String(format: "%.2f", totalCharge))", placeholder: "0.0")
//                        cell.viewCustomerOwesLine.backgroundColor = .redText
                    }
                }
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



//MARK: - LOCAL DATABASE MANAGE
extension CheckListUpdateViewController{
    
    
    func setupStaticData() {
        
        let arrData = self.objOrderData.arrProduct
        self.objOrderData.arrProduct = []
        
        //GET PRODUCT DATA
        for obj in arrData{
            if obj.objProduct?.checklist_id != 0{
                self.objOrderData.arrProduct.append(obj)
            }
        }
        
        if isCheckListOtherDataSaved(strOrderUniqeID: self.strOrderUniqueId) == false{
            //SET SIGNATURE ARRAT
            self.arrOtherData = []
            for i in 0..<self.objOrderData.arrProduct.count{
                let  obj = self.objOrderData.arrProduct[i]
                self.arrOtherData.append(NoteModel(startHours: 0.0, endHours: 0.0, dNote: obj.delivery_note, rNote: obj.returned_note, rStoreId: "", rStore: "", dEmplayess: self.getEmployeesName(emp_id: obj.delivery_emp), dEmplayessId: "\(obj.delivery_emp)", rEmplayess: self.getEmployeesName(emp_id: obj.returned_emp), rEmplayessId: "\(obj.returned_emp)", dSignature: UIImage(), rSignature: UIImage(), productID: obj.id ?? 0, machine_id: obj.machine_id ?? 0, dSignatureUrl: obj.delivery_sign, rSignatureUrl: obj.return_sign, inTime: obj.inTime, outTime: obj.outTime, selectFuleDelivery:  obj.fuel_initial_reading , selectFuleReturn:  obj.fuel_final_reading , selectCleaningDelivery: "\(obj.startCleaning ?? 0)", selectCleaningReturn:  "\(obj.endCleaning ?? 0)"))
                
                
                //CHECK EQUMPEMT
                if obj.objMachine != nil{
                    if obj.objMachine?.unique_id != ""{
                        
                        let checklistType = self.isDeliveryType ? "Delivery" : "Return"
                        if isCheckListOrderDetailSaved(strOrderUniqeID: "\(checklistType)_\(self.strOrderUniqueId)") == false{
                            self.setUpTheEqupmentData(objEquipment: obj.objMachine, arrQuestions: obj.arrQuestions, index: i)
                            
                            //CALL API ALSO
                            self.getCheckListPriceAPI(CheckListParameater: CheckListParameater(equipment_unique_id: obj.objMachine?.unique_id ?? "", type: "return", order_product_unique_id: obj.unique_id ?? ""), index: i)
                        }
                        
                    }
                }
                else{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                        self.tblView.reloadData()
                    })
                }
            }
        }
        else{
            self.arrOtherData = []
            let checklistType = self.isDeliveryType ? "Delivery" : "Return"
            self.arrOtherData = getChecklistOtherData(strOrderUniqeID: "\(checklistType)_\(self.strOrderUniqueId)") ?? []
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                self.tblView.reloadData()
            })

        }

    }
    
    
    func setUpTheEqupmentData(objEquipment : MachineModel?, arrQuestions: [CustomerCheckListModel], index : Int){
        
        var objProduct = self.objOrderData.arrProduct[index]
        objProduct.arrQuestions = arrQuestions
        
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
            objCheckList?.startCleaning = "\(objProduct.startCleaning ?? 0)"
            objCheckList?.endCleaning = "\(objProduct.endCleaning ?? 0)"
            objCheckList?.selectCleaningDelivery = "\(objProduct.startCleaning ?? 0)"
            objCheckList?.selectCleaningReturn = "\(objProduct.endCleaning ?? 0)"

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: {
            self.CalculatTotalCharge()
            self.tblView.reloadData()
        })
    }
    
}
