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
import Alamofire
protocol OrderDetailsDelegate : NSObject {
    func updateOrderDetails(selectIndex : Int, objOrderData : OrdersListModel)
}

class OrderDetailsViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: OrderDetailsDelegate?

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!
    @IBOutlet weak var con_Upload: NSLayoutConstraint!

    @IBOutlet weak var viewBilling: UIView!
    @IBOutlet weak var lblBillingInfo: UILabel!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var lblNumber: UILabel!
    @IBOutlet weak var imgCall: UIImageView!
    @IBOutlet weak var lblEmail: UILabel!
    @IBOutlet weak var lblAddress: UILabel!
    @IBOutlet weak var imgEditAddress: UIImageView!
    @IBOutlet weak var imgMapAddress: UIImageView!

    @IBOutlet weak var lblNoteTitle: UILabel!
    @IBOutlet weak var viewAddNoteBtn: UIView!
    @IBOutlet weak var imgAddNoteBtn: UIImageView!
    @IBOutlet weak var lblAddNote: UILabel!
    @IBOutlet weak var objNoteView: UIStackView!

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
    @IBOutlet weak var objButtons1: UIStackView!
    @IBOutlet weak var objButtons2: UIStackView!
    @IBOutlet weak var objButtons3: UIStackView!

    @IBOutlet weak var viewLicense: UIView!
    @IBOutlet weak var imgLicense: UIImageView!
    @IBOutlet weak var lblLicense: UILabel!

    @IBOutlet weak var viewTermsAndCondition: UIView!
    @IBOutlet weak var lblTermsAndCondition: UILabel!
    
    @IBOutlet weak var viewCheckListDeliv: UIView!
    @IBOutlet weak var imgCheckListDeliv: UIImageView!
    @IBOutlet weak var lblCheckListDeliv: UILabel!
    
    @IBOutlet weak var viewCheckListRet: UIView!
    @IBOutlet weak var imgCheckListRet: UIImageView!
    @IBOutlet weak var lblCheckListRet: UILabel!

    
    @IBOutlet weak var viewPhotVideoDeli: UIView!
    @IBOutlet weak var imgPhotVideoDeli: UIImageView!
    @IBOutlet weak var lblPhotVideoDeli: UILabel!
    @IBOutlet weak var btnPhotVideoDeli: UIButton!
    
    @IBOutlet weak var viewPhotVideoRet: UIView!
    @IBOutlet weak var imgPhotVideoRet: UIImageView!
    @IBOutlet weak var lblPhotVideoRet: UILabel!
    @IBOutlet weak var btnPhotVideoRet: UIButton!

    @IBOutlet weak var viewDeliveryStatus: UIView!
    @IBOutlet weak var imgDeliveryStatus: UIImageView!
    @IBOutlet weak var lblDeliveryStatus: UILabel!

    @IBOutlet weak var viewPickupStatus: UIView!
    @IBOutlet weak var imgPickupStatus: UIImageView!
    @IBOutlet weak var lblPickupStatus: UILabel!

    
    
    
    //LOADING
    let orderDetailsPlaceholderMarker = Placeholder()
    var arrUserList : [UserListModel] = []
    
    //OTHER
    var isOrderScreen : Bool = false
    var isLoading : Bool = true
    var strOrderID : String = ""
    var strOrderUniqueId : String = ""
    var isPresent : Bool = false
    
    
    var selectIndex : Int = -1
    var objOrderData : OrdersListModel!
    var strProductID : String = ""
    var deliveryType : String = "Delivery"
    var isBillingView : Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        syncOrderNoteWithAPI()

        NotificationCenter.default.addObserver(self, selector: #selector(startUploadData), name: .startUploadData, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopUploadData), name: .stopUploadData, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(UpdateCheckListsProduct), name: .updateCheckList, object: nil)


    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        
        //CHECK DATA
        self.stopUploadData()

        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true
        
        self.updateNavigationbar()
        
        //CALL API
        self.getUserDataFromLocally()
        self.getOrderDetailFromLocally()

    }
    
    func updateNavigationbar(){
        //SET NAVIGATION BAR
        setNavigationBarFor(controller: self, title: "\(strOrderID)", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: self.objOrderData != nil ? (self.objOrderData.is_same_as_billing == false ? "+View Billing Info" : "") : "", isDetailsScree: true) {
            
            if self.selectIndex != -1{
                if self.objOrderData != nil{
                    self.delegate?.updateOrderDetails(selectIndex: self.selectIndex, objOrderData: self.objOrderData)
                }
            }
            
            //BACK SCREE
            if self.isPresent == true{
                self.dismiss(animated: true)
            }
            else{
                if self.isOrderScreen == true{
                    self.navigationController?.popToRootViewController(animated: true)
                }
                else{
                    self.navigationController?.popViewController(animated: true)
                }
            }
            
        } rightActionHandler: {
            if self.objOrderData.is_same_as_billing == false{
                if self.isBillingView{
                    self.isBillingView = false
                }
                else{
                    self.isBillingView = true
                }
                
                self.updateBillingView()
            }
           
        }
    }
    
    @objc func startUploadData(){
        self.con_Upload.constant = manageFont(font: 0)
        
    }
    
    @objc func stopUploadData(){
        self.con_Upload.constant = 0
    }
    
    func updateBillingView(){
        self.viewBilling.isHidden = !self.isBillingView
        
        //SET HEADER
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            //SET TABLE HEADER
            let vw_Table = self.tblView.tableHeaderView
            vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.lblProductTitle.frame.origin.y + self.lblProductTitle.frame.size.height)

            self.tblView.tableHeaderView = vw_Table
            
            //RELOAD TABLE
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                self.tblView.reloadData()
            }
        }
    }
    
    func setTheView(){
        self.isLoading = false
        self.stopLoading()
        self.setFooter()
        self.updateNavigationbar()
        
        //SET DETAILS
        if self.objOrderData != nil{
            self.lblProductTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strProductList)

            
            //SET BILLING ADDRESS
            self.viewBilling.isHidden = true
            if self.objOrderData.objBillingAddress != nil{
                if let objAddress = self.objOrderData.objBillingAddress{
                    self.viewBilling.isHidden = false

                    self.lblBillingInfo.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.BillingInfo)

                    self.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objAddress.full_name ?? "")")
                    self.lblEmail.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: objAddress.email ?? "")

                    let strPhone: String = "\(objAddress.phone ?? "")".trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    self.lblNumber.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: strPhone)
                    imgColor(imgColor: self.imgCall, colorHex: .secondary)
                    self.lblEmail.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "\(objAddress.email ?? "")")
                    self.lblEmail.alpha = 0.7
                    
                    imgColor(imgColor: self.imgMapAddress, colorHex: .secondary)
                    imgColor(imgColor: self.imgEditAddress, colorHex: .secondary)
                    self.lblAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: "\(objAddress.full_address ?? "")")
                }
            }
            
            
            //SET DELIVERY ADDRESS
            if self.objOrderData.objDeliveryAddress != nil{
                if let objAddress = self.objOrderData.objDeliveryAddress{
                    self.lblDeliveryInfo.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.DeliveryInfo)

                    self.lblDeliveryName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objAddress.full_name ?? "")")
                    self.lblDeliveryEmail.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: objAddress.email ?? "")

                    
                    
                    let strPhone: String = "\(objAddress.phone ?? "")".trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    self.lblDeliveryNumber.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: strPhone)
                    imgColor(imgColor: self.imgDeliveryCall, colorHex: .secondary)
                    self.lblDeliveryEmail.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "\(objAddress.email ?? "")")
                    self.lblEmail.alpha = 0.7
                    
                    imgColor(imgColor: self.imgDeliveryMapAddress, colorHex: .secondary)
                    imgColor(imgColor: self.imgDeliveryEditAddress, colorHex: .secondary)
                    self.lblDeliveryAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: "\(objAddress.full_address ?? "")")
                }

            }
            
    
