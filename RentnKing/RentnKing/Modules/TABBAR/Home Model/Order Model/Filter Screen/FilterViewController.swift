//
//  FilterViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 11/04/24.
//

import UIKit

protocol FilterProtocol : AnyObject {
    func SelectFilter(categoryID : Int, strStatus : String, strDeliveryType : String)
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
    
    @IBOutlet weak var con_SelectView: NSLayoutConstraint!
    @IBOutlet weak var viewCaregory: UIView!
    @IBOutlet weak var lblCaregory: UILabel!

    @IBOutlet weak var viewStatus: UIView!
    @IBOutlet weak var lblStatus: UILabel!
    
    @IBOutlet weak var viewType: UIView!
    @IBOutlet weak var lblType: UILabel!

    
    var initialConViewBgTop: CGFloat = 0.0
    var safeAreaTopPadding: CGFloat = 0.0
    var topSpacing: CGFloat = 20.0
    var bgAlpha: CGFloat = 0.5
    var selectFilterIndex : Int = 1
    var selectCategoryID : Int = 0
    var selectStatus :  String = "all"
    var selectType :  String = "all"
    var isScheduleScreen : Bool = false
    
    var arrCategorys : [CategoryModel] = []
    var arrStatus : [String] = ["all","completed", "failed", "fraud" ,"refunded", "refunding", "pending"]
    var arrDeliveryType : [String] = ["all","delivery", "in store"]


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
        self.viewType.backgroundColor = .clear

        self.lblCaregory.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "Category")
        self.lblCaregory.textAlignment = .center

        self.lblStatus.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "Status")
        self.lblStatus.textAlignment = .center

        self.lblType.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "Delivery Type")
        self.lblType.textAlignment = .center


        if select == 1{
            self.viewCaregory.backgroundColor = .background
            self.lblCaregory.textColor = .primary
        }
        else if select == 2{
            self.viewStatus.backgroundColor = .background
            self.lblStatus.textColor = .primary
        }
        else if select == 3{
            self.viewType.backgroundColor = .background
            self.lblType.textColor = .primary
        }
        
        //CHECK TYPE
        self.viewType.isHidden = true
        self.viewStatus.isHidden = false
        if self.isScheduleScreen{
            self.viewType.isHidden = false
            self.viewStatus.isHidden = true
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
            self.delegate?.SelectFilter(categoryID: self.selectCategoryID, strStatus: self.selectStatus != "all" ? self.selectStatus : "", strDeliveryType: self.selectType)
            
            DispatchQueue.main.async {
                self.dismiss(animated: false)
            }
        }
    }
    
    @IBAction func btnSelectFilterClicked(_ sender: UIButton) {
        if sender.tag == 1{
            self.selectFilterIndex = 1
        }
        else if sender.tag == 2{
            self.selectFilterIndex = 2
        }
        else if sender.tag == 3{
            self.selectFilterIndex = 3
        }
        
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
            return self.arrDeliveryType.count
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
                cell.lblName.configureLable(textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: self.arrDeliveryType[indexPath.row].capitalized)
                
                if self.selectType.lowercased() == self.arrDeliveryType[indexPath.row].lowercased(){
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
            self.selectStatus = self.arrStatus[indexPath.row].lowercased()
        }
        else if self.selectFilterIndex == 3{
            self.selectType = self.arrDeliveryType[indexPath.row].lowercased()
        }
        //RELOAD TABLE
        self.tblView.reloadData()
    }
}
