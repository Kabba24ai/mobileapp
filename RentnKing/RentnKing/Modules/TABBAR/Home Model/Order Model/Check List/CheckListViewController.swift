//
//  CheckListViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 10/09/24.
//

import UIKit

protocol  CheckListDelegate : NSObject {
    func UpdateCheckListProduct(selectIndex: Int, arrUpdateProduct : [ProductModel])
}

class CheckListViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: CheckListDelegate?

    @IBOutlet weak var tblView: UITableView!
    @IBOutlet weak var con_Submit: NSLayoutConstraint!
    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!
    @IBOutlet weak var con_SubmitBottom : NSLayoutConstraint!

    @IBOutlet weak var lblTotalChargeTitle: UILabel!
    @IBOutlet weak var lblTotalCharge: UILabel!

    //LOADING
    let machinePlaceholderMarker = Placeholder()

    //OTHER
    var isLoading : Bool = true

    
    var objOrderData : OrdersModel!
    var arrProductList : [ProductModel] = []
    
    var selectIndex : Int = -1
    var strOrderID : String = ""
    var strProductID : String = ""

    var strTotalCharge : Float = 0.0
    
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
        setNavigationBarFor(controller: self, title: "Check List", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
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
        
        self.lblTotalChargeTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strTotalCheckList)
        self.lblTotalCharge.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "\(Application.currency)\(self.strTotalCharge)")

        //UPDATE DATA
        self.setCheckListData()
    }
    
    func stopLoading(){
        indicatorHide()
        self.CalculatTotalCharge()
        self.tblView.reloadData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.machinePlaceholderMarker.remove()
        }
    }
    
    
    func setCheckListData(){
        for i in 0..<self.objOrderData.arrProduct.count{
            var objProduct = self.objOrderData.arrProduct[i]
            
            for j in 0..<(objProduct.checkList?.arrQuestions?.count ?? 0){
                var objQuestion = objProduct.checkList?.arrQuestions?[j]

                //GET BALANCE
                var balance = (objQuestion?.objQuestion?.delivered ?? 0.0) - (objQuestion?.objQuestion?.returned ?? 0.0)
                if balance < 0{
                    balance = 0.0
                }

                //GET CUSTOMER OWES
                var customerOwes = balance * (objQuestion?.objQuestion?.question_value ?? 0)
                if customerOwes < 0{
                    customerOwes = 0.0
                }
                
                //SET DATA
                objQuestion?.objQuestion?.balance = balance
                objQuestion?.objQuestion?.customerOwes = customerOwes
                
                //UPDATE DATA
                objProduct.checkList?.arrQuestions?.remove(at: j)
                objProduct.checkList?.arrQuestions?.insert(objQuestion!, at: j)
            }
            
            //UPDATE DATA
            self.objOrderData.arrProduct.remove(at: i)
            self.objOrderData.arrProduct.insert(objProduct, at: i)
        }
        
        //RELOAD TABLE
        DispatchQueue.main.asyncAfter(deadline: .now()){
            self.CalculatTotalCharge()
            self.tblView.reloadData()
        }
        
    }
}



//MARK: - BUTTON ACTION
extension CheckListViewController {

    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if self.checkQustions() == false{
            showAlertMessage(strMessage: "Please enter delivered or returned")
        }
       
        else{
            //ADD ORDER LIST
//            let arrOrder = CoreDBManager.sharedDatabase.getOrderListData(strOrderID: self.strOrderID, strType: uploadType.hours.rawValue)
//            if arrOrder.count == 0{
//                CoreDBManager.sharedDatabase.saveOrderList(strOrderID: self.strOrderID, strType: uploadType.hours.rawValue) { _ in
//                }
//            }
            
            //GET HORES DATA
            let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderID, strType: uploadType.checkList.rawValue)
            if arrData.count != 0{
                CoreDBManager.sharedDatabase.deleteUploadData(strOrderID: self.strOrderID, strType: uploadType.checkList.rawValue) { isSave in
                    if isSave{
                        //SAVE IN TABLE
                        self.saveChecklistData(arrProduct: self.objOrderData.arrProduct)
                    }
                }
            }
            else{
                //SAVE IN TABLE
                self.saveChecklistData(arrProduct: self.objOrderData.arrProduct)
            }
            
