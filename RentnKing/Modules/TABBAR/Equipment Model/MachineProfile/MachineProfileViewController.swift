//
//  MachineProfileViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 18/03/25.
//

import UIKit



class MachineProfileViewController: UIViewController, UIGestureRecognizerDelegate {
    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!
    @IBOutlet weak var imgSearch: UIImageView!
    @IBOutlet weak var viewSearch: UIView!
    @IBOutlet weak var txtSearch: UITextField!
    @IBOutlet weak var objSearchIndicator: UIActivityIndicatorView!
    
    @IBOutlet weak var lblStoreFilter: UILabel!
    
    @IBOutlet weak var viewCurrentlyAssign: UIControl!
    @IBOutlet weak var imgCurrentlyAssignTick: UIImageView!
    @IBOutlet weak var img_Calender: UIImageView!
    @IBOutlet weak var lblCurrentlyAssign: UILabel!
    
    @IBOutlet var emptyDataView : EmptyDataView!{
        didSet{
            emptyDataView.noDataFound()
            emptyDataView.isHidden = true
        }
    }

    
    //OTHER
    var strTxtSearch = ""
    var int_CurrentlyAssignedTick: Int = 1
    let machineProfilePlaceholderMarker = Placeholder()
    var isLoading : Bool = true
    var objRefresh : UIRefreshControl?

    var arrMainMachineProfileList : [MachineModel] = []
    var arrMachineProfileList : [MachineModel] = []
    var arrCategoryList : [CategoryModel] = []
    var arrStatues : [FilterTypes] = []
    var arrServices : [FilterTypes] = []
    var arrStoreList :[StoreModel] = []

    var selectCategoryID : Int = 0
    var selectStatus : String = "All"
    var selectService : String = "All"
    var strStoreID : String = ""
    var strStoreName : String = ""
    
    //OTHER
    var _loadingView: UIActivityIndicatorView!
    var bool_Load: Bool = false
    var pageCount: Int = 1
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        //SET REFRSH CONTROLGm
        self.objRefresh = UIRefreshControl()
        let refreshView = UIView(frame: CGRect(x: 0, y: view.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0, width: 0, height: 0))
        self.tblView.addSubview(refreshView)
        self.objRefresh?.tintColor = UIColor.primary
        self.objRefresh?.addTarget(self, action: #selector(self.refreshList), for: .valueChanged)
        refreshView.addSubview(self.objRefresh!)
        
        self.setupTableView()
                
        
        //RESTORE SAVED STORE FILTER
        if let savedID = UserDefaults.standard.string(forKey: "savedMachineStoreID"), !savedID.isEmpty {
            self.strStoreID = savedID
            self.strStoreName = UserDefaults.standard.string(forKey: "savedMachineStoreName") ?? ""
        }

        self.txtSearch.configureText(bgColour: UIColor.clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "", placeholder: str.strSearchEqupment)
        self.txtSearch.clearButtonMode = .whileEditing
        self.txtSearch.text = ""
        if let clearButton = txtSearch.value(forKey: "_clearButton") as? UIButton{
            let templateImage =  clearButton.imageView?.image?.withRenderingMode(.alwaysTemplate)
            clearButton.setImage(templateImage, for: .normal)
            clearButton.tintColor = .gray
        }

        self.imgCurrentlyAssignTick.image = .iconCheck
        self.lblCurrentlyAssign.configureLable(textColor: .darkGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 15, text: str.strCurrentlyAssigned)
        
        
        DispatchQueue.main.async {
            
            
            //GET CATEGORY DATA
            getCategoryList { arr_data in
                self.arrCategoryList = arr_data
            }
            
            //GET STORE LIST DATA FROM LOCAL
            getStoreList { arr_data in
                var mappedStores = arr_data.map { obj -> StoreModel in
                    var updatedObj = obj
                    updatedObj.fullAddress = [
                        obj.address,
                        obj.city,
                        obj.state,
                        obj.zip_code
                    ]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")
                    return updatedObj
                }

                // Add "All Stores" option at the top (this page only)
                if var allStores = StoreModel(JSON: [:]) {
                    allStores.id = 0
                    allStores.name = str.strSelectStore
                    mappedStores.insert(allStores, at: 0)
                }

                self.arrStoreList = mappedStores
            }
            
            //GET DATA
            self.refreshList()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(refreshList), name: .refreshMachineProfileList, object: nil)
    }
    

