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
    @IBOutlet var emptyDataView : EmptyDataView!{
        didSet{
            emptyDataView.noDataFound()
            emptyDataView.isHidden = true
        }
    }

    
    //OTHER
    let machineProfilePlaceholderMarker = Placeholder()
    var isLoading : Bool = true
    var objRefresh : UIRefreshControl?

    var arrMainMachineProfileList : [MachineModel] = []
    var arrMachineProfileList : [MachineModel] = []
    var arrCategoryList : [CategoryModel] = []
    var arrStatues : [FilterTypes] = []
    var arrServices : [FilterTypes] = []

    var selectCategoryID : Int = 0
    var selectStatus : String = "All"
    var selectService : String = "All"

    
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
        
        //GET DATA
        self.refreshList()
       
        
        NotificationCenter.default.addObserver(self, selector: #selector(refreshList), name: .refreshMachineProfileList, object: nil)
    }
    

    @objc func refreshList(){
        //GET Equipment LIST DATA
        getEquipmentList { arr_data in
            self.isLoading = false
            self.objRefresh?.endRefreshing()
            self.sortData(arr_machine: arr_data)
        }
    }
    
    func sortData(arr_machine: [MachineModel]) {
        var arrData = arr_machine
        
        let statusPriority: [String: Int] = [
            "Damaged": 0,
            "Maint. Hold": 1,
            "Maintenance Hold": 1,
            "Rented": 2,
            "Available": 3
        ]
        
        arrData.sort { m1, m2 in
            
            let s1 = statusPriority[m1.current_status] ?? Int.max
            let s2 = statusPriority[m2.current_status] ?? Int.max

            // 1️⃣ Sort by status priority
            if s1 != s2 {
                return s1 < s2
            }

            // 2️⃣ If same status → sort alphabetically by equipment name
            let name1 = m1.equipment_name ?? ""
            let name2 = m2.equipment_name ?? ""
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }
                
        self.arrMachineProfileList = arrData
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
        self.arrStatues = [FilterTypes(text: "All", value: "0"), FilterTypes(text: "Available", value: "1"), FilterTypes(text: "Damaged", value: "2"), FilterTypes(text: "Maint. Hold", value: "3"), FilterTypes(text: "Rented", value: "4")]
        self.arrServices = [FilterTypes(text: "All", value: "0"), FilterTypes(text: "Serv. Due", value: "1")]
    }

    
    func setNavigation(){
        //SET NAVIGATION BAR
        setNavigationBarForButtons(controller: self, title: str.strMachineProfile, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: ["icon_Filter"], isFilter: self.checkFilter()) {
            setupKeyboard(true)

            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in
        
            //FILTER
            let storyboard = UIStoryboard(name: GlobalMainConstants.EQUIPMENT_MODEL, bundle: nil)
            let view = storyboard.instantiateViewController(withIdentifier: "MachineFilterViewController") as! MachineFilterViewController
            view.delegate = self
            view.arrCategorys = self.arrCategoryList
            view.arrStatues = self.arrStatues
            view.arrServices = self.arrServices
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
    
    func checkFilter() -> Bool{
        //CEHCK FILTER
        if self.selectCategoryID != 0 ||  (self.selectStatus != "" && self.selectStatus != "All") || (self.selectService != "" && self.selectService != "All"){
            return true
        }
        else{
            return false
        }
    }
    
    
    // MARK: - UITEXTFIELD
    @objc func textFieldDidChangeSearch() {
    
        let strSearch = self.txtSearch.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        if strSearch.count <= 3{
            return
        }
        
        
    }
    
    func callAPI(category_id: Int, status: String, service_status: String, search: String){
        self.arrMachineProfileList = []
        
        //APPLY FILTER
        self.arrMachineProfileList = self.arrMainMachineProfileList.filter {
            ($0.current_status == status) ||
            ($0.objProductCategory?.id == category_id)
        }
        
        
        let strSearch = self.txtSearch.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        
        //GET arrSearchPhoneContacts LIST
        self.arrMachineProfileList = self.arrMachineProfileList.filter { (Int((($0.equipment_name?.lowercased()) as NSString?)?.range(of: strSearch.lowercased()).location ?? 0) != NSNotFound) || (Int((($0.equipment_id?.lowercased()) as NSString?)?.range(of: strSearch.lowercased()).location ?? 0) != NSNotFound)}
        

        self.emptyDataView.isHidden = self.arrMachineProfileList.count == 0 ? false : true

        //RELOAD TABLE
        self.tblView.reloadData()

    }
}



extension MachineProfileViewController : MachineFilterProtocol{
    
    func SelectFilter(categoryID: Int, strStatus: String, strService: String) {
        self.selectCategoryID = 0
        self.selectStatus = "All"
        self.selectService = "All"

        if categoryID != 0 {
            self.selectCategoryID = categoryID
        }
        
        
        if strStatus != "" && strStatus.lowercased() != "all"{
            self.selectStatus = strStatus
        }
        
        if strService != "" && strService.lowercased() != "all"{
            self.selectService = strService
        }
        
//        //GET Equipment LIST DATA
//        getEquipmentList { arr_data in
//            self.isLoading = false
//            self.objRefresh?.endRefreshing()
//            
//            let arrData = arr_data
//            
//            if self.selectCategoryID == 0 {
//                self.sortData(arr_machine: arrData)
//            }
//            else {
//                let filteredMachines = arrData.filter {
//                    $0.category_id == self.selectCategoryID
//                }
//                self.sortData(arr_machine: filteredMachines)
//            }
//        }
        
        getEquipmentList { arr_data in
            self.isLoading = false
            self.objRefresh?.endRefreshing()
            
            let filteredData = arr_data.filter { machine in
                
                // ✅ Category filter
                if self.selectCategoryID != 0,
                   machine.category_id != self.selectCategoryID {
                    return false
                }
                
                // ✅ Status filter
                if self.selectStatus.lowercased() != "all",
                   machine.current_status.lowercased() != self.selectStatus.lowercased() {
                    return false
                }
                
                return true
            }
            
            self.sortData(arr_machine: filteredData)
        }

        
        self.setNavigation()

        
        
//        //CALL API
//        self.setNavigation()
//        self.callAPI(category_id: self.selectCategoryID, status: self.selectStatus, service_status: self.selectService, search: self.txtSearch.text ?? "")
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
        ]
    }
}


//MARK: -- UITABEL DELEGATE --

extension MachineProfileViewController : UITableViewDelegate, UITableViewDataSource{
   
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
            
    
//            cell.lblLocation.configureLable(textAlignment: .right, textColor: .secondary, fontName: objData.order_id != nil ? GlobalMainConstants.APP_FONT_Roboto_Bold : GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: objData.order_id != nil ? 16 : 14, text: objData.order_id != nil ? "\(objData.order_id ?? 0)" : "\(objData.location_name ?? "")")
//            if objData.order_id != nil{
//                cell.lblLocation.attributedText = setFontAttributes(str: objData.order_id != nil ? "Order ID : \(objData.order_id ?? 0)" : "\(objData.location_name ?? "")")
//            }
            
            
            
        
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

