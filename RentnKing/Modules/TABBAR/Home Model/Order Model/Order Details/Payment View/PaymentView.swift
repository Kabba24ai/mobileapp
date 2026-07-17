//
//  PaymentView.swift
//  RentnKing
//
//  Created by Jigar Khatri on 15/02/24.
//

import UIKit
@objc protocol PayMentDelegate{
    func PaymnetSuccess()
}


class PaymentView: UIView {
    weak var delegate: PayMentDelegate?

    //VIEW
    @IBOutlet weak var subView: UIView!
    @IBOutlet weak var inerView: UIView!
    @IBOutlet var mainView: UIView!
    @IBOutlet weak var lblPay : UILabel!
    @IBOutlet weak var con_Btn: NSLayoutConstraint!
    @IBOutlet weak var viewPay: UIView!

    //CONSTANT
    @IBOutlet weak var con_Popup: NSLayoutConstraint!
    @IBOutlet weak var con_PopupMain: NSLayoutConstraint!

    
    @IBOutlet weak var lblTitle: UILabel!
    
    @IBOutlet weak var viewPaymentFirstName: UIView!
    @IBOutlet weak var txtPaymentFirstName: UITextField!

    @IBOutlet weak var viewPaymentLastName: UIView!
    @IBOutlet weak var txtPaymentLastName: UITextField!

    @IBOutlet weak var viewCardNumber: UIView!
    @IBOutlet weak var txtCardNumber: UITextField!

    @IBOutlet weak var viewMonth: UIView!
    @IBOutlet weak var txtMonth: UITextField!

    @IBOutlet weak var viewYear: UIView!
    @IBOutlet weak var txtYear: UITextField!

    @IBOutlet weak var viewCVC: UIView!
    @IBOutlet weak var txtCVC: UITextField!
    
    @IBOutlet weak var viewClose: UIView!
    @IBOutlet weak var imgClose: UIImageView!

    // New outlets
    @IBOutlet weak var lblBalanceDue: UILabel!
    @IBOutlet weak var lblBalanceDueAmount: UILabel!
    @IBOutlet weak var viewPaymentMethod: UIView!
    @IBOutlet weak var txtPaymentMethod: UITextField!
    @IBOutlet weak var viewCardFields: UIView!
    @IBOutlet weak var con_CardFieldsHeight: NSLayoutConstraint!
    @IBOutlet weak var viewPersonResponsible: UIView!
    @IBOutlet weak var txtPersonResponsible: UITextField!
    @IBOutlet weak var viewNotes: UIView!
    @IBOutlet weak var txtNotes: UITextView!
    @IBOutlet weak var lblPaymentMethod: UILabel!
    @IBOutlet weak var lblPersonResponsible: UILabel!
    @IBOutlet weak var lblNotes: UILabel!
    @IBOutlet weak var viewCheckNumber: UIView!
    @IBOutlet weak var txtCheckNumber: UITextField!
    @IBOutlet weak var con_CheckNumberHeight: NSLayoutConstraint!

    var strOrderUniqueId : String = ""
    var strBalanceDue : String = ""
    var arrMonth : [String] = ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12"]
    var arrYear : [String] = []
    var arrPaymentMethod : [String] { [str.strPayMethodCreditDebit, str.strPayMethodCash, str.strPayMethodCheck, str.strPayMethodBankTransfer, str.strPayMethodOther] }
    private var previousTextFieldContent: String?
    private var previousSelection: UITextRange?

    var strPaymentType : String = ""
    var strPersonId : String = ""
    