    @objc func refreshList(){
        self.pageCount = 1
        //GET Equipment LIST DATA
        // Parse the equipment cache OFF the main thread (it maps many heavy MachineModel
        // objects); update the UI back on main. This stops the screen from freezing while
        // opening — the isLoading shimmer covers the brief wait.
        DispatchQueue.global(qos: .userInitiated).async {
            getEquipmentList(strType: "RentalReady", strstoreid: self.strStoreID) { arr_data in
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.objRefresh?.endRefreshing()
                    self.sortData(arr_machine: arr_data)
                }
            }
        }
    }
    
    func sortData(arr_machine: [MachineModel]) {
   
        if self.pageCount == 1{
            self.arrMachineProfileList = arr_machine
        }
        else{
            for obj in arr_machine{
                self.arrMachineProfileList.append(obj)
            }
        }
       
        self.arrMainMachineProfileList = self.arrMachineProfileList
        
        //SET THE VIEW
        self.setTheView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        syncEquipmentWithAPI()
        
        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true
        
        //SET NAVIGATION BAR
        self.setNavigation()


        //SET DATA
        self.arrStatues = [FilterTypes(text: "All", value: "0"), FilterTypes(text: "Available", value: "1"), FilterTypes(text: "Damaged", value: "2"), FilterTypes(text: "Maint. Hold", value: "3"), FilterTypes(text: "Rented", value: "4"), FilterTypes(text: "Service Due", value: "5"), FilterTypes(text: "Service OverDue", value: "6")]
        self.arrServices = [FilterTypes(text: "All", value: "0"), FilterTypes(text: "Serv. Due", value: "1")]
    }

    
    func setNavigation(){
        self.updateStoreLabel()
        //SET NAVIGATION BAR
        setNavigationBarForButtons(controller: self, title: str.strMachineProfile, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: ["icon_Filter"], isFilter: self.checkFilter()) {
            setupKeyboard(true)
            self.navigationController?.popViewController(animated: true)
        } rightActionHandler: {sender, SelectTag  in
            //FILTER
            let storyboard = UIStoryboard(name: GlobalMainConstants.EQUIPMENT_MODEL, bundle: nil)
            let view = storyboard.instantiateViewController(withIdentifier: "MachineFilterViewController") as! MachineFilterViewController
            view.delegate = self
            view.arrStores = self.arrStoreList
            view.arrCategorys = self.arrCategoryList
            view.arrStatues = self.arrStatues
            view.arrServices = self.arrServices
            view.selectStoreID = self.strStoreID
            view.selectStoreName = self.strStoreName
            view.selectCategoryID = self.selectCategoryID
            view.selectStatus = self.selectStatus
            view.selectService = self.selectService
            view.view.backgroundColor = UIColor.clear
            view.modalPresentationStyle = .overCurrentContext
            self.present(view, animated: false) {
                view.view.backgroundColor = UIColor(red: 0 / 255.0, green: 0 / 255.0, blue: 0 / 255.0, alpha: 0.5)
            }
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
        
        
        //STORE FILTER LABEL
        self.lblStoreFilter.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14, text: "")
        self.updateStoreLabel()

        //SET SEARCH TEXT
        self.txtSearch.addTarget(self, action: #selector(textFieldDidChangeSearch), for: .editingDidEndOnExit)

        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            //STOP LOADING
            self.stopLoading()
            self.isLoading = false
            
            //NO DATA
            self.emptyDataView.isHidden = true
            if self.arrMachineProfileList.count == 0{
                self.emptyDataView.isHidden = false
            }
            
            //RELOAD DATA
            self.tblView.reloadData()
        }
    }
    
    
    
    func stopLoading(){
        indicatorHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.machineProfilePlaceholderMarker.remove()
        }
    }
    
    func updateStoreLabel() {
        if !strStoreID.isEmpty && !strStoreName.isEmpty {
            lblStoreFilter.text = "Store: \(strStoreName)"
            lblStoreFilter.isHidden = false
        } else {
            lblStoreFilter.isHidden = true
        }
    }

    func checkFilter() -> Bool{
        if self.selectCategoryID != 0 ||
            (self.selectStatus != "" && self.selectStatus != "All") ||
            (self.selectService != "" && self.selectService != "All") ||
            (self.strStoreID != "" && self.strStoreID != "0") {
            return true
        }
        return false
    }
    
    
    // MARK: - UITEXTFIELD
    @objc func textFieldDidChangeSearch() {
        self.pageCount = 1
        self.callAPI()
        
    }

    func callAPI (){
        let strSearch = self.txtSearch.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        self.strTxtSearch = strSearch
        self.objRefresh?.isUserInteractionEnabled = true
        
        //GET Equipment LIST DATA
        getFilterEquipmentList(strType: "RentalReady", str_search: self.strTxtSearch, str_store_id: self.strStoreID, int_assigned: self.int_CurrentlyAssignedTick, str_category: "\(self.selectCategoryID)", str_status: self.selectStatus, pageCount: self.pageCount) { arr_data in
            if self.pageCount == 1{
                self.arrMachineProfileList = []
            }
            self.stopAnimatingView()
            self.isLoading = false
            self.objRefresh?.endRefreshing()
            self.objRefresh?.isUserInteractionEnabled = true
            self.sortData(arr_machine: arr_data)
            
            // Pagination Control
            if arr_data.count >= Int(Application.PageOrderLimit) {
                self.bool_Load = false
                self.pageCount += 1
            } else {
                self.bool_Load = true
            }
        }
    }
    
    
    
    // MARK: - Action
    @IBAction func btn_CurrentlyAssign_Action(_ sender: UIControl) {
        if self.int_CurrentlyAssignedTick == 1 {
            self.int_CurrentlyAssignedTick = 0
            self.imgCurrentlyAssignTick.image = .iconUnCheck
        }
        else {
            self.int_CurrentlyAssignedTick = 1
            self.imgCurrentlyAssignTick.image = .iconCheck
        }
        
        //GET Equipment LIST DATA
        self.isLoading = true
        self.tblView.reloadData()
        self.objRefresh?.isUserInteractionEnabled = false
        self.pageCount = 1
        self.callAPI()
        
        
    }
    
    
}



