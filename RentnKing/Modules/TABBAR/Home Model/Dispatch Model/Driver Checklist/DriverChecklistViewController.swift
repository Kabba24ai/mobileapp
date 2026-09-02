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
    var strCallCustomer : String = "confirmed"
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

    // 2026-09 workflow correction — persistent, editable checklist state.
    /// The state Laravel last received. Leaving the screen with anything newer
    /// queues a PARTIAL driver_checklist.update (no equipment_driver_status →
    /// no ready-to-go / arrived side effects on the server).
    private var syncedSnapshot: DriverChecklistLocalState?
    /// True once past the checklist stage (Ready to Go tapped this session, or
    /// the server already has ready-to-go/arrived) — the checklist controls
    /// are hidden then, so exits must not queue a partial save.
    private var passedChecklistStage = false
    /// Server already recorded Arrived for this leg: Screen 2 still opens
    /// (routing is absolute) showing the Arrived status, and its button just
    /// continues to Order Details without re-firing the Arrived mutation.
    private var alreadyArrived = false

    // Side-by-side toggles replacing the fuel/keys dropdowns (delivery only)
    private let fuelSegment = UISegmentedControl(items: ["Not Full", "Full"])
    private let keysSegment = UISegmentedControl(items: ["Missing", "With Machine"])

    // Call Customer confirmation toggle, shown next to the "1. Call Customer" title.
    // Right option ("With Machine") is the confirmed state required before Ready to Go.
    private let callCustomerSegment = UISegmentedControl(items: ["Confirmed", "No Answer"])

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
    private var callCustomerCheckboxButtons: [UIButton] = []

    
    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        //SET LOADING
        self.setTheView()
        self.setProduct()
        self.setupDriverCheckList()
        self.setupStatusView()
        self.getReadyToGo_ArrivedStatus()
        self.setupHeader()
    }
    
    
    func getReadyToGo_ArrivedStatus() {
        var ready_to_go_at: String = ""
        var arrived_at: String = ""
        var is_arrived: Bool = false

        if self.objDispatch?.is_delivered == false {
            //DELIVERY CASE
            ready_to_go_at = self.objDispatch?.delivery_checklist?.ready_to_go_at ?? ""
            arrived_at = self.objDispatch?.delivery_checklist?.arrived_at ?? ""
            is_arrived = self.objDispatch?.delivery_checklist?.is_arrived ?? false
        }
        else{
            //PICKUP CASE
            ready_to_go_at = self.objDispatch?.pickup_checklist?.ready_to_go_at ?? ""
            arrived_at = self.objDispatch?.pickup_checklist?.arrived_at ?? ""
            is_arrived = self.objDispatch?.pickup_checklist?.is_arrived ?? false
        }

        if is_arrived {
            // ALREADY ARRIVED. Screen 2 still opens (routing is absolute) and
            // shows the recorded Arrived status; the button becomes "Continue"
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
            
            if arrived {
                getHeight = getHeight + self.viewArrivedMain!.frame.origin.y + self.viewArrivedMain!.frame.size.height
            }
            else {
                if self.objDispatch?.is_delivered == true {
                    getHeight = getHeight + self.viewReadytoGo!.frame.origin.y + self.viewReadytoGo!.frame.size.height + self.viewCallCustomerSubChecklist.frame.size.height
                }
                else {
                    getHeight = getHeight + self.viewReadytoGo!.frame.origin.y + self.viewReadytoGo!.frame.size.height
                }
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
    
    func strOpenMap(){
        if self.objDispatch == nil{
            return
        }
                      
        
        let strAddress : String = self.objDispatch?.order?.objDeliveryAddress?.full_address ?? ""
        openAddressInMap(address: strAddress)

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

        // Only show a toggle when the equipment actually has fuel / keys.
        // Hidden only when the flag is explicitly false; shown when true or missing.
        self.showFuelSegment = (self.objDispatch?.objEquipment?.is_fuel != false)
        self.showKeysSegment = (self.objDispatch?.objEquipment?.is_key != false)

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

        // Build only the columns that apply. Defaults: the LEFT option (index 0) —
        // "Not Full" / "Missing" — to match the staging screen.
        var columns: [UIView] = []

        if showFuelSegment {
            columns.append(makeSegmentColumn(title: "2. Fuel", segment: fuelSegment))
            fuelSegment.selectedSegmentIndex = 0
            self.strDoubleCheck = "Not Full"
            fuelSegment.addTarget(self, action: #selector(fuelSegmentChanged(_:)), for: .valueChanged)
        } else {
            self.strDoubleCheck = ""   // no fuel on this equipment
        }

        if showKeysSegment {
            columns.append(makeSegmentColumn(title: "3. Keys", segment: keysSegment))
            keysSegment.selectedSegmentIndex = 0
            self.strKeys = "Missing"
            keysSegment.addTarget(self, action: #selector(keysSegmentChanged(_:)), for: .valueChanged)
        } else {
            self.strKeys = ""          // no keys on this equipment
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

        callCustomerSegment.selectedSegmentIndex = 0     // default LEFT ("Missing")
        self.strCallCustomer = "confirmed"
        callCustomerSegment.addTarget(self, action: #selector(callCustomerSegmentChanged(_:)), for: .valueChanged)
        // Default "Missing" → checklist active and required.
        self.setCallCustomerChecklistEnabled(true)
    }

    /// "With Machine" (right) means the customer already has the unit — no call-customer checklist needed.
    private var isCallWithMachine: Bool { callCustomerSegment.selectedSegmentIndex == 1 }

    @objc private func callCustomerSegmentChanged(_ sender: UISegmentedControl) {
        self.strCallCustomer = sender.selectedSegmentIndex == 1 ? "no_answer" : "confirmed"
        // "With Machine" → the call-customer checklist is inactive and not required.
        // "Missing" → the checklist is active and every item must be checked.
        self.setCallCustomerChecklistEnabled(sender.selectedSegmentIndex != 1)
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
    
    
    private func updateReadyToGoButton() {
        let allChecked = self.checklistType == "pickup" ? !callReturnCustomerChecks.contains(false) : !callDeliveryCustomerChecks.contains(false)
        // A toggle that isn't shown (equipment has no fuel / no keys) is not required.
        let fuelFilled = !self.showFuelSegment || !(self.strDoubleCheck).trimmingCharacters(in: .whitespaces).isEmpty
        let keysFilled = !self.showKeysSegment || !(self.strKeys).trimmingCharacters(in: .whitespaces).isEmpty
        // "With Machine" skips the Call Customer checklist; "Missing" requires every item checked.
        let callChecklistOK = isCallWithMachine || allChecked

        var isEnabled = callChecklistOK && fuelFilled && keysFilled
        if self.checklistType == "pickup"{
            isEnabled = callChecklistOK
        }
        btnReadytoGo.isEnabled = isEnabled
        // Delivery → light green, Return/pickup → amber
//        let enabledColor: UIColor = (self.checklistType == "pickup") ? .secondaryText : UIColor(red: 0.404, green: 0.792, blue: 0.404, alpha: 1.0)
//        viewReadytoGo.backgroundColor = isEnabled ? enabledColor : .darkGray
        viewReadytoGo.backgroundColor = isEnabled ? hexStringToUIColor(hex: "3DDC6E") : .darkGray
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
        //        let alert = UIAlertController(title: "Ready to go", message: "Are you sure you're ready to go?", preferredStyle: .alert)
        //
        //        alert.addAction(UIAlertAction(title: str.no, style: .cancel))
        //
        //        alert.addAction(UIAlertAction(title: str.yes, style: .default, handler: { _ in
        //
        //
        //
        //        }))
        //
        //        self.present(alert, animated: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: {
            self.strOpenMap()
        })
        
        
        // Durably queued (Sync Engine) before the UI moves on; the toast reports Pending Sync → Synced.
        // Carries the full checklist state (answers + ticks) with the departure transition.
        //
        // Checklist-driven Queue Line (2026-09): "Load Map & Go" IS the
        // departure — it sends the canonical ON MY WAY status (the server
        // back-fills ready_to_go_at when the prep stamp was skipped, so every
        // existing consumer keeps working). The Queue Line board shows the
        // item as Staged + In Transit until arrival/signed completion.
        let readyToGoState = currentLocalState()
        let readyToGoOperationId = saveDriverChecklistLocally(order_product_unique_id: self.productUniqueId, equipment_fuel: self.strDoubleCheck, call_customer: self.strCallCustomer, equipment_key_location: self.strKeys, equipment_driver_status: kDriverCheckListStatus.kOnMyWay.rawValue, checklist_type: self.checklistType, driver_checks: readyToGoState.checks.map { $0 ? 1 : 0 })
        syncDriverChecklistWithAPI()
        KabbaSync.showStatusToast(for: readyToGoOperationId)
        passedChecklistStage = true
        syncedSnapshot = readyToGoState
        
        
        // Show On My Way status view, hide checklist
        self.viewArrivedMain.isHidden = false
        self.viewDriverCheckList.isHidden = true
        
        
        // Set current date & time
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy hh:mm a"
        self.lbl_Arrived_dateTime.text = formatter.string(from: Date())
        //========================================================//
        
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let strReadytoGoDate = formatter.string(from: Date())
        
        if self.objDispatch?.is_delivered == false {
            //DELIVERY CASE — the local saved answers are KEPT (they restore into
            //Screen 2 on every revisit; Ready to Go is a stage, not an eraser).
            self.objDispatch?.delivery_checklist?.ready_to_go_at = strReadytoGoDate
            self.delegate_Data?.data_updateInCurrentDic(index: self.selectIndex, dicCheckList: self.objDispatch?.delivery_checklist)
        }
        else{
            //PICKUP CASE
            self.objDispatch?.pickup_checklist?.ready_to_go_at = strReadytoGoDate
            self.delegate_Data?.data_updateInCurrentDic(index: self.selectIndex, dicCheckList: self.objDispatch?.pickup_checklist)
        }
        
        
        
        self.setupHeader()
        
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

    /// The screen's controls as one value (pickup has no fuel/keys — both stay "").
    private func currentLocalState() -> DriverChecklistLocalState {
        DriverChecklistLocalState(
            checks: checklistType == "pickup" ? callReturnCustomerChecks : callDeliveryCustomerChecks,
            callCustomer: self.strCallCustomer,
            fuel: self.strDoubleCheck,
            keys: self.strKeys
        )
    }

    /// Called on EVERY mutation (checkbox, segment) so progress is durable the
    /// moment it is entered — backing out, force quit and relaunch all keep it.
    func saveChecklistState() {
        UserDefaults.standard.set(currentLocalState().dictionary(), forKey: localStateKey)
    }

    func restoreChecklistState() {
        // Local copy first (most recent edits on this phone); otherwise the
        // state the server last accepted (fresh install / reassigned driver).
        let stored = DriverChecklistLocalState(dictionary: UserDefaults.standard.dictionary(forKey: localStateKey))
        let seededFromServer = stored == nil
        guard let state = stored ?? serverSeededState() else {
            syncedSnapshot = currentLocalState()
            return
        }

        if checklistType == "pickup" {
            for (i, val) in state.checks.enumerated() where i < callReturnCustomerChecks.count {
                callReturnCustomerChecks[i] = val
            }
        } else {
            for (i, val) in state.checks.enumerated() where i < callDeliveryCustomerChecks.count {
                callDeliveryCustomerChecks[i] = val
            }
        }

        let checks = checklistType == "pickup" ? callReturnCustomerChecks : callDeliveryCustomerChecks
        for (i, btn) in callCustomerCheckboxButtons.enumerated() where i < checks.count {
            btn.isSelected = checks[i]
        }

        if showFuelSegment, !state.fuel.isEmpty {
            self.strDoubleCheck = state.fuel
            fuelSegment.selectedSegmentIndex = state.fuel == "Full" ? 1 : 0
        }

        // Restore keys
        if showKeysSegment, !state.keys.isEmpty {
            self.strKeys = state.keys
            keysSegment.selectedSegmentIndex = state.keys == "With Machine" ? 1 : 0
        }

        // Restore Call Customer state ("no_answer" → checklist inactive)
        if !state.callCustomer.isEmpty {
            self.strCallCustomer = state.callCustomer
            let withMachine = (state.callCustomer == "no_answer")
            callCustomerSegment.selectedSegmentIndex = withMachine ? 1 : 0
            setCallCustomerChecklistEnabled(!withMachine)
        }

        self.updateReadyToGoButton()

        if seededFromServer {
            // Keep the server copy locally too, so the list's green band and the
            // next open agree without a network round trip.
            saveChecklistState()
        }
        // What the screen now shows IS the converged state — only edits made
        // after this point need a partial sync on exit.
        syncedSnapshot = currentLocalState()
    }

    /// The mini-checklist state the SERVER has accepted for this product+leg,
    /// from the dispatch feed's checklist block. nil when it holds nothing.
    private func serverSeededState() -> DriverChecklistLocalState? {
        let checklist = checklistType == "pickup" ? self.objDispatch?.pickup_checklist : self.objDispatch?.delivery_checklist
        guard let checklist else { return nil }
        let state = DriverChecklistLocalState(
            checks: (checklist.driver_checks ?? []).map { $0 == 1 },
            callCustomer: checklist.call_customer ?? "",
            fuel: checklist.equipment_fuel ?? "",
            keys: checklist.equipment_key_location ?? ""
        )
        return (state.hasProgress || !(checklist.driver_checks ?? []).isEmpty) ? state : nil
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
                                       driver_checks: current.checks.map { $0 ? 1 : 0 })
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
            driver_checks: arrivedState.checks.map { $0 ? 1 : 0 }
        )
        syncDriverChecklistWithAPI()
        KabbaSync.showStatusToast(for: arrivedOperationId)
        alreadyArrived = true
        syncedSnapshot = arrivedState
        
        // Set current date & time
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let strArrivedDate = formatter.string(from: Date())
        
        if self.objDispatch?.is_delivered == false {
            //DELIVERY CASE
            self.objDispatch?.delivery_checklist?.arrived_at = strArrivedDate
            self.objDispatch?.delivery_checklist?.equipment_driver_status = "Arrived"
            self.objDispatch?.delivery_checklist?.equipment_fuel = self.strDoubleCheck
            self.objDispatch?.delivery_checklist?.equipment_key_location = self.strKeys
            self.objDispatch?.delivery_checklist?.is_arrived = true
            self.objDispatch?.delivery_checklist?.is_delivered = true
            self.delegate_Data?.data_updateInCurrentDic(index: self.selectIndex, dicCheckList: self.objDispatch?.delivery_checklist)
        }
        else{
            //PICKUP CASE
            self.objDispatch?.pickup_checklist?.arrived_at = strArrivedDate
            self.objDispatch?.pickup_checklist?.equipment_driver_status = "Arrived"
            self.objDispatch?.pickup_checklist?.equipment_fuel = self.strDoubleCheck
            self.objDispatch?.pickup_checklist?.equipment_key_location = self.strKeys
            self.objDispatch?.pickup_checklist?.is_arrived = true
            self.objDispatch?.pickup_checklist?.is_delivered = true
            self.delegate_Data?.data_updateInCurrentDic(index: self.selectIndex, dicCheckList: self.objDispatch?.pickup_checklist)
        }
        
        
        self.pushOrderDetails()
    }

    /// Screen 2 → Screen 3. The ONLY way Order Details is reached from
    /// Dispatch — through this screen, for every state (see DriverChecklistRouting).
    private func pushOrderDetails() {
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
            newViewController.isOrderScreen = true
            newViewController.selectIndex = self.selectIndex
            newViewController.strOrderUniqueId = self.strOrderUniqueId
            newViewController.strOrderID = self.strOrderID
            newViewController.fromCheckListScreen = true
            newViewController.strProductID = self.productUniqueId

            newViewController.strComplateDelivery = "\(self.objDispatch?.is_delivered == false ? "Delivery" : "Return") Complete - Next Mission"
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
}