//            //CHECK ADDRESS SAME
//            self.viewDelivery.isHidden = false
//            self.viewDeliverySame.isHidden = true
//            if self.objOrderData.is_same_as_billing ?? false{
//                self.viewDelivery.isHidden = true
//                self.viewDeliverySame.isHidden = true
//            }
        }
        
        self.lblNoteTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strDeliveryNote)
        self.lblAddNote.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.strAddNoteBtn)

        imgColor(imgColor: self.imgAddNoteBtn, colorHex: .secondary)
        self.viewAddNoteBtn.backgroundColor = .clear
        self.viewAddNoteBtn.viewCorneRadius(radius: 5.0, isRound: false)
        
//        let headerStack = UIStackView()
        self.objNoteView.axis = .vertical
        self.objNoteView.spacing = 0
        self.objNoteView.translatesAutoresizingMaskIntoConstraints = false
        self.objNoteView.removeAllArrangedSubviews()
        for (idx, note) in self.objOrderData.arrOrderNote.enumerated() {
            let row = NoteRowView()
            row.configure(with: note)
            row.onEdit = { [weak self] in self?.edit(at: idx) }
            row.onDelete = { [weak self] in self?.delete(at: idx) }
            self.objNoteView.addArrangedSubview(row)
        }
        
        //CEHCK PRODUCT TYPE
        self.objButtons1.isHidden = false
        self.objButtons2.isHidden = false
        self.objButtons3.isHidden = false
        if self.checkProductType(arrData: self.objOrderData.arrProduct){
            self.objButtons1.isHidden = true
            self.objButtons2.isHidden = true
            self.objButtons3.isHidden = true
        }

        //SET HEADER
        self.updateBillingView()

    }
    
    
    
    func checkProductType(arrData : [OrderProductModel]) -> Bool{
        for obj in arrData{
            if obj.objProductData?.product_type?.lowercased() == "rental"{
                return false
            }
        }
        return true
    }
    
    private func edit(at index: Int) {
        print(index)
        if self.objOrderData == nil && arrUserList.count == 0{
            return
        }
        
        let objDate = objOrderData.arrOrderNote[index]

        //ADD NOTE POPUP
        let window = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
        window?.endEditing(true)
        let aleartView = AddNoteView(frame: CGRect(x: 0, y: 0 ,width : window?.frame.width ?? 0.0, height: window?.frame.height ?? 0.0))
        aleartView.delegate = self
        aleartView.objNoteData = objDate
        aleartView.loadPopUpView(strOrderID: self.objOrderData.unique_id ?? "", strNote: str.strAddNote , arr: self.arrUserList)
        window?.addSubview(aleartView)
        
    }
    
    private func delete(at index: Int) {
        if self.objOrderData == nil && arrUserList.count == 0{
            return
        }

        let objDate = objOrderData.arrOrderNote[index]

        //CALL API
        let alert = UIAlertController(title: Application.appName, message: "Are you sure you want to delete this note?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
            
//            if NetworkReachabilityManager()!.isReachable {
//                //CALL API
//                RentnKing.deleteNote(struniqueID: objDate.unique_id ?? "", note_id: 0) { is_success in
//                    
//                    indicatorHide()
//                    
//                    //UPDATE DATA
//                    self.CallAPIforGetOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(unique_id: self.strOrderUniqueId, product_id: self.strProductID))
//                }
//            }
//            else {
                self.deleteNoteDataNoInternetCase(note_dic: objDate)
//            }
       
        }))
        alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }

    func setFooter(){
        //SET DETAILS
        if self.objOrderData != nil{
            self.lblSubAmount.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.SubAmount)
            self.lblSubAmountPrice.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.objOrderData.sub_total ?? "")
            self.lblSubAmountPrice.textAlignment = .right
            
            self.lblTax.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.strTax)
            self.lblTaxPrice.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.objOrderData.tax_amount ?? "")

            self.lblTotalAmount.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.TotalAmount)
            self.lblTotlaPrice.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.objOrderData.amount ?? "")
            self.lblTotlaPrice.textAlignment = .right
            
            self.lblPayment.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.paymentStatus)
            self.lblPaymentType.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.objOrderData.payment_status ?? "")
            
            //SET PAYMENT TYPE
            self.viewPaymentType.backgroundColor = .secondary
            self.viewPaymentType.viewCorneRadius(radius: 5.0, isRound: false)
            if self.objOrderData.payment_status?.lowercased() == "pending"{
                self.viewPaymentType.backgroundColor = .secondaryText
            }
            else if self.objOrderData.payment_status?.lowercased() == "failed"{
                self.lblPaymentType.textColor = .primary
                self.viewPaymentType.backgroundColor = .redText
            }
            
            //SET OTHER BUTTONS
            self.lblLicense.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strLinces)
            self.lblTermsAndCondition.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strTerms)
            self.lblCheckListDeliv.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strCheckListDeliv)
            self.lblCheckListRet.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strCheckListRet)
            self.lblDeliveryStatus.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strDeliveyStatus)
            self.lblPickupStatus.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPickupStatus)

            self.lblPhotVideoDeli.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPhotoAndVideoDeli)
            self.lblPhotVideoRet.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPhotoAndVideoRec)
            
            //CHECK AND SET VIEW
            self.viewLicense.backgroundColor = .clear
            self.viewLicense.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: self.imgLicense, colorHex: .secondary)
            
            //GET LOACA DATA
            let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderUniqueId, strType: uploadType.image.rawValue)
            if self.objOrderData.arrLicense.count != 0 || arrData.count != 0 {
                self.lblLicense.textColor = .background
                imgColor(imgColor: self.imgLicense, colorHex: .background)
                self.viewLicense.backgroundColor = .secondary
            }
            
            
            //T&C
            self.viewTermsAndCondition.backgroundColor = .clear
            self.viewTermsAndCondition.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            self.lblTermsAndCondition.textColor = .secondary
            if self.objOrderData.terms_status == "Accepted"{
                self.lblTermsAndCondition.textColor = .background
                self.viewTermsAndCondition.backgroundColor = .secondary
            }
            else if self.objOrderData.terms_status == "Exempt"{
                self.viewTermsAndCondition.backgroundColor = .clear
                self.viewTermsAndCondition.viewBorderCorneRadius(radius: 10, borderColour: .lightGray)
                self.lblTermsAndCondition.textColor =  .lightGray
            }
            
            
            //PHOT/VIDEO DELIVERY
            self.viewPhotVideoDeli.backgroundColor = .clear
            self.viewPhotVideoDeli.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: self.imgPhotVideoDeli, colorHex: .secondary)
            
            let arrDataVideoDelivery = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderUniqueId, strType: uploadType.video_image.rawValue,strVideoType: "delivery")
            if self.objOrderData.arrProduct.contains(where: { $0.arrDeliveryMedia.count != 0 }) || arrDataVideoDelivery.count != 0 {
                self.lblPhotVideoDeli.textColor = .background
                imgColor(imgColor: self.imgPhotVideoDeli, colorHex: .background)
                self.viewPhotVideoDeli.backgroundColor = .secondary
            }
                      
            //PHOT/VIDEO RETURN
            self.viewPhotVideoRet.backgroundColor = .clear
            self.viewPhotVideoRet.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: self.imgPhotVideoRet, colorHex: .secondary)

            let arrDataVideoReturn = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderUniqueId, strType: uploadType.video_image.rawValue,strVideoType: "pickup")
            if self.objOrderData.arrProduct.contains(where: { $0.arrPickupMedia.count != 0 }) || arrDataVideoReturn.count != 0 {
                self.lblPhotVideoRet.textColor = .background
                imgColor(imgColor: self.imgPhotVideoRet, colorHex: .background)
                self.viewPhotVideoRet.backgroundColor = .secondary
            }
            
            //CHECKLIST
            self.viewCheckListDeliv.backgroundColor = .clear
            self.viewCheckListDeliv.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            self.viewCheckListDeliv.viewBorderCorneRadius(borderColour: .secondary , size: 1)

            self.viewCheckListRet.backgroundColor = .clear
            self.viewCheckListRet.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            self.viewCheckListRet.viewBorderCorneRadius(borderColour: .secondary, size: 1)

            
            imgColor(imgColor: self.imgCheckListDeliv, colorHex: .secondary )
            imgColor(imgColor: self.imgCheckListRet, colorHex: .secondary)
            
            //CHECK DELIVERY CHECKLIST
            if self.objOrderData.arrProduct.contains(where: { $0.is_delivered ?? false }) {
                self.lblCheckListDeliv.textColor = .background
                imgColor(imgColor: self.imgCheckListDeliv, colorHex: .background)
                self.viewCheckListDeliv.backgroundColor = .secondary
            }
      
            //CHECK RETURN CHECKLIST
            if self.objOrderData.arrProduct.contains(where: { $0.is_returned ?? false }) {
                self.lblCheckListRet.textColor = .background
                imgColor(imgColor: self.imgCheckListRet, colorHex: .background)
                self.viewCheckListRet.backgroundColor = .secondary
            }
            
            if self.objOrderData.arrProduct.contains(where: { $0.is_delivered ?? false }) == false {
                self.lblCheckListRet.textColor = .lightGray
                imgColor(imgColor: self.imgCheckListRet, colorHex: .lightGray)
                self.viewCheckListRet.backgroundColor = .clear
                self.viewCheckListRet.viewBorderCorneRadius(borderColour: .lightGray, size: 1)
            }

            //SET HEADER
            DispatchQueue.main.asyncAfter(deadline: .now()) {

                let height = self.objOrderData.payment_status?.lowercased() == "failed" ? 0 : self.objButtons.frame.size.height + 20
                self.objButtons.isHidden = false
                if self.objOrderData.payment_status?.lowercased() == "failed"{
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
extension OrderDetailsViewController: MFMessageComposeViewControllerDelegate, PayMentDelegate, AddNoteDelegate, LicenseUploadDelegate, TermsDelegate{
    
    @IBAction func btnCallClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
        var getNumber = ""
        if sender.tag == 0{
            getNumber = self.objOrderData.objBillingAddress?.phone ?? ""
        }
        else{
            getNumber = self.objOrderData.objDeliveryAddress?.phone ?? ""
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
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            if let presenter = pickerAlert.popoverPresentationController {
                presenter.sourceView = self.view
                presenter.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1, height: 1)
                presenter.permittedArrowDirections = []

            }
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
            if let objAddress = self.objOrderData.objBillingAddress{
                strAddress = "\(objAddress.full_address ?? "")"
            }
        }
        else{
            if let objAddress = self.objOrderData.objDeliveryAddress{
                strAddress = "\(objAddress.full_address ?? "")"
            }
        }

        if strAddress != ""{
            openAddressInMap(address: strAddress)
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
                newViewController.strAddressTryp = "Billing"
                newViewController.strTitle = str.BillingInfo
                newViewController.objAdress = self.objOrderData.objBillingAddress
            }
            else{
                newViewController.strAddressTryp = "Shipping"
                newViewController.strTitle = str.DeliveryInfo
                newViewController.objAdress = self.objOrderData.objDeliveryAddress
            }
            newViewController.strOrderUniqueId = self.strOrderUniqueId
            newViewController.orderID = "\(self.objOrderData.id ?? 0)"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
        
    }
    
    @IBAction func btnEditNoteClicked(_ sender : UIButton) {
        if self.objOrderData == nil && arrUserList.count == 0 {
            self.CallAPIforGetUsers(CatrgoryParameater: CatrgoryParameater())
            return
        }
        
        
        //ADD NOTE POPUP
        let window = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
        window?.endEditing(true)
        let aleartView = AddNoteView(frame: CGRect(x: 0, y: 0 ,width : window?.frame.width ?? 0.0, height: window?.frame.height ?? 0.0))
        aleartView.delegate = self
//        aleartView.loadPopUpView(strOrderID: self.objOrderData.unique_id ?? "", strNote: self.lblNote.text == str.strAddNote ? "" : self.lblNote.text ?? "", arr: self.arrUserList)
        aleartView.loadPopUpView(strOrderID: self.objOrderData.unique_id ?? "", strNote: str.strAddNote  , arr: self.arrUserList)
        window?.addSubview(aleartView)
    }
    
    func strAddNote(strNote: String) {
        self.CallAPIforGetOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(unique_id: self.strOrderUniqueId, product_id: self.strProductID))
    }
 
    
    @IBAction func btnPaymentClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
        if self.objOrderData.payment_status?.lowercased() == "pending"{
            //VERIFICATION POPUP
            let window = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
            window?.endEditing(true)
            let aleartView = PaymentView(frame: CGRect(x: 0, y: 0 ,width : window?.frame.width ?? 0.0, height: window?.frame.height ?? 0.0))
            aleartView.delegate = self
            aleartView.loadPopUpView(strOrderUniqueId: "\(self.objOrderData.unique_id ?? "")")
            window?.addSubview(aleartView)

        }
    }
    
    func PaymnetSuccess() {
        //CALL API
        self.CallAPIforGetOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(unique_id: self.strOrderUniqueId, product_id: self.strProductID))
    }
    

    @IBAction func btnLicenseClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "LicenseUploadViewController") as? LicenseUploadViewController{
            newViewController.delegate = self
            newViewController.arrLicense = self.objOrderData.arrLicense
            newViewController.strOrderID = self.objOrderData.unique_id ?? ""
            newViewController.selectIndex = sender.tag
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    
    func linceUploadSucess(selectIndex: Int, arrImage: [String]) {
        self.isLoading = false
        self.CallAPIforGetOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(unique_id: self.strOrderUniqueId, product_id: self.strProductID))
    }
    

    @IBAction func btnTermsAndConditionClicked(_ sender : UIButton) {
        if self.objOrderData == nil{
            return
        }
        
        
        //GET DATA
        if self.objOrderData.status == "Exempt"{
            return
        }

        
        if self.objOrderData.terms_page != ""{
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "TermsAndConditionViewController") as? TermsAndConditionViewController{
                newViewController.isOrderFrom = true
                newViewController.delegate = self
                newViewController.selectIndex = sender.tag
                newViewController.signUrl = self.objOrderData.terms_page ?? ""
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
    }
  
   
    func termsSucess(selectIndex: Int) {
        if self.objOrderData == nil{
            return
        }
        
        //UPDATE DATA
        self.objOrderData.terms_status = "Accepted"
        
        //UODATE TERMS
        self.setFooter()
    }
    
    @IBAction func btnDeliveryImageVideoUploadClicked(_ sender : UIButton) {
        //IMAGE VIDEO DELIVERY
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ImageUploadViewController") as? ImageUploadViewController {
            newViewController.strType = "delivery"
            newViewController.selectIndex = selectIndex
            newViewController.objOrderDetail = self.objOrderData
            newViewController.strOrderID = self.strOrderUniqueId
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    @IBAction func btnReturnImageVideoUploadClicked(_ sender : UIButton) {
        //IMAGE VIDEO RETURN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ImageUploadViewController") as? ImageUploadViewController {
            newViewController.strType = "pickup"
            newViewController.selectIndex = selectIndex
            newViewController.objOrderDetail = self.objOrderData
            newViewController.strOrderID = self.strOrderUniqueId
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    @IBAction func btnCheckListDelivClicked(_ sender : UIButton) {
        if self.objOrderData.arrProduct.contains(where: { $0.is_delivered ?? false }) {
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListUpdateViewController") as? CheckListUpdateViewController{
                newViewController.isUpdateData = true
                newViewController.isDeliveryType = true
                newViewController.isDeleteChecklist = true
                newViewController.selectIndex = self.selectIndex
                newViewController.strOrderUniqueId = self.strOrderUniqueId
                newViewController.strOrderID = self.strOrderID
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
        else{
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListViewController") as? CheckListViewController{
                newViewController.isDeliveryType = true
                newViewController.selectIndex = self.selectIndex
                newViewController.strOrderUniqueId = self.strOrderUniqueId
                newViewController.strOrderID = self.objOrderData.order_number ?? ""
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
    }
    
    @IBAction func btnCheckListRetClicked(_ sender : UIButton) {
        if self.objOrderData.arrProduct.contains(where: { $0.is_delivered ?? false }) == false{
            return
        }

        if self.objOrderData.arrProduct.contains(where: { $0.is_returned ?? false }) {
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListUpdateViewController") as? CheckListUpdateViewController{
                newViewController.isUpdateData = true
                newViewController.isDeliveryType = false
                newViewController.selectIndex = self.selectIndex
                newViewController.strOrderUniqueId = self.strOrderUniqueId
                newViewController.strOrderID = self.strOrderID
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
        else {
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListViewController") as? CheckListViewController{
                newViewController.isDeliveryType = false
                newViewController.selectIndex = self.selectIndex
                newViewController.strOrderUniqueId = self.strOrderUniqueId
                newViewController.strOrderID = self.objOrderData.order_number ?? ""
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
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
            return 1
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
            cell.imgProduct.backgroundColor = .white
            if let strImg = objDetails.objProductData?.product_image_url{
                cell.imgProduct.setImage(strImg: strImg)
            }

//            let getPrice = getProductTotlaPrice(productID: objDetails.id ?? 0)

        
            //SET FONT
            cell.lblProductName.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "\(objDetails.product_name ?? "") * \(objDetails.quantity ?? 0 )")
            cell.lblTotlaPrice.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "\(objDetails.total ?? "" )")
            
            
            //SET SCHEDULE DATE
            cell.lblScheduleDate.text = ""
            if objDetails.objProductData?.product_type == "Rental"{
                let strDate = setFontAttributes(str: str.sttScheduleDate, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0)
                strDate.append(setFontAttributes(str: " \(objDetails.objProductData?.pickup_date ?? "")", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0))
                cell.lblScheduleDate.attributedText = strDate
            }

            
            //CHECK OPTION
            cell.objPrice.isHidden = true
            cell.objOptions.isHidden = true
            if objDetails.objProductData?.arrProductOptions.count != 0{
//                cell.objPrice.isHidden = false
                cell.objOptions.isHidden = false
                
            }

            //SET OPTIONS VALUE
            cell.lblOptionsValues.text = ""
            cell.lblPrice.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.strPrice)
            cell.lblOptions.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: str.strOptionsTotal)


            //SET OPTION VALUE
            var strValues : String = ""
            for objOptions in objDetails.objProductData?.arrProductOptions ?? []{
                if strValues == ""{
                    strValues = "- \(objOptions.name ?? "")"
                }
                else{
                    strValues = "\(strValues)\n- \(objOptions.name ?? "")"
                }
            }

    
            cell.lblOptionsValues.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: strValues)
       
            //CHECK STORE ADDRESS
            var text : String = ""
            var linkTextWithColor : String = ""
            cell.imgStore.isHidden = false
            cell.con_imgStore.constant = 30
            cell.lblStoreAddress.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: "")

            if objDetails.objProductData?.delivery_transport_mode == "Truck"{
                cell.imgStore.image = UIImage(named: "icon_delivery_pending")
                imgColor(imgColor: cell.imgStore, colorHex: .secondary)
                
                var location : String = "Pending"
                if objDetails.equipment_location != "" && objDetails.equipment_location != nil{
                    location = objDetails.equipment_location ?? ""
                }
                text = "Delivery From : \(location)"
                linkTextWithColor = "Delivery From :"

            }
            else{
                cell.imgStore.image = UIImage(named: "icon_store")
                imgColor(imgColor: cell.imgStore, colorHex: .secondary)
                
                text = "In Store : \(objDetails.objProductData?.store_name ?? "")"
                linkTextWithColor = "In Store :"
            }
           
            let range = (text as NSString).range(of: linkTextWithColor)

            let attributedString = NSMutableAttributedString(string:text)
            attributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.secondary , range: range)

            cell.lblStoreAddress.attributedText = attributedString

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

            let destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
            destination.name = address
            
            MKMapItem.openMaps(
                with: [destination]
            )
        }
    }
}


