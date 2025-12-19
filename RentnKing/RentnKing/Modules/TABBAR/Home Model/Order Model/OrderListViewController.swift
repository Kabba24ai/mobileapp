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
    var arrOrderList : [OrdersListModel] = []
    var arrCategoryList : [CategoryModel] = []
    
    //OTHER
    var isLoading : Bool = true
    var objRefresh : UIRefreshControl?
    var _loadingView: UIActivityIndicatorView!
    var bool_Load: Bool = false
    var pageCount: Int = 1
    var deliveryIndex : Int = 0
    var deliveryType : String = "Delivery"

    var selectCategoryID : String = ""
    var selectStatus : String = "All"
    var selectPaymentType : String = "All"
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        NotificationCenter.default.addObserver(self, selector: #selector(startUploadData), name: .startUploadData, object: nil)
//        NotificationCenter.default.addObserver(self, selector: #selector(stopUploadData), name: .stopUploadData, object: nil)
//
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

        
        //GET CATEGORY DATA
        getCategoryList { arr_data in
            self.arrCategoryList = arr_data
        }
        

    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        setupKeyboard(false)
        syncOrderNoteWithAPI()
        
//        self.getCategorys(CatrgoryParameater: CatrgoryParameater())
        
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
        setNavigationBarForButtons(controller: self, title: str.strOderTitle, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: ["icon_Filter"], isFilter: self.checkFilter()) {
            
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
                view.arrCategorys = self.arrCategoryList
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
    
    // MARK: - Refresh Action
    @objc func refreshList() {
        self.pageCount = 1
        self.bool_Load = true

        // Always show existing local data immediately
        let localData = self.getOrderData()
        if !localData.isEmpty {
            self.arrOrderList = localData
            self.setTheView()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let params = OrdersParameater(page: "\(self.pageCount)", search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, status: self.selectStatus)
            self.fetchOrders(OrdersParameater: params, overrideLocal: true)
        }
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
    
    func checkFilter() -> Bool{
        //CEHCK FILTER
        if self.selectCategoryID != "" || self.selectStatus != "All" ||  self.selectPaymentType != "All"{
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
        if strSearch.count <= 3 {
            self.refreshList()
            return
        }
                
        //GET STORE LIST
        self.objSearchIndicator.isHidden = true
        self.objSearchIndicator.stopAnimating()
        if strSearch != "" && strSearch.count >= 3{
            self.callAPI(search: strSearch, category_id: self.selectCategoryID, selectStatus: self.selectStatus, selectPaymentType: self.selectPaymentType)
        }
        else{
            self.callAPI(search: "", category_id: self.selectCategoryID, selectStatus: self.selectStatus, selectPaymentType: self.selectPaymentType)
        }
    }
    
    func callAPI(search: String, category_id: String, selectStatus: String, selectPaymentType: String){
        //CALL API
        self.objSearchIndicator.isHidden = false
        self.objSearchIndicator.startAnimating()
        self.pageCount = 1
        self.isLoading = true
        self.arrOrderList = []
        self.emptyDataView.isHidden = true
        
        let params = OrdersParameater(page: "\(self.pageCount)", search: search, category_id: category_id, status: selectStatus, payment_method: selectPaymentType)
        fetchOrders(OrdersParameater: params, overrideLocal: false)
    }
}


extension OrderListViewController : FilterProtocol{
   
    
    func SelectFilter(categoryID: Int, strStatus: String, strPaymentType: String, strDeliveryType: String) {
        self.selectCategoryID = ""
        self.selectStatus = strStatus
        self.selectPaymentType = strPaymentType
       
        if categoryID != 0{
            self.selectCategoryID = "\(categoryID)"
        }    
        
        //CALL API
        self.setNavigation()
        self.callAPI(search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, selectStatus: self.selectStatus, selectPaymentType: self.selectPaymentType)
    }
}

//MARK: - LOCAL DATABASE MANAGE
extension OrderListViewController{
    
    // MARK: - Fetch Orders (Main Controller)
    func fetchOrders(OrdersParameater : OrdersParameater, overrideLocal: Bool = false) {
        
        let params = OrdersParameater// OrdersParameater(page: "\(page)", search: txtSearch.text ?? "", category_id: selectCategoryID, status: selectStatus)
        
        callAPIforGetOrderList(OrdersParameater: params) { [weak self] isSaved in
            guard let self = self else { return }
            
            self.isLoading = false
            self.stopAnimatingView()
            self.objRefresh?.endRefreshing()
            
            if isSaved {
                let localData = self.getOrderData()
                
                if overrideLocal {
                    // Replace all old data
                    self.arrOrderList = localData
                    self.setTheView()

                } else {
                    // Append only new unique orders
                    let newItems = localData.filter { newItem in
                        !self.arrOrderList.contains(where: { $0.id == newItem.id })
                    }
                    self.arrOrderList.append(contentsOf: newItems)
                }
                
                // Pagination Control
                if localData.count >= Int(Application.PageOrderLimit) {
                    self.bool_Load = false
                    self.pageCount += 1
                } else {
                    self.bool_Load = true
                }
            } else {
                self.bool_Load = true
            }
            
            DispatchQueue.main.async {
                self.setTheView()
            }
        }
    }
        
    // MARK: - Get Local Data
    func getOrderData() -> [OrdersListModel] {
        if let arr = SDKUserDefault.getMappableArray(OrdersListModel.self, for: kFileStorageName.kOrderList.rawValue) {
            return arr
        }
        return []
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

    @IBOutlet weak var objButtonAll: UIStackView!
    @IBOutlet weak var objButton1: UIStackView!
    @IBOutlet weak var objButton2: UIStackView!
    @IBOutlet weak var objButton3: UIStackView!
    
    @IBOutlet weak var viewPhotVideoDeli: UIView!
    @IBOutlet weak var imgPhotVideoDeli: UIImageView!
    @IBOutlet weak var lblPhotVideoDeli: UILabel!
    @IBOutlet weak var btnPhotVideoDeli: UIButton!
    
    @IBOutlet weak var viewPhotVideoRet: UIView!
    @IBOutlet weak var imgPhotVideoRet: UIImageView!
    @IBOutlet weak var lblPhotVideoRet: UILabel!
    @IBOutlet weak var btnPhotVideoRet: UIButton!

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
            viewCheckListDeliv,
            viewCheckListRet,
            viewPhotVideoDeli,
            viewPhotVideoRet,
            viewDeliveryStatus,
            viewPickupStatus,
            viewPaymentType

        ]
    }
}


//MARK: -- UITABEL DELEGATE --

//extension OrderListViewController : UITableViewDelegate, UITableViewDataSource, , LicenseUploadDelegate, , ImageVideoUploadDelegate, MachineHoursDelegate, , CheckListDelegate{
extension OrderListViewController : UITableViewDelegate, UITableViewDataSource, OrderDetailsDelegate, LicenseUploadDelegate{
    
    
    
    
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
    // MARK: - Scroll Pagination
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.view.endEditing(true)
        
        guard scrollView == tblView else { return }
        
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.frame.size.height
        
        if offsetY > contentHeight - frameHeight - 50, !bool_Load, !isLoading, txtSearch.text?.isEmpty == true {
            bool_Load = true
            isLoading = true
            
            //START LOADING
            startAnimatingView()
            
            //CALL API
            let params = OrdersParameater(page: "\(self.pageCount)", search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, status: self.selectStatus)
            fetchOrders(OrdersParameater: params)
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
            var objData : OrdersListModel!
            objData = self.arrOrderList[indexPath.row]

            //SET FONT
            cell.lblDate.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: objData.order_date ?? "")
            cell.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.customer_name ?? "")")
            
            let strPhone: String = "\(objData.objDeliveryAddress?.phone ?? "")".trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            cell.lblPhone.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: strPhone)
            imgColor(imgColor: cell.imgCall, colorHex: .secondary)
            cell.lblEmail.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "\(objData.objDeliveryAddress?.email ?? "")")
            cell.lblEmail.alpha = 0.7
            
            cell.lblLicense.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strLinces)
            cell.lblTermsAndCondition.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strTerms)
            cell.lblCheckListDeliv.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strCheckListDeliv)
            cell.lblCheckListRet.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strCheckListRet)

            cell.lblPhotVideoDeli.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPhotoAndVideoDeli)
            cell.lblPhotVideoRet.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPhotoAndVideoRec)
            cell.lblDeliveryStatus.configureLable(textColor: .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strDeliveyStatus)
            cell.lblPickupStatus.configureLable(textColor:  .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPickupStatus)

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
            let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.unique_id ?? "", strType: uploadType.image.rawValue)
            if objData.arrLicense.count != 0 || arrData.count != 0 {
                cell.lblLicense.textColor = .background
                imgColor(imgColor: cell.imgLicense, colorHex: .background)
                cell.viewLicense.backgroundColor = .secondary
            }

            
            //PHOT/VIDEO DELIVERY
            cell.viewPhotVideoDeli.backgroundColor = .clear
            cell.viewPhotVideoDeli.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: cell.imgPhotVideoDeli, colorHex: .secondary)
            
            let arrDataVideoDelivery = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.unique_id ?? "", strType: uploadType.video_image.rawValue,strVideoType: "delivery")
            if self.imageVideoDeliveryUpload(selectIndex: indexPath.row) || arrDataVideoDelivery.count != 0{
                cell.lblPhotVideoDeli.textColor = .background
                imgColor(imgColor: cell.imgPhotVideoDeli, colorHex: .background)
                cell.viewPhotVideoDeli.backgroundColor = .secondary
            }
            
            //PHOT/VIDEO RETURN
            cell.viewPhotVideoRet.backgroundColor = .clear
            cell.viewPhotVideoRet.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: cell.imgPhotVideoRet, colorHex: .secondary)

            let arrDataVideoReturn = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: objData.unique_id ?? "", strType: uploadType.video_image.rawValue,strVideoType: "pickup")
            if  self.imageVideoReturnUpload(selectIndex: indexPath.row) || arrDataVideoReturn.count != 0{
                cell.lblPhotVideoRet.textColor = .background
                imgColor(imgColor: cell.imgPhotVideoRet, colorHex: .background)
                cell.viewPhotVideoRet.backgroundColor = .secondary
            }
            
            
            //T&C
            cell.viewTermsAndCondition.backgroundColor = .clear
            cell.viewTermsAndCondition.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            cell.lblTermsAndCondition.textColor = .secondary
            if objData.terms_status == "Accepted"{
                cell.lblTermsAndCondition.textColor = .background
                cell.viewTermsAndCondition.backgroundColor = .secondary
            }
            else if objData.terms_status == "Exempt"{
                cell.viewTermsAndCondition.backgroundColor = .clear
                cell.viewTermsAndCondition.viewBorderCorneRadius(radius: 10, borderColour: .lightGray)
                cell.lblTermsAndCondition.textColor =  .lightGray
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
            
            // BUTTON ACTION
            cell.btnCall.tag = indexPath.row
            cell.btnCall.addTarget(self, action: #selector(self.btnCallClicked(_:)), for: .touchUpInside)

            cell.btnLicense.tag = indexPath.row
            cell.btnLicense.addTarget(self, action: #selector(self.btnLicenseClicked(_:)), for: .touchUpInside)

            cell.btnTermsAndCondition.tag = indexPath.row
            cell.btnTermsAndCondition.addTarget(self, action: #selector(self.btnTermsAndConditionClicked(_:)), for: .touchUpInside)

            cell.btnPhotVideoDeli.tag = indexPath.row
            cell.btnPhotVideoDeli.addTarget(self, action: #selector(self.btnDeliveryImageVideoUploadClicked(_:)), for: .touchUpInside)

            cell.btnPhotVideoRet.tag = indexPath.row
            cell.btnPhotVideoRet.addTarget(self, action: #selector(self.btnReturnImageVideoUploadClicked(_:)), for: .touchUpInside)

            cell.btnCheckListDeliv.tag = indexPath.row
            cell.btnCheckListDeliv.addTarget(self, action: #selector(self.btnCheckListDelivClicked(_:)), for: .touchUpInside)

            cell.btnCheckListRet.tag = indexPath.row
            cell.btnCheckListRet.addTarget(self, action: #selector(self.btnCheckListRetClicked(_:)), for: .touchUpInside)

            //CEHCK PRODUCT TYPE
            cell.objButton1.isHidden = false
            cell.objButton2.isHidden = false
            cell.objButton3.isHidden = false
            if self.checkProductType(arrData: objData.arrProduct){
                cell.objButton1.isHidden = true
                cell.objButton2.isHidden = true
                cell.objButton3.isHidden = true
            }
//
//            cell.btnDeliveryStatus.tag = indexPath.row
//            cell.btnDeliveryStatus.addTarget(self, action: #selector(self.btnDeliveryStatusClicked(_:)), for: .touchUpInside)
//
//            cell.btnPickupStatus.tag = indexPath.row
//            cell.btnPickupStatus.addTarget(self, action: #selector(self.btnPickupStatusClicked(_:)), for: .touchUpInside)

            
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
        
     
        //ORDER DETAILS SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
            newViewController.delegate = self
            newViewController.selectIndex = indexPath.row
            newViewController.strOrderUniqueId = objData.unique_id ?? ""
            newViewController.strOrderID = "\(objData.order_number ?? "")"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    func updateOrderDetails(selectIndex: Int, objOrderData: OrdersListModel) {
        
        //UPDATE DATA
        self.arrOrderList.remove(at: selectIndex)
        self.arrOrderList.insert(objOrderData, at: selectIndex)

        //RELOAD TABLE
        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, section: 0)], with: .automatic)
    }
    
//    

//
//    
//    
//    @objc func btnMachineHoursClicked(_ sender : UIButton) {
//        if self.arrOrderList.count == 0 || self.checkMachineHoursAllocate(selectIndex: sender.tag) == false{
//            return
//        }
//        
//    
//        
//        let objData = self.arrOrderList[sender.tag]
//    
//        
//        //TERMS AND CONDITION
//        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
//        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "MachineHoursViewController") as? MachineHoursViewController{
//            newViewController.delegate = self
//            newViewController.selectIndex = sender.tag
//            newViewController.strOrderID = "\(objData.id ?? 0)"
//            self.navigationController?.pushViewController(newViewController, animated: true)
//        }
//    }
//  
    @objc func btnCheckListDelivClicked(_ sender : UIButton) {
        
//        if checkCheckListActive(selectIndex: sender.tag) == false{
//            return
//        }
//        
        let objData = self.arrOrderList[sender.tag]
    
        if self.checkCheckListStatus(selectIndex: sender.tag, isDelivery: true){
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListUpdateViewController") as? CheckListUpdateViewController{
                newViewController.isUpdateData = true
                newViewController.isDeliveryType = true
                newViewController.isDeleteChecklist = true
                newViewController.selectIndex = sender.tag
                newViewController.strOrderUniqueId = objData.unique_id ?? ""
                newViewController.strOrderID = "\(objData.id ?? 0)"
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
        else{
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListViewController") as? CheckListViewController{
                newViewController.isDeliveryType = true
//                newViewController.delegate = self
                newViewController.selectIndex = sender.tag
                newViewController.strOrderUniqueId = objData.unique_id ?? ""
                newViewController.strOrderID = "\(objData.order_number ?? "")"

                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
        
   
    }
    
    @objc func btnCheckListRetClicked(_ sender : UIButton) {
        if self.checkCheckListStatus(selectIndex: sender.tag, isDelivery: true) == false{
            return
        }

        
//        if checkCheckListActive(selectIndex: sender.tag) == false{
//            return
//        }
        
        let objData = self.arrOrderList[sender.tag]
        
        if self.checkCheckListStatus(selectIndex: sender.tag, isDelivery: false){
            
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListUpdateViewController") as? CheckListUpdateViewController{
                newViewController.isUpdateData = true
                newViewController.isDeliveryType = false
//                newViewController.delegate = self
                newViewController.selectIndex = sender.tag
                newViewController.strOrderUniqueId = objData.unique_id ?? ""
                newViewController.strOrderID = "\(objData.id ?? 0)"
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
        else{
            
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckListViewController") as? CheckListViewController{
                newViewController.isDeliveryType = false
//                newViewController.delegate = self
                newViewController.selectIndex = sender.tag
                newViewController.strOrderUniqueId = objData.unique_id ?? ""
                newViewController.strOrderID = "\(objData.order_number ?? "")"
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
    }
//  
//    
    @objc func btnDeliveryImageVideoUploadClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0{
            return
        }
        
        //GET DATA
//        var arrImageVideoLisr : [ImageVideoModel] = []
//        for objImage in self.arrOrderList[sender.tag].order_image_links{
//            let isImageType = objImage.isImageType()
//            let url: URL = URL(fileURLWithPath: "")
//            let objData = ImageVideoModel(type: isImageType ? "img" : "video", image: UIImage(), strVideo: url, strUrl: objImage, isUpload: true)
//            arrImageVideoLisr.append(objData)
//        }
     
        
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ImageUploadViewController") as? ImageUploadViewController{
//            newViewController.delegate = self
            newViewController.strType = "delivery"
            newViewController.selectIndex = sender.tag
//            newViewController.arrImageVideoLisr = arrImageVideoLisr
            newViewController.objOrderDetail = self.arrOrderList[sender.tag]
            newViewController.strOrderID = "\(self.arrOrderList[sender.tag].unique_id ?? "")"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    
    @objc func btnReturnImageVideoUploadClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0{
            return
        }
        
        //GET DATA
//        var arrImageVideoLisr : [ImageVideoModel] = []
//        for objImage in self.arrOrderList[sender.tag].order_image_links{
//            let isImageType = objImage.isImageType()
//            let url: URL = URL(fileURLWithPath: "")
//            let objData = ImageVideoModel(type: isImageType ? "img" : "video", image: UIImage(), strVideo: url, strUrl: objImage, isUpload: true)
//            arrImageVideoLisr.append(objData)
//        }
     
        
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ImageUploadViewController") as? ImageUploadViewController{
//            newViewController.delegate = self
            newViewController.strType = "pickup"
            newViewController.selectIndex = sender.tag
//            newViewController.arrImageVideoLisr = arrImageVideoLisr
            newViewController.objOrderDetail = self.arrOrderList[sender.tag]
            newViewController.strOrderID = "\(self.arrOrderList[sender.tag].unique_id ?? "")"
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
            newViewController.arrLicense = objData.arrLicense
            newViewController.strOrderID = "\(objData.unique_id ?? "")"
            newViewController.selectIndex = sender.tag
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    func linceUploadSucess(selectIndex: Int, arrImage: [String]) {
        if self.arrOrderList.count == 0{
            return
        }

        //RELOAD CELL
        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, column: 0)], with: .none)
    }
    
    func imageVideoDeliveryUpload(selectIndex: Int)->Bool{
        if self.arrOrderList.count == 0{
            return false
        }
        
        var objData = self.arrOrderList[selectIndex]
        for obj in objData.arrProduct{
            if obj.arrDeliveryMedia.count == 0{
                return false
            }
        }
        
        return true
    }
    
    func imageVideoReturnUpload(selectIndex: Int)->Bool{
        if self.arrOrderList.count == 0{
            return false
        }
        
        var objData = self.arrOrderList[selectIndex]
        for obj in objData.arrProduct{
            if obj.arrPickupMedia.count == 0{
                return false
            }
        }
        
        return true
    }
    
    
    func checkProductType(arrData : [OrderProductModel]) -> Bool{
        for obj in arrData{
            if obj.objProductData?.product_type?.lowercased() == "rental"{
                return false
            }
        }
        return true
    }
    
//
//    
//    func UpdateMachinHours(selectIndex: Int, arrUpdateMachinHours: [MachineHoursModel]) {
//    
//        
//        if self.arrOrderList.count == 0{
//            return
//        }
//        var objData = self.arrOrderList[selectIndex]
//        objData.arrMachineHours = arrUpdateMachinHours
//        
//        //UPDATE TERMS
//        self.arrOrderList.remove(at: selectIndex)
//        self.arrOrderList.insert(objData, at: selectIndex)
//
//        //RELOAD CELL
//        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, column: 0)], with: .none)
//    }
//    
//    
//    
//    func checkMachineHoursAllocate(selectIndex: Int) -> Bool{
//        //GET DATA
//        if self.arrOrderList.count == 0{
//            return false
//        }
//        let objData = self.arrOrderList[selectIndex]
//
//        
//        for obj in objData.arrMachineHours{
//            if obj.allocated != 0{
//                return true
//            }
//        }
//        
//        return false
//    }
//    
//    func checkMachineStartHoursComplate(selectIndex: Int) -> Bool{
//        //GET DATA
//        if self.arrOrderList.count == 0{
//            return false
//        }
//        let objData = self.arrOrderList[selectIndex]
//
//        let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: "\(objData.id ?? 0)", strType: uploadType.hours.rawValue)
//        if arrData.count != 0{
//            for obj in arrData{
//                if obj.start == "" || obj.start == "0" || obj.start == "0.0" || obj.start == nil{
//                    return false
//                }
//            }
//        }
//        else{
//            for obj in objData.arrMachineHours{
//                if obj.start == 0{
//                    return false
//                }
//            }
//        }
//      
//        return true
//    }
//    
//    func checkMachineEndHoursComplate(selectIndex: Int) -> Bool{
//        //GET DATA
//        if self.arrOrderList.count == 0{
//            return false
//        }
//        let objData = self.arrOrderList[selectIndex]
//
//        let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: "\(objData.id ?? 0)", strType: uploadType.hours.rawValue)
//        if arrData.count != 0{
//            for obj in arrData{
//                if obj.end == "" || obj.end == "0" || obj.end == "0.0" || obj.end == nil{
//                    return false
//                }
//            }
//        }
//        else{
//            for obj in objData.arrMachineHours{
//                if obj.end == 0{
//                    return false
//                }
//            }
//        }
//        
//        return true
//    }
//    
//    func checkTermsAndConditionStatus(selectIndex: Int) -> Bool{
//        //GET DATA
//        if self.arrOrderList.count == 0{
//            return false
//        }
//        let objData = self.arrOrderList[selectIndex]
//
//        
//        if objData.token != "" && objData.token != nil{
//            if objData.arrProduct.count != 0{
//                for obj in objData.arrProduct{
//                    if obj.objProduct?.use_global == true {
//                        return true
//                    }
//                }
//            }
//        }
//      
//        return false
//    }
//
    func checkCheckListStatus(selectIndex: Int, isDelivery : Bool) -> Bool{
        //GET DATA
        if self.arrOrderList.count == 0{
            return false
        }
        let objData = self.arrOrderList[selectIndex]
        for obj in objData.arrProduct{
            if isDelivery {
                return obj.is_delivered ?? false

            }
            else{
                return obj.is_returned ?? false
            }
        }
        return false
    }
//
//    func checkCheckListActive(selectIndex: Int) -> Bool{
//        //GET DATA
//        if self.arrOrderList.count == 0{
//            return false
//        }
//        
//        let objData = self.arrOrderList[selectIndex]
//        
//        //GET PRODUCT DATA
//        for obj in objData.arrProduct{
//            if obj.objProduct?.checklist_id != 0{
//                return true
//            }
//        }
//        
//        return false
//    }
//
// 
//    func checkDeliveryPickupStatus(selectIndex: Int, isDeliveryType : Bool) -> (String, Bool, Int){
//        //GET DATA
//        if self.arrOrderList.count == 0{
//            return ("icon_delivery_pending", false, 0)
//        }
//        let objData = self.arrOrderList[selectIndex]
//
//        
//        var strImg : String = "icon_delivery_pending"
//        if objData.arrDeliveryStatus.count != 0{
//            
//            for obj in objData.arrDeliveryStatus{
//                if isDeliveryType{
//                    //GET IMAGE
//                    if obj.customer_delivery == 2{
//                        strImg = "icon_delivery_pending"
//                    }
//                    else{
//                        strImg = "icon_store"
//                    }
//                    
//                    //CHECK STATUS
//                    if obj.delivery_status?.value != "2"{
//                        return (strImg, false, obj.product_id ?? 0)
//                    }
//                }
//                else{
//                    //GET IMAGE
//                    if obj.customer_pickup == 2{
//                        strImg = "icon_delivery_pending"
//                    }
//                    else{
//                        strImg = "icon_store"
//                    }
//                    
//                    //CHECK STATUS
//                    if obj.pickup_status?.value != "2"{
//                        return (strImg, false, obj.product_id ?? 0)
//                    }
//                }
//            }
//        }
//        else{
//            return (strImg, false, 0)
//        }
//        
//        return (strImg, true, 0)
//    }
//    
//    
//    //CHECKLIST
    @objc func UpdateCheckListsProduct(notification : NSNotification){
        if self.arrOrderList.count == 0{
            return
        }
        
        if let userInfo = notification.userInfo,
           let arrUpdateCheckList = userInfo["checklist_data"] as? [NoteModel], let selectIndex = userInfo["index"] as? Int , let strType = userInfo["type"] as? Bool {
              
            var objData = self.arrOrderList[selectIndex]
            for obj in arrUpdateCheckList{
                let MenuID = objData.arrProduct.map{$0.id}
                if let index = MenuID.firstIndex(of: obj.productID){
                    var objProduct = objData.arrProduct[index]
                    if strType{
                        objProduct.is_delivered = true
                    }
                    else{
                        objProduct.is_returned = true
                    }
                    
                    
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
//    
//    func UpdateCheckListProduct(selectIndex: Int, arrUpdateCheckList: [NoteModel]) {
//        
//        if self.arrOrderList.count == 0{
//            return
//        }
//        
//        var objData = self.arrOrderList[selectIndex]
//        for obj in arrUpdateCheckList{
//            let MenuID = objData.arrProduct.map{$0.product_id}
//            if let index = MenuID.firstIndex(of: obj.productID){
//                var objProduct = objData.arrProduct[index]
//                objProduct.delivery_note = obj.dNote
//                objProduct.returned_note = obj.rNote
//                objProduct.delivery_emp = Int(obj.dEmplayessId) ?? 0
//                objProduct.returned_emp = Int(obj.rEmplayessId) ?? 0
//                objProduct.delivery_sign = "true"
//                objProduct.return_sign = "true"
//                
//                objData.arrProduct.remove(at: index)
//                objData.arrProduct.insert(objProduct, at: index)
//            }
//        }
//        
//        
//        //UPDATE TERMS
//        self.arrOrderList.remove(at: selectIndex)
//        self.arrOrderList.insert(objData, at: selectIndex)
//
//        //RELOAD CELL
//        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, column: 0)], with: .none)
//    }
//    
//   
//    func checkCheckListComplate(selectIndex: Int) -> Bool{
//        //GET DATA
//        if self.arrOrderList.count == 0{
//            return false
//        }
//        let objData = self.arrOrderList[selectIndex]
//
//        let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: "\(objData.id ?? 0)", strType: uploadType.checkList.rawValue)
//        if arrData.count != 0{
//            for obj in arrData{
//                if obj.checklist_delivered == "" || obj.checklist_delivered == "0" || obj.checklist_delivered == "0.0" || obj.checklist_delivered == nil || obj.checklist_returned == "" || obj.checklist_returned == "0" || obj.checklist_returned == "0.0" || obj.checklist_returned == nil{
//                    return false
//                }
//            }
//        }
//        else{
//            for obj in objData.arrProduct{
//                for objData in obj.checkList?.arrQuestions ?? []{
//                    if objData.objQuestion?.delivered == 0 ||  objData.objQuestion?.returned == 0{
//                        return false
//                    }
//                }
//            }
//        }
//      
//        return true
//    }
    


    
}




