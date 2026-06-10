//
//  ScheduleListViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 14/02/24.
//

import UIKit
import MessageUI
import EventKit
import EventKitUI
import Alamofire
extension UIButton {
    func toBarButtonItem() -> UIBarButtonItem? {
        return UIBarButtonItem(customView: self)
    }
}



class ScheduleListViewController: UIViewController, UIGestureRecognizerDelegate {

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!
    
    @IBOutlet weak var viewDelivery: UIView!
    @IBOutlet weak var lblDelivery: UILabel!
    @IBOutlet weak var imgDelivery: UIImageView!
    @IBOutlet weak var imgSelectDelivery: UIImageView!

    @IBOutlet weak var viewPickup: UIView!
    @IBOutlet weak var lblPickup: UILabel!
    @IBOutlet weak var imgPickup: UIImageView!
    @IBOutlet weak var imgSelectPickup: UIImageView!

    @IBOutlet weak var viewTodayOnly: UIView!
//    @IBOutlet weak var lblTodayOnly: UILabel!
//    var isTodayOnly : Bool = true
//    private let customTodayOnlySwitch: CustomSwitch = {
//        let sw = CustomSwitch()
//        sw.translatesAutoresizingMaskIntoConstraints = false
//        sw.onTintColor = .systemGreen
//        sw.offTintColor = .darkGray
//        sw.thumbTintColor = .white
//        sw.isOn = true
//        return sw
//    }()
    var strSelectDay = "Today"
    private let segmentedControl = CustomSegmentedControl()


    
//    @IBOutlet weak var viewPending: UIView!
//    @IBOutlet weak var lblPending: UILabel!
//    @IBOutlet weak var viewCompleted: UIView!
//    @IBOutlet weak var lblCompleted: UILabel!


    @IBOutlet weak var objSearchIndicator: UIActivityIndicatorView!

    
    //SEARCH
    @IBOutlet weak var con_statusHeight: NSLayoutConstraint!
    @IBOutlet weak var con_searchTop: NSLayoutConstraint!
    @IBOutlet var viewSearch: UIView!
    @IBOutlet var viewSearchMain: UIView!
    @IBOutlet var txtSearch: UITextField!
    @IBOutlet var btnCancelSearch: UIButton!

    
    @IBOutlet var emptyDataView : EmptyDataView!{
        didSet{
            emptyDataView.noDataFound()
            emptyDataView.isHidden = true
        }
    }
    
    
    //LOADING
    let schedulePlaceholderMarker = Placeholder()
//    var arrAllData : [SchedulesModel] = []
    var arrScheduleList : [SchedulesModel] = []
//    var arrSearchScheduleList : [SchedulesModel] = []
    var arrCategoryList : [CategoryModel] = []

    //OTHER
    var isLoading : Bool = true
    var isHeaderLoading : Bool = true
    var objRefresh : UIRefreshControl?
    var _loadingView: UIActivityIndicatorView!
    var bool_Load: Bool = false
    var pageCount: Int = 1
    var isDeliveryType : Bool = true
    var isPending : Bool = true
    var selectStatus: String = "1"
    var selectType : String = "Delivery"
//    var strFilter : String = "All"
    
    var selectCategoryID : String = ""
    var selectDeliveryType : String = "All"

