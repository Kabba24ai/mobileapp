//
//  DriverChecklistViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 18/06/26.
//

protocol DriverChecklistDelegate {
    func data_updateInCurrentDic(index: Int, dicCheckList: CheckListResponeData?)
}



import UIKit
import MessageUI
import Alamofire
import ObjectMapper

class DriverChecklistViewController: UIViewController, UIGestureRecognizerDelegate {

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!

    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var lblPhone: UILabel!
    
    @IBOutlet weak var lblProductName: UILabel!
    @IBOutlet weak var lblOptions: UILabel!
    @IBOutlet weak var lblOptionsValues: UILabel!

    
    @IBOutlet weak var imgCall: UIImageView!
    @IBOutlet weak var lblDateTime: UILabel!
    @IBOutlet weak var imgOrderType: UIImageView!


    @IBOutlet weak var lblAddress: UILabel!
    @IBOutlet weak var btnAddress: UIButton!

    @IBOutlet weak var lblReturnAddress: UILabel!
    @IBOutlet weak var btnReturnAddress: UIButton!
    
    @IBOutlet weak var lblDriver: UILabel!
    @IBOutlet weak var imgDriver: UIImageView!
    
    @IBOutlet weak var viewDriverCheckList: UIView!
    @IBOutlet weak var lblDriverCheckListTitle: UILabel!
    @IBOutlet weak var lblCallCustomerTitle: UILabel!
    @IBOutlet weak var viewCallCustomerSubChecklist: UIView!
    @IBOutlet weak var viewCallCustomerStackChecklist: UIStackView!
    
//    @IBOutlet weak var lblDoubleCheckTitle: UILabel!
//    @IBOutlet weak var txtDoubleCheck: UITextField!
    @IBOutlet weak var viewDoubleCheck: UIView!
    @IBOutlet weak var con_DoubleCheck: NSLayoutConstraint!
    var strDoubleCheck : String = ""
    /// "" (unset) | "confirmed" | "no_answer" — nothing is preselected (spec §7.1).
    var strCallCustomer : String = ""
    var strKeys : String = ""
    var buttonColour : UIColor = .secondaryText

//    @IBOutlet weak var lblKeysTitle: UILabel!
//    @IBOutlet weak var txtKeys: UITextField!
//    @IBOutlet weak var viewkeys: UIView!
//    @IBOutlet weak var con_keys: NSLayoutConstraint!

    @IBOutlet weak var viewReadytoGo: UIView!
    @IBOutlet weak var btnReadytoGo: UIButton!
    @IBOutlet weak var lblReadytoGo: UILabel!
    
    //Arrived View
    @IBOutlet weak var viewArrivedMain: UIView!
    @IBOutlet weak var lbl_status: UILabel!
    @IBOutlet weak var lbl_Arrived_dateTime: UILabel!
    @IBOutlet weak var btnArrivedView: UIView!
    @IBOutlet weak var btnArrived: UIButton!
    @IBOutlet weak var lblArrived: UILabel!
        
    var delegate_Data: DriverChecklistDelegate?
    var objDispatch: SchedulesModel?
    var strOrderUniqueId : String = ""
    var strOrderID : String = ""
    var selectIndex : Int = 0
    var productUniqueId : String = "" //USER THIS ID FOR order_product_unique_id
    var checklistType : String = ""
    /// When the server was asked for objDispatch's data (nil = unknown): a Load Map & Go /
    /// Arrived the server confirmed after that is not in the row yet (review F2).
    var serverObservedAt: Date?

    // 2026-09 workflow correction — persistent, editable checklist state.
    /// The state Laravel last received. Leaving the screen with anything newer
    /// queues a PARTIAL driver_checklist.update (no equipment_driver_status →
    /// no ready-to-go / arrived side effects on the server).
    private var syncedSnapshot: DriverChecklistLocalState?
    /// True once past the checklist stage (Ready to Go tapped this session, or
    /// the server already has ready-to-go/arrived) — the checklist controls
    /// are hidden then, so exits must not queue a partial save.
    private var passedChecklistStage = false
    /// The effective stage is already Arrived (Dispatch normally routes that
    /// straight to Main Order, spec §5; this is the safety net if the screen is
    /// reached anyway): the Arrived status is shown and the button just
    /// continues to Order Details without re-firing the Arrived mutation.
    private var alreadyArrived = false

    // Side-by-side toggles replacing the fuel/keys dropdowns (delivery only)
    let fuelSegment = UISegmentedControl(items: ["Not Full", "Full"])
    let keysSegment = UISegmentedControl(items: ["Missing", "With Machine"])

    // Call Customer outcome, shown next to the "1. Call Customer" title:
    // Confirmed (every check required) or No Answer (an explicit, recorded attempt).
    let callCustomerSegment = UISegmentedControl(items: ["Confirmed", "No Answer"])

    // Driver Delivery Process Flow (2026-09-27): the effective unit ("Name · #TAG"),
    // the Review Assembly door (Delivery, every state) and the one sentence that
    // says why Load Map & Go is disabled — built in code, in the header stack.
    let unitIdentityLabel = UILabel()
    let reviewAssemblyButton = UIButton(type: .system)
    let gateBlockerLabel = UILabel()

    /// Seams (hosted tests inject; production reads the shared engine, the cached
    /// review, the network and Apple Maps).
    var operationsSnapshot: () -> [SyncOperation] = { KabbaSync.engine?.snapshot() ?? [] }
    var cachedAssemblyReview: (String) -> AssemblyReviewEnvelope? = { KabbaAssemblySync.cached(orderUniqueId: $0) }
    var isReachable: () -> Bool = { NetworkReachabilityManager()?.isReachable == true }
    var openMaps: (String, @escaping (Bool) -> Void) -> Void = { address, done in openAddressInMap(address: address, completion: done) }
    var presentNoticeOverride: ((UIAlertController) -> Void)?

    // Whether each toggle is shown — driven by the equipment's is_fuel / is_key flags.
    // Shown when the flag is true (or missing); hidden only when explicitly false.
    private var showFuelSegment = true
    private var showKeysSegment = true

    private let callDeliveryCustomerSubItems = [
        "Verify delivery address",
        "Verify Equipment order",
        "Verify Attachments",
        "Ask about unloading situation"
    ]
    
    private let callReturnCustomerSubItems = [
        "Pickup ready; no extension",
        "Equipment is accessible",
        "Key is in the unit"
    ]
    
    private let arrKeysItems = [
        "In Truck Cup Holder",
        "In Truck Storage Bin",
        "In my pocket",
        "Left in machine"
    ]
    
    
    private var callDeliveryCustomerChecks: [Bool] = [false, false, false, false]
    private var callReturnCustomerChecks: [Bool] = [false, false, false]
    private(set) var callCustomerCheckboxButtons: [UIButton] = []

    /// The header row built in code: the effective unit + Review Assembly.
    private let driverToolsRow = UIStackView()

    
    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        //SET LOADING
        self.setTheView()
        self.setProduct()
        self.setupDriverTools()
        self.setupDriverCheckList()
        self.setupStatusView()
        self.getReadyToGo_ArrivedStatus()
        self.setupHeader()

