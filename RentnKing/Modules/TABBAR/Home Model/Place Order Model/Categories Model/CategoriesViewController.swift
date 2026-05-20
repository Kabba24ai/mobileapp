//
//  CategoriesViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 11/01/24.
//

import UIKit
import FontAwesome

class CategoriesViewController: UIViewController, UIGestureRecognizerDelegate {
    
    //DECLARE VARIABLE
    @IBOutlet weak var objCollectionView: UICollectionView!

    @IBOutlet weak var viewOrder: UIView!
    @IBOutlet weak var imgOrder: UIImageView!
    @IBOutlet weak var lblOrder: UILabel!
    
    @IBOutlet weak var viewProduct: UIView!
    @IBOutlet weak var imgProduct: UIImageView!
    @IBOutlet weak var lblProduct: UILabel!
    @IBOutlet var emptyDataView : EmptyDataView!{
        didSet{
            emptyDataView.noDataFound()
            emptyDataView.isHidden = true
        }
    }
    
    //LOADING
    let catrgoryPlaceholderMarker = Placeholder()

    //OTHER
    var isLoading : Bool = true

    var arrCategorys : [CategoryModel] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        
    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()

        
        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true
        
        //SET NAVIGATION BAR
        setNavigationBarForButtons(controller: self, title: str.strScheduleTitle, isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: ["icon_cart_shopping", "icon_Search"], isFilter: false) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {sender, SelectTag  in
        
            if SelectTag == 1{
                //SEARCH
                let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
                if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ProductListViewController") as? ProductListViewController{
                    newViewController.isSearch = true
                    self.navigationController?.pushViewController(newViewController, animated: true)
                }

            }
            else{
                
                //MOVE TO CHECKOUT SCREEN
                let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
                if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CheckOutViewController") as? CheckOutViewController{
                    self.navigationController?.pushViewController(newViewController, animated: true)
                }
            }
        }
        
        //GET DATA
        self.getCategorys()
        
    }

    func setTheView(){
        
        //SET IMG
        imgColor(imgColor: self.imgOrder, colorHex: .secondary)
        imgColor(imgColor: self.imgProduct, colorHex: .secondary)
        
        
        //SET FONT
        self.lblOrder.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strOrders)
        self.lblProduct.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strProducts)


        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            //STOP LOADING
            self.stopLoading()
            self.isLoading = false
            
            //SET VIEW
            self.viewOrder.backgroundColor = .clear
            self.viewOrder.viewBorderCorneRadius(borderColour: .secondary)
            self.viewOrder.viewCorneRadius(radius: 15, isRound: false)
            
            self.viewProduct.backgroundColor = .clear
            self.viewProduct.viewBorderCorneRadius(borderColour: .secondary)
            self.viewProduct.viewCorneRadius(radius: 15, isRound: false)
            
            //RELOAD DATA
            self.objCollectionView.reloadData()
        }
        
    }
    
    func stopLoading(){
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.catrgoryPlaceholderMarker.remove()
        }
        indicatorHide()
    }
}


//MARK: - BUTTON ACTION
extension CategoriesViewController {
    @IBAction func btnOrderListClicked(_ sender: UIButton) {
//        //MOVE ORDERS SCREEN
//        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
//        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ImageUploadViewController") as? ImageUploadViewController{
//            self.navigationController?.pushViewController(newViewController, animated: true)
//        }
//        
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderListViewController") as? OrderListViewController{
            self.navigationController?.pushViewController(newViewController, animated: true)
        }

    }
}



class CategoryCell: UICollectionViewCell {
    @IBOutlet weak var con_imgCategory: NSLayoutConstraint!
    @IBOutlet weak var imgCategory: UIImageView!
    @IBOutlet weak var imgAdd: UIImageView!

    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var viewBG: UIView!
    @IBOutlet weak var btnSelect: UIButton!

    @IBOutlet weak var viewCloseMain: UIView!
    @IBOutlet weak var viewClose: UIView!
    @IBOutlet weak var btnClose: UIButton!

    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            imgCategory,
            lblName
            
        ]
    }
}



//MARK: - Collection View -
extension CategoriesViewController : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout{
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if isLoading{
            return 20
        }
        else{
            return  self.arrCategorys.count
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 30, bottom: 0, right: 30)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 10
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {

        
        return CGSize(width: (collectionView.frame.size.width - CGFloat(70)) / 2 , height: ((collectionView.frame.size.width - CGFloat(70)) / 2)  + manageWidth(size: 20))

    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell  = collectionView.dequeueReusableCell(withReuseIdentifier: "CategoryCell", for: indexPath) as! CategoryCell
        cell.backgroundColor = UIColor.clear
        cell.viewBG.backgroundColor = .clear

        //SET IMG
//        cell.imgCategory.viewCorneRadius(radius: 15, isRound: false)

        if isLoading{
            self.catrgoryPlaceholderMarker.register(cell.getAnimableSubviews())
            self.catrgoryPlaceholderMarker.startAnimation()
            return cell
        }
        
        //SET VIEW
        cell.viewBG.viewCorneRadius(radius: 15, isRound: false)
        cell.viewBG.viewBorderCorneRadius(borderColour: .secondaryView)
//        cell.imgCategory.roundCornersView(onTopLeft: true, topRight: true, bottomLeft: false, bottomRight: false, radius: 15)
        
        //SET IMG
        cell.imgCategory.setImage(strImg: self.arrCategorys[indexPath.row].image ?? "")
        cell.imgCategory.backgroundColor = .white
        
        //SET TITLE AND TIME
        cell.lblName.configureLable(textAlignment: .center, textColor: .secondaryView, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: self.arrCategorys[indexPath.row].name ?? "")
        
      
        return cell
        
        
    }
    
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if self.arrCategorys.count == 0{
            return
        }
        
        //MOVE TO DETAILS SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ProductListViewController") as? ProductListViewController{
            newViewController.objCategory = self.arrCategorys[indexPath.row]
            self.navigationController?.pushViewController(newViewController, animated: true)
        }

    }
}

