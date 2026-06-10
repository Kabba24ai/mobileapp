//
//  CRMListDetailViewController.swift
//  RentnKing
//
//  Created by DEEPAK JAIN on 27/05/26.
//

import UIKit


// MARK: - MODEL

struct CustomerDetailModel {
    
    let name: String
    let accountNumber: String
    let companyName: String?
    
    let taxStatus: String
    let validUntil: String
    
    let email: String?
    let website: String?
    let personalPhone: String?
    let companyPhone: String?
    
    let billingAddress: String?
    let deliveryAddress: String?
}

class CRMListDetailViewController: UIViewController, UIGestureRecognizerDelegate {
    
    // MARK: - Properties
    
    var customer: CustomerModel?
    
    @IBOutlet weak var lbl_name: UILabel!
    @IBOutlet weak var lbl_account: UILabel!
    @IBOutlet weak var lbl_account_title: UILabel!
    @IBOutlet weak var lbl_company_name: UILabel!
    @IBOutlet weak var lbl_company_name_title: UILabel!
    @IBOutlet weak var lbl_contact_info_title: UILabel!
    @IBOutlet weak var lbl_email: UILabel!
    @IBOutlet weak var lbl_email_title: UILabel!
    @IBOutlet weak var lbl_website: UILabel!
    @IBOutlet weak var lbl_website_title: UILabel!
    @IBOutlet weak var lbl_phone: UILabel!
    @IBOutlet weak var lbl_phone_title: UILabel!
    @IBOutlet weak var lbl_company_phone: UILabel!
    @IBOutlet weak var lbl_company_phone_title: UILabel!
    
    @IBOutlet weak var lbl_address_info_title: UILabel!
    @IBOutlet weak var lbl_billing_address: UILabel!
    @IBOutlet weak var lbl_billing_address_title: UILabel!
    @IBOutlet weak var lbl_delivery_address: UILabel!
    @IBOutlet weak var lbl_delivery_address_title: UILabel!

    
    // MARK: - Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupContent()
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

    
    func setNavigation() {
        //SET NAVIGATION BAR
        setNavigationBarForButtons(controller: self, title: str.strCustomerDetails, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: [] , isFilter: false) {
            setupKeyboard(true)

            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in  }
    }
    
    
    func setupContent() {
        
        let strUniqueID = (customer?.unique_id ?? "") == "" ? "N/A" : customer?.unique_id ?? ""
        let strName = (customer?.full_name ?? "").trimmed == "" ? "N/A" : customer?.full_name ?? ""
        let strEmail = (customer?.email ?? "").trimmed == "" ? "N/A" : customer?.email ?? ""
        let strPhone = (customer?.phone ?? "").trimmed == "" ? "N/A" : customer?.phone ?? ""
        let strCompanyPhone = (customer?.company_phone ?? "").trimmed == "" ? "N/A" : customer?.company_phone ?? ""
        let strWebsite = (customer?.company_website ?? "").trimmed == "" ? "N/A" : customer?.company_website ?? ""
        let strCompanyName = (customer?.company_name ?? "").trimmed == "" ? "N/A" : customer?.company_name ?? ""
        
        self.lbl_name.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: strName)
        
        self.lbl_account_title.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strAccount)
        self.lbl_account.configureLable(textAlignment: .left, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14, text: strUniqueID)
        
        self.lbl_company_name_title.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strCompanyName)
        self.lbl_company_name.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: strCompanyName)
        
        
        self.lbl_contact_info_title.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strContactInfo)
        
        self.lbl_email_title.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 15, text: str.strEmailAddress)
        self.lbl_email.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: strEmail)
        
        self.lbl_website_title.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 15, text: str.strCompanyWebsite)
        self.lbl_website.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: strWebsite)
        
        self.lbl_phone_title.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 15, text: str.strPersonalPhone)
        self.lbl_phone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: strPhone)
        
        self.lbl_company_phone_title.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 15, text: str.strCompanyPhone)
        self.lbl_company_phone.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: strCompanyPhone)
        
        
        self.lbl_address_info_title.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strAddressInfo)
        
        self.lbl_billing_address_title.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 15, text: str.strBillingAddress)
        self.lbl_billing_address.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "N/A")
        
        self.lbl_delivery_address_title.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 15, text: str.strDeliveryAddress)
        self.lbl_delivery_address.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "N/A")

    }
}

