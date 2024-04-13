//
//  ProductDetailsViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 16/01/24.
//

import UIKit
import ObjectMapper


class ProductDetailsViewController: UIViewController, UIGestureRecognizerDelegate {
   

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!

    @IBOutlet weak var con_imgHeight: NSLayoutConstraint!
    @IBOutlet weak var imgProduct: UIImageView!

    @IBOutlet weak var viewPrice: UIView!
    @IBOutlet weak var lblPrice: UILabel!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var lblDetails: UILabel!

    
    @IBOutlet weak var lblSelectTitle: UILabel!
    @IBOutlet weak var viewSelectDate: UIView!
    @IBOutlet weak var lblSelectData: UILabel!

    @IBOutlet weak var addToCartBUtton: AddToCartButton!

    @IBOutlet weak var con_AddCart: NSLayoutConstraint!
    @IBOutlet weak var viewAddCart: UIView!
    @IBOutlet weak var imgAddCart: UIImageView!
    @IBOutlet weak var lblAddCart: UILabel!
    
    //DELIVERY OPTIONS
    @IBOutlet weak var lblDeliveryOptions: UILabel!
    @IBOutlet weak var objDeliveryOptions: UIStackView!

    @IBOutlet weak var objWantDelivery: UIStackView!
    @IBOutlet weak var lblWantDelivery: UILabel!
    @IBOutlet weak var imgWantDelivery: UIImageView!
    
    @IBOutlet weak var viewDelivery: UIView!
    @IBOutlet weak var imgDeliveryItem: UIImageView!
    @IBOutlet weak var lblDeliveryItem: UILabel!
    
    @IBOutlet weak var imgPickupItem: UIImageView!
    @IBOutlet weak var lblPickupItem: UILabel!

    
    @IBOutlet weak var objWillPickup: UIStackView!
    @IBOutlet weak var lblWillPickup: UILabel!
    @IBOutlet weak var imgWillPickup: UIImageView!

    @IBOutlet weak var viewPickup: UIView!
    @IBOutlet weak var viewStore: UIView!
    @IBOutlet weak var txtStore: UITextField!

    var selectWillPickup : Bool = false

    
    var selectWantDelivery : Bool = false
    var SelectDeliveryUpto: Bool = false
    var SelectPickupUpto: Bool = false
    var selectStore : Bool = false
    var storeID : String = ""

    @IBOutlet var emptyDataView : EmptyDataView!{
        didSet{
            emptyDataView.noDataFound()
            emptyDataView.isHidden = true
        }
    }

    
    //LOADING
    let productDetailsPlaceholderMarker = Placeholder()
    var isUpdateProduct : Bool = false
    
    //OTHER
    var isLoading : Bool = true
    var objData : ProductModel!
    var arrStoreList :[StoreModel] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        
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
        
        //GET PODUCT DATA
        if let index = Checkout.shared.cart.firstIndex(where: { $0.product.id == self.objData.id }){
            self.objData = Checkout.shared.cart[index].product
            
            
            if objData.delivery == true || objData.pickup == true{
                self.selectWantDelivery = true
                self.SelectDeliveryUpto = objData.delivery ?? false
                self.SelectPickupUpto = objData.pickup ?? false
                
                if objData.storeID != ""{
                    self.selectWillPickup = true
                    
                    let MenuID = self.arrStoreList.map{$0.id}
                    if let index = MenuID.firstIndex(of: Int(objData.storeID )){
                        
                        self.txtStore.text = self.arrStoreList[index].fullAddress
                        self.storeID = objData.storeID 
                    }
                }
            }
            else{
                if objData.storeID != ""{
                    self.selectWillPickup = true
                    
                    let MenuID = self.arrStoreList.map{$0.id}
                    if let index = MenuID.firstIndex(of: Int(objData.storeID )){
                        
                        self.txtStore.text = self.arrStoreList[index].fullAddress
                        self.storeID = objData.storeID 
                    }
                }
            }
            
            //UPDATE DATA
            self.setDetails()

        }
        else if self.isUpdateProduct == false{
            self.isLoading = true
            self.selectWantDelivery = false
            self.SelectDeliveryUpto = false
            self.SelectPickupUpto = false
            self.selectStore = false
            
            self.getProductList(ProductParameater: ProductParameater(product_id: "\(self.objData.id ?? 0)"))
            
            
        }
        else {
            self.setDetails()
        }
        
