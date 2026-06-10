//
//  FilterViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 11/04/24.
//

import UIKit

protocol FilterProtocol : AnyObject {
    func SelectFilter(categoryID : Int, strStatus : String, strPaymentType : String, strDeliveryType : String, strNotificationType : String)
}


class FilterViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate : FilterProtocol? = nil

    //SET VIEW VALUES
    @IBOutlet weak var viewFilter: UIView!
    @IBOutlet weak var conTopView: NSLayoutConstraint!
    @IBOutlet weak var conHeightView: NSLayoutConstraint!
    @IBOutlet weak var conViewHeader: NSLayoutConstraint!
  

    @IBOutlet var tblView: UITableView!
    @IBOutlet weak var btnDone: UIButton!
    @IBOutlet weak var btnCancel: UIButton!
    @IBOutlet weak var lblTitle: UILabel!

    //SET OTHER VALUE   Multiple Pick up and for other stores
    @IBOutlet weak var viewItemMenu: UIView!
    
    @IBOutlet weak var viewCaregory: UIView!
    @IBOutlet weak var lblCaregory: UILabel!

    @IBOutlet weak var viewStatus: UIView!
    @IBOutlet weak var lblStatus: UILabel!
    
    @IBOutlet weak var viewPaymentType: UIView!
    @IBOutlet weak var lblPaymentType: UILabel!

    @IBOutlet weak var viewType: UIView!
    @IBOutlet weak var lblType: UILabel!

    @IBOutlet weak var viewNotificationType: UIView!
    @IBOutlet weak var lblNotificationType: UILabel!

    @IBOutlet weak var viewPastOrder: UIView!
    @IBOutlet weak var lblPastOrder: UILabel!

    
    var initialConViewBgTop: CGFloat = 0.0
    var safeAreaTopPadding: CGFloat = 0.0
    var topSpacing: CGFloat = 20.0
    var bgAlpha: CGFloat = 0.5
    var selectFilterIndex : Int = 1
    var selectCategoryID : Int = 0
    var selectStatus :  String = "All"
    var selectPaymentType :  String = "All"
    var selectType :  String = "Pending"
    var selectNotificationType :  String = "All"
    var isScheduleScreen : Bool = false
    var strPastSelect : String = "None"

    var arrCategorys : [CategoryModel] = []
    var arrStatus : [String] = ["All","Paid", "Pending", "Account" ,"Partial Refund", "Refunded", "Failed"]
    var arrPaymentMethos: [String] = ["All","Card", "COD", "Account"]
    var arrScheduleStatus : [String] = ["Pending","Completed"]
    var arrNotification: [String] = ["All","Unread", "Read"]
    var arrPastOrder: [String] = ["None", "Past 7 Days", "Past 15 Days", "Past 30 Days"]


    

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
        
        
        //RELOAD
        self.setView()
        
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
        conHeightView.constant = view.bounds.size.height - 50 - (topSpacing + safeAreaTopPadding)
        
    }
    
    func setView(){
        
        //SET FONT
        self.lblTitle.configureLable(textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "Select Filter")
        self.lblTitle.textAlignment = .center
        
        self.btnCancel.configureLable(bgColour: .clear, textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: "Cancel")
        self.btnDone.configureLable(bgColour: .clear, textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 18.0, text: "Apply")
        
        //SET VIEW
        self.setSelectFilterViews(select: self.selectFilterIndex)
    }
    
    func setSelectFilterViews(select : Int){
        self.viewCaregory.backgroundColor = .clear
        self.viewStatus.backgroundColor = .clear
        self.viewPaymentType.backgroundColor = .clear
        self.viewNotificationType.backgroundColor = .clear
        self.viewType.backgroundColor = .clear
        self.viewPastOrder.backgroundColor = .clear

        self.lblCaregory.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "Category")
        self.lblCaregory.textAlignment = .center

        self.lblStatus.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "Status")
        self.lblStatus.textAlignment = .center

        self.lblPaymentType.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "Payment Type")
        self.lblPaymentType.textAlignment = .center

        self.lblType.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "Status")
        self.lblType.textAlignment = .center

        self.lblNotificationType.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "Notification")
        self.lblNotificationType.textAlignment = .center

        self.lblPastOrder.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "Past Orders")
        self.lblPastOrder.textAlignment = .center

        if select == 1{
            self.viewCaregory.backgroundColor = .background
            self.lblCaregory.textColor = .primary
        }
        else if select == 2{
            self.viewStatus.backgroundColor = .background
            self.lblStatus.textColor = .primary
        }
        else if select == 3{
            self.viewPaymentType.backgroundColor = .background
            self.lblPaymentType.textColor = .primary
        }
        else if select == 4{
            self.viewType.backgroundColor = .background
            self.lblType.textColor = .primary
        }
        else if select == 5{
            self.viewNotificationType.backgroundColor = .background
            self.lblNotificationType.textColor = .primary
        }
        else if select == 6{
            self.viewPastOrder.backgroundColor = .background
            self.lblPastOrder.textColor = .primary
        }
        
        //CHECK TYPE
        self.viewType.isHidden = true
        self.viewStatus.isHidden = false
        self.viewPaymentType.isHidden = false
        self.viewNotificationType.isHidden = false
        self.viewPastOrder.isHidden = true
        if self.isScheduleScreen{
            self.viewType.isHidden = false
            self.viewStatus.isHidden = true
            self.viewPaymentType.isHidden = true
            self.viewNotificationType.isHidden = true
            self.viewPastOrder.isHidden = false
        }
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
            
            //GET DATA
            self.delegate?.SelectFilter(categoryID: self.selectCategoryID, strStatus: self.selectStatus, strPaymentType: self.selectPaymentType, strDeliveryType: self.selectType, strNotificationType: self.selectNotificationType)
            
            DispatchQueue.main.async {
                self.dismiss(animated: false)
            }
        }
    }
    
    @IBAction func btnSelectFilterClicked(_ sender: UIButton) {
//        if sender.tag == 1{
//            self.selectFilterIndex = 1
//        }
//        else if sender.tag == 2{
//            self.selectFilterIndex = 2
//        }
//        else if sender.tag == 3{
//            self.selectFilterIndex = 3
//        }
//        else if sender.tag == 4{
//            self.selectFilterIndex = 4
//        }
//        else if sender.tag == 5{
//            self.selectFilterIndex = 5
//        }
//        else if sender.tag == 6{
//            
//        }
        self.selectFilterIndex = sender.tag
        //SET VIEW AND REPLAOD
        self.setSelectFilterViews(select: self.selectFilterIndex)
        self.tblView.reloadData()
    }
}