    var isSelectPickup : Bool = true
    var isSelectDelivery : Bool = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setSearchBar(isHide: true)

        
        // Do any additional setup after loading the view.
        //SET REFRSH CONTROL
        self.objRefresh = UIRefreshControl()
        let refreshView = UIView(frame: CGRect(x: 0, y: view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0, width: 0, height: 0))
        self.tblView.addSubview(refreshView)
        self.objRefresh?.tintColor = UIColor.primary
        self.objRefresh?.addTarget(self, action: #selector(self.refreshList), for: .valueChanged)
        refreshView.addSubview(self.objRefresh!)
        

        
        //SET LOADING
        self.setupTableView()
        
        
        //GET CATEGORY DATA
        getCategoryList { arr_data in
            self.arrCategoryList = arr_data
        }
    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
//        self.getCategorys(CatrgoryParameater: CatrgoryParameater())

        //GET DATA
        self.refreshList()
        
        
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
    
  
    
    func setNavigation(){
        //SET NAVIGATION BAR
        setNavigationBarForButtons(controller: self, title: str.strScheduleTitle, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: ["icon_Filter", "icon_Search"], isFilter: self.checkFilter()) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in
        
            if SelectTag == 1{
                //SEARCH
                self.setSearchBar(isHide: false)

            }
            else{
                //FILTER
                let storyboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
                let view = storyboard.instantiateViewController(withIdentifier: "FilterViewController") as! FilterViewController
                view.delegate = self
                view.isScheduleScreen = true
                view.arrCategorys = self.arrCategoryList
                view.selectCategoryID = Int(self.selectCategoryID) ?? 0
                view.selectType = self.selectStatus == "1" ? "Pending" : "Completed"
                view.view.backgroundColor = UIColor.clear
                view.modalPresentationStyle = .overCurrentContext
                self.present(view, animated: false) {
                    view.view.backgroundColor = UIColor(red: 0 / 255.0, green: 0 / 255.0, blue: 0 / 255.0, alpha: 0.5)
                }
            }
        }
    }
    
    func checkFilter() -> Bool{
        //CEHCK FILTER
        if self.selectCategoryID != "" || self.selectDeliveryType != "All"{
            return true
        }
        else{
            return false
        }
    }
    
    // MARK: - Refresh Action
    @objc func refreshList() {
        self.pageCount = 1
        self.bool_Load = true
        self.isLoading = true
        self.arrScheduleList = []
        self.tblView.reloadData()


        // Always show existing local data immediately
        let localData = self.getScheduleOrderData(schedule_type: self.selectType, schedule_status: self.selectStatus == "1" ? "Pending" : "Completed")
        if !localData.isEmpty {
            self.arrScheduleList = localData
            self.setTheView()
        }
        else {
            self.arrScheduleList.removeAll()
            self.setTheView()
        }

        if NetworkReachabilityManager()!.isReachable {
            self.APICall()
        }
    }
     
    func APICall() {
        let params = OrdersParameater(page: "\(self.pageCount)", schedule_type: self.selectType, schedule_status: self.selectStatus == "1" ? "Pending" : "Completed", search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, transport_mode: self.selectDeliveryType, date_filter: self.strSelectDay)
        self.fetchOrders(OrdersParameater: params, overrideLocal: true)
    }
    
//    @objc func refreshList(){
//        //GET DATA
//        self.viewPendingCount.isHidden = true
//        self.viewPickupCount.isHidden = true
//        self.viewDeliveryCount.isHidden = true
//        self.viewCompletedCount.isHidden = true
//
//        self.isLoading = true
//        self.arrScheduleList = []
//        self.tblView.reloadData()
//        self.pageCount = 1
//        
//        self.getScheduleList(OrdersParameater: OrdersParameater(page: "\(self.pageCount)", schedule_type: self.selectType, schedule_status: self.selectStatus == "1" ? "Pending" : "Completed", search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, transport_mode: self.selectDeliveryType))
//
//    }
    
