//
//  OrderDetailsViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 15/02/24.
//

import UIKit
import MessageUI

class OrderDetailsViewController: UIViewController, UIGestureRecognizerDelegate {

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!

    @IBOutlet weak var viewBilling: UIView!
    @IBOutlet weak var lblBillingInfo: UILabel!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var lblNumber: UILabel!
    @IBOutlet weak var imgCall: UIImageView!
    @IBOutlet weak var lblEmail: UILabel!
    @IBOutlet weak var lblAddress: UILabel!

    @IBOutlet weak var imgEditAddress: UIImageView!
    @IBOutlet weak var imgMapAddress: UIImageView!

    @IBOutlet weak var lblProductTitle: UILabel!

    @IBOutlet weak var lblSubAmount: UILabel!
    @IBOutlet weak var lblSubAmountPrice: UILabel!

    @IBOutlet weak var lblTax: UILabel!
    @IBOutlet weak var lblTaxPrice: UILabel!

    @IBOutlet weak var lblTotalAmount: UILabel!
    @IBOutlet weak var lblTotlaPrice: UILabel!

    @IBOutlet weak var lblPayment: UILabel!
    @IBOutlet weak var lblPaymentType: UILabel!
    @IBOutlet weak var viewPaymentType: UIView!


    @IBOutlet weak var objButtons: UIStackView!

    @IBOutlet weak var viewLicense: UIView!
    @IBOutlet weak var imgLicense: UIImageView!
    @IBOutlet weak var lblLicense: UILabel!

    @IBOutlet weak var viewTermsAndCondition: UIView!
    @IBOutlet weak var lblTermsAndCondition: UILabel!

    
    @IBOutlet weak var viewHours: UIView!
    @IBOutlet weak var imgHours: UIImageView!
    @IBOutlet weak var lblHours: UILabel!

    @IBOutlet weak var viewCheckList: UIView!
    @IBOutlet weak var imgCheckList: UIImageView!
    @IBOutlet weak var lblCheckList: UILabel!
    
    @IBOutlet weak var viewPhotVideo: UIView!
    @IBOutlet weak var imgPhotVideo: UIImageView!
    @IBOutlet weak var lblPhotVideo: UILabel!

    @IBOutlet weak var viewDeliveryStatus: UIView!
    @IBOutlet weak var imgDeliveryStatus: UIImageView!
    @IBOutlet weak var lblDeliveryStatus: UILabel!

    
    
    
    //LOADING
    let orderDetailsPlaceholderMarker = Placeholder()

    //OTHER
    var isLoading : Bool = true
    var strOrderID : String = ""