        // The gate and the unit header follow the engine: a switch or an
        // acknowledgement made on the Assembly Review (or drained by the sync)
        // changes what this screen may allow.
        NotificationCenter.default.addObserver(self, selector: #selector(syncQueueDidChange), name: .kabbaSyncQueueChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func syncQueueDidChange() {
        DispatchQueue.main.async { [weak self] in self?.refreshDerivedState() }
    }

    /// Re-reads what the engine and the row say — the effective unit (a switch
    /// made on the review rebinds the fuel / keys answers, D5) and the gate.
    func refreshDerivedState() {
        guard self.isViewLoaded else { return }
        self.updateUnitHeader()
        if !passedChecklistStage && !alreadyArrived {
            // Re-run the restore against the effective unit; what the server has
            // accepted is unchanged by this, so the partial-sync baseline stays.
            let synced = self.syncedSnapshot
            self.restoreChecklistState()
            self.syncedSnapshot = synced
        }
        self.updateReadyToGoButton()
    }
    
    
    func getReadyToGo_ArrivedStatus() {
        // Review F2: the stage is DERIVED from the durable Sync Engine steps (Load Map & Go /
        // Arrived saved on this phone) over the row's server copy — leaving Dispatch, a
        // force-quit or a relaunch offline can never forget it, or offer the step again.
        let effective = self.effectiveTrip()
        let ready_to_go_at: String = effective.readyToGoAt ?? ""
        let arrived_at: String = effective.arrivedAt ?? ""
        let is_arrived: Bool = effective.stage == .arrived

        if is_arrived {
            // ALREADY ARRIVED (Dispatch routes this to Main Order; safety net):
            // show the recorded Arrived status; the button becomes "Continue"
            // and only navigates — the Arrived mutation is never re-fired.
            alreadyArrived = true
            passedChecklistStage = true
            self.viewArrivedMain?.isHidden = false
            self.viewDriverCheckList.isHidden = true
            self.setStatusLine(kDriverCheckListStatus.kArrived.rawValue)
            self.lblArrived.text = "Continue"
            self.lbl_Arrived_dateTime.text = Self.displayDateTime(arrived_at.isEmpty ? ready_to_go_at : arrived_at)
            self.setupHeader(arrived: true)
        }
        else if ready_to_go_at != "" {
            //ARRIVED BUTTON VIEW SHOW — driver is en route (past the checklist stage)
            passedChecklistStage = true

            // Show On My Way status view, hide checklist
            self.viewArrivedMain?.isHidden = false
            self.viewDriverCheckList.isHidden = true

            self.lbl_Arrived_dateTime.text = Self.displayDateTime(ready_to_go_at)

            self.setupHeader(arrived: true)

        }
        else {
            //READY TO GO BUTTON VIEW SHOW
        }
    }

    /// "yyyy-MM-dd HH:mm:ss" (server) → "MM/dd/yyyy hh:mm a" (display); falls back to now.
    private static func displayDateTime(_ raw: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let parsed = formatter.date(from: raw)
        formatter.dateFormat = "MM/dd/yyyy hh:mm a"
        return formatter.string(from: parsed ?? Date())
    }

    /// Rewrites the "Status: Delivery/Return <state>" line (setupStatusView
    /// seeds it with "On the Way"; the arrived revisit shows "Arrived").
    private func setStatusLine(_ state: String) {
        let statusText = NSMutableAttributedString(
            string: "Status: ",
            attributes: [.foregroundColor: UIColor.primary,
                         .font: UIFont(name: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .bold)]
        )
        let leg = self.objDispatch?.is_delivered == false ? "Delivery" : "Return"
        statusText.append(NSAttributedString(
            string: "\(leg) \(state)",
            attributes: [.foregroundColor: UIColor.secondary,
                         .font: UIFont(name: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .bold)]
        ))
        self.lbl_status.attributedText = statusText
    }
    
    func setupHeader(arrived: Bool = false) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let vw_Table = self.tblView.tableHeaderView else { return }

            var getHeight: CGFloat = self.lblReturnAddress!.frame.origin.y + self.lblReturnAddress!.frame.size.height

            // The rows built in code sit in the same vertical stack as the checklist
            // and the status view: the unit / Review Assembly row above, the gate
            // sentence below (only while it says something). viewArrivedMain is a
            // sibling in that stack, so its origin already includes the tools row;
            // viewReadytoGo is nested inside viewDriverCheckList, so it does not.
            let spacing = (self.viewDriverCheckList.superview as? UIStackView)?.spacing ?? 0
            
            if arrived {
                getHeight = getHeight + self.viewArrivedMain!.frame.origin.y + self.viewArrivedMain!.frame.size.height
            }
            else {
                getHeight += self.driverToolsRow.isHidden ? 0 : self.driverToolsRow.frame.size.height + spacing
                if self.objDispatch?.is_delivered == true {
                    getHeight = getHeight + self.viewReadytoGo!.frame.origin.y + self.viewReadytoGo!.frame.size.height + self.viewCallCustomerSubChecklist.frame.size.height
                }
                else {
                    getHeight = getHeight + self.viewReadytoGo!.frame.origin.y + self.viewReadytoGo!.frame.size.height
                }
                getHeight += self.gateBlockerLabel.isHidden ? 0 : self.gateBlockerLabel.frame.size.height + spacing
            }
            
