//
//  MachineHoursViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 08/02/24.
//

import UIKit

protocol  MachineHoursDelegate : NSObject {
    func UpdateMachinHours(selectIndex: Int, arrUpdateMachinHours : [MachineHoursModel])
}

class MachineHoursViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: MachineHoursDelegate?

    @IBOutlet weak var tblView: UITableView!
    @IBOutlet weak var con_Submit: NSLayoutConstraint!
    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!
    @IBOutlet weak var con_SubmitBottom : NSLayoutConstraint!

    
    //LOADING
    let machinePlaceholderMarker = Placeholder()

    //OTHER
    var isLoading : Bool = true

    
    var objOrderData : OrdersModel!
    var arrProductList : [ProductModel] = []
    
    var selectIndex : Int = -1
    var strOrderID : String = ""
    var strProductID : String = ""

    override func viewDidLoad() {
        super.viewDidLoad()
//        setupCutomeKeyboard()
        // Do any additional setup after loading the view.
        setupKeyboard(false)

        
        //CALL API
        self.viewSubmit.isHidden = true
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID, product_id: self.strProductID))
        
        
        
        //KEYBOARD METHOD
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification , object:nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification , object:nil)

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
        setNavigationBarFor(controller: self, title: "Machine Hours", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)
            
            
        } rightActionHandler: {
            
            
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        setupKeyboard(true)
    }
    
    func setTheView(){
        self.isLoading = false
        indicatorHide()
        self.stopLoading()

        //SET SUBMIT
        self.viewSubmit.isHidden = false
        self.con_Submit.constant = manageWidth(size: 45.0)
        self.viewSubmit.backgroundColor = .secondaryTextView
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strSubmit)
    }
    
    func stopLoading(){
        indicatorHide()
        self.tblView.reloadData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.machinePlaceholderMarker.remove()
        }
    }
}



//MARK: - BUTTON ACTION
extension MachineHoursViewController {

    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if chekcAddHours() == false{
            showAlertMessage(strMessage: "Please enter start or end hours")
        }
       
        else{
            //ADD ORDER LIST
//            let arrOrder = CoreDBManager.sharedDatabase.getOrderListData(strOrderID: self.strOrderID, strType: uploadType.hours.rawValue)
//            if arrOrder.count == 0{
//                CoreDBManager.sharedDatabase.saveOrderList(strOrderID: self.strOrderID, strType: uploadType.hours.rawValue) { _ in
//                }
//            }
            
            //GET HORES DATA
            let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderID, strType: uploadType.hours.rawValue)
            if arrData.count != 0{
                CoreDBManager.sharedDatabase.deleteUploadData(strOrderID: self.strOrderID, strType: uploadType.hours.rawValue) { isSave in
                    if isSave{
                        //SAVE IN TABLE
                        self.saveHoursData(arr: self.objOrderData.arrMachineHours)
                    }
                }
            }
            else{
                //SAVE IN TABLE
                self.saveHoursData(arr: self.objOrderData.arrMachineHours)
            }
            
            //CALL API
//            self.updateHours(arrHours: getMachineHoursArray())
        }
    }
    
    func saveHoursData(arr : [MachineHoursModel]){
        var arrData = arr
        if arrData.count != 0{
            let objData = arrData[0]
            
            //SAVE IN DATA BASE
            CoreDBManager.sharedDatabase.saveUploadDataList(objSaveData: SaveImageVideoParameater(orderID: self.strOrderID, type: uploadType.hours.rawValue, isImage: false, name: "", allocated: "\(objData.allocated ?? 0)", end: "\(objData.end ?? 0)", over: "\(objData.additinal ?? 0)", over_rate: "\(objData.price ?? 0)", productID: "\(objData.product_id ?? 0)", start: "\(objData.start ?? 0)", total: "\(objData.total ?? 0)", total_cost: "\(objData.total_cost ?? 0)")) { isSave in
                if isSave{
                    arrData.remove(at: 0)
                    self.saveHoursData(arr: arrData)
                }
                else{
                    showAlertMessage(strMessage: "Machine Hours not update")
                }
            }
        }
        else{
            //SUCCESS m,m
            if self.selectIndex != -1{
                self.delegate?.UpdateMachinHours(selectIndex: self.selectIndex, arrUpdateMachinHours: self.objOrderData.arrMachineHours)
            }
            
            //UPLOAD LOCAL DATA
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0){
                GlobalMainConstants.appDelegate?.uploadAllData()
            }
            
            showAlertMessage(strMessage: "Machine Hours update successfully")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                self.navigationController?.popViewController(animated: true)
            }
        }
    }
    
    func chekcAddHours() -> Bool{
        for objData in self.objOrderData.arrMachineHours{
            if objData.start != 0 || objData.end != 0{
                return true
            }
        }
        return false
    }
    
}


//MARK: -- UITEXTFIELD DELEGATE
extension MachineHoursViewController : UITextFieldDelegate{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool{
        
        //RELOAD TABLE
        self.tblView.reloadData()
        
