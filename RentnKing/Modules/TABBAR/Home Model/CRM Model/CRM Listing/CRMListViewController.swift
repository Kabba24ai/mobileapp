//
//  CRMListViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 26/05/26.
//

import UIKit

class CRMListViewController: UIViewController , UIGestureRecognizerDelegate {
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

    var currentPage: Int = 1
    var perPage: Int = 10
    var isLoadingMore: Bool = false
    var hasMoreData: Bool = true
    
    
    //OTHER
    let customerPlaceholderMarker = Placeholder()
    var isLoading : Bool = true
    var objRefresh : UIRefreshControl?
    
    var arrMainCustomerList : [CustomerModel] = []
    var arrCustomerList : [CustomerModel] = []
    
    var arrTagList : [CustomerTagModel] = []

    var arr_selectTagID = [String]()

    
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

        
        //GET TAG DATA
        getCustomerTagList { arr_data in
            self.arrTagList = arr_data
        }
        
        //GET DATA
        self.refreshList()
       
        
        NotificationCenter.default.addObserver(self, selector: #selector(refreshList), name: .refreshMachineProfileList, object: nil)
    }
    

    @objc func refreshList(){
        //GET Customer LIST DATA
        getCustomerList(page: self.currentPage, perPage: self.perPage, completion: { arr_data in
            self.isLoading = false
            self.objRefresh?.endRefreshing()
            self.arrCustomerList = arr_data
            self.arrMainCustomerList = arr_data
            self.tblView.reloadData()
            
            self.setTheView()
        })
            
        
    }
    
    func loadCustomers(isRefresh: Bool = false) {

        if isLoadingMore || !hasMoreData {
            return
        }

        isLoadingMore = true

        if isRefresh {
            currentPage = 1
            hasMoreData = true
        }

        getCustomerList(
            page: currentPage,
            perPage: perPage
        ) { arr_data in

            self.isLoading = false
            self.objRefresh?.endRefreshing()
            self.isLoadingMore = false

            if isRefresh {
                self.arrCustomerList.removeAll()
            }

            if arr_data.count < self.perPage {
                self.hasMoreData = false
            }

            self.arrCustomerList.append(contentsOf: arr_data)
            self.arrMainCustomerList = self.arrCustomerList

            self.currentPage += 1

            self.tblView.reloadData()
            self.setTheView()
        }
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
    }

    
    func setNavigation(){
        //SET NAVIGATION BAR
        setNavigationBarForButtons(controller: self, title: str.strCustomer, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: ["icon_Filter"], isFilter: self.checkFilter()) {
            setupKeyboard(true)

            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in
        
            //FILTER
            let storyboard = UIStoryboard(name: GlobalMainConstants.EQUIPMENT_MODEL, bundle: nil)
            let view = storyboard.instantiateViewController(withIdentifier: "MachineFilterViewController") as! MachineFilterViewController
            view.delegate = self
            view.screenFromCustomer = true
            view.arrCustomerTag = self.arrTagList
            view.arrSelectedTag = self.arr_selectTagID
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
            if self.arrCustomerList.count == 0 {
                self.emptyDataView.isHidden = false
            }
            
            //RELOAD DATA
            self.tblView.reloadData()
        }
    }
    
    
    
    func stopLoading(){
        indicatorHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.customerPlaceholderMarker.remove()
        }
    }
    
    func checkFilter() -> Bool{
        //CEHCK FILTER
        if self.arr_selectTagID.count != 0 {
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
        
        CallAPIforGetCustomerList(CustomerParameater: CustomerParameater.init(page: 1, per_page: 10, search_name: strSearch)) { arr_data in
            self.isLoading = false
            self.objRefresh?.endRefreshing()
            self.arrCustomerList = arr_data
            self.emptyDataView.isHidden = self.arrCustomerList.count == 0 ? false : true
            
            //RELOAD TABLE
            self.tblView.reloadData()
        }
    }
    
    
}



extension CRMListViewController : MachineFilterProtocol{
    
