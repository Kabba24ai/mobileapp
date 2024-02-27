//
//  PaymentViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 25/01/24.
//

import UIKit

class PaymentViewController: UIViewController, UIGestureRecognizerDelegate {

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!

    //BILLING INFO
    @IBOutlet weak var lblBillingIfo: UILabel!

    @IBOutlet weak var viewFirstName: UIView!
    @IBOutlet weak var lblFirstName: UILabel!
    @IBOutlet weak var txtFirstName: UITextField!
    
    @IBOutlet weak var viewLastName: UIView!
    @IBOutlet weak var lblLastName: UILabel!
    @IBOutlet weak var txtLastName: UITextField!

    @IBOutlet weak var lblEmail: UILabel!
    @IBOutlet weak var viewEmail: UIView!
    @IBOutlet weak var txtEmail: UITextField!

    @IBOutlet weak var lblPhone: UILabel!
    @IBOutlet weak var viewPhone: UIView!
    @IBOutlet weak var txtPhone: UITextField!

    
    @IBOutlet weak var lblAddress: UILabel!
    @IBOutlet weak var viewAddress: UIView!
    @IBOutlet weak var txtAddress: UITextView!
    @IBOutlet weak var txtAddressPlaceholder: UITextView!

    @IBOutlet weak var lblState: UILabel!
    @IBOutlet weak var viewState: UIView!
    @IBOutlet weak var txtState: UITextField!

    @IBOutlet weak var lblCity: UILabel!
    @IBOutlet weak var viewCity: UIView!
    @IBOutlet weak var txtCity: UITextField!

    @IBOutlet weak var lblZipCode: UILabel!
    @IBOutlet weak var viewZipCode: UIView!
    @IBOutlet weak var txtZipCode: UITextField!

    //DELIVERY INFO
    @IBOutlet weak var lblDeliveryIfo: UILabel!
    @IBOutlet weak var imgSameBilling: UIImageView!
    @IBOutlet weak var lblSameBilling: UILabel!

    @IBOutlet weak var viewDeliveyFirstName: UIView!
    @IBOutlet weak var lblDeliveyFirstName: UILabel!
    @IBOutlet weak var txtDeliveyFirstName: UITextField!
    
    @IBOutlet weak var viewDeliveyLastName: UIView!
    @IBOutlet weak var lblDeliveyLastName: UILabel!
    @IBOutlet weak var txtDeliveyLastName: UITextField!

    @IBOutlet weak var lblDeliveyEmail: UILabel!
    @IBOutlet weak var viewDeliveyEmail: UIView!
    @IBOutlet weak var txtDeliveyEmail: UITextField!

    @IBOutlet weak var lblDeliveyPhone: UILabel!
    @IBOutlet weak var viewDeliveyPhone: UIView!
    @IBOutlet weak var txtDeliveyPhone: UITextField!

    @IBOutlet weak var lblDeliveyAddress: UILabel!
    @IBOutlet weak var viewDeliveyAddress: UIView!
    @IBOutlet weak var txtDeliveyAddress: UITextView!
    @IBOutlet weak var txtDeliveyAddressPlaceholder: UITextView!

    @IBOutlet weak var lblDeliveyState: UILabel!
    @IBOutlet weak var viewDeliveyState: UIView!
    @IBOutlet weak var txtDeliveyState: UITextField!

    @IBOutlet weak var lblDeliveyCity: UILabel!
    @IBOutlet weak var viewDeliveyCity: UIView!
    @IBOutlet weak var txtDeliveyCity: UITextField!

    @IBOutlet weak var lblDeliveyZipCode: UILabel!
    @IBOutlet weak var viewDeliveyZipCode: UIView!
    @IBOutlet weak var txtDeliveyZipCode: UITextField!
    
    @IBOutlet weak var objDeliveyDetials: UIStackView!
    @IBOutlet weak var viewDeliveyNotes: UIView!
    @IBOutlet weak var objDeliveyStates: UIStackView!
    
    @IBOutlet weak var lblOrderNote: UILabel!
    @IBOutlet weak var viewOrderNote: UIView!
    @IBOutlet weak var txtOrderNote: UITextView!
    @IBOutlet weak var txtOrderNotePlaceholder: UITextView!

    @IBOutlet weak var lblPaymentMethod: UILabel!
    
    @IBOutlet weak var imgPayCard: UIImageView!
    @IBOutlet weak var lblPayCard: UILabel!
    @IBOutlet weak var viewPayCard: UIView!
    
