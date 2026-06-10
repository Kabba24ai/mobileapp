//
//  SettingViewController.swift
//  Kabba Extension
//
//  Created by Jigar Khatri on 07/10/23.
//

import UIKit

class SettingViewController: UIViewController, UIGestureRecognizerDelegate, NavigationDelegate {
    func selectSearch() {
        
    }
    @IBOutlet weak var lblName : UILabel!
    @IBOutlet weak var lblEmail : UILabel!

    @IBOutlet weak var viewLogOut : UIView!
    @IBOutlet weak var btnLogOut : UIButton!
    @IBOutlet weak var con_Button: NSLayoutConstraint!
    
    //SET NAVIGATION BAR
    @IBOutlet weak var con_NavigationBar : NSLayoutConstraint!
    @IBOutlet private weak var viewNavigation: NavigationBar!{
        didSet{
            viewNavigation.setSearchButton(isHidden: false)
            viewNavigation.delegate = self
        }
    }
    
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
        self.con_NavigationBar.constant = GlobalMainConstants.NavigationHeight
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = false
        
        //SET THE VIEW
        self.setTheView()
    }
    
   
    
    
    //SET THE VIEW
    func setTheView() {
        
        //SET COLLECTION HEIGHT
        self.con_Button.constant = manageWidth(size: 330)
        
        //SET FONT
        if let objUser = UserDefaults.standard.user{
            self.lblName.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 22.0, text: objUser.full_name ?? "")
            self.lblEmail.configureLable(textColor: .gray.withAlphaComponent(0.8), fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: objUser.email ?? "")
        }
        
//        self.txtEmail.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter email")
//        self.txtPassword.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "", placeholder: "Enter password")
        
        
        self.btnLogOut.configureLable(bgColour: .clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Log Out")
        
        
        //SET VIEW
        self.viewLogOut.backgroundColor = .clear
        self.viewLogOut.viewBorderCorneRadius(borderColour: .secondary)
        self.viewLogOut.viewCorneRadius(radius: 0, isRound: true)
    }
}


//MARK: - BUTTON ACTION
extension SettingViewController{
    @IBAction func btnLogOutClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        self.showLogoutAlert()
    }
    
    
    func showLogoutAlert() {
        let alert = UIAlertController(
            title: "Logout",
            message: "Are you sure you want to log out?",
            preferredStyle: .alert
        )

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        let logoutAction = UIAlertAction(title: "Logout", style: .destructive) { _ in
            self.LogOutUser()
        }

        alert.addAction(cancelAction)
        alert.addAction(logoutAction)

        DispatchQueue.main.async {
            self.present(alert, animated: true)
        }
    }
    
    
    func LogOutUser()  {
        RemoveAllDataLogout()
        
        //NVIGATE WELCOME SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.LOGIN_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "LoginViewController") as? LoginViewController{
            /* Initiating instance of ui-navigation-controller with view-controller */
            let navigationController = UINavigationController()
            navigationController.viewControllers = [newViewController]
            GlobalMainConstants.appDelegate?.window?.rootViewController = navigationController
            GlobalMainConstants.appDelegate?.window?.makeKeyAndVisible()
        }
    }
    
    func RemoveAllDataLogout() {
        //REMOVE ALL DATA
        UserDefaults.standard.user = nil
        UserDefaults.standard.accessToken = nil
        
        //SAVE OBJECT
        UserDefaults.standard.baseURL = ""
        
        //SET DATA TO EXTENSION
        defaultsToExtension?.set("", forKey: "api_url")
        defaultsToExtension?.set("", forKey: "auth_token")
        defaultsToExtension?.synchronize()
    }
    
}