            //CALL API
//            self.updateHours(arrHours: getMachineHoursArray())
        }
    }
    
    func saveChecklistData(arrProduct : [ProductModel]){
        let arrData = arrProduct
        if arrData.count != 0{
            let objData = arrData[0]
            
            //SAVE IN DATA BASE
            self.saveCheckList(arrProduct: arrProduct, arrQustion: objData.checkList?.arrQuestions ?? [], productID: "\(objData.product_id ?? 0)")

        }
        else{
            //SUCCESS m,m
            if self.selectIndex != -1{
                self.delegate?.UpdateCheckListProduct(selectIndex: self.selectIndex, arrUpdateProduct: self.objOrderData.arrProduct)
            }
            
            //UPLOAD LOCAL DATA
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0){
                GlobalMainConstants.appDelegate?.uploadAllData()
            }
            
            self.navigationController?.popViewController(animated: true)


            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                showAlertMessage(strMessage: "CheckList update successfully")
            }
        }
    }
    
    
    func saveCheckList(arrProduct : [ProductModel], arrQustion : [QuestionsListModel], productID : String){
        var arrProduct = arrProduct
        var arrData = arrQustion
        if arrData.count != 0{
            let objData = arrData[0]
            
            //SAVE IN DATA BASE
            CoreDBManager.sharedDatabase.saveUploadDataList(objSaveData: SaveImageVideoParameater(orderID: self.strOrderID, type: uploadType.checkList.rawValue, isImage: false, name: "", productID: productID, qustion_id: "\(objData.objQuestion?.id ?? 0)" , checklist_delivered: "\(objData.objQuestion?.delivered ?? 0)", checklist_returned: "\(objData.objQuestion?.returned ?? 0)", checklist_Value: "\(objData.objQuestion?.question_value ?? 0)")) { isSave in
                if isSave{
                    arrData.remove(at: 0)
                    self.saveCheckList(arrProduct: arrProduct, arrQustion: arrData, productID: productID)
                }
                else{
                    showAlertMessage(strMessage: "CheckList not update")
                }
            }
        }
        else{
            arrProduct.remove(at: 0)
            self.saveChecklistData(arrProduct: arrProduct)
        }
    }
    
    func checkQustions() -> Bool{
        for i in 0..<self.objOrderData.arrProduct.count{
            let objProduct = self.objOrderData.arrProduct[i]
            
            for j in 0..<(objProduct.checkList?.arrQuestions?.count ?? 0){
                let objQuestions = objProduct.checkList?.arrQuestions?[j]
                
                if objQuestions?.objQuestion?.delivered != 0 || objQuestions?.objQuestion?.returned != 0{
                    return true
                }
            }
        }
        
        return false
    }
    
}


//MARK: -- UITEXTFIELD DELEGATE
extension CheckListViewController : UITextFieldDelegate{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool{
        
        //RELOAD TABLE
        self.CalculatTotalCharge()
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
                    let section : Int = Int(textField.accessibilityValue ?? "") ?? 0
                    let index : Int = Int(textField.accessibilityLanguage ?? "") ?? 0

                    var objProduct = self.objOrderData.arrProduct[section]
                    var objdata = objProduct.checkList?.arrQuestions?[index]
                    
                    if textField.tag == 100{
                        objdata?.objQuestion?.delivered = Float(newString) ?? 0.0
                    }
                    else{
                        objdata?.objQuestion?.returned = Float(newString) ?? 0.0
                    }

                    //GET BALANCE
                    var balance = (objdata?.objQuestion?.delivered ?? 0.0) - (objdata?.objQuestion?.returned ?? 0.0)
                    if balance < 0{
                        balance = 0.0
                    }