    @IBOutlet weak var imgCOD: UIImageView!
    @IBOutlet weak var lblCOD: UILabel!
    @IBOutlet weak var viewCOD: UIView!
    @IBOutlet weak var lblCODMessage: UILabel!

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

    @IBOutlet weak var con_Checkout: NSLayoutConstraint!
    @IBOutlet weak var viewTotalPayment: UIView!
    @IBOutlet weak var lblTotalPayment: UILabel!

    
    
    //OTHER VARIABLE
    var arrStates : [StatesModel] = []
    var isDeliveySameBilling : Bool = true
    var isPayCard : Bool = true
    var arrMonth : [String] = ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12"]
    var arrYear : [String] = []
    private var previousTextFieldContent: String?
    private var previousSelection: UITextRange?

    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        //GET STATES
        if self.arrStates.count == 0{
            self.getStatesAPI()
        }
        
        //GET YEAR
        let year = Calendar.current.component(.year, from: Date())
        for i in year..<year+30{
            self.arrYear.append("\(i % 100)")
        }
        
        //SET FOOTER VIEW
        self.setBillingIfo()
        self.setDeliveryIfo()
        self.setPaymentType()
        
        //SELECT DEFAULT STATE
        let MenuID = self.arrStates.map{$0.is_default}
        if let index = MenuID.firstIndex(of: 1){
            self.txtState.text = self.arrStates[index].name ?? ""
            self.txtDeliveyState.text = self.arrStates[index].name ?? ""
        }
        
       
        
    }
    


    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true
        
        //SET NAVIGATION BAR
        setNavigationBarFor(controller: self, title: str.strPaymentTitle, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {
        }
    }
    
    
    func setBillingIfo(){
        self.con_Checkout.constant = manageWidth(size: 45.0)
        
        //SET FONT
        self.lblBillingIfo.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: str.BillingInfo, numberOfLines: 1)

        self.lblOrderNote.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: str.strOrderNote, numberOfLines: 1)

        self.lblPaymentMethod.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: str.strPaymentMothod, numberOfLines: 1)

        self.lblCODMessage.configureLable(textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 12.0, text: str.codMessage, numberOfLines: 0)

        self.viewTotalPayment.backgroundColor = .secondaryTextView
        self.lblTotalPayment.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strCheckOut)

        
        //SET LABLE
        self.lblFirstName.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strFirstName)
        self.lblLastName.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strLastName)
        self.lblPhone.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strPhone)
        self.lblEmail.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strEmail)
        self.lblAddress.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strAddress)
        self.lblState.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strState)
        self.lblCity.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strCity)
        self.lblZipCode.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strZipCode)
        self.lblPayCard.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.strPayCard)
        self.lblCOD.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.strCOD)

        
        //SET FONT
        self.txtFirstName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterFirstName)
        self.txtFirstName.delegate = self
        
        self.txtLastName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterLastName)
        self.txtLastName.delegate = self

        self.txtEmail.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterEamil)
        self.txtEmail.delegate = self

        self.txtPhone.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterPhone)
        self.txtPhone.delegate = self
        
        self.txtAddress.configureText(bgColour: .clear, textColor: .primary , fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "")
        self.txtAddress.delegate = self

        self.txtAddressPlaceholder.configureText(bgColour: .clear, textColor: .lightGray , fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.enterAddress)
        self.txtAddressPlaceholder.delegate = self

        self.txtState.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.selectState)
        self.txtState.delegate = self

        self.txtCity.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterCity)
        self.txtCity.delegate = self

        self.txtZipCode.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterZipCode)
        self.txtZipCode.delegate = self


        self.txtOrderNote.configureText(bgColour: .clear, textColor: .primary , fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "")
        self.txtOrderNote.delegate = self

        self.txtOrderNotePlaceholder.configureText(bgColour: .clear, textColor: .lightGray , fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.enterOrderNote)
        self.txtOrderNotePlaceholder.delegate = self

        self.txtPaymentFirstName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterFirstName)
        self.txtPaymentFirstName.delegate = self

        self.txtPaymentLastName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterLastName)
        self.txtPaymentLastName.delegate = self

        self.txtCardNumber.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strCreditCard)
        self.txtCardNumber.delegate = self
        self.txtCardNumber.addTarget(self, action: #selector(reformatAsCardNumber), for: .editingChanged)

        self.txtMonth.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strMonth)
        self.txtMonth.delegate = self

        self.txtYear.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strYear)
        self.txtYear.delegate = self

        self.txtCVC.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strCVC)
        self.txtCVC.delegate = self

        
        
        //SET VIEW
        self.viewFirstName.setTheTextView(bgColor: .secondary )
        self.viewLastName.setTheTextView(bgColor: .secondary )
        self.viewPhone.setTheTextView(bgColor: .secondary )
        self.viewEmail.setTheTextView(bgColor: .secondary )
        self.viewAddress.setTheTextView(bgColor: .secondary )
        self.viewState.setTheTextView(bgColor: .secondary )
        self.viewCity.setTheTextView(bgColor: .secondary )
        self.viewZipCode.setTheTextView(bgColor: .secondary )
        self.viewOrderNote.setTheTextView(bgColor: .secondary )

        self.viewPaymentFirstName.setTheTextView(bgColor: .secondary )
        self.viewPaymentLastName.setTheTextView(bgColor: .secondary )
        self.viewCardNumber.setTheTextView(bgColor: .secondary )
        self.viewMonth.setTheTextView(bgColor: .secondary )
        self.viewYear.setTheTextView(bgColor: .secondary )
        self.viewCVC.setTheTextView(bgColor: .secondary )

        //SET HEADER
        self.setHeader()
    }
    
    func setPaymentType(){
        self.viewPayCard.isHidden = !isPayCard
        self.viewCOD.isHidden = isPayCard
        
        self.imgPayCard.image = UIImage(named: isPayCard ? "icon_RadioSelect" : "icon_RadioUnSelect")
        imgColor(imgColor: self.imgPayCard, colorHex: .secondary)
        self.imgCOD.image = UIImage(named: !isPayCard ? "icon_RadioSelect" : "icon_RadioUnSelect")
        imgColor(imgColor: self.imgCOD, colorHex: .secondary)

        
        //SET HEADER
        self.setHeader()
    }
    
 
    func setTheDeliveySameBilling(){

        //SET IMAGE
        self.imgSameBilling.image = UIImage(named: self.isDeliveySameBilling ? "icon_Check" : "icon_unCheck")
        imgColor(imgColor: self.imgSameBilling, colorHex: .secondaryView)
        
        //SET VIEW
        self.objDeliveyDetials.isHidden = self.isDeliveySameBilling
        self.viewDeliveyNotes.isHidden = self.isDeliveySameBilling
        self.objDeliveyStates.isHidden = self.isDeliveySameBilling
        
        //SET DETAILS
        if self.isDeliveySameBilling == false{
            self.txtDeliveyFirstName.text = self.txtFirstName.text
            self.txtDeliveyLastName.text = self.txtLastName.text
            self.txtDeliveyEmail.text = self.txtEmail.text
            self.txtDeliveyPhone.text = self.txtPhone.text
            self.txtDeliveyAddress.text = self.txtAddress.text
            self.txtDeliveyState.text = self.txtState.text
            self.txtDeliveyCity.text = self.txtCity.text
            self.txtDeliveyZipCode.text = self.txtZipCode.text
            
            //CEHCK TEXT
            self.txtDeliveyAddressPlaceholder.text = "Enter address"
            if self.txtDeliveyAddress.text != ""{
                self.txtDeliveyAddressPlaceholder.text = ""
            }
        }
        
        
        //SET HEADER
        self.setHeader()
    }
    
    func setHeader(){
        //SET HEADER
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            //SET TABLE HEADER
            let vw_Table = self.tblView.tableHeaderView
            vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.viewTotalPayment.frame.origin.y + self.viewTotalPayment.frame.size.height + 30)

            self.tblView.tableHeaderView = vw_Table
        }
    }
    
    
    func setDeliveryIfo(){
        self.setTheDeliveySameBilling()
        
        //SET FONT
        self.lblDeliveryIfo.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: str.DeliveryInfo, numberOfLines: 1)

        self.lblSameBilling.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: str.sameAsBilling, numberOfLines: 1)

        
        //SET LABLE
        self.lblDeliveyFirstName.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strFirstName)
        self.lblDeliveyLastName.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strLastName)
        self.lblDeliveyPhone.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strPhone)
        self.lblDeliveyEmail.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strEmail)
        self.lblDeliveyAddress.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strAddress)
        self.lblDeliveyState.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strState)
        self.lblDeliveyCity.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strCity)
        self.lblDeliveyZipCode.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strZipCode)

        
        //SET FONT
        self.txtDeliveyFirstName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterFirstName)
        self.txtFirstName.delegate = self
        
        self.txtDeliveyLastName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterLastName)
        self.txtLastName.delegate = self

        self.txtDeliveyEmail.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterEamil)
        self.txtEmail.delegate = self

        self.txtDeliveyPhone.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterPhone)
        self.txtDeliveyPhone.delegate = self
        
        self.txtDeliveyAddress.configureText(bgColour: .clear, textColor: .primary , fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "")
        self.txtAddress.delegate = self

        self.txtDeliveyAddressPlaceholder.configureText(bgColour: .clear, textColor: .lightGray , fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.enterAddress)
        self.txtAddressPlaceholder.delegate = self

        self.txtDeliveyState.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.selectState)
        self.txtState.delegate = self

        self.txtDeliveyCity.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterCity)
        self.txtCity.delegate = self

        self.txtDeliveyZipCode.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.enterZipCode)
        self.txtZipCode.delegate = self


        
        //SET VIEW
        self.viewDeliveyFirstName.setTheTextView(bgColor: .secondary )
        self.viewDeliveyLastName.setTheTextView(bgColor: .secondary )
        self.viewDeliveyPhone.setTheTextView(bgColor: .secondary )
        self.viewDeliveyEmail.setTheTextView(bgColor: .secondary )
        self.viewDeliveyAddress.setTheTextView(bgColor: .secondary )
        self.viewDeliveyState.setTheTextView(bgColor: .secondary )
        self.viewDeliveyCity.setTheTextView(bgColor: .secondary )
        self.viewDeliveyZipCode.setTheTextView(bgColor: .secondary )

        //SET VIEW
        self.setHeader()
    }
}