            vw_Table.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: getHeight + 50)
            self.tblView.tableHeaderView = vw_Table
            self.tblView.reloadData()
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
        setNavigationBarForButtons(controller: self, title: "Driver Checklist", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: [], isFilter: false) {

            //BACK SCREEN
            self.navigationController?.popViewController(animated: true)

        } rightActionHandler: {sender, SelectTag  in
        }

        // Back from the Assembly Review (a switch, an acknowledgement) or from
        // anywhere else: the unit header and the gate reflect the engine now.
        self.refreshDerivedState()
    }
    
  

    func setTheView(){
        if self.objDispatch == nil{
            return
        }
        
        //SET FONT
        self.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(self.objDispatch?.order?.customer_name ?? "")")
//            #if DEBUG
//            #endif
        self.lblPhone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(self.objDispatch?.order?.customer_phone ?? "")")
        imgColor(imgColor: self.imgCall, colorHex: .secondary)
        
//            cell.lblDelivery.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strLinces)
        
        //SET ADDRESS
        self.lblPhone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(self.objDispatch?.order?.customer_phone ?? "")")
        self.lblPhone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(self.objDispatch?.order?.customer_phone ?? "")")
        self.lblDriver.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "+ Assign")

        //SET ADDRESS
        //SET DATE
        var strDate : String = ""
        var strTime : String = ""
        
        imgColor(imgColor: self.imgDriver, colorHex: .secondary)
        var textStart = "Start Point: Pending"
        var textEnd = "End Point: Pending"
        self.btnAddress.isHidden = true
        self.btnReturnAddress.isHidden = true
        
        if self.objDispatch?.is_delivered == false {

            //SET DRIVER NAME
            if let objTransport = self.objDispatch?.delivery_employee, let name = objTransport.name{
                self.lblDriver.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: name)
            }
            
            //GET DELIVERY DATA
            strDate = "\(self.objDispatch?.delivery_date ?? "")"
            strTime = "\(self.objDispatch?.delivery_time ?? "")"
            
            //GET ADDRESS
            var locationDelivery : String = "Pending"
            if let objData = self.objDispatch?.objEquipment, let objDelivery = objData.equipment_store, let name = objDelivery.name{
                locationDelivery = name
            }
            
            self.lblAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: locationDelivery)
            
            self.lblReturnAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: "\(self.objDispatch?.order?.objDeliveryAddress?.full_address ?? "")")
            self.btnReturnAddress.isHidden = false

            
            textStart = "Start Point: \(locationDelivery)"
            textEnd = "End Point:\n\(self.objDispatch?.order?.objDeliveryAddress?.full_address ?? "")"

        }
        else {

            //SET DRIVER NAME
            if let objTransport = self.objDispatch?.pickup_employee, let name = objTransport.name{
                self.lblDriver.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: name)
            }
            
            //GET PICKUP DATA
            strDate = "\(self.objDispatch?.pickup_date ?? "")"
            strTime = "\(self.objDispatch?.pickup_time ?? "")"

            //GET ADDRESS
            var locationDelivery : String = "Pending"
            if let objData = self.objDispatch?.objEquipment, let objDelivery = objData.equipment_store, let name = objDelivery.name{
                locationDelivery = name
            }

            self.lblAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: "\(self.objDispatch?.order?.objDeliveryAddress?.full_address ?? "")")
            self.btnAddress.isHidden = false

            self.lblReturnAddress.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: locationDelivery)

            textStart = "Start Point:\n\(self.objDispatch?.order?.objDeliveryAddress?.full_address ?? "") "
            textEnd = "End Point: \(locationDelivery)"

        }
        
        

        //START POINT
        let linkTextStartWithColor = "Start Point:"
        let rangeStart = (textStart as NSString).range(of: linkTextStartWithColor)
        let attributedStartString = NSMutableAttributedString(string:textStart)
        attributedStartString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.secondary , range: rangeStart)

        self.lblAddress.attributedText = attributedStartString
        self.lblAddress.numberOfLines = 2
        
        //END POINT
        let linkTextEndWithColor = "End Point:"
        let rangeEnd = (textEnd as NSString).range(of: linkTextEndWithColor)
        let attributedEndString = NSMutableAttributedString(string:textEnd)
        attributedEndString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.secondary , range: rangeEnd)

        self.lblReturnAddress.attributedText = attributedEndString
        self.lblReturnAddress.numberOfLines = 2
        
        
        //SET IMAGE
        if self.objDispatch?.delivery_transport_mode == "Truck"{
            self.imgOrderType.image = UIImage(named: "icon_delivery_pending")
        }
        else{
            self.imgOrderType.image = UIImage(named: "icon_store")
        }
        
        self.lblDateTime.configureLable(textColor: .primary.withAlphaComponent(0.6), fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: "\(strDate) \(strTime)")
        imgColor(imgColor: self.imgOrderType, colorHex: .background)
        
      
        
        //SET STORE NAME
        self.lblProductName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: "\(self.objDispatch?.product_name ?? "")")
                
    }
    
    func setProduct(){
        if self.objDispatch == nil{
            return
        }
        
        //SET OPTIONS VALUE
        self.lblOptionsValues.text = ""
        self.lblOptions.text = ""
        
        //SET OPTION VALUE        
        var strValues : String = ""
        for objOptions in self.objDispatch?.objProduct?.arrProductOptions ?? []{
            if strValues == ""{
                strValues = "- \(objOptions.name ?? "")"
            }
            else{
                strValues = "\(strValues)\n- \(objOptions.name ?? "")"
            }
        }

        if strValues != ""{
            self.lblOptions.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: str.strOptionsTotal)
            self.lblOptions.attributedText = setUndelineFontAttributes(str: str.strOptionsTotal, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0)

            self.lblOptionsValues.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: strValues)
            self.lblOptionsValues.numberOfLines = 0
        }
    }
}


// MARK: - Button Actions

extension DriverChecklistViewController : MFMessageComposeViewControllerDelegate {

    
    @IBAction func btnCallClicked(_ sender : UIButton) {
        if self.objDispatch == nil{
            return
        }
    
        var getNumber = self.objDispatch?.order?.customer_phone ?? ""
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

    
    
    @IBAction func btnMapClicked(_ sender : UIButton) {
        self.strOpenMap()
    }
    
    /// Opens the customer address in Apple Maps; when nothing can be opened (no
    /// service, unroutable address) the Service Offline notice says so and this
    /// button stays for a retry (spec §8).
    func strOpenMap(){
        if self.objDispatch == nil{
            return
        }

        let strAddress : String = self.objDispatch?.order?.objDeliveryAddress?.full_address ?? ""
        self.openMaps(strAddress) { [weak self] opened in
            if !opened { self?.presentServiceOfflineNotice() }
        }
    }

    /// §8: the status is saved on this phone and will sync; navigation needs service.
    func presentServiceOfflineNotice() {
        let alert = UIAlertController(title: LoadMapAndGoDecision.serviceOfflineTitle,
                                      message: LoadMapAndGoDecision.serviceOfflineMessage,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        if let override = self.presentNoticeOverride {
            override(alert)
        } else {
            self.present(alert, animated: true)
        }
    }
    
}

//MARK: - Driver Checklist View
extension DriverChecklistViewController {
    
    func setupDriverCheckList() {
        
        self.lblDriverCheckListTitle.configureLable(textAlignment: .center, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strDriverCheckListTitle)
        
        self.lblCallCustomerTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16, text: str.strCallCustomer)
        setupCallCustomerSubChecklist()
        setupCallCustomerSegment()
        
//        self.lblDoubleCheckTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16, text: str.strDoubleCheck)
//        
//        self.txtDoubleCheck.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "", placeholder: str.strSelectEquipmentFuel)
//        
//        self.lblKeysTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16, text: str.strKeys)
//        
//        self.txtKeys.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "", placeholder: str.strSelectKeys)
        
        self.lblReadytoGo.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16, text: str.strReadyToGo)
        
        self.viewDoubleCheck.setTheTextView(bgColor: .primary )
//        self.viewkeys.setTheTextView(bgColor: .primary )
        self.viewReadytoGo.viewCorneRadius(radius: 12, isRound: false)
        self.updateReadyToGoButton()
        
        //SET CONTECT
        if self.checklistType  == "pickup"{
            self.con_DoubleCheck.constant = 0
//            self.con_keys.constant = 0
            self.viewDoubleCheck.isHidden = true
//            self.viewkeys.isHidden = true

//            self.lblKeysTitle.text = ""
//            self.lblDoubleCheckTitle.text = ""
        }
        else{
            self.setupFuelKeysSegments()
        }

        self.setupReadyToGoButtonLayout()
        self.restoreChecklistState()
    }

