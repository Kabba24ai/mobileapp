//
//  LicenseUploadViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 03/02/24.
//

import UIKit

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
    
    @IBOutlet weak var viewSecond: UIView!
    @IBOutlet weak var imgSecond: UIImageView!
    @IBOutlet weak var lblSecond: UILabel!
    
    @IBOutlet weak var con_Submit: NSLayoutConstraint!
    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!
    
    let imagePicker = UIImagePickerController()
    
    var selectIndex : Int = -1
    var isSelctFrontImage : Bool = false
    var strOrderID : String = ""
    var arrLicense : [String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.imagePicker.delegate = self

        // Do any additional setup after loading the view.
        
        //SET  VIEW
        self.setTheView()

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
        setNavigationBarFor(controller: self, title: "License Upload", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)
            
            
        } rightActionHandler: {
            
            
        }
    }
    
    func setTheView(){
        
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
        self.con_Submit.constant = manageWidth(size: 45.0)
        self.viewSubmit.backgroundColor = .secondaryTextView
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strSubmit)
        
        self.lblFirst.configureLable(textColor: .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: str.strUplodFirst)
        self.lblSecond.configureLable(textColor: .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: str.strUplodSecod)
        
        //SET IMAGE
        if self.arrLicense.count != 0{
            //FRONT
            if self.arrLicense.count > 0{
                self.viewEditFront.isHidden = false
                self.imgFront.setImageURL(strImg: self.arrLicense[0] )
                self.imgFront.backgroundColor = .white
            }
            
            //BACK
            if self.arrLicense.count > 1{
                self.viewEditBack.isHidden = false
                self.imgBack.setImageURL(strImg: self.arrLicense[1] )
                self.imgBack.backgroundColor = .white
            }
        }
    }
}

//MARK: - BUTTON ACTION
extension LicenseUploadViewController {
    @IBAction func btn1FrontClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        self.isSelctFrontImage = true
        self.openImagePicker(senderr: sender)

    }
    
    @IBAction func btn1BackClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        self.isSelctFrontImage = false
        self.openImagePicker(senderr: sender)
    }
    
    
    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if self.imgFront.image == nil{
            showAlertMessage(strMessage: "Please upload license front")
        }
        else if self.imgBack.image == nil{
            showAlertMessage(strMessage: "Please upload license back")
        }
        else{
            //CALL API
            
//            if self.saveImage(image: self.imgFront.image ?? UIImage(), orderID: self.strOrderID, imgName: "front"){
//                print("save")
//                
//                if self.saveImage(image: self.imgBack.image ?? UIImage(), orderID: self.strOrderID, imgName: "back"){
//                 
////                    showAlertMessage(strMessage: "Upload license update successfully")
////                    self.delegate?.linceUploadSucess(selectIndex: self.selectIndex, arrImage: dicData)
////
////                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
////                        self.navigationController?.popViewController(animated: true)
////                    }
//
//                }
//            }
            callLicenseUploadAPI(LicenseParameater: LicenseParameater(order_id: self.strOrderID))
        }
    }
    
    
    func saveImage(image: UIImage, orderID : String, imgName : String) -> Bool {
        guard let data = image.jpegData(compressionQuality: 1) ?? image.pngData() else {
            return false
        }
      
        do {
            try data.write(to: LicenseUploadDirectory.appendingPathComponent("\(orderID)_\(imgName).png"))
            return true
        } catch {
            print(error.localizedDescription)
            return false
        }
    }
}



//MARK: - UIImagePicker View Delegate Datasource method

extension LicenseUploadViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func openImagePicker(senderr: UIButton) {
        
        let imageAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        
      
        let Capture = UIAlertAction.init(title: "Take Photo", style: .default, handler: { (action) in
            
            if(UIImagePickerController .isSourceTypeAvailable(UIImagePickerController.SourceType.camera)) {
                self.imagePicker.sourceType = .camera
                self.imagePicker.cameraDevice = .rear
                self.imagePicker.showsCameraControls = true
                self.imagePicker.allowsEditing = true
                
                GlobalMainConstants.appDelegate?.window?.rootViewController?.present(self.imagePicker, animated: true, completion: nil)
            }
            else{
                showAlertMessage(strMessage: str.notSupportCamera)
            }
        })
        
        let chosefromlib = UIAlertAction.init(title: "Choose Photo", style: .default, handler: { (action) in
            
            self.imagePicker.sourceType = .photoLibrary
            self.imagePicker.allowsEditing = true
            GlobalMainConstants.appDelegate?.window?.rootViewController?.present(self.imagePicker, animated: true, completion: nil)
        })
        
        
        let cancel = UIAlertAction.init(title: "Cancel", style: .destructive, handler: { (action) in
            
            imageAlert.dismiss(animated: true, completion: nil)
        })
        
        
        imageAlert.addAction(Capture)
        imageAlert.addAction(chosefromlib)
        imageAlert.addAction(cancel)
        
        if let presenter = imageAlert.popoverPresentationController {
            presenter.sourceView = senderr
            presenter.sourceRect = senderr.frame
        }
        self.present(imageAlert, animated: true, completion: nil)
    }
    
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true) {
            if let PickedImage: UIImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {
                DispatchQueue.main.async {

                    if self.isSelctFrontImage{
                        self.imgFront.backgroundColor = .primary
                        self.imgFront.image = PickedImage
                        self.viewEditFront.isHidden = false

                    }
                    else{
                        self.imgBack.backgroundColor = .primary
                        self.imgBack.image = PickedImage
                        self.viewEditBack.isHidden = false

                    }
                }
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) {
        }
    }
}

