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

      
      }
}
