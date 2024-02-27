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
        
        if UserDefaults.standard.language == "ar" {
            button.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
        }
        let btnAction = UIBarButtonItemWithClouser(button: button, actionHandler: actionLeft)
        controller.navigationItem.leftBarButtonItem = btnAction
    }
    
    
    if let actionRight = rightActionHandler {
        navigationController.navigationItem.setHidesBackButton(true, animated: false)
        let button: UIButton = UIButton(type:.custom)
        button.backgroundColor = UIColor.clear
        button.setImage(UIImage(named: rightIcon), for: .normal)
        buttonImageColor(btnImage: button, imageName: rightIcon, colorHex: .secondary)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

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



func setNavigationBarForImg(controller: UIViewController,
                            title:String = "",
                            isTransperent:Bool = false,
                            hideShadowImage: Bool = false,
                            leftIcon : String,
                            rightIcon : String,
                            leftActionHandler: ((_ SelectTag : Int) -> Void)? = nil,
                            rightActionHandler: ((_ SelectTag : Int) -> Void)? = nil) {
    
    guard let navigationController = controller.navigationController else{
        return
    }
    

    //SET PORTRAIT MODE
    AppUtility.PortraitMode()
 
    //SET NAVIGATION TITLE IMAGE
    if title != ""{
        controller.navigationItem.titleView = addNavBarImage(strLogo: title, controller: controller.navigationController!)
    }
 
    //SET NAVIGATION
    setNavigation(controller: controller, isTransperent: isTransperent)
    

    if let actionLeft = leftActionHandler  {
        navigationController.navigationItem.setHidesBackButton(true, animated: false)
        
        
        let bannerWidth = navigationController.navigationBar.frame.size.width
        let bannerHeight = navigationController.navigationBar.frame.size.height
     
        //SUBSCRIPTION BUTTON
        let viewSubscription = UIView(frame: CGRect.init(x: 0, y: 0, width: bannerWidth - 40 , height: bannerHeight))
        viewSubscription.backgroundColor = .clear
        viewSubscription.tag = 10
        let spaceBetwen = 20.0
        
        
        
        //SET CENTER WIDHT
        let currentWidht = viewSubscription.frame.size.width - (bannerHeight * 2) - (spaceBetwen * 2)
        
        //Image View
        let imageView = UIImageView()
        imageView.backgroundColor = UIColor.clear
        imageView.heightAnchor.constraint(equalToConstant: bannerHeight).isActive = true
        imageView.widthAnchor.constraint(equalToConstant: bannerHeight).isActive = true
        imageView.image = UIImage(named: leftIcon)
        imageView.contentMode = .scaleAspectFit

        
        //Stack View
        let stackView = UIStackView(frame: CGRect.init(x: 0, y: 0, width: viewSubscription.frame.size.width , height: viewSubscription.frame.size.width))
        stackView.backgroundColor = UIColor.clear
        stackView.axis  = NSLayoutConstraint.Axis.horizontal
        stackView.distribution  = UIStackView.Distribution.equalSpacing
        stackView.alignment = UIStackView.Alignment.center
        stackView.spacing   = spaceBetwen
//        stackView.addArrangedSubview(searchView)
        stackView.addArrangedSubview(imageView)
//        stackView.addArrangedSubview(subcriptionView)
//        stackView.addArrangedSubview(notificationView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        viewSubscription.addSubview(stackView)

        let btnSubscriptionAction = UIBarButtonItem(customView: viewSubscription)
        
        controller.navigationItem.leftBarButtonItems = [btnSubscriptionAction]
        
        
        
//        //SUBSCRIPTION BUTTON
//        let bannerHeight = navigationController.navigationBar.frame.size.height
//        let viewSubscription = UIView(frame: CGRect.init(x: 0, y: 0, width: bannerHeight, height: bannerHeight ))
//
//        viewSubscription.backgroundColor = .clear
//        viewSubscription.tag = 0
//
//        let imgUser = UIImageView(frame: CGRect(x: 0, y: 0, width: viewSubscription.frame.size.width , height: viewSubscription.frame.size.height ) )
//        imgUser.layer.masksToBounds = true
//        imgUser.backgroundColor = .clear
//        imgUser.contentMode = .scaleAspectFit
//        imgUser.image = UIImage(named: leftIcon)
//
//
//        viewSubscription.addSubview(imgUser)
//
//        let btnSubscriptionAction = UIBarButtonItemWithClouser(view: viewSubscription, actionHandler2: actionLeft)
//
//        controller.navigationItem.leftBarButtonItem = btnSubscriptionAction
    }
    
    if let actionRight = rightActionHandler {
        navigationController.navigationItem.setHidesBackButton(true, animated: false)
        let button: UIButton = UIButton(type:.custom)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 10)
        button.backgroundColor = UIColor.clear
        
        button.setImage(UIImage(named: rightIcon), for: .normal)
        
        
        if UserDefaults.standard.language == "ar" {
            button.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
        }
        
        let btnAction = UIBarButtonItemWithClouser(button: button, actionHandler2: actionRight)
        controller.navigationItem.rightBarButtonItem = btnAction
    }
    
    func didTapEditButton(sender: AnyObject){
    }
    
    func didTapSearchButton(sender: AnyObject){
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

