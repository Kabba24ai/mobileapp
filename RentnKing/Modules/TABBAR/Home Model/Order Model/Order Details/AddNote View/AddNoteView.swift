//
//  PaymentView.swift
//  RentnKing
//
//  Created by Jigar Khatri on 15/02/24.
//

import UIKit
@objc protocol AddNoteDelegate{
    func strAddNote(strNote : String)
}


class AddNoteView: UIView {
    weak var delegate: AddNoteDelegate?

    //VIEW
    @IBOutlet weak var subView: UIView!
    @IBOutlet weak var inerView: UIView!
    @IBOutlet var mainView: UIView!
    @IBOutlet weak var lblPay : UILabel!
    @IBOutlet weak var con_Btn: NSLayoutConstraint!
    @IBOutlet weak var viewPay: UIView!

    //CONSTANT
    @IBOutlet weak var con_Popup: NSLayoutConstraint!
    @IBOutlet weak var con_PopupMain: NSLayoutConstraint!

    
    @IBOutlet weak var lblTitle: UILabel!
    @IBOutlet weak var txtNote: UITextView!
    @IBOutlet weak var txtNotePlaceholder: UITextView!

   
    @IBOutlet weak var viewClose: UIView!
    @IBOutlet weak var imgClose: UIImageView!


    var orderID : String = ""
    var strNote : String = ""
    
    // method to load reasons xib.
    func loadPopUpView(strOrderID: String ,strNote : String) {
        // ContactUS name of the XIB.
        Bundle.main.loadNibNamed("AddNoteView", owner:self, options:nil)
        self.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        self.subView.layer.cornerRadius = 10.0
        self.mainView.frame = self.bounds
        self.addSubview(self.mainView)
        self.mainView.layoutIfNeeded()
        
        setupKeyboard(false)

        //SET ANIMATION
        
        self.subView.transform = CGAffineTransform(scaleX: 0.2, y:0.2)
        UIView.animate(withDuration:1.0, delay: 0.0, usingSpringWithDamping: 0.5,
                       initialSpringVelocity: 0.5, options: [], animations:
                        {
            self.subView.transform = CGAffineTransform(scaleX: 1.0, y:1.0)
        }, completion:nil)
        
        
        
        //SET FONT
        self.orderID = strOrderID
        self.strNote = strNote
        self.setTheView()
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
                        self.removeFromSuperview()
                    }
                })
            }
        })
    }
    
    //SET THE VIEW
    func setTheView() {
   
        //SET CONSTANT
        self.con_Popup.constant = manageWidth(size: 350)
        
        //SET FONT
        self.lblTitle.configureLable(textAlignment : .center, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: str.strDeliveryNote)
        
        //SET VIEW
        self.subView.backgroundColor = UIColor.clear
        self.inerView.backgroundColor = UIColor.background
        self.inerView.viewCorneRadius(radius: 10.0, isRound: false)
        self.inerView.viewBorderCorneRadius(borderColour: .secondary)
        self.inerView.viewBorderCorneRadius2(borderSize: 2.0, borderColour: .secondary.withAlphaComponent(0.4))
        
        
        self.txtNote.configureText(bgColour: .clear, textColor: .primary , fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "")
        self.txtNote.delegate = self

        self.txtNotePlaceholder.configureText(bgColour: .clear, textColor: .lightGray , fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.strAddNote)
        if self.strNote != ""{
            self.txtNote.text = self.strNote
            self.txtNotePlaceholder.text = ""
        }
        
        self.viewPay.backgroundColor = .secondaryTextView
        self.viewClose.backgroundColor = .background
        self.viewClose.viewCorneRadius(radius: 0, isRound: true)
        self.viewClose.viewBorderCorneRadius(borderColour: .secondary)
        imgColor(imgColor: self.imgClose, colorHex: .secondary)
 
        //SET CONSTANT
        self.con_Btn.constant = manageWidth(size: 45)
        self.lblPay.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Save")

    }
    
    //......................... OTHER FUNCION .........................//
    @IBAction func btnCloseClicked(_ sender: Any) {
        self.endEditing(true)

        self.removeViewWithAnimation(isClose: false)
    }

    @IBAction func btnPayClicked(_ sender: Any) {
        self.endEditing(true)

        let strNote: String = self.txtNote.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        
        if strNote == ""{
            showAlertMessage(strMessage: "Please enter note")
        }
        else {
            //CALL API
            self.addNote(AddNoteParameater: AddNoteParameater(order_id: self.orderID, order_note: strNote))
        }

    }
    
}










struct AddNoteParameater: Codable {
    var order_id : String
    var order_note: String
}


extension AddNoteView :WebServiceHelperDelegate{
    
    func addNote(AddNoteParameater:AddNoteParameater){
       
        guard let parameater = try? AddNoteParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.addOrderNote.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "addOrderNote"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }
    
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "addOrderNote"{
                print(data)
                
                self.removeViewWithAnimation(isClose: true)
                DispatchQueue.main.async {
                    self.delegate?.strAddNote(strNote: self.txtNote.text)
                }
                
            }
        }
        else{
            indicatorHide()
            //SET THE VIEW
            if data.getStringForID(key: "message") != ""{
                showAlertMessage(strMessage: data.getStringForID(key: "message"))
            }
            else{
                showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
            }
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        

        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}






extension AddNoteView:  UITextViewDelegate{
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let newText = (textView.text as NSString).replacingCharacters(in: range, with: text)
        
        if textView == self.txtNote{
            if newText.count != 0{
                self.txtNotePlaceholder.text = ""
            }
            else{
                self.txtNotePlaceholder.text = str.strAddNote
                self.txtNote.text = ""
            }
        }
        
        return true
        
    }
}
