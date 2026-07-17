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

class CRMListDetailViewController: UIViewController, UIGestureRecognizerDelegate, AddNoteDelegate {
    
    // MARK: - Properties

    var customer: CustomerModel?

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
    @IBOutlet weak var constraint_viewAddress_top: NSLayoutConstraint!

    // Tags pills container (added programmatically below Contact Info)
    private var tagsContainerView: UIView?
    private var notesSectionView: UIView?
    private var ordersSectionView: UIView?

    // MARK: - Life Cycle

    private var dynamicSectionsAdded = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !dynamicSectionsAdded {
            dynamicSectionsAdded = true
            setupTagsPills()      // Tags below Contact Info
            setupNotesSection()  // Notes below Address Info
            setupOrdersSection() // Orders below Notes
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

    
    func setNavigation() {
        //SET NAVIGATION BAR
        setNavigationBarForButtons(controller: self, title: str.strCustomerDetails, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: [] , isFilter: false) {
            setupKeyboard(true)

            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in  }
    }
    
    
    func setupContent() {
        
        //let strUniqueID = (customer?.unique_id ?? "") == "" ? "N/A" : customer?.unique_id ?? ""
        let strName = (customer?.full_name ?? "").trimmed == "" ? "N/A" : customer?.full_name ?? ""
        //let strEmail = (customer?.email ?? "").trimmed == "" ? "N/A" : customer?.email ?? ""
        let strPhone = (customer?.phone ?? "").trimmed == "" ? "N/A" : customer?.phone ?? ""
        let strCompanyPhone = (customer?.company_phone ?? "").trimmed == "" ? "N/A" : customer?.company_phone ?? ""
        //let strWebsite = (customer?.company_website ?? "").trimmed == "" ? "N/A" : customer?.company_website ?? ""
        let strCompanyName = (customer?.company_name ?? "").trimmed == "" ? "N/A" : customer?.company_name ?? ""
        var strBillingAddress = (customer?.objBillingAddress?.full_address ?? "").trimmed == "" ? "N/A" : customer?.objBillingAddress?.full_address ?? ""
        var strDeliveryAddress = (customer?.objDeliveryAddress?.full_address ?? "").trimmed == "" ? "N/A" : customer?.objDeliveryAddress?.full_address ?? ""
        
        let strBilling = strBillingAddress.replacingOccurrences(of: ",", with: "")
        strBillingAddress = strBilling.trimmed == "" ? "N/A" : strBillingAddress
        
        let strDelivery = strDeliveryAddress.replacingOccurrences(of: ",", with: "")
        strDeliveryAddress = strDelivery.trimmed == "" ? "N/A" : strDeliveryAddress
        
        self.lbl_contact_info_title.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strContactInfo)

        // Row 1: Name | Personal Phone
        self.lbl_phone_title.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 15, text: strName)
        self.lbl_phone.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 15, text: strPhone)

        // Row 2: Company Name | Company Phone
        self.lbl_company_phone_title.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 15, text: strCompanyName)
        self.lbl_company_phone.configureLable(textAlignment: .right, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 15, text: strCompanyPhone)

        self.lbl_address_info_title.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strAddressInfo)
        
        self.lbl_billing_address_title.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 15, text: str.strBillingAddress)
        self.lbl_billing_address.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: strBillingAddress)
        
        self.lbl_delivery_address_title.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 15, text: str.strDeliveryAddress)
        self.lbl_delivery_address.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: strDeliveryAddress)
    }

    // MARK: - Tags Pills

    private func setupTagsPills() {
        tagsContainerView?.removeFromSuperview()
        tagsContainerView = nil

        let tags = customer?.arr_tags ?? []
        guard let contactInfoView = lbl_contact_info_title.superview?.superview else { return }
        guard let addressView = lbl_address_info_title.superview?.superview else { return }
        guard let footerView = contactInfoView.superview else { return }

        // Force layout so frames are accurate
        footerView.layoutIfNeeded()

        let leftMargin: CGFloat = 16
        let rightMargin: CGFloat = 16
        let contentWidth = footerView.bounds.width - leftMargin - rightMargin
        var insertY = contactInfoView.frame.maxY + 16

        if !tags.isEmpty {
            // --- "Tags" title ---
            let titleHeight: CGFloat = 22
            let titleLabel = UILabel(frame: CGRect(x: leftMargin, y: insertY, width: contentWidth, height: titleHeight))
            titleLabel.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16, text: str.strTags)
            footerView.addSubview(titleLabel)
            insertY += titleHeight + 10

            // --- Pills ---
            let pillHeight: CGFloat = 30
            let hSpacing: CGFloat = 8
            let vSpacing: CGFloat = 8
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0

            let pillsContainer = UIView(frame: .zero)
            pillsContainer.backgroundColor = .clear

            for tag in tags {
                let tagName = tag.name ?? ""
                guard !tagName.isEmpty else { continue }
                let pill = makePillLabel(text: tagName)
                let pillWidth = min(pill.intrinsicContentSize.width + 24, contentWidth)
                if currentX + pillWidth > contentWidth && currentX > 0 {
                    currentX = 0
                    currentY += pillHeight + vSpacing
                }
                pill.frame = CGRect(x: currentX, y: currentY, width: pillWidth, height: pillHeight)
                pillsContainer.addSubview(pill)
                currentX += pillWidth + hSpacing
            }

            let pillsHeight = currentY + pillHeight
            pillsContainer.frame = CGRect(x: leftMargin, y: insertY, width: contentWidth, height: pillsHeight)
            footerView.addSubview(pillsContainer)
            insertY += pillsHeight + 16

            // Store wrapper (title + pills) for cleanup on next call
            let wrapper = UIView(frame: CGRect(x: 0, y: contactInfoView.frame.maxY, width: footerView.bounds.width, height: insertY - contactInfoView.frame.maxY))
            wrapper.backgroundColor = .clear
            wrapper.isUserInteractionEnabled = false
            footerView.addSubview(wrapper)
            tagsContainerView = wrapper
            self.constraint_viewAddress_top.constant = wrapper.frame.size.height
        }

        // Position Address Information section below tags (or contact info if no tags)
        var addressFrame = addressView.frame
        addressFrame.origin.y = insertY
        addressView.frame = addressFrame

        // Resize footer to fit all content
        let totalHeight = insertY + addressView.frame.height + 16
        var footerFrame = footerView.frame
        footerFrame.size.height = totalHeight
        footerView.frame = footerFrame

        // Refresh tableView footer
        if let tableView = footerView.superview as? UITableView {
            tableView.tableFooterView = footerView
        }
    }

    // MARK: - Notes Section

    private func setupNotesSection() {
        notesSectionView?.removeFromSuperview()
        notesSectionView = nil

        // Address Info: lbl_address_info_title → rAc-sp-OZG → MPa-Bq-PJ6
        guard let addressView = lbl_address_info_title.superview?.superview else { return }
        guard let footerView = addressView.superview else { return }

        // Force layout so addressView.frame is up to date
        footerView.layoutIfNeeded()

        let leftMargin: CGFloat = 16
        let rightMargin: CGFloat = 16
        let contentWidth = footerView.bounds.width - leftMargin - rightMargin
        var insertY = addressView.frame.maxY + 20

        let notes = (customer?.arr_notes ?? []).reversed()

        // ── Separator line ──
        let separator = UIView(frame: CGRect(x: leftMargin - 4, y: insertY, width: footerView.bounds.width - 24, height: 1))
        separator.backgroundColor = UIColor.secondary.withAlphaComponent(0.3)
        footerView.addSubview(separator)
        insertY += 1 + 16

        // ── Header: "Notes" (left) | "+ Add Notes" (right) ──
        let headerHeight: CGFloat = 24

        let notesTitle = UILabel(frame: CGRect(x: leftMargin, y: insertY, width: contentWidth * 0.5, height: headerHeight))
        notesTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.strNotes)
        footerView.addSubview(notesTitle)

        let addBtn = UIButton(type: .system)
        addBtn.configureLable(bgColour: .clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 15, text: "+ \(str.strAddNoteBtn)")
        addBtn.frame = CGRect(x: leftMargin + contentWidth * 0.5, y: insertY, width: contentWidth * 0.5, height: headerHeight)
        addBtn.contentHorizontalAlignment = .right
        addBtn.addTarget(self, action: #selector(addNotesTapped), for: .touchUpInside)
        footerView.addSubview(addBtn)

        insertY += headerHeight + 12

        // ── Notes list ──
        if notes.isEmpty {
            let emptyLabel = UILabel(frame: CGRect(x: leftMargin, y: insertY, width: contentWidth, height: 20))
            emptyLabel.configureLable(textColor: .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: str.strNoNoteAvailable)
            footerView.addSubview(emptyLabel)
            insertY += 20
        } else {
            for note in notes {
                let noteDesc = note.description ?? ""
                let noteMeta = "\(note.created_date ?? "") - \(note.created_time ?? "") by \(note.created_by ?? "")"

                // Bullet dot
                let bullet = UIView(frame: CGRect(x: leftMargin, y: insertY + 8, width: 7, height: 7))
                bullet.backgroundColor = .secondary
                bullet.layer.cornerRadius = 3.5
                footerView.addSubview(bullet)

                // Note description
                let descLabel = UILabel()
                descLabel.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 15, text: noteDesc)
                descLabel.numberOfLines = 0
                let descWidth = contentWidth - 15 - 8  // bullet(7) + gap(8)
                let descSize = descLabel.sizeThatFits(CGSize(width: descWidth, height: .greatestFiniteMagnitude))
                descLabel.frame = CGRect(x: leftMargin + 15, y: insertY, width: descWidth, height: descSize.height)
                footerView.addSubview(descLabel)

                // Meta (created by / date)
                let metaLabel = UILabel()
                metaLabel.configureLable(textColor: .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Light, fontSize: 12, text: noteMeta)
                metaLabel.numberOfLines = 2
                let metaSize = metaLabel.sizeThatFits(CGSize(width: descWidth, height: .greatestFiniteMagnitude))
                metaLabel.frame = CGRect(x: leftMargin + 15, y: insertY + descSize.height + 4, width: descWidth, height: metaSize.height)
                footerView.addSubview(metaLabel)

                insertY += descSize.height + metaSize.height + 8

                // Divider
                let div = UIView(frame: CGRect(x: leftMargin, y: insertY + 4, width: contentWidth, height: 0.5))
                div.backgroundColor = UIColor.separator
                footerView.addSubview(div)
                insertY += 14
            }
        }

        insertY += 16

        // Keep track of all added views via a container tag
        let wrapper = UIView(frame: CGRect(x: 0, y: addressView.frame.maxY, width: footerView.bounds.width, height: insertY - addressView.frame.maxY))
        wrapper.backgroundColor = .clear
        wrapper.isUserInteractionEnabled = false
        footerView.addSubview(wrapper)
        notesSectionView = wrapper

        // Resize footer to fit everything
        var footerFrame = footerView.frame
        footerFrame.size.height = insertY
        footerView.frame = footerFrame

        if let tableView = footerView.superview as? UITableView {
            tableView.tableFooterView = footerView
        }
    }

    @objc private func addNotesTapped() {
        guard let window = UIApplication.shared.windows.first else { return }
        let arrUserList = SDKUserDefault.getMappableArray(UserListModel.self, for: kFileStorageName.kOrderDetailUserData.rawValue) ?? []
        let alertView = AddNoteView(frame: CGRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height))
        alertView.loadPopUpView(strOrderID: customer?.unique_id ?? "", strNote: "", arr: arrUserList)
        alertView.delegate = self
        window.addSubview(alertView)
    }

    // MARK: - Orders Section

    private func setupOrdersSection() {
        ordersSectionView?.removeFromSuperview()
        ordersSectionView = nil

        guard let addressView = lbl_address_info_title.superview?.superview else { return }
        guard let footerView = addressView.superview else { return }

        footerView.layoutIfNeeded()

        let leftMargin: CGFloat = 16
        let contentWidth = footerView.bounds.width - leftMargin - 16

        // Start below whatever footer height is now (Notes section already expanded it)
        var insertY = footerView.frame.height

        // ── Separator line ──
        let separator = UIView(frame: CGRect(x: leftMargin - 4, y: insertY, width: footerView.bounds.width - 24, height: 1))
        separator.backgroundColor = UIColor.secondary.withAlphaComponent(0.3)
        footerView.addSubview(separator)
        insertY += 1 + 16

        // ── Header: "Orders" title ──
        let headerHeight: CGFloat = 24
        let ordersTitle = UILabel(frame: CGRect(x: leftMargin, y: insertY, width: contentWidth, height: headerHeight))
        ordersTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: "Orders")
        footerView.addSubview(ordersTitle)
        insertY += headerHeight + 12

        // ── Empty state (no API data yet) ──
        let emptyLabel = UILabel(frame: CGRect(x: leftMargin, y: insertY, width: contentWidth, height: 20))
        emptyLabel.configureLable(textColor: .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14, text: "No Orders Found")
        footerView.addSubview(emptyLabel)
        insertY += 20 + 16

        // Track wrapper
        let wrapper = UIView(frame: CGRect(x: 0, y: footerView.frame.height, width: footerView.bounds.width, height: insertY - footerView.frame.height))
        wrapper.backgroundColor = .clear
        wrapper.isUserInteractionEnabled = false
        footerView.addSubview(wrapper)
        ordersSectionView = wrapper

        // Resize footer
        var footerFrame = footerView.frame
        footerFrame.size.height = insertY
        footerView.frame = footerFrame

        if let tableView = footerView.superview as? UITableView {
            tableView.tableFooterView = footerView
        }
    }

    private func makePillLabel(text: String) -> UILabel {
        let label = UILabel()
        label.configureLable(textAlignment: .center, textColor: .secondary, fontName:  GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 13, text: text)
        label.backgroundColor = UIColor.secondary.withAlphaComponent(0.15)
        label.layer.cornerRadius = 15
        label.layer.borderWidth = 1
        label.layer.borderColor = UIColor.secondary.withAlphaComponent(0.4).cgColor
        label.clipsToBounds = true
        return label
    }
    
    
    func strAddNote(strNote: String) {
        print("Notes:====>>\(strNote)")
    }
    
    func updateDataNoInternetCase(note_dic: OrderNoteModel?, for_delete: Bool) {
    }
}

