//
//  LicenseUploadViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 03/02/24.
//

import UIKit
import Nuke
import NukeExtensions

protocol LicenseUploadDelegate : NSObject {
    func linceUploadSucess(selectIndex : Int, arrImage : [String])
}


class LicenseUploadViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: LicenseUploadDelegate?
    
    @IBOutlet weak var imgFront: UIImageView!
    @IBOutlet weak var viewEditFront: UIView!
    @IBOutlet weak var imgBack: UIImageView!
    @IBOutlet weak var viewEditBack: UIView!
    
    @IBOutlet weak var viewFirst: UIView!
    @IBOutlet weak var imgFirst: UIImageView!
    @IBOutlet weak var lblFirst: UILabel!
    @IBOutlet weak var lblFrontImageTitle: UILabel!
    @IBOutlet weak var cons_viewFirst_Width: NSLayoutConstraint!
    @IBOutlet weak var cons_viewFirst_Height: NSLayoutConstraint!
    
    @IBOutlet weak var viewSecond: UIView!
    @IBOutlet weak var imgSecond: UIImageView!
    @IBOutlet weak var lblSecond: UILabel!
    @IBOutlet weak var lblBackImageTitle: UILabel!
    @IBOutlet weak var cons_viewSecond_Width: NSLayoutConstraint!
    @IBOutlet weak var cons_viewSecond_Height: NSLayoutConstraint!
    
    @IBOutlet weak var lblBottomText: UILabel!
    
    @IBOutlet weak var con_Submit: NSLayoutConstraint!
    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!
    
    @IBOutlet weak var con_SubmitAutoInjection: NSLayoutConstraint!
    @IBOutlet weak var viewSubmitAutoInjection: UIView!
    @IBOutlet weak var lblSubmitAutoInjection: UILabel!
    
    private let overlayView = OverlayView()
    let imagePicker = UIImagePickerController()
    
    var selectIndex : Int = -1
    var isSelctFrontImage : Bool = false
    var strOrderID : String = ""
    var arrLicense : [LicenseModel] = []
    /// Sides the employee photographed on this visit — only these (or new license details)
    /// are queued again; reopening and saving never uploads the same license twice.
    var changedSides: Set<String> = []
    /// Sides whose order image (Kabba's copy) actually finished loading on screen — only those
    /// may be re-sent from the screen; a placeholder never is.
    var remoteLoadedSides: Set<String> = []
    private var syncObserver: NSObjectProtocol?

    deinit {
        if let syncObserver = syncObserver { NotificationCenter.default.removeObserver(syncObserver) }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.imagePicker.delegate = self
        
        // Do any additional setup after loading the view.
        
        self.setTheView()

        // The badge follows the copy on this phone: Pending Sync → Synced / Needs Attention.
        syncObserver = NotificationCenter.default.addObserver(forName: .kabbaSyncOperationChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshLicenseStatus()
        }
        
        //GET DATA
//        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(unique_id: self.strOrderID, product_id: ""))

    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true
        
        //SET NAVIGATION BAR
        setNavigationBarFor(controller: self, title: str.strUploadLicense, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)
            
            
        } rightActionHandler: {
            
            
        }
        
    }
    
    func setTheView(){
        
        // Define licence frame
        let width = view.frame.width - 60
        let height: CGFloat = width * 0.6
        self.cons_viewFirst_Width.constant = width
        self.cons_viewFirst_Height.constant = height
        self.cons_viewSecond_Width.constant = width
        self.cons_viewSecond_Height.constant = height        
        
        //SET VIEW
        self.viewFirst.backgroundColor = .clear
        self.viewFirst.viewBorderCorneRadius(borderColour: .secondary)
        self.viewFirst.viewCorneRadius(radius: 5, isRound: false)
        self.viewSecond.backgroundColor = .clear
        self.viewSecond.viewBorderCorneRadius(borderColour: .secondary)
        self.viewSecond.viewCorneRadius(radius: 5, isRound: false)
        self.viewEditFront.isHidden = true
        self.viewEditBack.isHidden = true
        
        //SET IMAGE
        imgColor(imgColor: self.imgFirst, colorHex: .lightGray)
        imgColor(imgColor: self.imgSecond, colorHex: .lightGray)
        
        //SET FONT
        self.lblFrontImageTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16, text: str.strFrontImage)
        self.lblBackImageTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16, text: str.strBackImage)
        
        self.lblBottomText.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: str.strLicenseBottomText)
        
        self.con_Submit.constant = manageWidth(size: 45.0)
        self.viewSubmit.backgroundColor = .secondaryTextView
        self.con_SubmitAutoInjection.constant = manageWidth(size: 45.0)
        self.viewSubmitAutoInjection.backgroundColor = .secondaryTextView
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strSubmitOnly)
        self.lblSubmitAutoInjection.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 15.0, text: str.strSubmitAutoInjection)
        
        self.lblFirst.configureLable(textColor: .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: str.strUplodFirst)
        self.lblSecond.configureLable(textColor: .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: str.strUplodSecod)
        
        //SET IMAGE
        // MOBILE-QUALITY-01 (item 06): with the Sync Engine, the license THIS PHONE saved wins
        // over the order record — an older or empty server copy never hides it — and each side
        // says where it stands (Pending Sync / Needs Attention / Synced), with its expiration.
        if KabbaSync.isReady {
            self.renderSavedLicense()
            return
        }

        let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderID, strType: uploadType.image.rawValue)
        
        if arrData.count != 0 {
            
            //FRONT
            if let indx = arrData.firstIndex(where: { dic_upload in
                return dic_upload.image_side == "front"
            }) {
                if let imgFront = loadImage(fileName: arrData[indx].name ?? "") {
                    self.viewEditFront.isHidden = false
                    self.imgFront.image = imgFront
                    self.imgFront.backgroundColor = .white
                }
            }
            else {
                if arrData.count != 0 {
                    if let imgFront = loadImage(fileName: arrData[0].name ?? "") {
                        self.viewEditFront.isHidden = false
                        self.imgFront.image = imgFront
                        self.imgFront.backgroundColor = .white
                    }
                }
            }
            
            //BACK
            if let indx = arrData.firstIndex(where: { dic_upload in
                return dic_upload.image_side == "back"
            }) {
                if let imgBack = loadImage(fileName: arrData[indx].name ?? ""){
                    self.viewEditBack.isHidden = false
                    self.imgBack.image = imgBack
                    self.imgBack.backgroundColor = .white
                }
            }
            else {
                if arrData.count > 1 {
                    if let imgBack = loadImage(fileName: arrData[1].name ?? ""){
                        self.viewEditBack.isHidden = false
                        self.imgBack.image = imgBack
                        self.imgBack.backgroundColor = .white
                    }
                }
            }
    
        }
        else if self.arrLicense.count != 0 {
            
            // FRONT
            if let front = arrLicense.first(where: { $0.side?.lowercased() == "front" }),
               let url = front.media_url {
                
                viewEditFront.isHidden = false
                imgFront.setImageURL(strImg: url)
                imgFront.backgroundColor = .white
            }
            else {
                if self.arrLicense.count != 0 {
                    viewEditFront.isHidden = false
                    imgFront.setImageURL(strImg: self.arrLicense[0].media_url ?? "")
                    imgFront.backgroundColor = .white
                }
            }

            // BACK
            if let back = arrLicense.first(where: { $0.side?.lowercased() == "back" }),
               let url = back.media_url {
                
                viewEditBack.isHidden = false
                imgBack.setImageURL(strImg: url)
                imgBack.backgroundColor = .white
            }
            else {
                if self.arrLicense.count > 1 {
                    viewEditBack.isHidden = false
                    imgBack.setImageURL(strImg: self.arrLicense[1].media_url ?? "")
                    imgBack.backgroundColor = .white
                }
            }
        }
    }
}