    func setTheView(){
        self.objSearchIndicator.isHidden = true
        self.objSearchIndicator.stopAnimating()

        self.viewTodayOnly.backgroundColor = .clear
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        self.viewTodayOnly.addSubview(segmentedControl)
        
        NSLayoutConstraint.activate([
            segmentedControl.centerXAnchor.constraint(equalTo: self.viewTodayOnly.centerXAnchor),
            segmentedControl.centerYAnchor.constraint(equalTo: self.viewTodayOnly.centerYAnchor),
            segmentedControl.widthAnchor.constraint(equalToConstant: 250)
        ])
        
        segmentedControl.valueChanged = { segment in
            switch segment {
            case .today:
                if self.strSelectDay != "Today"{
                    self.strSelectDay = "Today"
                    self.refreshList()
                }
                
                
            case .tomorrow:
                if self.strSelectDay != "Tomorrow"{
                    self.strSelectDay = "Tomorrow"
                    self.refreshList()
                }
                
            case .all:
                if self.strSelectDay != "All"{
                    self.strSelectDay = "All"
                    self.refreshList()
                }
            }
        }
        
//        self.viewTodayOnly.addSubview(self.customTodayOnlySwitch)
//        self.customTodayOnlySwitch.addTarget(self,action: #selector(switchChanged(_:)),for: .valueChanged)
//        self.lblTodayOnly.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 12, text: "Today Only")

        
        //SET IMAGE
        imgColor(imgColor: self.imgDelivery, colorHex: .secondary)
        imgColor(imgColor: self.imgPickup, colorHex: .secondary)
        self.setDeliveryType()
        
        //SET FONT
        self.lblDelivery.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strDelivery)
        self.lblPickup.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strPickup)
        
        self.setTheType(isDelivery: self.isDeliveryType)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            //STOP LOADING
            self.stopLoading()
            self.isLoading = false
            
            //NO DATA
            self.emptyDataView.isHidden = true
            if self.arrScheduleList.count == 0{
                self.emptyDataView.isHidden = false
            }
            
            //RELOAD DATA
            self.tblView.reloadData()
        }

    }
    
//    @objc private func switchChanged(_ sender: CustomSwitch) {
//        self.view.endEditing(true)
//        self.isTodayOnly = sender.isOn
//        self.refreshList()
//    }
    func setTheType(isDelivery : Bool){
        self.selectType = isDelivery == true ? "Delivery" : "Return"
       
        
        self.lblDelivery.textColor = isDelivery == true ? .background : .primary
        self.lblPickup.textColor = isDelivery == false ? .background : .primary

        //SET VIEW
        self.viewDelivery.viewCorneRadius(radius: 10.0, isRound: false)
        self.viewPickup.viewCorneRadius(radius: 10.0, isRound: false)
        self.viewDelivery.viewBorderCorneRadius(borderColour: .secondary)
        self.viewPickup.viewBorderCorneRadius(borderColour: .secondary)
        
        self.viewDelivery.backgroundColor = isDelivery == true ? .secondary : .clear
        self.viewPickup.backgroundColor = isDelivery == false ? .secondary : .clear
        
    }
    
    func setDeliveryType(){
        
        
        self.imgSelectDelivery.image = UIImage(named: "icon_unCheck")
        self.imgSelectPickup.image = UIImage(named: "icon_unCheck")
        if self.isSelectDelivery && self.isSelectPickup{
            self.selectDeliveryType = "All"
            
            self.imgSelectDelivery.image = UIImage(named: "icon_Check")
            self.imgSelectPickup.image = UIImage(named: "icon_Check")
        }
        else if self.isSelectDelivery && !self.isSelectPickup{
            self.selectDeliveryType = "Truck"
            self.imgSelectDelivery.image = UIImage(named: "icon_Check")

        }
        else if self.isSelectPickup && !self.isSelectDelivery{
            self.selectDeliveryType = "Store"
            self.imgSelectPickup.image = UIImage(named: "icon_Check")
        }
    }
 
    
    func stopLoading(){
        indicatorHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.schedulePlaceholderMarker.remove()
        }
    }
    
    
    
    func setSearchBar(isHide : Bool){
        //SET VIEW
        self.viewSearchMain.backgroundColor = .background
        self.viewSearchMain.viewCorneRadius(radius: 0.0, isRound: true)
        self.viewSearchMain.viewBorderCorneRadius(borderColour: .secondary)

        self.btnCancelSearch.configureLable(bgColour: .clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Cancel")
        self.txtSearch.configureText(bgColour: UIColor.clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.strSearch)
        self.txtSearch.clearButtonMode = .whileEditing
        self.txtSearch.text = ""
        
        //SET SEARCH TEXT
        self.txtSearch.addTarget(self, action: #selector(textFieldDidChangeSearch), for: .editingDidEndOnExit)
        
        self.viewSearch.isHidden = true
        self.viewDelivery.isHidden = false
        self.viewPickup.isHidden = false
        
        //SEARCH VIEW
        self.con_statusHeight.constant = 50
        self.con_searchTop.constant = -(self.viewSearch.frame.size.height)
        if isHide == false{
            self.con_statusHeight.constant = 0
            self.viewDelivery.isHidden = true
            self.viewPickup.isHidden = true
            UIView.animate(withDuration: 0.2) {
                self.viewSearch.isHidden = false
                self.con_searchTop.constant = 0
                self.txtSearch.becomeFirstResponder()
                self.view.layoutIfNeeded()
            }
        }
        
        
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
            //CALL API
            self.callAPI(search: strSearch, category_id: self.selectCategoryID, deliveryType: self.selectDeliveryType)
        }
        else{
            //CALL API
            self.callAPI(search: "", category_id: self.selectCategoryID, deliveryType: self.selectDeliveryType)
        }
    }
    
    func callAPI(search: String, category_id: String, deliveryType: String){
        //CALL API
        self.objSearchIndicator.isHidden = false
        self.objSearchIndicator.startAnimating()
        self.pageCount = 1
        self.isLoading = true
        self.arrScheduleList = []
        self.emptyDataView.isHidden = true

        self.selectDeliveryType = self.selectDeliveryType == "" ? "All" : self.selectDeliveryType
        
        let params =  OrdersParameater(page: "\(self.pageCount)", schedule_type: self.selectType, schedule_status: self.selectStatus == "1" ? "Pending" : "Completed", search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, transport_mode: self.selectDeliveryType == "" ? "All" : self.selectDeliveryType, date_filter: self.strSelectDay)
        fetchOrders(OrdersParameater: params, overrideLocal: false)
                
        //RELOAD TABLE
        self.tblView.reloadData()
    }
}