    // method to load reasons xib.
    func loadPopUpView(strOrderUniqueId: String, balanceDue: String = "") {
        self.strBalanceDue = balanceDue
        // ContactUS name of the XIB.
        Bundle.main.loadNibNamed("PaymentView", owner:self, options:nil)
        self.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        self.subView.layer.cornerRadius = 10.0
        self.mainView.frame = self.bounds
        self.addSubview(self.mainView)
        self.mainView.layoutIfNeeded()
        
        setupKeyboard(false)

        //SET ANIMATION
        
        self.subView.transform = CGAffineTransform(scaleX: 0.2, y:0.2)
        UIView.animate(withDuration:1.0, delay: 0.0, usingSpringWithDamping: 0.5,
                       initialSpringVelocity: 0.5, options: [], animations:
                        {
            self.subView.transform = CGAffineTransform(scaleX: 1.0, y:1.0)
        }, completion:nil)
        
        
        
        //KEYBOARD METHOD
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification , object:nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification , object:nil)

        
        //SET FONT
        self.strOrderUniqueId = strOrderUniqueId
        self.setTheView()
    }
    
    func removeViewWithAnimation(isClose : Bool) {
        self.subView.transform = CGAffineTransform.identity
        UIView.animate(withDuration: 0.1, animations: {
            self.subView.transform = CGAffineTransform(scaleX: 1.01, y:1.01)
        } ,completion:{ (finished) in
            if(finished) {
                self.alpha = 1.0
                UIView.animate(withDuration:0.5, animations: {
                    self.alpha = 0
                    self.subView.transform = CGAffineTransform(scaleX: 0.2, y:0.2)
                }, completion: { (finished) in
                    if(finished) {
                        self.delegate?.PaymnetSuccess()
                        self.removeFromSuperview()
                    }
                })
            }
        })
    }
    
    //SET THE VIEW
    func setTheView() {
        //GET YEAR
        let year = Calendar.current.component(.year, from: Date())
        for i in year..<year+30{
            self.arrYear.append("\(i % 100)")
        }
        
        //SET CONSTANT
        self.con_Popup.constant = manageWidth(size: 350)
        
        //SET FONT
        self.lblTitle.configureLable(textAlignment: .center, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strProcessPayment)
        
        //SET VIEW
        self.subView.backgroundColor = UIColor.clear
        self.inerView.backgroundColor = UIColor.background
        self.inerView.viewCorneRadius(radius: 10.0, isRound: false)
        self.inerView.viewBorderCorneRadius(borderColour: .secondary)
        self.inerView.viewBorderCorneRadius2(borderSize: 2.0, borderColour: .secondary.withAlphaComponent(0.4))
        
        
        self.txtPaymentFirstName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterFirstName)
        self.txtPaymentFirstName.delegate = self

        self.txtPaymentLastName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterLastName)
        self.txtPaymentLastName.delegate = self

        self.txtCardNumber.configureText(keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strCreditCard)
        self.txtCardNumber.delegate = self
        self.txtCardNumber.addTarget(self, action: #selector(reformatAsCardNumber), for: .editingChanged)

        self.txtMonth.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strMonth)
        self.txtMonth.delegate = self

        self.txtYear.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strYear)
        self.txtYear.delegate = self

        self.txtCVC.configureText(keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strCVC)
        self.txtCVC.delegate = self

        
        self.viewPaymentFirstName.setTheTextView(bgColor: .secondary )
        self.viewPaymentLastName.setTheTextView(bgColor: .secondary )
        self.viewCardNumber.setTheTextView(bgColor: .secondary )
        self.viewMonth.setTheTextView(bgColor: .secondary )
        self.viewYear.setTheTextView(bgColor: .secondary )
        self.viewCVC.setTheTextView(bgColor: .secondary )
        self.viewPay.backgroundColor = .secondaryTextView
        self.viewClose.backgroundColor = .background
        self.viewClose.viewCorneRadius(radius: 0, isRound: true)
        self.viewClose.viewBorderCorneRadius(borderColour: .secondary)
        imgColor(imgColor: self.imgClose, colorHex: .secondary)

        //SET CONSTANT
        self.con_Btn.constant = manageWidth(size: 45)
        self.lblPay.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strPay)

        // Balance Due
        self.lblBalanceDue?.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "Balance Due")
        self.lblBalanceDueAmount?.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: self.strBalanceDue.isEmpty ? "$0.00" : self.strBalanceDue)

        // Section labels
        self.lblBalanceDue?.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.strBalanceDue)
        self.lblPaymentMethod?.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: str.strPaymentMethod)
        self.lblPersonResponsible?.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: str.strPersonResponsible)
        self.lblNotes?.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: str.strNotesOptional)

        // Payment Method
        self.txtPaymentMethod?.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strSelectPaymentMethod)
        self.txtPaymentMethod?.isUserInteractionEnabled = false
        self.viewPaymentMethod?.setTheTextView(bgColor: .secondary)

        // Card fields hidden by default
        self.con_CardFieldsHeight?.constant = 0
        self.viewCardFields?.clipsToBounds = true

        // Check Number hidden by default
        self.txtCheckNumber?.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strEnterCheckNumber)
        self.txtCheckNumber?.delegate = self
        self.viewCheckNumber?.setTheTextView(bgColor: .secondary)
        self.con_CheckNumberHeight?.constant = 0
        self.viewCheckNumber?.clipsToBounds = true

        // Person Responsible
        self.txtPersonResponsible?.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strSelectPersonResponsible)
        self.txtPersonResponsible?.isUserInteractionEnabled = false
        self.viewPersonResponsible?.setTheTextView(bgColor: .secondary)

        // Notes
        self.txtNotes?.backgroundColor = .clear
        self.txtNotes?.textColor = UIColor.primary
        self.txtNotes?.font = UIFont(name: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 14.0)
        self.viewNotes?.setTheTextView(bgColor: .secondary)
    }
    
    //......................... OTHER FUNCION .........................//
    @IBAction func btnCloseClicked(_ sender: Any) {
        self.endEditing(true)

        self.removeViewWithAnimation(isClose: false)
    }

    @IBAction func btnPayClicked(_ sender: Any) {
        self.endEditing(true)
        let selectedPaymentMethod = self.txtPaymentMethod?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectPerson = self.txtPersonResponsible?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectCheckNumber = self.txtCheckNumber?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if selectedPaymentMethod.isEmpty {
            showAlertMessage(strMessage: str.errSelectPaymentMethod)
            return
        }

        if selectedPaymentMethod == str.strPayMethodCreditDebit {
            let strPaymentFirstName: String = self.txtPaymentFirstName.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let strPaymentFirstLastName: String = self.txtPaymentLastName.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let strCardNumber: String = self.txtCardNumber.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let strMonth: String = self.txtMonth.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let strYear: String = self.txtYear.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let strCVC: String = self.txtCVC.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if strPaymentFirstName.isEmpty {
                showAlertMessage(strMessage: str.errEnterFirstName)
            } else if strPaymentFirstLastName.isEmpty {
                showAlertMessage(strMessage: str.errEnterLastName)
            } else if strCardNumber.isEmpty {
                showAlertMessage(strMessage: str.errEnterCardNumber)
            } else if validatePhoneNumber(value: strCardNumber) {
                showAlertMessage(strMessage: str.errValidCardNumber)
            } else if strMonth.isEmpty {
                showAlertMessage(strMessage: str.errSelectMonth)
            } else if strYear.isEmpty {
                showAlertMessage(strMessage: str.errSelectYear)
            } else if strCVC.isEmpty {
                showAlertMessage(strMessage: str.errEnterCVC)
            } else {
                let carNumber = self.txtCardNumber.text?.replacingOccurrences(of: " ", with: "") ?? ""
                self.apiPayment(OrdersPaymentParameater: OrdersPaymentParameater(order_unique_id: self.strOrderUniqueId, payment_type: self.strPaymentType, responsible_person: self.strPersonId, payment_note: self.txtNotes.text ?? "", cheque_number: "", card_number: carNumber, mm_yy: "\(strMonth)/\(strYear)", cvc: strCVC))
            }
        }
        else if selectedPaymentMethod == str.strPayMethodCheck {
            if selectCheckNumber.isEmpty{
                showAlertMessage(strMessage: str.errenterCheck)
                return
            }
            else if selectPerson.isEmpty{
                showAlertMessage(strMessage: str.errSelectPerson)
                return
            }
            
            self.apiPayment(OrdersPaymentParameater: OrdersPaymentParameater(order_unique_id: self.strOrderUniqueId, payment_type: self.strPaymentType, responsible_person: self.strPersonId, payment_note: self.txtNotes.text, cheque_number: selectCheckNumber, card_number: "", mm_yy: "", cvc: ""))


        }
        else {
            if selectPerson.isEmpty{
                showAlertMessage(strMessage: str.errSelectPerson)
                return
            }
            
            self.apiPayment(OrdersPaymentParameater: OrdersPaymentParameater(order_unique_id: self.strOrderUniqueId, payment_type: self.strPaymentType, responsible_person: self.strPersonId, payment_note: self.txtNotes.text, cheque_number: "", card_number: "", mm_yy: "", cvc: ""))
        }
    }

    @IBAction func btnSelectPaymentMethodClicked(_ sender: UIButton) {
        let ViewController = UIApplication.getTopViewController()
        
        let sheet = UIAlertController(title: str.strPaymentMethod, message: nil, preferredStyle: .actionSheet)
        for method in self.arrPaymentMethod {
            sheet.addAction(UIAlertAction(title: method, style: .default, handler: { [weak self] _ in
                guard let self = self else { return }
                
                if method == str.strPayMethodCreditDebit{
                    self.strPaymentType = "CreditCard"
                }
                else if method == str.strPayMethodCash{
                    self.strPaymentType = "Cash"
                }
                else if method == str.strPayMethodBankTransfer{
                    self.strPaymentType = "BankTransfer"
                }
                else if method == str.strPayMethodCheck{
                    self.strPaymentType = "Cheque"
                }
                else if method == str.strPayMethodOther{
                    self.strPaymentType = "Other"
                }
                                
                
                
                self.txtPaymentMethod?.text = method
                let isCard = method == str.strPayMethodCreditDebit
                let isCheck = method == str.strPayMethodCheck
                self.con_CardFieldsHeight?.constant = isCard ? 148 : 0
                self.con_CheckNumberHeight?.constant = isCheck ? 44 : 0
                if !isCheck { self.txtCheckNumber?.text = "" }
                UIView.animate(withDuration: 0.25) {
                    self.viewCardFields?.superview?.layoutIfNeeded()
                }
            }))
        }
        sheet.addAction(UIAlertAction(title: str.cancel, style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }

        ViewController?.present(sheet, animated: true)
    }

    @IBAction func btnSelectPersonResponsibleClicked(_ sender: UIButton) {
        let ViewController = UIApplication.getTopViewController()
        
        let arrUserList = SDKUserDefault.getMappableArray(UserListModel.self, for: kFileStorageName.kOrderDetailUserData.rawValue) ?? []
        guard !arrUserList.isEmpty else { return }

        let sheet = UIAlertController(title: str.strPersonResponsible, message: nil, preferredStyle: .actionSheet)
        for user in arrUserList {
            let name = user.full_name ?? ""
            sheet.addAction(UIAlertAction(title: name, style: .default, handler: { [weak self] _ in
                self?.txtPersonResponsible?.text = name
                self?.strPersonId = "\(user.id ?? 0)"
            }))
        }
        sheet.addAction(UIAlertAction(title: str.cancel, style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }

        ViewController?.present(sheet, animated: true)

    }
    
    
    @IBAction func btnSelectMonthClicked(_ sender: UIButton) {
        if self.arrMonth.count == 0{
            return
        }

        actionPicker(sender, strTitle: str.strMonth, arrData: self.arrMonth, selectValue: self.txtMonth.text ?? "") { (selectIndex, selectValue) in

            //SELECT VIDEO QULITY
            self.txtMonth.text = selectValue
        }
    }
    
    @IBAction func btnSelectYearClicked(_ sender: UIButton) {
        if self.arrYear.count == 0{
            return
        }

        actionPicker(sender, strTitle: str.strYear, arrData: self.arrYear, selectValue: self.txtYear.text ?? "") { (selectIndex, selectValue) in

            //SELECT VIDEO QULITY
            self.txtYear.text = selectValue
        }
    }
}



//MARK: -- UITEXTFIELD DELEGATE
extension PaymentView : UITextFieldDelegate{

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        
        
        if  textField == self.txtCardNumber || textField == self.txtCVC{
            let inverseSet = NSCharacterSet(charactersIn:"0123456789").inverted
            let components = string.components(separatedBy: inverseSet)
            let filtered = components.joined(separator: "")
           
            
            if filtered == string {
                
                if textField == self.txtCardNumber{
                    previousTextFieldContent = textField.text;
                    previousSelection = textField.selectedTextRange;
                    return true
                }
                else if textField == self.txtCVC{
                    if range.location <= 3 || string.count == 0 {
                        return true
                    }
                    else{
                        return false
                    }
                }
                else{
                    return true
                }
                
            } else {
                return false
            }
        }
        else{
            return true
        }
    }
}



