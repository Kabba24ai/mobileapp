//
//  DispatchListViewController.swift
//  RentnKing
//
//  Dispatch shows Deliveries + Returns combined for a driver, sorted by priority.
//  Differences from Schedule: no Delivery/Return toggle; combined list; Start/End point;
//  priority-based sort; Today/Tomorrow/All date chips; admin PIN to see all drivers.
//

import UIKit
import MessageUI
import Alamofire
import ObjectMapper

class DispatchListViewController: UIViewController, UIGestureRecognizerDelegate, DriverChecklistDelegate {

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!
    
    @IBOutlet weak var imgSelectDriver: UIImageView!
    @IBOutlet weak var lblSelectDriver: UILabel!

    @IBOutlet weak var viewDelivery: UIView!
    @IBOutlet weak var lblDelivery: UILabel!
    @IBOutlet weak var imgDelivery: UIImageView!
    @IBOutlet weak var imgSelectDelivery: UIImageView!

    @IBOutlet weak var viewPickup: UIView!
    @IBOutlet weak var lblPickup: UILabel!
    @IBOutlet weak var imgPickup: UIImageView!
    @IBOutlet weak var imgSelectPickup: UIImageView!

    @IBOutlet weak var viewTodayOnly: UIView!
    @IBOutlet weak var viewSelectDriver: UIView!

    
    @IBOutlet weak var objSearchIndicator: UIActivityIndicatorView!

    
    //SEARCH
    @IBOutlet weak var con_statusHeight: NSLayoutConstraint!
    @IBOutlet weak var con_searchTop: NSLayoutConstraint!
    @IBOutlet var viewSearch: UIView!
    @IBOutlet var viewSearchMain: UIView!
    @IBOutlet var txtSearch: UITextField!
    @IBOutlet var btnCancelSearch: UIButton!

   
    
    

    @IBOutlet var emptyDataView: EmptyDataView! {
        didSet {
            emptyDataView.noDataFound()
            emptyDataView.isHidden = true
        }
    }


    // MARK: - State
    var arrDispatchList : [SchedulesModel] = []

    var isLoading = true
    var bool_Load = false
    var pageCount = 1
    var objRefresh: UIRefreshControl?
    var _loadingView: UIActivityIndicatorView!

    // Filters
    var isDeliverySelect : Bool = true
    var isReturnSelect : Bool = true


    var isSelectPickup : Bool = false
    var isSelectDelivery : Bool = true
    var selectDeliveryType : String = "Truck"