    var objOrderData : OrdersModel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        //CALL API
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID))

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
        setNavigationBarFor(controller: self, title: "#\(strOrderID)", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "icon_cart_shopping", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)
            
            
        } rightActionHandler: {
            
            //MOVE TO CHECKOUT SCREEN
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckOutViewController") as? CheckOutViewController{
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
            
        }
    }
    
    
    func setTheView(){
        self.isLoading = false
        self.stopLoading()
        self.setFooter()
      
        
        //SET DETAILS
        if self.objOrderData != nil{
            self.lblProductTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strProductList)

            
            if let objAddress = self.objOrderData.objAdress{
                
                self.lblBillingInfo.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.BillingInfo)

                self.lblName.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: objAddress.name ?? "")
                self.lblEmail.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: objAddress.name ?? "")

                
                self.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objAddress.name ?? "")")
                
                let strPhone: String = "\(objAddress.phone ?? "")".trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                self.lblNumber.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: strPhone)
                imgColor(imgColor: self.imgCall, colorHex: .secondary)
                self.lblEmail.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "\(objAddress.email ?? "")")
                self.lblEmail.alpha = 0.7
                
                imgColor(imgColor: self.imgMapAddress, colorHex: .secondary)
                imgColor(imgColor: self.imgEditAddress, colorHex: .secondary)
                self.lblAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: "\(objAddress.address ?? ""), \(objAddress.city ?? ""), \(objAddress.state ?? ""), \(objAddress.country ?? ""), \(objAddress.zip_code ?? "")")

                
            }
        }
        //        self.lblSubTotlaPrice.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(Application.currency)\(Checkout.shared.itemPrice.stringValue)", numberOfLines: 1)
        
        
        //SET HEADER
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            //SET TABLE HEADER
            let vw_Table = self.tblView.tableHeaderView
            vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.lblProductTitle.frame.origin.y + self.lblProductTitle.frame.size.height)

            self.tblView.tableHeaderView = vw_Table
        }
        
        //RELOAD TABLE
        self.tblView.reloadData()

    }
    
    func setFooter(){
        //SET DETAILS
        if self.objOrderData != nil{
            self.lblSubAmount.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.SubAmount)
            self.lblSubAmountPrice.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.objOrderData.sub_total ?? "")

            self.lblTax.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.strTax)
            self.lblTaxPrice.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.objOrderData.tax_amount ?? "")

            self.lblTotalAmount.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.TotalAmount)
            self.lblTotlaPrice.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.objOrderData.amount ?? "")

            self.lblPayment.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.paymentStatus)
            self.lblPaymentType.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.objOrderData.payment?.status?.label ?? "")
            
            //SET PAYMENT TYPE
            self.viewPaymentType.backgroundColor = .secondary
            self.viewPaymentType.viewCorneRadius(radius: 5.0, isRound: false)
            if self.objOrderData.payment?.status?.label?.lowercased() == "pending"{
                self.viewPaymentType.backgroundColor = .secondaryText
            }
            
            
            //SET OTHER BUTTONS
            self.lblLicense.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strLinces)
            self.lblTermsAndCondition.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strTerms)
            self.lblHours.configureLable(textColor: self.checkMachineHoursAllocate() == true ? .secondary : .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strHours)
            self.lblCheckList.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strCheckList)
            self.lblPhotVideo.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPhotoAndVideo)
            self.lblDeliveryStatus.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strDeliveyStatus)

            
            //CHECK AND SET VIEW
            self.viewLicense.backgroundColor = .clear
            self.viewLicense.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: self.imgLicense, colorHex: .secondary)
            
            if self.objOrderData.license_image_links.count != 0{
                self.lblLicense.textColor = .background
                imgColor(imgColor: self.imgLicense, colorHex: .background)
                self.viewLicense.backgroundColor = .secondary
            }
            
            //T&C
            self.viewTermsAndCondition.backgroundColor = .clear
            self.viewTermsAndCondition.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            
            if self.objOrderData.customer_signature != "" && self.objOrderData.customer_signature != nil{
                self.lblTermsAndCondition.textColor = .background
                self.viewTermsAndCondition.backgroundColor = .secondary
            }
            
            //HOURS
            self.viewHours.backgroundColor = .clear
            self.viewHours.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            self.viewHours.viewBorderCorneRadius(borderColour: self.checkMachineHoursAllocate() == true ? .secondary : .lightGray, size: 1)
            imgColor(imgColor: self.imgHours, colorHex: self.checkMachineHoursAllocate() == true ? .secondary : .lightGray)

//            if objData.customer_signature != "" && objData.customer_signature != nil{
//                self.lblHours.textColor = .background
//                imgColor(imgColor: self.imgHours, colorHex: .background)
//                self.viewHours.backgroundColor = .secondary
//            }
            
            
            //CHECKLIST
            self.viewCheckList.backgroundColor = .clear
            self.viewCheckList.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: self.imgCheckList, colorHex: .secondary)

//            if objData.customer_signature != "" && objData.customer_signature != nil{
//                self.lblCheckList.textColor = .background
//                imgColor(imgColor: self.imgCheckList, colorHex: .background)
//                self.viewCheckList.backgroundColor = .secondary
//            }
            
            //PHOT/VIDEO
            self.viewPhotVideo.backgroundColor = .clear
            self.viewPhotVideo.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: self.imgPhotVideo, colorHex: .secondary)

            if self.objOrderData.order_image_links.count != 0{
                self.lblPhotVideo.textColor = .background
                imgColor(imgColor: self.imgPhotVideo, colorHex: .background)
                self.viewPhotVideo.backgroundColor = .secondary
            }
            

            //DELIVERY STATUS
            self.viewDeliveryStatus.backgroundColor = .clear
            self.viewDeliveryStatus.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: self.imgDeliveryStatus, colorHex: .secondary)