        return true
    }
    

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        if textField.tag == 100 || textField.tag == 101{
            let inverseSet = NSCharacterSet(charactersIn:"0123456789.").inverted
            let components = string.components(separatedBy: inverseSet)
            let filtered = components.joined(separator: "")
            
            if filtered == string {
                guard let text = textField.text else { return false }
                var newString = (text as NSString).replacingCharacters(in: range, with: string)
                newString = newString.replacingOccurrences(of: "\(Application.currency)", with: "")
                

                let countdots = newString.components(separatedBy: ".").count - 1
                if countdots <= 1
                {
                    let index : Int = Int(textField.accessibilityLanguage ?? "") ?? 0
                    var objdata = self.objOrderData.arrMachineHours[index]
                    
                    if textField.tag == 100{
                        objdata.start = Float(newString) ?? 0.0
                    }
                    else{
                        objdata.end = Float(newString) ?? 0.0
                    }

                    //UPDATE ARRAY
                    self.objOrderData.arrMachineHours.remove(at: index)
                    self.objOrderData.arrMachineHours.insert(objdata, at: index)
                    
                    //CALCULATE HOURS
                    self.calculateHours(index : index)
                }
                else{
                    return false
                }
                
                
                return true
                
            } else {
                return false
            }
        }
        else{
            return true
        }
    }
    
   
    
    
    func calculateHours(index : Int){
        var objdata = self.objOrderData.arrMachineHours[index]

        //SET TOTLA HOURS
        let hours = Float(objdata.end ?? 0) - Float(objdata.start ?? 0)
        let totalHours = Int(hours.rounded(.up))
        objdata.total = 0
        if totalHours > 0{
            //SET TOTAL HOURS
            objdata.total = Float(totalHours)
        }
        
        
        //SET ADDITION HOURS
        var additionslHours = totalHours - (objdata.allocated ?? 0)
        objdata.additinal = 0
        if additionslHours > 0{
            //SET TOTAL HOURS
            objdata.additinal = Int(Float(additionslHours))
        }
        else{
            additionslHours = 0
        }
        
        
        //SET TOTAL CHARGE
        let totalCharge = Float(additionslHours) * Float(objdata.price ?? 0)
        objdata.total_cost = totalCharge

        
        //UPDATE ARRAY
        self.objOrderData.arrMachineHours.remove(at: index)
        self.objOrderData.arrMachineHours.insert(objdata, at: index)
            
        
        //RELAOD ABLE
//        self.tblView.reloadData()
    }
}




//MARK: -- UITABEL CELL --
class MachineHoursListCell : UITableViewCell{

    @IBOutlet weak var con_imgHeight: NSLayoutConstraint!
    @IBOutlet weak var imgProduct: UIImageView!

    @IBOutlet weak var lblProduct: UILabel!
    @IBOutlet weak var lblDate: UILabel!

    @IBOutlet weak var lblStartHours: UILabel!
    @IBOutlet weak var txtStartHours: UITextField!
    
    @IBOutlet weak var lblAllocatedHours: UILabel!
    @IBOutlet weak var txtAllocatedHours: UITextField!

    @IBOutlet weak var lblEndHours: UILabel!
    @IBOutlet weak var txtEndHours: UITextField!

    @IBOutlet weak var lblTotalHours: UILabel!
    @IBOutlet weak var txtTotalHours: UITextField!

    @IBOutlet weak var lblAdditionalHours: UILabel!
    @IBOutlet weak var txtAdditionalHours: UITextField!

    @IBOutlet weak var lblHoursFee: UILabel!
    @IBOutlet weak var txtHoursFee: UITextField!

    @IBOutlet weak var lblTotalCharge: UILabel!
    @IBOutlet weak var txtTotalCharge: UITextField!
    @IBOutlet weak var viewTotalCharge: UIView!
    @IBOutlet weak var viewTotalChargeLine: UIView!

    @IBOutlet weak var viewLine: UIView!

    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            imgProduct,
            lblProduct,
            lblDate,
            lblStartHours,
            txtStartHours,
            lblAllocatedHours,
            txtAllocatedHours,
            lblEndHours,
            txtEndHours,
            lblTotalHours,
            txtTotalHours,
            lblAdditionalHours,
            txtAdditionalHours,
            lblHoursFee,
            txtHoursFee,
            lblTotalCharge,
            txtTotalCharge,
            viewTotalCharge
            
        ]
    }
}


//MARK: -- UITABEL DELEGATE --

extension MachineHoursViewController : UITableViewDelegate, UITableViewDataSource{
    
    //HEADER SECTION
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isLoading{
            return 5
        }
        else{
            return self.objOrderData.arrMachineHours.count
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if isLoading{
            return UITableView.automaticDimension
        }
        else{
            let  objDetails = self.objOrderData.arrMachineHours[indexPath.row]
            if self.objOrderData.arrProduct.firstIndex(where: { $0.product_id == objDetails.product_id }) != nil{
                return UITableView.automaticDimension
            }
            else{
                return 0
            }
        }
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "MachineHoursListCell") as? MachineHoursListCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.isHidden = false