        //SET NAVIGATION BAR
        setNavigationBarFor(controller: self, title: self.objData.name ?? "", isTransperent: true, hideShadowImage: true, leftIcon: self.isUpdateProduct ? "icon_closeSmall" : "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            if self.isUpdateProduct{
                self.dismiss(animated: true)
            }
            else{
                self.navigationController?.popViewController(animated: true)
            }
        } rightActionHandler: {
            
        }

        //GET STORE LIST
        self.getStoreAddress()
        
        //SET THE VIEW
        self.setTheView()
        
        //RELOAD TABLE
        self.tblView.reloadData()
    }
    
    
    func setTheView(){

        //SET IMAEGE
        self.con_imgHeight.constant = manageWidth(size: 140)
        self.imgProduct.viewCorneRadius(radius: 5, isRound: false)

      
        //SET VIEW
        self.viewPrice.backgroundColor = .secondaryTextView
        self.viewPrice.viewCorneRadius(radius: 5.0, isRound: false)
       
        self.viewSelectDate.backgroundColor = .clear
        self.viewSelectDate.viewCorneRadius(radius: 5.0, isRound: false)
        
        //SET ADD BUTTO
        self.addToCartBUtton.delegate = self
        self.addToCartBUtton.maxLimit = 100000
        
        //CHECK QUNTIRY
        self.addToCartBUtton.count = self.objData.qty
        self.addToCartBUtton.isSoldOut = false
        

        
        //SET FONT
        self.lblSelectTitle.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Light, fontSize: 14.0, text: "")
        
        self.lblSelectData.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: str.strSelectData)
        if self.objData.selectDate.lowercased() != str.strSelectData.lowercased() && self.objData.selectDate != ""{
            self.lblSelectData.text = self.objData.selectDate
        }

        self.lblAddCart.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.addCart)

        //SET FOOTER
        self.setFooter()
    }
    
    func setDetails(){
        self.isLoading = false
        self.productDetailsPlaceholderMarker.remove()

        //SET TABLE
        self.tblView.isHidden = false
        self.tblView.reloadData()
        
        //SET VIEW
        self.viewSelectDate.viewBorderCorneRadius(borderColour: .secondaryView)

        //SET CART VIEW
        self.con_AddCart.constant = manageWidth(size: 45.0)
        self.viewAddCart.backgroundColor = .secondaryTextView
        imgColor(imgColor: self.imgAddCart, colorHex: .backgroundView)
        
        //SET FONT
        if self.objData != nil{
            self.lblName.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: self.objData.name ?? "")

            self.lblPrice.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 22.0, text: "\(Application.currency)\(self.objData.price?.stringValue ?? "")")
            self.lblPrice.textAlignment = .center
    
            self.lblDetails.text = ""