extension MachineProfileViewController : MachineFilterProtocol{

    func SelectFilter(categoryID: Int, strStatus: String, strService: String, strStoreID: String, strStoreName: String) {
        self.selectCategoryID = 0
        self.selectStatus = "All"
        self.selectService = "All"
        self.strStoreID = strStoreID
        self.strStoreName = strStoreName

        if categoryID != 0 {
            self.selectCategoryID = categoryID
        }
        if strStatus != "" && strStatus.lowercased() != "all" {
            self.selectStatus = strStatus
        }
        if strService != "" && strService.lowercased() != "all" {
            self.selectService = strService
        }

        // Save store to UserDefaults
        if !strStoreID.isEmpty {
            if strStoreID == "0" {
                UserDefaults.standard.removeObject(forKey: "savedMachineStoreID")
                UserDefaults.standard.removeObject(forKey: "savedMachineStoreName")
            }
            else {
                UserDefaults.standard.set(strStoreID, forKey: "savedMachineStoreID")
                UserDefaults.standard.set(strStoreName, forKey: "savedMachineStoreName")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: "savedMachineStoreID")
            UserDefaults.standard.removeObject(forKey: "savedMachineStoreName")
        }

        self.isLoading = true
        self.tblView.reloadData()
        self.objRefresh?.isUserInteractionEnabled = false
        self.pageCount = 1
        self.callAPI()
        self.setNavigation()
    }
}




//MARK: -- TABLE CELL --
class MachineProfileListCell : UITableViewCell{

    @IBOutlet weak var lblCatrgoryName: UILabel!
    @IBOutlet weak var lblDate: UILabel!
    
//    @IBOutlet weak var lblCalass: UILabel!
    @IBOutlet weak var lblMachineID: UILabel!
    
