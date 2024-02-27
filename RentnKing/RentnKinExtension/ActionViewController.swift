//
//  ActionViewController.swift
//  Kabba
//
//  Created by Jigar Khatri on 20/09/23.
//

import UIKit
import MobileCoreServices
import UniformTypeIdentifiers
import Contacts
import Alamofire
import IQKeyboardManagerSwift


class ActionViewController: UIViewController, UIGestureRecognizerDelegate {
   
    //DECLARE VARIABLE
    @IBOutlet weak var tblView : UITableView!
    @IBOutlet weak var con_tblTop: NSLayoutConstraint!
    @IBOutlet weak var con_tblBottom: NSLayoutConstraint!


    @IBOutlet weak var imgClose: UIImageView!
    @IBOutlet weak var lblHeader: UILabel!


    @IBOutlet weak var viewFirstName: UIView!
    @IBOutlet weak var lblFirstName: UILabel!
    @IBOutlet weak var txtFirstName: UITextField!
    
    @IBOutlet weak var viewLastName: UIView!
    @IBOutlet weak var lblLastName: UILabel!
    @IBOutlet weak var txtLastName: UITextField!

    
    @IBOutlet weak var lblPhone: UILabel!
    @IBOutlet weak var viewPhone: UIView!
    @IBOutlet weak var txtPhone: UITextField!

    @IBOutlet weak var lblPhone2: UILabel!
    @IBOutlet weak var viewPhone2: UIView!
    @IBOutlet weak var txtPhone2: UITextField!

    @IBOutlet weak var lblEmail: UILabel!
    @IBOutlet weak var viewEmail: UIView!
    @IBOutlet weak var txtEmail: UITextField!
   
    @IBOutlet weak var lblTag: UILabel!
    @IBOutlet weak var viewTagList: UIView!
    @IBOutlet weak var tagListView: TagListView!

    @IBOutlet weak var lblNote: UILabel!
    @IBOutlet weak var viewNote: UIView!
    @IBOutlet weak var txtNote: UITextView!
    @IBOutlet weak var viewNoteMain: UIView!

    
    @IBOutlet weak var objIndicator: UIActivityIndicatorView!
    @IBOutlet weak var objTagIndicator: UIActivityIndicatorView!
    @IBOutlet weak var btnAdd: UIButton!
    @IBOutlet weak var ViewSave: UIView!
    @IBOutlet weak var btnSave: UIButton!
    @IBOutlet weak var btnSaveEdit: UIButton!

    var arrNumber : [String] = []
    var arrTags : [TagListModel] = []
    var arrSelectedTags : [String] = []
    var isNoteSelect : Bool = false
    var moveKeybordValude : CGFloat = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
//        IQKeyboardManager.shared.enable = true
        
        //sET VIEW
        self.setTheView()
        
        // Get the item[s] we're handling from the extension context.
        