    /// Arranges the Load Map & Go icon/text like the dispatch buttons, by checklistType.
    private func setupReadyToGoButtonLayout() {
        guard let stack = lblReadytoGo.superview as? UIStackView,
              let imgLogo = stack.arrangedSubviews.compactMap({ $0 as? UIImageView }).first else { return }

        if self.checklistType == "pickup" {
            // Return: flipped icon first, then text  → [🚚][Load Map & Go]
            imgLogo.transform = CGAffineTransform(scaleX: -1, y: 1)
            stack.insertArrangedSubview(imgLogo, at: 0)
            stack.insertArrangedSubview(lblReadytoGo, at: 1)
        } else {
            // Delivery: text first, then icon (no flip)  → [Load Map & Go][icon]
            imgLogo.transform = .identity
            stack.insertArrangedSubview(lblReadytoGo, at: 0)
            stack.insertArrangedSubview(imgLogo, at: 1)
        }
    }

    /// Delivery only — replaces the fuel/keys dropdowns with two labelled toggles side by side.
    private func setupFuelKeysSegments() {
        guard fuelSegment.superview == nil else { return }

        // Hide the original dropdowns / titles
//        self.txtDoubleCheck.isHidden = true
//        self.txtKeys.isHidden = true
//        self.lblDoubleCheckTitle.text = ""
//        self.lblKeysTitle.text = ""
//        self.viewkeys.isHidden = true
//        self.con_keys.constant = 0

        // Ask only what the yard's own predicate requires (requires_fuel_check /
        // requires_key_check, D5); a cached row that predates it falls back to the
        // display flag; unknown = ask (a silent skip is never safe).
        let unit = self.objDispatch?.objEquipment
        self.showFuelSegment = DriverChecklistGate.fuelRequired(requiresFuelCheck: unit?.requires_fuel_check, isFuel: unit?.is_fuel)
        self.showKeysSegment = DriverChecklistGate.keysRequired(requiresKeyCheck: unit?.requires_key_check, isKey: unit?.is_key)

        // If the equipment has neither fuel nor keys, hide the whole container.
        if !showFuelSegment && !showKeysSegment {
            self.con_DoubleCheck.constant = 0
            self.viewDoubleCheck.isHidden = true
            self.strDoubleCheck = ""
            self.strKeys = ""
            self.updateReadyToGoButton()
            return
        }

        // Host the labelled segments side-by-side; transparent container, no border
        self.con_DoubleCheck.constant = 84
        self.viewDoubleCheck.isHidden = false
        self.viewDoubleCheck.backgroundColor = .clear
        self.viewDoubleCheck.layer.borderWidth = 0

        // Build only the columns that apply. NOTHING is preselected (spec §7.1):
        // an unanswered control is a blocker, and Not Full / Missing are recorded
        // answers that block departure (D2 / D11) — never defaults.
        var columns: [UIView] = []

        if showFuelSegment {
            columns.append(makeSegmentColumn(title: "2. Fuel", segment: fuelSegment))
            fuelSegment.selectedSegmentIndex = UISegmentedControl.noSegment
            self.strDoubleCheck = ""
            fuelSegment.addTarget(self, action: #selector(fuelSegmentChanged(_:)), for: .valueChanged)
        } else {
            self.strDoubleCheck = ""   // the yard asks no fuel question for this unit
        }

        if showKeysSegment {
            columns.append(makeSegmentColumn(title: "3. Keys", segment: keysSegment))
            keysSegment.selectedSegmentIndex = UISegmentedControl.noSegment
            self.strKeys = ""
            keysSegment.addTarget(self, action: #selector(keysSegmentChanged(_:)), for: .valueChanged)
        } else {
            self.strKeys = ""          // the yard asks no key question for this unit
        }

        let row = UIStackView(arrangedSubviews: columns)
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.alignment = .fill
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        self.viewDoubleCheck.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: viewDoubleCheck.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: viewDoubleCheck.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: viewDoubleCheck.topAnchor, constant: 8),
            row.bottomAnchor.constraint(lessThanOrEqualTo: viewDoubleCheck.bottomAnchor)
        ])

//        // Re-anchor the Ready-to-Go button a proper distance below the fuel container
//        if let sv = viewReadytoGo.superview {
//            for c in sv.constraints where (c.firstItem as? UIView) == viewReadytoGo && c.firstAttribute == .top {
//                c.isActive = false
//            }
//            viewReadytoGo.topAnchor.constraint(equalTo: viewDoubleCheck.bottomAnchor, constant: 34).isActive = true
//        }

