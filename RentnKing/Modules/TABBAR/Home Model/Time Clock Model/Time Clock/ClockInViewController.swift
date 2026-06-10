//
//  ClockInViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 25/09/24.
//

import UIKit

class ClockInViewController: UIViewController, UIGestureRecognizerDelegate {

    @IBOutlet weak var lblTitle: UILabel!
    @IBOutlet weak var lblCurrentTime: UILabel!
    @IBOutlet weak var lblLastTime: UILabel!
    @IBOutlet weak var lblShiftTime: UILabel!

    @IBOutlet weak var viewStatus: UIView!
    @IBOutlet weak var txtStatus: UITextField!

    @IBOutlet weak var con_Submit: NSLayoutConstraint!
    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!

    
    var objData : EmployeesModel!
    var arrNextStatus : [EmpStatusModel] = []
    var selectStatusCode : String = ""
    var strLastTime : String = ""
    var strLastStatus : String = ""
    var strCurrentDate : String = ""
    var strShiftTime : String = ""
    var arrStatusList : [EmpStatusModel] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
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
        setNavigationBarForButtons(controller: self, title: str.strUpdateStatus, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: [], isFilter: false) {
            setupKeyboard(true)

            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in
        }
        

        
        //SET VIEW
        self.setTheView()
    }

    func setTheView(){
   
        
        //SET FONT
        self.lblTitle.configureLable(textAlignment: .center, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: "Welcome back \(self.objData.name ?? "")")

        self.lblShiftTime.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "Shift Schedule : \(self.strShiftTime)")
        self.lblCurrentTime.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "Current : \(self.strCurrentDate)")
//        self.lblLastTime.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 45.0, text: self.strLastTime == "" ? "-" : self.strLastTime)

        self.txtStatus.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 18.0, text: "", placeholder: str.strChangeStatus)
        
        //SET VIEW
        self.viewStatus.backgroundColor = .clear
        self.viewStatus.viewCorneRadius(radius: 5.0, isRound: false)
        self.viewStatus.viewBorderCorneRadius(borderColour: .secondary)

        //SET SUBMIT
        self.con_Submit.constant = manageWidth(size: 45.0)
        self.viewSubmit.backgroundColor = .secondaryTextView
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strSubmit)
        
    }

}



//MARK: - BUTTON ACTION
extension ClockInViewController{
    
    
    @IBAction func btnSelectStatusClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if self.arrNextStatus.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: "Select Status", arrData: self.arrNextStatus.compactMap { $0.status_name}, selectValue: self.txtStatus.text ?? "") { index, selectValue in
           
            self.txtStatus.text = selectValue
            self.selectStatusCode = self.arrNextStatus[index].status_code ?? ""
        
        }
    }
    
    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        if self.selectStatusCode != ""{
            self.updateEmployeesStatusAPI(EmployeParameater: EmployeParameater(employee_id: "\(self.objData.id ?? 0)", status_code: self.selectStatusCode, comment: ""))
        }
        else{
            showAlertMessage(strMessage: "Please select a status.")
        }
    }
}




//MARK: -- TABLE CELL --
class StatusListCell : UITableViewCell{
    @IBOutlet weak var lblStatus: UILabel!
    @IBOutlet weak var lblTime: UILabel!
}

//MARK: -- UITABEL DELEGATE --

extension ClockInViewController : UITableViewDelegate, UITableViewDataSource{
    
    //HEADER SECTION
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.arrStatusList.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "StatusListCell") as? StatusListCell{
            cell.backgroundColor = UIColor.clear
            
            if self.arrStatusList.count == 0{
                return cell
            }
            
            //GET DATA
            let objData = self.arrStatusList[indexPath.row]
            
            
            //SET FONT
            cell.lblStatus.configureLable(textAlignment: .left, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18, text: "- \(objData.status_name ?? "")")
            cell.lblTime.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: objData.created_date ?? "")
            
            
            cell.layoutIfNeeded()
            return cell
            
        }
        return UITableViewCell()
    }
}