//.............................. UIPanGestureRecognizer .....................//
//MARK: - UIPanGestureRecognizer -

extension FilterViewController {
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
class FilterCell : UITableViewCell{
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var imgTag: UIImageView!
}

//MARK: -- UITABEL DELEGATE --
extension FilterViewController : UITableViewDelegate, UITableViewDataSource{
  
        
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.selectFilterIndex == 1{
            return self.arrCategorys.count
        }
        else if self.selectFilterIndex == 2{
            return self.arrStatus.count
        }
        else if self.selectFilterIndex == 3{
            return self.arrPaymentMethos.count
        }
        else if self.selectFilterIndex == 4{
            return self.arrScheduleStatus.count
        }
        else if self.selectFilterIndex == 5{
            return self.arrNotification.count
        }
        else if self.selectFilterIndex == 6{
            return self.arrPastOrder.count
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
     
        if let cell = tableView.dequeueReusableCell(withIdentifier: "FilterCell") as? FilterCell{
            
            //SET FONT
            cell.imgTag.image = UIImage(named: "icon_RadioUnSelect")
            if self.selectFilterIndex == 1{
                cell.lblName.configureLable(textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.arrCategorys[indexPath.row].name?.capitalized ?? "")
                
                if self.selectCategoryID == self.arrCategorys[indexPath.row].id ?? 0{
                    cell.imgTag.image = UIImage(named: "icon_RadioSelect")
                }
            }
            else if self.selectFilterIndex == 2{
                cell.lblName.configureLable(textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.arrStatus[indexPath.row].capitalized)
                
                if self.selectStatus.lowercased() == self.arrStatus[indexPath.row].lowercased(){
                    cell.imgTag.image = UIImage(named: "icon_RadioSelect")
                }
            }
            else if self.selectFilterIndex == 3{
                cell.lblName.configureLable(textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.arrPaymentMethos[indexPath.row].capitalized)
                
                if self.selectPaymentType.lowercased() == self.arrPaymentMethos[indexPath.row].lowercased(){
                    cell.imgTag.image = UIImage(named: "icon_RadioSelect")
                }
            }
            else if self.selectFilterIndex == 4{
                cell.lblName.configureLable(textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.arrScheduleStatus[indexPath.row] .capitalized)
                
                if self.selectType.lowercased() == self.arrScheduleStatus[indexPath.row].lowercased(){
                    cell.imgTag.image = UIImage(named: "icon_RadioSelect")
                }
            }
            else if self.selectFilterIndex == 5{
                cell.lblName.configureLable(textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.arrNotification[indexPath.row] .capitalized)
                
                if self.selectNotificationType.lowercased() == self.arrNotification[indexPath.row].lowercased(){
                    cell.imgTag.image = UIImage(named: "icon_RadioSelect")
                }
            }
            else if self.selectFilterIndex == 6{
                cell.lblName.configureLable(textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.arrPastOrder[indexPath.row] .capitalized)
                
                if self.strPastSelect.lowercased() == self.arrPastOrder[indexPath.row].lowercased(){
                    cell.imgTag.image = UIImage(named: "icon_RadioSelect")
                }
            }
            imgColor(imgColor: cell.imgTag, colorHex: .background)
            return cell
        }
    
        return UITableViewCell()

    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        //SELECT
        if self.selectFilterIndex == 1{
            self.selectCategoryID = self.arrCategorys[indexPath.row].id ?? 0
        }
        else if self.selectFilterIndex == 2{
            self.selectStatus = self.arrStatus[indexPath.row]
        }
        else if self.selectFilterIndex == 3{
            self.selectPaymentType = self.arrPaymentMethos[indexPath.row]
        }
        else if self.selectFilterIndex == 4{
            self.selectType = self.arrScheduleStatus[indexPath.row]
        }
        else if self.selectFilterIndex == 5{
            self.selectNotificationType = self.arrNotification[indexPath.row]
        }
        else if self.selectFilterIndex == 6{
            self.strPastSelect = self.arrPastOrder[indexPath.row]
        }
        //RELOAD TABLE
        self.tblView.reloadData()
    }
}
