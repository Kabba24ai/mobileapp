//
//  NavigationController.swift
//  MusicInxite
//
//  Created by Jigar Khatri on 08/02/23.
//

import Foundation
import UIKit
import Nuke

//............................... SET NAVIGATIONS ...............................................//

func setNavigation(controller: UIViewController, isTransperent:Bool = false){
    guard let navigationController = controller.navigationController else{
        return
    }
    
    //SET NAVIGATION
    navigationController.view.semanticContentAttribute = UserDefaults.standard.language == "ar" ? .forceRightToLeft : .forceLeftToRight
    
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
        [NSAttributedString.Key.foregroundColor: UIColor.secondaryView!,
         NSAttributedString.Key.font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 20.0)]
        
        navigationController.navigationBar.standardAppearance = appearance
        navigationController.navigationBar.scrollEdgeAppearance = appearance
    }
    else{
        navigationController.navigationBar.titleTextAttributes =
        [NSAttributedString.Key.foregroundColor: UIColor.secondaryView!,
         NSAttributedString.Key.font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 20.0)]
    }
    
    navigationController.navigationBar.barTintColor = UIColor.primary
    navigationController.navigationBar.isTranslucent = isTransperent
    navigationController.navigationBar.shadowImage = UIImage() //(hideShadowImage) ? UIImage() : nil
    navigationController.navigationBar.setBackgroundImage(UIImage(), for: .default)
}

extension UIColor {