//MARK: - BUTTON ACTION
extension ScheduleListViewController {
    @IBAction func btnCancelSearchClicked(_ sender: UIButton) {
        self.setSearchBar(isHide: true)
        
        //CALL API
        self.callAPI(search: "", category_id: self.selectCategoryID, deliveryType: self.selectDeliveryType)

    }
    
    @IBAction func btnDeliveryClicked(_ sender: UIButton) {
        if self.isDeliveryType == false{
            self.isDeliveryType = true
            
            //SET VIEW
            self.setTheType(isDelivery: self.isDeliveryType)
            
            //CALL API
            self.refreshList()
        }
      
    }
    
    @IBAction func btnPickupClicked(_ sender: UIButton) {
        if self.isDeliveryType == true{
            self.isDeliveryType = false
            
            //SET VIEW
            self.setTheType(isDelivery: self.isDeliveryType)

            //CALL API
            self.refreshList()
        }
    }
    
    @IBAction func btnSelectTypeClicked(_ sender: UIButton) {
        if sender.tag == 100{
            if self.isSelectDelivery{
                self.isSelectDelivery = false
            }
            else{
                self.isSelectDelivery = true
            }
        }
        else if sender.tag == 101{
            if self.isSelectPickup{
                self.isSelectPickup = false
            }
            else{
                self.isSelectPickup = true
            }
        }
        
        //SET DATA
        self.setDeliveryType()
        
        //CALL API
        self.callAPI(search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, deliveryType: self.selectDeliveryType)

    }

}

extension ScheduleListViewController : FilterProtocol{
    func SelectFilter(categoryID: Int, strStatus: String, strPaymentType: String, strDeliveryType: String, strNotificationType: String) {
        self.selectCategoryID = ""
        self.selectDeliveryType = ""

        if categoryID != 0{
            self.selectCategoryID = "\(categoryID)"
        }
        
        
        if strDeliveryType == "Pending"{
            self.selectStatus = "1"
        }
        else if strDeliveryType == "Completed"{
            self.selectStatus = "2"
        }
        
        
        //CALL API
        self.setDeliveryType()
        self.setNavigation()
        self.callAPI(search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, deliveryType: self.selectDeliveryType)
    }
}



//MARK: - LOCAL DATABASE MANAGE
extension ScheduleListViewController{
    