        self.updateReadyToGoButton()
    }

    private func makeSegmentColumn(title: String, segment: UISegmentedControl) -> UIStackView {
        let lbl = UILabel()
        lbl.text = title
        lbl.textColor = .secondary
        lbl.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 16)
        lbl.adjustsFontSizeToFitWidth = true
        lbl.minimumScaleFactor = 0.7
        lbl.numberOfLines = 1

        styleChecklistSegment(segment)
        segment.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let column = UIStackView(arrangedSubviews: [lbl, segment])
        column.axis = .vertical
        column.spacing = 16
        column.alignment = .fill
        return column
    }

    /// Applies the shared Fuel/Keys/Call-Customer segmented-control styling.
    private func styleChecklistSegment(_ segment: UISegmentedControl) {
        segment.selectedSegmentTintColor = .secondary
        segment.backgroundColor = .clear
        segment.layer.borderWidth = 1
        segment.layer.borderColor = UIColor.secondary.cgColor
        segment.layer.cornerRadius = 8
        segment.layer.masksToBounds = true
        segment.apportionsSegmentWidthsByContent = false
        segment.setTitleTextAttributes([.foregroundColor: UIColor.secondary as Any,
                                        .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 12)], for: .normal)
        segment.setTitleTextAttributes([.foregroundColor: UIColor.black,
                                        .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 12)], for: .selected)
        segment.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Places the Call Customer confirmation toggle at the right of the "1. Call Customer" title.
    private func setupCallCustomerSegment() {
        guard callCustomerSegment.superview == nil, let container = lblCallCustomerTitle.superview else { return }
        styleChecklistSegment(callCustomerSegment)
        container.addSubview(callCustomerSegment)
        NSLayoutConstraint.activate([
            callCustomerSegment.centerYAnchor.constraint(equalTo: lblCallCustomerTitle.centerYAnchor),
            callCustomerSegment.trailingAnchor.constraint(equalTo: lblCallCustomerTitle.trailingAnchor),
            callCustomerSegment.heightAnchor.constraint(equalToConstant: 32),
            callCustomerSegment.widthAnchor.constraint(equalToConstant: 190),
            callCustomerSegment.leadingAnchor.constraint(greaterThanOrEqualTo: lblCallCustomerTitle.leadingAnchor, constant: 8)
        ])

        callCustomerSegment.selectedSegmentIndex = UISegmentedControl.noSegment   // nothing preselected (D3)
        self.strCallCustomer = ""
        callCustomerSegment.addTarget(self, action: #selector(callCustomerSegmentChanged(_:)), for: .valueChanged)
        self.setCallCustomerChecklistEnabled(true)
    }

    /// "No Answer" (right): an explicit, recorded call attempt — the sub-checklist does not apply.
    private var isNoAnswer: Bool { callCustomerSegment.selectedSegmentIndex == 1 }

    @objc private func callCustomerSegmentChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0: self.strCallCustomer = "confirmed"
        case 1: self.strCallCustomer = "no_answer"
        default: self.strCallCustomer = ""
        }
        // No Answer → the call-customer checklist is inactive and not required.
        // Confirmed (or nothing yet) → the checklist is active; Confirmed needs every item.
        self.setCallCustomerChecklistEnabled(!isNoAnswer)
        self.updateReadyToGoButton()
        self.saveChecklistState()
    }

    /// Enables/disables the Call Customer sub-checklist rows (checkbox + row tap) and dims them.
    private func setCallCustomerChecklistEnabled(_ enabled: Bool) {
        for row in viewCallCustomerStackChecklist.arrangedSubviews {
            row.isUserInteractionEnabled = enabled
            row.alpha = enabled ? 1.0 : 0.4
        }
        for btn in callCustomerCheckboxButtons {
            btn.isEnabled = enabled
        }
    }

    @objc private func fuelSegmentChanged(_ sender: UISegmentedControl) {
        self.strDoubleCheck = sender.selectedSegmentIndex == 0 ? "Not Full" : "Full"
        self.updateReadyToGoButton()
        self.saveChecklistState()
    }

    @objc private func keysSegmentChanged(_ sender: UISegmentedControl) {
        self.strKeys = sender.selectedSegmentIndex == 0 ? "Missing" : "With Machine"
        self.updateReadyToGoButton()
        self.saveChecklistState()
    }
    
    
    private var isDeliveryLeg: Bool { self.checklistType != "pickup" }

    /// The cached Assembly Review's gate for this mission as this phone knows it
    /// (nil = no review on this phone → honestly STOP, §6.4). Delivery only.
    private func assemblyGate(_ operations: [SyncOperation]) -> AssemblyPolicy.LocalGate? {
        guard isDeliveryLeg else { return nil }
        return AssemblyPolicy.gate(forMission: self.productUniqueId,
                                   in: self.cachedAssemblyReview(self.strOrderUniqueId)?.data,
                                   queue: QueueLineLocalOverlay.from(operations),
                                   overlay: AssemblyLocalOverlay.from(operations))
    }

    /// The departure gate (spec §7): Assembly GO ∧ Call complete ∧ (fuel n/a ∨ Full)
    /// ∧ (keys n/a ∨ With Machine) — every term explicit, no default passes.
    private var gateDecision: DriverChecklistGateDecision {
        let checks = isDeliveryLeg ? callDeliveryCustomerChecks : callReturnCustomerChecks
        return DriverChecklistGate.evaluate(DriverChecklistGateInputs(
            isDeliveryLeg: isDeliveryLeg,
            call: CallOutcome(callCustomer: self.strCallCustomer, ticks: checks),
            fuelRequired: isDeliveryLeg && self.showFuelSegment,
            fuel: FuelAnswer(rawValue: self.strDoubleCheck),
            keysRequired: isDeliveryLeg && self.showKeysSegment,
            keys: KeysAnswer(rawValue: self.strKeys),
            assemblyReady: isDeliveryLeg ? self.assemblyGate(self.operationsSnapshot())?.ready : nil))
    }

    private func updateReadyToGoButton() {
        let decision = self.gateDecision
        btnReadytoGo.isEnabled = decision.enabled
        viewReadytoGo.backgroundColor = decision.enabled ? hexStringToUIColor(hex: "3DDC6E") : .darkGray
        // The one sentence that says why — hidden once the button is live or the truck has left.
        gateBlockerLabel.text = decision.firstBlocker
        gateBlockerLabel.isHidden = decision.enabled || passedChecklistStage || alreadyArrived
    }
    
    private func setupCallCustomerSubChecklist() {
        callCustomerCheckboxButtons.removeAll()
        viewCallCustomerStackChecklist.removeAllArrangedSubviews()
        
        // Remove storyboard fixed height so container wraps stack content
        viewCallCustomerSubChecklist.constraints
            .filter { $0.firstAttribute == .height && $0.secondItem == nil }
            .forEach { $0.isActive = false }
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        viewCallCustomerSubChecklist.addSubview(stackView)
        
        let arrCustomer : [String] = checklistType != "pickup" ? callDeliveryCustomerSubItems : callReturnCustomerSubItems
        
        for (index, item) in arrCustomer.enumerated() {
            let rowView = UIView()
            rowView.translatesAutoresizingMaskIntoConstraints = false
            
            let checkbox = UIButton(type: .custom)
            checkbox.tag = index
            checkbox.setImage(UIImage(systemName: "square"), for: .normal)
            checkbox.setImage(UIImage(systemName: "checkmark.square.fill"), for: .selected)
            checkbox.tintColor = .primary
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            checkbox.addTarget(self, action: #selector(callCustomerCheckboxTapped(_:)), for: .touchUpInside)
            
            let label = UILabel()
            label.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: item)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.isUserInteractionEnabled = false
            
            rowView.addSubview(checkbox)
            rowView.addSubview(label)
            
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(callCustomerRowTapped(_:)))
            rowView.tag = index
            rowView.isUserInteractionEnabled = true
            rowView.addGestureRecognizer(tapGesture)
            
            NSLayoutConstraint.activate([
                rowView.heightAnchor.constraint(equalToConstant: 36),
                checkbox.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
                checkbox.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
                checkbox.widthAnchor.constraint(equalToConstant: 25),
                checkbox.heightAnchor.constraint(equalToConstant: 25),
                label.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
                label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor)
            ])
            
            viewCallCustomerStackChecklist.addArrangedSubview(rowView)
            
            //stackView.addArrangedSubview(rowView)
            callCustomerCheckboxButtons.append(checkbox)
        }
        