extension PaymentView {

    @objc func reformatAsCardNumber(textField: UITextField) {
        var targetCursorPosition = 0
        if let startPosition = textField.selectedTextRange?.start {
            targetCursorPosition = textField.offset(from: textField.beginningOfDocument, to: startPosition)
        }

        var cardNumberWithoutSpaces = ""
        if let text = textField.text {
            cardNumberWithoutSpaces = self.removeNonDigits(string: text, andPreserveCursorPosition: &targetCursorPosition)
        }

        if cardNumberWithoutSpaces.count > 16 {
            textField.text = previousTextFieldContent
            textField.selectedTextRange = previousSelection
            return
        }

        let cardNumberWithSpaces = self.insertCreditCardSpaces(cardNumberWithoutSpaces, preserveCursorPosition: &targetCursorPosition)
        textField.text = cardNumberWithSpaces

        if let targetPosition = textField.position(from: textField.beginningOfDocument, offset: targetCursorPosition) {
            textField.selectedTextRange = textField.textRange(from: targetPosition, to: targetPosition)
        }
    }

    func removeNonDigits(string: String, andPreserveCursorPosition cursorPosition: inout Int) -> String {
        var digitsOnlyString = ""
        let originalCursorPosition = cursorPosition

        for i in Swift.stride(from: 0, to: string.count, by: 1) {
            let characterToAdd = string[string.index(string.startIndex, offsetBy: i)]
            if characterToAdd >= "0" && characterToAdd <= "9" {
                digitsOnlyString.append(characterToAdd)
            }
            else if i < originalCursorPosition {
                cursorPosition -= 1
            }
        }

        return digitsOnlyString
    }