//MARK: - BUTTON ACTION
extension LicenseUploadViewController {
    @IBAction func btn1FrontClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        self.isSelctFrontImage = true
        self.openImagePicker(senderr: sender, type: str.strUploadFrontImage)

    }
    
    @IBAction func btn1BackClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        self.isSelctFrontImage = false
        self.openImagePicker(senderr: sender, type: str.strUploadBackImage)
    }
    
    
    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if self.imgFront.image == nil{
            showAlertMessage(strMessage: "Please upload the front of your license.")
        }
        else if self.imgBack.image == nil{
            showAlertMessage(strMessage: "Please upload the back of your license.")
        }
        else if KabbaSync.isReady {
            // Phase 4: each side lives in the Sync Engine's protected storage as a durable
            // license_media.upload operation (stable client ids, replayed by Kabba, removed from
            // the phone only after acceptance). MOBILE-QUALITY-01 (item 06): only a side that
            // changed is queued; a waiting copy is replaced, never uploaded twice.
            let save: KabbaMediaSync.LicenseSave
            do {
                save = try KabbaMediaSync.saveLicense(orderUniqueId: self.strOrderID, changedSides: self.changedSides,
                                                      trustedImageSides: self.remoteLoadedSides) { side in
                    (side == "front" ? self.imgFront.image : self.imgBack.image)?.jpegData(compressionQuality: 0.25)
                }
            } catch {
                // Not on the phone: say so and stay — never a success message, never navigation.
                showAlertMessage(strMessage: KabbaMediaSync.licenseSaveFailureMessage(error))
                return
            }
            self.changedSides = []
            self.delegate?.linceUploadSucess(selectIndex: self.selectIndex, arrImage: [])
            // Non-blocking (~1 s, no button) and straight back to Order Details — no alert to
            // dismiss, nothing for a pop to race with. Sync continues on its own.
            KabbaSync.confirmSavedOnPhone(KabbaMediaSync.licenseSavedMessage(save)) { self.routeAfterSave() }
        }
        else{
            //CALL API
            if self.saveImage(image: self.imgFront.image ?? UIImage(), orderID: self.strOrderID, imgName: "front"){
                print("save")
                
                if self.saveImage(image: self.imgBack.image ?? UIImage(), orderID: self.strOrderID, imgName: "back"){
                    
                    let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderID, strType: uploadType.image.rawValue)
                    if arrData.count != 0{
                        CoreDBManager.sharedDatabase.deleteUploadData(strOrderID: self.strOrderID, strType: uploadType.image.rawValue) { isSave in
                            self.setLicenseData()
                        }
                    }
                    else{
                        self.setLicenseData()
                
                    }
                }
            }
        }
    }
    
    @IBAction func btnSubmitAutoInjectionClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if self.imgFront.image == nil{
            showAlertMessage(strMessage: "Please upload the front of your license.")
        }
        else if self.imgBack.image == nil{
            showAlertMessage(strMessage: "Please upload the back of your license.")
        }
        else {
            
            //MOVE AUTO INJECTION SCREEN
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "LicenseTypeViewController") as? LicenseTypeViewController {
                newViewController.strOrderID = self.strOrderID
                newViewController.selectIndex = self.selectIndex
                newViewController.imgFront = self.imgFront.image ?? UIImage()
                newViewController.imgBack = self.imgBack.image ?? UIImage()
                newViewController.changedSides = self.changedSides
                newViewController.trustedImageSides = self.remoteLoadedSides
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
    }
    
    func setLicenseData(){
        //SAVE IN DATA BASE
        CoreDBManager.sharedDatabase.saveUploadDataList(objSaveData: SaveImageVideoParameater(orderID: self.strOrderID, type: uploadType.image.rawValue, isImage: true, name: "\(self.strOrderID)_front.png", image_side: "front")) { isSave in
            if isSave{
                CoreDBManager.sharedDatabase.saveUploadDataList(objSaveData: SaveImageVideoParameater(orderID: self.strOrderID, type: uploadType.image.rawValue, isImage: true, name: "\(self.strOrderID)_back.png", image_side: "back")) { isSave in
                    if isSave{
                        
                        showAlertMessage(strMessage: "License updated successfully.")
                        
                        self.delegate?.linceUploadSucess(selectIndex: self.selectIndex, arrImage: [])
                        
                        //UPLOAD LOCAL DATA
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0){
                            GlobalMainConstants.appDelegate?.uploadAllData()
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                            self.routeAfterSave()
                        }
                    }
                }
            }
        }
    }
    
    
    func saveImage(image: UIImage, orderID : String, imgName : String) -> Bool {
        // Compress (was quality 1 / raw PNG — multi-MB per license side). Matches the other upload paths.
        guard let data = image.jpegData(compressionQuality: 0.25) ?? image.pngData() else {
            return false
        }
      
        do {
            // Driver's-license images are sensitive PII — encrypt at rest. UntilFirstUserAuthentication
            // keeps them readable by background uploads after the device's first unlock.
            try data.write(to: LicenseUploadDirectory.appendingPathComponent("\(orderID)_\(imgName).png"),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            print(error.localizedDescription)
            return false
        }
    }
}



