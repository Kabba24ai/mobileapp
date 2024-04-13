//
//  OrderDetailsViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 15/02/24.
//

import UIKit
import MessageUI
import CoreLocation
import MapKit
protocol OrderDetailsDelegate : NSObject {
    func updateOrderDetails(selectIndex : Int, objOrderData : OrdersModel)
}

class OrderDetailsViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: OrderDetailsDelegate?

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

    @IBOutlet weak var viewDelivery: UIView!
    @IBOutlet weak var lblDeliveryInfo: UILabel!
    @IBOutlet weak var lblDeliveryName: UILabel!
    @IBOutlet weak var lblDeliveryNumber: UILabel!
    @IBOutlet weak var imgDeliveryCall: UIImageView!
    @IBOutlet weak var lblDeliveryEmail: UILabel!
    @IBOutlet weak var lblDeliveryAddress: UILabel!
    @IBOutlet weak var imgDeliveryEditAddress: UIImageView!
    @IBOutlet weak var imgDeliveryMapAddress: UIImageView!

    
    

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

    
    @IBOutlet weak var viewHoursStart: UIView!
    @IBOutlet weak var imgHoursStart: UIImageView!
    @IBOutlet weak var lblHoursStart: UILabel!

    @IBOutlet weak var viewHoursEnd: UIView!
    @IBOutlet weak var imgHoursEnd: UIImageView!
    @IBOutlet weak var lblHoursEnd: UILabel!

    
    @IBOutlet weak var viewCheckList: UIView!
    @IBOutlet weak var imgCheckList: UIImageView!
    @IBOutlet weak var lblCheckList: UILabel!
    
    @IBOutlet weak var viewPhotVideo: UIView!
    @IBOutlet weak var imgPhotVideo: UIImageView!
    @IBOutlet weak var lblPhotVideo: UILabel!

    @IBOutlet weak var viewDeliveryStatus: UIView!
    @IBOutlet weak var imgDeliveryStatus: UIImageView!
    @IBOutlet weak var lblDeliveryStatus: UILabel!

    @IBOutlet weak var viewPickupStatus: UIView!
    @IBOutlet weak var imgPickupStatus: UIImageView!
    @IBOutlet weak var lblPickupStatus: UILabel!

    
    
    
    //LOADING
    let orderDetailsPlaceholderMarker = Placeholder()

    //OTHER
    var isOrderScreen : Bool = false
    var isLoading : Bool = true
    var strOrderID : String = ""

    var selectIndex : Int = -1
    var objOrderData : OrdersModel!
    var strProductID : String = ""
    var deliveryType : String = "Delivery"

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
        setNavigationBarFor(controller: self, title: "#\(strOrderID)", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "icon_cart_shopping", isDetailsScree: true) {
            
            if self.selectIndex != -1{
                if self.objOrderData != nil{
                    self.delegate?.updateOrderDetails(selectIndex: self.selectIndex, objOrderData: self.objOrderData)
                }
            }
            
            //BACK SCREE
            if self.isOrderScreen == true{
                self.navigationController?.popToRootViewController(animated: true)
            }
            else{
                self.navigationController?.popViewController(animated: true)
            }
            
            
            
        } rightActionHandler: {
            
            //MOVE TO CHECKOUT SCREEN
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckOutViewController") as? CheckOutViewController{
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
            
        }
        
        //CALL API
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID, product_id: self.strProductID))

    }
    
    
    func setTheView(){
        self.isLoading = false
        self.stopLoading()
        self.setFooter()
      
        
        //SET DETAILS
        if self.objOrderData != nil{
            self.lblProductTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strProductList)

            
            //SET BILLING ADDRESS
            self.viewBilling.isHidden = true
            if self.objOrderData.billing_address != nil{
                if let objAddress = self.objOrderData.billing_address{
                    self.viewBilling.isHidden = false

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
            
            
            //SET DELIVERY ADDRESS
            self.viewDelivery.isHidden = true
            if self.objOrderData.billing_address != nil{
                if let objAddress = self.objOrderData.shipping_address{
                    self.viewDelivery.isHidden = false

                    self.lblDeliveryInfo.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.DeliveryInfo)

                    self.lblDeliveryName.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: objAddress.name ?? "")
                    self.lblDeliveryEmail.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: objAddress.name ?? "")

                    
                    self.lblDeliveryName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objAddress.name ?? "")")
                    
                    let strPhone: String = "\(objAddress.phone ?? "")".trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    self.lblDeliveryNumber.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: strPhone)
                    imgColor(imgColor: self.imgDeliveryCall, colorHex: .secondary)
                    self.lblDeliveryEmail.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "\(objAddress.email ?? "")")
                    self.lblEmail.alpha = 0.7
                    
                    imgColor(imgColor: self.imgDeliveryMapAddress, colorHex: .secondary)
                    imgColor(imgColor: self.imgDeliveryEditAddress, colorHex: .secondary)
                    self.lblDeliveryAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: "\(objAddress.address ?? ""), \(objAddress.city ?? ""), \(objAddress.state ?? ""), \(objAddress.country ?? ""), \(objAddress.zip_code ?? "")")
                }

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
            else if self.objOrderData.payment?.status?.label?.lowercased() == "failed"{
                self.lblPaymentType.textColor = .primary
                self.viewPaymentType.backgroundColor = .redText
            }
            
            //SET OTHER BUTTONS
            self.lblLicense.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strLinces)
            self.lblTermsAndCondition.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strTerms)
            self.lblHoursStart.configureLable(textColor: self.checkMachineHoursAllocate() == true ? .secondary : .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strHoursStart)
            self.lblHoursEnd.configureLable(textColor: self.checkMachineHoursAllocate() == true ? .secondary : .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strHoursEnd)
            self.lblCheckList.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strCheckList)
            self.lblPhotVideo.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPhotoAndVideo)
            self.lblDeliveryStatus.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strDeliveyStatus)
            self.lblPickupStatus.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPickupStatus)

            
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
            self.viewTermsAndCondition.viewBorderCorneRadius(borderColour: self.checkTermsAndConditionStatus() == true ? .secondary : .lightGray, size: 1)
            self.lblTermsAndCondition.textColor = self.checkTermsAndConditionStatus() == true ? .secondary : .lightGray

            if self.objOrderData.customer_signature != "" && self.objOrderData.customer_signature != nil && self.checkTermsAndConditionStatus() == true{
                self.lblTermsAndCondition.textColor = .background
                self.viewTermsAndCondition.backgroundColor = .secondary
            }
            
            //HOURS
            self.viewHoursStart.backgroundColor = .clear
            self.viewHoursEnd.backgroundColor = .clear
            self.viewHoursStart.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            self.viewHoursEnd.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            self.viewHoursStart.viewBorderCorneRadius(borderColour: self.checkMachineHoursAllocate() == true ? .secondary : .lightGray, size: 1)
            self.viewHoursEnd.viewBorderCorneRadius(borderColour: self.checkMachineHoursAllocate() == true ? .secondary : .lightGray, size: 1)
            imgColor(imgColor: self.imgHoursStart, colorHex: self.checkMachineHoursAllocate() == true ? .secondary : .lightGray)
            imgColor(imgColor: self.imgHoursEnd, colorHex: self.checkMachineHoursAllocate() == true ? .secondary : .lightGray)

            if self.checkMachineHoursAllocate() == true && self.checkMachineStartHoursComplate() == true{
                self.lblHoursStart.textColor = .background
                imgColor(imgColor: self.imgHoursStart, colorHex: .background)
                self.viewHoursStart.backgroundColor = .secondary
            }
            
            if self.checkMachineHoursAllocate() == true && self.checkMachineEndHoursComplate() == true{
                self.lblHoursEnd.textColor = .background
                imgColor(imgColor: self.imgHoursEnd, colorHex: .background)
                self.viewHoursEnd.backgroundColor = .secondary
            }
            
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
            let getDeliveryData = checkDeliveryPickupStatus(isDeliveryType: true)

            self.viewDeliveryStatus.backgroundColor = .clear
            self.viewDeliveryStatus.viewBorderCorneRadius(radius: 10, borderColour: self.objOrderData.arrDeliveryStatus.count != 0 ? .secondary : .lightGray)
            self.imgDeliveryStatus.image = UIImage(named: getDeliveryData.0)
            imgColor(imgColor: self.imgDeliveryStatus, colorHex: self.objOrderData.arrDeliveryStatus.count != 0 ? .secondary : .lightGray)
            
            if getDeliveryData.1 == true{
                self.lblDeliveryStatus.textColor = .background
                imgColor(imgColor: self.imgDeliveryStatus, colorHex: .background)
                self.viewDeliveryStatus.backgroundColor = .secondary
            }
            
          
            //PICKUP STATUS
            let getPickupData = checkDeliveryPickupStatus(isDeliveryType: false)

            self.viewPickupStatus.backgroundColor = .clear
            self.viewPickupStatus.viewBorderCorneRadius(radius: 10, borderColour: self.objOrderData.arrDeliveryStatus.count != 0 ? .secondary : .lightGray)
            self.imgPickupStatus.image = UIImage(named: getPickupData.0)
            imgColor(imgColor: self.imgPickupStatus, colorHex: self.objOrderData.arrDeliveryStatus.count != 0 ? .secondary : .lightGray)
            
            if getPickupData.1 == true{
                self.lblPickupStatus.textColor = .background
                imgColor(imgColor: self.imgPickupStatus, colorHex: .background)
                self.viewPickupStatus.backgroundColor = .secondary
            }
            
            
            

            //SET HEADER
            DispatchQueue.main.asyncAfter(deadline: .now()) {

                let height = self.objOrderData.payment?.status?.label?.lowercased() == "failed" ? 0 : self.objButtons.frame.size.height + 20
                self.objButtons.isHidden = false
                if self.objOrderData.payment?.status?.label?.lowercased() == "failed"{
                    self.objButtons.isHidden = true
                }
                
                //SET TABLE HEADER
                let vw_Table = self.tblView.tableFooterView
                vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.objButtons.frame.origin.y + height )

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
        
        var getNumber = ""
        if sender.tag == 0{
            getNumber = self.objOrderData.billing_address?.phone ?? ""
        }
        else{
            getNumber = self.objOrderData.shipping_address?.phone ?? ""
        }
        
        getNumber = getNumber.replacingOccurrences(of: "+1", with: "")
        
        let pickerAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        
        
        let cancel = UIAlertAction.init(title: "Cancel", style: UIAlertAction.Style.cancel, handler: { (action) in
            
            pickerAlert.dismiss(animated: true, completion: nil)
        })
        
        let call = UIAlertAction.init(title: "Call \(getNumber)", style: UIAlertAction.Style.default, handler: { (action) in
            
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
        
        var strAddress : String = ""
        if sender.tag == 0{
            if let objAddress = self.objOrderData.billing_address{
                strAddress = "\(objAddress.address ?? ""), \(objAddress.city ?? ""), \(objAddress.state ?? ""), \(objAddress.country ?? ""), \(objAddress.zip_code ?? "")"
            }
        }
        else{
            if let objAddress = self.objOrderData.shipping_address{
                strAddress = "\(objAddress.address ?? ""), \(objAddress.city ?? ""), \(objAddress.state ?? ""), \(objAddress.country ?? ""), \(objAddress.zip_code ?? "")"
            }
        }

        if strAddress != ""{
            openAddressInMap(address: strAddress)
//            if (UIApplication.shared.canOpenURL(URL(string:"comgooglemaps://")!)) {  //if phone has an app
//                
//                if let url = URL(string: "comgooglemaps-x-callback://?saddr=&daddr=\(strAddress)&directionsmode=driving") {
//                    UIApplication.shared.open(url, options: [:])
//                }}
//            else {
//                //Open in browser
//                if let urlDestination = URL.init(string: "https://www.google.co.in/maps/dir/?saddr=&daddr=\(strAddress)&directionsmode=driving") {
//                    UIApplication.shared.open(urlDestination)
//                }
//            }
        }
      
    }
    
    
    
    @IBAction func btnAddressClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
       
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "AddressViewController") as? AddressViewController{
            if sender.tag == 0{
                newViewController.strTitle = str.BillingInfo
                newViewController.objAdress = self.objOrderData.billing_address
            }
            else{
                newViewController.strTitle = str.DeliveryInfo
                newViewController.objAdress = self.objOrderData.shipping_address
            }
            newViewController.orderID = "\(self.objOrderData.id ?? 0)"
            self.navigationController?.pushViewController(newViewController, animated: true)
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
        
        if self.checkTermsAndConditionStatus() == true{
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
    }
    
    
    @IBAction func btnMachineHoursClicked(_ sender : UIButton) {
        if self.objOrderData == nil || checkMachineHoursAllocate() == false{
            return
        }
     
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "MachineHoursViewController") as? MachineHoursViewController{
            newViewController.strOrderID = "\(self.objOrderData.id ?? 0)"
            newViewController.strProductID = self.strProductID
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
    
    @IBAction func btnDeliveryStatusClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
        //GET
        let getDeliveryData = checkDeliveryPickupStatus(isDeliveryType: true)
        if getDeliveryData.1 == false{
            //GET PRODUCT NAME
            
            let MenuID = self.objOrderData.arrProduct.map{$0.product_id}
            if let index = MenuID.firstIndex(of: getDeliveryData.2){
                let productName = self.objOrderData.arrProduct[index].product_name
                
                
                //CALL API
                let alert = UIAlertController(title: Application.appName, message: "Are you sure you have deliverd '\(productName ?? "")' to \(self.objOrderData.objAdress?.name ?? "" )", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                    
                   
                    let MenuID = self.objOrderData.arrDeliveryStatus.map{$0.product_id}
                    if let index = MenuID.firstIndex(of: getDeliveryData.2){
                        self.deliveryType = "Delivery"
                        
                        self.updateStatus(UpdateStatusParameater: UpdateStatusParameater(id: "\(self.objOrderData.arrDeliveryStatus[index].id ?? 0)", delivery_status: "2", pickup_status: ""), index: index)
                    }
               
                }))
                alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
                self.present(alert, animated: true)
            }
        }
    }
    
    @IBAction func btnPickupStatusClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
        
        //GET
        let getDeliveryData = checkDeliveryPickupStatus(isDeliveryType: false)
        if getDeliveryData.1 == false{
            //GET PRODUCT NAME
            
            let MenuID = self.objOrderData.arrProduct.map{$0.product_id}
            if let index = MenuID.firstIndex(of: getDeliveryData.2){
                let productName = self.objOrderData.arrProduct[index].product_name
                
                
                //CALL API
                let alert = UIAlertController(title: Application.appName, message: "Are you sure you have received '\(productName ?? "")' to \(self.objOrderData.objAdress?.name ?? "" )", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                    
                    let MenuID = self.objOrderData.arrDeliveryStatus.map{$0.product_id}
                    if let index = MenuID.firstIndex(of: getDeliveryData.2){
                        self.deliveryType = "Pickup"
                        
                        self.updateStatus(UpdateStatusParameater: UpdateStatusParameater(id: "\(self.objOrderData.arrDeliveryStatus[index].id ?? 0)", delivery_status: "", pickup_status: "2"), index: index)
                    }
               
                }))
                alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
                self.present(alert, animated: true)
            }
        }
    }
 
    func PaymnetSuccess() {
        //CALL API
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID, product_id: self.strProductID))
    }
    
  
    func termsSucess(selectIndex: Int) {
        self.isLoading = false
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID, product_id: self.strProductID))

    }
    
    func linceUploadSucess(selectIndex: Int, arrImage: [String]) {
        self.isLoading = false
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID, product_id: self.strProductID))
    }
    
    func ImageVideoUploadSucess(selectIndex: Int, arrImage: [String]) {
        self.isLoading = false
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID, product_id: self.strProductID))
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
    
    
    func checkMachineStartHoursComplate() -> Bool{
        if self.objOrderData == nil{
            return false
        }

        for obj in objOrderData.arrMachineHours{
            if obj.start == 0{
                return false
            }
        }
        
        return true
    }
    
    func checkMachineEndHoursComplate() -> Bool{
        if self.objOrderData == nil{
            return false
        }

        for obj in objOrderData.arrMachineHours{
            if obj.end == 0{
                return false
            }
        }
        
        return true
    }
    
    
    func checkTermsAndConditionStatus() -> Bool{
        if self.objOrderData == nil{
            return false
        }
        
        if self.objOrderData.token != "" && self.objOrderData.token != nil{
            if self.objOrderData.arrProduct.count != 0{
                for obj in self.objOrderData.arrProduct{
                    if obj.objProduct?.use_global == true{
                        return true
                    }
                }
            }
        }

        
        return false
    }
 
    func checkDeliveryPickupStatus(isDeliveryType : Bool) -> (String, Bool, Int){
        if self.objOrderData == nil{
            return ("icon_delivery_pending", false, 0)
        }
        
        
        var strImg : String = "icon_delivery_pending"
        if self.objOrderData.arrDeliveryStatus.count != 0{
            
            for obj in self.objOrderData.arrDeliveryStatus{
                if isDeliveryType{
                    //GET IMAGE
                    if obj.customer_delivery == 2{
                        strImg = "icon_delivery_pending"
                    }
                    else{
                        strImg = "icon_store"
                    }
                    
                    //CHECK STATUS
                    if obj.delivery_status?.value != "2"{
                        return (strImg, false, obj.product_id ?? 0)
                    }
                }
                else{
                    //GET IMAGE
                    if obj.customer_pickup == 2{
                        strImg = "icon_delivery_pending"
                    }
                    else{
                        strImg = "icon_store"
                    }
                    
                    //CHECK STATUS
                    if obj.pickup_status?.value != "2"{
                        return (strImg, false, obj.product_id ?? 0)
                    }
                }
            }
        }
        else{
            return (strImg, false, 0)
        }
        
        return (strImg, true, 0)
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
                let strScheduleDate = convertStringToNewFormateString(date: "\(objDetails.product_options.deldate ?? "")", withFormat: Application.passServertDAte, newFormate: Application.strDateFormet) ?? ""

                let strDate = setFontAttributes(str: str.sttScheduleDate, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0)
                strDate.append(setFontAttributes(str: " \(strScheduleDate)", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0))
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
       
            //CHECK STORE ADDRESS
            cell.imgStore.isHidden = false
            cell.con_imgStore.constant = 0
            cell.lblStoreAddress.text = ""
            if objDetails.storeAdderss != nil{
                cell.con_imgStore.constant = 30
                imgColor(imgColor: cell.imgStore, colorHex: .secondary)
                cell.lblStoreAddress.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: "\(objDetails.storeAdderss?.address ?? ""), \(objDetails.storeAdderss?.city ?? ""), \(objDetails.storeAdderss?.state ?? ""), \(objDetails.storeAdderss?.zip_code ?? "")")
            }
            
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


///Opens text address in maps
func openAddressInMap(address: String?){
    guard let address = address else {return}
    
    let geoCoder = CLGeocoder()
    geoCoder.geocodeAddressString(address) { (placemarks, error) in
        guard let placemarks = placemarks?.first else {
            return
        }
        
        let location = placemarks.location?.coordinate
        
        if let lat = location?.latitude, let lon = location?.longitude{
//
//                let query = "?ll=\(lat),\(lon)"
//                let urlString = "http://maps.apple.com/".appending(query)
//                if let url = URL(string: urlString) {
//                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
//                }
//
//
            
            let destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
            destination.name = address
            
            MKMapItem.openMaps(
                with: [destination]
            )
        }
    }
}
