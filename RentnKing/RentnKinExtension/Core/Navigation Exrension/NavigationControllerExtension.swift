//
//  NavigationControllerExtension.swift
//  RentnKinExtension
//
//  Created by Jigar Khatri on 04/01/24.
//

import Foundation
import UIKit
import Nuke

//............................... SET NAVIGATIONS ...............................................//

func setNavigationExtension(controller: UIViewController, isTransperent:Bool = false){
    guard let navigationController = controller.navigationController else{
        return
    }
    
    //SET NAVIGATION
    navigationController.view.semanticContentAttribute = .forceLeftToRight
    
//    if checkDeviceiPad(){
//        navigationController.additionalSafeAreaInsets.top = 30
//    }
    
    if #available(iOS 15, *) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.clear
        appearance.shadowColor = .clear
        
        // Title font color
        appearance.titleTextAttributes =
        [NSAttributedString.Key.foregroundColor: UIColor.primary!,
         NSAttributedString.Key.font: SetTheFont(fontName: GlobalConstants.APP_FONT_Roboto_Bold, size: 18.0)]
        
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
    }
    else{
        navigationController.navigationBar.titleTextAttributes =
        [NSAttributedString.Key.foregroundColor: UIColor.primary!,
         NSAttributedString.Key.font: SetTheFont(fontName: GlobalConstants.APP_FONT_Roboto_Bold, size: 18.0)]
    }
    
    navigationController.navigationBar.barTintColor = UIColor.primary
    navigationController.navigationBar.isTranslucent = isTransperent
    navigationController.navigationBar.shadowImage = UIImage() //(hideShadowImage) ? UIImage() : nil
    navigationController.navigationBar.setBackgroundImage(UIImage(), for: .default)
 
}
func setNavigationBarForExtension(controller: UIViewController,
                         title:String = "",
                         isTransperent:Bool = false,
                         hideShadowImage: Bool = false,
                         leftIcon : String,
                         rightIcon : String,
                         isDetailsScree : Bool,
                         leftActionHandler: (() -> Void)? = nil,
                         rightActionHandler: ((_ SelectTag : Int) -> Void)? = nil) {
    
    guard let navigationController = controller.navigationController else{
        return
    }
    
    controller.navigationItem.title = title
  
    //SET NAVIGATION
    setNavigationExtension(controller: controller, isTransperent: isTransperent)
    
    
    if let actionLeft = leftActionHandler {
        navigationController.navigationItem.setHidesBackButton(true, animated: false)
        let button: UIButton = UIButton(type:.custom)
        button.backgroundColor = UIColor.clear
        button.setImage(UIImage(named: leftIcon), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        let btnAction = UIBarButtonItemWithClouserExtension(button: button, actionHandler: actionLeft)
        controller.navigationItem.leftBarButtonItem = btnAction
    }
    
    
//    if let actionRight = rightActionHandler {
//        navigationController.navigationItem.setHidesBackButton(true, animated: false)
//
//        if isDetailsScree{
//            //SUBSCRIPTION BUTTON
//            let bannerHeight = navigationController.navigationBar.frame.size.height - 5
//            let viewSubscription = UIView(frame: CGRect.init(x: 0, y: 5, width: bannerHeight * 1.9, height: bannerHeight ))
//
//            viewSubscription.backgroundColor = .clear
//            viewSubscription.tag = 0
//
//            let imgUser = UIImageView(frame: CGRect(x: 0, y: 0, width: viewSubscription.frame.size.width , height: viewSubscription.frame.size.height ) )
//            imgUser.layer.masksToBounds = true
//            imgUser.viewCorneRadius(radius: 10, isRound: false)
//            imgUser.backgroundColor = .clear
//            imgUser.contentMode = .scaleAspectFit
//            if let url = URL(string: rightIcon.replacingOccurrences(of: " ", with: "%20")){
//                Nuke.loadImage(with: url, options: ImageLoadingOptions(transition: .fadeIn(duration: 0.33)), into: imgUser)
//            }
//            
//
//            viewSubscription.addSubview(imgUser)
//
//            let btnSubscriptionAction = UIBarButtonItemWithClouserExtension(view: viewSubscription, actionHandler2: actionRight)
//
//            controller.navigationItem.rightBarButtonItem = btnSubscriptionAction
//        }
//        else{
//            
//            
//            let bannerHeight = navigationController.navigationBar.frame.size.height
//            let viewSubscription = UIView(frame: CGRect.init(x: 0, y: 0, width: bannerHeight, height: bannerHeight ))
//
//            viewSubscription.backgroundColor = .clear
//            viewSubscription.tag = 0
//
//            let imgUser = UIImageView(frame: CGRect(x: (viewSubscription.frame.size.width / 2) - (25/2), y: (viewSubscription.frame.size.height / 2) - (25/2), width: 25 , height: 25 ) )
//            imgUser.layer.masksToBounds = true
//            imgUser.backgroundColor = .clear
//            imgUser.contentMode = .scaleAspectFit
//            imgUser.image = UIImage(named: rightIcon)
//            
//
//            viewSubscription.addSubview(imgUser)
//
//            let btnSubscriptionAction = UIBarButtonItemWithClouserExtension(view: viewSubscription, actionHandler2: actionRight)
//
//            controller.navigationItem.rightBarButtonItem = btnSubscriptionAction
//            
//            
//
//        }
        
      

        
//    }
}