//            self.lblDetails.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: "\(self.objData.description?.html2String ?? "")")
            
            
            //SET IMG
            self.imgProduct.setImage(strImg: self.objData.image ?? "")
            self.imgProduct.backgroundColor = .white
        }
        
        
        //SET HEADER
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            //SET TABLE HEADER
            let vw_Table = self.tblView.tableHeaderView
            vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.lblDetails.frame.origin.y + self.lblDetails.frame.size.height)

            self.tblView.tableHeaderView = vw_Table
        }
    }
    
    func setFooter(){
        if self.objData.store_pickup == 0 && self.objData.delivery_pickup == 0{
            self.objDeliveryOptions.isHidden = true
            self.lblDeliveryOptions.text = ""
        }
        else{
            self.objDeliveryOptions.isHidden = false
            self.lblDeliveryOptions.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.deliveryOptions)
            self.lblWantDelivery.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.wantToDelivery)
            self.lblWillPickup.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: str.willPickup)

            
            
            //CHECK DELIVERY VIEW
            self.objWantDelivery.isHidden = true
            if self.objData.delivery_pickup == 1{
                self.objWantDelivery.isHidden = false
                
                self.viewDelivery.isHidden = !self.selectWantDelivery
                self.imgWantDelivery.image = UIImage(named: self.selectWantDelivery ? "icon_Check" : "icon_unCheck")
                if self.selectWantDelivery{
                    if self.SelectPickupUpto == false && self.SelectDeliveryUpto == false{
                        self.selectWantDelivery = false
                        self.viewDelivery.isHidden = true
                        self.imgWantDelivery.image = UIImage(named: "icon_unCheck")

                    }
                }
                imgColor(imgColor: self.imgWantDelivery, colorHex: .secondary)

                
                //SET FONT
                let strDelivery = setFontAttributes(str: "Delivery - Up to \(self.objData.delivery_range ?? 0) Miles : ", fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0)
                strDelivery.append(setFontAttributes(str: "+$\(self.objData.delivery_price ?? 0)", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0))
                self.lblDeliveryItem.attributedText = strDelivery

                
                let strPickup = setFontAttributes(str: "Pickup - Up to \(self.objData.delivery_range ?? 0) Miles : ", fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0)
                strPickup.append(setFontAttributes(str: "+$\(self.objData.delivery_price ?? 0)", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0))
                self.lblPickupItem.attributedText = strPickup
                
                //SET IMAGE
                self.imgDeliveryItem.image = UIImage(named: self.SelectDeliveryUpto ? "icon_Check" : "icon_unCheck")
                imgColor(imgColor: self.imgDeliveryItem, colorHex: .secondary)

                self.imgPickupItem.image = UIImage(named: self.SelectPickupUpto ? "icon_Check" : "icon_unCheck")
                imgColor(imgColor: self.imgPickupItem, colorHex: .secondary)

                //UPDATE PICKU AND DELIVERY DATA
                self.updateDeliveryAndPickupData(isPickupAdd: self.SelectPickupUpto, isDeliveryAdd: self.SelectDeliveryUpto, strPrice: self.objData.delivery_price ?? 0.0)

            }
            
            //CEHCK WILL PICKUP
            self.objWillPickup.isHidden = true
            if self.objData.store_pickup == 1{
                self.objWillPickup.isHidden = false
                
                self.viewPickup.isHidden = !self.selectWillPickup
                self.imgWillPickup.image = UIImage(named: self.selectWillPickup ? "icon_Check" : "icon_unCheck")
                imgColor(imgColor: self.imgWillPickup, colorHex: .secondary)

                self.txtStore.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "", placeholder: "Select Store")
                
                self.viewStore.backgroundColor = .clear
                self.viewStore.viewBorderCorneRadius(borderColour: .secondary)
                self.viewStore.viewCorneRadius(radius: 5, isRound: false)
            }
            
            

        }
     
        
        //SET HEADER
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            //SET TABLE HEADER
            let vw_Table = self.tblView.tableFooterView
            vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.objDeliveryOptions.frame.origin.y + self.objDeliveryOptions.frame.size.height + 20)

            self.tblView.tableFooterView = vw_Table
            
        }
       

    }
}


extension ProductDetailsViewController : AddToCartButtonDelegate{
    func itemAddedAtIndexPath(_ indexPath: IndexPath, count: Int) {
        
        print(count)
        //UPDATE DATA
        self.objData.qty = count
    }
    
    func itemRemovedAtIndexPath(_ indexPath: IndexPath, count: Int) {
        print(count)
        //UPDATE DATA
        self.objData.qty = count
    }
}


//MARK: - BUTTON ACTION
extension ProductDetailsViewController {
    @IBAction func btnWantToDelveryClicked(_ sender: UIButton) {
        if self.selectWantDelivery{
            self.selectWantDelivery = false
            self.SelectDeliveryUpto = false
            self.SelectPickupUpto = false
        }
        else{
            self.selectWantDelivery = true
            self.SelectDeliveryUpto = true
            self.SelectPickupUpto = true
            self.selectWillPickup = false
            self.storeID = ""
        }
        
        
        //SET FOOTER
        self.setFooter()
    }
    
    @IBAction func btnDelveryUpClicked(_ sender: UIButton) {
        if self.selectWillPickup{
            return
        }
        
        if self.SelectDeliveryUpto{
            self.SelectDeliveryUpto = false
        }
        else{
            self.SelectDeliveryUpto = true
        }
        
        //SET FOOTER
        self.setFooter()
    }
    
    @IBAction func btnPickupUpClicked(_ sender: UIButton) {
        if self.SelectPickupUpto{
            self.SelectPickupUpto = false
        }
        else{
            self.SelectPickupUpto = true
        }
        
        //SET FOOTER
        self.setFooter()
    }
    
    @IBAction func btnWillPickupClicked(_ sender: UIButton) {
        if self.selectWillPickup{
            self.selectWillPickup = false
            self.txtStore.text = ""
            self.SelectDeliveryUpto = false
        }
        else{
            self.selectWillPickup = true
            self.SelectDeliveryUpto = false

        }
        
        //SET FOOTER
        self.setFooter()
    }
    