    private let segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Today", "All"])
        control.selectedSegmentIndex = 0   // default: Today
        return control
    }()
    var strSelectDay = "Today"
    let dispatchPlaceholderMarker = Placeholder()


    var selectStatus: String = "1"
    var selectCategoryID : String = ""
    var arrCategoryList : [CategoryModel] = []
    var arrDriverEmployesList : [EmployeesModel] = []

    var selectDriver : String = "All Drivers"
    var selectDriverID : String = ""
    
    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setSearchBar(isHide: true)

        //RESTORE TODAY'S SELECTED DRIVER (cleared automatically on a new day)
        self.restoreSelectedDriverForToday()

        
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
        
        
         //GET EMPLOYEE LIST DATA
         getDriverEmployeeList { arr_data in
             self.arrDriverEmployesList = arr_data
             
             //ADD
             let map = Map(mappingType: .fromJSON, JSON: [:])
             var objDriver = EmployeesModel(map: map)
             objDriver?.name = "All Drivers"
             self.arrDriverEmployesList.insert(objDriver!, at: 0)
             
             self.setTheView()
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
        setNavigationBarForButtons(controller: self, title: str.strDispatchTitle, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: ["icon_HomeSelect"], isFilter: false) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in
        
            if SelectTag == 1{
                // Home — Store List popup
                let vc = StoreListViewController()
                vc.view.backgroundColor = .clear
                vc.modalPresentationStyle = .overCurrentContext
                self.present(vc, animated: false) {
                    vc.showPopup()
                }
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
  
    
    // MARK: - Refresh Action
    @objc func refreshList() {
        self.pageCount = 1
        self.bool_Load = true
        self.isLoading = true
        self.arrDispatchList = []
        self.tblView.reloadData()
        self.setTheView()

        // Always show existing local data immediately
        let localData = self.getDispatchOrderData(schedule_type: self.selectScheduleType())
        if !localData.isEmpty {
            self.arrDispatchList = localData
            self.setTheView()
        }
        else {
            self.arrDispatchList.removeAll()
            self.setTheView()
        }

        if NetworkReachabilityManager()?.isReachable == true {
            self.APICall()
        }
    }
    
    func selectScheduleType() -> String{
        if self.isDeliverySelect == true && self.isReturnSelect == false {
            return "Delivery"
        }
        else if self.isDeliverySelect == false && self.isReturnSelect == true {
            return "Return"
        }
        return "All"
    }

     
    func APICall() {
        let params = DispatchParameater(page: "\(self.pageCount)", schedule_type: self.selectScheduleType(), schedule_status: self.selectStatus == "1" ? "Pending" : "Completed", category_id: self.selectCategoryID, search: self.txtSearch.text ?? "", transport_mode: self.selectDeliveryType, date_filter: self.strSelectDay, driver_id: self.selectDriverID)
        self.fetchDispatchOrders(DispatchParameater: params, overrideLocal: true)
    }
    
    
    func setTheView(){
        self.objSearchIndicator.isHidden = true
        self.objSearchIndicator.stopAnimating()

        self.viewSelectDriver.backgroundColor = .clear

        // Today / All toggle (design only) — pinned to the right of the "All Driver" row
        if segmentedControl.superview == nil {
            segmentedControl.translatesAutoresizingMaskIntoConstraints = false
            segmentedControl.selectedSegmentIndex = 0   // default: Today
            segmentedControl.backgroundColor = .clear
            segmentedControl.selectedSegmentTintColor = .secondaryView
            segmentedControl.layer.borderWidth = 1
            segmentedControl.layer.borderColor = UIColor.secondaryView?.cgColor
            segmentedControl.layer.cornerRadius = 8
            segmentedControl.layer.masksToBounds = true
            segmentedControl.setTitleTextAttributes([
                .foregroundColor: UIColor.secondaryView ?? .cyan,
                .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 12.0)
            ], for: .normal)
            segmentedControl.setTitleTextAttributes([
                .foregroundColor: UIColor.black,
                .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 12.0)
            ], for: .selected)

            segmentedControl.addTarget(self, action: #selector(segmentDayChanged(_:)), for: .valueChanged)

            self.viewSelectDriver.addSubview(segmentedControl)

            NSLayoutConstraint.activate([
                segmentedControl.trailingAnchor.constraint(equalTo: self.viewSelectDriver.trailingAnchor, constant: -16),
                segmentedControl.centerYAnchor.constraint(equalTo: self.viewSelectDriver.centerYAnchor),
                segmentedControl.widthAnchor.constraint(equalToConstant: 116),
                segmentedControl.heightAnchor.constraint(equalToConstant: 28)
            ])
        }

        
        //SET IMAGE
        imgColor(imgColor: self.imgDelivery, colorHex: .secondary)
        imgColor(imgColor: self.imgPickup, colorHex: .secondary)
        self.setDeliveryType()
        
        //SET FONT
        self.lblDelivery.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strDelivery)
        self.lblPickup.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strPickup)
        
        self.setTheType()
        
        //SET DRIVER
        imgColor(imgColor: self.imgSelectDriver, colorHex: .secondary)
        self.lblSelectDriver.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: self.selectDriver)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            //STOP LOADING
            self.stopLoading()
            self.isLoading = false
            
            //NO DATA
            self.emptyDataView.isHidden = true
            if self.arrDispatchList.count == 0{
                self.emptyDataView.isHidden = false
            }
            
            //RELOAD DATA
            self.tblView.reloadData()
        }

    }
    
    func setTheType(){
       
        
        self.lblDelivery.textColor = self.isDeliverySelect == true ? .background : .primary
        self.lblPickup.textColor = self.isReturnSelect == true ? .background : .primary

        //SET VIEW
        self.viewDelivery.viewCorneRadius(radius: 10.0, isRound: false)
        self.viewPickup.viewCorneRadius(radius: 10.0, isRound: false)
        self.viewDelivery.viewBorderCorneRadius(borderColour: .secondary)
        self.viewPickup.viewBorderCorneRadius(borderColour: .secondary)
        
        self.viewDelivery.backgroundColor = self.isDeliverySelect == true ? .secondary : .clear
        self.viewPickup.backgroundColor = self.isReturnSelect == true ? .secondary : .clear
        
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
            self.dispatchPlaceholderMarker.remove()
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
        self.con_statusHeight.constant = 0
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
            self.callAPI(search: strSearch)
        }
        else{
            //CALL API
            self.callAPI(search: "")
        }
    }
    
    func callAPI(search: String){
        //CALL API
        self.objSearchIndicator.isHidden = false
        self.objSearchIndicator.startAnimating()
        self.pageCount = 1
        self.isLoading = true
        self.arrDispatchList = []
        self.emptyDataView.isHidden = true

        self.selectDeliveryType = self.selectDeliveryType == "" ? "All" : self.selectDeliveryType
        
        
        let params = DispatchParameater(page: "\(self.pageCount)", schedule_type: self.selectScheduleType(), schedule_status: self.selectStatus == "1" ? "Pending" : "Completed", category_id: self.selectCategoryID, search: search, transport_mode: self.selectDeliveryType, date_filter: self.strSelectDay, driver_id: self.selectDriverID)
        self.fetchDispatchOrders(DispatchParameater: params, overrideLocal: true)

        
        
        //RELOAD TABLE
        self.tblView.reloadData()
    }
}


extension DispatchListViewController : FilterProtocol{
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
        self.callAPI(search: self.txtSearch.text ?? "")
    }
}
// MARK: - Button Actions

extension DispatchListViewController {

    
    @IBAction func btnDeliveryClicked(_ sender: UIButton) {
        if self.isDeliverySelect == false{
            self.isDeliverySelect = true
        }
        else{
            self.isDeliverySelect = false
        }
        
        
        //SET VIEW
        self.setTheType()
        
        //CALL API
        self.refreshList()
    }
    