    func insertCreditCardSpaces(_ string: String, preserveCursorPosition cursorPosition: inout Int) -> String {
        // Mapping of card prefix to pattern is taken from
        // https://baymard.com/checkout-usability/credit-card-patterns

        // UATP cards have 4-5-6 (XXXX-XXXXX-XXXXXX) format
        let is456 = string.hasPrefix("1")

        // These prefixes reliably indicate either a 4-6-5 or 4-6-4 card. We treat all these
        // as 4-6-5-4 to err on the side of always letting the user type more digits.
        let is465 = [
            // Amex
            "34", "37",

            // Diners Club
            "300", "301", "302", "303", "304", "305", "309", "36", "38", "39"
        ].contains { string.hasPrefix($0) }

        // In all other cases, assume 4-4-4-4-3.
        // This won't always be correct; for instance, Maestro has 4-4-5 cards according
        // to https://baymard.com/checkout-usability/credit-card-patterns, but I don't
        // know what prefixes identify particular formats.
        let is4444 = !(is456 || is465)

        var stringWithAddedSpaces = ""
        let cursorPositionInSpacelessString = cursorPosition

        for i in 0..<string.count {
            let needs465Spacing = (is465 && (i == 4 || i == 8 || i == 12))
            let needs456Spacing = (is456 && (i == 4 || i == 8 || i == 12))
            let needs4444Spacing = (is4444 && i > 0 && (i % 4) == 0)

            if needs465Spacing || needs456Spacing || needs4444Spacing {
                stringWithAddedSpaces.append(" ")

                if i < cursorPositionInSpacelessString {
                    cursorPosition += 1
                }
            }

            let characterToAdd = string[string.index(string.startIndex, offsetBy:i)]
            stringWithAddedSpaces.append(characterToAdd)
        }

        return stringWithAddedSpaces
    }
}



