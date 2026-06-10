//
//  CheckOutViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 11/01/24.
//

import UIKit

class CheckOutViewController: UIViewController, UIGestureRecognizerDelegate, MenuProtocol, UIPopoverPresentationControllerDelegate, AleartDelegate {
    
 

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!
    @IBOutlet var emptyDataView : EmptyDataView!{
        didSet{
            emptyDataView.noItemsFound()
            emptyDataView.isHidden = true
        }
    }
    
    //TOTLA SECTION
    @IBOutlet weak var objTotlaAmount: UIStackView!

    @IBOutlet weak var lblSubTotla: UILabel!
    @IBOutlet weak var lblSubTotlaPrice: UILabel!
    
    @IBOutlet weak var objTax: UIStackView!
    @IBOutlet weak var lblTax: UILabel!
    @IBOutlet weak var lblTaxPrice: UILabel!

    @IBOutlet weak var objCustomeValue: UIStackView!
    @IBOutlet weak var lblCustomeValue: UILabel!
    @IBOutlet weak var lblCustomeValuePrice: UILabel!
    @IBOutlet weak var viewCloseCustomeValue: UIView!
    @IBOutlet weak var imgCloseCustomeValue: UIImageView!

    
    @IBOutlet weak var lblTotlaAmount: UILabel!
    @IBOutlet weak var lblTotlaAmountPrice: UILabel!
    @IBOutlet weak var btnMenu: UIButton!

    //CHECKOUT
    @IBOutlet weak var con_Checkout: NSLayoutConstraint!
    @IBOutlet weak var viewCheckout: UIView!
    @IBOutlet weak var lblCheckout: UILabel!

    
    

    //LOADING
    let checkOutPlaceholderMarker = Placeholder()

    //OTHER
    var isLoading : Bool = true
    var arrStates : [StatesModel] = []
    var customAmountTaxePrice : Double = 0.0