//            if objData.customer_signature != "" && objData.customer_signature != nil{
//                self.lblDeliveryStatus.textColor = .background
//                imgColor(imgColor: self.imgDeliveryStatus, colorHex: .background)
//                self.viewDeliveryStatus.backgroundColor = .secondary
//            }
            
            
            //SET HEADER
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                //SET TABLE HEADER
                let vw_Table = self.tblView.tableFooterView
                vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.objButtons.frame.origin.y + self.objButtons.frame.size.height + 20)

                self.tblView.tableFooterView = vw_Table
            }
            
        }
            
    }
    func stopLoading(){
        indicatorHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.orderDetailsPlaceholderMarker.remove()
        }
    }
}


//MARK: - BUTTON ACTION
extension OrderDetailsViewController: MFMessageComposeViewControllerDelegate, LicenseUploadDelegate, TermsDelegate, ImageVideoUploadDelegate, PayMentDelegate{
   
    

    @IBAction func btnCallClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
        var getNumber = self.objOrderData.objAdress?.phone ?? ""
        getNumber = getNumber.replacingOccurrences(of: "+1", with: "")
        
        let pickerAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        
        
        let cancel = UIAlertAction.init(title: "Cancel", style: UIAlertAction.Style.cancel, handler: { (action) in
            
            pickerAlert.dismiss(animated: true, completion: nil)
        })
        
        let call = UIAlertAction.init(title: "Call \(self.objOrderData.objAdress?.phone ?? "")", style: UIAlertAction.Style.default, handler: { (action) in
            
            guard let number = URL(string: "tel://+1\(getNumber)") else { return }
            UIApplication.shared.open(number)
            
        })
        
        let sendMessage = UIAlertAction.init(title: "Send Message", style: UIAlertAction.Style.default, handler: { (action) in
            
            if (MFMessageComposeViewController.canSendText()) {
                let controller = MFMessageComposeViewController()
                controller.body = ""
                controller.recipients = ["+1\(getNumber)"]
                controller.messageComposeDelegate = self
                self.present(controller, animated: true, completion: nil)
            }
        })
        
        
        
        pickerAlert.addAction(call)
        pickerAlert.addAction(sendMessage)
        pickerAlert.addAction(cancel)
        