struct OrdersPaymentParameater: Codable {
    var order_unique_id : String
    var payment_type : String //Cash, Cheque, BankTransfer, CreditCard, Other
    var responsible_person : String
    var payment_note : String
    var cheque_number : String
    var card_number: String
    var mm_yy: String
    var cvc: String
    
}


extension PaymentView :WebServiceHelperDelegate{
    
    func apiPayment(OrdersPaymentParameater:OrdersPaymentParameater){
       
        guard let parameater = try? OrdersPaymentParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.orderPayment.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "orderPayment"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }
    
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "orderPayment"{
                print(data)
                
                self.removeViewWithAnimation(isClose: true)
                DispatchQueue.main.async {
                    showAlertMessage(strMessage: data.getStringForID(key: "message"))
                }
                
            }
        }
        else{
            indicatorHide()
            //SET THE VIEW
//            self.setTheView()
            if data.getStringForID(key: "message") != ""{
                showAlertMessage(strMessage: data.getStringForID(key: "message"))
            }
            else{
                showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
            }
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        

        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}



//MARK: - KEYBORD DELEGATE
extension PaymentView {
    
    @objc func keyboardWillShow(notification: NSNotification) {
        let keyboardHeight = (notification.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height
        print(keyboardHeight)
        self.con_PopupMain.constant = -100
    }

    @objc func keyboardWillHide(notification: NSNotification) {
        let keyboardHeight = (notification.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height
        print(keyboardHeight)
        self.con_PopupMain.constant = 0
    }
}