    override func viewDidLoad() {
        super.viewDidLoad()
        Checkout.shared.customeAmount = 0
        setupKeyboard(true)

        NotificationCenter.default.addObserver(self, selector: #selector(self.cartUpdated(notificatio:)), name: .cartUpdated, object: nil)

        if Checkout.shared.cart.count == 0{
            //NO DATA
            self.tblView.isHidden = true
            self.emptyDataView.isHidden = false
        }
        else{
            //GET DATA
            self.tblView.isHidden = false
            self.getStatesAPI()
        }
        
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
        setNavigationBarFor(controller: self, title: str.strCheckOut, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: Checkout.shared.cart.count != 0 ? "icon_MenuSelect" : "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {
            
            if Checkout.shared.cart.count != 0{
                let storyboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
                let popVC = storyboard.instantiateViewController(withIdentifier: "MenuPopup") as! MenuPopup
                popVC.modalPresentationStyle = .popover
                popVC.delegate = self
                
                let popOverVC = popVC.popoverPresentationController
                popOverVC?.delegate = self
                popOverVC?.backgroundColor = UIColor.white
                popOverVC?.sourceView = self.btnMenu
                popOverVC?.sourceRect = CGRect(x: self.btnMenu.bounds.midX, y: self.btnMenu.bounds.minY, width: 0, height: 0)
                popVC.preferredContentSize = CGSize(width: manageWidth(size: 220.0), height: (manageWidth(size: 60.0)))
                
                popVC.modalTransitionStyle = .crossDissolve
                self.present(popVC, animated: true) 
            }
          
        }
        
        //SET FOOTER VIEW
        self.setFooter()
        
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.none
    }
    
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.none
    }
    
    
    func SelctMenuIndex(Index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() ){
            //OPTION POPUP
            let window = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
            window?.endEditing(true)
            let aleartView = AlertPopUp(frame: CGRect(x: 0, y: 0 ,width : window?.frame.width ?? 0.0, height: window?.frame.height ?? 0.0))
            aleartView.loadPopUpView(strMessage: str.strCustomValue, strOptions: "", section: 0, index: 0, isAmount:  true)
            aleartView.delegate = self
            window?.addSubview(aleartView)

        }
    }
    
    func SelectYes(section: Int, index: Int, amout: Double, isTax: Bool) {
        Checkout.shared.customeAmount = amout
        
        if isTax{
        
            if Checkout.shared.cart.count != 0{
                let cartItem  = Checkout.shared.cart[0]
                
                //GET TAXE PRICE
                var taxePercentage: Double = 0.0
                for objTaxe in cartItem.product.arrTaxes{
                    taxePercentage = taxePercentage + Double((objTaxe.percentage ?? 0.0))
                }
                
                self.customAmountTaxePrice =  ((amout * taxePercentage)/100)

            }
            Checkout.shared.taxCharge = Checkout.shared.taxCharge + self.customAmountTaxePrice
        }
     

        //SET VIEW
        self.setFooter()
    }
    
    @objc private func cartUpdated(notificatio: NSNotification?){
        //RELOAD TABLE
        self.tblView.reloadData()
        
        //SET FOOTER VIEW
        self.setFooter()
    }
    
    func setFooter(){
        //SET DETAILS
        self.lblSubTotla.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.strSubtotal, numberOfLines: 1)
        self.lblSubTotlaPrice.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(Application.currency)\(Checkout.shared.itemPrice.stringValue)", numberOfLines: 1)

        //SET TEXT
        self.objTax.isHidden = true
        if Checkout.shared.taxCharge != 0{
            self.objTax.isHidden = false
        }
        self.lblTax.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.strTax, numberOfLines: 1)
        self.lblTaxPrice.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(Application.currency)\(Checkout.shared.taxCharge.stringValue)", numberOfLines: 1)

        //SET CUSTOME VALUE
        self.objCustomeValue.isHidden = true
        if Checkout.shared.customeAmount != 0{
            self.objCustomeValue.isHidden = false
        }
        self.lblCustomeValue.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.strCustomAmount, numberOfLines: 1)
        self.lblCustomeValuePrice.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(Application.currency)\(Checkout.shared.customeAmount)", numberOfLines: 1)
        
        //SET VIEW
        self.viewCloseCustomeValue.backgroundColor = .primary
        self.viewCloseCustomeValue.viewCorneRadius(radius: 0, isRound: true)
        imgColor(imgColor: self.imgCloseCustomeValue, colorHex: .backgroundView)
        
        self.lblTotlaAmount.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.strTotalAmount, numberOfLines: 1)
        self.lblTotlaAmountPrice.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(Application.currency)\(Checkout.shared.total.stringValue)", numberOfLines: 1)

        
        //CHECKOUT VIEW
        self.con_Checkout.constant = manageWidth(size: 45.0)
        self.viewCheckout.backgroundColor = .secondaryTextView
        self.lblCheckout.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strCheckOut)

        
        //SET HEADER
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            //SET TABLE HEADER
            let vw_Table = self.tblView.tableFooterView
            vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.viewCheckout.frame.origin.y + self.viewCheckout.frame.size.height + 20)

            self.tblView.tableFooterView = vw_Table
        }
    }
}


//MARK: - BUTTON ACTION
extension CheckOutViewController {
    
    @IBAction func btnPaymentClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        //MOVE TO CHECKOUT SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "PaymentViewController") as? PaymentViewController{
            newViewController.arrStates = self.arrStates
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
        
    }
}

//MARK: - BUTTON ACTION
extension CheckOutViewController{
    @IBAction func btnRemoveCustomAmountClicked(_ sender: UIButton) {
        Checkout.shared.customeAmount = 0.0
        Checkout.shared.taxCharge = Checkout.shared.taxCharge - self.customAmountTaxePrice

        //SET FONT
        self.setFooter()
    }
}

//MARK: -- UITABEL CELL --
class CartListCell : UITableViewCell{
    @IBOutlet weak var con_imgHeight: NSLayoutConstraint!
    @IBOutlet weak var imgProduct: UIImageView!
    @IBOutlet weak var lblProductName: UILabel!
    @IBOutlet weak var lblTotlaPrice: UILabel!
    @IBOutlet weak var lblScheduleDate: UILabel!
    