    @IBAction func btnPickupClicked(_ sender: UIButton) {
        if self.isReturnSelect == false{
            self.isReturnSelect = true
        }
        else{
            self.isReturnSelect = false
        }
        
        //SET VIEW
        self.setTheType()

        //CALL API
        self.refreshList()
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
        self.callAPI(search: self.txtSearch.text ?? "")

    }
    
    
    @objc func segmentDayChanged(_ sender: UISegmentedControl) {
        self.strSelectDay = sender.selectedSegmentIndex == 0 ? "Today" : "All"
        self.refreshList()
    }

    @IBAction func btnSelectDriverClicked(_ sender: UIButton) {
       // self.view.endEditing(true)
        
        if self.arrDriverEmployesList.count == 0{
            return
        }

        
        actionPicker(sender, strTitle: "Select Driver", arrData: self.arrDriverEmployesList.compactMap { $0.name}, selectValue: self.lblSelectDriver.text ?? "") { index, selectValue in
            
            self.selectDriver = selectValue
            self.lblSelectDriver.text = selectValue

            if selectValue == "All Drivers"{
                self.selectDriverID = ""
            }
            else{
                self.selectDriverID = "\(self.arrDriverEmployesList[index].id ?? 0)"
            }

            //SAVE SELECTED DRIVER FOR TODAY (auto-resets next day)
            self.saveSelectedDriverForToday(name: self.selectDriver, id: self.selectDriverID)

            //RELOAD
            self.refreshList()
        }
    }
}


//MARK: - LOCAL DATABASE MANAGE
extension DispatchListViewController{

    // MARK: - Selected Driver (per-day persistence)
    private var kDriverName: String { "dispatchSelectedDriverName" }
    private var kDriverID: String   { "dispatchSelectedDriverID" }
    private var kDriverDate: String { "dispatchSelectedDriverDate" }

    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Saves the selected driver with today's date.
    func saveSelectedDriverForToday(name: String, id: String) {
        let defaults = UserDefaults.standard
        defaults.set(name, forKey: kDriverName)
        defaults.set(id, forKey: kDriverID)
        defaults.set(todayDateString(), forKey: kDriverDate)
    }

    /// Restores the saved driver only if it was chosen today; otherwise resets to "All Driver".
    func restoreSelectedDriverForToday() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: kDriverDate) == todayDateString() {
            self.selectDriver   = defaults.string(forKey: kDriverName) ?? "All Drivers"
            self.selectDriverID = defaults.string(forKey: kDriverID) ?? ""
        } else {
            // New day → clear the stored selection and default to All Driver
            self.selectDriver   = "All Drivers"
            self.selectDriverID = ""
            defaults.removeObject(forKey: kDriverName)
            defaults.removeObject(forKey: kDriverID)
            defaults.removeObject(forKey: kDriverDate)
        }
    }

    // MARK: - Fetch Orders (Main Controller)
    func fetchDispatchOrders(DispatchParameater : DispatchParameater, overrideLocal: Bool = false) {
        
        let params = DispatchParameater
        callAPIforGetDispatchList(DispatchParameater: params) { [weak self] isSaved in
            guard let self = self else { return }
            
            self.isLoading = false
            self.stopAnimatingView()
            self.objRefresh?.endRefreshing()
            if self.pageCount == 1{
                self.arrDispatchList = []
            }
            
            if isSaved {
                let localData = self.getDispatchOrderData(schedule_type: DispatchParameater.schedule_type)
                
                if overrideLocal {
                    // Replace all old data
                    self.arrDispatchList = localData
                } else {
                    // Append only new unique orders
                    let newItems = localData.filter { newItem in
                        !self.arrDispatchList.contains(where: { $0.id == newItem.id })
                    }
                    self.arrDispatchList.append(contentsOf: newItems)
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
    func getDispatchOrderData(schedule_type: String) -> [SchedulesModel] {
        if let arr = SDKUserDefault.getMappableArray(SchedulesModel.self, for: "\(kFileStorageName.kDispatchJobList.rawValue)_\(schedule_type)_\(self.strSelectDay)_\(self.selectDriverID)") {
            return arr
        }
        return []
    }
}



//MARK: -- TABLE CELL --
class DispatchListCell : UITableViewCell{
    @IBOutlet weak var lblOrderNumber: UILabel!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var lblPhone: UILabel!
    @IBOutlet weak var viewLine: UIView!
    @IBOutlet weak var lblProductName: UILabel!
    @IBOutlet weak var imgCall: UIImageView!
    @IBOutlet weak var btnCall: UIButton!
    @IBOutlet weak var lblDateTime: UILabel!
    @IBOutlet weak var imgOrderType: UIImageView!
    @IBOutlet weak var lblStatus: UILabel!
    @IBOutlet weak var btnStatus: UIButton!
    @IBOutlet weak var viewStatus: UIView!


    @IBOutlet weak var lblAddress: UILabel!
    @IBOutlet weak var btnAddress: UIButton!

    @IBOutlet weak var lblReturnAddress: UILabel!
    @IBOutlet weak var btnReturnAddress: UIButton!
    
    @IBOutlet weak var lblDriver: UILabel!
    @IBOutlet weak var imgDriver: UIImageView!
    @IBOutlet weak var btnDriver: UIButton!

    /// Sets the customer name and, when overdue, prepends an inline red warning icon
    /// INSIDE the name label so the layout/spacing doesn't move.
    func setName(_ number: String, overdue: Bool) {
        let font = lblOrderNumber.font ?? UIFont.systemFont(ofSize: 14)
        let color = lblOrderNumber.textColor ?? .label

        guard overdue else {
            lblOrderNumber.text = number
            return
        }

        let attachment = NSTextAttachment()
        let cfg = UIImage.SymbolConfiguration(pointSize: font.pointSize, weight: .bold)
        attachment.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: cfg)?
            .withTintColor(.systemRed, renderingMode: .alwaysOriginal)

        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: "  " + number,
                                         attributes: [.font: font, .foregroundColor: color]))
        lblOrderNumber.attributedText = result
    }

    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            lblName,
            viewStatus,
            lblPhone,
            imgCall,
            lblProductName,
            viewLine,
            lblAddress,
            lblReturnAddress,
            lblDateTime,
            imgOrderType,
            lblDriver,
            imgDriver
        ]
    }
}


