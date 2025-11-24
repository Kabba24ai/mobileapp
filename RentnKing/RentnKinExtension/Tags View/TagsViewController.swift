//
//  TagsViewController.swift
//  Kabba
//
//  Created by Jigar Khatri on 27/09/23.
//

import UIKit

protocol TagsProtocol : AnyObject {
    func SelectTag(arrTag : [Int])
}


class TagsViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate : TagsProtocol? = nil
    
    //SET VIEW VALUES
    @IBOutlet weak var viewFilter: UIView!
    @IBOutlet weak var conTopView: NSLayoutConstraint!
    @IBOutlet weak var conHeightView: NSLayoutConstraint!
    @IBOutlet weak var conViewHeader: NSLayoutConstraint!
    
    @IBOutlet weak var viewCreatTag: UIView!
    @IBOutlet weak var lblCreatTag: UILabel!

    @IBOutlet weak var viewTagMain: UIView!
    @IBOutlet weak var viewTag: UIView!
    @IBOutlet weak var lblHeader: UILabel!
    @IBOutlet weak var viewName: UIView!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var txtName: UITextField!
    @IBOutlet weak var viewTagClose: UIView!
    @IBOutlet weak var lblClose: UILabel!
    @IBOutlet weak var viewTagSubmit: UIView!
    @IBOutlet weak var btnTagSubmit: UIButton!
    @IBOutlet weak var objTagIndicator: UIActivityIndicatorView!


    @IBOutlet var tblView: UITableView!
    @IBOutlet weak var btnDone: UIButton!
    @IBOutlet weak var btnCancel: UIButton!
    @IBOutlet weak var lblTitle: UILabel!

    //SET OTHER VALUE   Multiple Pick up and for other stores
    @IBOutlet weak var viewItemMenu: UIView!
    
    var initialConViewBgTop: CGFloat = 0.0
    var safeAreaTopPadding: CGFloat = 0.0
    var topSpacing: CGFloat = 20.0
    var bgAlpha: CGFloat = 0.5
    
    var arrTags : [TagListModel] = []
    var arrSelectedTags : [Int] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        conViewHeader.constant = 200
        
        
        //ADD PANGESTURE
        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
        pan.delegate = self
        viewFilter.addGestureRecognizer(pan)
        view.layoutIfNeeded()
        
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        self.view.backgroundColor = .background
        
        //SET TO VIEW CONSTANT
        conTopView.constant = self.view.bounds.size.height;
        
        //SET VIEW RADIUS
        let maskLayer = CAShapeLayer()
        maskLayer.frame = viewFilter.bounds
        maskLayer.path = UIBezierPath(roundedRect: viewFilter.bounds, byRoundingCorners: [.topRight, .topLeft], cornerRadii: CGSize(width: 10, height: 10)).cgPath
        viewFilter.layer.mask = maskLayer
        viewFilter.layer.masksToBounds = true
        
        self.viewTag.isHidden = true
        self.registerForKeyboardNotifications()
        
        //RELOAD
        self.setView()
        if self.arrTags.count != 0{
            self.arrTags = self.arrTags.sorted(by: {$0.name?.lowercased() ?? "" < $1.name?.lowercased() ?? ""})
        }
        
        self.tblView.reloadData()

    }
    
    override func viewDidAppear(_ animated: Bool) {
        //SET BG COLOR
        UIView.animate(withDuration: 0.5, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.2, options: .curveEaseInOut, animations: {
            self.conTopView.constant = self.topSpacing + self.safeAreaTopPadding
            self.view.backgroundColor = UIColor.black.withAlphaComponent(self.bgAlpha)
            self.view.layoutIfNeeded()
        }) { finished in
            
        }
    }
    
    override func viewWillLayoutSubviews() {
        
        
        //VIEW RADIUS
        viewItemMenu.layer.masksToBounds = true
        viewItemMenu.layer.cornerRadius = 20.0
        self.viewItemMenu.backgroundColor = .primary

        //SET VIEW CONSTANT
        conHeightView.constant = view.bounds.size.height - (topSpacing + safeAreaTopPadding)
        
    }
    
    func setView(){
        
        //SET FONT
        self.lblTitle.configureLable(textColor: UIColor.background, fontName: GlobalConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select Tags")
        self.lblName.configureLable(textColor: UIColor.primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "Tag*")
        self.lblHeader.configureLable(textColor: UIColor.primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 20.0, text: "Create Tags")
        self.lblHeader.textAlignment = .center

        self.btnCancel.configureLable(bgColour: .clear, textColor: .background, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "Cancel")
        self.btnDone.configureLable(bgColour: UIColor(named: "secondaryEXCopy"), textColor: .background, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "Submit")
        self.btnDone.viewCorneRadius(radius: 5, isRound: false)

        self.lblCreatTag.configureLable(textColor: UIColor.background, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "+ Create")
        self.lblClose.configureLable(textColor: UIColor.background, fontName: GlobalConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "X")
        self.btnTagSubmit.configureLable(bgColour: .clear, textColor: .background, fontName: GlobalConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Submit")

        //SET VIEW
        self.viewCreatTag.backgroundColor = .clear// UIColor(named: "secondaryEXCopy")
        self.viewCreatTag.viewCorneRadius(radius: 5, isRound: false)

        
        //SET FONT
        self.txtName.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter tag")

        
        //SET VIEW
        self.viewName.setTheTextView(bgColor: .secondary ?? .clear)
        self.viewTagMain.backgroundColor = .background
        self.viewTagMain.viewCorneRadius(radius: 10, isRound: false)
        self.viewTagClose.backgroundColor = .secondary
//        self.viewTagClose.viewCorneRadius(radius: 10, isRound: false)
        self.viewTagClose.roundCorners(corners: [.topRight], radius: 10)
        self.viewTagSubmit.viewCorneRadius(radius: 10, isRound: false)
        self.viewTagSubmit.backgroundColor = .primary
        
        //SET TAG BUTTON
        self.viewTagSubmit.isHidden = false
        self.objTagIndicator.isHidden = true
        self.objTagIndicator.stopAnimating()
        
        
    }
    
    func registerForKeyboardNotifications(){
        
        let numberToolbar = UIToolbar(frame:CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 50))
        numberToolbar.barStyle = .default
        numberToolbar.items = [
        UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
        UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(doneWithNumberPad))]
        numberToolbar.sizeToFit()
        txtName.inputAccessoryView = numberToolbar
    }
    
    @objc func doneWithNumberPad() {
        //Done with number pad
        self.dismissKeyboard()
    }
    
    @objc func dismissKeyboard()
    {
        view.endEditing(true)
    }
    
    
    //..................... OTHER FUNCTION .................//
    
    
    //MARK:- BUTTON ACTION
    @IBAction func btnCloseTagClicked(_ sender: Any) {
        self.dismissKeyboard()
        self.viewTag.isHidden = true
    }
    
    @IBAction func btnCreateTagClicked(_ sender: Any) {
        self.dismissKeyboard()
        self.setView()
        self.viewTag.isHidden = false
    }
    
    @IBAction func btnSubmitTagClicked(_ sender: Any) {
        self.view.endEditing(true)

        //CHECK VALIDATION
        let strName: String = self.txtName.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
    
        self.lblName.textColor = .primary
        if strName == ""{
            self.lblName.textColor = .red
        }
        else{
            //CALL API
            self.viewTagSubmit.isHidden = true
            self.objTagIndicator.isHidden = false
            self.objTagIndicator.startAnimating()
            
            self.submitTagAPI(createTagParameater: createTagParameater(name: strName))
            
        }
        
    }
    
    @IBAction func btnCancelClicked(_ sender: Any) {
        //DISMISS VIEW
        UIView.animate(withDuration: 0.3, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.2, options: .curveEaseInOut, animations: {
            self.conTopView.constant = self.conHeightView.constant + (self.topSpacing + self.safeAreaTopPadding)
            self.view.backgroundColor = UIColor.black.withAlphaComponent(0.0)
            self.view.layoutSubviews()
        }) { finished in
            
            self.dismiss(animated: false)
        }
    }
    
    @IBAction func btnDoneClicked(_ sender: Any) {
        //DISMISS VIEW
        UIView.animate(withDuration: 0.3, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.2, options: .curveEaseInOut, animations: {
            self.conTopView.constant = self.conHeightView.constant + (self.topSpacing + self.safeAreaTopPadding)
            self.view.backgroundColor = UIColor.black.withAlphaComponent(0.0)
            self.view.layoutSubviews()
        }) { finished in
            
            self.delegate?.SelectTag(arrTag: self.arrSelectedTags)
            
            DispatchQueue.main.async {
                self.dismiss(animated: false)
            }
        }
    }
}