    // MARK: - Fetch Orders (Main Controller)
    func fetchOrders(OrdersParameater : OrdersParameater, overrideLocal: Bool = false) {
        
        let params = OrdersParameater
        
        callAPIforGetScheduleList(OrdersParameater: params) { [weak self] isSaved in
            guard let self = self else { return }
            
            self.isLoading = false
            self.stopAnimatingView()
            self.objRefresh?.endRefreshing()
            if self.pageCount == 1{
                self.arrScheduleList = []
            }
            
            if isSaved {
                let localData = self.getScheduleOrderData(schedule_type: OrdersParameater.schedule_type, schedule_status: OrdersParameater.schedule_status)
                
                if overrideLocal {
                    // Replace all old data
                    self.arrScheduleList = localData
                } else {
                    // Append only new unique orders
                    let newItems = localData.filter { newItem in
                        !self.arrScheduleList.contains(where: { $0.id == newItem.id })
                    }
                    self.arrScheduleList.append(contentsOf: newItems)
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
    func getScheduleOrderData(schedule_type: String, schedule_status: String) -> [SchedulesModel] {
        if let arr = SDKUserDefault.getMappableArray(SchedulesModel.self, for: "\(kFileStorageName.kScheduleOrderList.rawValue)_\(schedule_type)_\(schedule_status)_\(self.strSelectDay)") {
            return arr
        }
        return []
    }
}


//MARK: -- TABLE CELL --
class ScheduleListCell : UITableViewCell{
//    @IBOutlet weak var lblOrderNumber: UILabel!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var lblPhone: UILabel!
    @IBOutlet weak var viewLine: UIView!
    @IBOutlet weak var lblProductName: UILabel!
    @IBOutlet weak var imgCall: UIImageView!
    @IBOutlet weak var btnUpdateOrder: UIButton!
    @IBOutlet weak var btnCall: UIButton!
    @IBOutlet weak var lblDateTime: UILabel!
    @IBOutlet weak var imgOrderType: UIImageView!

    @IBOutlet weak var viewDelivery: MTSlideToOpenView!
    @IBOutlet weak var viewComplate: UIView!
    @IBOutlet weak var lblComplate: UILabel!
    @IBOutlet weak var con_Delivery: NSLayoutConstraint!

    @IBOutlet weak var lblAddress: UILabel!
    @IBOutlet weak var imgMapAddress: UIImageView!
    @IBOutlet weak var btnAddress: UIButton!

    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            lblName,
            lblPhone,
            imgCall,
            lblProductName,
            viewLine,
            viewDelivery,
            lblAddress,
            imgMapAddress,
            lblDateTime,
            imgOrderType,
            viewComplate
        ]
    }
}



//MARK: -- UITABEL DELEGATE --

extension ScheduleListViewController : UITableViewDelegate, UITableViewDataSource, MFMessageComposeViewControllerDelegate , OrderDetailsDelegate{

    
   
 
    

    
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
            let params = OrdersParameater(page: "\(self.pageCount)", schedule_type: self.selectType, schedule_status: self.selectStatus == "1" ? "Pending" : "Completed", search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, transport_mode: self.selectDeliveryType, date_filter: self.strSelectDay)
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
            return self.arrScheduleList.count
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "ScheduleListCell") as? ScheduleListCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.isHidden = false
            cell.viewComplate.viewBorderCorneRadius(borderColour: .clear)

            if isLoading {
                cell.viewLine.isHidden = true
                cell.viewDelivery.viewBorderCorneRadius(borderColour: .clear)
                self.schedulePlaceholderMarker.register(cell.getAnimableSubviews())
                self.schedulePlaceholderMarker.startAnimation()
                return cell
            }
            
            //GET DATA
            let objData = self.arrScheduleList[indexPath.row]
            
            //SET FONT
            cell.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.order?.customer_name ?? "")")
//            #if DEBUG
//            cell.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.id ?? 0) : \(objData.name ?? "")")
//            #endif
            cell.lblPhone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.order?.customer_phone ?? "")")
            imgColor(imgColor: cell.imgCall, colorHex: .secondary)
            
