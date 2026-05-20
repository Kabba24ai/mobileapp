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
    @IBOutlet weak var imgSearch: UIImageView!
    @IBOutlet weak var viewSearch: UIView!
    @IBOutlet weak var txtSearch: UITextField!
    @IBOutlet weak var objSearchIndicator: UIActivityIndicatorView!
    @IBOutlet weak var con_Upload: NSLayoutConstraint!  
    @IBOutlet var emptyDataView : EmptyDataView!{
        didSet{
            emptyDataView.noDataFound()
            emptyDataView.isHidden = true
        }
    }
    
    //LOADING
    let orderPlaceholderMarker = Placeholder()
    var arrOrderList : [OrdersModel] = []
    var arrCategorys : [CategoryModel] = []
    
    //OTHER
    var isLoading : Bool = true
    var objRefresh : UIRefreshControl?
    var _loadingView: UIActivityIndicatorView!
    var bool_Load: Bool = false
    var pageCount: Int = 1
    var deliveryIndex : Int = 0
    var deliveryType : String = "Delivery"

    var selectCategoryID : String = ""
    var selectStatus : String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(startUploadData), name: .startUploadData, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopUploadData), name: .stopUploadData, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(UpdateCheckListsProduct), name: .updateCheckList, object: nil)

        // Do any additional setup after loading the view.
        //SET REFRSH CONTROLGm
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
        
        
        self.txtSearch.configureText(bgColour: UIColor.clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "", placeholder: str.strSearch)
        self.txtSearch.clearButtonMode = .whileEditing
        self.txtSearch.text = ""
        if let clearButton = txtSearch.value(forKey: "_clearButton") as? UIButton{
            let templateImage =  clearButton.imageView?.image?.withRenderingMode(.alwaysTemplate)
            // Set the template image copy as the button image
            clearButton.setImage(templateImage, for: .normal)
            // Finally, set the image color
            clearButton.tintColor = .gray
        }

    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        setupKeyboard(false)
        
        self.getCategorys()
        
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
        
        self.setNavigation()
        

    }
    
    @objc func startUploadData(){
        self.con_Upload.constant = manageFont(font: 0)
    }
    
    @objc func stopUploadData(){
        self.con_Upload.constant = 0
    }

    
    func setNavigation(){
        //SET NAVIGATION BAR
        setNavigationBarForButtons(controller: self, title: str.strOderTitle, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: ["icon_Filter", "icon_cart_shopping"], isFilter: self.checkFilter()) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in
        
            if SelectTag == 1{
                //MOVE TO CHECKOUT SCREEN
                let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
                if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckOutViewController") as? CheckOutViewController{
                    self.navigationController?.pushViewController(newViewController, animated: true)
                }
            }
            else{
                //FILTER
                let storyboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
                let view = storyboard.instantiateViewController(withIdentifier: "FilterViewController") as! FilterViewController
                view.delegate = self
                view.arrCategorys = self.arrCategorys
                view.selectCategoryID = Int(self.selectCategoryID) ?? 0
                view.selectStatus = self.selectStatus == "" ? "all" : self.selectStatus
                view.view.backgroundColor = UIColor.clear
                view.modalPresentationStyle = .overCurrentContext
                self.present(view, animated: false) {
                    view.view.backgroundColor = UIColor(red: 0 / 255.0, green: 0 / 255.0, blue: 0 / 255.0, alpha: 0.5)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
//        setupKeyboard(true)
    }
    
    @objc func refreshList(){
        //GET DATA
        self.pageCount = 1
        self.getOrderList(OrdersParameater: OrdersParameater(page: "\(self.pageCount)", search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, status: self.selectStatus))
    }
    
    func setTheView(){
        self.objSearchIndicator.isHidden = true
        self.objSearchIndicator.stopAnimating()
        
        //SET THE VIEW
        self.viewSearch.backgroundColor = .clear
        self.viewSearch.viewBorderCorneRadius(borderColour: .secondary)
        self.viewSearch.viewCorneRadius(radius: 10.0, isRound: false)
        imgColor(imgColor: self.imgSearch, colorHex: .secondary)
        
        
        //SET SEARCH TEXT
        self.txtSearch.addTarget(self, action: #selector(textFieldDidChangeSearch), for: .editingDidEndOnExit)

        
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
    
    func checkFilter() -> Bool{
        //CEHCK FILTER
        if self.selectCategoryID != "" || self.selectStatus != ""{
            return true
        }
        else{
            return false
        }
    }
    
    func stopLoading(){
        indicatorHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.orderPlaceholderMarker.remove()
        }
    }
    
    struct Item {
        let name: String
        let description: String
        var items: [Item]
    }

    struct ArrayObject {
        var items: [Item]
        // other properties...
    }

    
    // Function to search for a key in the items of ArrayObject
    func searchKey(_ key: String, in arrayObject: ArrayObject) -> Bool {
        for item in arrayObject.items {
            if item.items.contains(where: { $0.name == key }) {
                return true
            }
        }
        return false
    }

    
    
    // MARK: - UITEXTFIELD
    @objc func textFieldDidChangeSearch() {
    
        let strSearch = self.txtSearch.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        if strSearch.count <= 3{
            return
        }
        
        
        //GET STORE LIST
        self.objSearchIndicator.isHidden = true
        self.objSearchIndicator.stopAnimating()
        if strSearch != "" && strSearch.count >= 3{
     
            self.callAPI(search: strSearch, category_id: self.selectCategoryID, selectStatus: self.selectStatus)
        }
        else{
            self.callAPI(search: "", category_id: self.selectCategoryID, selectStatus: self.selectStatus)
        }
    }
    
    func callAPI(search: String, category_id: String, selectStatus: String){
        //CALL API
        self.objSearchIndicator.isHidden = false
        self.objSearchIndicator.startAnimating()
        self.pageCount = 1
        self.isLoading = true
        self.arrOrderList = []
        self.emptyDataView.isHidden = true
        self.getOrderList(OrdersParameater: OrdersParameater(page: "\(self.pageCount)", search: search, category_id: category_id, status: selectStatus))

        //RELOAD TABLE
        self.tblView.reloadData()
    }
}


extension OrderListViewController : FilterProtocol{
    func SelectFilter(categoryID: Int, strStatus: String, strDeliveryType: String) {
        self.selectCategoryID = ""
        self.selectStatus = ""

        if categoryID != 0{
            self.selectCategoryID = "\(categoryID)"
        }
        
        if strStatus != "" && strStatus.lowercased() != "all"{
            self.selectStatus = strStatus
        }
        
        //CALL API
        self.setNavigation()
        self.callAPI(search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, selectStatus: self.selectStatus)
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

    @IBOutlet weak var objButton1: UIStackView!
    @IBOutlet weak var objButton2: UIStackView!
    @IBOutlet weak var objButton3: UIStackView!
    @IBOutlet weak var viewHoursStart: UIView!
    @IBOutlet weak var imgHoursStart: UIImageView!
    @IBOutlet weak var lblHoursStart: UILabel!
    @IBOutlet weak var btnHoursStart: UIButton!

    @IBOutlet weak var viewHoursEnd: UIView!
    @IBOutlet weak var imgHoursEnd: UIImageView!
    @IBOutlet weak var lblHoursEnd: UILabel!
    @IBOutlet weak var btnHoursEnd: UIButton!

    
    @IBOutlet weak var viewPhotVideo: UIView!
    @IBOutlet weak var imgPhotVideo: UIImageView!
    @IBOutlet weak var lblPhotVideo: UILabel!
    @IBOutlet weak var btnPhotVideo: UIButton!

    @IBOutlet weak var viewCheckListDeliv: UIView!
    @IBOutlet weak var imgCheckListDeliv: UIImageView!
    @IBOutlet weak var lblCheckListDeliv: UILabel!
    @IBOutlet weak var btnCheckListDeliv: UIButton!
    
    @IBOutlet weak var viewCheckListRet: UIView!
    @IBOutlet weak var imgCheckListRet: UIImageView!
    @IBOutlet weak var lblCheckListRet: UILabel!
    @IBOutlet weak var btnCheckListRet: UIButton!
    
    @IBOutlet weak var viewDeliveryStatus: UIView!
    @IBOutlet weak var imgDeliveryStatus: UIImageView!
    @IBOutlet weak var lblDeliveryStatus: UILabel!
    @IBOutlet weak var btnDeliveryStatus: UIButton!

    @IBOutlet weak var viewPickupStatus: UIView!
    @IBOutlet weak var imgPickupStatus: UIImageView!
    @IBOutlet weak var lblPickupStatus: UILabel!
    @IBOutlet weak var btnPickupStatus: UIButton!

    @IBOutlet weak var lblPaymentType: UILabel!
    @IBOutlet weak var viewPaymentType: UIView!

    
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
            viewHoursStart,
            viewHoursEnd,
            viewCheckListDeliv,
            viewCheckListRet,
            viewPhotVideo,
            viewDeliveryStatus,
            viewPickupStatus,
            viewPaymentType

        ]
    }
}


