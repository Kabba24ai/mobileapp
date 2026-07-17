//
//  AddressViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 27/02/24.
//

import UIKit


protocol UpdateDriverDelegate{
    func updateDriver(delivery_employee: EmployeesModel?, pickup_employee: EmployeesModel?, index: Int)
}

class AssignDriverViewController: UIViewController, UIGestureRecognizerDelegate {
    var delegate: UpdateDriverDelegate?

    //CONSTANT
    @IBOutlet weak var tblView: UITableView!

    @IBOutlet weak var con_Btn: NSLayoutConstraint!
    @IBOutlet weak var lblSubmit : UILabel!
    @IBOutlet weak var viewSubmit: UIView!
    
    

    @IBOutlet weak var viewDriverDlivery: UIView!
    @IBOutlet weak var txtDriverDlivery: UITextField!
    @IBOutlet weak var lblDriverDlivery: UILabel!
    @IBOutlet weak var lblDeliveryFrom: UILabel!
    @IBOutlet weak var lblDeliveryTo: UILabel!

    @IBOutlet weak var viewDriverReturn: UIView!
    @IBOutlet weak var txtDriverReturn: UITextField!
    @IBOutlet weak var lblDriverReturn: UILabel!
    @IBOutlet weak var lblReturnFrom: UILabel!
    @IBOutlet weak var lblReturnTo: UILabel!

    
    var arrDriverEmployesList : [EmployeesModel] = []

    var delivery_employee: EmployeesModel?
    var pickup_employee: EmployeesModel?

    var productUniqueId : String = ""
    var selectDispatchIndex : Int = 0
    var deliveryFrom = "From : Pending"
    var deliveryTo = "To : Pending"
    var returnFrom = "From : Pending"
    var returnTo = "To : Pending"

    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboard(true)

        //GET EMPLOYEE LIST DATA
        getDriverEmployeeList { arr_data in
            self.arrDriverEmployesList = arr_data
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
        setNavigationBarFor(controller: self, title: "Update Driver", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)
            
        } rightActionHandler: {
        }
        
        //SET THE VIEW
        self.setTheView()
    }
    
    //SET THE VIEW
    func setTheView() {

        //SET LABLE
        self.lblDriverDlivery.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "Driver Delivery")
        self.lblDriverReturn.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "Driver Return")

       
        self.txtDriverDlivery.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Select delivery name")

        self.txtDriverReturn.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Select return name")

        self.lblDeliveryFrom.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: self.deliveryFrom)
        self.lblDeliveryTo.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: self.deliveryTo)
        self.lblReturnFrom.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: self.returnFrom)
        self.lblReturnTo.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: self.returnTo)

        
        //START POINT
        let strFrom = "From:"
        let strTo = "To:"
        
        ///*** DELIVERY
        let rangeDeliveryFrom = (self.deliveryFrom as NSString).range(of: strFrom)
        let attributedDeliveryFromString = NSMutableAttributedString(string:self.deliveryFrom)
        attributedDeliveryFromString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.secondary , range: rangeDeliveryFrom)
        self.lblDeliveryFrom.attributedText = attributedDeliveryFromString
        self.lblDeliveryFrom.numberOfLines = 2

        let rangeDeliveryTo = (self.deliveryTo as NSString).range(of: strTo)
        let attributedDeliveryToString = NSMutableAttributedString(string:self.deliveryTo)
        attributedDeliveryToString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.secondary , range: rangeDeliveryTo)
        self.lblDeliveryTo.attributedText = attributedDeliveryToString
        self.lblDeliveryTo.numberOfLines = 2

        ///*** RETURN
        let rangeReturnFrom = (self.returnFrom as NSString).range(of: strFrom)
        let attributedReturnFromString = NSMutableAttributedString(string:self.returnFrom)
        attributedReturnFromString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.secondary , range: rangeReturnFrom)
        self.lblReturnFrom.attributedText = attributedReturnFromString
        self.lblReturnFrom.numberOfLines = 2

        let rangeReturnTo = (self.returnTo as NSString).range(of: strTo)
        let attributedReturnToString = NSMutableAttributedString(string:self.returnTo)
        attributedReturnToString.addAttribute(NSAttributedString.Key.foregroundColor, value: UIColor.secondary , range: rangeReturnTo)
        self.lblReturnTo.attributedText = attributedReturnToString
        self.lblReturnTo.numberOfLines = 2

     
        
        //SET VIEW
        self.viewDriverDlivery.setTheTextView(bgColor: .secondary )
        self.viewDriverReturn.setTheTextView(bgColor: .secondary )

        self.viewSubmit.backgroundColor = .secondaryTextView
 
        //SET CONSTANT
        self.con_Btn.constant = manageWidth(size: 45)
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strUpdate)

        self.setTheDriver()
       
        
        
        //SET HEADER
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            //SET TABLE HEADER
            let vw_Table = self.tblView.tableHeaderView
            vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.viewSubmit.frame.origin.y + self.viewSubmit.frame.size.height)

            
            self.tblView.tableHeaderView = vw_Table
        }
    }
    
    func setTheDriver(){
        //SET DRIVER NAME
        if self.delivery_employee != nil, let name = self.delivery_employee?.name{
            self.txtDriverDlivery.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: name, placeholder: "Select delivery name")

            self.txtDriverReturn.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Select return name")
        }
        
        if self.pickup_employee != nil, let name = self.pickup_employee?.name{
            self.txtDriverReturn.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: name, placeholder: "Select return name")
        }

    }
    
}

//MARK: -- BUTTON ACTION

extension AssignDriverViewController {
    
    
    @IBAction func btnSelectDriverEmployessClicked(_ sender: UIButton) {
       // self.view.endEditing(true)
        
        if self.arrDriverEmployesList.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: sender.tag == 1 ? "Select Delivery Driver" : "Select Return Driver", arrData: self.arrDriverEmployesList.compactMap { $0.name}, selectValue: sender.tag == 1 ? self.txtDriverDlivery.text ?? "" : self.txtDriverReturn.text ?? "") { index, selectValue in
            
            if sender.tag == 1{
                self.delivery_employee = self.arrDriverEmployesList[index]
            }
            else{
                self.pickup_employee = self.arrDriverEmployesList[index]
            }
            
            self.setTheDriver()
        }
    }
    
    
   
    
    @IBAction func btnUpdateClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
         //CALL DRIVER API
         if self.productUniqueId != "" && (self.delivery_employee != nil || self.pickup_employee != nil){
             var user_delivery_id = ""
             var user_pickup_id = ""
             if self.delivery_employee != nil, let userID = self.delivery_employee?.id{
                 user_delivery_id = "\(userID)"
             }
             
             if self.pickup_employee != nil, let userID = self.pickup_employee?.id{
                 user_pickup_id = "\(userID)"
             }
             
             self.updateDriver(UpdateDriversParameater: UpdateDriversParameater(order_product_unique_id: self.productUniqueId, user_delivery_id: user_delivery_id, user_pickup_id: user_pickup_id))
             
           
         }
    }
}