//        NSLayoutConstraint.activate([
//            stackView.topAnchor.constraint(equalTo: viewCallCustomerSubChecklist.topAnchor),
//            stackView.leadingAnchor.constraint(equalTo: viewCallCustomerSubChecklist.leadingAnchor),
//            stackView.trailingAnchor.constraint(equalTo: viewCallCustomerSubChecklist.trailingAnchor),
//            stackView.bottomAnchor.constraint(equalTo: viewCallCustomerSubChecklist.bottomAnchor)
//        ])
    }
    
    @objc private func callCustomerCheckboxTapped(_ sender: UIButton) {
        if self.checklistType == "pickup"{
            callReturnCustomerChecks[sender.tag].toggle()
            sender.isSelected = callReturnCustomerChecks[sender.tag]
        }
        else{
            callDeliveryCustomerChecks[sender.tag].toggle()
            sender.isSelected = callDeliveryCustomerChecks[sender.tag]
        }
        updateReadyToGoButton()
        self.saveChecklistState()
    }

    @objc private func callCustomerRowTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag, index < callCustomerCheckboxButtons.count else { return }
        if self.checklistType == "pickup"{
            let checkbox = callCustomerCheckboxButtons[index]
            callReturnCustomerChecks[index].toggle()
            checkbox.isSelected = callReturnCustomerChecks[index]
        }
        else{
            let checkbox = callCustomerCheckboxButtons[index]
            callDeliveryCustomerChecks[index].toggle()
            checkbox.isSelected = callDeliveryCustomerChecks[index]
        }
        updateReadyToGoButton()
        self.saveChecklistState()
    }
    
    @IBAction func btnEquimentFuel_Action(_ sender: UIButton) {
        
        actionPicker(sender, strTitle: "", arrData: arrFlueDelivery.compactMap { $0.name}, selectValue: "") { index, selectValue in
            self.strDoubleCheck = getFlueName(strId: "\(arrFlueDelivery[index].id)" )
            self.updateReadyToGoButton()
        }
    }
    
    @IBAction func btnKeys_Action(_ sender: UIButton) {
        actionPicker(sender, strTitle: "", arrData: self.arrKeysItems, selectValue: "") { index, selectValue in
            self.strKeys = selectValue
            self.updateReadyToGoButton()
        }
    }
    
    @IBAction func btnReadytoGo_Action(_ sender: UIButton) {
        // F2: a departure is recorded once — a replayed tap or stale screen never queues another;
        // the durable trip (engine over the row) decides too, not only this screen's flags (§8).
        guard !passedChecklistStage, !alreadyArrived, self.effectiveTrip().recordsDeparture else { return }

        // The gate is re-evaluated at the tap, not trusted from the button state (§7).
        let decision = self.gateDecision
        guard decision.enabled else {
            self.updateReadyToGoButton()
            return
        }

        // Record FIRST (§8). Durably queued (Sync Engine) before anything moves; the
        // toast reports Pending Sync → Synced. Carries the full checklist state —
        // answers, ticks and the unit they were given for (D5) — with the departure.
        //
        // Checklist-driven Queue Line (2026-09): "Load Map & Go" IS the
        // departure — it sends the canonical ON MY WAY status (the server
        // back-fills ready_to_go_at when the prep stamp was skipped, so every
        // existing consumer keeps working). The Queue Line board shows the
        // item as Staged + In Transit until arrival/signed completion. From this
        // moment the assignment is locked on this phone (spec §3.4).
        let readyToGoState = currentLocalState()
        let readyToGoOperationId = saveDriverChecklistLocally(order_product_unique_id: self.productUniqueId,
                                                              equipment_fuel: self.strDoubleCheck,
                                                              call_customer: self.strCallCustomer,
                                                              equipment_key_location: self.strKeys,
                                                              equipment_driver_status: kDriverCheckListStatus.kOnMyWay.rawValue,
                                                              checklist_type: self.checklistType,
                                                              driver_checks: readyToGoState.checks.map { $0 ? 1 : 0 },
                                                              equipment_unique_id: readyToGoState.equipmentUniqueId)
        syncDriverChecklistWithAPI()
        KabbaSync.showStatusToast(for: readyToGoOperationId)
        passedChecklistStage = true
        syncedSnapshot = readyToGoState

        // Show the On My Way status view, hide the checklist and the gate sentence.
        self.viewArrivedMain.isHidden = false
        self.viewDriverCheckList.isHidden = true
        self.gateBlockerLabel.isHidden = true

        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy hh:mm a"
        self.lbl_Arrived_dateTime.text = formatter.string(from: Date())

        // The Dispatch row copy learns the ANSWERS only; the stage is the engine's.
        self.reportAnswersToDispatch()
        self.setupHeader(arrived: true)

        // THEN navigate (§8): with service Apple Maps opens and Kabba stays here in
        // the On My Way state; without it — or when the address cannot be routed —
        // the Service Offline notice says the status is saved and will sync, and
        // the map button stays for a retry. Never a pretend map, never a block.
        switch LoadMapAndGoDecision.outcome(reachable: self.isReachable()) {
        case .openMaps:
            self.strOpenMap()
        case .serviceOffline:
            self.presentServiceOfflineNotice()
        }
    }

    /// Screen 2 → the Dispatch row copy: the answers as recorded (fuel, keys, call,
    /// ticks, unit). Dispatch merges exactly these fields — never the stage.
    private func reportAnswersToDispatch() {
        let state = currentLocalState()
        var block = (isDeliveryLeg ? self.objDispatch?.delivery_checklist : self.objDispatch?.pickup_checklist)
            ?? Mapper<CheckListResponeData>().map(JSON: [:])
        block?.equipment_fuel = state.fuel.isEmpty ? nil : state.fuel
        block?.equipment_key_location = state.keys.isEmpty ? nil : state.keys
        block?.call_customer = state.callCustomer.isEmpty ? nil : state.callCustomer
        block?.driver_checks = state.checks.map { $0 ? 1 : 0 }
        block?.equipment_unique_id = state.equipmentUniqueId.isEmpty ? nil : state.equipmentUniqueId
        if isDeliveryLeg { self.objDispatch?.delivery_checklist = block } else { self.objDispatch?.pickup_checklist = block }
        self.delegate_Data?.data_updateInCurrentDic(index: self.selectIndex, dicCheckList: block)
    }
    
    
    
    private func setupStatusView() {
        self.lbl_status.textAlignment = .center
        self.lbl_status.numberOfLines = 1
        let statusText = NSMutableAttributedString(
            string: "Status: ",
            attributes: [.foregroundColor: UIColor.primary,
                         .font: UIFont(name: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .bold)]
        )
        var strStatus : String = "Return \(kDriverCheckListStatus.kOnMyWay.rawValue)"
        if self.objDispatch?.is_delivered == false{
            strStatus = "Delivery \(kDriverCheckListStatus.kOnMyWay.rawValue)"
        }
        statusText.append(NSAttributedString(
            string: strStatus,
            attributes: [.foregroundColor: UIColor.secondary,
                         .font: UIFont(name: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 20) ?? UIFont.systemFont(ofSize: 20, weight: .bold)]
        ))
        self.lbl_status.attributedText = statusText
        
        // Date & Time
        self.lbl_Arrived_dateTime.textAlignment = .center
        self.lbl_Arrived_dateTime.textColor = .primary.withAlphaComponent(0.5)
        self.lbl_Arrived_dateTime.font = UIFont(name: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 14)
        self.lbl_Arrived_dateTime.text = "Date | Time"
        
        // Arrived button — same style as Ready to Go
        self.lblArrived.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16, text: "Arrived")
        
        self.btnArrivedView.viewCorneRadius(radius: 12, isRound: false)
        // Same colour as the Ready-to-Go button: delivery → green, return → amber
        
