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

    @IBOutlet var emptyDataView : EmptyDataView!{
        didSet{
            emptyDataView.noDataFound()
            emptyDataView.isHidden = true
        }
    }
    
    
    //LOADING
    let schedulePlaceholderMarker = Placeholder()
    var arrOrderList : [SchedulesModel] = []
    
    //OTHER
    var isLoading : Bool = true
    var objRefresh : UIRefreshControl?
    var _loadingView: UIActivityIndicatorView!
    var bool_Load: Bool = false
    var pageCount: Int = 1
    var isDeliveryType : Bool = true
    var isPending : Bool = true

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
        self.viewLine.backgroundColor = .clear
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
        setNavigationBarFor(controller: self, title: str.strScheduleTitle, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "icon_cart_shopping", isDetailsScree: true) {
            
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
        self.getScheduleList(OrdersParameater: OrdersParameater(page: "\(self.pageCount)"))
    }
    
    func setTheView(){
        
        //SET FONT
        self.lblDelivery.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strDelivery)
        self.lblPickup.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strPickup)

        self.lblPending.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strPending)
        self.lblCompleted.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strCompleted)

        
        self.setTheType(isDelivery: self.isDeliveryType)
        self.setOrderType(isPending: self.isPending)
        
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
    
    func setTheType(isDelivery : Bool){
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
}

//MARK: - BUTTON ACTION
extension ScheduleListViewController {
    @IBAction func btnDeliveryClicked(_ sender: UIButton) {
        self.isDeliveryType = true
        
        //SET VIEW
        self.setTheType(isDelivery: self.isDeliveryType)
    }
    
    @IBAction func btnPickupClicked(_ sender: UIButton) {
        self.isDeliveryType = false
        
        //SET VIEW
        self.setTheType(isDelivery: self.isDeliveryType)

    }
    
    @IBAction func btnPendingClicked(_ sender: UIButton) {
        self.isPending = true
        
        //SET VIEW
        self.setOrderType(isPending: self.isPending)
    }
    
    @IBAction func btnCompletedClicked(_ sender: UIButton) {
        self.isPending = false
        
        //SET VIEW
        self.setOrderType(isPending: self.isPending)
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

    @IBOutlet weak var viewDelivery: UIView!
    @IBOutlet weak var imgDelivery: UIImageView!
    @IBOutlet weak var lblDelivery: UILabel!
    @IBOutlet weak var btnDelivery: UIButton!

    @IBOutlet weak var viewTermsAndCondition: UIView!
    @IBOutlet weak var lblTermsAndCondition: UILabel!
    @IBOutlet weak var btnTermsAndCondition: UIButton!

    
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
            viewTermsAndCondition,
        ]
    }
}



//MARK: -- UITABEL DELEGATE --

extension ScheduleListViewController : UITableViewDelegate, UITableViewDataSource, MFMessageComposeViewControllerDelegate {
 
    

    
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
                        self.getScheduleList(OrdersParameater: OrdersParameater(page: "\(self.pageCount)"))
                     
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
        if let cell = tableView.dequeueReusableCell(withIdentifier: "ScheduleListCell") as? ScheduleListCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.isHidden = false
            
            if isLoading {
                cell.viewLine.isHidden = true
                self.schedulePlaceholderMarker.register(cell.getAnimableSubviews())
                self.schedulePlaceholderMarker.startAnimation()
                return cell
            }
            
            //GET DATA
            let objData = self.arrOrderList[indexPath.row]
            
            //SET FONT
            cell.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.name ?? "")")
            cell.lblPhone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(objData.phone ?? "")")
            imgColor(imgColor: cell.imgCall, colorHex: .secondary)
            
            cell.lblDelivery.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strLinces)
            cell.lblTermsAndCondition.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strTerms)

            
            //SET NAME
            var strProduct : String = ""
            for objProduct in objData.order?.arrProduct ?? []{
                strProduct = "\(objProduct.product_name ?? "") * \(objProduct.qty )"
            }
            cell.lblProductName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: strProduct)

            
            
            //CHECK AND SET VIEW
            cell.viewDelivery.backgroundColor = .clear
            cell.viewDelivery.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            imgColor(imgColor: cell.imgDelivery, colorHex: .secondary)
            
            if objData.order?.license_image_links.count != 0{
                cell.lblDelivery.textColor = .background
                imgColor(imgColor: cell.imgDelivery, colorHex: .background)
                cell.viewDelivery.backgroundColor = .secondary
            }
            
            //T&C
            cell.viewTermsAndCondition.backgroundColor = .clear
            cell.viewTermsAndCondition.viewBorderCorneRadius(radius: 10, borderColour: .secondary)
            
            if objData.order?.customer_signature != "" && objData.order?.customer_signature != nil{
                cell.lblTermsAndCondition.textColor = .background
                cell.viewTermsAndCondition.backgroundColor = .secondary
            }
            
            
            // BUTTON ACTION
            cell.btnCall.tag = indexPath.row
            cell.btnCall.addTarget(self, action: #selector(self.btnCallClicked(_:)), for: .touchUpInside)

//            cell.btnDelivery.tag = indexPath.row
//            cell.btnDelivery.addTarget(self, action: #selector(self.btnDeliveryClicked(_:)), for: .touchUpInside)

            cell.btnTermsAndCondition.tag = indexPath.row
            cell.btnTermsAndCondition.addTarget(self, action: #selector(self.btnTermsAndConditionClicked(_:)), for: .touchUpInside)

            
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
    
    @objc func btnCallClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0{
            return
        }
        
        var getNumber = self.arrOrderList[sender.tag].phone ?? ""
        getNumber = getNumber.replacingOccurrences(of: "+1", with: "")
        
        let pickerAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        
      
        let cancel = UIAlertAction.init(title: "Cancel", style: UIAlertAction.Style.cancel, handler: { (action) in
            
            pickerAlert.dismiss(animated: true, completion: nil)
        })
        
        let call = UIAlertAction.init(title: "Call \(self.arrOrderList[sender.tag].phone ?? "")", style: UIAlertAction.Style.default, handler: { (action) in
            
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

    
    
  
    
//    @objc func btnDeliveryClicked(_ sender : UIButton) {
//        if self.arrOrderList.count == 0{
//            return
//        }
//
//    }
//    
    
    @objc func btnTermsAndConditionClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0{
            return
        }
        
     
    }
    
   
}



extension ScheduleListViewController{
    
}