//MARK: -- UITABEL DELEGATE --

extension DispatchListViewController : UITableViewDelegate, UITableViewDataSource, MFMessageComposeViewControllerDelegate , OrderDetailsDelegate, UpdateDriverDelegate{


    
    
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
            let params = DispatchParameater(page: "\(self.pageCount)", schedule_type: self.selectScheduleType(), schedule_status: self.selectStatus == "1" ? "Pending" : "Completed", category_id: self.selectCategoryID, search: self.txtSearch.text ?? "", transport_mode: self.selectDeliveryType, date_filter: self.strSelectDay, driver_id: self.selectDriverID)
            self.fetchDispatchOrders(DispatchParameater: params)

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
            return self.arrDispatchList.count
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "DispatchListCell") as? DispatchListCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.isHidden = false

            if isLoading {
                cell.viewLine.isHidden = true
                self.dispatchPlaceholderMarker.register(cell.getAnimableSubviews())
                self.dispatchPlaceholderMarker.startAnimation()
                return cell
            }
            
            if self.arrDispatchList.count == 0{
                return cell
            }
            
            //GET DATA
            let objData = self.arrDispatchList[indexPath.row]

            //OVERDUE FLAG — delivery rows use is_delivery_overdue, pickup rows use is_pickup_overdue
            let isRowOverdue = (objData.is_delivered == false) ? (objData.is_delivery_overdue ?? false) : (objData.is_pickup_overdue ?? false)

            //SET FONT
            cell.lblOrderNumber.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "#\(objData.order?.id ?? 0)")
            cell.setName("#\(objData.order?.id ?? 0)", overdue: isRowOverdue)

            cell.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.order?.customer_name ?? "")")
            
//            #if DEBUG
//            cell.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.id ?? 0) : \(objData.name ?? "")")
//            #endif
            cell.lblPhone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.order?.customer_phone ?? "")")
            imgColor(imgColor: cell.imgCall, colorHex: .secondary)
            
//            cell.lblDelivery.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strLinces)
            
            //SET ADDRESS
            cell.lblPhone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.order?.customer_phone ?? "")")
            cell.lblPhone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.order?.customer_phone ?? "")")
            cell.lblDriver.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "+ Assign")

            //SET ADDRESS
            //SET DATE
            var strDate : String = ""
            var strTime : String = ""
            
            imgColor(imgColor: cell.imgDriver, colorHex: .secondary)
            var textStart = "Start Point: Pending"
            var textEnd = "End Point: Pending"
            cell.btnAddress.isHidden = true
            cell.btnReturnAddress.isHidden = true
            
            cell.viewStatus.backgroundColor = .secondaryText
            cell.viewStatus.viewCorneRadius(radius: 10, isRound: false)

            // Button colour reflects driver progress: amber (pending) until the driver has saved a
            // Driver Checklist for this item, then green (started). Applies to delivery AND return.

            //CHECK STATUS
           
            
