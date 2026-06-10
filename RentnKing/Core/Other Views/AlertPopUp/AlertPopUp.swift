//
//  AlertPopUp.swift
//  Now TV!
//
//  Created by Jigar Khatri on 06/09/23.
//

import UIKit
@objc protocol AleartDelegate{
    func SelectYes(section: Int, index : Int, amout: Double, isTax : Bool)
}


class AlertPopUp: UIView {
    weak var delegate: AleartDelegate?

   
    //VIEW
    @IBOutlet weak var subView: UIView!
    @IBOutlet weak var inerView: UIView!
    @IBOutlet var mainView: UIView!

    @IBOutlet weak var viewKeep : UIView!
    @IBOutlet weak var lblKeep : UILabel!
    @IBOutlet weak var viewRemove : UIView!
    @IBOutlet weak var lblRemove : UILabel!

    @IBOutlet weak var lblMessage: UILabel!
    
    @IBOutlet weak var viewAmount: UIView!
    @IBOutlet weak var txtAmount: UITextField!
    @IBOutlet weak var cont_Amount: NSLayoutConstraint!
    @IBOutlet weak var cont_Top: NSLayoutConstraint!
    @IBOutlet weak var cont_Bottom: NSLayoutConstraint!
    
    @IBOutlet weak var objSelectTax: UIStackView!
    @IBOutlet weak var cont_SelectTax: NSLayoutConstraint!

    @IBOutlet weak var imgTax: UIImageView!
    @IBOutlet weak var lblTax: UILabel!

    @IBOutlet weak var imgFreeTax: UIImageView!
    @IBOutlet weak var lblFreeTax: UILabel!
    

    var currentSection : Int = 0
    var currentIndex : Int = 0
    var isAmount : Bool = false
    var isChargeTax : Bool = true
    
    // method to load reasons xib.
    func loadPopUpView(strMessage : String, strOptions: String, section: Int, index : Int, isAmount : Bool = false) {
        // ContactUS name of the XIB.
        Bundle.main.loadNibNamed("AlertPopUp", owner:self, options:nil)
        self.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        self.subView.layer.cornerRadius = 10.0
        self.mainView.frame = self.bounds
        self.addSubview(self.mainView)
        self.mainView.layoutIfNeeded()
        
        
        //SET ANIMATION
        self.subView.transform = CGAffineTransform(scaleX: 0.2, y:0.2)
        UIView.animate(withDuration:1.0, delay: 0.0, usingSpringWithDamping: 0.5,
                       initialSpringVelocity: 0.5, options: [], animations:
                        {
            self.subView.transform = CGAffineTransform(scaleX: 1.0, y:1.0)
        }, completion:nil)
        
        //SET TEXT
        self.isAmount = isAmount
        self.cont_Top.constant = 0
        self.cont_Amount.constant = 0
        self.cont_Bottom.constant = 16
        self.objSelectTax.isHidden = true
        self.cont_SelectTax.constant = 0
        self.viewAmount.backgroundColor = .clear
        self.viewAmount.viewCorneRadius(radius: 5, isRound: false)
        self.viewAmount.viewBorderCorneRadius(borderColour: .backgroundView?.withAlphaComponent(0.7))
        self.viewAmount.isHidden = true

        if isAmount == true{
            self.cont_Top.constant = 12
            self.cont_Bottom.constant = 30
            self.objSelectTax.isHidden = false
            self.cont_SelectTax.constant = 30
            self.cont_Amount.constant = manageWidth(size: 50)
            self.viewAmount.isHidden = false
            
            //SET TEXT
            self.txtAmount.configureText(bgColour: .clear, textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "", placeholder: str.strEnterValue)
            self.txtAmount.delegate = self
        }
        
        //SET FONT
        self.currentSection = section
        self.currentIndex = index
        self.setTheView(strMessage: strMessage, strOptions: strOptions, isAmount: isAmount)
    }
    