//MARK: -- BUTTON ACTION ---
extension PaymentViewController{
    @IBAction func btnSelectStateClicked(_ sender : UIButton) {
        if self.arrStates.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: str.strSelectState, arrData: self.arrStates.compactMap { $0.name}, selectValue: self.txtState.text ?? "") { index, selectValue in
           
            self.txtState.text = selectValue
            if self.isDeliveySameBilling{
                self.txtState.text = selectValue
            }
        }
    }
        
    @IBAction func btnDeliveySameAsBillingClicked(_ sender : UIButton) {
        if self.isDeliveySameBilling{
            self.isDeliveySameBilling = false
        }
        else{
            self.isDeliveySameBilling = true
        }
        
        //SET VIEW
        self.setTheDeliveySameBilling()
    }
    
    @IBAction func btnDeliveySelectStateClicked(_ sender : UIButton) {
        if self.arrStates.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: str.strSelectState, arrData: self.arrStates.compactMap { $0.name}, selectValue: self.txtState.text ?? "") { index, selectValue in
           
            if self.isDeliveySameBilling == false{
                self.txtState.text = selectValue
            }
        }
    }
    
    @IBAction func btnPaymentTypeClicked(_ sender: UIButton) {
        
        if sender.tag == 1{
            self.isPayCard = true
        }
        else{
            self.isPayCard = false
        }
        
        //SET TYPE
        self.setPaymentType()
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
    
    
    @IBAction func btnCheckoutClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        //CHECK VALIDATION
        let strFirstName: String = self.txtFirstName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strLastName: String = self.txtLastName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strEmil: String = self.txtEmail.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strPhone: String = self.txtPhone.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strAddress: String = self.txtAddress.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strState: String = self.txtState.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strCity: String = self.txtCity.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strZip: String = self.txtZipCode.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        
        let strDeliveryFirstName: String = self.txtDeliveyFirstName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strDeliveryLastName: String = self.txtDeliveyLastName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strDeliveryEmil: String = self.txtDeliveyEmail.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strDeliveryPhone: String = self.txtDeliveyPhone.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strDeliveryAddress: String = self.txtDeliveyAddress.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strDeliveryState: String = self.txtDeliveyState.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strDeliveryCity: String = self.txtDeliveyCity.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strDeliveryZip: String = self.txtDeliveyZipCode.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
       
        
        if strFirstName == ""{
            showAlertMessage(strMessage: "Please enter first name")
        }
        else if strLastName == ""{
            showAlertMessage(strMessage: "Please enter last name")
        }
        else if strEmil == ""{
            showAlertMessage(strMessage: "Please enter email")
        }
        else if !validateEmail(enteredEmail: strEmil){
            showAlertMessage(strMessage: "Please enter valide email")
        }
        else if strPhone == ""{
            showAlertMessage(strMessage: "Please enter phone")
        }
        else if strPhone.validPhoneNumber == false || strPhone.count != 14{
            showAlertMessage(strMessage: "Please enter valide phone")
        }
        else if strAddress == ""{
            showAlertMessage(strMessage: "Please enter address")
        }
        else if strState == ""{
            showAlertMessage(strMessage: "Please select State")
        }
        else if strCity == ""{
            showAlertMessage(strMessage: "Please enter city")
        }
        else if strZip == ""{
            showAlertMessage(strMessage: "Please enter zip code")
        }
        else {
            if self.isDeliveySameBilling == false{
                if strDeliveryFirstName == ""{
                    showAlertMessage(strMessage: "Please enter delivery first name")
                }
                else if strDeliveryLastName == ""{
                    showAlertMessage(strMessage: "Please enter delivery last name")
                }
                else if strDeliveryEmil == ""{
                    showAlertMessage(strMessage: "Please enter delivery email")
                }
                else if !validateEmail(enteredEmail: strDeliveryEmil){
                    showAlertMessage(strMessage: "Please enter valide delivery email")
                }

                else if strDeliveryPhone == ""{
                    showAlertMessage(strMessage: "Please enter delivery phone")
                }
                else if strDeliveryPhone.validPhoneNumber == false || strDeliveryPhone.count != 14{
                    showAlertMessage(strMessage: "Please enter valide delivery phone")
                }
                else if strDeliveryAddress == ""{
                    showAlertMessage(strMessage: "Please enter delivery address")
                }
                else if strDeliveryState == ""{
                    showAlertMessage(strMessage: "Please select delivery State")
                }
                else if strDeliveryCity == ""{
                    showAlertMessage(strMessage: "Please enter delivery city")
                }
                else if strDeliveryZip == ""{
                    showAlertMessage(strMessage: "Please enter delivery zip code")
                }
                else{
                    if self.isPayCard{
                        if checkPayment(){
                            //CALL API
                            print("PAY ONLNE")
                            let carNumber : String = self.txtCardNumber.text?.replacingOccurrences(of: " ", with: "") ?? ""
                            self.placeOrderAPI(placeOrderParameater: placeOrderParameater(first_name: strFirstName, last_name: strLastName, email: strEmil, phone: strPhone, address: strAddress, zipcode: strZip, city: strCity, state: strState, note: self.txtOrderNote.text ?? "", same_as_delivery: self.isDeliveySameBilling, payment_method: "authorizenet", delivery_first_name: strFirstName, delivery_last_name: strLastName, delivery_email: strEmil, delivery_mobile: strPhone, delivery_address: strAddress, delivery_zipcode: strZip, delivery_city: strCity, delivery_state: strState,tax_amount: "\(Checkout.shared.taxCharge.stringValue)", total_amount: Checkout.shared.total.stringValue, card_number: carNumber, mm_yy: "\(self.txtMonth.text ?? "")/\(self.txtYear.text ?? "")", cvc: self.txtCVC.text ?? ""), arrCart: self.createCartArray())

                        }
                    }
                    else{
                        //CALL API
                        print("COD")
                        
                        self.placeOrderAPI(placeOrderParameater: placeOrderParameater(first_name: strFirstName, last_name: strLastName, email: strEmil, phone: strPhone, address: strAddress, zipcode: strZip, city: strCity, state: strState, note: self.txtOrderNote.text ?? "", same_as_delivery: self.isDeliveySameBilling, payment_method: "cod", delivery_first_name: strFirstName, delivery_last_name: strLastName, delivery_email: strEmil, delivery_mobile: strPhone, delivery_address: strAddress, delivery_zipcode: strZip, delivery_city: strCity, delivery_state: strState,tax_amount: "\(Checkout.shared.taxCharge.stringValue)", total_amount: Checkout.shared.total.stringValue, card_number: "", mm_yy: "", cvc: ""), arrCart: self.createCartArray())

                    }
                }
            }
            else{
                if self.isPayCard{
                    if checkPayment(){
                        //CALL API
                        print("PAY ONLNE")
                        let carNumber : String = self.txtCardNumber.text?.replacingOccurrences(of: " ", with: "") ?? ""
                        self.placeOrderAPI(placeOrderParameater: placeOrderParameater(first_name: strFirstName, last_name: strLastName, email: strEmil, phone: strPhone, address: strAddress, zipcode: strZip, city: strCity, state: strState, note: self.txtOrderNote.text ?? "", same_as_delivery: self.isDeliveySameBilling, payment_method: "authorizenet", delivery_first_name: strFirstName, delivery_last_name: strLastName, delivery_email: strEmil, delivery_mobile: strPhone, delivery_address: strAddress, delivery_zipcode: strZip, delivery_city: strCity, delivery_state: strState,tax_amount: "\(Checkout.shared.taxCharge.stringValue)", total_amount: Checkout.shared.total.stringValue, card_number: carNumber, mm_yy: "\(self.txtMonth.text ?? "")/\(self.txtYear.text ?? "")", cvc: self.txtCVC.text ?? ""), arrCart: self.createCartArray())

                    }
                }
                else{
                    //CALL API
                    print("COD")
                    
                    self.placeOrderAPI(placeOrderParameater: placeOrderParameater(first_name: strFirstName, last_name: strLastName, email: strEmil, phone: strPhone, address: strAddress, zipcode: strZip, city: strCity, state: strState, note: self.txtOrderNote.text ?? "", same_as_delivery: self.isDeliveySameBilling, payment_method: "cod", delivery_first_name: strFirstName, delivery_last_name: strLastName, delivery_email: strEmil, delivery_mobile: strPhone, delivery_address: strAddress, delivery_zipcode: strZip, delivery_city: strCity, delivery_state: strState,tax_amount: "\(Checkout.shared.taxCharge.stringValue)", total_amount: Checkout.shared.total.stringValue, card_number: "", mm_yy: "", cvc: ""), arrCart: self.createCartArray())
                }
            }
        }
    }
    
    func callPlaceOrderAPI(){
    }
    func checkPayment() -> Bool{
        let strPaymentFirstName: String = self.txtPaymentFirstName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strPaymentFirstLastName: String = self.txtPaymentLastName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strCardNumber: String = self.txtCardNumber.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strMonth: String = self.txtMonth.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strYear: String = self.txtYear.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strCVC: String = self.txtCVC.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

        if strPaymentFirstName == ""{
            showAlertMessage(strMessage: "Please enter payment first name")
        }
        else if strPaymentFirstLastName == ""{
            showAlertMessage(strMessage: "Please enter payment last name")
        }
        else if strCardNumber == ""{
            showAlertMessage(strMessage: "Please enter card number")
        }
        else if validatePhoneNumber(value: strCardNumber){
            showAlertMessage(strMessage: "Please enter valide card number")
        }
        else if strMonth == ""{
            showAlertMessage(strMessage: "Please select month")
        }
   
        else if strYear == ""{
            showAlertMessage(strMessage: "Please select year")
        }
        else if strCVC == ""{
            showAlertMessage(strMessage: "Please enter CVC")
        }
        else{
            return true
        }
        
        return false
    }
    
    
    func createCartArray() -> NSMutableDictionary{
        var cart : NSMutableDictionary = [:]
        
        for objData in Checkout.shared.cart{
            
            let getProductTotal = self.getProductTextAndTotal(cartItem: objData.product)

            let dicData : NSMutableDictionary = ["id" : "\(objData.product.id ?? 0)" ,
                                                 "name" : "\(objData.product.name ?? "")",
                                                 "qty" : "\(objData.product.qty)",
                                                 "deldate" : "\(convertStringToNewFormateString(date: objData.product.selectDate, withFormat: Application.strDateFormet, newFormate: Application.passServertDAte) ?? "")",
                                                 "weight" : "0.0",
                                                 "price" : "\(objData.product.price ?? 0.0)",
                                                 "subTotal" : getProductTotal.0,
                                                 "taxRate" : getProductTotal.1,
                                                 "taxTotal" : getProductTotal.2,
                                                 "delivery" : objData.product.delivery ?? false,
                                                 "pickup" : objData.product.pickup ?? false,
                                                 "store_id" : objData.product.storeID ,
                                                 "options" : getOptionsData(options: objData.product.options)]

            cart = ["\(objData.product.id ?? 0)" : dicData]
        }
        
        
        return cart
    }
    
   
    func getOptionsData(options: [ProductOptionsModel]) -> NSMutableArray{
        let arrOptions : NSMutableArray = []

        //GET PTION VALUDE
        for obj in options{
            for objOption in obj.values{
                if objOption.type == true{
                    let dicData : NSMutableDictionary = ["option_value" : "\(objOption.option_value ?? "")" ,
                                                       "affect_price" : "\(objOption.price ?? 0)",
                                                    "affect_type" : 0,
                                                       "option_type" : "Rental"]
                    
                    arrOptions.add(dicData)
                }
            }
        }
        
        return arrOptions
    }
    
    
    func getProductTextAndTotal(cartItem : ProductModel) -> (String, String, String){
        //GET OPRION PRICE
        var subTotal: Double = 0.0
        var taxeTotal: Double = 0.0
        var taxePercentage: Double = 0.0

        //GET OPTIONS PRICES
        var optionsPrice : Double = 0.0
        for arrOptios in cartItem.options{
            for valude in arrOptios.values{
                if valude.type == true{
                    optionsPrice = optionsPrice + Double((valude.price ?? 0.0))
                }
            }
        }
        
        //ITEM PRICE
        subTotal = Double((cartItem.price ?? 0) * Float(cartItem.qty)) + Double(optionsPrice)
        
        //GET TAXE PRICE
        for objTaxe in cartItem.arrTaxes{
            taxePercentage = taxePercentage + Double((objTaxe.percentage ?? 0.0))
        }
        
        taxeTotal = (subTotal * taxePercentage) / 100

            
        return ("\(subTotal)", "\(taxePercentage)", "\(taxeTotal)")
        

    }
}