//MARK: -- UITABEL DELEGATE --

extension OrderListViewController : UITableViewDelegate, UITableViewDataSource, TermsDelegate, LicenseUploadDelegate, MFMessageComposeViewControllerDelegate, ImageVideoUploadDelegate, MachineHoursDelegate, OrderDetailsDelegate, CheckListDelegate{
  
    

    
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
                if self.arrOrderList.count != 0 && self.txtSearch.text == ""{
                    if bool_Load == false && self.arrOrderList.count != 0 {

                        //Refresh code
                        self.bool_Load = true

                        //START LOADING
                        startAnimatingView()

                        //CALL API
                        self.getOrderList(OrdersParameater: OrdersParameater(page: "\(self.pageCount)", search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, status: self.selectStatus))
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
            
            if self.arrOrderList.count == 0{
                return cell
            }
            
            //GET DATA
            var objData : OrdersModel!
            objData = self.arrOrderList[indexPath.row]

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
            cell.lblHoursStart.configureLable(textColor: self.checkMachineHoursAllocate(selectIndex: indexPath.row) == true ? .secondary : .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strHoursStart)
            cell.lblHoursEnd.configureLable(textColor: self.checkMachineHoursAllocate(selectIndex: indexPath.row) == true ? .secondary : .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strHoursEnd)
            cell.lblCheckListDeliv.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strCheckListDeliv)
            cell.lblCheckListRet.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strCheckListRet)