        // For example, look for an image and place it into an image view.
        // Replace this with something appropriate for the type[s] your extension supports.
        for item in self.extensionContext!.inputItems as! [NSExtensionItem] {
            for provider in item.attachments! {
                if provider.hasItemConformingToTypeIdentifier(kUTTypeContact as String){
                    
                    provider.loadItem(forTypeIdentifier: kUTTypeContact as String, options: nil, completionHandler: { (contactCoder, error) in
                        OperationQueue.main.addOperation
                        {
                            if error == nil
                            {
                                if let contactCoder = contactCoder
                                {
                                    do {
                                        let theContacts = try CNContactVCardSerialization.contacts(with: contactCoder as! Data)
                                        
                                        for obj in theContacts{
                                            //GET NAME
                                            self.txtFirstName.text = "\(obj.givenName)"
                                            self.txtLastName.text = "\(obj.familyName)"
                                            
                                            //GET EMAIL
                                            for objEmail in obj.emailAddresses{
                                                self.txtEmail.text = "\(objEmail.value)"
                                            }
                                            
                                            
                                            //GET NUMBER
                                            for objNumber in obj.phoneNumbers{
                                            
                                                self.arrNumber.append(objNumber.value.stringValue)
                                            }
                                            
                                            if self.arrNumber.count != 0{
                                                
                                                //GET LAST 10Number
                                                var number = self.arrNumber[0]
                                                number = number.replacingOccurrences(of: "(", with: "")
                                                number = number.replacingOccurrences(of: ")", with: "")
                                                number = number.replacingOccurrences(of: " ", with: "")
                                                number = number.replacingOccurrences(of: "-", with: "")

                                                print(number)
                                                var strNumebr = number
                                                if number.count >= 10{
                                                    strNumebr = String(number.suffix(10))
                                                }
                                                print(strNumebr)
                                                self.txtPhone.text = self.format(with: Application.phoneFormate, phone: strNumebr)
                                                
//                                                if self.arrNumber.count > 1{
//                                                    self.txtPhone2.text = self.arrNumber[1]
//                                                }
                                            }
                                            
                                            
                                            //CHECK VALUE
                                            let strFirstName: String = self.txtFirstName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
//                                            let strLastName: String = self.txtLastName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
                                            let strPhone: String = self.txtPhone.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

                                            if strFirstName == strPhone{
                                                self.txtFirstName.text = ""
                                            }
                                        }
                                        print(theContacts)
                                    }
                                    catch{
                                        print("error")
                                    }
                                }
                            }
                        }
                    })
                }
            }
        }
        
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.view.backgroundColor = .background

        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true
        
        
        //SET KEYBORD
        setupKeyboard(false)
        self.registerForKeyboardNotifications()
        self.hideKeyboard()

        self.setHeader()
        
        //GET TAGS
        self.getTagsAPI()
    }
    
    
    func setTheView(){
        //SET BUTTON
        imgColor(imgColor: self.imgClose, colorHex: .secondary)

        
        self.ViewSave.isHidden = false
        self.objIndicator.isHidden = true
        self.objIndicator.stopAnimating()
        
        
        //SET TAGVIEW
        self.viewTagList.backgroundColor = .clear
        self.viewTagList.viewCorneRadius(radius: 10.0, isRound: false)
        self.viewTagList.viewBorderCorneRadius(borderColour: .lightGray)
        
        self.tagListView.isHidden = false
        self.tagListView.delegate = self
        self.tagListView.removeAllTags()

        //SET NOTE
        self.viewNote.viewBorderCorneRadius(borderColour: .gray)
        self.viewNote.viewCorneRadius(radius: 5, isRound: false)
        
        //SET LABLE
        self.lblHeader.configureLable(textColor: UIColor.primary, fontName: GlobalConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "Contact Info")
        self.lblFirstName.configureLable(textColor: UIColor.primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "First Name")
        self.lblLastName.configureLable(textColor: UIColor.primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "Last Name")
        self.lblPhone.configureLable(textColor: UIColor.primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "Mobile*")
        self.lblPhone2.configureLable(textColor: UIColor.primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "Company Name")
        self.lblEmail.configureLable(textColor: UIColor.primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "Email")
        self.lblTag.configureLable(textColor: UIColor.primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "Select Tags")
        self.lblNote.configureLable(textColor: UIColor.primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "Note")

        
        //SET FONT
        self.txtFirstName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter first name")
        self.txtFirstName.delegate = self
        
        self.txtLastName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter last name")
        self.txtLastName.delegate = self

        self.txtPhone.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter number")
        self.txtPhone.delegate = self

        self.txtPhone2.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter company name")
        self.txtPhone2.delegate = self
        
        self.txtEmail.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter email")
        self.txtEmail.delegate = self

        self.txtNote.configureText(bgColour: .clear, textColor: .primary ?? UIColor.white, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "")
        self.txtNote.delegate = self
        
        self.btnSave.configureLable(bgColour: .primary, textColor: .background, fontName: GlobalConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Save")
        self.btnSave.btnCorneRadius(radius: 10, isRound: false)
        self.btnSaveEdit.configureLable(bgColour: .secondary, textColor: .background, fontName: GlobalConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Save & Edit")
        self.btnSaveEdit.btnCorneRadius(radius: 10, isRound: false)
        
        //SET VIEW
        self.viewFirstName.setTheTextView(bgColor: .secondary ?? .clear)
        self.viewLastName.setTheTextView(bgColor: .secondary ?? .clear)
        self.viewPhone.setTheTextView(bgColor: .secondary ?? .clear)
        self.viewPhone2.setTheTextView(bgColor: .secondary ?? .clear)
        self.viewEmail.setTheTextView(bgColor: .secondary ?? .clear)
        self.viewTagList.setTheTextView(bgColor: .secondary ?? .clear)
        self.viewNote.setTheTextView(bgColor: .secondary ?? .clear)
//        self.ViewSave.roundCorners(corners: [.topRight], radius: 10)
//        self.ViewSave.viewCorneRadius(radius: 10, isRound: false)
        self.ViewSave.backgroundColor = .clear
    }
  
    func setHeader(){
        //SET HEADER
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            //SET TABLE HEADER
            let vw_Table = self.tblView.tableHeaderView
            vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.ViewSave.frame.origin.y + self.ViewSave.frame.size.height + (checkDeviceiPad() ? 200 : 20))
            self.tblView.tableHeaderView = vw_Table
        }
    }
}


