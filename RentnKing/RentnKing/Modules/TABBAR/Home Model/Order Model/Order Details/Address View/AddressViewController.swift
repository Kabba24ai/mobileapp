//
//  AddressViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 27/02/24.
//

import UIKit

class AddressViewController: UIViewController, UIGestureRecognizerDelegate {

    //CONSTANT
    @IBOutlet weak var tblView: UITableView!

    @IBOutlet weak var con_Btn: NSLayoutConstraint!
    @IBOutlet weak var lblSubmit : UILabel!
    @IBOutlet weak var viewSubmit: UIView!
    
    @IBOutlet weak var viewName: UIView!
    @IBOutlet weak var txtName: UITextField!
    @IBOutlet weak var lblName: UILabel!

    @IBOutlet weak var viewPhone: UIView!
    @IBOutlet weak var txtPhone: UITextField!
    @IBOutlet weak var lblPhone: UILabel!

    @IBOutlet weak var viewEmail: UIView!
    @IBOutlet weak var txtEmail: UITextField!
    @IBOutlet weak var lblEmail: UILabel!

    @IBOutlet weak var viewState: UIView!
    @IBOutlet weak var txtState: UITextField!
    @IBOutlet weak var lblState: UILabel!

    @IBOutlet weak var viewCity: UIView!
    @IBOutlet weak var txtCity: UITextField!
    @IBOutlet weak var lblCity: UILabel!

    @IBOutlet weak var viewAddress: UIView!
    @IBOutlet weak var txtAddress: UITextField!
    @IBOutlet weak var lblAddress: UILabel!

    @IBOutlet weak var viewZip: UIView!
    @IBOutlet weak var txtZip: UITextField!
    @IBOutlet weak var lblZip: UILabel!

    
    
    var strTitle : String = ""
    var orderID : String = ""
    var arrStates : [StatesModel] = []
    var objAdress: AddressModel?


    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboard(true)

        // Do any additional setup after loading the view.
        
        //GET STATES
        self.getStatesAPI()

    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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
        setNavigationBarFor(controller: self, title: self.strTitle, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)
            
        } rightActionHandler: {
        }
        
        //SET THE VIEW
        self.setTheView()
    }
    
    //SET THE VIEW
    func setTheView() {

        //SET LABLE
        self.lblName.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "Name")
        self.lblPhone.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strPhone)
        self.lblEmail.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strEmail)
        self.lblState.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strState)
        self.lblCity.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strCity)
        self.lblAddress.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strAddress)
        self.lblZip.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strZipCode)

        
        self.txtName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "\(self.objAdress?.name ?? "")", placeholder: "Enter name")
        self.txtName.delegate = self

        self.txtPhone.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "\(self.objAdress?.phone ?? "")", placeholder: str.enterPhone)
        self.txtPhone.delegate = self

        self.txtEmail.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "\(self.objAdress?.email ?? "")", placeholder: str.enterEamil)
        self.txtEmail.delegate = self

        self.txtState.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "\(self.objAdress?.state ?? "")", placeholder: str.selectState)
        self.txtState.delegate = self

        self.txtCity.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "\(self.objAdress?.city ?? "")", placeholder: str.enterCity)
        self.txtCity.delegate = self

        self.txtAddress.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "\(self.objAdress?.address ?? "")", placeholder: str.enterAddress)
        self.txtAddress.delegate = self

        self.txtZip.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "\(self.objAdress?.zip_code ?? "")", placeholder: str.enterZipCode)
        self.txtZip.delegate = self

        
        //SET VIEW
        self.viewName.setTheTextView(bgColor: .secondary )
        self.viewPhone.setTheTextView(bgColor: .secondary )
        self.viewEmail.setTheTextView(bgColor: .secondary )
        self.viewState.setTheTextView(bgColor: .secondary )
        self.viewCity.setTheTextView(bgColor: .secondary )
        self.viewAddress.setTheTextView(bgColor: .secondary )
        self.viewZip.setTheTextView(bgColor: .secondary )

        self.viewSubmit.backgroundColor = .secondaryTextView
 
        //SET CONSTANT
        self.con_Btn.constant = manageWidth(size: 45)
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strUpdate)

        
        //SET HEADER
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            //SET TABLE HEADER
            let vw_Table = self.tblView.tableHeaderView
            vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.viewSubmit.frame.origin.y + self.viewSubmit.frame.size.height)

            self.tblView.tableHeaderView = vw_Table
        }
    }
    
}

//MARK: -- BUTTON ACTION

extension AddressViewController {
    @IBAction func btnSelectStateClicked(_ sender: UIButton) {
        if self.arrStates.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: str.strSelectState, arrData: self.arrStates.compactMap { $0.name}, selectValue: self.txtState.text ?? "") { index, selectValue in
            
            self.txtState.text = selectValue
        }
    }
    
    
    @IBAction func btnUpdateClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        //CHECK VALIDATION
        let strName: String = self.txtName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strPhone: String = self.txtPhone.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strEmil: String = self.txtEmail.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strState: String = self.txtState.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strCity: String = self.txtCity.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strAddress: String = self.txtAddress.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strZip: String = self.txtZip.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        
        
        if strName == ""{
            showAlertMessage(strMessage: "Please enter name")
        }
        else if strPhone == ""{
            showAlertMessage(strMessage: "Please enter phone")
        }
        else if strEmil == ""{
            showAlertMessage(strMessage: "Please enter email")
        }
        else if !validateEmail(enteredEmail: strEmil){
            showAlertMessage(strMessage: "Please enter valide email")
        }
       
        else if strPhone.validPhoneNumber == false || strPhone.count != 14{
            showAlertMessage(strMessage: "Please enter valide phone")
        }
        else if strState == ""{
            showAlertMessage(strMessage: "Please select State")
        }
        else if strCity == ""{
            showAlertMessage(strMessage: "Please enter city")
        }
        else if strAddress == ""{
            showAlertMessage(strMessage: "Please enter address")
        }
        else if strZip == ""{
            showAlertMessage(strMessage: "Please enter zip code")
        }
        else {
            //CALLAPI
            self.updateAddress(UpdateAddressParameater: UpdateAddressParameater(address_id: "\(self.objAdress?.id ?? 0)", name: strName, phone: strPhone, email: strEmil, state: strState, city: strCity, zip_code: strZip, address: strAddress))
        }
    }
}



//MARK: -- UITEXTFIELD DELEGATE
extension AddressViewController : UITextFieldDelegate{
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        
        
        if textField == self.txtPhone || textField == self.txtZip {
            let inverseSet = NSCharacterSet(charactersIn:"0123456789").inverted
            let components = string.components(separatedBy: inverseSet)
            let filtered = components.joined(separator: "")
           
            
            if filtered == string {
                if textField == self.txtPhone {
                    guard let text = textField.text else { return false }
                    let newString = (text as NSString).replacingCharacters(in: range, with: string)
                    textField.text = format(with: "(XXX) XXX-XXXX", phone: newString)
                    return false
                }
                else if textField == self.txtZip{
                    if range.location <= 5 || string.count == 0 {
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