            cell.lblPhotVideo.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPhotoAndVideo)
            cell.lblDeliveryStatus.configureLable(textColor: objData.arrDeliveryStatus.count != 0 ? .secondary : .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strDeliveyStatus)
            cell.lblPickupStatus.configureLable(textColor: objData.arrDeliveryStatus.count != 0 ? .secondary : .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPickupStatus)

            //SET NAME
            var strProduct : String = ""
            for objProduct in objData.arrProduct{
                if strProduct != "" {
                    strProduct = "\(strProduct)\n• \(objProduct.product_name ?? "")"
                }
                else{
                    strProduct = "• \(objProduct.product_name ?? "")"
                }
            }
            cell.lblProductName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: strProduct)

            
            
            //CHECK LICENSE
            cell.viewLicense.backgroundColor = .clear
            cell.viewLicense.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: cell.imgLicense, colorHex: .secondary)
            
            //GET LOACA DATA
            let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: "\(objData.id ?? 0)", strType: uploadType.image.rawValue)
            if objData.license_image_links.count != 0 || arrData.count != 0 || objData.addLicenseImageLocally == true{
                cell.lblLicense.textColor = .background
                imgColor(imgColor: cell.imgLicense, colorHex: .background)
                cell.viewLicense.backgroundColor = .secondary
            }
            
            //T&C
            let isTerms = self.checkTermsAndConditionStatus(selectIndex: indexPath.row)
            
            
            cell.viewTermsAndCondition.backgroundColor = .clear
            cell.viewTermsAndCondition.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            cell.viewTermsAndCondition.viewBorderCorneRadius(radius: 10, borderColour: isTerms == true ? .secondary : .lightGray)
            cell.lblTermsAndCondition.textColor = isTerms == true ? .secondary : .lightGray

            if objData.customer_signature != "" && objData.customer_signature != nil && isTerms == true{
                cell.lblTermsAndCondition.textColor = .background
                cell.viewTermsAndCondition.backgroundColor = .secondary
            }
            
            //HOURS
            cell.viewHoursStart.backgroundColor = .clear
            cell.viewHoursEnd.backgroundColor = .clear
            cell.viewHoursStart.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            cell.viewHoursEnd.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            cell.viewHoursStart.viewBorderCorneRadius(borderColour: self.checkMachineHoursAllocate(selectIndex: indexPath.row) == true ? .secondary : .lightGray, size: 1)
            cell.viewHoursEnd.viewBorderCorneRadius(borderColour: self.checkMachineHoursAllocate(selectIndex: indexPath.row) == true ? .secondary : .lightGray, size: 1)

            imgColor(imgColor: cell.imgHoursStart, colorHex: self.checkMachineHoursAllocate(selectIndex: indexPath.row) == true ? .secondary : .lightGray)
            imgColor(imgColor: cell.imgHoursEnd, colorHex: self.checkMachineHoursAllocate(selectIndex: indexPath.row) == true ? .secondary : .lightGray)

            if self.checkMachineHoursAllocate(selectIndex: indexPath.row) == true && self.checkMachineStartHoursComplate(selectIndex: indexPath.row) == true{
                cell.lblHoursStart.textColor = .background
                imgColor(imgColor: cell.imgHoursStart, colorHex: .background)
                cell.viewHoursStart.backgroundColor = .secondary
            }
            
            if self.checkMachineHoursAllocate(selectIndex: indexPath.row) == true && self.checkMachineEndHoursComplate(selectIndex: indexPath.row) == true{
                cell.lblHoursEnd.textColor = .background
                imgColor(imgColor: cell.imgHoursEnd, colorHex: .background)
                cell.viewHoursEnd.backgroundColor = .secondary
            }
            
            
            //CHECKLIST
            cell.viewCheckListDeliv.backgroundColor = .clear
            cell.viewCheckListDeliv.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            cell.viewCheckListDeliv.viewBorderCorneRadius(borderColour: .secondary , size: 1)

            cell.viewCheckListRet.backgroundColor = .clear
            cell.viewCheckListRet.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            cell.viewCheckListRet.viewBorderCorneRadius(borderColour: .secondary, size: 1)

            
            imgColor(imgColor: cell.imgCheckListDeliv, colorHex: .secondary )
            imgColor(imgColor: cell.imgCheckListRet, colorHex: .secondary)

            
            //CHECK DELIVERY CHECKLIST
            if self.checkCheckListStatus(selectIndex: indexPath.row, isDelivery: true){
                cell.lblCheckListDeliv.textColor = .background
                imgColor(imgColor: cell.imgCheckListDeliv, colorHex: .background)
                cell.viewCheckListDeliv.backgroundColor = .secondary
            }
      
            //CHECK RETURN CHECKLIST
            if self.checkCheckListStatus(selectIndex: indexPath.row, isDelivery: false){
                cell.lblCheckListRet.textColor = .background
                imgColor(imgColor: cell.imgCheckListRet, colorHex: .background)
                cell.viewCheckListRet.backgroundColor = .secondary
            }
            
            if self.checkCheckListStatus(selectIndex: indexPath.row, isDelivery: true) == false{
                cell.lblCheckListRet.textColor = .lightGray
                imgColor(imgColor: cell.imgCheckListRet, colorHex: .lightGray)
                cell.viewCheckListRet.backgroundColor = .clear
                cell.viewCheckListRet.viewBorderCorneRadius(borderColour: .lightGray, size: 1)
            }
            
            
            if checkCheckListActive(selectIndex: indexPath.row) == false{
                cell.lblCheckListDeliv.textColor = .lightGray
                imgColor(imgColor: cell.imgCheckListDeliv, colorHex: .lightGray)
                cell.viewCheckListDeliv.backgroundColor = .clear
                cell.viewCheckListDeliv.viewBorderCorneRadius(borderColour: .lightGray, size: 1)

                cell.lblCheckListRet.textColor = .lightGray
                imgColor(imgColor: cell.imgCheckListRet, colorHex: .lightGray)
                cell.viewCheckListRet.backgroundColor = .clear
                cell.viewCheckListRet.viewBorderCorneRadius(borderColour: .lightGray, size: 1)
            }

            //PHOT/VIDEO
            cell.viewPhotVideo.backgroundColor = .clear
            cell.viewPhotVideo.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: cell.imgPhotVideo, colorHex: .secondary)

            let arrDataVideo = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: "\(objData.id ?? 0)", strType: uploadType.video_image.rawValue)
            if objData.order_image_links.count != 0 || arrDataVideo.count != 0{
                cell.lblPhotVideo.textColor = .background
                imgColor(imgColor: cell.imgPhotVideo, colorHex: .background)
                cell.viewPhotVideo.backgroundColor = .secondary
            }
            

            //DELIVERY STATUS
            let getDeliveryData = checkDeliveryPickupStatus(selectIndex: indexPath.row, isDeliveryType: true)

            cell.viewDeliveryStatus.backgroundColor = .clear
            cell.viewDeliveryStatus.viewBorderCorneRadius(radius: 10, borderColour: objData.arrDeliveryStatus.count != 0 ? .secondary : .lightGray)
            cell.imgDeliveryStatus.image = UIImage(named: getDeliveryData.0)
            imgColor(imgColor: cell.imgDeliveryStatus, colorHex: objData.arrDeliveryStatus.count != 0 ? .secondary : .lightGray)
            
            if getDeliveryData.1 == true{
                cell.lblDeliveryStatus.textColor = .background
                imgColor(imgColor: cell.imgDeliveryStatus, colorHex: .background)
                cell.viewDeliveryStatus.backgroundColor = .secondary
            }
            
            //PICKUP STATUS
            let getPickupData = checkDeliveryPickupStatus(selectIndex: indexPath.row, isDeliveryType: false)

            cell.viewPickupStatus.backgroundColor = .clear
            cell.viewPickupStatus.viewBorderCorneRadius(radius: 10, borderColour: objData.arrDeliveryStatus.count != 0 ? .secondary : .lightGray)
            cell.imgPickupStatus.image = UIImage(named: getPickupData.0)
            imgColor(imgColor: cell.imgPickupStatus, colorHex: objData.arrDeliveryStatus.count != 0 ? .secondary : .lightGray)

            if getPickupData.1 == true{
                cell.lblPickupStatus.textColor = .background
                imgColor(imgColor: cell.imgPickupStatus, colorHex: .background)
                cell.viewPickupStatus.backgroundColor = .secondary
            }
            
            //CEHCK BUTTON
            cell.objButton1.isHidden = false
            cell.objButton2.isHidden = false
            cell.objButton3.isHidden = false
            cell.lblPaymentType.text = ""
            cell.viewPaymentType.backgroundColor = .clear
            if objData.payment?.status?.label?.lowercased() == "failed"{
                cell.viewPaymentType.backgroundColor = .redText
                cell.viewPaymentType.viewCorneRadius(radius: 5.0, isRound: false)
                cell.lblPaymentType.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: objData.payment?.status?.label ?? "")

                
                cell.objButton1.isHidden = true
                cell.objButton2.isHidden = true
                cell.objButton3.isHidden = true
            }
            
            // BUTTON ACTION
            cell.btnCall.tag = indexPath.row
            cell.btnCall.addTarget(self, action: #selector(self.btnCallClicked(_:)), for: .touchUpInside)

            cell.btnLicense.tag = indexPath.row
            cell.btnLicense.addTarget(self, action: #selector(self.btnLicenseClicked(_:)), for: .touchUpInside)

            cell.btnTermsAndCondition.tag = indexPath.row
            cell.btnTermsAndCondition.addTarget(self, action: #selector(self.btnTermsAndConditionClicked(_:)), for: .touchUpInside)

            cell.btnHoursStart.tag = indexPath.row
            cell.btnHoursStart.addTarget(self, action: #selector(self.btnMachineHoursClicked(_:)), for: .touchUpInside)

            cell.btnHoursEnd.tag = indexPath.row
            cell.btnHoursEnd.addTarget(self, action: #selector(self.btnMachineHoursClicked(_:)), for: .touchUpInside)

            
            cell.btnCheckListDeliv.tag = indexPath.row
            cell.btnCheckListDeliv.addTarget(self, action: #selector(self.btnCheckListDelivClicked(_:)), for: .touchUpInside)

            cell.btnCheckListRet.tag = indexPath.row
            cell.btnCheckListRet.addTarget(self, action: #selector(self.btnCheckListRetClicked(_:)), for: .touchUpInside)

            
            cell.btnPhotVideo.tag = indexPath.row
            cell.btnPhotVideo.addTarget(self, action: #selector(self.btnImageVideoUploadClicked(_:)), for: .touchUpInside)

            cell.btnDeliveryStatus.tag = indexPath.row
            cell.btnDeliveryStatus.addTarget(self, action: #selector(self.btnDeliveryStatusClicked(_:)), for: .touchUpInside)

            cell.btnPickupStatus.tag = indexPath.row
            cell.btnPickupStatus.addTarget(self, action: #selector(self.btnPickupStatusClicked(_:)), for: .touchUpInside)

            
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
        
        //GET DATA
        let objData = self.arrOrderList[indexPath.row]
        
     
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
            newViewController.delegate = self
            newViewController.selectIndex = indexPath.row
            newViewController.strOrderID = "\(objData.id ?? 0)"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    func updateOrderDetails(selectIndex: Int, objOrderData: OrdersModel) {
        
        //UPDATE DATA
        self.arrOrderList.remove(at: selectIndex)
        self.arrOrderList.insert(objOrderData, at: selectIndex)

        //RELOAD TABLE
        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, section: 0)], with: .automatic)
    }
    
    
    @objc func btnCallClicked(_ sender : UIButton) {
        
        if self.arrOrderList.count == 0{
            return
        }
        
        //GET DATA
        let objData = self.arrOrderList[sender.tag]
        
        var getNumber = objData.objAdress?.phone ?? ""
        getNumber = getNumber.replacingOccurrences(of: "+1", with: "")
        
        let pickerAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        
      
        let cancel = UIAlertAction.init(title: "Cancel", style: UIAlertAction.Style.cancel, handler: { (action) in
            
            pickerAlert.dismiss(animated: true, completion: nil)
        })
        
        let call = UIAlertAction.init(title: "Call \(objData.objAdress?.phone ?? "")", style: UIAlertAction.Style.default, handler: { (action) in
            
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
        
    
        
        let objData = self.arrOrderList[sender.tag]
    
        
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "MachineHoursViewController") as? MachineHoursViewController{
            newViewController.delegate = self
            newViewController.selectIndex = sender.tag
            newViewController.strOrderID = "\(objData.id ?? 0)"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
  
    @objc func btnCheckListDelivClicked(_ sender : UIButton) {
        
        if checkCheckListActive(selectIndex: sender.tag) == false{
            return
        }
        
        let objData = self.arrOrderList[sender.tag]
    
        if self.checkCheckListStatus(selectIndex: sender.tag, isDelivery: true){
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListUpdateViewController") as? CheckListUpdateViewController{
                newViewController.isUpdateData = true
                newViewController.isDeliveryType = true
                newViewController.delegate = self
                newViewController.selectIndex = sender.tag
                newViewController.strOrderID = "\(objData.id ?? 0)"
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
        else{
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListViewController") as? CheckListViewController{
                newViewController.isDeliveryType = true
                newViewController.delegate = self
                newViewController.selectIndex = sender.tag
                newViewController.strOrderID = "\(objData.id ?? 0)"
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
        
   
    }
    
    @objc func btnCheckListRetClicked(_ sender : UIButton) {
        if self.checkCheckListStatus(selectIndex: sender.tag, isDelivery: true) == false{
            return
        }
        
        if checkCheckListActive(selectIndex: sender.tag) == false{
            return
        }
        
        let objData = self.arrOrderList[sender.tag]
        
        if self.checkCheckListStatus(selectIndex: sender.tag, isDelivery: false){
            
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListUpdateViewController") as? CheckListUpdateViewController{
                newViewController.isUpdateData = true
                newViewController.isDeliveryType = false
                newViewController.delegate = self
                newViewController.selectIndex = sender.tag
                newViewController.strOrderID = "\(objData.id ?? 0)"
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
        else{
            
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListViewController") as? CheckListViewController{
                newViewController.isDeliveryType = false
                newViewController.delegate = self
                newViewController.selectIndex = sender.tag
                newViewController.strOrderID = "\(objData.id ?? 0)"
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
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
        
        //GET DATA
        let objData = self.arrOrderList[sender.tag]
    
        
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "LicenseUploadViewController") as? LicenseUploadViewController{
            newViewController.delegate = self
            newViewController.arrLicense = objData.license_image_links
            newViewController.strOrderID = "\(objData.id ?? 0)"
            newViewController.selectIndex = sender.tag
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    
    @objc func btnTermsAndConditionClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0{
            return
        }
        
        //GET DATA
        let objData = self.arrOrderList[sender.tag]
        
        if self.checkTermsAndConditionStatus(selectIndex: sender.tag) == true{
            var strTermsUrl : String = ""
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
    }
    
    @objc func btnDeliveryStatusClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0{
            return
        }
        
        //GET DATA
        let objData = self.arrOrderList[sender.tag]

        
        //GET
        let getDeliveryData = checkDeliveryPickupStatus(selectIndex: sender.tag, isDeliveryType: true)
        if getDeliveryData.1 == false{
            //GET PRODUCT NAME
            
            let MenuID = objData.arrProduct.map{$0.product_id}
            if let index = MenuID.firstIndex(of: getDeliveryData.2){
                let productName = objData.arrProduct[index].product_name
                
                
                //CALL API
                let alert = UIAlertController(title: Application.appName, message: "Are you sure you have deliverd '\(productName ?? "")' to \(objData.objAdress?.name ?? "" )", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                   
                    let MenuID = objData.arrDeliveryStatus.map{$0.product_id}
                    if let index = MenuID.firstIndex(of: getDeliveryData.2){
                        self.deliveryIndex = index
                        self.deliveryType = "Delivery"
                        
                        self.updateStatus(UpdateStatusParameater: UpdateStatusParameater(id: "\(objData.arrDeliveryStatus[index].id ?? 0)", delivery_status: "2", pickup_status: ""), index: sender.tag)
                    }
               
                }))
                alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
                self.present(alert, animated: true)
            }
        }
    }
    
    @objc func btnPickupStatusClicked(_ sender : UIButton) {
      
        if self.arrOrderList.count == 0{
            return
        }
        //GET DATA
        let objData = self.arrOrderList[sender.tag]

        
        //GET
        let getDeliveryData = checkDeliveryPickupStatus(selectIndex: sender.tag, isDeliveryType: false)
        if getDeliveryData.1 == false{
            //GET PRODUCT NAME
            
            let MenuID = objData.arrProduct.map{$0.product_id}
            if let index = MenuID.firstIndex(of: getDeliveryData.2){
                let productName = objData.arrProduct[index].product_name
                
                
                //CALL API
                let alert = UIAlertController(title: Application.appName, message: "Are you sure you have received '\(productName ?? "")' to \(objData.objAdress?.name ?? "" )", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                    
                    let MenuID = objData.arrDeliveryStatus.map{$0.product_id}
                    if let index = MenuID.firstIndex(of: getDeliveryData.2){
                        self.deliveryIndex = index
                        self.deliveryType = "Pickup"

                        self.updateStatus(UpdateStatusParameater: UpdateStatusParameater(id: "\(objData.arrDeliveryStatus[index].id ?? 0)", delivery_status: "", pickup_status: "2"), index: sender.tag)
                    }
               
                }))
                alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
                self.present(alert, animated: true)
            }
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
        
        let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: "\(objData.id ?? 0)", strType: uploadType.image.rawValue)
        if arrData.count != 0{
            objData.addLicenseImageLocally = true
        }
        
        
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
        
        //UPDATE TERMS
        self.arrOrderList.remove(at: selectIndex)
        self.arrOrderList.insert(objData, at: selectIndex)

       
        
        //RELOAD CELL
        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, column: 0)], with: .none)
    }
    
    
    
    func UpdateMachinHours(selectIndex: Int, arrUpdateMachinHours: [MachineHoursModel]) {
    
        
        if self.arrOrderList.count == 0{
            return
        }
        var objData = self.arrOrderList[selectIndex]
        objData.arrMachineHours = arrUpdateMachinHours
        
        //UPDATE TERMS
        self.arrOrderList.remove(at: selectIndex)
        self.arrOrderList.insert(objData, at: selectIndex)

        //RELOAD CELL
        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, column: 0)], with: .none)
    }
    
    
    
    func checkMachineHoursAllocate(selectIndex: Int) -> Bool{
        //GET DATA
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
    
    func checkMachineStartHoursComplate(selectIndex: Int) -> Bool{
        //GET DATA
        if self.arrOrderList.count == 0{
            return false
        }
        let objData = self.arrOrderList[selectIndex]

        let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: "\(objData.id ?? 0)", strType: uploadType.hours.rawValue)
        if arrData.count != 0{
            for obj in arrData{
                if obj.start == "" || obj.start == "0" || obj.start == "0.0" || obj.start == nil{
                    return false
                }
            }
        }
        else{
            for obj in objData.arrMachineHours{
                if obj.start == 0{
                    return false
                }
            }
        }
      
        return true
    }
    
    func checkMachineEndHoursComplate(selectIndex: Int) -> Bool{
        //GET DATA
        if self.arrOrderList.count == 0{
            return false
        }
        let objData = self.arrOrderList[selectIndex]

        let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: "\(objData.id ?? 0)", strType: uploadType.hours.rawValue)
        if arrData.count != 0{
            for obj in arrData{
                if obj.end == "" || obj.end == "0" || obj.end == "0.0" || obj.end == nil{
                    return false
                }
            }
        }
        else{
            for obj in objData.arrMachineHours{
                if obj.end == 0{
                    return false
                }
            }
        }
        
        return true
    }
    
    func checkTermsAndConditionStatus(selectIndex: Int) -> Bool{
        //GET DATA
        if self.arrOrderList.count == 0{
            return false
        }
        let objData = self.arrOrderList[selectIndex]

        
        if objData.token != "" && objData.token != nil{
            if objData.arrProduct.count != 0{
                for obj in objData.arrProduct{
                    if obj.objProduct?.use_global == true {
                        return true
                    }
                }
            }
        }
      
        return false
    }
    
    func checkCheckListStatus(selectIndex: Int, isDelivery : Bool) -> Bool{
        //GET DATA
        if self.arrOrderList.count == 0{
            return false
        }
        let objData = self.arrOrderList[selectIndex]
        for obj in objData.arrProduct{
            if isDelivery {
                if obj.delivery_emp != 0 && obj.delivery_sign != ""{
                    return true
                }
            }
            else{
                if  obj.returned_emp != 0 && obj.return_sign != ""{
                    return true
                }
            }
            
        }
      
        return false
    }

    func checkCheckListActive(selectIndex: Int) -> Bool{
        //GET DATA
        if self.arrOrderList.count == 0{
            return false
        }
        
        let objData = self.arrOrderList[selectIndex]
        
        //GET PRODUCT DATA
        for obj in objData.arrProduct{
            if obj.objProduct?.checklist_id != 0{
                return true
            }
        }
        
        return false
    }

 
    func checkDeliveryPickupStatus(selectIndex: Int, isDeliveryType : Bool) -> (String, Bool, Int){
        //GET DATA
        if self.arrOrderList.count == 0{
            return ("icon_delivery_pending", false, 0)
        }
        let objData = self.arrOrderList[selectIndex]

        
        var strImg : String = "icon_delivery_pending"
        if objData.arrDeliveryStatus.count != 0{
            
            for obj in objData.arrDeliveryStatus{
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
    
    
    //CHECKLIST
    @objc func UpdateCheckListsProduct(notification : NSNotification){
        if self.arrOrderList.count == 0{
            return
        }
        
        if let userInfo = notification.userInfo,
             let arrUpdateCheckList = userInfo["checklist_data"] as? [NoteModel], let selectIndex = userInfo["index"] as? Int {
              
            var objData = self.arrOrderList[selectIndex]
            for obj in arrUpdateCheckList{
                let MenuID = objData.arrProduct.map{$0.product_id}
                if let index = MenuID.firstIndex(of: obj.productID){
                    var objProduct = objData.arrProduct[index]
                    objProduct.delivery_note = obj.dNote
                    objProduct.returned_note = obj.rNote
                    objProduct.delivery_emp = Int(obj.dEmplayessId) ?? 0
                    objProduct.returned_emp = Int(obj.rEmplayessId) ?? 0
                    objProduct.delivery_sign = "true"
                    objProduct.return_sign = "true"
                    
                    objData.arrProduct.remove(at: index)
                    objData.arrProduct.insert(objProduct, at: index)
                }
            }
            
            
            //UPDATE TERMS
            self.arrOrderList.remove(at: selectIndex)
            self.arrOrderList.insert(objData, at: selectIndex)
            
            //RELOAD CELL
            self.tblView.reloadRows(at: [IndexPath(row: selectIndex, column: 0)], with: .none)
          }
    }
    
    func UpdateCheckListProduct(selectIndex: Int, arrUpdateCheckList: [NoteModel]) {
        
        if self.arrOrderList.count == 0{
            return
        }
        
        var objData = self.arrOrderList[selectIndex]
        for obj in arrUpdateCheckList{
            let MenuID = objData.arrProduct.map{$0.product_id}
            if let index = MenuID.firstIndex(of: obj.productID){
                var objProduct = objData.arrProduct[index]
                objProduct.delivery_note = obj.dNote
                objProduct.returned_note = obj.rNote
                objProduct.delivery_emp = Int(obj.dEmplayessId) ?? 0
                objProduct.returned_emp = Int(obj.rEmplayessId) ?? 0
                objProduct.delivery_sign = "true"
                objProduct.return_sign = "true"
                
                objData.arrProduct.remove(at: index)
                objData.arrProduct.insert(objProduct, at: index)
            }
        }
        
        
        //UPDATE TERMS
        self.arrOrderList.remove(at: selectIndex)
        self.arrOrderList.insert(objData, at: selectIndex)

        //RELOAD CELL
        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, column: 0)], with: .none)
    }
    
   
    func checkCheckListComplate(selectIndex: Int) -> Bool{
        //GET DATA
        if self.arrOrderList.count == 0{
            return false
        }
        let objData = self.arrOrderList[selectIndex]

        let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: "\(objData.id ?? 0)", strType: uploadType.checkList.rawValue)
        if arrData.count != 0{
            for obj in arrData{
                if obj.checklist_delivered == "" || obj.checklist_delivered == "0" || obj.checklist_delivered == "0.0" || obj.checklist_delivered == nil || obj.checklist_returned == "" || obj.checklist_returned == "0" || obj.checklist_returned == "0.0" || obj.checklist_returned == nil{
                    return false
                }
            }
        }
        else{
            for obj in objData.arrProduct{
                for objData in obj.checkList?.arrQuestions ?? []{
                    if objData.objQuestion?.delivered == 0 ||  objData.objQuestion?.returned == 0{
                        return false
                    }
                }
            }
        }
      
        return true
    }
    


    
}

