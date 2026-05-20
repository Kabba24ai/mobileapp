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

    var arrMachineProfileList : [MachineProfileModel] = []
    var arrCategorys : [CategoryModel] = []
    var arrClass : [CategoryModel] = []
    var arrStatues : [InventoryStatusModel] = []
    var arrServices : [InventoryStatusModel] = []

    var selectCategoryID : String = ""
    var selectClassID : String = ""
    var selectStatus : String = "all"
    var selectService : String = "all"

    
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
        self.setNavigation()

        //GET DATA
        self.refreshList()

    }

    @objc func refreshList(){
        //GET DATA
        self.callAPI(category_id: self.selectCategoryID, class_id: self.selectClassID, machine_status: self.selectStatus, service_status: self.selectService, search: self.txtSearch.text ?? "")
       
        //FILTER
        self.getInventoryCategorys()
        self.getInventoryClass()
        self.getInventorystatus()
        self.getInventoryService()

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
            view.arrCategorys = self.arrCategorys
            view.arrClass = self.arrClass
            view.arrStatues = self.arrStatues
            view.arrServices = self.arrServices
            view.selectCategoryID = Int(self.selectCategoryID) ?? 0
            view.selectClassID = Int(self.selectClassID) ?? 0
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
        if self.selectCategoryID != "" || self.selectClassID != "" ||  (self.selectStatus != "" && self.selectStatus != "all") || (self.selectService != "" && self.selectService != "all"){
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
        
        
        //GET STORE LIST
        self.objSearchIndicator.isHidden = true
        self.objSearchIndicator.stopAnimating()
        if strSearch != "" && strSearch.count >= 3{
     
            self.callAPI(category_id: self.selectCategoryID, class_id: self.selectClassID, machine_status: self.selectStatus, service_status: self.selectService, search: strSearch)
        }
        else{
            self.callAPI(category_id: self.selectCategoryID, class_id: self.selectClassID, machine_status: self.selectStatus, service_status: self.selectService, search: "")
        }
    }
    
    func callAPI(category_id: String, class_id: String, machine_status: String, service_status: String, search: String){
        //CALL API
        self.objSearchIndicator.isHidden = false
        self.objSearchIndicator.startAnimating()
        self.isLoading = true
        self.arrMachineProfileList = []
        self.emptyDataView.isHidden = true
        
        var strStatus = machine_status
        var strServiceStatus = service_status
        if machine_status.lowercased( ) == "all"{
            strStatus = ""
        }
        if service_status.lowercased( ) == "all"{
            strServiceStatus = ""
        }
        self.getMachineProfileListAPI(MAchineProfileParameater: MAchineProfileParameater(category_id: category_id, class_id: class_id, machine_status: strStatus, service_status: strServiceStatus, search: search))

        //RELOAD TABLE
        self.tblView.reloadData()
    }
}


extension MachineProfileViewController : MachineFilterProtocol{
    func SelectFilter(categoryID: Int, classID: Int, strStatus: String, strService: String) {
        self.selectCategoryID = ""
        self.selectClassID = ""
        self.selectStatus = "all"
        self.selectService = "all"

        if categoryID != 0{
            self.selectCategoryID = "\(categoryID)"
        }
        
        if classID != 0{
            self.selectClassID = "\(classID)"
        }
        
        if strStatus != "" && strStatus.lowercased() != "all"{
            self.selectStatus = strStatus
        }
        
        if strService != "" && strService.lowercased() != "all"{
            self.selectService = strService
        }

        
        
        //CALL API
        self.setNavigation()
        self.callAPI(category_id: self.selectCategoryID, class_id: self.selectClassID, machine_status: self.selectStatus, service_status: self.selectService, search: self.txtSearch.text ?? "")
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
    @IBOutlet weak var imgStatus: UIImageView!
    @IBOutlet weak var btnStatus: UIButton!
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
            btnStatus,
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
            cell.lblCatrgoryName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.category ?? "")")
            cell.lblDate.configureLable(textAlignment: .right, textColor: .primary.withAlphaComponent(0.7), fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "\(objData.status_change ?? "")")
            
//            cell.lblCalass.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "\(objData.class_name ?? "")")
//            cell.lblCalass.alpha = 0.7
            cell.lblMachineID.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.machine_id ?? "")")
            
            
            cell.lblMachineName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: "  • \(objData.product_name ?? "")")

           
//            cell.lblTechName.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "\(objData.first_name ?? "") \(objData.last_name ?? "")")
            
    
            cell.lblLocation.configureLable(textAlignment: .right, textColor: .secondary, fontName: objData.order_id != nil ? GlobalMainConstants.APP_FONT_Roboto_Bold : GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: objData.order_id != nil ? 16 : 14, text: objData.order_id != nil ? "\(objData.order_id ?? 0)" : "\(objData.location_name ?? "")")
            if objData.order_id != nil{
                cell.lblLocation.attributedText = setFontAttributes(str: objData.order_id != nil ? "Order ID : \(objData.order_id ?? 0)" : "\(objData.location_name ?? "")")
            }
            
            
            //SET BUTTON STATUS
            cell.lblStatus.configureLable(textAlignment: .center, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14, text: "\(objData.machine_status ?? "")")
            
            //SET IMAGE
            cell.imgStatus.image = UIImage(named: "icon_Available")
            imgColor(imgColor: cell.imgStatus, colorHex: .secondary)

            
            
            
            if objData.machine_status == "Damaged" {
                cell.lblStatus.configureLable(textAlignment: .center, textColor: .redText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14, text: "\(objData.machine_status ?? "")")
                
                //SET IMAGE
                cell.imgStatus.image = UIImage(named: "icon_Damaged")
                imgColor(imgColor: cell.imgStatus, colorHex: .redText)
            }
            else if objData.machine_status == "Maint. Hold" || objData.machine_status == "Maintenance Hold"{
                cell.lblStatus.configureLable(textAlignment: .center, textColor: .secondaryText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14, text: "\(objData.machine_status ?? "")")
                
                //SET IMAGE
                cell.imgStatus.image = UIImage(named: "icon_MaintHold")
                imgColor(imgColor: cell.imgStatus, colorHex: .secondaryText)
            }
            else if objData.machine_status == "Rented"{
                cell.lblStatus.configureLable(textAlignment: .center, textColor: .greenText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14, text: "\(objData.machine_status ?? "")")
                
                //SET IMAGE
                cell.imgStatus.image = UIImage(named: "icon_Rented")
                imgColor(imgColor: cell.imgStatus, colorHex: .greenText)
            }
            
            //SET SERVICE
            cell.imgService.isHidden = true
            imgColor(imgColor: cell.imgService, colorHex: .secondaryText)
            if objData.has_machine_hour == 1 {
                cell.imgService.isHidden = false
            }

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
        
        //MOVE FORGOT SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.EQUIPMENT_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "MachineDetailsViewController") as? MachineDetailsViewController{
            newViewController.strID = "\(self.arrMachineProfileList[indexPath.row].id ?? 0)"
            newViewController.strTitleName = "\(self.arrMachineProfileList[indexPath.row].product_name ?? "") (\(self.arrMachineProfileList[indexPath.row].machine_id ?? ""))"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }

    }
    
    
    @objc func btnOrderClicked(_ sender : UIButton) {
        if self.arrMachineProfileList.count == 0{
            return
            
        }
        
        
        if self.arrMachineProfileList[sender.tag].order_id != nil{
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
                newViewController.strOrderID = "\(self.arrMachineProfileList[sender.tag].order_id ?? 0)"
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
    }
}