    /// Converts this `UIColor` instance to a 1x1 `UIImage` instance and returns it.
    ///
    /// - Returns: `self` as a 1x1 `UIImage`.
    func as1ptImage() -> UIImage {
        UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
        setFill()
        UIGraphicsGetCurrentContext()?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
}


func setNavigationBarFor(controller: UIViewController,
                         title:String = "",
                         isTransperent:Bool = false,
                         hideShadowImage: Bool = false,
                         leftIcon : String,
                         rightIcon : String,
                         isDetailsScree : Bool,
                         leftActionHandler: (() -> Void)? = nil,
                         rightActionHandler: (() -> Void)? = nil) {
    
    guard let navigationController = controller.navigationController else{
        return
    }
    
    controller.navigationItem.title = title
  
    //SET NAVIGATION
    setNavigation(controller: controller, isTransperent: isTransperent)
    
    
    if let actionLeft = leftActionHandler {
        navigationController.navigationItem.setHidesBackButton(true, animated: false)
        let button: UIButton = UIButton(type:.custom)
        button.backgroundColor = UIColor.clear
        button.setImage(UIImage(named: leftIcon), for: .normal)
        buttonImageColor(btnImage: button, imageName: leftIcon, colorHex: .secondary)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        button.frame = CGRect(x: 0, y: 0, width: 24, height: 24)

        if UserDefaults.standard.language == "ar" {
            button.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
        }
        let btnAction = UIBarButtonItemWithClouser(button: button, actionHandler: actionLeft)
        controller.navigationItem.leftBarButtonItem = btnAction
    }
    
    
    if rightIcon == "+View Billing"{
        if let actionRight = rightActionHandler {
            navigationController.navigationItem.setHidesBackButton(true, animated: false)
            let button: UIButton = UIButton(type:.custom)
            button.backgroundColor = UIColor.clear
            button.configureLable(bgColour: .clear, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14, text: rightIcon)

            let btnAction = UIBarButtonItemWithClouser(button: button, actionHandler: actionRight)
            if rightIcon == "icon_cart_shopping"{
                btnAction.setBadge(with: Checkout.shared.cart.count)
            }
            
            if rightIcon != ""{
                controller.navigationItem.rightBarButtonItem = btnAction
            }
        }

    }
    else{
        if let actionRight = rightActionHandler {
            navigationController.navigationItem.setHidesBackButton(true, animated: false)
            let button: UIButton = UIButton(type:.custom)
            button.backgroundColor = UIColor.clear
            button.setImage(UIImage(named: rightIcon), for: .normal)
            buttonImageColor(btnImage: button, imageName: rightIcon, colorHex: .secondary)
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            button.frame = CGRect(x: 0, y: 0, width: 24, height: 24)

            if UserDefaults.standard.language == "ar" {
                button.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
            }

            let btnAction = UIBarButtonItemWithClouser(button: button, actionHandler: actionRight)
            if rightIcon == "icon_cart_shopping"{
                btnAction.setBadge(with: Checkout.shared.cart.count)
            }
            
            if rightIcon != ""{
                controller.navigationItem.rightBarButtonItem = btnAction
            }
        }

    }
}


func setNavigationBarForButtons(controller: UIViewController,
                                title:String = "",
                                isTransperent:Bool = false,
                                hideShadowImage: Bool = false,
                                leftIcon : String,
                                rightIcon : [String],
                                isFilter : Bool,
                                leftActionHandler: (() -> Void)? = nil,
                                rightActionHandler: ((_ sender : UIBarButtonItem, _ SelectTag : Int) -> Void)? = nil) {

    guard let navigationController = controller.navigationController else{
        return
    }
    
    controller.navigationItem.title = title
  
    //SET NAVIGATION
    setNavigation(controller: controller, isTransperent: isTransperent)
    
    
    if let actionLeft = leftActionHandler {
        navigationController.navigationItem.setHidesBackButton(true, animated: false)
        let button: UIButton = UIButton(type:.custom)
        button.backgroundColor = UIColor.clear
        button.setImage(UIImage(named: leftIcon), for: .normal)
        buttonImageColor(btnImage: button, imageName: leftIcon, colorHex: .secondary)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        button.frame = CGRect(x: 0, y: 0, width: 24, height: 24)

        if UserDefaults.standard.language == "ar" {
            button.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
        }
        let btnAction = UIBarButtonItemWithClouser(button: button, actionHandler: actionLeft)
        controller.navigationItem.leftBarButtonItem = btnAction
    }
    
    
    if let actionRight = rightActionHandler {
        navigationController.navigationItem.setHidesBackButton(true, animated: false)
       
        var arrAction : [UIBarButtonItemWithClouser] = []
        for i in 0..<rightIcon.count{
            let iconRight = rightIcon[i]
            let button: UIButton = UIButton(type:.custom)
            button.tag = i
            button.backgroundColor = UIColor.clear
            button.setImage(UIImage(named: iconRight), for: .normal)
            buttonImageColor(btnImage: button, imageName: iconRight, colorHex: .secondary)
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            button.frame = CGRect(x: 0, y: 0, width: 24, height: 24)

            if UserDefaults.standard.language == "ar" {
                button.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
            }

            let btnAction = UIBarButtonItemWithClouser(button: button, actionHandler3: actionRight)
            if iconRight == "icon_Filter"{
                btnAction.setBadge(with: isFilter ? 1 : 0)
                btnAction.setFilter(isFilter: isFilter)
            }
            
            arrAction.append(btnAction)
        }
        
        
        
        if arrAction.count != 0{
            controller.navigationItem.rightBarButtonItems = arrAction
        }
      
    }
}

var safeAreaInset: UIEdgeInsets = {
    if #available(iOS 11.0, *) {
        if let window = UIApplication.shared.windows.filter({$0.isKeyWindow}).first{
            return window.safeAreaInsets
        }
        return UIEdgeInsets.zero
    }
    else{
        return UIEdgeInsets.zero
    }
}()



fileprivate let whiteImage = UIImage(setColor: .primary)
func addNavBarImage(strLogo : String,controller: UINavigationController) -> UIImageView{
    
    let navController = controller
    
    let image = UIImage(named: strLogo) //Your logo url here
    let imageView = UIImageView(image: image)
    
    let bannerWidth = navController.navigationBar.frame.size.width
    let bannerHeight = navController.navigationBar.frame.size.height
    
    let bannerX = bannerWidth / 2 - (image?.size.width ?? 0) / 2
    let bannerY = bannerHeight / 2 - (image?.size.height ?? 0) / 2
    
    imageView.frame = CGRect(x: bannerX, y: bannerY, width: manageWidth(size: 130), height: bannerHeight)
    imageView.contentMode = .scaleAspectFit
    
    return imageView
}


extension UIImage {
    
    public convenience init?(setColor: UIColor?, size: CGSize = CGSize(width: 1, height: 1)) {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0.0)
        setColor?.setFill()
        UIRectFill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = image?.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }
}

