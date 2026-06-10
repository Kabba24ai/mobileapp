//
//  LicenseTypeViewController.swift
//  RentnKing
//
//  Created by DEEPAK JAIN on 09/04/26.
//

import UIKit

class LicenseTypeViewController: UIViewController, UIGestureRecognizerDelegate {

    //CONSTANT
    @IBOutlet weak var tblView: UITableView!

    @IBOutlet weak var con_Btn: NSLayoutConstraint!
    @IBOutlet weak var lblSubmit : UILabel!
    @IBOutlet weak var viewSubmit: UIView!
    
    @IBOutlet weak var lblTopText: UILabel!
    
    @IBOutlet weak var viewLicenseType: UIView!
    @IBOutlet weak var txtLicenseType: UITextField!
    @IBOutlet weak var lblLicenseType: UILabel!
    
    @IBOutlet weak var lblLicenseExpiratation: UILabel!

    @IBOutlet weak var viewMonth: UIView!
    @IBOutlet weak var txtMonth: UITextField!

    @IBOutlet weak var viewYear: UIView!
    @IBOutlet weak var txtYear: UITextField!

    var imgFront = UIImage()
    var imgBack = UIImage()
    var strOrderID : String = ""
    var selectIndex : Int = -1
    var strSelectedEmpID = ""
    var arrEmployesList : [EmployeesModel] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboard(true)
        // Do any additional setup after loading the view.
        
        //SET IMAGE
        let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderID, strType: uploadType.image.rawValue)
        if arrData.count != 0 {

            //FRONT
            if let indx = arrData.firstIndex(where: { dic_upload in
                return dic_upload.image_side == "front"
            }) {
                let empID = arrData[indx].auto_inject_by
                let expData = arrData[indx].license_expiry_date
            }
            else {
                if arrData.count != 0 {
                    let empID = arrData[0].auto_inject_by
                    let expData = arrData[0].license_expiry_date
                }
            }
            
            //BACK
            if let indx = arrData.firstIndex(where: { dic_upload in
                return dic_upload.image_side == "back"
            }) {
                let empID = arrData[indx].auto_inject_by
                let expData = arrData[indx].license_expiry_date
            }
            else {
                if arrData.count > 1 {
                    let empID = arrData[1].auto_inject_by
                    let expData = arrData[1].license_expiry_date
                }
            }
        }
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
        setNavigationBarFor(controller: self, title: str.strUploadLicense, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)
            
        } rightActionHandler: {
        }
        
        //SET THE VIEW
        self.setTheView()
        
        
        //GET EMPLOYEE LIST DATA
        getEmployeeList { arr_data in
            self.arrEmployesList = arr_data
        }
    }
    
    //SET THE VIEW
    func setTheView() {

        //SET LABLE
        self.lblTopText.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 15.0, text: str.strLicenseTypeTopText)
        
        self.lblLicenseType.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: str.strSelectEmployess, numberOfLines: 1)
        self.txtLicenseType.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "", placeholder: str.strSelectEmployess)
        
        self.lblLicenseExpiratation.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "License Expiration", numberOfLines: 1)
        
        self.txtMonth.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "", placeholder: "Month")
        self.txtYear.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "", placeholder: "Year")
        
        //SET VIEW
        self.viewLicenseType.setTheTextView(bgColor: .secondary )
        self.viewMonth.setTheTextView(bgColor: .secondary )
        self.viewYear.setTheTextView(bgColor: .secondary )

        self.viewSubmit.backgroundColor = .secondaryTextView
 
        //SET CONSTANT
        self.con_Btn.constant = manageWidth(size: 45)
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strSubmit)

        
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

extension LicenseTypeViewController {
    