                    //GET CUSTOMER OWES
                    var customerOwes = balance * (objdata?.objQuestion?.question_value ?? 0)
                    if customerOwes < 0{
                        customerOwes = 0.0
                    }
                    
                    
                    //SET DATA
                    objdata?.objQuestion?.balance = balance
                    objdata?.objQuestion?.customerOwes = customerOwes
                    
                    
                    //UPDATE
                    objProduct.checkList?.arrQuestions?.remove(at: index)
                    objProduct.checkList?.arrQuestions?.insert(objdata!, at: index)
                    
                    //UPDATE ARRAY
                    self.objOrderData.arrProduct.remove(at: section)
                    self.objOrderData.arrProduct.insert(objProduct, at: section)
                    
                    //UPDATE DATA
                    
                    //RELOAD TABLE
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                        self.CalculatTotalCharge()
                    }
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
    
    func CalculatTotalCharge(){
        self.strTotalCharge = 0.0
        
        for i in 0..<self.objOrderData.arrProduct.count{
            let objProduct = self.objOrderData.arrProduct[i]
            
            for j in 0..<(objProduct.checkList?.arrQuestions?.count ?? 0){
                let objQuestion = objProduct.checkList?.arrQuestions?[j]
                
                //SET TOTAL CHARGE
                self.strTotalCharge = self.strTotalCharge + (objQuestion?.objQuestion?.customerOwes ?? 0.0)
                
            }
        }
        
        //RELOAD TABLE
        self.lblTotalCharge.text = "\(Application.currency)\(self.strTotalCharge)"
    }
}




//MARK: -- UITABEL CELL --
class ProductCheckListCell : UITableViewCell{

    @IBOutlet weak var con_imgHeight: NSLayoutConstraint!
    @IBOutlet weak var imgProduct: UIImageView!

    @IBOutlet weak var lblProduct: UILabel!
    @IBOutlet weak var lblDate: UILabel!

   
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            imgProduct,
            lblProduct,
            lblDate
            
        ]
    }
}
class CheckListCell : UITableViewCell{

    @IBOutlet weak var lblTitle: UILabel!

    @IBOutlet weak var lblDelivered: UILabel!
    @IBOutlet weak var txtDelivered: UITextField!
    
    @IBOutlet weak var lblReturned: UILabel!
    @IBOutlet weak var txtReturned: UITextField!

    @IBOutlet weak var lblBalance: UILabel!
    @IBOutlet weak var txtBalance: UITextField!

    
    @IBOutlet weak var lblValue: UILabel!
    @IBOutlet weak var txtValue: UITextField!

    @IBOutlet weak var lblCustomerOwes: UILabel!
    @IBOutlet weak var txtCustomerOwes: UITextField!

    
    

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
            lblDelivered,
            txtDelivered,
            lblReturned,
            txtReturned,
            lblBalance,
            txtBalance,
            lblValue,
            txtValue,
            lblCustomerOwes,
            txtCustomerOwes
            
        ]
    }
}


//MARK: -- UITABEL DELEGATE --

extension CheckListViewController : UITableViewDelegate, UITableViewDataSource{
    
    //HEADER SECTION
    func numberOfSections(in tableView: UITableView) -> Int {
        if self.isLoading{
            return 1
        }
        else{
            return self.objOrderData.arrProduct.count
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        //SET HEADER HEIGHT
        if let cell = tableView.dequeueReusableCell(withIdentifier: "ProductCheckListCell") as? ProductCheckListCell{
            cell.backgroundColor = UIColor.background
            
            if self.objOrderData.arrProduct.count == 0{
                return nil
            }
            
            let  objProductDetails = self.objOrderData.arrProduct[section]

            //SET PRODUCT IMAGE
            cell.con_imgHeight.constant = manageWidth(size: 70)
            cell.imgProduct.viewCorneRadius(radius: 5, isRound: false)
            cell.imgProduct.setImage(strImg: objProductDetails.product_image ?? "")
            cell.imgProduct.backgroundColor = .white
            
            
            //SET FONT
            cell.lblProduct.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "\(objProductDetails.product_name ?? "") * \(objProductDetails.qty )")
            
            //SET SCHEDULE DATE
            cell.lblDate.text = ""
            let strDate = setFontAttributes(str: str.sttScheduleDate, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0)
            strDate.append(setFontAttributes(str: " \( objProductDetails.product_options.deldate ?? "")", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0))
            cell.lblDate.attributedText = strDate
            
            return cell
        }
        
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if self.isLoading{
            return 0
        }
        else{
            return manageWidth(size: 100)
        }
    }
    
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isLoading{
            return 2
        }
        else{
            if self.objOrderData.arrProduct.count != 0{
                return self.objOrderData.arrProduct[section].checkList?.arrQuestions?.count ?? 0
            }
            else{
                return 0
            }
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
      
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "CheckListCell") as? CheckListCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.isHidden = false

