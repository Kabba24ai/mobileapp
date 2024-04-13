//
//  OrderSuccessViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 30/01/24.
//

import UIKit

class OrderSuccessViewController: UIViewController {

    
    //CHECKOUT
    @IBOutlet weak var con_Home: NSLayoutConstraint!
    @IBOutlet weak var viewHome: UIView!
    @IBOutlet weak var lblHome: UILabel!

    @IBOutlet weak var viewTerms: UIView!
    @IBOutlet weak var lblTerms: UILabel!

    var orderID : String = ""
    var signUrl : String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        Checkout.shared.products = []
        Checkout.shared.cart = []
        Checkout.shared.customeAmount = 0
        // Do any additional setup after loading the view.
    }
    

    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        self.tabBarController?.tabBar.isHidden = true
      
        //SET VIEW
        self.strTheView()
    }
    
    
    func strTheView(){
        self.con_Home.constant = manageWidth(size: 45.0)
        
        //SET FONT
        self.lblHome.configureLable(textColor: .secondaryText, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "HOME", numberOfLines: 1)
        self.lblTerms.configureLable(textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Terms and Conditions", numberOfLines: 1)

        self.viewHome.backgroundColor = .clear
        self.viewTerms.backgroundColor = .secondaryText
        self.viewHome.viewBorderCorneRadius(borderColour: .secondaryText)
        
        //CEHCK VIEW
        self.viewTerms.isHidden = true
        if self.signUrl != ""{
            self.viewTerms.isHidden = false
        }
    }
}


//MARK: - BUTTON ACTION
extension OrderSuccessViewController {
    @IBAction func btnTermsConditionlicked(_ sender: UIButton) {
        if self.signUrl == "" || self.orderID == ""{
            return
        }
        
        
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "TermsAndConditionViewController") as? TermsAndConditionViewController{
            newViewController.signUrl = self.signUrl
            newViewController.orderID = self.orderID
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
        
    }
    
    @IBAction func btnHomeClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        //MOVE TO CHECKOUT SCREEN
        self.navigationController?.popToRootViewController(animated: true)

    }
}