        if let presenter = pickerAlert.popoverPresentationController {
            presenter.sourceView = sender
            presenter.sourceRect = sender.frame
        }
        self.present(pickerAlert, animated: true, completion: nil)
    }
    
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        self.dismiss(animated: true, completion: nil)
        
    }
    
    
    @IBAction func btnMapClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
        if sender.tag == 1{
            //GET BILLING INFO
            var strAddress : String = ""
            if let objAddress = self.objOrderData.objAdress{
                strAddress = "\(objAddress.address ?? ""), \(objAddress.city ?? ""), \(objAddress.state ?? ""), \(objAddress.country ?? ""), \(objAddress.zip_code ?? "")"
                
                if (UIApplication.shared.canOpenURL(URL(string:"comgooglemaps://")!)) {  //if phone has an app
                    
                    if let url = URL(string: "comgooglemaps-x-callback://?saddr=&daddr=\(strAddress)&directionsmode=driving") {
                        UIApplication.shared.open(url, options: [:])
                    }}
                else {
                    //Open in browser
                    if let urlDestination = URL.init(string: "https://www.google.co.in/maps/dir/?saddr=&daddr=\(strAddress)&directionsmode=driving") {
                        UIApplication.shared.open(urlDestination)
                    }
                }
            }
            
        }
    }
    
    @IBAction func btnPaymentClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
        if self.objOrderData.payment?.status?.label?.lowercased() == "pending"{
            //VERIFICATION POPUP
            let window = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
            window?.endEditing(true)
            let aleartView = PaymentView(frame: CGRect(x: 0, y: 0 ,width : window?.frame.width ?? 0.0, height: window?.frame.height ?? 0.0))
            aleartView.delegate = self
            aleartView.loadPopUpView(strOrderID: "\(self.objOrderData.id ?? 0)")
            window?.addSubview(aleartView)

        }
    }
    
    @IBAction func btnLicenseClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "LicenseUploadViewController") as? LicenseUploadViewController{
            newViewController.delegate = self
            newViewController.arrLicense = self.objOrderData.license_image_links
            newViewController.strOrderID = "\(self.objOrderData.id ?? 0)"
            newViewController.selectIndex = sender.tag
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    
    @IBAction func btnTermsAndConditionClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
        var strTermsUrl : String = ""
        if self.objOrderData.token != "" && self.objOrderData.token != nil{
            strTermsUrl = "\(Application.TermsURL)\(self.objOrderData.token ?? "")/sign-terms?admin=true"
        }
        else{
            showAlertMessage(strMessage: str.somethingWentWrong)
            return
        }
        
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "TermsAndConditionViewController") as? TermsAndConditionViewController{
            newViewController.isOrderFrom = true
            newViewController.delegate = self
            newViewController.selectIndex = sender.tag
            newViewController.signUrl = strTermsUrl
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    
    @IBAction func btnMachineHoursClicked(_ sender : UIButton) {
        if self.objOrderData == nil || checkMachineHoursAllocate() == false{
            return
        }
     
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "MachineHoursViewController") as? MachineHoursViewController{
            newViewController.strOrderID = "\(self.objOrderData.id ?? 0)"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    @IBAction func btnImageVideoUploadClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
     
        
        //GET DATA
        var arrImageVideoLisr : [ImageVideoModel] = []
        for objImage in self.objOrderData.order_image_links{
            let isImageType = objImage.isImageType()
            let url: URL = URL(fileURLWithPath: "")
            let objData = ImageVideoModel(type: isImageType ? "img" : "video", image: UIImage(), strVideo: url, strUrl: objImage, isUpload: true)
            arrImageVideoLisr.append(objData)
        }
     
        
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ImageUploadViewController") as? ImageUploadViewController{
            newViewController.delegate = self
            newViewController.selectIndex = sender.tag
            newViewController.arrImageVideoLisr = arrImageVideoLisr
            newViewController.strOrderID = "\(self.objOrderData.id ?? 0)"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
 
    func PaymnetSuccess() {
        //CALL API
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID))
    }
    
  
    func termsSucess(selectIndex: Int) {
        self.isLoading = false
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID))

    }
    
    func linceUploadSucess(selectIndex: Int, arrImage: [String]) {
        self.isLoading = false
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID))
    }
    
    func ImageVideoUploadSucess(selectIndex: Int, arrImage: [String]) {
        self.isLoading = false
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID))
    }
    
    func checkMachineHoursAllocate() -> Bool{
        if self.objOrderData == nil{
            return false
        }
        for obj in objOrderData.arrMachineHours{
            if obj.allocated != 0{
                return true
            }
        }
        
        return false
    }
}



//MARK: -- UITABEL DELEGATE --

extension OrderDetailsViewController : UITableViewDelegate, UITableViewDataSource{
    
    //HEADER SECTION
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isLoading{
            return 5
        }
        else{
            return self.objOrderData.arrProduct.count
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
      
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "CartListCell") as? CartListCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.backgroundColor = .clear
            
            if isLoading {
                self.orderDetailsPlaceholderMarker.register(cell.getAnimableSubviews())
                self.orderDetailsPlaceholderMarker.startAnimation()
                return cell
            }
            
            let  objDetails = self.objOrderData.arrProduct[indexPath.row]
            

            //SET IMAG
            cell.viewLine.backgroundColor = .lightGray
            cell.con_imgHeight.constant = manageWidth(size: 70)
            cell.imgProduct.viewCorneRadius(radius: 5, isRound: false)
            cell.imgProduct.setImage(strImg: objDetails.product_image ?? "")
            cell.imgProduct.backgroundColor = .white