    @IBOutlet weak var objPrice: UIStackView!
    @IBOutlet weak var lblPrice: UILabel!
    @IBOutlet weak var lblPriceTotal: UILabel!
    
    @IBOutlet weak var objDistances: UIStackView!
    @IBOutlet weak var lblDistances: UILabel!
    @IBOutlet weak var lblDistancesPrice: UILabel!
    @IBOutlet weak var lblDistancesValues: UILabel!

    
    @IBOutlet weak var objOptions: UIStackView!
    @IBOutlet weak var lblOptions: UILabel!
    @IBOutlet weak var lblOptionsPrice: UILabel!
    @IBOutlet weak var lblOptionsValues: UILabel!

    @IBOutlet weak var objButtons: UIStackView!
    @IBOutlet weak var viewRemove: UIView!
    @IBOutlet weak var imgRemove: UIImageView!
    @IBOutlet weak var lblRemove: UILabel!
    @IBOutlet weak var btnRemove: UIButton!
    
    @IBOutlet weak var viewUpdate: UIView!
    @IBOutlet weak var btnUpdate: UIButton!
    
    //STORE ADSRESS
    @IBOutlet weak var imgDelivery: UIImageView!
    @IBOutlet weak var lblDelivery: UILabel!
    
    @IBOutlet weak var imgPickup: UIImageView!
    @IBOutlet weak var lblPickup: UILabel!


    @IBOutlet weak var viewLine: UIView!

    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            imgProduct,
            lblProductName,
//            lblTotlaPrice,
//            lblScheduleDate,
            lblPrice,
            lblPriceTotal,
            lblOptions,
            lblOptionsPrice,
            lblOptionsValues,
//            lblRemove
//            imgStore,
//            lblStoreAddress
        ]
    }
}

//MARK: -- UITABEL DELEGATE --

extension CheckOutViewController : UITableViewDelegate, UITableViewDataSource{

    
    //HEADER SECTION
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isLoading{
            return 5
        }
        
