//
//  OrderListViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 01/02/24.
//

import UIKit
import MessageUI

class OrderListViewController: UIViewController, UIGestureRecognizerDelegate  {
    

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!
    @IBOutlet var emptyDataView : EmptyDataView!{
        didSet{
            emptyDataView.noDataFound()
            emptyDataView.isHidden = true
        }
    }
    
    //LOADING
    let orderPlaceholderMarker = Placeholder()
    var arrOrderList : [OrdersModel] = []
    
    //OTHER
    var isLoading : Bool = true
    var objRefresh : UIRefreshControl?
    var _loadingView: UIActivityIndicatorView!
    var bool_Load: Bool = false
    var pageCount: Int = 1

    override func viewDidLoad() {
        super.viewDidLoad()


        // Do any additional setup after loading the view.
        //SET REFRSH CONTROL
        self.objRefresh = UIRefreshControl()
        let refreshView = UIView(frame: CGRect(x: 0, y: view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0, width: 0, height: 0))
        self.tblView.addSubview(refreshView)
        self.objRefresh?.tintColor = UIColor.primary
        self.objRefresh?.addTarget(self, action: #selector(self.refreshList), for: .valueChanged)
        refreshView.addSubview(self.objRefresh!)
        
        //GET DATA
        self.refreshList()
        
        //SET LOADING
        self.setupTableView()
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
        setNavigationBarFor(controller: self, title: str.strOderTitle, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "icon_cart_shopping", isDetailsScree: true) {
            
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
    
    @objc func refreshList(){
        //GET DATA
        self.pageCount = 1
        self.getOrderList(OrdersParameater: OrdersParameater(page: "\(self.pageCount)"))
    }
    
    func setTheView(){
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            //STOP LOADING
            self.stopLoading()
            self.isLoading = false
            
            //NO DATA
            self.emptyDataView.isHidden = true
            if self.arrOrderList.count == 0{
                self.emptyDataView.isHidden = false
            }
            
            //RELOAD DATA
            self.tblView.reloadData()
        }
        
    }
    
    func stopLoading(){
        indicatorHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.orderPlaceholderMarker.remove()
        }
    }
}




//MARK: -- TABLE CELL --
class OrderListCell : UITableViewCell{
//    @IBOutlet weak var lblOrderNumber: UILabel!
    @IBOutlet weak var lblDate: UILabel!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var lblPhone: UILabel!
    @IBOutlet weak var lblEmail: UILabel!
    @IBOutlet weak var viewLine: UIView!
    @IBOutlet weak var lblProductName: UILabel!
    @IBOutlet weak var imgCall: UIImageView!
    @IBOutlet weak var btnCall: UIButton!

    @IBOutlet weak var viewLicense: UIView!
    @IBOutlet weak var imgLicense: UIImageView!
    @IBOutlet weak var lblLicense: UILabel!
    @IBOutlet weak var btnLicense: UIButton!

    @IBOutlet weak var viewTermsAndCondition: UIView!
    @IBOutlet weak var lblTermsAndCondition: UILabel!
    @IBOutlet weak var btnTermsAndCondition: UIButton!

    
    @IBOutlet weak var viewHours: UIView!
    @IBOutlet weak var imgHours: UIImageView!
    @IBOutlet weak var lblHours: UILabel!
    @IBOutlet weak var btnHours: UIButton!

    @IBOutlet weak var viewCheckList: UIView!
    @IBOutlet weak var imgCheckList: UIImageView!
    @IBOutlet weak var lblCheckList: UILabel!
    @IBOutlet weak var btnCheckList: UIButton!
    
    @IBOutlet weak var viewPhotVideo: UIView!
    @IBOutlet weak var imgPhotVideo: UIImageView!
    @IBOutlet weak var lblPhotVideo: UILabel!
    @IBOutlet weak var btnPhotVideo: UIButton!

