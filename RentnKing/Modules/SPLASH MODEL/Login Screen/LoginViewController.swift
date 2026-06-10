//
//  LoginViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 07/01/26.
//

import UIKit

class LoginViewController: UIViewController {

    //DECLARE VARIABLE
    @IBOutlet weak var viewSelectCustomer : UIView!
    @IBOutlet weak var imgelectCustomer : UIImageView!
    @IBOutlet weak var txtSelectCustomer : UITextField!

    @IBOutlet weak var viewEamil : UIView!
    @IBOutlet weak var txtEmail : UITextField!
    @IBOutlet weak var con_Text: NSLayoutConstraint!

    @IBOutlet weak var viewPassword : UIView!
    @IBOutlet weak var txtPassword : UITextField!

    @IBOutlet weak var viewLogin : UIView!
    @IBOutlet weak var btnLogin : UIButton!
    @IBOutlet weak var con_Button: NSLayoutConstraint!

    @IBOutlet weak var btnSignup : UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        UserDefaults.standard.baseURL = ""
        // Do any additional setup after loading the view.
    }
    

    
    override func viewWillAppear(_ animated: Bool) {
        
        //SET VIEW
        self.view.backgroundColor = .background

        //SET PORTRAIT MODE
        AppUtility.PortraitMode()
        
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        self.tabBarController?.tabBar.isHidden = true
        
//        self.txtEmail.text = ""
//        self.txtPassword.text = ""
        
     
        //SET THE VIEW
        self.setTheView()
        
    }
    
    //SET THE VIEW
    func setTheView() {

        //SET COLLECTION HEIGHT
        self.con_Text.constant = manageWidth(size: 330)
        self.con_Button.constant = manageWidth(size: 330)

        //SET FONT
        imgColor(imgColor: self.imgelectCustomer, colorHex: .secondary)
        self.txtSelectCustomer.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter Compnay Code")
        self.txtSelectCustomer.delegate = self
        self.txtEmail.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter email")
        self.txtPassword.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter password")

        
        self.btnLogin.configureLable(bgColour: .clear, textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Login")
        self.btnSignup.configureLable(bgColour: .clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "Sign Up")

        
        //SET VIEW
        self.viewSelectCustomer.isHidden = false
        self.viewSelectCustomer.setTheTextView(bgColor: .secondary)
        self.viewEamil.setTheTextView(bgColor: .secondary)
        self.viewPassword.setTheTextView(bgColor: .secondary)
     
        self.viewLogin.backgroundColor = .secondary
        self.viewLogin.viewCorneRadius(radius: 0, isRound: true)

#if DEBUG
        self.txtEmail.text = "gary.jezorski@kabba.ai"
        self.txtPassword.text = "Gary#1234"
//
        self.txtEmail.text = "jigar.khatri@kabba.ai"
        self.txtPassword.text = "12345678"
//
//        if UserDefaults.standard.baseURL == "https://api.rentnking.com/api/admin/v1/"{
//            self.txtPassword.text = "Jigar#1234"
//        }

#endif
    
    }
    

}

extension LoginViewController : UITextFieldDelegate{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if  textField == self.txtSelectCustomer{
            let inverseSet = NSCharacterSet(charactersIn:"0123456789").inverted
            let components = string.components(separatedBy: inverseSet)
            let filtered = components.joined(separator: "")
            
            if filtered == string {
                return true
            } else {
                return false
            }
        }
        else{
            return true
        }
    }

    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField == self.txtSelectCustomer {
            print(textField.text ?? "")
            if textField.text != ""{
                self.getCustomerDataAPI(CustomerParameater: CustomerParameater(code: textField.text ?? ""))
            }
        }
    }
}
//MARK: - BUTTON ACTION
extension LoginViewController{
    @IBAction func btnSelectCustomerClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        let arrTempCustomer : [String] = ["Rent 'N' King", "PNW Equipment Rental", "SEO Equip"]
        
        
        actionPicker(sender, strTitle: "Select Customer", arrData: arrTempCustomer, selectValue: arrTempCustomer[sender.tag]) { index, selectValue in
            
            //UPDATE DATA
            self.txtSelectCustomer.text = selectValue
        }
    }
    
    @IBAction func btnLoginClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if UserDefaults.standard.baseURL != nil && UserDefaults.standard.baseURL != "" {
            //CHECK VALIDATION
            let strCode = self.txtSelectCustomer.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            let strEmail = self.txtEmail.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            let strPassword = self.txtPassword.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

            
            if strCode == ""{
                showAlertMessage(strMessage: "Please enter compnay code.")
            }
            else if strEmail == ""{
                showAlertMessage(strMessage: "Please enter your email address.")
            }
            else if !validateEmail(enteredEmail: strEmail){
                showAlertMessage(strMessage: "Please enter a valid email address.")
            }
            else if strPassword == ""{
                showAlertMessage(strMessage: "Please enter your password.")
            }
            else{
                //LOGIN
                self.loginAPI(LoginParameater: LoginParameater(email: strEmail, password: strPassword))
            }
        }
        else{
            showAlertMessage(strMessage: "Please enter or check the customer code.")
        }
       
    }
    
    @IBAction func btnSignupClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        //MOVE SCHEDULE SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.LOGIN_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "SignupViewController") as? SignupViewController{
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    
}