//            cell.lblDelivery.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strLinces)
            
            //SET ADDRESS
            imgColor(imgColor: cell.imgMapAddress, colorHex: .secondary)
            cell.lblAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: "\(objData.order?.objDeliveryAddress?.full_address ?? "")")

            //SET DATE
            var strDate : String = ""
            var strTime : String = ""
            if self.selectType.lowercased() == "Delivery".lowercased(){
                //GET DELIVERY DATA
                strDate = "\(objData.delivery_date ?? "")"
                strTime = "\(objData.delivery_time ?? "")"
                
                //SET IMAGE
                if objData.delivery_transport_mode == "Truck"{
                    cell.imgOrderType.image = UIImage(named: "icon_delivery_pending")
                }
                else{
                    cell.imgOrderType.image = UIImage(named: "icon_store")
                    
                    //SET STORE ADDRESS
                    if objData.objProduct?.store_name != ""{
                        let text = "In Store : \(objData.objProduct?.store_name ?? "")"
                        let linkTextWithColor = "In Store :"

                        let range = (text as NSString).range(of: linkTextWithColor)

                        let attributedString = NSMutableAttributedString(string:text)
                        attributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.secondary , range: range)

                        cell.lblAddress.attributedText = attributedString
                    }
                }
            }
            else{
                //GET PICKUP DATA
                strDate = "\(objData.pickup_date ?? "")"
                strTime = "\(objData.pickup_time ?? "")"

                //SET IMAGE
                if objData.pickup_transport_mode  == "Truck"{
                    cell.imgOrderType.image = UIImage(named: "icon_delivery_pending")
                }
                else{
                    cell.imgOrderType.image = UIImage(named: "icon_store")
                    
                    //SET STORE ADDRESS
                    if objData.objProduct?.store_name != ""{
                        let text = "In Store : \(objData.objProduct?.store_name ?? "")"
                        let linkTextWithColor = "In Store :"

                        let range = (text as NSString).range(of: linkTextWithColor)

                        let attributedString = NSMutableAttributedString(string:text)
                        attributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.secondary , range: range)

                        cell.lblAddress.attributedText = attributedString
                    }
                    
                }
            }
            cell.lblDateTime.configureLable(textColor: .primary.withAlphaComponent(0.6), fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(strDate) \(strTime)")
            imgColor(imgColor: cell.imgOrderType, colorHex: .secondary)
            
          
            
            //SET STORE NAME
            cell.lblProductName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: "\(objData.product_name ?? "")")
            
            
            //SET VIEW
            cell.viewComplate.backgroundColor = .secondary
            cell.viewComplate.viewCorneRadius(radius: 10, isRound: false)
            cell.lblComplate.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "")

            //CHECK AND SET VIEW
            cell.viewDelivery.isHidden = true
            cell.viewComplate.isHidden = false
            cell.btnUpdateOrder.isHidden = false
            if self.selectType.lowercased() == "Delivery".lowercased(){
                if objData.delivery_status == "Completed"{
                    cell.viewDelivery.isHidden = true
                    cell.viewComplate.isHidden = false
                    cell.lblComplate.text = "Delivery completed. See order details."
                    cell.btnUpdateOrder.isHidden = true
                }
                else{
                    cell.viewComplate.backgroundColor = .clear
                    cell.viewComplate.viewBorderCorneRadius(borderColour: .secondary)
                    cell.lblComplate.text = "Update - Delivery Completed"
                    cell.lblComplate.textColor = .primary
                }
            }
            else{
                if objData.pickup_status == "Completed"{
                    cell.viewDelivery.isHidden = true
                    cell.viewComplate.isHidden = false
                    cell.lblComplate.text = "Pickup completed. See order details."
                    cell.btnUpdateOrder.isHidden = true
                }
                else{
                    cell.viewComplate.backgroundColor = .clear
                    cell.viewComplate.viewBorderCorneRadius(borderColour: .secondary)
                    cell.lblComplate.text = "Update - Pickup Completed"
                    cell.lblComplate.textColor = .primary
                }
            }

            cell.viewDelivery.isHidden = true
            cell.viewComplate.isHidden = true

        
            // BUTTON ACTION
            cell.btnUpdateOrder.tag = indexPath.row
            cell.btnUpdateOrder.addTarget(self, action: #selector(self.btnUpdateOrderClicked(_:)), for: .touchUpInside)

            cell.btnCall.tag = indexPath.row
            cell.btnCall.addTarget(self, action: #selector(self.btnCallClicked(_:)), for: .touchUpInside)

            cell.btnAddress.tag = indexPath.row
            cell.btnAddress.addTarget(self, action: #selector(self.btnMapClicked(_:)), for: .touchUpInside)

            
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
        if self.arrScheduleList.count == 0{
            return
        }
        let objData = self.arrScheduleList[indexPath.row]

        
        //ORDER DETAILS SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
            newViewController.delegate = self
            newViewController.selectIndex = indexPath.row
            newViewController.strOrderUniqueId = objData.order?.unique_id ?? ""
            newViewController.strOrderID = "\(objData.order?.order_number ?? "")"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }

    }
    
    
    func updateOrderDetails(selectIndex: Int, objOrderData: OrdersListModel) {}
    
    func getStoreAddress(arr : [ProductModel]) -> String{
        for objDetails in arr{
            if objDetails.storeAdderss != nil{
                return "\(objDetails.storeAdderss?.address ?? ""), \(objDetails.storeAdderss?.city ?? ""), \(objDetails.storeAdderss?.state ?? ""), \(objDetails.storeAdderss?.zip_code ?? "")"
            }
        }
        
        return ""
    }
    
    
    @objc func btnUpdateOrderClicked(_ sender : UIButton){
        if self.arrScheduleList.count == 0 || self.arrScheduleList.count < sender.tag{
            return
        }
        
        
        let objData = self.arrScheduleList[sender.tag]

        //GET NAME
        let productName : String = "\(objData.product_name ?? "")"

        

        if self.selectType.lowercased() == "Delivery".lowercased(){
            if objData.delivery_status != "Completed"{
                                
                //CALL API
                let alert = UIAlertController(title: Application.appName, message: "Are you sure you have deliverd '\(productName)' to \(objData.order?.customer_name ?? "")", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                   
                    self.updateStatus(UpdateStatusParameater: UpdateStatusParameater(order_product_unique_id: objData.unique_id ?? "", schedule_type: "Delivery", schedule_status: "Completed"), index: sender.tag)
                }))
                alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
                self.present(alert, animated: true)

            }
        }
        else{
            if objData.pickup_status != "Completed"{
                //CALL API
                let alert = UIAlertController(title: Application.appName, message: "Are you sure you have received '\(productName)' to \(objData.order?.customer_name ?? "")", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
                    
                    self.updateStatus(UpdateStatusParameater: UpdateStatusParameater(order_product_unique_id: objData.unique_id ?? "", schedule_type: "Return", schedule_status: "Completed"), index: sender.tag)
                }))
                alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
                self.present(alert, animated: true)

            }
        }
    }
    
    
    
    
    
    
    @objc func btnCallClicked(_ sender : UIButton) {
        if self.arrScheduleList.count == 0{
            return
        }
        let objData = self.arrScheduleList[sender.tag]

    
        var getNumber = objData.order?.customer_phone ?? ""
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
        //... handle sms screen actions
        self.dismiss(animated: true, completion: nil)
    }

    
    
    @objc func btnMapClicked(_ sender : UIButton) {
        if self.arrScheduleList.count == 0{
            return
        }
                      
        let objData = self.arrScheduleList[sender.tag]
        
        var strAddress : String = objData.order?.objDeliveryAddress?.full_address ?? ""
        if self.selectType.lowercased() == "Delivery".lowercased(){
            if objData.delivery_transport_mode == "Store"{
                strAddress = objData.objProduct?.store_address ?? ""
            }
        }
        else{
            if objData.pickup_transport_mode == "Store"{
                strAddress = objData.objProduct?.store_address ?? ""
            }
        }
        openAddressInMap(address: strAddress)
    }
}