    func removeViewWithAnimation(isClose : Bool) {
        self.subView.transform = CGAffineTransform.identity
        UIView.animate(withDuration: 0.1, animations: {
            self.subView.transform = CGAffineTransform(scaleX: 1.01, y:1.01)
        } ,completion:{ (finished) in
            if(finished) {
                self.alpha = 1.0
                UIView.animate(withDuration:0.5, animations: {
                    self.alpha = 0
                    self.subView.transform = CGAffineTransform(scaleX: 0.2, y:0.2)
                }, completion: { (finished) in
                    if(finished) {
                        if isClose{
                            self.delegate?.SelectYes(section: self.currentSection, index:self.currentIndex, amout: 0.0, isTax: self.isChargeTax)
                        }
                        self.removeFromSuperview()
                    }
                })
            }
        })
    }
    
    //SET THE VIEW
    func setTheView(strMessage : String, strOptions: String, isAmount : Bool) {
        
        //SET FONT
        self.lblMessage.configureLable(textColor: UIColor.backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 20.0, text: strMessage)
        self.lblMessage.textAlignment = .center
        
        self.lblKeep.configureLable(textColor: UIColor.primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: isAmount ? str.yes : "Keep \(strOptions)")
        self.lblKeep.textAlignment = .center

        self.lblRemove.configureLable(textColor: UIColor.primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: isAmount ? str.no : str.strRemoveOptions)
        self.lblRemove.textAlignment = .center

        //SET TAX
        self.setTax()
        
        //SET VIEW
        self.viewKeep.backgroundColor = .greenText
        self.viewRemove.backgroundColor = .redText
        
        self.viewKeep.viewCorneRadius(radius: 5.0, isRound: false)
        self.viewRemove.viewCorneRadius(radius: 5.0, isRound: false)
    }
    
    func setTax(){
        self.imgFreeTax.image = UIImage(named: self.isChargeTax ? "icon_RadioUnSelect" : "icon_RadioSelect")
        self.imgTax.image = UIImage(named: self.isChargeTax ? "icon_RadioSelect" : "icon_RadioUnSelect")
        imgColor(imgColor: self.imgTax, colorHex: .background)
        imgColor(imgColor: self.imgFreeTax, colorHex: .background)

        self.lblTax.configureLable(textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.strChargeTax)
        self.lblFreeTax.configureLable(textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.strTaxFree)

    }
    
    //......................... OTHER FUNCION .........................//
    @IBAction func btnNoClicked(_ sender: Any) {
        self.endEditing(true)
        removeViewWithAnimation(isClose: isAmount ? false : true)
    }
    
    @IBAction func btnTaxClicked(_ sender: Any) {
        if self.isChargeTax{
            self.isChargeTax = false
        }
        else{
            self.isChargeTax = true
        }
        
        //SET TAX
        self.setTax()
    }
    
    @IBAction func btnYesClicked(_ sender: Any) {
        self.endEditing(true)
        if isAmount{
            //CHECK VALIDATION
            let strAmount: String = self.txtAmount.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            if strAmount == ""{
                showAlertMessage(strMessage: "Please enter an amount.")
            }
            else{
                self.removeViewWithAnimation(isClose: false)
                DispatchQueue.main.async {
                    self.delegate?.SelectYes(section: 0, index: 0, amout: Double(strAmount) ?? 0.0, isTax: self.isChargeTax)
                }
            }
        }
        else{
            self.removeViewWithAnimation(isClose: isAmount ? true : false)
        }
        

        
    }
}




extension AlertPopUp : UITextFieldDelegate{
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField == self.txtAmount{
            let inverseSet = NSCharacterSet(charactersIn:"0123456789.").inverted
            let components = string.components(separatedBy: inverseSet)
            let filtered = components.joined(separator: "")
            if filtered == string {
                let candidate = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) ?? string
        //        let candidate = oldString.stringByReplacingCharactersInRange(range, withString: string)
                let regex = try? NSRegularExpression(pattern: "^\\d{0,5}(\\.\\d{0,2}?)?$", options: [])
                return regex?.firstMatch(in: candidate, options: [], range: NSRange(location: 0, length: candidate.count)) != nil
//                return true
            }
            else{
                return false
            }
        }
        return true

    }
}
