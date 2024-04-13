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
    @IBOutlet weak var viewPickup: UIView!
    @IBOutlet weak var lblPickup: UILabel!
    @IBOutlet weak var con_DeliveryPickupLine: NSLayoutConstraint!
    @IBOutlet weak var viewLine: UIView!

    @IBOutlet weak var viewPending: UIView!
    @IBOutlet weak var lblPending: UILabel!
    @IBOutlet weak var viewCompleted: UIView!
    @IBOutlet weak var lblCompleted: UILabel!

    @IBOutlet weak var viewPendingCount: UIView!
    @IBOutlet weak var lblPendingCount: UILabel!

    @IBOutlet weak var viewCompletedCount: UIView!
    @IBOutlet weak var lblCompletedCount: UILabel!

    @IBOutlet weak var viewDeliveryCount: UIView!
    @IBOutlet weak var lblDeliveryCount: UILabel!

    @IBOutlet weak var viewPickupCount: UIView!
    @IBOutlet weak var lblPickupCount: UILabel!
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
    var arrCategorys : [CategoryModel] = []

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
    var selectDeliveryType : String = ""

    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(self.setcount), name: .scheduleCount, object: nil)

        
        // Do any additional setup after loading the view.
        //SET REFRSH CONTROL
        self.objRefresh = UIRefreshControl()
        let refreshView = UIView(frame: CGRect(x: 0, y: view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0, width: 0, height: 0))
        self.tblView.addSubview(refreshView)
        self.objRefresh?.tintColor = UIColor.primary
        self.objRefresh?.addTarget(self, action: #selector(self.refreshList), for: .valueChanged)
        refreshView.addSubview(self.objRefresh!)
        

        
        //SET LOADING
        self.viewLine.backgroundColor = .clear
        self.setupTableView()
    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        self.setSearchBar(isHide: true)
        self.getCategorys()

        //GET DATA
        self.refreshList()
        
        //SET COUNT
        self.setcount()
        GlobalMainConstants.appDelegate?.getScheduleCount()

        
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
                view.arrCategorys = self.arrCategorys
                view.selectCategoryID = Int(self.selectCategoryID) ?? 0
                view.selectType = self.selectDeliveryType == "" ? "all" : self.selectDeliveryType
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
        if self.selectCategoryID != "" || self.selectDeliveryType != ""{
            return true
        }
        else{
            return false
        }
    }
    
    @objc func refreshList(){
        //GET DATA
        self.viewPendingCount.isHidden = true
        self.viewPickupCount.isHidden = true
        self.viewDeliveryCount.isHidden = true
        self.viewCompletedCount.isHidden = true

        self.isLoading = true
        self.arrScheduleList = []
        self.tblView.reloadData()
        self.pageCount = 1
        self.getScheduleList(OrdersParameater: OrdersParameater(page: "\(self.pageCount)", type: self.selectType, status: self.selectStatus, search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, deliveryType: self.selectDeliveryType))

    }
    
    func setTheView(){
        self.objSearchIndicator.isHidden = true
        self.objSearchIndicator.stopAnimating()

        
        //SET FONT
        self.lblDelivery.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strDelivery)
        self.lblPickup.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPickup)

        self.lblPending.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strPending)
        self.lblCompleted.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strCompleted)
        self.lblCompletedCount.configureLable(textColor: .white, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 12.0, text: "")
        self.lblPendingCount.configureLable(textColor: .white, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 12.0, text: "")
        self.lblDeliveryCount.configureLable(textColor: .white, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 12.0, text: "")
        self.lblPickupCount.configureLable(textColor: .white, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 12.0, text: "")

        
        self.setTheType(isDelivery: self.isDeliveryType)
        self.setOrderType(isPending: self.isPending)
        
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
        
        //SET COUNT
        self.setcount()

    }
    
    func setTheType(isDelivery : Bool){
        self.selectType = isDelivery == true ? "Delivery" : "Pickup"

        self.viewLine.backgroundColor = .secondary
        self.lblDelivery.textColor = isDelivery == true ? .secondary : .primary.withAlphaComponent(0.6)
        self.lblPickup.textColor = isDelivery == false ? .secondary : .primary.withAlphaComponent(0.6)

        //ANIMATION
        UIView.animate(withDuration: 0.2,
                   delay: 0.1,
                       options: UIView.AnimationOptions.curveEaseIn,
                   animations: { () -> Void in
            if isDelivery{
                self.con_DeliveryPickupLine.constant = 0
                
            }
            else{
                let strPickupSize = self.viewPickup.frame.origin.x + (self.viewPickup.frame.size.width / 2) - (self.viewLine.frame.size.width / 2)
                let strDeliverySize = (self.viewDelivery.frame.origin.x + (self.viewDelivery.frame.size.width / 2) - (self.viewLine.frame.size.width / 2))
                self.con_DeliveryPickupLine.constant = strPickupSize - strDeliverySize

            }

            self.view.layoutIfNeeded()

        }, completion: { (finished) -> Void in
        // ....
        })
        
    }
    
    func setOrderType(isPending : Bool){
        self.selectStatus = isPending == true ? "1" : "2"

        self.lblPending.textColor = isPending == true ? .background : .primary
        self.lblCompleted.textColor = isPending == false ? .background : .primary

        //SET VIEW
        self.viewPending.viewCorneRadius(radius: 10.0, isRound: false)
        self.viewCompleted.viewCorneRadius(radius: 10.0, isRound: false)
        self.viewPending.viewBorderCorneRadius(borderColour: .secondary)
        self.viewCompleted.viewBorderCorneRadius(borderColour: .secondary)
        
        self.viewPending.backgroundColor = isPending == true ? .secondary : .clear
        self.viewCompleted.backgroundColor = isPending == false ? .secondary : .clear
    }
    
    func stopLoading(){
        indicatorHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.schedulePlaceholderMarker.remove()
        }
    }
    
    
    @objc func setcount(){
        //SET SCHEDUKE COUNT
        self.viewPendingCount.backgroundColor = .redText
        self.viewPendingCount.viewCorneRadius(radius: 0.0, isRound: true)
        self.viewPendingCount.isHidden = true
        
        self.viewCompletedCount.backgroundColor = .redText
        self.viewCompletedCount.viewCorneRadius(radius: 0.0, isRound: true)
        self.viewCompletedCount.isHidden = true
        
        self.viewDeliveryCount.backgroundColor = .redText
        self.viewDeliveryCount.viewCorneRadius(radius: 0.0, isRound: true)
        self.viewDeliveryCount.isHidden = true

        self.viewPickupCount.backgroundColor = .redText
        self.viewPickupCount.viewCorneRadius(radius: 0.0, isRound: true)
        self.viewPickupCount.isHidden = true

//        let pendingCount = pendingDelivertCount + pendingPickupCount
//        self.viewPendingCount.isHidden = true
//        if pendingCount != 0{
//            self.viewPendingCount.isHidden = false
//            self.lblPendingCount.text = "\(pendingCount)"
//        }
// 
//        let complteCount = complateDelivertCount + complatePickupCount
//        self.viewCompletedCount.isHidden = true
//        if complteCount != 0{
//            self.viewCompletedCount.isHidden = false
//            self.lblCompletedCount.text = "\(complteCount)"
//        }
        
        if self.isPending{
            self.setPickupDeliveryCount(strDelivery: pendingDelivertCount + pastDelivertCount, strPickup: pendingPickupCount + pastPickupCount)
        }
        else{
            self.viewDeliveryCount.isHidden = true
            self.viewPickupCount.isHidden = true

//            self.setPickupDeliveryCount(strDelivery: complateDelivertCount, strPickup: complatePickupCount)
        }

    }
    
    func setPickupDeliveryCount(strDelivery : Int , strPickup : Int){
        self.viewDeliveryCount.isHidden = true
        if strDelivery != 0{
            self.viewDeliveryCount.isHidden = false
            self.lblDeliveryCount.text = "\(strDelivery)"
        }
        
        self.viewPickupCount.isHidden = true
        if strPickup != 0{
            self.viewPickupCount.isHidden = false
            self.lblPickupCount.text = "\(strPickup)"
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
        self.viewPending.isHidden = false
        self.viewCompleted.isHidden = false
        self.viewDelivery.isHidden = false
        self.viewPickup.isHidden = false
        self.viewLine.isHidden = false
        
        //SEARCH VIEW
        self.con_statusHeight.constant = 50
        self.con_searchTop.constant = -(self.viewSearch.frame.size.height)
        if isHide == false{
            self.con_statusHeight.constant = 0
            self.viewPending.isHidden = true
            self.viewCompleted.isHidden = true
            self.viewDelivery.isHidden = true
            self.viewPickup.isHidden = true
            self.viewLine.isHidden = true
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

        self.getScheduleList(OrdersParameater: OrdersParameater(page: "\(self.pageCount)", type: self.selectType, status: self.selectStatus, search: search, category_id: category_id, deliveryType: deliveryType))

        
        //RELOAD TABLE
        self.tblView.reloadData()
    }
    
//    func filter(){
//        if self.strFilter == "All"{
//            self.arrScheduleList = self.arrAllData
//        }
//        else if self.selectType.lowercased() == "Delivery".lowercased(){
//            if self.strFilter == "Delivery"{
//                self.arrScheduleList = self.arrAllData.filter { Int(("\($0.customer_delivery ?? 0)" as NSString?)?.range(of: "2").location ?? 0) != NSNotFound}
//            }
//            else{
//                self.arrScheduleList = self.arrAllData.filter { Int(("\($0.customer_delivery ?? 0)" as NSString?)?.range(of: "1").location ?? 0) != NSNotFound}
//            }
//        }
//        else{
//            if self.strFilter == "Delivery"{
//                self.arrScheduleList = self.arrAllData.filter { Int(("\($0.customer_pickup ?? 0)" as NSString?)?.range(of: "2").location ?? 0) != NSNotFound}
//            }
//            else{
//                self.arrScheduleList = self.arrAllData.filter { Int(("\($0.customer_pickup ?? 0)" as NSString?)?.range(of: "1").location ?? 0) != NSNotFound}
//            }
//
//        }
//        
//        //RELOAD
//        self.tblView.reloadData()
//    }
}



extension ScheduleListViewController : FilterProtocol{
    func SelectFilter(categoryID: Int, strStatus: String, strDeliveryType: String) {
        self.selectCategoryID = ""
        self.selectDeliveryType = ""

        if categoryID != 0{
            self.selectCategoryID = "\(categoryID)"
        }
        
        
        if strDeliveryType != "" && strDeliveryType.lowercased() != "all"{
            self.selectDeliveryType = strDeliveryType
        }
        
        //CALL API
        self.setNavigation()
        self.callAPI(search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, deliveryType: self.selectDeliveryType)
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
    
    @IBAction func btnPendingClicked(_ sender: UIButton) {
        if self.isPending == false{
            self.isPending = true
            
            //SET VIEW
            self.setOrderType(isPending: self.isPending)
            
            //CALL API
            self.refreshList()
        }
    }
    
    @IBAction func btnCompletedClicked(_ sender: UIButton) {
        if self.isPending == true{
            self.isPending = false
            
            //SET VIEW
            self.setOrderType(isPending: self.isPending)
            
            //CALL API
            self.refreshList()
        }
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

        if scrollView == tblView{
            if tblView.contentSize.height <= tblView.contentOffset.y + tblView.frame.size.height && tblView.contentOffset.y >= 0 {
                if self.arrScheduleList.count != 0 && self.txtSearch.text == ""{
                    if bool_Load == false {

                        //Refresh code
                        self.bool_Load = true

                        //START LOADING
                        startAnimatingView()

                        //CALL API
                        self.getScheduleList(OrdersParameater: OrdersParameater(page: "\(self.pageCount)", type: self.selectType, status: self.selectStatus, search: self.txtSearch.text ?? "", category_id: self.selectCategoryID, deliveryType: self.selectDeliveryType))
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
            cell.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.name ?? "")")
            #if DEBUG
            cell.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.id ?? 0) : \(objData.name ?? "")")
            #endif
            cell.lblPhone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.phone ?? "")")
            imgColor(imgColor: cell.imgCall, colorHex: .secondary)
            
//            cell.lblDelivery.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strLinces)
            
            //SET ADDRESS
            imgColor(imgColor: cell.imgMapAddress, colorHex: .secondary)
            cell.lblAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: "\(objData.location ?? "")")

            //SET DATE
            var strDate : String = ""
            var strTime : String = ""
            if self.selectType.lowercased() == "Delivery".lowercased(){
                //GET DELIVERY DATA
                strDate = convertStringToNewFormateString(date: "\(objData.delivery_date ?? "")", withFormat: Application.pickerDateFormet, newFormate: Application.strDateFormet) ?? ""
                strTime = convertStringToNewFormateString(date: "\(objData.delivery_time ?? "")", withFormat: Application.HHMMSS, newFormate: Application.HMMA) ?? ""
                
                //SET IMAGE
                if objData.customer_delivery == 2{
                    cell.imgOrderType.image = UIImage(named: "icon_delivery_pending")
                }
                else{
                    cell.imgOrderType.image = UIImage(named: "icon_store")
                    
                    //SET STORE ADDRESS
                    
                    if self.getStoreAddress(arr: objData.order?.products ?? []) != ""{
                        let text = "In Store : \(self.getStoreAddress(arr: objData.order?.products ?? []))"
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
                strDate = convertStringToNewFormateString(date: "\(objData.pickup_date ?? "")", withFormat: Application.pickerDateFormet, newFormate: Application.strDateFormet) ?? ""
                strTime = convertStringToNewFormateString(date: "\(objData.pickup_time ?? "")", withFormat: Application.HHMMSS, newFormate: Application.HMMA) ?? ""
                
                //SET IMAGE
                if objData.customer_pickup == 2{
                    cell.imgOrderType.image = UIImage(named: "icon_delivery_pending")
                }
                else{
                    cell.imgOrderType.image = UIImage(named: "icon_store")
                    
                    //SET STORE ADDRESS
                    if self.getStoreAddress(arr: objData.order?.products ?? []) != ""{
                        cell.lblAddress.text = "In Store : \(self.getStoreAddress(arr: objData.order?.products ?? []))"
                    }
                }
            }
            cell.lblDateTime.configureLable(textColor: .primary.withAlphaComponent(0.6), fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(strDate) \(strTime)")
            imgColor(imgColor: cell.imgOrderType, colorHex: .secondary)
            
          
            
            
//            if objDetails.storeAdderss != nil{
//                cell.con_imgStore.constant = 30
//                imgColor(imgColor: cell.imgStore, colorHex: .secondary)
//                cell.lblStoreAddress.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: "\(objDetails.storeAdderss?.address ?? ""), \(objDetails.storeAdderss?.city ?? ""), \(objDetails.storeAdderss?.state ?? ""), \(objDetails.storeAdderss?.zip_code ?? "")")
//            }
            
            //SET NAME
            var strProduct : String = ""
            for objProduct in objData.order?.products ?? []{
                if strProduct != "" {
                    strProduct = "\(strProduct)\n• \(objProduct.product_name ?? "")"
                }
                else{
                    strProduct = "• \(objProduct.product_name ?? "")"
                }
            }
            
            cell.lblProductName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: strProduct)
            
            cell.viewDelivery.backgroundColor = .clear
            cell.con_Delivery.constant = manageWidth(size: checkDeviceiPad() ? 450 : 350)
            DispatchQueue.main.asyncAfter(wallDeadline: .now()) {
                cell.viewDelivery.tag = indexPath.row
                cell.viewDelivery.sliderViewTopDistance = 0
                cell.viewDelivery.thumbnailViewTopDistance = 4;
                cell.viewDelivery.thumbnailViewStartingDistance = 4;
                cell.viewDelivery.layer.cornerRadius =  cell.viewDelivery.frame.size.height / 2
                cell.viewDelivery.thumnailImageView.backgroundColor = .secondaryView
                cell.viewDelivery.draggedView.backgroundColor = .clear
                cell.viewDelivery.delegate = self
                cell.viewDelivery.thumnailImageView.image = #imageLiteral(resourceName: "icon_slideNext").imageFlippedForRightToLeftLayoutDirection()
                imgColor(imgColor: cell.viewDelivery.thumnailImageView, colorHex: .background)
                cell.viewDelivery.sliderBackgroundColor = .clear
                cell.viewDelivery.viewBorderCorneRadius(borderColour: .secondary)
                cell.viewDelivery.textFont = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 16.0)
                cell.viewDelivery.labelText = ""
                
                cell.viewDelivery.textColor = UIColor.white
                DispatchQueue.main.asyncAfter(deadline: .now()){
                    if self.selectType.lowercased() == "Delivery".lowercased(){
                        cell.viewDelivery.transform = CGAffineTransform(rotationAngle: 0)
                        cell.viewDelivery.textLabel.transform = CGAffineTransform(rotationAngle: 0)
                        cell.viewDelivery.labelText = "Delivery Completed - Swipe Right"
                    }
                    else{
                        cell.viewDelivery.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
                        cell.viewDelivery.textLabel.transform = CGAffineTransform(rotationAngle: -CGFloat.pi)

                        cell.viewDelivery.labelText = "Pickup Completed - Swipe Left"
                    }
                }
            }
            
            //SET VIEW
            cell.viewComplate.backgroundColor = .secondary
            cell.viewComplate.viewCorneRadius(radius: 10, isRound: false)
            cell.lblComplate.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "")

            //CHECK AND SET VIEW
            cell.viewDelivery.isHidden = false
            cell.viewComplate.isHidden = true
            if self.selectType.lowercased() == "Delivery".lowercased(){
                if objData.delivery_status?.value == "2"{
                    cell.viewDelivery.isHidden = true
                    cell.viewComplate.isHidden = false
                    cell.lblComplate.text = "Delivery Completed - See Order Details"
                }
            }
            else{
                if objData.pickup_status?.value == "2"{
                    cell.viewDelivery.isHidden = true
                    cell.viewComplate.isHidden = false
                    cell.lblComplate.text = "Pickup Completed - See Order Details"

                }
            }

            
        
            // BUTTON ACTION
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

     
        //TERMS AND CONDITION
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
            newViewController.delegate = self
            newViewController.selectIndex = indexPath.row
            newViewController.strOrderID = "\(objData.order_id ?? 0)"
            newViewController.strProductID = "\(objData.product_id ?? 0)"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    
    func updateOrderDetails(selectIndex: Int, objOrderData: OrdersModel) {
        
    }
    
    func getStoreAddress(arr : [ProductModel]) -> String{
        for objDetails in arr{
            if objDetails.storeAdderss != nil{
                return "\(objDetails.storeAdderss?.address ?? ""), \(objDetails.storeAdderss?.city ?? ""), \(objDetails.storeAdderss?.state ?? ""), \(objDetails.storeAdderss?.zip_code ?? "")"
            }
        }
        
        return ""
    }
    
    @objc func btnCallClicked(_ sender : UIButton) {
        if self.arrScheduleList.count == 0{
            return
        }
        let objData = self.arrScheduleList[sender.tag]

    
        var getNumber = objData.phone ?? ""
        getNumber = getNumber.replacingOccurrences(of: "+1", with: "")
        
        let pickerAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        
      
        let cancel = UIAlertAction.init(title: "Cancel", style: UIAlertAction.Style.cancel, handler: { (action) in
            
            pickerAlert.dismiss(animated: true, completion: nil)
        })
        
        let call = UIAlertAction.init(title: "Call \(objData.phone ?? "")", style: UIAlertAction.Style.default, handler: { (action) in
            
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

    
    
    @objc func btnMapClicked(_ sender : UIButton) {
        if self.arrScheduleList.count == 0{
            return
        }
        let objData = self.arrScheduleList[sender.tag]
        
        let strAddress : String = objData.location ?? ""
        if strAddress != ""{
            openAddressInMap(address: strAddress)
        }
      
    }
}



extension ScheduleListViewController : MTSlideToOpenDelegate{
    
    // MARK: MTSlideToOpenDelegate
    func mtSlideToOpenDelegateDidFinish(_ sender: MTSlideToOpenView) {
        if self.arrScheduleList.count == 0{
            return
        }
        let objData = self.arrScheduleList[sender.tag]
        
        
        let getID = objData.id
        if self.selectType.lowercased() == "Delivery".lowercased(){
            self.updateStatus(UpdateStatusParameater: UpdateStatusParameater(id: "\(getID ?? 0)", delivery_status: "2", pickup_status: ""), index: sender.tag)
        }
        else{
            self.updateStatus(UpdateStatusParameater: UpdateStatusParameater(id: "\(getID ?? 0)", delivery_status: "", pickup_status: "2"), index: sender.tag)
        }
        
    }
}


extension ScheduleListViewController{
    
}