    @IBAction func btnSelectEmployessClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        if self.arrEmployesList.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: "Select Employee", arrData: self.arrEmployesList.compactMap { $0.name}, selectValue: "") { index, selectValue in
            
            //UPDATE DATA
            self.txtLicenseType.text = self.arrEmployesList[index].name
            self.strSelectedEmpID = "\(self.arrEmployesList[index].id ?? 0)"
        }
    }
    
    @IBAction func btnSelectMonthClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        let formatter = DateFormatter()
        let arrMonth = formatter.shortMonthSymbols ?? []
        
        actionPicker(sender, strTitle: "Select Month", arrData: arrMonth, selectValue: "") { index, selectValue in
            
            //UPDATE DATA
            self.txtMonth.text = selectValue
        }
    }
    
    @IBAction func btnSelectYearClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        let currentYear = Calendar.current.component(.year, from: Date())

        // Create year array (current year → next 50 years)
        let arrYear = (0...50).map { "\(currentYear + $0)" }
        
        actionPicker(sender, strTitle: "Select Year", arrData: arrYear, selectValue: "") { index, selectValue in
            self.txtYear.text = selectValue
        }
    }
    
    
    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        let strEmployee = self.txtLicenseType.text ?? ""
        let strMonth = self.txtMonth.text ?? ""
        let strYear = self.txtYear.text ?? ""
        
        if strEmployee == "" {
            showAlertMessage(strMessage: "Please select license employee type.")
        }
        else if strMonth == "" {
            showAlertMessage(strMessage: "Please select month.")
        }
        else if strYear == "" {
            showAlertMessage(strMessage: "Please select year.")
        }
        else {
            //CALL API
            if self.saveImage(image: self.imgFront, orderID: self.strOrderID, imgName: "front") {
                print("save")
                
                if self.saveImage(image: self.imgBack, orderID: self.strOrderID, imgName: "back") {
                    
                    let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderID, strType: uploadType.image.rawValue)
                    if arrData.count != 0 {
                        CoreDBManager.sharedDatabase.deleteUploadData(strOrderID: self.strOrderID, strType: uploadType.image.rawValue) { isSave in
                            self.setLicenseData()
                        }
                    }
                    else{
                        self.setLicenseData()
                        
                    }
                }
            }
        }
    }
    
    
    func saveImage(image: UIImage, orderID : String, imgName : String) -> Bool {
        guard let data = image.jpegData(compressionQuality: 1) ?? image.pngData() else {
            return false
        }
      
        do {
            try data.write(to: LicenseUploadDirectory.appendingPathComponent("\(orderID)_\(imgName).png"))
            return true
        } catch {
            print(error.localizedDescription)
            return false
        }
    }
    
    func setLicenseData() {
        var strExpDate = ""
        let strMonth = self.txtMonth.text ?? ""
        let strYear = self.txtYear.text ?? ""
        
        if let result = formattedDate(month: strMonth, year: strYear) {
            strExpDate = result
        }
        
        //SAVE IN DATA BASE
        CoreDBManager.sharedDatabase.saveUploadDataList(objSaveData: SaveImageVideoParameater(orderID: self.strOrderID, type: uploadType.image.rawValue, isImage: true, name: "\(self.strOrderID)_front.png", image_side: "front", license_expiry_date: strExpDate, auto_inject_by: self.strSelectedEmpID)) { isSave in
            if isSave{
                CoreDBManager.sharedDatabase.saveUploadDataList(objSaveData: SaveImageVideoParameater(orderID: self.strOrderID, type: uploadType.image.rawValue, isImage: true, name: "\(self.strOrderID)_back.png", image_side: "back", license_expiry_date: strExpDate, auto_inject_by: self.strSelectedEmpID)) { isSave in
                    if isSave{
                        
                        showAlertMessage(strMessage: "License updated successfully.")

                        //UPLOAD LOCAL DATA
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0){
                            GlobalMainConstants.appDelegate?.uploadAllData()
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                            
                            if let targetViewController = self.navigationController?.viewControllers.first(where: { $0 is OrderListViewController || $0 is OrderDetailsViewController  }) {
                                (targetViewController as? OrderListViewController)?.linceUploadSucess(selectIndex: self.selectIndex, arrImage: [])
                                (targetViewController as? OrderDetailsViewController)?.linceUploadSucess(selectIndex: self.selectIndex, arrImage: [])
                                self.navigationController?.popToViewController(targetViewController, animated: true)
                            }
                            
                        }
                    }
                }
            }
        }
    }
}