//        self.btnArrivedView.backgroundColor = (self.checklistType == "pickup") ? .secondaryText : UIColor(red: 0.404, green: 0.792, blue: 0.404, alpha: 1.0)
        self.btnArrivedView.backgroundColor = hexStringToUIColor(hex: "128A4C")
        self.btnArrived.addTarget(self, action: #selector(btnArrivedClicked), for: .touchUpInside)
        
        self.viewArrivedMain.isHidden = true
    }
    
    // MARK: - Local State Persistence
    //
    // Scoped to ORDER-PRODUCT + LEG (DriverChecklistLocalState v2 key): the
    // delivery checklist of product A can never populate its return, another
    // line of the same order, or another order. Saved answers are current
    // state, not a lock — every restore lands in the same editable controls.

    private var localStateKey: String {
        DriverChecklistLocalState.key(
            orderProductUniqueId: self.productUniqueId,
            leg: checklistType == "pickup" ? DriverChecklistLocalState.legPickup : DriverChecklistLocalState.legDelivery
        )
    }

    /// The screen's controls as one value (pickup has no fuel/keys — both stay ""),
    /// bound to the unit the answers were given for (D5).
    private func currentLocalState() -> DriverChecklistLocalState {
        DriverChecklistLocalState(
            checks: checklistType == "pickup" ? callReturnCustomerChecks : callDeliveryCustomerChecks,
            callCustomer: self.strCallCustomer,
            fuel: self.strDoubleCheck,
            keys: self.strKeys,
            equipmentUniqueId: self.effectiveUnit?.id ?? ""
        )
    }

    /// Called on EVERY mutation (checkbox, segment) so progress is durable the
    /// moment it is entered — backing out, force quit and relaunch all keep it.
    func saveChecklistState() {
        UserDefaults.standard.set(currentLocalState().dictionary(), forKey: localStateKey)
    }

    func restoreChecklistState() {
        // Local copy first (most recent edits on this phone); otherwise the state
        // the server last accepted (fresh install / reassigned driver). Either way
        // the fuel / keys answers restore ONLY for the unit they were given for
        // (D5, §7.3): a replaced unit starts unanswered; the call and its ticks
        // belong to the mission and always come back.
        let stored = DriverChecklistLocalState(dictionary: UserDefaults.standard.dictionary(forKey: localStateKey))
        let serverCopy = (checklistType == "pickup" ? self.objDispatch?.pickup_checklist : self.objDispatch?.delivery_checklist)?.serverCopy
        let state = DriverChecklistLocalState.restore(local: stored, server: serverCopy, effectiveUnit: self.effectiveUnit?.id)

        if let state {
            if checklistType == "pickup" {
                callReturnCustomerChecks = callReturnCustomerChecks.indices.map { $0 < state.checks.count ? state.checks[$0] : false }
            } else {
                callDeliveryCustomerChecks = callDeliveryCustomerChecks.indices.map { $0 < state.checks.count ? state.checks[$0] : false }
            }
        }
        let checks = checklistType == "pickup" ? callReturnCustomerChecks : callDeliveryCustomerChecks
        for (i, btn) in callCustomerCheckboxButtons.enumerated() where i < checks.count {
            btn.isSelected = checks[i]
        }

        // Fuel / keys: the recorded answer, or nothing selected.
        self.strDoubleCheck = (showFuelSegment && isDeliveryLeg) ? (state?.fuel ?? "") : ""
        fuelSegment.selectedSegmentIndex = FuelAnswer(rawValue: self.strDoubleCheck).map { $0 == .full ? 1 : 0 } ?? UISegmentedControl.noSegment
        self.strKeys = (showKeysSegment && isDeliveryLeg) ? (state?.keys ?? "") : ""
        keysSegment.selectedSegmentIndex = KeysAnswer(rawValue: self.strKeys).map { $0 == .withMachine ? 1 : 0 } ?? UISegmentedControl.noSegment

        // Call outcome: only the two explicit values are answers (a legacy "Yes" is not).
        switch state?.callCustomer {
        case "confirmed"?: self.strCallCustomer = "confirmed"; callCustomerSegment.selectedSegmentIndex = 0
        case "no_answer"?: self.strCallCustomer = "no_answer"; callCustomerSegment.selectedSegmentIndex = 1
        default:           self.strCallCustomer = "";          callCustomerSegment.selectedSegmentIndex = UISegmentedControl.noSegment
        }
        setCallCustomerChecklistEnabled(!isNoAnswer)

        self.updateReadyToGoButton()

        // The record on this phone now names the effective unit (and, seeded from
        // the server, keeps the copy locally so the list's green band and the next
        // open agree without a round trip). Its existence — defaults included — is
        // what makes a second Start Delivery land here instead of the review
        // (§3.3.1): reaching Screen 2 through the driver road IS the evidence.
        saveChecklistState()
        // What the screen now shows IS the converged state — only edits made
        // after this point need a partial sync on exit.
        syncedSnapshot = currentLocalState()
    }

    // MARK: - Partial-progress sync (Laravel convergence)

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        syncPartialProgressIfNeeded()
    }

    /// Leaving the screen with unsynced edits queues ONE durable partial save:
    /// the payload carries the answers but NO equipment_driver_status, so the
    /// server stores them without touching ready-to-go/arrived timestamps,
    /// fulfillment, or any completion side effect. Offline-safe by
    /// construction — the Sync Engine drains it when connectivity returns.
    private func syncPartialProgressIfNeeded() {
        guard !passedChecklistStage, !alreadyArrived else { return }
        let current = currentLocalState()
        guard current != syncedSnapshot else { return }

        _ = saveDriverChecklistLocally(order_product_unique_id: self.productUniqueId,
                                       equipment_fuel: self.strDoubleCheck,
                                       call_customer: self.strCallCustomer,
                                       equipment_key_location: self.strKeys,
                                       equipment_driver_status: "",   // partial: no transition
                                       checklist_type: self.checklistType,
                                       driver_checks: current.checks.map { $0 ? 1 : 0 },
                                       equipment_unique_id: current.equipmentUniqueId)
        syncDriverChecklistWithAPI()
        syncedSnapshot = current
    }

    @objc private func btnArrivedClicked() {
        //        let alert = UIAlertController(title: "Arrived", message: "Are you sure you've arrived?", preferredStyle: .alert)
        //
        //        alert.addAction(UIAlertAction(title: str.no, style: .cancel))
        //
        //        alert.addAction(UIAlertAction(title: str.yes, style: .default, handler: { _ in
        //
        //        }))
        //
        //        self.present(alert, animated: true)
        
        
                
        if alreadyArrived {
            // Revisit after arrival: the button is "Continue" — navigate only,
            // never re-fire the Arrived mutation.
            self.pushOrderDetails()
            return
        }

        let arrivedState = currentLocalState()
        let arrivedOperationId = saveDriverChecklistLocally(
            order_product_unique_id: self.productUniqueId,
            equipment_fuel:          self.strDoubleCheck, call_customer: self.strCallCustomer,
            equipment_key_location:  self.strKeys,
            equipment_driver_status: kDriverCheckListStatus.kArrived.rawValue,
            checklist_type: self.checklistType,
            driver_checks: arrivedState.checks.map { $0 ? 1 : 0 },
            equipment_unique_id: arrivedState.equipmentUniqueId
        )
        syncDriverChecklistWithAPI()
        KabbaSync.showStatusToast(for: arrivedOperationId)
        alreadyArrived = true
        syncedSnapshot = arrivedState

        // The Dispatch row copy learns the answers only; Arrived is the engine's
        // durable step (DriverStageOverlay), never a flag written onto the row.
        self.reportAnswersToDispatch()
        self.pushOrderDetails()
    }

    /// Screen 2 → Screen 3 (Main Order) — the same construction Dispatch uses when
    /// the effective stage is already Arrived (DeliveryWorkflowRouting, D4).
    private func pushOrderDetails() {
        guard let row = self.objDispatch,
              let details = DispatchListViewController.makeOrderDetails(for: row, index: self.selectIndex) else { return }
        self.navigationController?.pushViewController(details, animated: true)
    }
}

