//
//  Global.swift
//  Now TV!
//
//  Created by Jigar Khatri on 29/08/23.
//

import Foundation
import UIKit
import AVFoundation
import IQKeyboardManagerSwift

struct GlobalConstants
{
    // Constant define here.
    static let developerTest : Bool = false
    static let appLive : Bool = true
    
    //Implementation View height
    static let screenHeightDeveloper : Double =  checkDeviceiPad() ? 1024 : 898
    static let screenWidthDeveloper : Double = checkDeviceiPad() ? 768 : 430


    static let PageLimit: Int = 10
    static let spacing: Int = checkDeviceiPad() ? 16 : 8
    static let corner: Int = checkDeviceiPad() ? 10 : 5
    
   
    
    //System width height
    static let windowWidth: Double = Double(UIScreen.main.bounds.size.width)
    static let windowHeight: Double = Double(UIScreen.main.bounds.size.height)

    
   
    
    //FONT NAME
    static let APP_FONT_Roboto_Black = "Roboto-Black"
    static let APP_FONT_Roboto_Bold = "Roboto-Bold"
    static let APP_FONT_Roboto_Light = "Roboto-Light"
    static let APP_FONT_Roboto_Medium = "Roboto-Medium"
    static let APP_FONT_Roboto_Regular = "Roboto-Regular"
    static let APP_FONT_HelveticaNeue = "HelveticaNeue"

    //IPHONE NAME
    static let iPhone4_4s = "iPhones4 or 4S"
    static let iPhone5_5c_5s_SE = "iPhones 5/5s/5c/SE"
    static let iPhone6_6s_7_8 = "iPhones 6/6s/7/8"
    static let iPhone6P_6s_6sP_7P_8P = "iPhones 6+/6S+/7+/8+"
    static let iPhoneXR = "iPhone_XR"
    static let iPhoneX_XS = "iPhones X/XS"
    static let iPhoneXSMax = "iPhone XSMax"
    static let iPhoneUnknown = "unknown"
    
    
    //STOREBORD NAME
    static let Main = "MainInterface"
    
    
    
    //Device Token
    static let DeviceToken = UserDefaults.standard.object(forKey: "DeviceToken")
    
}




func getVisibleViewController(_ rootViewController: UIViewController) -> UIViewController? {
    
    if let presentedViewController = rootViewController.presentedViewController {
        return getVisibleViewController(presentedViewController)
    }
    
    if let navigationController = rootViewController as? UINavigationController {
        return navigationController.visibleViewController
    }
    
    if let tabBarController = rootViewController as? UITabBarController {
        return tabBarController.selectedViewController
    }
    
    return rootViewController
}
//............................... MANAGE ...............................................//

//MARK: - MANAGE FONT

func CheckFontNameList (){
    //CHECK FONT NAME
    for fontFamilyName in UIFont.familyNames{
        for fontName in UIFont.fontNames(forFamilyName: fontFamilyName){
            print("Family: \(fontFamilyName)     Font: \(fontName)")
        }
    }
}

func checkDeviceiPad() -> Bool{
    return UIDevice.current.userInterfaceIdiom == .pad ? true : false
}
func checkLandscape() -> Bool{
    if UIDevice.current.orientation == UIDeviceOrientation.landscapeLeft {
        return true
    } else if UIDevice.current.orientation == UIDeviceOrientation.landscapeRight {
        return true
    } else if UIDevice.current.orientation == UIDeviceOrientation.portrait {
        return false
    } else if UIDevice.current.orientation == UIDeviceOrientation.portraitUpsideDown {
        return false
    }
    return false
}


//............................... SET COLOR ...............................................//

// MARK: - SET COLOR
func colorFromRGB(valueRed: CGFloat, valueGreen: CGFloat, valueBlue: CGFloat) -> UIColor {
    return UIColor(red: valueRed / 255.0, green: valueGreen / 255.0, blue: valueBlue / 255.0, alpha: 1.0)
    
}

func hexStringToUIColor (hex:String) -> UIColor {
    var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    if (cString.hasPrefix("#")) {
        cString.remove(at: cString.startIndex)
    }

    if ((cString.count) != 6) {
        return UIColor.gray
    }

    var rgbValue:UInt64 = 0
    Scanner(string: cString).scanHexInt64(&rgbValue)

    return UIColor(
        red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
        green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
        blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
        alpha: CGFloat(1.0)
    )
}

//SET IMAGE COLOR
func imgColor (imgColor : UIImageView ,  colorHex : UIColor?){
    let templateImage = imgColor.image?.withRenderingMode(UIImage.RenderingMode.alwaysTemplate)
    imgColor.image = templateImage
    imgColor.tintColor = colorHex
}


func buttonImageColor (btnImage : UIButton, imageName : String , colorHex: UIColor?){
    let buttonImage = UIImage(named: imageName)
    btnImage.setImage(buttonImage?.withRenderingMode(.alwaysTemplate), for: .normal)
    btnImage.tintColor = colorHex
}







//MARK: - Manage function for value save -
extension NSDictionary {
    func getStringForID(key: String) -> String! {
        
        var strKeyValue : String = ""
        if self[key] != nil {
            if (self[key] as? Int) != nil {
                strKeyValue = String(self[key] as? Int ?? 0)
            } else if (self[key] as? String) != nil {
                strKeyValue = self[key] as? String ?? ""
            }else if (self[key] as? Double) != nil {
                strKeyValue = String(self[key] as? Double ?? 0)
            }else if (self[key] as? Float) != nil {
                strKeyValue = String(self[key] as? Float ?? 0)
            }else if (self[key] as? Bool) != nil {
                let bool_Get = self[key] as? Bool ?? false
                if bool_Get == true{
                    strKeyValue = "1"
                }else{
                    strKeyValue = "0"
                }
            }
        }
        return strKeyValue
    }
    
    func getArrayVarification(key: String) -> NSArray {
        
        var strKeyValue : NSArray = []
        if self[key] != nil {
            if (self[key] as? NSArray) != nil {
                strKeyValue = self[key] as? NSArray ?? []
            }
        }
        return strKeyValue
    }
}



//URL
enum Url {
    
    //API
    static let contactTags = NSURL(string: "\(Application.BaseURL)contact-tags")!
    static let createTags = NSURL(string: "\(Application.BaseURL)create-contact-tag")!

    //CREATE CONTECT
    static let createContact = NSURL(string: "\(Application.BaseURL)create-contact")!
}



func SetTheFont(fontName :String, size :Double) -> UIFont {
    return UIFont(name: fontName, size: manageFont(font: size + 2))!
}

func manageFont(font : Double) -> CGFloat{
    
    let cal : Double = GlobalConstants.windowWidth * font
    return CGFloat(cal / GlobalConstants.screenWidthDeveloper)
}




extension Encodable {
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            throw NSError()
        }
        return dictionary
    }
    
    var dictionary: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)).flatMap { $0 as? [String: Any] }
    }
}