            if isLoading {
                cell.viewLine.isHidden = true
                self.machinePlaceholderMarker.register(cell.getAnimableSubviews())
                self.machinePlaceholderMarker.startAnimation()
                return cell
            }
            
            let  objDetails = self.objOrderData.arrMachineHours[indexPath.row]
            
            if let index = self.objOrderData.arrProduct.firstIndex(where: { $0.product_id == objDetails.product_id }){
                let  objProductDetails = self.objOrderData.arrProduct[index]

                //SET PRODUCT IMAGE
                cell.con_imgHeight.constant = manageWidth(size: 70)
                cell.imgProduct.viewCorneRadius(radius: 5, isRound: false)
                cell.imgProduct.setImage(strImg: objProductDetails.product_image ?? "")
                cell.imgProduct.backgroundColor = .white


                //SET FONT
                cell.lblProduct.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "\(objProductDetails.product_name ?? "") * \(objProductDetails.qty )")
                
                //SET SCHEDULE DATE
                cell.lblDate.text = ""
                if objProductDetails.product_options != nil{
                    let strDate = setFontAttributes(str: str.sttScheduleDate, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0)
                    strDate.append(setFontAttributes(str: " \( objProductDetails.product_options.deldate ?? "")", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0))
                    cell.lblDate.attributedText = strDate
                }
            }

         
            
            cell.lblStartHours.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strStartHourse)
            cell.txtStartHours.configureText(textAlignment: .center, keyboardTye: .numbersAndPunctuation, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: objDetails.start ?? 0 == 0 ? "" : "\(objDetails.start ?? 0.0)", placeholder: "0.0")
            cell.txtStartHours.tag = 100
            cell.txtStartHours.accessibilityLanguage = "\(indexPath.row)"
            cell.txtStartHours.delegate = self
            
            cell.lblAllocatedHours.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strAllocatedHourse)
            cell.txtAllocatedHours.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(objDetails.allocated ?? 0)", placeholder: "0")
            cell.txtAllocatedHours.delegate = self

            
            cell.lblEndHours.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strEndtHourse)
            cell.txtEndHours.configureText(textAlignment: .center, keyboardTye: .numbersAndPunctuation, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: objDetails.end ?? 0 == 0 ? "" : "\(objDetails.end ?? 0)", placeholder: "0.0")
            cell.txtEndHours.tag = 101
            cell.txtEndHours.accessibilityLanguage = "\(indexPath.row)"
            cell.txtEndHours.delegate = self
            
            cell.lblTotalHours.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strTotalHourse)
            cell.txtTotalHours.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(objDetails.total ?? 0)", placeholder: "0")
            cell.txtTotalHours.delegate = self
            
            cell.lblAdditionalHours.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strAdditionalHourse)
            cell.txtAdditionalHours.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(objDetails.additinal ?? 0)", placeholder: "0")
            cell.txtAdditionalHours.delegate = self
            
            cell.lblHoursFee.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strHourseFee)
            cell.txtHoursFee.configureText(textAlignment: .center, keyboardTye: .numbersAndPunctuation, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(Application.currency)\(objDetails.price ?? 0)", placeholder: "\(Application.currency)0")
            cell.txtHoursFee.delegate = self
            
            cell.lblTotalCharge.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strTotalCharge)
            cell.txtTotalCharge.configureText(textAlignment: .center, keyboardTye: .numbersAndPunctuation, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(Application.currency)\(objDetails.total_cost ?? 0)", placeholder: "\(Application.currency)0")
            cell.txtTotalCharge.delegate = self
            cell.viewTotalCharge.backgroundColor = .clear
//            cell.viewTotalChargeLine.isHidden = false
//            self.setTotlaCharges()
            
            cell.viewTotalCharge.viewBorderCorneRadius(borderColour: .clear)
            cell.viewTotalChargeLine.isHidden = false
            cell.txtTotalCharge.textColor = .primary
            if objDetails.total_cost ?? 0 > 0{
                cell.viewTotalChargeLine.isHidden = true
                cell.viewTotalCharge.viewBorderCorneRadius(borderColour: .redText)
                cell.txtTotalCharge.textColor = .redText
            }
            else{
                cell.viewTotalChargeLine.isHidden = false
                cell.viewTotalCharge.viewBorderCorneRadius(borderColour: .clear)
                cell.txtTotalCharge.text = "\(Application.currency)0"
                cell.txtTotalCharge.textColor = .primary
            }
            return cell
        }

        return UITableViewCell()
        
    }
    

    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
      
    }
}





//MARK: - KEYBORD DELEGATE
extension MachineHoursViewController {
    
    @objc func keyboardWillShow(notification: NSNotification) {
       let keyboardHeight = (notification.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height
       print(keyboardHeight)
        self.con_SubmitBottom.constant = (keyboardHeight - GetBottomSafeAreaHeight()) + 16

    }

    @objc func keyboardWillHide(notification: NSNotification) {
       let keyboardHeight = (notification.userInfo![UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue.height
       print(keyboardHeight)
        self.con_SubmitBottom.constant = 16.0

        //RELOAD TABLE
        self.tblView.reloadData()

    }
}

