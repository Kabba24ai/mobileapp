//
//  TimeClockLockViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 07/10/24.
//

import UIKit

class TimeClockLockViewController: UIViewController, UIGestureRecognizerDelegate {


    @IBOutlet weak var viewName: UIView!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var txtName: UITextField!

    @IBOutlet weak var con_Submit: NSLayoutConstraint!
    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!
    @IBOutlet weak var con_SubmitBottom : NSLayoutConstraint!

    var arrStatusList : [EmpStatusModel] = []
    var arrEmployesList : [EmployeesModel] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        setupKeyboard(false)

        
        
        //KEYBOARD METHOD
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification , object:nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification , object:nil)
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
        setNavigationBarForButtons(controller: self, title: str.strTimeClock, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: [], isFilter: false) {
            setupKeyboard(true)

            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in
        

        }
        
        //SET VIEW
        self.setTheView()
        self.getStatusAPI()

    }

    
    func setTheView(){
   
        
        //SET FONT
        self.lblName.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strMasterCode)
        self.txtName.configureText(bgColour: .clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: "", placeholder: str.strMasterCodeText)
        self.txtName.delegate = self
       
        //SET VIEW
        self.viewName.backgroundColor = .clear
        self.viewName.viewCorneRadius(radius: 5.0, isRound: false)
        self.viewName.viewBorderCorneRadius(borderColour: .secondary)

        
        //SET SUBMIT
        self.con_Submit.constant = manageWidth(size: 45.0)
        self.viewSubmit.backgroundColor = .secondaryTextView
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strSubmit)
    }
    
}



//MARK: - BUTTON ACTION
extension TimeClockLockViewController{

    
    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        
        if self.txtName.text == UserDefaults.standard.masterCode {
            UserDefaults.standard.useMasterCode = UserDefaults.standard.masterCode

            DispatchQueue.main.async {
                let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TIMECLOCK_MODEL, bundle: nil)
                if let newViewController = storyBoard.instantiateViewController(withIdentifier: "TimeClockViewController") as? TimeClockViewController{
                    self.navigationController?.pushViewController(newViewController, animated: true)
                }
            }
           
        }
        else{
            //CALL API
            self.getEmployeesStatusAPI(EmployeParameater: EmployeParameater(employee_id: "", temporary_code: self.txtName.text ?? ""))
        }
    }
}




//MARK: - KEYBORD DELEGATE
extension TimeClockLockViewController {
    
    @objc func keyboardWillShow(notification: NSNotification) {
       let keyboardHeight = (notification.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height
       print(keyboardHeight)
        self.con_SubmitBottom.constant = (keyboardHeight - GetBottomSafeAreaHeight()) + 16

    }

    @objc func keyboardWillHide(notification: NSNotification) {
       let keyboardHeight = (notification.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height
       print(keyboardHeight)
        self.con_SubmitBottom.constant = 20.0

    }
    
}




//MARK: -- UITEXTFIELD DELEGATE
extension TimeClockLockViewController : UITextFieldDelegate{
   
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        
        if  textField == self.txtName{
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
}