//MARK: - UIImagePicker View Delegate Datasource method

extension LicenseUploadViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate, CameraViewControllerDelegate {

    func openImagePicker(senderr: UIButton, type: String) {
        let cameraVC = CameraViewController()
        cameraVC.delegate = self
        cameraVC.strTitle = type
        cameraVC.modalPresentationStyle = .fullScreen
        GlobalMainConstants.appDelegate?.window?.rootViewController?.present(cameraVC, animated: true, completion: nil)
        
//        let imageAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
//        
//      
//        let Capture = UIAlertAction.init(title: "Take Photo", style: .default, handler: { (action) in
//            
//            if(UIImagePickerController .isSourceTypeAvailable(UIImagePickerController.SourceType.camera)) {
//                
//                let cameraVC = CameraViewController()
//                cameraVC.delegate = self
//                cameraVC.strTitle = type
//                cameraVC.modalPresentationStyle = .fullScreen
//                GlobalMainConstants.appDelegate?.window?.rootViewController?.present(cameraVC, animated: true, completion: nil)
//                
//                /*
//                self.imagePicker.sourceType = .camera
//                self.imagePicker.cameraDevice = .rear
//                self.imagePicker.showsCameraControls = true
//                self.imagePicker.allowsEditing = true
//                
//                GlobalMainConstants.appDelegate?.window?.rootViewController?.present(self.imagePicker, animated: true, completion: nil)
//                */
//            }
//            else{
//                showAlertMessage(strMessage: str.notSupportCamera)
//            }
//        })
//        
//        let chosefromlib = UIAlertAction.init(title: "Choose Photo", style: .default, handler: { (action) in
//            
//            self.imagePicker.sourceType = .photoLibrary
//            self.imagePicker.allowsEditing = true
//            GlobalMainConstants.appDelegate?.window?.rootViewController?.present(self.imagePicker, animated: true, completion: nil)
//        })
//        
//        
//        let cancel = UIAlertAction.init(title: "Cancel", style: .destructive, handler: { (action) in
//            
//            imageAlert.dismiss(animated: true, completion: nil)
//        })
//        
//        
//        imageAlert.addAction(Capture)
//        imageAlert.addAction(chosefromlib)
//        imageAlert.addAction(cancel)
//        
//        if let presenter = imageAlert.popoverPresentationController {
//            presenter.sourceView = senderr
//            presenter.sourceRect = senderr.frame
//        }
//        self.present(imageAlert, animated: true, completion: nil)
    }
    
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true) {
            if let PickedImage: UIImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {
                DispatchQueue.main.async {

                    if self.isSelctFrontImage{
                        self.imgFront.backgroundColor = .primary
                        self.imgFront.image = PickedImage
                        self.viewEditFront.isHidden = false
                        self.changedSides.insert("front")
                        self.setLicenseBadge(nil, on: self.imgFront)

                    }
                    else{
                        self.imgBack.backgroundColor = .primary
                        self.imgBack.image = PickedImage
                        self.viewEditBack.isHidden = false
                        self.changedSides.insert("back")
                        self.setLicenseBadge(nil, on: self.imgBack)

                    }
                }
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) {
        }
    }
    
    func didCaptureImage(_ image: UIImage) {
        debugPrint(image)
        DispatchQueue.main.async {
            if self.isSelctFrontImage{
                self.imgFront.backgroundColor = .primary
                self.imgFront.image = image
                self.viewEditFront.isHidden = false
                self.changedSides.insert("front")
                self.setLicenseBadge(nil, on: self.imgFront)
            }
            else{
                self.imgBack.backgroundColor = .primary
                self.imgBack.image = image
                self.viewEditBack.isHidden = false
                self.changedSides.insert("back")
                self.setLicenseBadge(nil, on: self.imgBack)
            }
        }
    }
    
    func didCancel() {
        debugPrint("Cancel Clicked")
    }
}