// MARK: - Driver Delivery Process Flow (2026-09-27): the effective unit, the stage, Review Assembly
extension DriverChecklistViewController {

    struct EffectiveUnit: Equatable {
        let id: String
        let name: String?
        let tag: String?
    }

    /// The unit this mission is effectively on: a switch this phone made (pending,
    /// syncing or synced — never a rejected one) outranks the row's feed copy.
    var effectiveUnit: EffectiveUnit? {
        if let pending = QueueLineLocalOverlay.from(self.operationsSnapshot()).pendingEquipment(for: self.productUniqueId) {
            return EffectiveUnit(id: pending.uniqueId, name: pending.name, tag: pending.displayId)
        }
        guard let unit = self.objDispatch?.objEquipment, let id = unit.unique_id, !id.isEmpty else { return nil }
        return EffectiveUnit(id: id, name: unit.equipment_name, tag: unit.equipment_id)
    }

    /// The driver's trip stage for this product × leg — durable local steps over the row's server copy.
    func effectiveTrip() -> DriverStageEffective {
        let checklist = self.isDeliveryLeg ? self.objDispatch?.delivery_checklist : self.objDispatch?.pickup_checklist
        return DriverStageOverlay.from(self.operationsSnapshot()).effective(
            orderProductUniqueId: self.productUniqueId, leg: self.checklistType,
            server: DriverStagePresentation.serverState(checklist), serverObservedAt: self.serverObservedAt)
    }

    /// Where this mission is (spec §3.3) as this phone knows it right now. Being on
    /// this screen through the driver road is itself the Screen 2 evidence.
    var effectiveStage: DeliveryWorkflowStage {
        let checklist = self.isDeliveryLeg ? self.objDispatch?.delivery_checklist : self.objDispatch?.pickup_checklist
        // The leg's completion is the ROW's flag; the checklist block's `is_delivered` is the
        // server's Arrived latch, never completion.
        let legCompleted = self.isDeliveryLeg ? self.objDispatch?.is_delivered == true : self.objDispatch?.is_returned == true
        return DriverMissionStage.stage(
            DriverMissionStage.Inputs(orderProductUniqueId: self.productUniqueId,
                                      isDeliveryLeg: self.isDeliveryLeg,
                                      serverTrip: DriverStagePresentation.serverState(checklist),
                                      serverObservedAt: self.serverObservedAt,
                                      serverChecklist: checklist?.serverCopy,
                                      serverLegCompleted: legCompleted,
                                      onDriverChecklist: true),
            review: self.cachedAssemblyReview(self.strOrderUniqueId)?.data,
            operations: self.operationsSnapshot())
    }

    /// The header row above the checklist: "Name · #TAG" of the effective unit and,
    /// on Delivery, the Review Assembly door (every state — operational before
    /// departure, read-only after, spec §6.1).
    private func setupDriverTools() {
        guard driverToolsRow.superview == nil, let stack = self.viewDriverCheckList.superview as? UIStackView else { return }

        unitIdentityLabel.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 15)
        unitIdentityLabel.textColor = .primary
        unitIdentityLabel.numberOfLines = 2
        unitIdentityLabel.adjustsFontSizeToFitWidth = true
        unitIdentityLabel.minimumScaleFactor = 0.8
        unitIdentityLabel.accessibilityIdentifier = "driverChecklist.unit"
        unitIdentityLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        driverToolsRow.axis = .horizontal
        driverToolsRow.alignment = .center
        driverToolsRow.spacing = 12
        driverToolsRow.isLayoutMarginsRelativeArrangement = true
        driverToolsRow.layoutMargins = UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16)
        driverToolsRow.addArrangedSubview(unitIdentityLabel)

        if isDeliveryLeg {
            reviewAssemblyButton.setTitle("Review Assembly", for: .normal)
            reviewAssemblyButton.titleLabel?.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 14)
            reviewAssemblyButton.setTitleColor(.secondary, for: .normal)
            reviewAssemblyButton.layer.borderWidth = 1
            reviewAssemblyButton.layer.borderColor = UIColor.secondary.cgColor
            reviewAssemblyButton.layer.cornerRadius = 8
            reviewAssemblyButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            reviewAssemblyButton.accessibilityIdentifier = "driverChecklist.reviewAssembly"
            reviewAssemblyButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            reviewAssemblyButton.addTarget(self, action: #selector(reviewAssemblyTapped), for: .touchUpInside)
            driverToolsRow.addArrangedSubview(reviewAssemblyButton)
        }

        gateBlockerLabel.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 13)
        gateBlockerLabel.textColor = .redText
        gateBlockerLabel.numberOfLines = 0
        gateBlockerLabel.textAlignment = .center
        gateBlockerLabel.accessibilityIdentifier = "driverChecklist.blocker"
        gateBlockerLabel.isHidden = true

        stack.insertArrangedSubview(driverToolsRow, at: 0)
        if let checklistIndex = stack.arrangedSubviews.firstIndex(of: self.viewDriverCheckList) {
            stack.insertArrangedSubview(gateBlockerLabel, at: checklistIndex + 1)
        } else {
            stack.addArrangedSubview(gateBlockerLabel)
        }
        self.updateUnitHeader()
    }

    func updateUnitHeader() {
        guard let unit = self.effectiveUnit else {
            unitIdentityLabel.text = "No equipment assigned"
            return
        }
        let name = (unit.name?.isEmpty == false) ? unit.name! : "Unit"
        unitIdentityLabel.text = (unit.tag?.isEmpty == false) ? "\(name) · #\(unit.tag!)" : name
    }

    /// Review Assembly from Screen 2 — a revisit: the review returns here, and is
    /// read-only once the phone is effectively On My Way or Arrived.
    @objc func reviewAssemblyTapped() {
        ChecklistEntry.openAssemblyReview(
            on: self.navigationController,
            orderUniqueId: self.strOrderUniqueId,
            orderNumber: self.strOrderID,
            focusOrderProductUniqueId: self.productUniqueId,
            origin: ChecklistEntry.Origin(kind: .driver(orderProductUniqueId: self.productUniqueId,
                                                        enteredFrom: self.effectiveStage,
                                                        isRevisit: true),
                                          selectIndex: self.selectIndex,
                                          fromCheckListScreen: true,
                                          missionServerTrip: DriverStagePresentation.serverState(
                                              self.isDeliveryLeg ? self.objDispatch?.delivery_checklist : self.objDispatch?.pickup_checklist),
                                          missionServerObservedAt: self.serverObservedAt))
    }
}