    func SelectFilter(categoryID: Int, strStatus: String, strService: String) {
        var strTag = ""
        self.arr_selectTagID.removeAll()

        if strStatus != "" {
            strTag = strStatus
            self.arr_selectTagID = strStatus.components(separatedBy: ",")
        }
        
        if strStatus == "0" {
            strTag = ""
        }
        
        self.currentPage = 1
        self.isLoadingMore = false
        self.hasMoreData = true
        
        CallAPIforGetCustomerList(CustomerParameater: CustomerParameater.init(page: self.currentPage, per_page: 10, tag: strTag)) { arr_data in
            self.isLoading = false
            self.objRefresh?.endRefreshing()
            self.arrCustomerList = arr_data
            self.emptyDataView.isHidden = self.arrCustomerList.count == 0 ? false : true
            
            //RELOAD TABLE
            self.tblView.reloadData()
        }

        self.setNavigation()
                
    }
}





//MARK: -- UITABEL DELEGATE --

//MARK: -- TABLE CELL --
class CustomerListCell : UITableViewCell{

    @IBOutlet weak var lblCustomerName: UILabel!
    @IBOutlet weak var lblCustomerPhone: UILabel!
    @IBOutlet weak var objCustomerPhone: UIStackView!

    @IBOutlet weak var lblCompanyName: UILabel!
    @IBOutlet weak var lblCompanyPhone: UILabel!
    @IBOutlet weak var objCompanyPhone: UIStackView!
    
    @IBOutlet weak var viewOrders: UIView!
    @IBOutlet weak var lblOrders: UILabel!
    
    @IBOutlet weak var viewTag: UIView!
    @IBOutlet weak var lblTag: UILabel!

    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            lblCompanyName,
            lblCustomerPhone,
            lblCustomerName,
            lblCompanyPhone,
            lblOrders
        ]
    }
}

extension CRMListViewController : UITableViewDelegate, UITableViewDataSource{
   
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.frame.size.height

        if offsetY > contentHeight - frameHeight - 100 {

            if !isLoadingMore && hasMoreData {
                loadCustomers()
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
            return self.arrCustomerList.count
            
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "CustomerListCell") as? CustomerListCell {
            cell.selectionStyle = .none
            cell.backgroundColor = UIColor.clear
            
            if isLoading {
                self.customerPlaceholderMarker.register(cell.getAnimableSubviews())
                self.customerPlaceholderMarker.startAnimation()
                return cell
            }
            
            if self.arrCustomerList.count == 0{
                return cell
            }
            
            //GET DATA
            let objData = self.arrCustomerList[indexPath.row]

            //SET FONT
            
            //CUSTOMER
            let strCustmerName = (objData.full_name == "" || objData.full_name == " ") ? "N/A" : objData.full_name ?? ""
            cell.lblCustomerName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: strCustmerName)

            let strCustmerPhone = (objData.phone == "" || objData.phone == " ") ? "N/A" : objData.phone ?? ""
            cell.lblCustomerPhone.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16, text: strCustmerPhone)
            cell.lblCustomerPhone.backgroundColor = .red
            

            //COMPANY
            let strCompanyName = (objData.company_name == "" || objData.company_name == " ") ? "N/A" :  objData.company_name ?? ""
            cell.lblCompanyName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(strCompanyName)")
          
            let strCompanyPhone = (objData.company_phone == "" || objData.company_phone == " ") ? "N/A" : objData.company_phone ?? ""
            cell.lblCompanyPhone.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16, text: strCompanyPhone)


            cell.lblOrders.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14, text: "0 Orders")
            cell.lblTag.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14, text: "\(objData.arr_tags.count) \((objData.arr_tags.count == 0 || objData.arr_tags.count == 1) ? "Tag" : "Tags")")
            
            //SET VIEW
            cell.viewOrders.backgroundColor = .secondary.withAlphaComponent(0.2)
            cell.viewTag.backgroundColor = .secondary.withAlphaComponent(0.2)
            cell.viewOrders.viewCorneRadius(radius: 0, isRound: true)
            cell.viewTag.viewCorneRadius(radius: 0, isRound: true)
            

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
        if self.arrCustomerList.count == 0 {
            return
        }
        
        let objData = self.arrCustomerList[indexPath.row]
        
        //MOVE SCHEDULE SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.EQUIPMENT_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CRMListDetailViewController") as? CRMListDetailViewController {
            newViewController.customer = objData
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
        
    }
    
    
    @objc func btnOrderClicked(_ sender : UIButton) {
        if self.arrCustomerList.count == 0{
            return
            
        }
    }
}