//.............................. UIPanGestureRecognizer .....................//
//MARK: - UIPanGestureRecognizer -

extension TagsViewController {
    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        
        if recognizer.state == .began {
            initialConViewBgTop = conTopView.constant
        }
        else if recognizer.state == .ended || recognizer.state == .failed || recognizer.state
                    == .cancelled {
            
            if (conTopView.constant < conHeightView.constant/3.5){
                //SET VIEW ON TOP
                UIView.animate(withDuration: 0.3, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.2, options: .curveEaseInOut, animations: {
                    self.conTopView.constant = self.topSpacing + self.safeAreaTopPadding
                    self.view.backgroundColor = UIColor.black.withAlphaComponent((self.bgAlpha * self.topSpacing) / self.conTopView.constant)
                    self.view.layoutSubviews()
                }) { finished in
                }
            }
            else{
                //DISMISS VIEW
                UIView.animate(withDuration: 0.3, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.2, options: .curveEaseInOut, animations: {
                    self.conTopView.constant = self.conHeightView.constant + (self.topSpacing + self.safeAreaTopPadding)
                    self.view.backgroundColor = UIColor.black.withAlphaComponent(0.0)
                    self.view.layoutSubviews()
                }) { finished in
                    
                    self.dismiss(animated: false)
                }
            }
        }
        else{
            
            //SET TOP CONSTANT
            let translatedPoint: CGPoint = recognizer.translation(in: recognizer.view!.superview)
            conTopView.constant = max(initialConViewBgTop + translatedPoint.y, topSpacing)
            
            //SET BG ALPHA
            let alphaComponent: CGFloat = (bgAlpha * topSpacing) / conTopView.constant
            view.backgroundColor = UIColor.black.withAlphaComponent(alphaComponent)
            
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return true
    }
}