            let getPrice = getProductTotlaPrice(productID: objDetails.id ?? 0)

        
            //SET FONT
            cell.lblProductName.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "\(objDetails.product_name ?? "") * \(objDetails.qty )")
            cell.lblTotlaPrice.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "")
            
            
            //SET SCHEDULE DATE
            cell.lblScheduleDate.text = ""
            if objDetails.product_options != nil{
                let strDate = setFontAttributes(str: str.sttScheduleDate, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0)
                strDate.append(setFontAttributes(str: " \( objDetails.product_options.deldate ?? "")", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0))
                cell.lblScheduleDate.attributedText = strDate
            }

            
            //CHECK OPTION
            cell.objPrice.isHidden = true
            cell.objOptions.isHidden = true
            if objDetails.dicOptions != nil{
                cell.objPrice.isHidden = false
                cell.objOptions.isHidden = false
            }

            //SET OPTIONS VALUE
            cell.lblOptionsValues.text = ""
            cell.lblPrice.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.strPrice)
            if getPrice.1 != 0{
                cell.lblPriceTotal.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "\(Application.currency)\((getPrice.1).stringValue)")
            }

            cell.lblOptions.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: str.strOptionsTotal)
            if getPrice.2 != 0{
                cell.lblOptionsPrice.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "\(Application.currency)\((getPrice.2).stringValue)")
            }
            

            //SET OPTION VALUE
            var strValues : String = ""
            if let dicCartValue = objDetails.dicOptions?["optionCartValue"] as? NSDictionary{
                let allKey  = dicCartValue.allKeys
                for objKey in allKey{
                    if let arrData = dicCartValue["\(objKey)"] as? NSArray{
                        
                        for objData in arrData {
                            let dicData = objData as? NSDictionary
                            let price = dicData?["option_value"] as? String
                            if strValues == ""{
                                strValues = "- \(price ?? "")"
                            }
                            else{
                                strValues = "\(strValues)\n- \(price ?? "")"
                            }
                        }
                    }
                }
            }
            
            cell.lblOptionsValues.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: strValues)
       

            
            return cell
        }

        return UITableViewCell()
        
    }
    
   
    @objc func btnRemoveClicked(_ sender: UIButton){
        let objDate = Checkout.shared.cart[sender.tag].product

        //CALL API
        let alert = UIAlertController(title: Application.appName, message: "Are you sure you want to remove \(objDate.name ?? "")?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
            
            //REMOVE ITEM
            Checkout.shared.removeProductFromCart(product: objDate)

            //CHECK ITEMS
            if Checkout.shared.cart.count == 0{
                //BACK SCREE
                self.navigationController?.popViewController(animated: true)
            }
            else{
                //RELOAD
                self.tblView.reloadData()
            }

       
        }))
        alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @objc func btnUpdateClicked(_ sender: UIButton){
        
        //MOVE TO PRODUCT SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ProductDetailsViewController") as? ProductDetailsViewController{
            newViewController.isUpdateProduct = true
            newViewController.objData = Checkout.shared.cart[sender.tag].product

            let vieweNavigationController = UINavigationController(rootViewController: newViewController)
            self.present(vieweNavigationController, animated: true)
        }
    }
    

    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
      
    }
    
    
    
  

}


func setFontAttributes(str : String, fontName: String , fontSize: Double) -> NSMutableAttributedString{
    let yourAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: UIColor.primary ,
        .font: SetTheFont(fontName: fontName, size: fontSize),
    ]

    
    let attributeString = NSMutableAttributedString(
        string: str,
        attributes: yourAttributes
    )

    return attributeString
}


extension OrderDetailsViewController{
  
 
    
    func getProductTotlaPrice(productID : Int) -> (Double, Double, Double){
        if productID != 0{
            if let index = self.objOrderData.arrProduct.firstIndex(where: { $0.id == productID }){
                
                let productItem = self.objOrderData.arrProduct[index]
                
                //GET PRICE
                let itemPrice = (Float(productItem.product_price ?? "") ?? 0) * Float(productItem.qty)
                
                //GET OPTIONS PRICES
                var optionsPrice : Double = 0.0
                if let dicOptions = productItem.dicOptions{
                    
                    if let dicCartValue = dicOptions["optionCartValue"] as? NSDictionary{
                        let allKey  = dicCartValue.allKeys
                        for objKey in allKey{
                            if let arrData = dicCartValue["\(objKey)"] as? NSArray{
                                
                                for objData in arrData {
                                    let dicData = objData as? NSDictionary
                                    
                                    let price = Float(dicData?.getStringForID(key: "affect_price") ?? "") ?? 0.0
                                    optionsPrice = optionsPrice + Double(price)
                                }
                            }
                        }
                    }
                }
                
                return ((Double(itemPrice) + (optionsPrice * Double(productItem.qty))), Double(itemPrice), optionsPrice)
                
            }
        }
        return (0, 0, 0)
    }
}
