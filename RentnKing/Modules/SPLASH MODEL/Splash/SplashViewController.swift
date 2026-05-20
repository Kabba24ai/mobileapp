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
        
        //MOVE TO TABBAR
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TABBAR, bundle: nil)
        let tabBariewController = storyBoard.instantiateViewController(withIdentifier: "TabbarViewController") as! TabbarViewController
        GlobalMainConstants.appDelegate?.window?.rootViewController = tabBariewController
        GlobalMainConstants.appDelegate?.window?.makeKeyAndVisible()
    }
}