        else{
            return Checkout.shared.cart.count

        }
       
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
      
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "CartListCell") as? CartListCell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.backgroundColor = .clear
            
            if isLoading {
                self.checkOutPlaceholderMarker.register(cell.getAnimableSubviews())
                self.checkOutPlaceholderMarker.startAnimation()
                return cell
            }
            
            let  objDetails = Checkout.shared.cart[indexPath.row]
            

            //SET IMAG
            cell.viewLine.backgroundColor = .lightGray
            cell.con_imgHeight.constant = manageWidth(size: 70)
            cell.imgProduct.viewCorneRadius(radius: 5, isRound: false)
            cell.imgProduct.setImage(strImg: objDetails.product.image ?? "")
            cell.imgProduct.backgroundColor = .white

            let getPrice = getProductTotlaPrice(productID: objDetails.product.id ?? 0)

        
            //SET FONT
            cell.lblProductName.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "\(objDetails.product.name ?? "") * \(objDetails.product.qty )")
            cell.lblTotlaPrice.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "\(Application.currency)\((getPrice.0).stringValue)")
            
            
            //SET SCHEDULE DATE
            let strDate = setFontAttributes(str: str.sttScheduleDate, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0)
            strDate.append(setFontAttributes(str: " \(objDetails.product.selectDate )", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0))
            cell.lblScheduleDate.attributedText = strDate

            
            //CHECK OPTION
            cell.objPrice.isHidden = true
            cell.objOptions.isHidden = true
            if checkOptionActive(arrOptions: objDetails.product.options){
                cell.objPrice.isHidden = false
                cell.objOptions.isHidden = false
            }

            //SET OPTIONS VALUE
            cell.lblOptionsValues.text = ""
            if objDetails.product.options.count != 0{
                
                cell.lblPrice.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: str.strPrice)
                cell.lblPriceTotal.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "\(Application.currency)\((getPrice.1).stringValue)")

                
                cell.lblOptions.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: str.strOptionsTotal)
                cell.lblOptionsPrice.configureLable(textAlignment: .right, textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "\(Application.currency)\((getPrice.2).stringValue)")

                //SET OPTION VALUE
                var strValues : String = ""
                for arrOptios in objDetails.product.options{
                    for valude in arrOptios.values{
                        if valude.type == true{
                            if strValues == ""{
                                strValues = "- \(valude.option_value ?? "")"
                            }
                            else{
                                strValues = "\(strValues)\n- \(valude.option_value ?? "")"
                            }
                        }
                    }
                }
                
                cell.lblOptionsValues.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: strValues)
            }
       
            //SET BUTTONS
            cell.viewRemove.backgroundColor = .clear
            cell.viewRemove.viewCorneRadius(radius: 5.0, isRound: false)
            cell.viewRemove.viewBorderCorneRadius(borderColour: .secondaryView)
            
            cell.viewUpdate.backgroundColor = .secondaryView
            cell.viewUpdate.viewCorneRadius(radius: 5.0, isRound: false)

            imgColor(imgColor: cell.imgRemove, colorHex: .secondaryView)
            cell.lblRemove.configureLable(textColor: .secondaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strRemove)
            
            cell.btnUpdate.configureLable(bgColour: .clear, textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strUpdate)

            
            //BUTTON ACTION
            cell.btnRemove.tag = indexPath.row
            cell.btnRemove.addTarget(self, action: #selector(btnRemoveClicked(_:)), for: .touchUpInside)

            cell.btnUpdate.tag = indexPath.row
            cell.btnUpdate.addTarget(self, action: #selector(btnUpdateClicked(_:)), for: .touchUpInside)

            
            return cell
        }

        return UITableViewCell()
        
    }
    
   
    @objc func btnRemoveClicked(_ sender: UIButton){
        let objDate = Checkout.shared.cart[sender.tag].product

        //CALL API
        let alert = UIAlertController(title: Application.appName, message: "Are you sure you want to remove \(objDate.name ?? "")?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
            
            //REMOVE ITEM
            Checkout.shared.removeProductFromCart(product: objDate)

            //CHECK ITEMS
            if Checkout.shared.cart.count == 0{
                //BACK SCREE
                self.navigationController?.popViewController(animated: true)
            }
            else{
                //RELOAD
                self.tblView.reloadData()
            }

       
        }))
        alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @objc func btnUpdateClicked(_ sender: UIButton){
        
        //MOVE TO PRODUCT SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ProductDetailsViewController") as? ProductDetailsViewController{
            newViewController.isUpdateProduct = true
            newViewController.objData = Checkout.shared.cart[sender.tag].product

            let vieweNavigationController = UINavigationController(rootViewController: newViewController)
            self.present(vieweNavigationController, animated: true)
        }
    }
    

    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
      
    }
    
    
    
  

}


extension CheckOutViewController{
    func setFontAttributes(str : String, fontName: String , fontSize: Double) -> NSMutableAttributedString{
        let yourAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.primary ,
            .font: SetTheFont(fontName: fontName, size: fontSize),
        ]

        
        let attributeString = NSMutableAttributedString(
            string: str,
            attributes: yourAttributes
        )

        return attributeString
    }
    
    func checkOptionActive(arrOptions : [ProductOptionsModel]) ->Bool{
        for obj in arrOptions{
            for objValude in obj.values{
                if objValude.type == true{
                    return true
                }
            }
        }
        return false
    }
    
    func getProductTotlaPrice(productID : Int) -> (Double, Double, Double){
        if productID != 0{
            if let index = Checkout.shared.cart.firstIndex(where: { $0.product.id == productID }){
                
                let cartItem = Checkout.shared.cart[index]
                //GET PRICE
                let itemPrice = (cartItem.product.price ?? 0) * Float(cartItem.product.qty)
                
                //GET OPTIONS PRICES
                var optionsPrice : Double = 0.0
                for arrOptios in cartItem.product.options{
                    for valude in arrOptios.values{
                        if valude.type == true{
                            optionsPrice = optionsPrice + Double((valude.price ?? 0.0))
                        }
                    }
                }
                
                return ((Double(itemPrice) + (optionsPrice * Double(cartItem.product.qty))), Double(itemPrice), optionsPrice)
                
            }
        }
        return (0, 0, 0)
    }
}