func loadImage(fileName: String) -> UIImage? {
    let fileURL = LicenseUploadDirectory.appendingPathComponent(fileName)
    do {
        let imageData = try Data(contentsOf: fileURL)
        return UIImage(data: imageData)
    } catch {
        print("Error loading image : \(error)")
    }
    return nil
}

func loadImagefromImageVideoDirectory(fileName: String) -> UIImage? {
    let fileURL = ImageVideoUploadDirectory.appendingPathComponent(fileName)
    do {
        let imageData = try Data(contentsOf: fileURL)
        return UIImage(data: imageData)
    } catch {
        print("Error loading image : \(error)")
    }
    return nil
}



func getVideoUrl(fileName: String) -> URL? {
    let fileURL = ImageVideoUploadDirectory.appendingPathComponent(fileName)
    return fileURL
}

// MARK: - Driver Delivery Process Flow (2026-09-27)
extension LicenseUploadViewController {
    /// Add Driver License → Main Order (§10.2): the Order Details that opened it, whatever
    /// lies beneath; a stack without one keeps its old single pop.
    func routeAfterSave() {
        CustomerSiteNavigation.goToMainOrder(on: self.navigationController)
    }
}

// MARK: - The license saved on this phone (MOBILE-QUALITY-01, item 06)
extension LicenseUploadViewController {