extension ActionViewController : TagListViewDelegate{
    
    // MARK: TagListViewDelegate
    func tagPressed(_ title: String, tagView: TagView, sender: TagListView) {
        print("Tag pressed: \(title), \(sender)")
        //        tagView.isSelected = !tagView.isSelected
       
    }
    
    func tagRemoveButtonPressed(_ title: String, tagView: TagView, sender: TagListView) {
        sender.removeTagView(tagView)
    }
}


//MARK: - BUTTON ACTION
extension ActionViewController : TagsProtocol{
    func SelectTag(arrTag: [String]) {
        self.arrSelectedTags = arrTag
        for obj in arrTag{
            self.tagListView.addTag(obj, tag: 1, isRemovButton: true)
            self.setHeader()
        }
        
        
    }
    
    @IBAction func btnAddTagClicked(_ sender: UIButton) {
        
        //CUSTOME LIST
        let storyboard = UIStoryboard(name: GlobalConstants.Main, bundle: nil)
        let view = storyboard.instantiateViewController(withIdentifier: "TagsViewController") as! TagsViewController
        view.delegate = self
        view.arrTags = self.arrTags
        view.arrSelectedTags = self.arrSelectedTags
        view.view.backgroundColor = UIColor.clear
        view.modalPresentationStyle = .overCurrentContext
        self.present(view, animated: false) {
            view.view.backgroundColor = UIColor(red: 0 / 255.0, green: 0 / 255.0, blue: 0 / 255.0, alpha: 0.5)
        }

    }
    
    @IBAction func btnCloseClicked() {
        // Return any edited content to the host app.
        // This template doesn't do anything, so we just echo the passed in items.
        let error = NSError(domain: "com.domain.name", code: 0, userInfo: nil)
        self.extensionContext?.cancelRequest(withError: error)
    }

    @IBAction func btnSaveClicked() {
        self.view.endEditing(true)

        //CHECK VALIDATION
        let strFirstName: String = self.txtFirstName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        let strLastName: String = self.txtLastName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        //CHECK VALIDATION
        var strPhone: String = self.txtPhone.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

    
        self.lblFirstName.textColor = .primary
        self.lblLastName.textColor = .primary
        self.lblPhone.textColor = .primary
//        if strName == ""{
//            self.lblName.textColor = .red
//        }
//        else 
        if strPhone == ""{
            self.lblPhone.textColor = .red
        }
        else{
            //CALL API
            self.ViewSave.isHidden = true
            self.objIndicator.isHidden = false
            self.objIndicator.startAnimating()
            
            strPhone = strPhone.replacingOccurrences(of: "(", with: "")
            strPhone = strPhone.replacingOccurrences(of: ")", with: "")
            strPhone = strPhone.replacingOccurrences(of: " ", with: "")
            strPhone = strPhone.replacingOccurrences(of: "-", with: "")

            //CALL API
            self.submitContectsAPI(contectParameater: contectParameater(name: "\(strFirstName) \(strLastName)",first_name: strFirstName, last_name: strLastName, email: self.txtEmail.text ?? "", phone: strPhone, company: self.txtPhone2.text ?? "", contactTag:  self.arrSelectedTags.joined(separator:"|"), note: self.txtNote.text ?? ""))
            
            //        self.extensionContext!.completeRequest(returningItems: nil, completionHandler: nil)

        }

    }
    
