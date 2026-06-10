//
//  SignupViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 30/04/26.
//

import UIKit

class SignupViewController: UIViewController, UIGestureRecognizerDelegate {

    //DECLARE VARIABLE
    @IBOutlet weak var viewName : UIView!
    @IBOutlet weak var txtName : UITextField!

    @IBOutlet weak var viewEamil : UIView!
    @IBOutlet weak var txtEmail : UITextField!
    @IBOutlet weak var con_Text: NSLayoutConstraint!

    @IBOutlet weak var viewPassword : UIView!
    @IBOutlet weak var txtPassword : UITextField!

    @IBOutlet weak var viewConfrimPassword : UIView!
    @IBOutlet weak var txtConfrimPassword : UITextField!

    
    @IBOutlet weak var viewLogin : UIView!
    @IBOutlet weak var btnLogin : UIButton!
    @IBOutlet weak var con_Button: NSLayoutConstraint!


    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    

    
    override func viewWillAppear(_ animated: Bool) {
        //SET VIEW
        self.view.backgroundColor = .background

        //SET PORTRAIT MODE
        AppUtility.PortraitMode()
                
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true
        
//        self.txtEmail.text = ""
//        self.txtPassword.text = ""
        
        //SET NAVIGATION BAR
        setNavigationBarForButtons(controller: self, title: "Sign Up", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: [], isFilter: false) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in
        
            
        }
        
        //SET THE VIEW
        self.setTheView()
        
    }
    
    //SET THE VIEW
    func setTheView() {

        //SET COLLECTION HEIGHT
        self.con_Text.constant = manageWidth(size: 330)
        self.con_Button.constant = manageWidth(size: 330)

        //SET FONT
        self.txtName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter name")
        self.txtEmail.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter email")
        self.txtPassword.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter password")
        self.txtConfrimPassword.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter confirm password")

        
        self.btnLogin.configureLable(bgColour: .clear, textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "SignUp")

        
        //SET VIEW
        self.viewName.setTheTextView(bgColor: .secondary)
        self.viewEamil.setTheTextView(bgColor: .secondary)
        self.viewPassword.setTheTextView(bgColor: .secondary)
        self.viewConfrimPassword.setTheTextView(bgColor: .secondary)

        self.viewLogin.backgroundColor = .secondary
        self.viewLogin.viewCorneRadius(radius: 0, isRound: true)
    }
    

}

//MARK: - BUTTON ACTION
extension SignupViewController{
    
    @IBAction func btnLoginClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if UserDefaults.standard.baseURL != nil && UserDefaults.standard.baseURL != "" {
            //CHECK VALIDATION
            let strName = self.txtName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            let strEmail = self.txtEmail.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            let strPassword = self.txtPassword.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            let strConfrimPassword = self.txtPassword.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

            if strName == ""{
                showAlertMessage(strMessage: "Please enter your name.")
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
            else if strConfrimPassword == ""{
                showAlertMessage(strMessage: "Please enter your confirm password.")
            }
            else if strPassword != strConfrimPassword{
                showAlertMessage(strMessage: "The confirm password doesn’t match the original password.")
            }
            else{
                indicatorShow()
                //LOGIN
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: {
                    indicatorHide()
                    //MOVE SCHEDULE SCREEN
                    let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.LOGIN_MODEL, bundle: nil)
                    if let newViewController = storyBoard.instantiateViewController(withIdentifier: "InReviewViewController") as? InReviewViewController{
                        self.navigationController?.pushViewController(newViewController, animated: true)
                    }
                })
            }
        }
        else{
            showAlertMessage(strMessage: "Please enter the customer code.")
        }
       
    }
    
}