    private static let badgeTag = 0x4C1C
    private static let expiryTag = 0x4C2A   // never badgeTag + 0 or + 1 (front / back badges)

    /// Each side: the copy saved on this phone (Pending Sync / Needs Attention — kept for review),
    /// else Kabba's copy of what this phone synced, else the order record. Plus the expiration.
    func renderSavedLicense() {
        let local = KabbaMediaSync.localLicense(orderUniqueId: self.strOrderID)
        for (side, imageView, editView) in [("front", self.imgFront!, self.viewEditFront!), ("back", self.imgBack!, self.viewEditBack!)] {
            if let copy = local[side] {
                var shown = false
                if let data = KabbaMediaSync.licenseImageData(copy), let image = UIImage(data: data) {
                    imageView.image = image
                    shown = true
                } else if let url = serverLicenseURL(side: side) ?? copy.serverMediaURL {
                    // Synced: the order record is Kabba's current license (the office may have
                    // replaced it since); this phone's acknowledgment is only the fallback.
                    loadOrderImage(url, into: imageView, side: side)
                    shown = true
                }
                if shown {
                    editView.isHidden = false
                    imageView.backgroundColor = .white
                }
                setLicenseBadge(copy, on: imageView)
            } else if let url = serverLicenseURL(side: side) {
                editView.isHidden = false
                loadOrderImage(url, into: imageView, side: side)
                imageView.backgroundColor = .white
                setLicenseBadge(nil, on: imageView)
            }
        }
        setExpiry(LocalLicense.displayExpiry(LocalLicense.expiryDate(local)))
    }

