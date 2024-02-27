//
//  TabbarViewController.swift
//  Belboy
//
//  Created by Jigar Khatri on 30/04/21.
//

import UIKit


class TabbarViewController: UITabBarController, UITabBarControllerDelegate{
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboard(true)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.languageUpdated(notificatio:)), name: .languageUpdate, object: nil)
        
        
        UITabBarItem.appearance().setTitleTextAttributes([NSAttributedString.Key.font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 12.0)], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([NSAttributedString.Key.font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 12.0)], for: .selected)
        UITabBar.appearance().clipsToBounds = false
        
      
        //SET TABBAR BG IMAGE
        self.tabBar.backgroundColor = .background
        
        self.tabBar.sizeToFit()
        self.tabBar.tintColor = .secondary
        self.tabBar.unselectedItemTintColor = .secondary
        
        
        self.tabBar.layer.masksToBounds = true
        self.tabBar.isTranslucent = true
        self.tabBar.barStyle = .blackOpaque
   
        let lineView = UIView(frame: CGRect(x: 0, y: 0, width:self.tabBar.frame.size.width, height: 1))
        lineView.backgroundColor = UIColor.secondary
        self.tabBar.addSubview(lineView)
        
//        self.tabBar.layer.borderWidth = 1
//        self.tabBar.layer.borderColor = UIColor.secondary?.cgColor
//        self.tabBar.clipsToBounds = true

        
        self.delegate = self
        
        //SET TABBAR
        self.configureTabBar()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
    }
    
    
    fileprivate func configureTabBar() {
        
        var controller:[UINavigationController] = []
        
        //HOME TABBAR
        let storyBoardHome: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
        if let tabOne = storyBoardHome.instantiateViewController(withIdentifier: "HomeViewController") as? HomeViewController {
            
            let item = UITabBarItem()
            item.title = str.home
            item.image = UIImage(named: "icon_HomeSelect")?.withRenderingMode(UIImage.RenderingMode.alwaysOriginal)
            item.selectedImage = UIImage(named: "icon_HomeSelect")?.withRenderingMode(UIImage.RenderingMode.alwaysOriginal)
            item.imageInsets = UIEdgeInsets(top: 3, left: 0, bottom: -3, right: 0)
            if safeAreaInset.bottom == 0{
                item.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -2)
            }
            
            tabOne.tabBarItem = item
            
            let navigationController = UINavigationController(rootViewController: tabOne)
            navigationController.view.backgroundColor = .background
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
            controller.append(navigationController)
        }
        
        //LIVE TABBAR
        let storyTV: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
        if let tabTow = storyTV.instantiateViewController(withIdentifier: "SettingViewController") as? SettingViewController {
            
            let item = UITabBarItem()
            item.title = str.setting
            item.image = UIImage(named: "icon_SettingSelect")?.withRenderingMode(UIImage.RenderingMode.alwaysOriginal)
            item.selectedImage = UIImage(named: "icon_SettingSelect")?.withRenderingMode(UIImage.RenderingMode.alwaysOriginal)
            item.imageInsets = UIEdgeInsets(top: 3, left: 0, bottom: -3, right: 0)
            
            if safeAreaInset.bottom == 0{
                item.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: -2)
            }
            
            tabTow.tabBarItem = item
            
            let navigationController = UINavigationController(rootViewController: tabTow)
            navigationController.view.backgroundColor = .background
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
            controller.append(navigationController)
        }
                
        viewControllers = controller
    }
    
    
 
    
    
    
    @objc func menuButtonAction(sender: UIButton) {

    }
    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
//        let tabBarIndex = tabBarController.selectedIndex
//        print(tabBarIndex)
        
    }
    
    override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        setupKeyboard(true)
        
        //SET PHONE VIBRATE
        ImpactGenerator()
       
    }    
}

extension TabbarViewController{
    @objc private func languageUpdated(notificatio: NSNotification?){
        configureTabBar()
    }
}



extension UIImage {
    func createSelectionIndicator(color: UIColor, size: CGSize, lineWidth: CGFloat) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        color.setFill()
        UIRectFill(CGRect(x: 0, y: size.height - lineWidth, width: size.width, height: lineWidth))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }
}