    @IBOutlet weak var viewDeliveryStatus: UIView!
    @IBOutlet weak var imgDeliveryStatus: UIImageView!
    @IBOutlet weak var lblDeliveryStatus: UILabel!
    @IBOutlet weak var btnDeliveryStatus: UIButton!

    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            lblDate,
            lblName,
            lblPhone,
            imgCall,
            lblEmail,
            lblProductName,
            viewLine,
            viewLicense,
            viewTermsAndCondition,
            viewHours,
            viewCheckList,
            viewPhotVideo,
            viewDeliveryStatus
            
        ]
    }
}


//MARK: -- UITABEL DELEGATE --

extension OrderListViewController : UITableViewDelegate, UITableViewDataSource, TermsDelegate, LicenseUploadDelegate, MFMessageComposeViewControllerDelegate, ImageVideoUploadDelegate{
 
    

    
    // MARK: - LODING VIEW
    func setupTableView() {
        let viewFooter = UIView(frame: CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: 40))
        
        _loadingView = UIActivityIndicatorView(style: .medium)
        _loadingView.color = .primary
        viewFooter.addSubview(_loadingView)
        self.tblView.tableFooterView = viewFooter
        _loadingView.isHidden = true
        _loadingView.frame = CGRect(x: viewFooter.frame.size.width / 2 - 15 , y: 0, width: 30, height: 30)
        _loadingView.center = CGPoint(x: viewFooter.frame.size.width / 2, y: _loadingView.center.y)
    }
    
    func startAnimatingView() {
 
        _loadingView.center = CGPoint(x: self.tblView.frame.size.width / 2, y: _loadingView.center.y)
        _loadingView.startAnimating()
        _loadingView.isHidden = false
    }
    
    func stopAnimatingView() {
        _loadingView.stopAnimating()
        _loadingView.isHidden = true
    }
    
    
    //MARK: - Scrollview Delegate -
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.view.endEditing(true)

        if scrollView == tblView{
            if tblView.contentSize.height <= tblView.contentOffset.y + tblView.frame.size.height && tblView.contentOffset.y >= 0 {
                if self.arrOrderList.count != 0{
                    if bool_Load == false && self.arrOrderList.count != 0 {

                        //Refresh code
                        self.bool_Load = true

                        //START LOADING
                        startAnimatingView()

                        //CALL API
                        self.getOrderList(OrdersParameater: OrdersParameater(page: "\(self.pageCount)"))
                     
                    }
                }
            }
        }
    }
    
    
    //HEADER SECTION
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isLoading{
            return 10
        }
        else{
            return self.arrOrderList.count
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "OrderListCell") as? OrderListCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.isHidden = false
            
            if isLoading {
                cell.viewLine.isHidden = true
                self.orderPlaceholderMarker.register(cell.getAnimableSubviews())
                self.orderPlaceholderMarker.startAnimation()
                return cell
            }
            
            //GET DATA
            let objData = self.arrOrderList[indexPath.row]
            
            //SET FONT
            cell.lblDate.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: convertStringToNewFormateString(date: "\(objData.created_at ?? "")", withFormat: Application.serverDateFormet, newFormate: Application.passServertDAte) ?? "")
            cell.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.objAdress?.name ?? "")")
            
            let strPhone: String = "\(objData.objAdress?.phone ?? "")".trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) 
            cell.lblPhone.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: strPhone)
            imgColor(imgColor: cell.imgCall, colorHex: .secondary)
            cell.lblEmail.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "\(objData.objAdress?.email ?? "")")
            cell.lblEmail.alpha = 0.7
            
            cell.lblLicense.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strLinces)
            cell.lblTermsAndCondition.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strTerms)
            cell.lblHours.configureLable(textColor: self.checkMachineHoursAllocate(selectIndex: indexPath.row) == true ? .secondary : .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strHours)
            cell.lblCheckList.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strCheckList)
            cell.lblPhotVideo.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPhotoAndVideo)
            cell.lblDeliveryStatus.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strDeliveyStatus)

            //SET NAME
            var strProduct : String = ""
            for objProduct in objData.arrProduct{
                strProduct = "\(objProduct.product_name ?? "") * \(objProduct.qty )"
            }
            cell.lblProductName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: strProduct)

            
            
            //CHECK AND SET VIEW
            cell.viewLicense.backgroundColor = .clear
            cell.viewLicense.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: cell.imgLicense, colorHex: .secondary)
            
            if objData.license_image_links.count != 0{
                cell.lblLicense.textColor = .background
                imgColor(imgColor: cell.imgLicense, colorHex: .background)
                cell.viewLicense.backgroundColor = .secondary
            }
            
            //T&C
            cell.viewTermsAndCondition.backgroundColor = .clear
            cell.viewTermsAndCondition.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            
            if objData.customer_signature != "" && objData.customer_signature != nil{
                cell.lblTermsAndCondition.textColor = .background
                cell.viewTermsAndCondition.backgroundColor = .secondary
            }
            
            //HOURS
            cell.viewHours.backgroundColor = .clear
            cell.viewHours.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            cell.viewHours.viewBorderCorneRadius(borderColour: self.checkMachineHoursAllocate(selectIndex: indexPath.row) == true ? .secondary : .lightGray, size: 1)
            imgColor(imgColor: cell.imgHours, colorHex: self.checkMachineHoursAllocate(selectIndex: indexPath.row) == true ? .secondary : .lightGray)