    @IBAction func btnSelectStoreClicked(_ sender: UIButton) {
        if self.arrStoreList.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: "Select Store", arrData: self.arrStoreList.compactMap { $0.fullAddress}, selectValue: self.txtStore.text ?? "") { index, selectValue in
           
            self.txtStore.text = selectValue
            self.storeID = "\(self.arrStoreList[index].id ?? 0)"

        }
        
    }
    
    @IBAction func btnSelectDateClicked(_ sender: UIButton) {
        
        actionDatePicker(sender, strTitle: str.strSelectData) { index, selectDate in
            self.lblSelectData.text = convertStringToNewFormateString(date: convertDateToString(date: selectDate, withFormat: Application.pickerDateFormet), withFormat: Application.pickerDateFormet, newFormate: Application.strDateFormet) ?? ""
            
            //SET DATE
            self.objData.selectDate = self.lblSelectData.text ?? ""
        }
    }
    
    @IBAction func btnAddToCartClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        //CHECK VALIDATION
        if self.lblSelectData.text?.lowercased() == str.strSelectData.lowercased(){
            showAlertMessage(strMessage: str.errorSelectDate)
        }else{
            if self.objData.store_pickup == 1{
                if self.selectWillPickup{
                    if self.storeID == ""{
                        showAlertMessage(strMessage: str.errorSelectStoreLocation)
                    }
                    else{
                        self.placeOrder()
                    }
                }
                else if self.SelectPickupUpto == false && self.SelectDeliveryUpto == false{
                    showAlertMessage(strMessage: str.errorSelectPickupDelivery)
                }
                else if self.SelectPickupUpto == false{
                    showAlertMessage(strMessage: str.errorSelectPickup)
                }
                else if self.SelectDeliveryUpto == false{
                    showAlertMessage(strMessage: str.errorSelectDelivery)
                }
                else{
                    self.placeOrder()
                }
            }
            else{
                self.placeOrder()

            }
        }
        
    }
    
    func placeOrder (){
        //ADD TO CART
        self.objData.storeID = self.storeID
        self.objData.pickup = self.SelectPickupUpto
        self.objData.delivery = self.SelectDeliveryUpto
        Checkout.shared.addProductToCart(product: self.objData) { status, product in

            if self.isUpdateProduct {
                self.dismiss(animated: true)
            }
            else{
                //MOVE TO CHECKOUT SCREEN
                let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
                if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckOutViewController") as? CheckOutViewController{
                    self.navigationController?.pushViewController(newViewController, animated: true)
                }
            }
        }
    }
    
    func updateDeliveryAndPickupData (isPickupAdd : Bool, isDeliveryAdd : Bool, strPrice : Float){
        
        //UPDATE PICKUP DATA
        if isPickupAdd{
            //SET EMPTY OBJECT
            let map = Map(mappingType: .fromJSON, JSON: [:])
            var objPickup = OptionsValueModel(map: map)
            objPickup?.option_value = "Pick Up"
            objPickup?.price = strPrice
            objPickup?.type = true
            objPickup?.isDisplay = false
            
            //UPDATE DELIVERY DATA
            let arrOptions = self.objData.options
            if arrOptions.count != 0{
                let MenuID = self.objData.options[0].values.map{$0.option_value}
                if MenuID.firstIndex(of: "Pick Up") == nil{
                    self.objData.options[0].values.append(objPickup!)
                }
            }
        }
        else{
            //REMOVE DELIVERY DATA
            let arrOptions = self.objData.options
            if arrOptions.count != 0{
                let MenuID = self.objData.options[0].values.map{$0.option_value}
                if let index = MenuID.firstIndex(of: "Pick Up"){
                    self.objData.options[0].values.remove(at: index)
                }
            }
        }
      
        
        
        //UPDATE DELIVERYT DATA
        if isDeliveryAdd{
            //SET EMPTY OBJECT
            let map = Map(mappingType: .fromJSON, JSON: [:])
            var objDelivery = OptionsValueModel(map: map)
            objDelivery?.option_value = "Delivery"
            objDelivery?.price = strPrice
            objDelivery?.type = true
            objDelivery?.isDisplay = false

            //UPDATE DELIVERY DATA
            let arrOptions = self.objData.options
            if arrOptions.count != 0{
                let MenuID = self.objData.options[0].values.map{$0.option_value}
                if MenuID.firstIndex(of: "Delivery") == nil{
                    self.objData.options[0].values.append(objDelivery!)
                }
            }
        }
        else{
            //REMOVE DELIVERY DATA
            let arrOptions = self.objData.options
            if arrOptions.count != 0{
                let MenuID = self.objData.options[0].values.map{$0.option_value}
                if let index = MenuID.firstIndex(of: "Delivery"){
                    self.objData.options[0].values.remove(at: index)
                }
            }
        }
    }
}