    @IBAction func btnSaveEditClicked() {
        //MOVE TP DETAILS SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalConstants.Main, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "DetailsViewController") as? DetailsViewController{
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
}




extension ActionViewController{
    //KEYBORD ACTION
    func hideKeyboard()
    {
        let tap: UITapGestureRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(self.dismissKeyboard))
        
        view.addGestureRecognizer(tap)
    }
    
    @objc func dismissKeyboard()
    {
        view.endEditing(true)
    }
    
    func registerForKeyboardNotifications(){
        //Adding notifies on keyboard appearing
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWasShown(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillBeHidden(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        
        let numberToolbar = UIToolbar(frame:CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        numberToolbar.barStyle = .default
        numberToolbar.items = [
//        UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelNumberPad)),
        UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
        UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(doneWithNumberPad))]
        numberToolbar.sizeToFit()
        self.txtFirstName.inputAccessoryView = numberToolbar
        self.txtLastName.inputAccessoryView = numberToolbar
        self.txtPhone.inputAccessoryView = numberToolbar
        self.txtPhone2.inputAccessoryView = numberToolbar
        self.txtEmail.inputAccessoryView = numberToolbar
        self.txtNote.inputAccessoryView = numberToolbar
    }
    
    @objc func cancelNumberPad() {
        //Cancel with number pad
    }
    @objc func doneWithNumberPad() {
        //Done with number pad
        self.dismissKeyboard()
    }
    
    @objc func keyboardWasShown(notification: NSNotification){
        //Need to calculate keyboard exact size due to Apple suggestions
        
        let info = notification.userInfo!
        let keyboardSize = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.size
        self.con_tblBottom.constant = (keyboardSize?.height ?? 0) - 20
        self.con_tblTop.constant = 0//-((keyboardSize?.height ?? 0) - 20)
        
        DispatchQueue.main.async {
            if self.isNoteSelect {
                self.tblView.setContentOffset( CGPoint(x: 0, y: (keyboardSize?.height ?? 0)/self.moveKeybordValude) , animated: true)
            }
        }
        
        self.view.animateConstraintWithDuration()
    }
    
    @objc func keyboardWillBeHidden(notification: NSNotification){
        self.con_tblBottom.constant = 0
        self.con_tblTop.constant = 0
        self.view.animateConstraintWithDuration()
        //Once keyboard disappears, restore original positions
    }
}



//MARK: -- UITEXTFIELD DELEGATE
extension ActionViewController : UITextFieldDelegate{
    func textFieldDidBeginEditing(_ textField: UITextField) {
        if textField == self.txtFirstName || textField == self.txtLastName || textField == self.txtPhone{
            self.isNoteSelect = false
        }
        else{
            self.moveKeybordValude = 3
            self.isNoteSelect = true
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        if textField == self.txtPhone{
            let inverseSet = NSCharacterSet(charactersIn:"0123456789").inverted
            let components = string.components(separatedBy: inverseSet)
            let filtered = components.joined(separator: "")
           
            
            if filtered == string {
                
                guard let text = textField.text else { return false }
                let newString = (text as NSString).replacingCharacters(in: range, with: string)
                textField.text = format(with: Application.phoneFormate, phone: newString)
                return false
            } else {
                return false
            }
        }
        else{
            return true
        }
    }
    
    
    /// mask example: `(XXX) XXX-XXXX`
    func format(with mask: String, phone: String) -> String {
        let numbers = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        var result = ""
        var index = numbers.startIndex // numbers iterator

        // iterate over the mask characters until the iterator of numbers ends
        for ch in mask where index < numbers.endIndex {
            if ch == "X" {
                // mask requires a number in this place, so take the next one
                result.append(numbers[index])

                // move numbers iterator to the next index
                index = numbers.index(after: index)

            } else {
                result.append(ch) // just append a mask character
            }
        }
        return result
    }
}


extension ActionViewController : UITextViewDelegate{
    func textViewDidBeginEditing(_ textField: UITextView) {
        self.moveKeybordValude = 1.2
        self.isNoteSelect = true
    }
}