    @IBOutlet weak var lblMachineName: UILabel!
    
//    @IBOutlet weak var lblTechName: UILabel!
    @IBOutlet weak var lblLocation: UILabel!
    @IBOutlet weak var btnOrder: UIButton!

    @IBOutlet weak var lblStatus: UILabel!
    @IBOutlet weak var viewStatus: UIView!
    @IBOutlet weak var imgStatus: UIImageView!
    @IBOutlet weak var imgService: UIImageView!

    @IBOutlet weak var viewLine: UIView!
 
    @IBOutlet weak var lblStoreLocation: UILabel!
    @IBOutlet weak var imgStoreLocation: UIImageView!

    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            lblCatrgoryName,
            lblDate,
//            lblCalass,
            lblMachineID,
            lblMachineName,
            lblLocation,
//            lblTechName,
            lblStatus,
            imgStatus,
            viewStatus,
            imgService,
            viewLine,
            lblStoreLocation,
            imgStoreLocation
        ]
    }
}


//MARK: -- UITABEL DELEGATE --

extension MachineProfileViewController : UITableViewDelegate, UITableViewDataSource{
   
    
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
            
            //START LOADING
            startAnimatingView()
            
            //CALL API
            self.callAPI()
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
            return self.arrMachineProfileList.count
            
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "MachineProfileListCell") as? MachineProfileListCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.isHidden = false
            
            if isLoading {
                cell.viewLine.isHidden = true
                self.machineProfilePlaceholderMarker.register(cell.getAnimableSubviews())
                self.machineProfilePlaceholderMarker.startAnimation()
                return cell
            }
            
            if self.arrMachineProfileList.count == 0{
                return cell
            }
            
            //GET DATA
            let objData = self.arrMachineProfileList[indexPath.row]

            //SET FONT
            if objData.objProductCategory != nil{
                cell.lblCatrgoryName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: objData.objProductCategory?.title ?? "")
            }
            cell.lblDate.configureLable(textAlignment: .right, textColor: .primary.withAlphaComponent(0.7), fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: objData.current_status_changed_at)

            cell.lblMachineID.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.equipment_id ?? "")")

            cell.lblMachineName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: "  • \(objData.equipment_name  ?? "")")

            
           