//            if objData.customer_signature != "" && objData.customer_signature != nil{
//                cell.lblHours.textColor = .background
//                imgColor(imgColor: cell.imgHours, colorHex: .background)
//                cell.viewHours.backgroundColor = .secondary
//            }
            
            
            //CHECKLIST
            cell.viewCheckList.backgroundColor = .clear
            cell.viewCheckList.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: cell.imgCheckList, colorHex: .secondary)

//            if objData.customer_signature != "" && objData.customer_signature != nil{
//                cell.lblCheckList.textColor = .background
//                imgColor(imgColor: cell.imgCheckList, colorHex: .background)
//                cell.viewCheckList.backgroundColor = .secondary
//            }
            
            //PHOT/VIDEO
            cell.viewPhotVideo.backgroundColor = .clear
            cell.viewPhotVideo.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: cell.imgPhotVideo, colorHex: .secondary)

            if objData.order_image_links.count != 0{
                cell.lblPhotVideo.textColor = .background
                imgColor(imgColor: cell.imgPhotVideo, colorHex: .background)
                cell.viewPhotVideo.backgroundColor = .secondary
            }
            

            //DELIVERY STATUS
            cell.viewDeliveryStatus.backgroundColor = .clear
            cell.viewDeliveryStatus.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: cell.imgDeliveryStatus, colorHex: .secondary)

