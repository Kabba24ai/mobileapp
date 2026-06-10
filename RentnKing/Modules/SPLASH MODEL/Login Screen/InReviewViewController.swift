//
//  InReviewViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 30/04/26.
//

import UIKit

class InReviewViewController: UIViewController {

    //DECLARE VARIABLE
    @IBOutlet weak var imgReview : UIImageView!
    @IBOutlet weak var lblTitle : UILabel!
    @IBOutlet weak var lblDetails : UILabel!

    @IBOutlet weak var viewLogOut : UIView!
    @IBOutlet weak var btnLogOut : UIButton!
    @IBOutlet weak var con_Button: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.

    }
    
    
    
    override func viewWillAppear(_ animated: Bool) {
        //SET VIEW
        self.view.backgroundColor = .background

        //SET PORTRAIT MODE
        AppUtility.PortraitMode()
                
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        self.tabBarController?.tabBar.isHidden = true
   
        //SET VIEW
        self.setTheView()
    }

    //SET THE VIEW
    func setTheView() {
        
        //SET COLLECTION HEIGHT
        self.con_Button.constant = manageWidth(size: 330)
        
        
        imgColor(imgColor: self.imgReview, colorHex: .secondary)
        self.lblTitle.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 14.0, text: "In Review")
        self.lblDetails.configureLable(textAlignment: .center, textColor: .primary.withAlphaComponent(0.7), fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: "Your Profile is under review.\nAfter approval you can see your data.")

        
        self.btnLogOut.configureLable(bgColour: .clear, textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Logout")

        
        //SET VIEW
        self.viewLogOut.backgroundColor = .secondary
        self.viewLogOut.viewCorneRadius(radius: 0, isRound: true)
    }

}



//MARK: - BUTTON ACTION
extension InReviewViewController{
    
    @IBAction func btnLogOutClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        let alert = UIAlertController(
            title: "Logout",
            message: "Are you sure you want to log out?",
            preferredStyle: .alert
        )

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        let logoutAction = UIAlertAction(title: "Logout", style: .destructive) { _ in
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

        alert.addAction(cancelAction)
        alert.addAction(logoutAction)

        DispatchQueue.main.async {
            self.present(alert, animated: true)
        }
        
      
    }
}