//            if objData.is_delivered == false {
//               
//            }
//            else{
//                //PICKUP CASE
//                is_arrived = objData.pickup_checklist?.is_arrived ?? false
//                ready_to_go_at = objData.pickup_checklist?.ready_to_go_at ?? ""
//                
//            }
//            
            if objData.is_delivered == false {
                //DELIVERY STATUS
//                let is_arrived: Bool = objData.delivery_checklist?.is_arrived ?? false
//                let ready_to_go_at: String = objData.delivery_checklist?.ready_to_go_at ?? ""
                let stringStatus : String = "Start Delivery"
//                if is_arrived == true{
//                    stringStatus = "Complete Delivery"
//                }
//                else if ready_to_go_at != ""{
//                    stringStatus = "Arrived Delivery"
//                }
//                
                
                //DELIVERY CASE
                let isDriverStarted = isLocalStoredValue(objData.order?.unique_id ?? "")
                let ready_to_go_at: String = objData.delivery_checklist?.ready_to_go_at ?? ""

                
                //DELIVERY BUTTON — text then logo (not flipped); green only once the driver started
//                cell.viewStatus.backgroundColor = ready_to_go_at != "" ? hexStringToUIColor(hex: "128A4C") : (isDriverStarted ? hexStringToUIColor(hex: "3DDC6E") : hexStringToUIColor(hex: "4DA3FF"))
                cell.viewStatus.backgroundColor = hexStringToUIColor(hex: "4DA3FF")
                cell.viewStatus.viewBorderCorneRadius(borderColour: ready_to_go_at != "" ? .redText : (isDriverStarted ? .redText : .clear), size: 4)
                cell.lblStatus.configureLable(textColor:  .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14, text: stringStatus)

                if let stack = cell.lblStatus.superview as? UIStackView,
                   let imgLogo = stack.arrangedSubviews.compactMap({ $0 as? UIImageView }).first {
                    stack.spacing = 8
                    imgLogo.transform = .identity
                    // Match the icon colour to the label (dark once ready to go). Reload the asset
                    // fresh as a template so the tint reliably applies.
                    imgLogo.image = UIImage(named: "icon_delivery_pending")?.withRenderingMode(.alwaysTemplate)
                    imgLogo.tintColor = ready_to_go_at != "" ? .primary : .background
                    stack.insertArrangedSubview(cell.lblStatus, at: 0)
                    stack.insertArrangedSubview(imgLogo, at: 1)
                }

                //SET DRIVER NAME
                if let objTransport = objData.delivery_employee, let name = objTransport.name{
                    cell.lblDriver.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: name)
                }
                
                //GET DELIVERY DATA
                strDate = "\(objData.delivery_date ?? "")"
                strTime = "\(objData.delivery_time ?? "")"
                
                //GET ADDRESS
                var locationDelivery : String = "Pending"
                if let objData = objData.objEquipment{
                    if let objDelivery = objData.equipment_store, let name = objDelivery.name{
                        locationDelivery = name
                    }
                }
                
                cell.lblAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: locationDelivery)
                
                cell.lblReturnAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: "\(objData.order?.objDeliveryAddress?.full_address ?? "")")
                cell.btnReturnAddress.isHidden = false

                textStart = "Start Point: \(locationDelivery)"
                textEnd = "End Point:\n\(objData.order?.objDeliveryAddress?.full_address ?? "")"

            }
            else {
                //PICKUP STATUS
//                let is_arrived: Bool = objData.pickup_checklist?.is_arrived ?? false
//                let ready_to_go_at: String = objData.pickup_checklist?.ready_to_go_at ?? ""
                let stringStatus : String = "Start Return"
//                if is_arrived == true{
//                    stringStatus = "Complete Return"
//                }
//                else if ready_to_go_at != ""{
//                    stringStatus = "Arrived Return"
//                }
                


                //DELIVERY CASE
                let isDriverStarted = isLocalStoredPickupValue(objData.order?.unique_id ?? "")
                let ready_to_go_at: String = objData.pickup_checklist?.ready_to_go_at ?? ""
                               
                
                //DELIVERY BUTTON — text then logo (not flipped); green only once the driver started
//                cell.viewStatus.backgroundColor = ready_to_go_at != "" ? hexStringToUIColor(hex: "128A4C") : (isDriverStarted ? hexStringToUIColor(hex: "3DDC6E") : .secondaryText)
                cell.viewStatus.backgroundColor = .secondaryText
                cell.viewStatus.viewBorderCorneRadius(borderColour: ready_to_go_at != "" ? .redText : (isDriverStarted ? .redText : .clear), size: 4)
                cell.lblStatus.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14, text: stringStatus)

                //RETURN BUTTON — flipped logo first then text; green only once the driver started
                if let stack = cell.lblStatus.superview as? UIStackView,
                   let imgLogo = stack.arrangedSubviews.compactMap({ $0 as? UIImageView }).first {
                    // Smaller gap: the flipped truck's speed-lines sit next to the text and add visual space
                    stack.spacing = 2
                    imgLogo.transform = CGAffineTransform(scaleX: -1, y: 1)
                    // Match the icon colour to the label (dark once ready to go). Reload the asset
                    // fresh as a template so the tint reliably applies.
                    imgLogo.image = UIImage(named: "icon_delivery_pending")?.withRenderingMode(.alwaysTemplate)
                    imgLogo.tintColor = ready_to_go_at != "" ? .primary : .background
                    stack.insertArrangedSubview(imgLogo, at: 0)
                    stack.insertArrangedSubview(cell.lblStatus, at: 1)
                }

                //SET DRIVER NAME
                if let objTransport = objData.pickup_employee, let name = objTransport.name{
                    cell.lblDriver.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: name)
                }
                
                //GET PICKUP DATA
                strDate = "\(objData.pickup_date ?? "")"
                strTime = "\(objData.pickup_time ?? "")"

                //GET ADDRESS
                var locationDelivery : String = "Pending"
                if let objData = objData.objEquipment{
                    if let objDelivery = objData.equipment_store, let name = objDelivery.name{
                        locationDelivery = name
                    }
                }

                cell.lblAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: "\(objData.order?.objDeliveryAddress?.full_address ?? "")")
                cell.btnAddress.isHidden = false

                cell.lblReturnAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: locationDelivery)

                textStart = "Start Point:\n\(objData.order?.objDeliveryAddress?.full_address ?? "") "
                textEnd = "End Point: \(locationDelivery)"

            }
            
            

            //START POINT
            let linkTextStartWithColor = "Start Point:"
            let rangeStart = (textStart as NSString).range(of: linkTextStartWithColor)
            let attributedStartString = NSMutableAttributedString(string:textStart)
            attributedStartString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.secondary , range: rangeStart)

            cell.lblAddress.attributedText = attributedStartString
            cell.lblAddress.numberOfLines = 2
            
            //END POINT
            let linkTextEndWithColor = "End Point:"
            let rangeEnd = (textEnd as NSString).range(of: linkTextEndWithColor)
            let attributedEndString = NSMutableAttributedString(string:textEnd)
            attributedEndString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.secondary , range: rangeEnd)

            cell.lblReturnAddress.attributedText = attributedEndString
            cell.lblReturnAddress.numberOfLines = 2
            
            
            //SET IMAGE
            if objData.delivery_transport_mode == "Truck"{
                cell.imgOrderType.image = UIImage(named: "icon_delivery_pending")
            }
            else{
                cell.imgOrderType.image = UIImage(named: "icon_store")
            }
            
            cell.lblDateTime.configureLable(textColor: .primary.withAlphaComponent(0.6), fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(strDate) \(strTime)")
            imgColor(imgColor: cell.imgOrderType, colorHex: .background)
            
          
            
            //SET STORE NAME
            cell.lblProductName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: "\(objData.product_name ?? "")")
            
                    
            // BUTTON ACTION
            cell.btnCall.tag = indexPath.row
            cell.btnCall.addTarget(self, action: #selector(self.btnCallClicked(_:)), for: .touchUpInside)

            cell.btnAddress.tag = indexPath.row
            cell.btnAddress.addTarget(self, action: #selector(self.btnMapClicked(_:)), for: .touchUpInside)

            cell.btnReturnAddress.tag = indexPath.row
            cell.btnReturnAddress.addTarget(self, action: #selector(self.btnMapClicked(_:)), for: .touchUpInside)

            cell.btnDriver.tag = indexPath.row
            cell.btnDriver.addTarget(self, action: #selector(self.btnAssingDriverClicked(_:)), for: .touchUpInside)

            cell.btnStatus.tag = indexPath.row
            cell.btnStatus.addTarget(self, action: #selector(self.btnStatusCallClicked(_:)), for: .touchUpInside)

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
    }
    
    @objc func btnStatusCallClicked(_ sender : UIButton) {
        if self.arrDispatchList.count == 0{
            return
        }
        let objData = self.arrDispatchList[sender.tag]
        var isDriverAssign : Bool = false
        var checklistType : String = ""
        if objData.is_delivered == false {
            checklistType = "delivery"
            
            //GET ADDRESS
            if let objTransport = objData.delivery_employee, let _ = objTransport.name{
                isDriverAssign = true
            }
        }
        else {
            checklistType = "pickup"
            
            //GET ADDRESS
            if let objTransport = objData.pickup_employee, let _ = objTransport.name{
                isDriverAssign = true
            }
            
            
        }

        
        if isDriverAssign == false {
            self.strAssignDriver(index: sender.tag)
        }
        else {
            var is_arrived: Bool = false
            var ready_to_go_at: String = ""
            var buttonColour : UIColor = .secondaryText

            if objData.is_delivered == false {
                //DELIVERY CASE
                is_arrived = objData.delivery_checklist?.is_arrived ?? false
                ready_to_go_at = objData.delivery_checklist?.ready_to_go_at ?? ""
                
                let isDriverStarted = isLocalStoredValue(objData.order?.unique_id ?? "")
                buttonColour = ready_to_go_at != "" ? hexStringToUIColor(hex: "128A4C") : (isDriverStarted ? hexStringToUIColor(hex: "3DDC6E") : hexStringToUIColor(hex: "4DA3FF"))

            }
            else{
                //PICKUP CASE
                is_arrived = objData.pickup_checklist?.is_arrived ?? false
                ready_to_go_at = objData.pickup_checklist?.ready_to_go_at ?? ""
                
                
                //DELIVERY CASE
                let isDriverStarted = isLocalStoredPickupValue(objData.order?.unique_id ?? "")
                buttonColour = ready_to_go_at != "" ? hexStringToUIColor(hex: "128A4C") : (isDriverStarted ? hexStringToUIColor(hex: "3DDC6E") : .secondaryText)

            }
            
            if is_arrived {
                print("=============DIS==============>>>> \(objData.unique_id ?? "")")
                //ORDER DETAILS SCREEN
                let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
                if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
                    newViewController.isOrderScreen = true
                    newViewController.fromCheckListScreen = true
                    newViewController.selectIndex = sender.tag
                    newViewController.strOrderUniqueId = objData.order?.unique_id ?? ""
                    newViewController.strOrderID = "\(objData.order?.order_number ?? "")"
                    newViewController.strComplateDelivery = "\(objData.is_delivered == false ? "Delivery" : "Return") Complete - Next Mission"
                    newViewController.strProductID = objData.unique_id ?? ""
                    self.navigationController?.pushViewController(newViewController, animated: true)
                }
            }
            else {
                
                if ready_to_go_at != "" {
                    //ARRIVED BUTTON VIEW SHOW
                }
                else {
                    //READY TO GO BUTTON VIEW SHOW
                }
                print("=============DIS33332==============>>>> \(objData.unique_id ?? "")")

                //ORDER DETAILS SCREEN
                let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.SCHEDULE_MODEL, bundle: nil)
                if let newViewController = storyBoard.instantiateViewController(withIdentifier: "DriverChecklistViewController") as? DriverChecklistViewController{
                    newViewController.delegate_Data = self
                    newViewController.buttonColour = buttonColour
                    newViewController.objDispatch = objData
                    newViewController.selectIndex = sender.tag
                    newViewController.strOrderUniqueId = objData.order?.unique_id ?? ""
                    newViewController.strOrderID = "\(objData.order?.order_number ?? "")"
                    newViewController.productUniqueId = objData.unique_id ?? ""
                    newViewController.checklistType = checklistType
                    self.navigationController?.pushViewController(newViewController, animated: true)
                }
            }
        }

        
    }
    
    func isLocalStoredValue(_ oederUniqueID: String) -> Bool {
        
        let strKey = "driverChecklist_\(oederUniqueID)_delivery"
        guard let dict = UserDefaults.standard.dictionary(forKey: strKey) else { return false }

        // Any checkbox ticked
        if let checks = dict["deliveryChecks"] as? [Int], checks.contains(1) { return true }

        // Fuel changed from default ("Not Full")
        if let fuel = dict["fuel"] as? String, fuel == "Full" { return true }

        // Keys changed from default ("Missing")
        if let keys = dict["keys"] as? String, keys == "With Machine" { return true }
        
        return false
    }
    
    func isLocalStoredPickupValue(_ oederUniqueID: String) -> Bool {
        let strKey = "driverChecklist_\(oederUniqueID)_pickup"
        guard let dict = UserDefaults.standard.dictionary(forKey: strKey) else { return false }

        // Any checkbox ticked
        if let checks = dict["deliveryChecks"] as? [Int], checks.contains(1) { return true }

        return false

    }
    
    
    func data_updateInCurrentDic(index: Int, dicCheckList: CheckListResponeData?) {

        if self.arrDispatchList[index].is_delivered == false {
            //DELIVERY CASE
            self.arrDispatchList[index].delivery_checklist = dicCheckList
        }
        else{
            //PICKUP CASE
            self.arrDispatchList[index].pickup_checklist = dicCheckList
        }

        SDKUserDefault.saveMappableArray(self.arrDispatchList, for: "\(kFileStorageName.kDispatchJobList.rawValue)_\(self.selectScheduleType())_\(self.strSelectDay)_\(self.selectDriverID)")
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
    
    
    
    
    
    
    @objc func btnCallClicked(_ sender : UIButton) {
        if self.arrDispatchList.count == 0{
            return
        }
        let objData = self.arrDispatchList[sender.tag]

    
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
        if self.arrDispatchList.count == 0{
            return
        }
                      
        let objData = self.arrDispatchList[sender.tag]
        
        let strAddress : String = objData.order?.objDeliveryAddress?.full_address ?? ""
        openAddressInMap(address: strAddress)
    }
    
    
    @objc func btnAssingDriverClicked(_ sender : UIButton) {
        self.strAssignDriver(index: sender.tag)
    }
    
    func strAssignDriver(index : Int){
        if self.arrDispatchList.count == 0{
            return
        }
        
        let objData = self.arrDispatchList[index]

        
        var deliveryFrom = "From: Pending"
        var deliveryTo = "To: Pending"
        var returnFrom = "From: Pending"
        var returnTo = "To: Pending"
        //GET DELIVERY ADDRESS
        var locationDelivery : String = "Pending"
        if let objData = objData.objEquipment{
            if let objDelivery = objData.equipment_store, let name = objDelivery.name{
                locationDelivery = name
            }
        }
        
        deliveryFrom = "From: \(locationDelivery)"
        deliveryTo = "To:\n\(objData.order?.objDeliveryAddress?.full_address ?? "")"

        
        //GET RETURN ADDRESS
        var locationReturn : String = "Pending"
        if let objData = objData.objEquipment{
            if let objDelivery = objData.equipment_store, let name = objDelivery.name{
                locationReturn = name
            }
        }


        returnFrom = "From:\n\(objData.order?.objDeliveryAddress?.full_address ?? "") "
        returnTo = "To: \(locationReturn)"
        
        
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.SCHEDULE_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "AssignDriverViewController") as? AssignDriverViewController{
            newViewController.delegate = self
            newViewController.selectDispatchIndex = index
            newViewController.productUniqueId = objData.unique_id ?? ""
            newViewController.delivery_employee = objData.delivery_employee
            newViewController.pickup_employee = objData.pickup_employee
            newViewController.deliveryFrom = deliveryFrom
            newViewController.deliveryTo = deliveryTo
            newViewController.returnFrom = returnFrom
            newViewController.returnTo = returnTo
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    func updateDriver(delivery_employee: EmployeesModel?, pickup_employee: EmployeesModel?, index: Int) {
        if self.arrDispatchList.count == 0{
            return
        }
        
        var objData = self.arrDispatchList[index]
        objData.delivery_employee = delivery_employee
        objData.pickup_employee = pickup_employee

        DispatchQueue.main.async {
            self.arrDispatchList.remove(at: index)
            self.arrDispatchList.insert(objData, at: index)
            
            self.tblView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        }
    }
    
}





extension String {
    
    func widthOfString(usingFont font: UIFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.width
    }
}

// MARK: - StoreListViewController

class StoreListViewController: UIViewController {

    private let dimView = UIView()
    private let popupView = UIView()
    private let lblTitle = UILabel()
    private let btnClose = UIButton(type: .system)
    private let tblView = UITableView()
    private let objIndicator = UIActivityIndicatorView(style: .medium)
    private var arrStores: [StoreModel] = []
    private var tblHeightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadStores()
    }

    private func setupUI() {
        // Dim background
        dimView.frame = view.bounds
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0)
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(dimView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissPopup))
        dimView.addGestureRecognizer(tap)

        // Popup card
        popupView.translatesAutoresizingMaskIntoConstraints = false
        popupView.backgroundColor = .background
        popupView.layer.cornerRadius = 16
        popupView.clipsToBounds = true
        view.addSubview(popupView)

        // Close button (top right)
        btnClose.translatesAutoresizingMaskIntoConstraints = false
        btnClose.setImage(UIImage(systemName: "xmark"), for: .normal)
        btnClose.tintColor = .secondary
        btnClose.addTarget(self, action: #selector(dismissPopup), for: .touchUpInside)
        popupView.addSubview(btnClose)

        // Title centered
        lblTitle.translatesAutoresizingMaskIntoConstraints = false
        lblTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: "Store List")
        lblTitle.textAlignment = .center
        popupView.addSubview(lblTitle)

        // Divider line
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .primary.withAlphaComponent(0.2)
        popupView.addSubview(divider)

        // Table
        tblView.translatesAutoresizingMaskIntoConstraints = false
        tblView.delegate = self
        tblView.dataSource = self
        tblView.backgroundColor = .clear
        tblView.separatorStyle = .none
        tblView.register(StoreListCell.self, forCellReuseIdentifier: "StoreListCell")
        popupView.addSubview(tblView)

        // Indicator
        objIndicator.translatesAutoresizingMaskIntoConstraints = false
        objIndicator.color = .secondary
        popupView.addSubview(objIndicator)

        let tblH = tblView.heightAnchor.constraint(equalToConstant: 60)
        tblHeightConstraint = tblH

        NSLayoutConstraint.activate([
            popupView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            popupView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            popupView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            popupView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.75),

            btnClose.topAnchor.constraint(equalTo: popupView.topAnchor, constant: 14),
            btnClose.trailingAnchor.constraint(equalTo: popupView.trailingAnchor, constant: -16),
            btnClose.widthAnchor.constraint(equalToConstant: 28),
            btnClose.heightAnchor.constraint(equalToConstant: 28),

            lblTitle.topAnchor.constraint(equalTo: popupView.topAnchor, constant: 14),
            lblTitle.leadingAnchor.constraint(equalTo: popupView.leadingAnchor, constant: 16),
            lblTitle.trailingAnchor.constraint(equalTo: popupView.trailingAnchor, constant: -16),
            lblTitle.heightAnchor.constraint(equalToConstant: 28),

            divider.topAnchor.constraint(equalTo: lblTitle.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: popupView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: popupView.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            tblView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            tblView.leadingAnchor.constraint(equalTo: popupView.leadingAnchor),
            tblView.trailingAnchor.constraint(equalTo: popupView.trailingAnchor),
            tblView.bottomAnchor.constraint(equalTo: popupView.bottomAnchor, constant: -18),
            tblH,

            objIndicator.centerXAnchor.constraint(equalTo: popupView.centerXAnchor),
            objIndicator.centerYAnchor.constraint(equalTo: tblView.centerYAnchor)
        ])
    }

    func showPopup() {
        UIView.animate(withDuration: 0.25) {
            self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        }
    }

    @objc private func dismissPopup() {
        UIView.animate(withDuration: 0.2, animations: {
            self.dimView.backgroundColor = .clear
        }) { _ in
            self.dismiss(animated: false)
        }
    }

    private func loadStores() {
        objIndicator.startAnimating()
        getStoreList { [weak self] stores in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.objIndicator.stopAnimating()
                self.arrStores = stores
                self.tblView.reloadData()
                self.tblView.layoutIfNeeded()
                self.tblHeightConstraint?.constant = self.tblView.contentSize.height
                UIView.animate(withDuration: 0.2) {
                    self.view.layoutIfNeeded()
                }
            }
        }
    }
}