//MARK: -- TABLE CELL --
class TagCell : UITableViewCell{
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var imgTag: UIImageView!
}

//MARK: -- UITABEL DELEGATE --
extension TagsViewController : UITableViewDelegate, UITableViewDataSource{
  
        
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.arrTags.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
     
        if let cell = tableView.dequeueReusableCell(withIdentifier: "TagCell") as? TagCell{
            
            //SET FONT
            cell.lblName.configureLable(textColor: UIColor.background, fontName: GlobalConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.arrTags[indexPath.row].name ?? "")
            cell.imgTag.image = UIImage(named: "icon_Uncheck ")
            if self.arrSelectedTags.count != 0{
                if self.arrSelectedTags.contains(self.arrTags[indexPath.row].id ?? 0){
                    cell.imgTag.image = UIImage(named: "icon_Check")
                }
            }
            imgColor(imgColor: cell.imgTag, colorHex: .background)
            
            return cell
        }
    
        return UITableViewCell()

    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        //CECHK TAGS
        let TagID = self.arrSelectedTags.map{$0}
        if let index = TagID.firstIndex(of: self.arrTags[indexPath.row].id ?? 0 ) {
            self.arrSelectedTags.remove(at: index)
        }
        else{
            self.arrSelectedTags.append(self.arrTags[indexPath.row].id ?? 0)
        }
            

        
        //RELOAD TABLE
        self.tblView.reloadData()
    }
}