    /// Live: the badges follow the sync state without re-entering anything.
    func refreshLicenseStatus() {
        guard isViewLoaded, KabbaSync.isReady else { return }
        let local = KabbaMediaSync.localLicense(orderUniqueId: self.strOrderID)
        for (side, imageView) in [("front", self.imgFront!), ("back", self.imgBack!)] where !changedSides.contains(side) {
            setLicenseBadge(local[side], on: imageView)
        }
        setExpiry(LocalLicense.displayExpiry(LocalLicense.expiryDate(local)))
    }

    /// Loads Kabba's image of a side and records whether it really arrived (the placeholder
    /// shown meanwhile must never be uploaded as the license).
    private func loadOrderImage(_ url: String, into imageView: UIImageView, side: String) {
        remoteLoadedSides.remove(side)
        let encoded = (url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "").replacingOccurrences(of: " ", with: "%20")
        guard let link = URL(string: encoded) else { return }
        NukeExtensions.loadImage(with: imageView.makeRequest(with: link), options: imageView.makeImageLoadingOptions(), into: imageView) { [weak self] result in
            if case .success = result, self?.changedSides.contains(side) == false { self?.remoteLoadedSides.insert(side) }
        }
    }

    private func serverLicenseURL(side: String) -> String? {
        let match = arrLicense.first(where: { $0.side?.lowercased() == side })
            ?? (side == "front" ? arrLicense.first : (arrLicense.count > 1 ? arrLicense[1] : nil))
        guard let url = match?.media_url, !url.isEmpty else { return nil }
        return url
    }

    func setLicenseBadge(_ copy: LocalLicenseSide?, on imageView: UIImageView) {
        let host = imageView.superview ?? imageView
        let label = (host.viewWithTag(Self.badgeTag + (imageView === imgFront ? 0 : 1)) as? UILabel) ?? {
            let l = LicenseBadgeLabel()
            l.tag = Self.badgeTag + (imageView === imgFront ? 0 : 1)
            l.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 12)
            l.textColor = .white
            l.layer.cornerRadius = 6
            l.layer.masksToBounds = true
            l.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(l)
            NSLayoutConstraint.activate([
                l.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 6),
                l.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -6),
            ])
            return l
        }()
        guard let copy = copy, !copy.statusLabel.isEmpty else {
            label.isHidden = true
            return
        }
        label.text = copy.statusLabel
        label.accessibilityIdentifier = "license.status.\(copy.side)"
        label.accessibilityLabel = "\(copy.side.capitalized) image: \(copy.statusLabel)"
        switch copy.state {
        case .needsAttention: label.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.92)
        case .synced:         label.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.92)
        default:              label.backgroundColor = UIColor.secondary.withAlphaComponent(0.92)
        }
        label.isHidden = false
        host.bringSubviewToFront(label)
    }

    private func setExpiry(_ text: String?) {
        guard let imageView = self.imgBack else { return }
        let host = imageView.superview ?? imageView
        let label = (host.viewWithTag(Self.expiryTag) as? UILabel) ?? {
            let l = LicenseBadgeLabel()
            l.tag = Self.expiryTag
            l.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 12)
            l.textColor = .white
            l.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            l.layer.cornerRadius = 6
            l.layer.masksToBounds = true
            l.accessibilityIdentifier = "license.expiry"
            l.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(l)
            NSLayoutConstraint.activate([
                l.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -6),
                l.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 6),
            ])
            return l
        }()
        label.text = text.map { "Expires \($0)" }
        label.isHidden = text == nil
        host.bringSubviewToFront(label)
    }
}

/// A label with a little room around its text (status badges over the license images).
private final class LicenseBadgeLabel: UILabel {
    var insets = UIEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