//            if objData.customer_signature != "" && objData.customer_signature != nil{
//                cell.lblDeliveryStatus.textColor = .background
//                imgColor(imgColor: cell.imgDeliveryStatus, colorHex: .background)
//                cell.viewDeliveryStatus.backgroundColor = .secondary
//            }
            
            
            // BUTTON ACTION
            cell.btnCall.tag = indexPath.row
            cell.btnCall.addTarget(self, action: #selector(self.btnCallClicked(_:)), for: .touchUpInside)

            cell.btnLicense.tag = indexPath.row
            cell.btnLicense.addTarget(self, action: #selector(self.btnLicenseClicked(_:)), for: .touchUpInside)

            cell.btnTermsAndCondition.tag = indexPath.row
            cell.btnTermsAndCondition.addTarget(self, action: #selector(self.btnTermsAndConditionClicked(_:)), for: .touchUpInside)

            cell.btnHours.tag = indexPath.row
            cell.btnHours.addTarget(self, action: #selector(self.btnMachineHoursClicked(_:)), for: .touchUpInside)

            cell.btnCheckList.tag = indexPath.row
//            cell.btnCheckList.addTarget(self, action: #selector(self.btnCheckListClicked(_:)), for: .touchUpInside)

            cell.btnPhotVideo.tag = indexPath.row
            cell.btnPhotVideo.addTarget(self, action: #selector(self.btnImageVideoUploadClicked(_:)), for: .touchUpInside)

            cell.btnDeliveryStatus.tag = indexPath.row
//            cell.btnDeliveryStatus.addTarget(self, action: #selector(self.btnDeliveryStatusClicked(_:)), for: .touchUpInside)

            
            cell.layoutIfNeeded()
            return cell

        }
        return UITableViewCell()
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
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if self.arrOrderList.count == 0{
            return
        }
     
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
            newViewController.strOrderID = "\(self.arrOrderList[indexPath.row].id ?? 0)"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    @objc func btnCallClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0{
            return
        }
        
        var getNumber = self.arrOrderList[sender.tag].objAdress?.phone ?? ""
        getNumber = getNumber.replacingOccurrences(of: "+1", with: "")
        
        let pickerAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        
      
        let cancel = UIAlertAction.init(title: "Cancel", style: UIAlertAction.Style.cancel, handler: { (action) in
            
            pickerAlert.dismiss(animated: true, completion: nil)
        })
        
        let call = UIAlertAction.init(title: "Call \(self.arrOrderList[sender.tag].objAdress?.phone ?? "")", style: UIAlertAction.Style.default, handler: { (action) in
            
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
        //... handle sms screen actions
        self.dismiss(animated: true, completion: nil)
    }

    
    
    @objc func btnMachineHoursClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0 || self.checkMachineHoursAllocate(selectIndex: sender.tag) == false{
            return
        }
     
        
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "MachineHoursViewController") as? MachineHoursViewController{
            newViewController.strOrderID = "\(self.arrOrderList[sender.tag].id ?? 0)"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    @objc func btnImageVideoUploadClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0{
            return
        }
        
        //GET DATA
        var arrImageVideoLisr : [ImageVideoModel] = []
        for objImage in self.arrOrderList[sender.tag].order_image_links{
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
            newViewController.strOrderID = "\(self.arrOrderList[sender.tag].id ?? 0)"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    
    @objc func btnLicenseClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0{
            return
        }
     
        
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "LicenseUploadViewController") as? LicenseUploadViewController{
            newViewController.delegate = self
            newViewController.arrLicense = self.arrOrderList[sender.tag].license_image_links
            newViewController.strOrderID = "\(self.arrOrderList[sender.tag].id ?? 0)"
            newViewController.selectIndex = sender.tag
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    
    @objc func btnTermsAndConditionClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0{
            return
        }
        
        var strTermsUrl : String = ""
        let objData = self.arrOrderList[sender.tag]
        if objData.token != "" && objData.token != nil{
            strTermsUrl = "\(Application.TermsURL)\(objData.token ?? "")/sign-terms?admin=true"
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
    
    func termsSucess(selectIndex: Int) {
        if self.arrOrderList.count == 0{
            return
        }
        
        var objData = self.arrOrderList[selectIndex]
        objData.customer_signature = "true"

        //UODATE TERMS
        self.arrOrderList.remove(at: selectIndex)
        self.arrOrderList.insert(objData, at: selectIndex)
        
        //RELOAD CELL
        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, column: 0)], with: .none)
    }
    
    func linceUploadSucess(selectIndex: Int, arrImage: [String]) {
        if self.arrOrderList.count == 0{
            return
        }
        
        var objData = self.arrOrderList[selectIndex]
        objData.license_image_links = arrImage
        
        //UODATE TERMS
        self.arrOrderList.remove(at: selectIndex)
        self.arrOrderList.insert(objData, at: selectIndex)
        
        //RELOAD CELL
        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, column: 0)], with: .none)
    }
    
    func ImageVideoUploadSucess(selectIndex: Int, arrImage: [String]) {
        if self.arrOrderList.count == 0{
            return
        }
        
        var objData = self.arrOrderList[selectIndex]
        objData.order_image_links = arrImage
        
        //UODATE TERMS
        self.arrOrderList.remove(at: selectIndex)
        self.arrOrderList.insert(objData, at: selectIndex)
        
        //RELOAD CELL
        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, column: 0)], with: .none)
    }
    
    func checkMachineHoursAllocate(selectIndex: Int) -> Bool{
        if self.arrOrderList.count == 0{
            return false
        }
        let objData = self.arrOrderList[selectIndex]
        for obj in objData.arrMachineHours{
            if obj.allocated != 0{
                return true
            }
        }
        
        return false
    }
}

