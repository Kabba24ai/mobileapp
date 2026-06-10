//
//  EPSignatureViewController.swift
//  Pods
//
//  Created by Prabaharan Elangovan on 13/01/16.
//
//

import UIKit

    // MARK: - EPSignatureDelegate
@objc public protocol EPSignatureDelegate {
    @objc optional    func epSignature(_: EPSignatureViewController, didCancel error : NSError)
    @objc optional    func epSignature(_: EPSignatureViewController, didSign signatureImage : UIImage, boundingRect: CGRect, strIndex : Int)
}

open class EPSignatureViewController: UIViewController {

    // MARK: - IBOutlets
    @IBOutlet weak var signatureView: EPSignatureView!
    
    // MARK: - Public Vars
    
    open var showsDate: Bool = true
    open var showsSaveSignatureOption: Bool = true
    open weak var signatureDelegate: EPSignatureDelegate?
    open var titleText : String = ""
    open var strIndex : Int = 0
    open var subtitleText = "Sign Here"
    open var tintColor = UIColor.background

    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!
    @IBOutlet weak var lblTitle: UILabel!
    @IBOutlet weak var lblDetails: UILabel!
    @IBOutlet weak var con_Submit: NSLayoutConstraint!

    @IBOutlet weak var btnCancel: UIButton!
    @IBOutlet weak var btnClear: UIButton!

    
    // MARK: - Life cycle methods
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        //SET PORTRAIT MODE
        AppUtility.lockOrientation(.landscape)
        let value = UIInterfaceOrientation.portrait.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")

//        let cancelButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.cancel, target: self, action: #selector(EPSignatureViewController.onTouchCancelButton))
//        cancelButton.tintColor = tintColor
//        self.navigationItem.leftBarButtonItem = cancelButton
//        
//        let clearButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.done, target: self, action: #selector(EPSignatureViewController.onTouchClearButton))
//        clearButton.tintColor = tintColor
//        self.navigationItem.rightBarButtonItem = clearButton

        //SET VIEW
        self.con_Submit.constant = manageWidth(size: 45.0)
        self.viewSubmit.backgroundColor = .background
        self.lblSubmit.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strSubmit)
        
        
        self.lblTitle.configureLable(textColor: .black, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.titleText)
        self.lblDetails.configureLable(textColor: .lightGray, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: self.subtitleText)


        self.btnCancel.configureLable(bgColour: .clear, textColor: .black, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Cancel")
        self.btnClear.configureLable(bgColour: .clear, textColor: .black, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Clear")
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        
        //SET PORTRAIT MODE
        AppUtility.lockOrientation(.landscape)
        let value = UIInterfaceOrientation.portrait.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")
        
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        self.tabBarController?.tabBar.isHidden = true
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        //SET PORTRAIT MODE
        AppUtility.PortraitMode()
    }
    
    override open func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Initializers
    
    public convenience init(signatureDelegate: EPSignatureDelegate) {
        self.init(signatureDelegate: signatureDelegate, showsDate: true, showsSaveSignatureOption: true)
    }
    
    public convenience init(signatureDelegate: EPSignatureDelegate, showsDate: Bool) {
        self.init(signatureDelegate: signatureDelegate, showsDate: showsDate, showsSaveSignatureOption: true)
    }
    
    public init(signatureDelegate: EPSignatureDelegate, showsDate: Bool, showsSaveSignatureOption: Bool ) {
        self.showsDate = showsDate
        self.showsSaveSignatureOption = showsSaveSignatureOption
        self.signatureDelegate = signatureDelegate
        let bundle = Bundle(for: EPSignatureViewController.self)
        super.init(nibName: "EPSignatureViewController", bundle: bundle)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        if let signature = signatureView.getSignatureAsImage() {
            signatureDelegate?.epSignature!(self, didSign: signature, boundingRect: signatureView.getSignatureBoundsInCanvas(), strIndex: self.strIndex)
            dismiss(animated: true, completion: nil)
        } else {
            showAlert("You have not signed.", andTitle: "Please draw your signature")
        }
    }
    
    // MARK: - Button Actions
    
    @IBAction func onTouchCancelButton() {
        signatureDelegate?.epSignature!(self, didCancel: NSError(domain: "EPSignatureDomain", code: 1, userInfo: [NSLocalizedDescriptionKey:"User not signed"]))
        dismiss(animated: true, completion: nil)
    }

    @objc func onTouchDoneButton() {
        if let signature = signatureView.getSignatureAsImage() {
            signatureDelegate?.epSignature!(self, didSign: signature, boundingRect: signatureView.getSignatureBoundsInCanvas(), strIndex: self.strIndex)
            dismiss(animated: true, completion: nil)
        } else {
            showAlert("You have not signed.", andTitle: "Please draw your signature")
        }
    }
    
    @objc func onTouchActionButton(_ barButton: UIBarButtonItem) {
        let action = UIAlertController(title: "Action", message: "", preferredStyle: UIAlertController.Style.actionSheet)
        action.view.tintColor = tintColor
        
        action.addAction(UIAlertAction(title: "Load default signature", style: UIAlertAction.Style.default, handler: { action in
            let docPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first
            let filePath = (docPath! as NSString).appendingPathComponent("sig.data")
            self.signatureView.loadSignature(filePath)
        }))
        
        action.addAction(UIAlertAction(title: "Delete default signature", style: UIAlertAction.Style.destructive, handler: { action in
            self.signatureView.removeSignature()
        }))
        
        action.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel, handler: nil))
        
        if let popOver = action.popoverPresentationController {
            popOver.barButtonItem = barButton
        }
        present(action, animated: true, completion: nil)
    }

    @IBAction func onTouchClearButton() {
        signatureView.clear()
    }
    
    override open func didRotate(from fromInterfaceOrientation: UIInterfaceOrientation) {
        signatureView.reposition()
    }
}
