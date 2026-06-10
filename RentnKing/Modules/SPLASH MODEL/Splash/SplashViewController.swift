//
//  SplashViewController.swift
//  Kabba Extension
//
//  Created by Jigar Khatri on 07/10/23.
//

import UIKit

class SplashViewController: UIViewController {
    
    //DECLARE VARIABLE
    @IBOutlet weak var objIndicator : UIActivityIndicatorView!

    
    override func viewDidLoad() {
        super.viewDidLoad()


        // Do any additional setup after loading the view.
        
        self.objIndicator.startAnimating()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0){
            self.moveToHomeScreen()
        }
        
        //GET CATEGORY LIST DATA
        callAPIforCategoryList(CatrgoryParameater: CatrgoryParameater()) { _ in
        }
        
        callAPIforCustomerTagList() { _ in
        }
    
        getPriceListAPI(completion: {_ in})
    }
    
    
    override func viewWillAppear(_ animated: Bool) {

        //SET VIEW
        self.view.backgroundColor = .background

        //SET PORTRAIT MODE
        AppUtility.PortraitMode()
        
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        self.tabBarController?.tabBar.isHidden = true
    
    }
    
    
    func moveToHomeScreen(){
        self.objIndicator.stopAnimating()
        
        if UserDefaults.standard.user != nil && UserDefaults.standard.accessToken != nil && UserDefaults.standard.baseURL != nil && UserDefaults.standard.baseURL != ""{
            //MOVE TO TABBAR
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TABBAR, bundle: nil)
            let tabBariewController = storyBoard.instantiateViewController(withIdentifier: "TabbarViewController") as! TabbarViewController
            GlobalMainConstants.appDelegate?.window?.rootViewController = tabBariewController
            GlobalMainConstants.appDelegate?.window?.makeKeyAndVisible()
        }
        else{
//            UserDefaults.standard.baseURL = ""
            
            //MOVE SCHEDULE SCREEN
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.LOGIN_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "LoginViewController") as? LoginViewController{
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
    }
    
    
    
}
