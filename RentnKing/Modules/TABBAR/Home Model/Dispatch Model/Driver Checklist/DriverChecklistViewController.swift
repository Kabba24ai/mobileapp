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
    var strKeys : String = ""
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

    // Side-by-side toggles replacing the fuel/keys dropdowns (delivery only)
    private let fuelSegment = UISegmentedControl(items: ["Full", "Refill"])
    private let keysSegment = UISegmentedControl(items: ["Present", "Missing"])

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

        if self.objDispatch?.is_delivered == false {
            //DELIVERY CASE
            ready_to_go_at = self.objDispatch?.delivery_checklist?.ready_to_go_at ?? ""
        }
        else{
            //PICKUP CASE
            ready_to_go_at = self.objDispatch?.pickup_checklist?.ready_to_go_at ?? ""
        }

        if ready_to_go_at != "" {
            //ARRIVED BUTTON VIEW SHOW

            // Show On My Way status view, hide checklist
            self.viewArrivedMain?.isHidden = false
            self.viewDriverCheckList.isHidden = true
            

            // Set current date & time
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let dateee = formatter.date(from: ready_to_go_at) {
                formatter.dateFormat = "MM/dd/yyyy hh:mm a"
                self.lbl_Arrived_dateTime.text = formatter.string(from: dateee)
            }
            else {
                formatter.dateFormat = "MM/dd/yyyy hh:mm a"
                self.lbl_Arrived_dateTime.text = formatter.string(from: Date())
            }

            self.setupHeader(arrived: true)
            
        }
        else {
            //READY TO GO BUTTON VIEW SHOW
        }
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

        // Host both labelled segments side-by-side; transparent container, no border
        self.con_DoubleCheck.constant = 84
        self.viewDoubleCheck.isHidden = false
        self.viewDoubleCheck.backgroundColor = .clear
        self.viewDoubleCheck.layer.borderWidth = 0

        let fuelColumn = makeSegmentColumn(title: "2. Equipment Fuel", segment: fuelSegment)
        let keysColumn = makeSegmentColumn(title: "3. Keys", segment: keysSegment)

        let row = UIStackView(arrangedSubviews: [fuelColumn, keysColumn])
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

        // Defaults: Refill (index 1) and Missing (index 1)
        fuelSegment.selectedSegmentIndex = 1
        keysSegment.selectedSegmentIndex = 1
        self.strDoubleCheck = "Refill"
        self.strKeys = "Missing"

        fuelSegment.addTarget(self, action: #selector(fuelSegmentChanged(_:)), for: .valueChanged)
        keysSegment.addTarget(self, action: #selector(keysSegmentChanged(_:)), for: .valueChanged)

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

        segment.selectedSegmentTintColor = .secondary
        segment.backgroundColor = .clear
        segment.layer.borderWidth = 1
        segment.layer.borderColor = UIColor.secondary.cgColor
        segment.layer.cornerRadius = 8
        segment.layer.masksToBounds = true
        segment.setTitleTextAttributes([.foregroundColor: UIColor.secondary as Any,
                                        .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 12)], for: .normal)
        segment.setTitleTextAttributes([.foregroundColor: UIColor.black,
                                        .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 12)], for: .selected)
        segment.translatesAutoresizingMaskIntoConstraints = false
        segment.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let column = UIStackView(arrangedSubviews: [lbl, segment])
        column.axis = .vertical
        column.spacing = 16
        column.alignment = .fill
        return column
    }

    @objc private func fuelSegmentChanged(_ sender: UISegmentedControl) {
        self.strDoubleCheck = sender.selectedSegmentIndex == 0 ? "Full" : "Refill"
        self.updateReadyToGoButton()
    }

    @objc private func keysSegmentChanged(_ sender: UISegmentedControl) {
        self.strKeys = sender.selectedSegmentIndex == 0 ? "Present" : "Missing"
        self.updateReadyToGoButton()
    }
    
    
    private func updateReadyToGoButton() {
        let allChecked = self.checklistType == "pickup" ? !callReturnCustomerChecks.contains(false) : !callDeliveryCustomerChecks.contains(false)
        let fuelFilled = !(self.strDoubleCheck).trimmingCharacters(in: .whitespaces).isEmpty
        let keysFilled = !(self.strKeys).trimmingCharacters(in: .whitespaces).isEmpty
        
        var isEnabled = allChecked && fuelFilled && keysFilled
        if self.checklistType == "pickup"{
            isEnabled = allChecked
        }
        btnReadytoGo.isEnabled = isEnabled
        // Delivery → light green, Return/pickup → amber
        let enabledColor: UIColor = (self.checklistType == "pickup") ? .secondaryText : UIColor(red: 0.404, green: 0.792, blue: 0.404, alpha: 1.0)
        viewReadytoGo.backgroundColor = isEnabled ? enabledColor : .darkGray
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
        
        
        saveDriverChecklistLocally(order_product_unique_id: self.productUniqueId, equipment_fuel: self.strDoubleCheck, equipment_key_location: self.strKeys, equipment_driver_status: kDriverCheckListStatus.kReadytoGo.rawValue, checklist_type: self.checklistType)
        syncDriverChecklistWithAPI()
        
        
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
            //DELIVERY CASE
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
        self.lblArrived.configureLable(textAlignment: .center, textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16, text: "Arrived")
        
        self.btnArrivedView.viewCorneRadius(radius: 12, isRound: false)
        // Same colour as the Ready-to-Go button: delivery → green, return → amber
        self.btnArrivedView.backgroundColor = (self.checklistType == "pickup") ? .secondaryText : UIColor(red: 0.404, green: 0.792, blue: 0.404, alpha: 1.0)
        self.btnArrived.addTarget(self, action: #selector(btnArrivedClicked), for: .touchUpInside)
        
        self.viewArrivedMain.isHidden = true
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
        
        
                
        saveDriverChecklistLocally(
            order_product_unique_id: self.productUniqueId,
            equipment_fuel:          self.strDoubleCheck,
            equipment_key_location:  self.strKeys,
            equipment_driver_status: kDriverCheckListStatus.kArrived.rawValue,
            checklist_type: self.checklistType
        )
        syncDriverChecklistWithAPI()
        
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
        
        
        //            self.navigationController?.popViewController(animated: true)
        
        //ORDER DETAILS SCREEN
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