//MARK: -- UITEXTFIELD DELEGATE
extension PaymentViewController : UITextFieldDelegate{
    func textFieldDidBeginEditing(_ textField: UITextField) {
//        if textField == self.txtFirstName || textField == self.txtLastName || textField == self.txtPhone{
//            self.isNoteSelect = false
//        }
//        else{
//            self.moveKeybordValude = 3
//            self.isNoteSelect = true
//        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        
        
        if textField == self.txtPhone || textField == self.txtDeliveyPhone || textField == self.txtZipCode || textField == self.txtCardNumber || textField == self.txtCVC{
            let inverseSet = NSCharacterSet(charactersIn:"0123456789").inverted
            let components = string.components(separatedBy: inverseSet)
            let filtered = components.joined(separator: "")
           
            
            if filtered == string {
                if textField == self.txtPhone || textField == self.txtDeliveyPhone {
                    guard let text = textField.text else { return false }
                    let newString = (text as NSString).replacingCharacters(in: range, with: string)
                    textField.text = format(with: "(XXX) XXX-XXXX", phone: newString)
                    return false
                }
                else if textField == self.txtCardNumber{
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
        else if textField == self.txtFirstName{
            self.txtPaymentFirstName.text = textField.text
            return true
        }
        else if textField == self.txtLastName{
            self.txtPaymentLastName.text = textField.text
            return true
        }
        else{
            return true
        }
    }
    
    
    /// mask example: `(XXX) XXX-XXXX`
    func format(with mask: String, phone: String) -> String {
        let numbers = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        var result = ""
        var index = numbers.startIndex // numbers iterator

        // iterate over the mask characters until the iterator of numbers ends
        for ch in mask where index < numbers.endIndex {
            if ch == "X" {
                // mask requires a number in this place, so take the next one
                result.append(numbers[index])

                // move numbers iterator to the next index
                index = numbers.index(after: index)

            } else {
                result.append(ch) // just append a mask character
            }
        }
        return result
    }
}





extension PaymentViewController:  UITextViewDelegate{
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let newText = (textView.text as NSString).replacingCharacters(in: range, with: text)
        
        if textView == self.txtAddress{
            if newText.count != 0{
                self.txtAddressPlaceholder.text = ""
            }
            else{
                self.txtAddressPlaceholder.text = "Enter address"
                self.txtAddress.text = ""
            }
        }
        else if textView == self.txtDeliveyAddress{
            if newText.count != 0{
                self.txtDeliveyAddressPlaceholder.text = ""
            }
            else{
                self.txtDeliveyAddressPlaceholder.text = "Enter address"
                self.txtDeliveyAddress.text = ""
            }
        }
        else if textView == self.txtOrderNote{
            if newText.count != 0{
                self.txtOrderNotePlaceholder.text = ""
            }
            else{
                self.txtOrderNotePlaceholder.text = str.enterOrderNote
                self.txtOrderNote.text = ""
            }
        }
        
        return true
        
    }
}



extension PaymentViewController {

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
