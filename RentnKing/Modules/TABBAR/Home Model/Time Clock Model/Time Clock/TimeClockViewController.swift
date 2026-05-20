//
//  TimeClockViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 25/09/24.
//

import UIKit
import CoreActionSheetPicker
class TimeClockViewController: UIViewController, UIGestureRecognizerDelegate {

    @IBOutlet weak var viewName: UIView!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var txtName: UITextField!

    @IBOutlet weak var viewEmpIDMain: UIView!
    @IBOutlet weak var viewEmpID: UIView!
    @IBOutlet weak var lblEmpID: UILabel!
    @IBOutlet weak var txtEmpID: UITextField!

    @IBOutlet weak var con_Submit: NSLayoutConstraint!
    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!
    @IBOutlet weak var con_SubmitBottom : NSLayoutConstraint!

    var arrStatusList : [EmpStatusModel] = []
    var arrEmployesList : [EmployeesModel] = []
    var selectIndex : Int = 0
    var selectTeamID : Int = 0
    var selectEmpCode : String = ""

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
        setNavigationBarForButtons(controller: self, title: str.strTimeClock, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: ["icon_logout"], isFilter: false) {
            setupKeyboard(true)

            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in
            if SelectTag == 0{
                
                //CALL API
                let alert = UIAlertController(title: Application.appName, message: "Are you sure you want to logout with Master Code?", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                    //REMOVE CODE
                    UserDefaults.standard.useMasterCode = ""

                    DispatchQueue.main.async {
                        //BACK SCREE
                        self.navigationController?.popViewController(animated: true)
                    }

               
                }))
                alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
                self.present(alert, animated: true)
            }
        }
        
        //CALL API
        self.selectTeamID = 0
        self.getEmployeesListAPI()
        self.getStatusAPI()
        
        //SET VIEW
        self.setTheView()
    }

    
    func setTheView(){
   
        
        //SET FONT
        self.lblName.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strTeamName)
        self.txtName.configureText(bgColour: .clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: "", placeholder: str.strSelectTeamName)
     
        self.lblEmpID.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strMemberID)
        self.txtEmpID.configureText(keyboardTye: .numberPad, bgColour: .clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: "", placeholder: str.strSelectMemberID)
        self.txtEmpID.delegate = self
        
        //SET VIEW
        self.viewName.backgroundColor = .clear
        self.viewName.viewCorneRadius(radius: 5.0, isRound: false)
        self.viewName.viewBorderCorneRadius(borderColour: .secondary)

        self.viewEmpID.backgroundColor = .clear
        self.viewEmpID.viewCorneRadius(radius: 5.0, isRound: false)
        self.viewEmpID.viewBorderCorneRadius(borderColour: .secondary)
        
        //SET SUBMIT
        self.con_Submit.constant = manageWidth(size: 45.0)
        self.viewSubmit.backgroundColor = .secondaryTextView
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strSubmit)

        
        //SET EMP VIEW
        self.setEmpView()
        
        #if DEBUG
//        self.txtEmpID.text = "841164"
        #endif
    }
    
    
    func setEmpView(){
        self.viewEmpIDMain.isHidden = true
        self.viewSubmit.isHidden = true
        
        if self.selectTeamID != 0{
            self.viewEmpIDMain.isHidden = false
            self.viewSubmit.isHidden = false
        }
    }
    
}



//MARK: - BUTTON ACTION
extension TimeClockViewController{
    
    @IBAction func btnSelectMemberClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if self.arrEmployesList.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: "Select Store", arrData: self.arrEmployesList.compactMap { $0.name}, selectValue: self.txtName.text ?? "") { index, selectValue in
           
            self.txtName.text = selectValue
            self.selectTeamID = self.arrEmployesList[index].id ?? 0
            self.selectEmpCode = self.arrEmployesList[index].employee_code ?? ""
            self.selectIndex = index
            
            DispatchQueue.main.asyncAfter(deadline: .now()){
                self.txtEmpID.becomeFirstResponder()
            }
            
            //SET EMP VIEW
            self.setEmpView()
        }
    }
    
    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        //CHECK VALIDATION
        let strEmID = self.txtEmpID.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

        
        if self.selectTeamID != 0 {
            

            if strEmID != ""{
                self.getEmployeesStatusAPI(EmployeParameater: EmployeParameater(employee_id: "\(self.selectTeamID)", temporary_code: self.txtEmpID.text ?? ""))
            }
            else{
                showAlertMessage(strMessage: "Please enter member id")
            }
        }

    }
}




//MARK: - KEYBORD DELEGATE
extension TimeClockViewController {
    
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
extension TimeClockViewController : UITextFieldDelegate{
   
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        
        if  textField == self.txtEmpID{
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