//            cell.lblTechName.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "\(objData.first_name ?? "") \(objData.last_name ?? "")")

            cell.lblStoreLocation.text = ""
            cell.imgStoreLocation.isHidden = true
            if objData.equipment_store != nil{
                cell.imgStoreLocation.isHidden = false
                cell.lblStoreLocation.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "\(objData.equipment_store?.name ?? "")")
            }
            imgColor(imgColor: cell.imgStoreLocation, colorHex: .secondary)
            
        
            //SET BUTTON STATUS
            cell.lblStatus.configureLable(textAlignment: .center, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14, text: "\(objData.current_status)")
            cell.viewStatus.backgroundColor = .clear
            cell.viewStatus.viewBorderCorneRadius(borderColour: .clear)
            
            //SET IMAGE
            cell.imgStatus.image = UIImage(named: "icon_Available")
            imgColor(imgColor: cell.imgStatus, colorHex: .secondary)

            
            let strOrderID = formattedOrderID(objData.id ?? 0)
            
            if objData.current_status == "Damaged" {
                cell.lblLocation.attributedText = setFontAttributes(str: "")
                
                cell.lblStatus.configureLable(textAlignment: .center, textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14, text: "\(objData.current_status)")
                
                //SET IMAGE
                cell.imgStatus.image = UIImage(named: "icon_Damaged")
                imgColor(imgColor: cell.imgStatus, colorHex: .redText)
            }
            else if objData.current_status == "Maint. Hold" || objData.current_status == "Maintenance Hold"{
                cell.lblLocation.attributedText = setFontAttributes(str: "")
                
                cell.lblStatus.configureLable(textAlignment: .center, textColor: .secondaryText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14, text: "\(objData.current_status)")
                
                //SET IMAGE
                cell.imgStatus.image = UIImage(named: "icon_MaintHold")
                imgColor(imgColor: cell.imgStatus, colorHex: .secondaryText)
            }
            else if objData.current_status == "Rented" {
                cell.lblLocation.configureLable(textAlignment: .right, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(strOrderID)")
                cell.lblLocation.attributedText = setFontAttributes(str: "Order ID: \(strOrderID)")
                
                cell.lblStatus.configureLable(textAlignment: .center, textColor: .greenText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14, text: "\(objData.current_status)")
                
                //SET IMAGE
                cell.imgStatus.image = UIImage(named: "icon_Rented")
                imgColor(imgColor: cell.imgStatus, colorHex: .greenText)
            }
            else {
                cell.lblLocation.attributedText = setFontAttributes(str: "")
            }
            
            //SET SERVICE
            cell.imgService.isHidden = true
//            imgColor(imgColor: cell.imgService, colorHex: .secondaryText)
//            if objData.has_machine_hour == 1 {
//                cell.imgService.isHidden = false
//            }

            // BUTTON ACTION
            cell.btnOrder.tag = indexPath.row
            cell.btnOrder.addTarget(self, action: #selector(self.btnOrderClicked(_:)), for: .touchUpInside)

            cell.layoutIfNeeded()
            return cell

        }
        return UITableViewCell()
    }
    
    
    func setFontAttributes(str : String) -> NSMutableAttributedString{
        let yourAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.secondary ,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]

        
        let attributeString = NSMutableAttributedString(
            string: str,
            attributes: yourAttributes
        )

        return attributeString
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if self.arrMachineProfileList.count == 0 {
            return
        }
        
        let objData = self.arrMachineProfileList[indexPath.row]
        let strOrderID = formattedOrderID(objData.current_order_id)
        let strEquipmentID = "\(objData.equipment_id ?? "")"
        let strEquipmentName = objData.equipment_name  ?? ""
        
        if objData.current_status == "Rented" && objData.current_order_unique_id != ""{

            let strMsg = "This \(strEquipmentName) - ID: \(strEquipmentID) is currently Rented and cannot be updated in the Rental Ready system.\n\nIf the rental is completed, please update the order to close out the rental → \(strOrderID)"

            let alert = UIAlertController(title: "", message: strMsg, preferredStyle: UIAlertController.Style.alert)
            
            alert.addAction(UIAlertAction(title: str.no, style: UIAlertAction.Style.default, handler: nil))
            
            alert.addAction(UIAlertAction(title: str.moveToOrder, style: .default, handler: { actionn in
                
                //MOVE TO ORDER DETAILS SCREEN
                
                let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
                if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
                    newViewController.strOrderUniqueId = objData.current_order_unique_id
                    newViewController.strOrderID = strOrderID
                    self.navigationController?.pushViewController(newViewController, animated: true)
                }
                
            }))
            
            getTopViewController?.present(alert, animated: true)
            
            return
        }
        
        //MOVE FORGOT SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.EQUIPMENT_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "MachineDetailsViewController") as? MachineDetailsViewController{
            newViewController.objRentalReadyData = self.arrMachineProfileList[indexPath.row]
            newViewController.strID = self.arrMachineProfileList[indexPath.row].unique_id ?? ""
            newViewController.strTitleName = "\(self.arrMachineProfileList[indexPath.row].equipment_name ?? "") (\(self.arrMachineProfileList[indexPath.row].equipment_id ?? ""))"
            newViewController.arrRentalReady = self
                .arrMachineProfileList[indexPath.row].arrAnswerRentalCheckList ?? []
            self.navigationController?.pushViewController(newViewController, animated: true)
        }

    }
    
    
    @objc func btnOrderClicked(_ sender : UIButton) {
        if self.arrMachineProfileList.count == 0{
            return
            
        }
        
//        
//        if self.arrMachineProfileList[sender.tag].order_id != nil{
//            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
//            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
//                newViewController.strOrderID = "\(self.arrMachineProfileList[sender.tag].order_id ?? 0)"
//                self.navigationController?.pushViewController(newViewController, animated: true)
//            }
//        }
    }
}