//MARK: -- UITABEL CELL --
class OptionsListCell : UITableViewCell{
    @IBOutlet weak var imgCheck: UIImageView!
    @IBOutlet weak var lblName: UILabel!
    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            imgCheck,
            lblName,
        ]
    }
}

//MARK: -- UITABEL DELEGATE --

extension ProductDetailsViewController : UITableViewDelegate, UITableViewDataSource, AleartDelegate{

    
    //HEADER SECTION
    func numberOfSections(in tableView: UITableView) -> Int {
        if isLoading{
            return 1
        }
        return self.objData.options.count
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let viewHeader = UIView()
        viewHeader.backgroundColor = UIColor.clear
        
        //SET LABLE HEADER
        let lblHeader = UILabel(frame: CGRect(x: 16, y: 0, width: CGFloat(GlobalMainConstants.windowWidth -  32), height: CGFloat(manageWidth(size: 40.0) )))
        lblHeader.textAlignment = .left
        
        //SET FONT
        lblHeader.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18, text: str.productOptions)
    
        viewHeader.addSubview(lblHeader)
        return viewHeader
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if isLoading{
            return 0
        }
        return manageWidth(size: 40.0)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isLoading{
            return 5
        }
        
        else{
            if self.objData != nil{
                let arrValue = self.objData.options[section].values
                var count : Int = 0
                for i in 0..<arrValue.count{
                    let obj = arrValue[i]
                    if obj.isDisplay{
                        count = count + 1
                    }
                }
                return count
            }
            else{
                return 0
            }
        }
       
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
      
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "OptionsListCell") as? OptionsListCell{
            cell.backgroundColor = UIColor.clear
            cell.imgCheck.image = UIImage(named: "")
            
            if isLoading {
                self.productDetailsPlaceholderMarker.register(cell.getAnimableSubviews())
                self.productDetailsPlaceholderMarker.startAnimation()
                return cell
            }
            
            let  objDetails = self.objData.options[indexPath.section].values[indexPath.row]
            

            //SET IMAG
            cell.imgCheck.image = UIImage(named: "icon_unCheck")
            if objDetails.type == true{
                cell.imgCheck.image = UIImage(named: "icon_Check")
            }
                
        
            //SET FONT
            let strName = setFontAttributes(str: "\(objDetails.option_value ?? "") : ", fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0)
            strName.append(setFontAttributes(str: "+$\(objDetails.price ?? 0)", fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0))
            cell.lblName.attributedText = strName

            
            return cell
        }

        return UITableViewCell()
        
    }
    
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
    
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let  objDetails = self.objData.options[indexPath.section].values[indexPath.row]
        
        //SET EMPTY OBJECT
        let map = Map(mappingType: .fromJSON, JSON: [:])
        var objValue = OptionsValueModel(map: map)
        objValue = objDetails
        
        if objDetails.value_type == true && objDetails.type == true{
            
            //OPTION POPUP
            let window = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
            window?.endEditing(true)
            let aleartView = AlertPopUp(frame: CGRect(x: 0, y: 0 ,width : window?.frame.width ?? 0.0, height: window?.frame.height ?? 0.0))
            aleartView.loadPopUpView(strMessage: objDetails.comment ?? "", strOptions: objDetails.option_value ?? "", section: indexPath.section, index: indexPath.row)
            aleartView.delegate = self
            window?.addSubview(aleartView)
            
        }
        else if objDetails.type == true{
            objValue?.type = false
        }
        else{
            objValue?.type = true
        }
        
        //UPDATE DATA
        self.objData.options[indexPath.section].values.remove(at: indexPath.row)
        self.objData.options[indexPath.section].values.insert(objValue!, at: indexPath.row)
        
        //RELOAD TABLE
        self.tblView.reloadData()
    }
    
    
    func SelectYes(section: Int, index: Int, amout: Double, isTax: Bool) {
        let  objDetails = self.objData.options[section].values[index]
        
        //SET EMPTY OBJECT
        let map = Map(mappingType: .fromJSON, JSON: [:])
        var objValue = OptionsValueModel(map: map)
        objValue = objDetails
        
        if objDetails.value_type == true && objDetails.type == true{
            objValue?.type = false
        }
        else{
            objValue?.type = true
        }
        
        //UPDATE DATA
        self.objData.options[section].values.remove(at: index)
        self.objData.options[section].values.insert(objValue!, at: index)
        
        //RELOAD TABLE
        self.tblView.reloadData()
    }
}


