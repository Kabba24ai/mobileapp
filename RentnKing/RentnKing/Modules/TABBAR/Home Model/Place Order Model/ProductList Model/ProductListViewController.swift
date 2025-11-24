//
//  ProductListViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 13/01/24.
//

import UIKit

class ProductListViewController: UIViewController, UIGestureRecognizerDelegate {

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!
    @IBOutlet weak var viewSearch: UIView!
    @IBOutlet weak var imgSearch: UIImageView!
    @IBOutlet weak var txtSearch: UITextField!
    @IBOutlet weak var con_Search: NSLayoutConstraint!
    @IBOutlet var emptyDataView : EmptyDataView!{
        didSet{
            emptyDataView.noDataFound()
            emptyDataView.isHidden = true
        }
    }
    
    //LOADING
    let productPlaceholderMarker = Placeholder()

    //OTHER
    var isLoading : Bool = true
    var objCategory : CategoryModel!
    
    var arrProductList : [ProductModel] = []
    var isSearch : Bool = false
    
    
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
        
        //SET NAVIGATION BAR
        
        setNavigationBarFor(controller: self, title: self.isSearch ? str.strSearchProduct : self.objCategory.name ?? "", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "icon_cart_shopping", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {
            
            //MOVE TO CHECKOUT SCREEN
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckOutViewController") as? CheckOutViewController{
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
        
        
        //GET DATA
        self.viewSearch.isHidden = true
        self.con_Search.constant = 0
        if self.isSearch == false{
            self.getProductList(ProductParameater: ProductParameater(category_id: "\(self.objCategory.id ?? 0)") )
        }
        else{
            //SET THE VIEW
            self.setSearchView()
        }
        
    }
    
    
    func setTheView(){
      
        //CHECK SEARCH
        self.viewSearch.isHidden = true
        self.con_Search.constant = 0
        if self.isSearch {
            self.viewSearch.isHidden = false
            self.con_Search.constant = 40
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            //STOP LOADING
            self.stopLoading()
            self.isLoading = false
            self.emptyDataView.isHidden = true
            if self.arrProductList.count == 0{
                self.emptyDataView.isHidden = false
            }
       
            //RELOAD DATA
            self.tblView.reloadData()
        }
    }
    
    func stopLoading(){
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.productPlaceholderMarker.remove()
        }
        indicatorHide()
    }

    
    func setSearchView(){
        
        //SET THE VIEW
        self.viewSearch.backgroundColor = .clear
        self.viewSearch.viewBorderCorneRadius(borderColour: .secondary)
        self.viewSearch.viewCorneRadius(radius: 10.0, isRound: false)
        imgColor(imgColor: self.imgSearch, colorHex: .secondary)
        
        self.txtSearch.configureText(bgColour: UIColor.clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: "", placeholder: str.strSearch)
        self.txtSearch.clearButtonMode = .whileEditing
        self.txtSearch.text = ""
        if let clearButton = txtSearch.value(forKey: "_clearButton") as? UIButton{
            let templateImage =  clearButton.imageView?.image?.withRenderingMode(.alwaysTemplate)
            // Set the template image copy as the button image
            clearButton.setImage(templateImage, for: .normal)
            // Finally, set the image color
            clearButton.tintColor = .gray
        }
        
        //SET SEARCH TEXT
        self.txtSearch.becomeFirstResponder()
        self.txtSearch.addTarget(self, action: #selector(textFieldDidChangeSearch), for: .editingChanged)
        
        //CHECK SEARCH
        self.viewSearch.isHidden = true
        self.con_Search.constant = 0
        if self.isSearch {
            self.viewSearch.isHidden = false
            self.con_Search.constant = 40
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            //STOP LOADING
            self.stopLoading()
            self.isLoading = false
            self.emptyDataView.isHidden = true
       
            //RELOAD DATA
            self.tblView.reloadData()
        }
        
    }
    
    // MARK: - UITEXTFIELD
    @objc func textFieldDidChangeSearch() {
    
        let strSearch = self.txtSearch.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        
        if strSearch.count >= 3{
            //GET  DATA
            self.isLoading = true
            self.arrProductList = []
            self.tblView.reloadData()
            self.getProductSearchList(ProductSearchParameater: ProductSearchParameater(product_search: strSearch))

        }
    }
}



//MARK: -- TABLE CELL --
class ProductListCell : UITableViewCell{
    @IBOutlet weak var con_imgHeight: NSLayoutConstraint!
    @IBOutlet weak var imgProduct: UIImageView!
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var lblPrice: UILabel!
    @IBOutlet weak var btnReadMore: UIButton!
    @IBOutlet weak var viewReadMore: UIView!

    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            imgProduct,
            lblName,
            lblPrice,
            btnReadMore,
            viewReadMore
        ]
    }
}


//MARK: -- TABLE CELL --

//MARK:: UITableViewDelegate, UITableViewDataSource
extension ProductListViewController: UITableViewDelegate, UITableViewDataSource {
  
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isLoading{
            return 20
        }
        else{
            return  self.arrProductList.count
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "ProductListCell") as? ProductListCell{
            cell.backgroundColor = UIColor.clear
            cell.con_imgHeight.constant = manageWidth(size: 140)
            cell.imgProduct.viewCorneRadius(radius: 5, isRound: false)
            cell.viewReadMore.backgroundColor = .clear
            
            if isLoading {
                self.productPlaceholderMarker.register(cell.getAnimableSubviews())
                self.productPlaceholderMarker.startAnimation()
                return cell
            }
            
            //GET DETAILS
            let objData = self.arrProductList[indexPath.row]
            
            //SET DETAILS
            cell.lblName.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 18.0, text: objData.name ?? "")
            cell.lblPrice.configureLable(textColor: .primaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "\(Application.currency)\(objData.price?.stringValue ?? "")")

            cell.btnReadMore.configureLable(bgColour: .clear, textColor: .secondaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: " \(str.strReserveNow) ")
            cell.viewReadMore.viewCorneRadius(radius: 5, isRound: false)
            cell.viewReadMore.viewBorderCorneRadius(borderColour: .secondaryView)
            
            //SET IMG
            cell.imgProduct.setImage(strImg: self.arrProductList[indexPath.row].image ?? "")
            cell.imgProduct.backgroundColor = .white
            
            // BUTTON ACTION
            cell.btnReadMore.tag = indexPath.row
            cell.btnReadMore.addTarget(self, action: #selector(self.btnReadMoreClicked(_:)), for: .touchUpInside)

                    
            cell.layoutIfNeeded()
            return cell
        }

        return UITableViewCell()
    }
  
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    }
    
    @objc func btnReadMoreClicked(_ sender : UIButton) {
        if self.arrProductList.count == 0 {
            return
        }
        
        //MOVE TO CHECKOUT SCREEN
        
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ProductDetailsViewController") as? ProductDetailsViewController{
            newViewController.objData = self.arrProductList[sender.tag]
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
}