extension StoreListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return arrStores.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StoreListCell", for: indexPath) as! StoreListCell
        cell.configure(with: arrStores[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
}

class StoreListCell: UITableViewCell {

    private let lblAddress = UILabel()
    private let imgLocation = UIImageView()
    private let divider = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        imgLocation.translatesAutoresizingMaskIntoConstraints = false
        imgLocation.image = UIImage(named: "icon_map")
        imgColor(imgColor: imgLocation, colorHex: .secondary)
        imgLocation.contentMode = .scaleAspectFit
        contentView.addSubview(imgLocation)

        lblAddress.translatesAutoresizingMaskIntoConstraints = false
        lblAddress.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "")
        lblAddress.numberOfLines = 0
        contentView.addSubview(lblAddress)

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .primary.withAlphaComponent(0.15)
        contentView.addSubview(divider)

        NSLayoutConstraint.activate([
            lblAddress.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            lblAddress.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            lblAddress.trailingAnchor.constraint(equalTo: imgLocation.leadingAnchor, constant: -10),
            lblAddress.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),

            imgLocation.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imgLocation.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            imgLocation.widthAnchor.constraint(equalToConstant: 20),
            imgLocation.heightAnchor.constraint(equalToConstant: 20),

            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            divider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    func configure(with store: StoreModel) {
        lblAddress.text = store.name ?? ""
    }
}

