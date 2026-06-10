//
//  PaymentView.swift
//  RentnKing
//
//  Created by Jigar Khatri on 15/02/24.
//

import UIKit
import Alamofire

protocol AddNoteDelegate{
    func strAddNote(strNote : String)
    func updateDataNoInternetCase(note_dic: OrderNoteModel?, for_delete: Bool)
}


class AddNoteView: UIView, UITextFieldDelegate {
    var delegate: AddNoteDelegate?

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

    @IBOutlet weak var viewUser: UIView!
    @IBOutlet weak var txtUSer: UITextField!
    @IBOutlet weak var lblUser: UILabel!
    
    @IBOutlet weak var viewClose: UIView!
    @IBOutlet weak var imgClose: UIImageView!


    var orderID : String = ""
    var strNote : String = ""
    var arrUserList : [UserListModel] = []
    var strUserID : String = ""
    var objNoteData : OrderNoteModel?
    
    // method to load reasons xib.
    func loadPopUpView(strOrderID: String ,strNote : String, arr : [UserListModel]) {
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
        self.arrUserList = arr
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
        self.lblUser.configureLable(textColor: UIColor.primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: str.strUser)

        
        self.txtNote.configureText(bgColour: .clear, textColor: .primary , fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "")
        self.txtNote.delegate = self

        self.txtUSer.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: str.selectUser)
        self.txtUSer.delegate = self

        
        self.txtNotePlaceholder.configureText(bgColour: .clear, textColor: .lightGray , fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.strAddNote)
        if self.strNote != ""{
            self.txtNote.text = self.strNote
            self.txtNotePlaceholder.text = ""
        }
        
        
        //CEHCK DATA
        if self.objNoteData != nil{
            self.txtNotePlaceholder.text = ""
            self.txtNote.text = self.objNoteData?.note
            self.txtUSer.text = self.objNoteData?.created_by
            self.strUserID = "\(self.objNoteData?.created_by_id ?? 0)"
        }
        
        
        self.viewPay.backgroundColor = .secondaryTextView
        self.viewClose.backgroundColor = .background
        self.viewClose.viewCorneRadius(radius: 0, isRound: true)
        self.viewClose.viewBorderCorneRadius(borderColour: .secondary)
        imgColor(imgColor: self.imgClose, colorHex: .secondary)
 
        //SET CONSTANT
        self.con_Btn.constant = manageWidth(size: 45)
        self.lblPay.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Save")
        
        //SET USER
        self.viewUser.setTheTextView(bgColor: .secondary )


    }
    
    //......................... OTHER FUNCION .........................//
    @IBAction func btnCloseClicked(_ sender: Any) {
        self.endEditing(true)

        self.removeViewWithAnimation(isClose: false)
    }

    @IBAction func btnPayClicked(_ sender: Any) {
        self.endEditing(true)

        let strNote: String = self.txtNote.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strUser: String = self.txtUSer.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

        if strUser == ""{
            showAlertMessage(strMessage: "Please select a user.")
        }
        else if strNote == ""{
            showAlertMessage(strMessage: "Please enter a note.")
        }
        else {
//            if NetworkReachabilityManager()!.isReachable {
//                //CALL API
//                if self.objNoteData != nil {
//                    RentnKing.updateNote(UpdateNoteParameater: UpdateNoteParameater(order_note_unique_id: self.objNoteData?.unique_id ?? "", note: strNote, user_id: self.strUserID), note_id: 0) { is_succss in
//                        self.manageRasponseClosePopup()
//                    }
//                }
//                else{
//                    RentnKing.addNote(AddNoteParameater: AddNoteParameater(order_unique_id: self.orderID, note: strNote, user_id: self.strUserID), note_id: 0) { is_succss in
//                        self.manageRasponseClosePopup()
//                    }
//
//                }
//            }
            //else {
                var dic_OrderNote = OrderNoteModel.init(JSON: [:])
                dic_OrderNote?.id = Int(randomNumber(length: 5))
                
                if self.objNoteData != nil {
                    dic_OrderNote = self.objNoteData
                }
                
                dic_OrderNote?.status = kOrderStatusType.kPending.rawValue
                dic_OrderNote?.type = self.objNoteData != nil ? kOrderStatusType.kEdit.rawValue : kOrderStatusType.kAdd.rawValue
                dic_OrderNote?.note = strNote
                dic_OrderNote?.created_at = getCurrentDate()
                dic_OrderNote?.created_by = strUser
                dic_OrderNote?.created_by_id = Int(self.strUserID) ?? 0
                dic_OrderNote?.unique_id = self.objNoteData != nil ? self.objNoteData?.unique_id ?? "" : self.orderID
                dic_OrderNote?.mainOrderUniqueID = self.orderID
                self.delegate?.updateDataNoInternetCase(note_dic: dic_OrderNote, for_delete: false)
                self.removeViewWithAnimation(isClose: true)
            //}

        }

    }
    
    func manageRasponseClosePopup() {
        self.removeViewWithAnimation(isClose: true)
        DispatchQueue.main.async {
            self.delegate?.strAddNote(strNote: self.txtNote.text)
        }
    }
    
    
    @IBAction func btnSelectUserClicked(_ sender: UIButton) {
        if self.arrUserList.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: str.strSelectState, arrData: self.arrUserList.compactMap { $0.full_name}, selectValue: self.txtUSer.text ?? "") { index, selectValue in
            
            self.strUserID = "\(self.arrUserList[index].id ?? 0)"
            self.txtUSer.text = selectValue
        }
    }
}

struct AddNoteParameater: Codable {
    var order_unique_id : String
    var note: String
    var user_id: String
}

struct UpdateNoteParameater: Codable {
    var order_note_unique_id : String
    var note: String
    var user_id: String
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