extension UIStackView {
    func removeAllArrangedSubviews() {
        let removedSubviews = arrangedSubviews.reduce([]) { (allSubviews, subview) -> [UIView] in
            self.removeArrangedSubview(subview)
            return allSubviews + [subview]
        }
        removedSubviews.forEach { $0.removeFromSuperview() }
    }
}


//MARK: - LOCAL DATABASE MANAGE
extension OrderDetailsViewController{

    //API CALL
    func getUserDataFromLocally() {
        // Always show existing local data immediately
        let localUserData = self.getUsersData()
        if !localUserData.isEmpty {
            self.arrUserList = localUserData
        }
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            //CALL API
            self.CallAPIforGetUsers(CatrgoryParameater: CatrgoryParameater())
        }
    }
    
    func getOrderDetailFromLocally() {
        // Always show existing local data immediately
        let localData = self.getOrderDetailData(order_id: self.strOrderUniqueId)
        if localData != nil {
            self.objOrderData = localData
            self.setTheView()
        }
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            //CALL API
            self.CallAPIforGetOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(unique_id: self.strOrderUniqueId, product_id: self.strProductID))
        }
    }
        
    // MARK: - Get Local Data
    func getUsersData() -> [UserListModel] {
        if let arr = SDKUserDefault.getMappableArray(UserListModel.self, for: kFileStorageName.kOrderDetailUserData.rawValue) {
            return arr
        }
        return []
    }
    
    func getOrderDetailData(order_id: String) -> OrdersListModel? {
        if let dic = SDKUserDefault.getMappableObject(OrdersListModel.self, for: "\(kFileStorageName.kOrderDetailData.rawValue)_\(order_id)") {
            return dic
        }
        return nil
    }
    
    
    
    // MARK: - ADD / UPDATE NOTE LOCALLY (OFFLINE CASE)
    func updateDataNoInternetCase(note_dic: OrderNoteModel?, for_delete: Bool) {
        guard let dic_note = note_dic else { return }
        
        let storageKey = "\(kFileStorageName.kOrderNoteData.rawValue)"
        var arrNoteData: [OrderNoteModel] = SDKUserDefault.getMappableArray(OrderNoteModel.self, for: storageKey) ?? []
        
        // Check if note already exists
        if let index = arrNoteData.firstIndex(where: { $0.id == dic_note.id }) {
            // Replace existing note (edit case)
            arrNoteData[index] = dic_note
            print("Updated existing note")
        } else {
            // Append new note
            arrNoteData.append(dic_note)
            print("Added new note")
        }
        
        // Save updated array
        SDKUserDefault.saveMappableArray(arrNoteData, for: storageKey)
        
        if for_delete == false {
            self.saveNoteDataInOrderDetails(arr_data: arrNoteData)
        }
    }

    // MARK: - SAVE NOTE DATA INSIDE ORDER DETAILS LOCALLY
    func saveNoteDataInOrderDetails(arr_data: [OrderNoteModel]) {
        guard var localData = self.getOrderDetailData(order_id: self.strOrderUniqueId) else {
            print("No local order data")
            return
        }
        
        var arrNote = localData.arrOrderNote
        
        for note in arr_data {
            if (note.type ?? "") != "delete" && note.mainOrderUniqueID == self.strOrderUniqueId {
                if let index = arrNote.firstIndex(where: { $0.id == note.id }) {
                    // Replace existing note
                    arrNote[index] = note
                    print("Update note")
                } else {
                    // Append new note
                    arrNote.insert(note, at: 0)
                    print("Added new note")
                }
            }
        }
        
        // Save updated note array back to local data
        localData.arrOrderNote = arrNote
        
        // Save updated order object in MMKV
        SDKUserDefault.saveMappableObject(localData, for: "\(kFileStorageName.kOrderDetailData.rawValue)_\(self.strOrderUniqueId)")
        
        self.objOrderData = localData
        self.setTheView()
    }
    
    
    
    // MARK: - DELETE NOTE LOCALLY (OFFLINE CASE)
    func deleteNoteDataNoInternetCase(note_dic: OrderNoteModel?) {
        guard let dic_note = note_dic else { return }
        
        let storageKey = "\(kFileStorageName.kOrderNoteData.rawValue)"
        
        // Fetch existing notes from local MMKV
        var arrNoteData: [OrderNoteModel] = SDKUserDefault.getMappableArray(OrderNoteModel.self, for: storageKey) ?? []
        
        // Remove note from array if it exists
        if let index = arrNoteData.firstIndex(where: { $0.id == dic_note.id }) {
            arrNoteData.remove(at: index)
            
            // Save updated array back
            SDKUserDefault.saveMappableArray(arrNoteData, for: storageKey)
            
        }
        else {
            print("Note not found locally for delete")

            var dic_OrderNote = OrderNoteModel.init(JSON: [:])
            dic_OrderNote?.id = Int(randomNumber(length: 5))
            dic_OrderNote?.status = kOrderStatusType.kPending.rawValue
            dic_OrderNote?.type = kOrderStatusType.kDelete.rawValue
            dic_OrderNote?.unique_id = note_dic?.unique_id ?? ""
            dic_OrderNote?.mainOrderUniqueID = self.strOrderUniqueId
            self.updateDataNoInternetCase(note_dic: dic_OrderNote, for_delete: true)
        }
        
        // Update order details accordingly
        self.deleteNoteFromOrderDetails(note: dic_note)
    }

    
    // MARK: - DELETE NOTE INSIDE ORDER DETAILS LOCALLY
    func deleteNoteFromOrderDetails(note: OrderNoteModel) {
        guard var localData = self.getOrderDetailData(order_id: self.strOrderUniqueId) else {
            print("⚠️ No local order data found for ID \(self.strOrderUniqueId)")
            return
        }
        
        var arrNote = localData.arrOrderNote
        
        // Remove note from order details if exists
        if let index = arrNote.firstIndex(where: { $0.id == note.id }) {
            arrNote.remove(at: index)
            print("🗑️ Removed note from order details with id: \(note.id ?? 0)")
        } else {
            print("⚠️ Note not found in order details with id: \(note.id ?? 0)")
        }
        
        // Save updated data
        localData.arrOrderNote = arrNote
        SDKUserDefault.saveMappableObject(localData, for: "\(kFileStorageName.kOrderDetailData.rawValue)_\(self.strOrderUniqueId)")
        
        self.objOrderData = localData
        self.setTheView()
    }
}