            if isLoading {
                cell.viewLine.isHidden = true
                self.machinePlaceholderMarker.register(cell.getAnimableSubviews())
                self.machinePlaceholderMarker.startAnimation()
                return cell
            }
            
            if self.objOrderData.arrProduct.count == 0 {
                return cell
            }
            
            if self.objOrderData.arrProduct[indexPath.section].checkList?.arrQuestions?.count == 0 {
                return cell
            }
            
            let  objDetails = self.objOrderData.arrProduct[indexPath.section].checkList?.arrQuestions?[indexPath.row]
                        

            cell.lblTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: objDetails?.objQuestion?.question ?? "")

            
            cell.lblDelivered.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strDelivered)
            cell.txtDelivered.configureText(textAlignment: .center, keyboardTye: .numbersAndPunctuation, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: objDetails?.objQuestion?.delivered ?? 0 == 0 ? "" : "\(objDetails?.objQuestion?.delivered ?? 0.0)", placeholder: "0.0")
            cell.txtDelivered.accessibilityValue = "\(indexPath.section)"
            cell.txtDelivered.tag = 100
            cell.txtDelivered.accessibilityLanguage = "\(indexPath.row)"
            cell.txtDelivered.delegate = self
            
            cell.lblReturned.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strReturned)
            cell.txtReturned.configureText(textAlignment: .center, keyboardTye: .numbersAndPunctuation, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: objDetails?.objQuestion?.returned ?? 0 == 0 ? "" : "\(objDetails?.objQuestion?.returned ?? 0)", placeholder: "0.0")
            cell.txtReturned.accessibilityValue = "\(indexPath.section)"
            cell.txtReturned.tag = 101
            cell.txtReturned.accessibilityLanguage = "\(indexPath.row)"
            cell.txtReturned.delegate = self
            
            
            cell.lblBalance.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strBalance)
            cell.txtBalance.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(objDetails?.objQuestion?.balance ?? 0)", placeholder: "0.0")
            cell.txtBalance.delegate = self

            
            cell.lblValue.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strValue)
            cell.txtValue.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(objDetails?.objQuestion?.question_value ?? 0)", placeholder: "0")
            cell.txtValue.delegate = self
            
            
            cell.lblCustomerOwes.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: str.strCustomerOwes)
            cell.txtCustomerOwes.configureText(textAlignment: .center, keyboardTye: .numberPad, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(Application.currency)\(objDetails?.objQuestion?.customerOwes ?? 0)", placeholder: "0")
            cell.txtCustomerOwes.delegate = self
            
        
//           
//            
//            cell.viewTotalCharge.viewBorderCorneRadius(borderColour: .clear)
//            cell.viewTotalChargeLine.isHidden = false
//            cell.txtTotalCharge.textColor = .primary
//            if objDetails.total_cost ?? 0 > 0{
//                cell.viewTotalChargeLine.isHidden = true
//                cell.viewTotalCharge.viewBorderCorneRadius(borderColour: .redText)
//                cell.txtTotalCharge.textColor = .redText
//            }
//            else{
//                cell.viewTotalChargeLine.isHidden = false
//                cell.viewTotalCharge.viewBorderCorneRadius(borderColour: .clear)
//                cell.txtTotalCharge.text = "\(Application.currency)0"
//                cell.txtTotalCharge.textColor = .primary
//            }
            return cell
        }

        return UITableViewCell()
        
    }
    

    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
      
    }
}





//MARK: - KEYBORD DELEGATE
extension CheckListViewController {
    
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
        self.CalculatTotalCharge()
        self.tblView.reloadData()

    }
}

