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
import KRProgressHUD
import ObjectMapper
import CoreActionSheetPicker

extension UIWindow {
    static var isLandscape: Bool {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.windows
                .first?
                .windowScene?
                .interfaceOrientation
                .isLandscape ?? false
        } else {
            return UIApplication.shared.statusBarOrientation.isLandscape
        }
    }
}

struct GlobalMainConstants
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
    
    static let NavigationHeight: Double = manageWidth(size: 65)
    
    //Name And Appdelegate Object
    static let appDelegate = (UIApplication.shared.delegate as? AppDelegate)
    
    
    //System width height
    static let windowWidth: Double = UIWindow.isLandscape ? Double(UIScreen.main.bounds.size.height) : Double(UIScreen.main.bounds.size.width)
    static let windowHeight: Double = UIWindow.isLandscape ? Double(UIScreen.main.bounds.size.width) : Double(UIScreen.main.bounds.size.height)

//    static let windowHeight: Double = Double(UIScreen.main.bounds.size.height)
    
    
    //STOREBORD NAME
    static let LOGIN_MODEL = "Login"
    static let TABBAR = "TabBar"
    
    static let HOME_MODEL = "Home"
    static let TIMECLOCK_MODEL = "TimeClock"
    static let ORDER_MODEL = "Order"
    static let SCHEDULE_MODEL = "Schedule"
    static let EQUIPMENT_MODEL = "Equipment"

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
    
    
    
    //Device Token
    static let DeviceToken = UserDefaults.standard.object(forKey: "DeviceToken")
    
}
let isRTL = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft


//GET VIEW TOP
var getTopViewController: UIViewController? {
    
    guard let rootViewController = GlobalMainConstants.appDelegate?.window?.rootViewController else {
        return nil
    }
    
    return getVisibleViewController(rootViewController)
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

func manageFont(font : Double) -> CGFloat{
    let cal : Double = GlobalMainConstants.windowWidth * font
    return CGFloat(cal / GlobalMainConstants.screenWidthDeveloper)
}

//MARK: - MANAGE HEIGHT
func manageHeight(size : Double) -> CGFloat{
    let cal : Double = GlobalMainConstants.windowHeight * size
    return CGFloat(cal / GlobalMainConstants.screenHeightDeveloper)
}

//MARK: - MANAGE WIDGH
func manageWidth(size : Double) -> CGFloat{
        
    let cal : Double = GlobalMainConstants.windowWidth * size
    return CGFloat(cal / GlobalMainConstants.screenWidthDeveloper)
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


//............................... SET THE FONT ...............................................//

func SetTheFont(fontName :String, size :Double) -> UIFont {
    return UIFont(name: fontName, size: manageFont(font: size))!
}

//............................... ALERT MESSAGE ...............................................//
func showAlertMessage(strMessage: String) {
    let alert = UIAlertController(title: Application.appName, message: strMessage, preferredStyle: UIAlertController.Style.alert)
    
    alert.addAction(UIAlertAction(title: str.ok, style: UIAlertAction.Style.default, handler: nil))
    getTopViewController?.present(alert, animated: true, completion: nil)
    
}



func convertSeccountToTime(remainingTime : Int) -> String{
    let hours = Int(remainingTime) / 3600
    let minutes = (Int(remainingTime) - hours * 3600) / 60
//    let seconds = Int(remainingTime) - hours * 3600 - minutes * 60
    
    var timing : String = ""
    if hours != 0{
        timing = "\(hours)h"
    }
    
    if minutes != 0{
        if timing != ""{
            timing = "\(timing) \(minutes)m"
        }
        else{
            timing = "\(minutes)m"
        }
    }
    
    
//    if seconds != 0{
//        if timing != ""{
//            timing = "\(timing) \(seconds)s"
//        }
//        else{
//            timing = "\(seconds)s"
//        } 
//    }
    
    return timing
}


//MARK: - SET KEYBOARD
@MainActor func setupKeyboard(_ enable: Bool) {
    IQKeyboardManager.shared.enable = enable
    IQKeyboardManager.shared.enableAutoToolbar = enable
    IQKeyboardManager.shared.toolbarConfiguration.placeholderConfiguration.showPlaceholder = !enable
    IQKeyboardManager.shared.toolbarConfiguration.previousNextDisplayMode = .alwaysShow
}

@MainActor func setupCutomeKeyboard() {
    IQKeyboardManager.shared.enable = true
    IQKeyboardManager.shared.enableAutoToolbar = true
    IQKeyboardManager.shared.toolbarConfiguration.placeholderConfiguration.showPlaceholder = true
    IQKeyboardManager.shared.toolbarConfiguration.previousNextDisplayMode = .alwaysHide
}

func removeNewLineToSpace(str_Value : String) -> String{
    let newString = str_Value.replacingOccurrences(of: "\n", with: " ")
    return newString
}


//MARK: -- Inicator AND LOADING --
func indicatorShow(){
    KRProgressHUD
        .set(style: .custom(background:  UIColor.backgroundView ?? UIColor.blue, text: UIColor.white, icon: nil))
        .set(activityIndicatorViewColors: [UIColor.white])
        .set(font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 20.0))
        .show(withMessage: str.appLoading)
}

func indicatorShowEmpty(){
    KRProgressHUD
        .set(style: .custom(background:  UIColor.clear , text: UIColor.white, icon: nil))
        .set(activityIndicatorViewColors: [UIColor.clear])
        .set(font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 14.0))
        .show(withMessage: "")
}
func indicatorHide(){
    KRProgressHUD.dismiss()
}


//func startLoading (view : UIView){
//    loadingPlaceholderView.cover(view, animated: true)
//    DispatchQueue.main.async {
//        indicatorShowEmpty()
//    }
//}

func startLoading (){
    DispatchQueue.main.async {
        indicatorShowEmpty()
    }
}

func storeLoading(){
//    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
//        placeholderMarker.remove()
//    }
    indicatorHide()
}





func GetBottomSafeAreaHeight() -> CGFloat  {
    //GET SAFE AREA HEIGHT
    var bottomSafeAreaHeight: CGFloat = 0
    if #available(iOS 11.0, *) {
        let window = UIApplication.shared.windows[0]
        let safeFrame = window.safeAreaLayoutGuide.layoutFrame
        bottomSafeAreaHeight = window.frame.maxY - safeFrame.maxY
    }
    return bottomSafeAreaHeight
}

func GetTopSafeAreaHeight() -> CGFloat  {
    //GET SAFE AREA HEIGHT
    var topSafeAreaHeight: CGFloat = 0
    if #available(iOS 11.0, *) {
        let window = UIApplication.shared.windows[0]
        let safeFrame = window.safeAreaLayoutGuide.layoutFrame
        topSafeAreaHeight = safeFrame.minY
    }
    return topSafeAreaHeight
}




func openURL(strURL : String){
    
    if let url = URL(string: "\(strURL)"), !url.absoluteString.isEmpty {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    // or outside scope use this
    guard let url = URL(string: "\(strURL)"), !url.absoluteString.isEmpty else {
        return
    }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
}

//............................... VALIDATION ...............................................//

//MARK: -- Email Validation --
func validateEmail(enteredEmail:String) -> Bool {
    
    let emailFormat = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
    let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailFormat)
    
    return emailPredicate.evaluate(with: enteredEmail)
}

func validatePhoneNumber(value: String) -> Bool {
    let charcterSet  = NSCharacterSet(charactersIn: "+0123456789").inverted
    let inputString = value.components(separatedBy: charcterSet)
    let filtered = inputString.joined(separator: "")
    return  value == filtered
}

func isValidPhone(phone: String) -> Bool {
    let phoneRegex = "([0-9]{3})+ [0-9]{3}+ [0-9]{4}"

//    let phoneRegex = "^[0-9+]{0,1}+[0-9]{5,16}$"
    let phoneTest = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
    return phoneTest.evaluate(with: phone)
}

extension String {
    public var validPhoneNumber: Bool {
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return false }
        if let match = detector.matches(in: self, options: [], range: NSMakeRange(0, self.count)).first?.phoneNumber {
            return match == self
        } else {
            return false
        }
    }
}


//......................... DEVICE INDENTIFIER .....................................//
//MARK: - DEVICE INDENTIFIER
func deviceIdentifier() -> String{
    switch UIScreen.main.nativeBounds.height {
    case 960:
        return GlobalMainConstants.iPhone4_4s
    case 1136:
        return GlobalMainConstants.iPhone5_5c_5s_SE
    case 1334:
        return GlobalMainConstants.iPhone6_6s_7_8
    case 1920, 2208:
        return GlobalMainConstants.iPhone6P_6s_6sP_7P_8P
    case 1792:
        return GlobalMainConstants.iPhoneXR
    case 2436:
        return GlobalMainConstants.iPhoneX_XS
    case 2688:
        return GlobalMainConstants.iPhoneXSMax
    default:
        return GlobalMainConstants.iPhoneUnknown
    }
}


func randomString(length: Int) -> String {
    let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return String((0...length-1).map{ _ in letters.randomElement()! })
}

func randomNumber(length: Int) -> String {
    let letters = "0123456789"
    return String((0...length-1).map{ _ in letters.randomElement()! })
}




//............................... SET VALUE  ............................................//
//MARK: --- DICTIONARY TO STRING

func DicToStr(arrayResponse : NSDictionary) -> String {
    //CONVERT DICTIONARY TO STRING VALUE
    var jsonData: Data? = nil
    do {
        jsonData = try JSONSerialization.data(withJSONObject: arrayResponse, options: [])
    } catch {
        print("Error")
    }
    var myString: String? = nil
    if let jsonData = jsonData {
        myString = String(data: jsonData, encoding: .utf8)
    }
    
    return myString ?? ""
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


//GET VIEW TOP
extension UIApplication {
    class func getTopViewController(base: UIViewController? = GlobalMainConstants.appDelegate?.window?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return getTopViewController(base: nav.visibleViewController)
        }
        else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return getTopViewController(base: selected)
        }
        else if let presented = base?.presentedViewController {
            return getTopViewController(base: presented)
        }
        else  if let tabbar = base?.children.first(where: {$0 is TabbarViewController}) as? TabbarViewController {
            return getTopViewController(base: tabbar)
        }
        return base
    }
    
    public var mainKeyWindow: UIWindow? {
        if #available(iOS 13, *) {
            return UIApplication.shared.connectedScenes
                .filter { $0.activationState == .foregroundActive }
                .first(where: { $0 is UIWindowScene })
                .flatMap { $0 as? UIWindowScene }?.windows
                .first(where: \.isKeyWindow)
        } else {
            return UIApplication.shared.windows.first { $0.isKeyWindow }
        }
    }
}

//............................... CONVERT DATE ............................................//



//............................... CONVERT HTML ............................................//
// MARK: - CONVERT HTML -
extension Data {
    var html2AttributedString: NSAttributedString? {
        do {
            return try NSAttributedString(data: self, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        } catch {
            print("error:", error)
            return  nil
        }
    }
    var html2String: String { html2AttributedString?.string ?? "" }
}

extension StringProtocol {
    var html2AttributedString: NSAttributedString? {
        Data(utf8).html2AttributedString
    }
    var html2String: String {
        html2AttributedString?.string ?? ""
    }
}



extension UIDevice {
    
    
    static let modelName: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        func mapToDevice(identifier: String) -> String { // swiftlint:disable:this cyclomatic_complexity
            #if os(iOS)
            switch identifier {
            case "iPod5,1":                                 return "iPod Touch 5"
            case "iPod7,1":                                 return "iPod Touch 6"
            case "iPhone3,1", "iPhone3,2", "iPhone3,3":     return "iPhone 4"
            case "iPhone4,1":                               return "iPhone 4s"
            case "iPhone5,1", "iPhone5,2":                  return "iPhone 5"
            case "iPhone5,3", "iPhone5,4":                  return "iPhone 5c"
            case "iPhone6,1", "iPhone6,2":                  return "iPhone 5s"
            case "iPhone7,2":                               return "iPhone 6"
            case "iPhone7,1":                               return "iPhone 6 Plus"
            case "iPhone8,1":                               return "iPhone 6s"
            case "iPhone8,2":                               return "iPhone 6s Plus"
            case "iPhone9,1", "iPhone9,3":                  return "iPhone 7"
            case "iPhone9,2", "iPhone9,4":                  return "iPhone 7 Plus"
            case "iPhone8,4":                               return "iPhone SE"
            case "iPhone10,1", "iPhone10,4":                return "iPhone 8"
            case "iPhone10,2", "iPhone10,5":                return "iPhone 8 Plus"
            case "iPhone10,3", "iPhone10,6":                return "iPhone X"
            case "iPhone11,2":                              return "iPhone XS"
            case "iPhone11,4", "iPhone11,6":                return "iPhone XS Max"
            case "iPhone11,8":                              return "iPhone XR"
            case "iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4":return "iPad 2"
            case "iPad3,1", "iPad3,2", "iPad3,3":           return "iPad 3"
            case "iPad3,4", "iPad3,5", "iPad3,6":           return "iPad 4"
            case "iPad4,1", "iPad4,2", "iPad4,3":           return "iPad Air"
            case "iPad5,3", "iPad5,4":                      return "iPad Air 2"
            case "iPad6,11", "iPad6,12":                    return "iPad 5"
            case "iPad7,5", "iPad7,6":                      return "iPad 6"
            case "iPad2,5", "iPad2,6", "iPad2,7":           return "iPad Mini"
            case "iPad4,4", "iPad4,5", "iPad4,6":           return "iPad Mini 2"
            case "iPad4,7", "iPad4,8", "iPad4,9":           return "iPad Mini 3"
            case "iPad5,1", "iPad5,2":                      return "iPad Mini 4"
            case "iPad6,3", "iPad6,4":                      return "iPad Pro (9.7-inch)"
            case "iPad6,7", "iPad6,8":                      return "iPad Pro (12.9-inch)"
            case "iPad7,1", "iPad7,2":                      return "iPad Pro (12.9-inch) (2nd generation)"
            case "iPad7,3", "iPad7,4":                      return "iPad Pro (10.5-inch)"
            case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4":return "iPad Pro (11-inch)"
            case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8":return "iPad Pro (12.9-inch) (3rd generation)"
            case "AppleTV5,3":                              return "Apple TV"
            case "AppleTV6,2":                              return "Apple TV 4K"
            case "AudioAccessory1,1":                       return "HomePod"
            case "i386", "x86_64":                          return "Simulator \(mapToDevice(identifier: ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "iOS"))"
            default:                                        return identifier
            }
            #elseif os(tvOS)
            switch identifier {
            case "AppleTV5,3": return "Apple TV 4"
            case "AppleTV6,2": return "Apple TV 4K"
            case "i386", "x86_64": return "Simulator \(mapToDevice(identifier: ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "tvOS"))"
            default: return identifier
            }
            #endif
        }
        
        return mapToDevice(identifier: identifier)
    }()
    
}




//URL
enum Url {
    static let updateToken = NSURL(string: "\(Application.BaseURL)device-token")!

    //CATEGORY
    static let categorys = NSURL(string: "\(Application.BaseURL)getcategories")!
    static let categoryProducts = NSURL(string: "\(Application.BaseURL)getcategoryproducts")!
    static let searchProducts = NSURL(string: "\(Application.BaseURL)search-products")!
    static let productsDetaisl = NSURL(string: "\(Application.BaseURL)getProductDetails")!

    static let getStores = NSURL(string: "\(Application.BaseURL)getStores")!
    static let placeORder = NSURL(string: "\(Application.BaseURL)place-order")!

    //STATES
    static let getStates = NSURL(string: "\(Application.BaseURL)getstates")!


    //ORDER
    static let orderList = NSURL(string: "\(Application.BaseURL)getorders")!
    static let orderDetails = NSURL(string: "\(Application.BaseURL)getorderdetail")!
    static let uploadLicense = NSURL(string: "\(Application.BaseURL)order/upload/license")!
    static let machineHours = NSURL(string: "\(Application.BaseURL)order/update/multiple/product-hours")!
    static let orderPayment = NSURL(string: "\(Application.BaseURL)order/payment")!
    static let updateAddress = NSURL(string: "\(Application.BaseURL)order/address/update")!
    static let updateCheckList = NSURL(string: "\(Application.BaseURL)order/checklist-update")!
    static let updateCheckListImages = NSURL(string: "\(Application.BaseURL)order/checklist-media-update")!
    static let addOrderNote = NSURL(string: "\(Application.BaseURL)order/note/update")!

    //TIME CLOCK
    static let timeClockSetting = NSURL(string: "\(Application.BaseURL)time-clock/settings")!
    static let statusList = NSURL(string: "\(Application.BaseURL)attendance/statues")!
    static let employeesList = NSURL(string: "\(Application.BaseURL)employees")!
    static let employeeStatus = NSURL(string: "\(Application.BaseURL)employee/status")!
    static let updateEmployeeStatus = NSURL(string: "\(Application.BaseURL)employee/attendance/track")!
    static let checkListPrice = NSURL(string: "\(Application.BaseURL)checklist/price")!
    static let machineList = NSURL(string: "\(Application.BaseURL)maintenance/inventory")!

    //IMAGE VIDEO UPLOAD
    static let uploadImageVideo = NSURL(string: "\(Application.BaseURL)order/upload/images")!
    static let removeImageVideo = NSURL(string: "\(Application.BaseURL)order/remove/images")!

    //SCHEDULE
    static let scheduleList = NSURL(string: "\(Application.BaseURL)order/delivery-pickup-list")!
    static let scheduleListCound = NSURL(string: "\(Application.BaseURL)order/delivery-pickup-count")!
    static let scheduleUpdate = NSURL(string: "\(Application.BaseURL)order/delivery-pickup-update")!

    //MACHINE PROFILE
    static let maintenanceProfile = NSURL(string: "\(Application.BaseURL)maintenance/inventory/report")!
    static let inventoryClass = NSURL(string: "\(Application.BaseURL)maintenance/inventory/class")!
    static let inventoryStatus = NSURL(string: "\(Application.BaseURL)maintenance/statues")!
    static let inventoryService = NSURL(string: "\(Application.BaseURL)maintenance/inventory/services")!

    static let rantalReady = NSURL(string: "\(Application.BaseURL)maintenance/profile/view")!
    static let updateRantalReady = NSURL(string: "\(Application.BaseURL)maintenance/inventory/update")!

}



func getVersionNumber(strVersionNumber : String) -> Int{
    let array = strVersionNumber.components(separatedBy: ".")
    print(array)
    var versionNumber : Int = 0
    for i in 0..<array.count{
        let number = array[i]
        //ADD SUM
        if i == 0{
            versionNumber  = (Int(number) ?? 0) * 1000
        }
        else{
            versionNumber = versionNumber + (Int(number) ?? 0)
        }
    }
    return versionNumber
}

func ImpactGenerator(){
    let impactFeedbackgenerator = UIImpactFeedbackGenerator(style: .light)
    impactFeedbackgenerator.prepare()
    impactFeedbackgenerator.impactOccurred()
}



//CHECK PRODUCT
func isDevelopmentProvisioningProfile() -> Bool {
    return true
    
}


func removeZero(strNumber : String) -> String{
    var arrString = Array(strNumber)
    if arrString.count != 0{
        if arrString[0] == "0"{
            arrString.remove(at: 0)
        }
        
        var Number : String = ""
        for str in arrString{
            Number = "\(Number)\(str)"
        }
        
        return Number
    }
    return ""
}


//MARK: -- Data Form   ate Convertion --
func convertStringToDate(dateString: String, withFormat format: String) -> Date? {
    if isValidDate(dateString: dateString, currentFormate: format) {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = format

        if let date = inputFormatter.date(from: dateString) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = format
            return outputFormatter.date(from: outputFormatter.string(from: date))
        }
    }
   
    return Date()
}

func convertDateToString(date: Date, withFormat format: String) -> String{
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return formatter.string(from: date) // string purpose I add here
}

func convertStringToNewFormateString(date: String, withFormat format: String, newFormate : String) -> String? {
    if isValidDate(dateString: date, currentFormate: format) {
        let dateFormatter = DateFormatter()
        
        dateFormatter.dateFormat = format
        let date = dateFormatter.date(from: date)
        dateFormatter.dateFormat = newFormate
        return  dateFormatter.string(from: date!)
    }
    return ""
}
    

extension Formatter {
    static let time: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = Application.HHMMSS
        return dateFormatter
    }()
}

func differenceStartAndEndTime(start: String, end: String) -> String {
    Formatter.time.defaultDate = Calendar.current.startOfDay(for: Date())
    guard let startTime = Formatter.time.date(from: start),
          var endTime = Formatter.time.date(from: end) else {
          return "0"
    }
    if endTime < startTime {
        endTime = Calendar.current.date(byAdding: .day, value: 1, to: endTime)!
    }
    
    
    return timeFormatted(Int(endTime.timeIntervalSince(startTime)))
}

func timeFormatted(_ totalSeconds: Int) -> String {
    let seconds: Int = totalSeconds % 60
    let minutes: Int = (totalSeconds / 60) % 60
    let hours: Int = (totalSeconds / 60) / 60
    return hours >= 1 ? String(format: "%02d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
}


func convertDateToString(date: Date, withFormat format: String, newFormate : String) -> String? {
    let inputFormatter = DateFormatter()
    inputFormatter.dateFormat = format
    let strDate = inputFormatter.string(from: date)

    if let date = inputFormatter.date(from: strDate) {
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = newFormate
        return outputFormatter.string(from: date)
    }
    return strDate
}


func CurrntDateToString( withFormat format: String, newFormate : String) -> String? {
    let inputFormatter = DateFormatter()
    inputFormatter.dateFormat = format
    let strDate = inputFormatter.string(from: Date())
    return strDate
}


func convertDateToNewFormateString(date: Date, withFormat format: String, newFormate : String) -> String? {
    let inputFormatter = DateFormatter()
    inputFormatter.dateFormat = format
    let strDate = inputFormatter.string(from: date)

    if let date = inputFormatter.date(from: strDate) {
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = newFormate
        return outputFormatter.string(from: date)
    }
    return strDate
}


func convertToGMT(dateToConvert:String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = Application.serverDateFormet
    let convertedDate = formatter.date(from: dateToConvert)
    formatter.timeZone = TimeZone(identifier: "GMT+6")
    return convertStringToDate2(dateString: formatter.string(from: convertedDate!)) ?? Date()
}

func convertStringToDate2(dateString: String) -> Date? {
    if isValidDate(dateString: dateString, currentFormate: Application.serverDateFormet) {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = Application.serverDateFormet

        if let date = inputFormatter.date(from: dateString) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateFormat = Application.serverDateFormet
            return outputFormatter.date(from: outputFormatter.string(from: date))
        }
    }
   
    return Date()
}

func convertToUTC(dateToConvert:String) -> Date {
    let formatter = DateFormatter()
    formatter.dateFormat = Application.serverDateFormet
    var convertedDate = formatter.date(from: dateToConvert)
    
    let timeZone = TimeZone(identifier: "UTC")
    if ((timeZone?.isDaylightSavingTime(for: Date())) != nil) {
        convertedDate = Calendar.current.date(byAdding: .hour, value: 1, to: convertedDate ?? Date())
       print("Yes, daylight saving time at a given date")
    }
    
    formatter.timeZone = TimeZone(identifier: "UTC")
    return convertStringToDate2(dateString: formatter.string(from: convertedDate!)) ?? Date()
}


func convertDateFormater(_ OrderDate: String, CurrentDateFormate : String, ChangeDateFormate  :String) -> String{
    
    if isValidDate(dateString: OrderDate, currentFormate: CurrentDateFormate) {
        let dateFormatter = DateFormatter()
        
        dateFormatter.dateFormat = CurrentDateFormate
        let date = dateFormatter.date(from: OrderDate)
        dateFormatter.dateFormat = ChangeDateFormate
        return  dateFormatter.string(from: date!)
    }
    return ""
}




func isValidDate(dateString: String, currentFormate : String?) -> Bool {
    let dateFormatterGet = DateFormatter()
    dateFormatterGet.dateFormat = currentFormate
    if let _ = dateFormatterGet.date(from: dateString) {
        //date parsing succeeded, if you need to do additional logic, replace _ with some variable name i.e date
        return true
    } else {
        // Invalid date
        return false
    }
}

extension Data {
    var hexString: String {
        let hexString = map { String(format: "%02.2hhx", $0) }.joined()
        return hexString
    }
}


extension String {
    func isValidNumber() -> Bool {
        return !isEmpty && range(of: "[^a-zA-Z0-9]", options: .regularExpression) == nil
    }
    
    func isValidPassword() -> Bool {
        //        let regularExpression = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[$@$!%*?&])[A-Za-z\\d$@$!%*?&]{8,}"
        let regularExpression = "^(?=.*[a-z])(?=.*[0-9])(?=.*[A-Z]).{8,}$"
        let passwordValidation = NSPredicate.init(format: "SELF MATCHES %@", regularExpression)
        
        return passwordValidation.evaluate(with: self)
    }
    
    func capitalizingFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }

    mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
}











//MARK: - VIDE SUBTITLE DATA
//func convertSubTitleFileInArray(strURL : URL!, strLocalFile : String) -> [videoSubTitleParameter]{
//    var text: String?
//    do {
//        if let url = strURL {
//            text = try String(contentsOf: url)
//        }
//    } catch {
//        return []
//    }
//    
//    
//    var arrSubTitle : [videoSubTitleParameter] = []
//    var scanner: Scanner?
//    scanner = Scanner(string: text ?? "")
//
//    
//    while !scanner!.isAtEnd {
//        
//        var index : Int = 0
//        var startString : NSString?
//        var endString : NSString?
//        var text : String = ""
//        var line : NSString?
//        var endScanningText : Bool = false
//        
//        scanner?.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines
//        scanner?.scanInt(&index)
//        scanner?.scanUpTo("-->", into: &startString)
//        scanner?.scanString("-->", into: nil)
//        scanner?.scanUpToCharacters(from: CharacterSet.newlines, into: &endString)
//        scanner?.charactersToBeSkipped = nil
//        scanner?.scanCharacters(from: CharacterSet.newlines, into: nil)
//        
//        repeat {
//            
//            endScanningText = !(scanner?.scanUpToCharacters(from: CharacterSet.newlines, into: &line))!
//            if !endScanningText {
//                let strLine  = line?.trimmingCharacters(in: CharacterSet.whitespaces)
//                text = text + "\(text.count > 0 ? "\n" : "")\(strLine ?? "")"
//                scanner?.scanUpTo("\n", into: nil)
//                scanner?.scanString("\n", into: nil)
//            }
//            
//        } while !endScanningText
//                
//        var obj : videoSubTitleParameter!
//        let map = Map(mappingType: .fromJSON, JSON: [:])
//        obj = videoSubTitleParameter(map: map)
//
//        
//        var strTitle = text.replacingOccurrences(of: "<b>", with: "")
//        strTitle = strTitle.replacingOccurrences(of: "</b>", with: "")
//        obj.title = strTitle
//        obj.startTime = timeConvert(from:"\(startString ?? "")", index: index)
//        obj.endTitme = timeConvert(from:"\(endString ?? "")", index: index)
//        arrSubTitle.append(obj)
//    }
//    
//    print(arrSubTitle)
//    return arrSubTitle
//}

func timeConvert(from timeString: String?, index : Int) -> TimeInterval {
    print("wwwwwww = > \(timeString ?? "")")
    var strTimeString = timeString?.replacingOccurrences(of: "WEBVTT", with: "")
    if index == 0 || index == 1{
        strTimeString = strTimeString?.replacingOccurrences(of: "\n﻿1", with: "")
    }
  
    strTimeString = strTimeString?.replacingOccurrences(of: "\n", with: "")
    strTimeString = strTimeString?.replacingOccurrences(of: " ", with: "")
    strTimeString = strTimeString?.replacingOccurrences(of: "<b>", with: "")

    var scanner: Scanner? = nil
    var hours: Int = 0
    var minutes: Int = 0
    var seconds: Int = 0
    var milliseconds: Int = 0
    var time: Float

    scanner = Scanner(string: strTimeString ?? "")
    scanner?.scanInt(&hours)
    scanner?.scanString(":", into: nil)
    scanner?.scanInt(&minutes)
    scanner?.scanString(":", into: nil)
    scanner?.scanInt(&seconds)
    scanner?.scanString(".", into: nil)
    scanner?.scanInt(&milliseconds)

    let strHour = hours * 3600
    let strMinute = minutes * 60
    
    print("-----======------")
    print(hours)
    print(minutes)
    print(seconds)
    print(milliseconds)
    time = Float(strHour + strMinute + seconds)
    
    print(time)
    return TimeInterval(time)
}




//MARK: - OPEN EXTERNAL URL
func opneExternalURL(strURL : String){
    if strURL == ""{
        return
    }
    
    // encode a space to %20 for example
    let escapedShareString = strURL.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)!

    // cast to an url
    let url = URL(string: escapedShareString)

    if #available(iOS 10.0, *) {
        UIApplication.shared.open(url!, options: [:], completionHandler: nil)
    } else {
        UIApplication.shared.openURL(url!)
    }
}

func registrerTableView(tblView : UITableView , tblCell : String){
    tblView.register(UINib(nibName: tblCell, bundle: nil), forCellReuseIdentifier: tblCell)
}

func registrerCollectionView(objCollection : UICollectionView , collectionCell : String){
    objCollection.register(UINib(nibName: collectionCell, bundle: nil), forCellWithReuseIdentifier: collectionCell)
}


func bandWidth(birRate : String) -> Double{
    switch (birRate) {
    case "1080":
        return 3471000
        
    case "720":
        return 1934000
    case "480":
        return 1106000
    case "360":
        return 837000
    case "240":
        return 185000
    case "160":
        return 65000
    default:
        break
    }
    return 0
}




extension UICollectionView {
    
    func scrollToEndIfArabic() {
        DispatchQueue.main.async {
            self.contentOffset
            = CGPoint(x: self.contentSize.width
                      - self.frame.width
                      + self.contentInset.right, y: 0)
        }
    }
}








func setButtonTitleNavigationBarFor(controller: UIViewController,
                                    title:String = "",
                                    isTransperent:Bool = false,
                                    hideShadowImage: Bool = false,
                                    leftIcon : String,
                                    rightIcon : String,
                                    leftActionHandler: (() -> Void)? = nil,
                                    rightActionHandler: (() -> Void)? = nil) {
    
    guard let navigationController = controller.navigationController else{
        return
    }
    
    //SET NAVIGATION TITLE IMAGE
    controller.title = title
    //    controller.navigationItem.titleView = addNavBarImage(strLogo: title, controller: controller.navigationController!)
    navigationController.view.semanticContentAttribute = UserDefaults.standard.language == "ar" ? .forceRightToLeft : .forceLeftToRight
    
    //    if isTransperent {
    //        navigationController.navigationBar.setBackgroundImage(UIImage(), for: .default)
    //    }
    //    else{
    //        navigationController.navigationBar.setBackgroundImage(whiteImage, for: .default)
    //    }
    
    navigationController.navigationBar.setBackgroundImage(UIImage(), for: .default)
    
    
    
    navigationController.navigationBar.barTintColor = UIColor.background
    navigationController.navigationBar.titleTextAttributes =
    [NSAttributedString.Key.foregroundColor: UIColor.primaryView!,
     NSAttributedString.Key.font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 16.0)]
    navigationController.navigationBar.isTranslucent = isTransperent
    navigationController.navigationBar.shadowImage = UIImage() //(hideShadowImage) ? UIImage() : nil
    
    
    if let actionLeft = leftActionHandler {
        navigationController.navigationItem.setHidesBackButton(true, animated: false)
        let button: UIButton = UIButton(type:.custom)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 0, right: 10)
        button.backgroundColor = UIColor.clear
        
        button.setImage(UIImage(named: leftIcon), for: .normal)
        buttonImageColor(btnImage: button, imageName: "icon_close", colorHex: UIColor.primary)
        
        if UserDefaults.standard.language == "ar" {
            button.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
        }
        let btnAction = UIBarButtonItemWithClouser(button: button, actionHandler: actionLeft)
        controller.navigationItem.leftBarButtonItem = btnAction
    }
    
    
    
    if let actionRight = rightActionHandler {
        navigationController.navigationItem.setHidesBackButton(true, animated: false)
        let button: UIButton = UIButton(type:.custom)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        button.backgroundColor = UIColor.clear
        button.setImage(UIImage(named: rightIcon), for: .normal)
        if UserDefaults.standard.language == "ar" {
            button.transform = CGAffineTransform(rotationAngle: CGFloat.pi)
        }
        let btnAction = UIBarButtonItemWithClouser(button: button, actionHandler: actionRight)
        controller.navigationItem.rightBarButtonItem = btnAction
    }
}



extension Double {
    var stringValue : String{
        return String(format: "%.2f", self)
    }
}

extension Float {
    var stringValue : String{
        return String(format: "%.2f", self)
    }
}
extension NSNumber {
    var stringValue : String{
        let number : Float = Float(truncating: self)
        return String(format: "%.2f", number)
    }
}



//MARK: -- Selected Index --
func selectedIndex(arr : NSArray, value : String) -> Int{
    for (index, _) in arr.enumerated() {
        if value == arr[index] as! String {
            return index
        }
    }
    return 0
}

//ACTION PICKER
func actionPicker(_ sender: UIButton, strTitle :String ,arrData :[String], selectValue :String, completion: @escaping (_ index: Int, _ values: String) -> Void) {
  
    
    let picker = ActionSheetStringPicker(title: strTitle, rows: arrData, initialSelection:selectedIndex(arr: arrData as NSArray, value: selectValue), doneBlock: { (picker, indexes, values) in
        
        completion(indexes , "\(values ?? "")")
        
    }, cancel: {ActionSheetStringPicker in return}, origin: sender)
    
    //        picker?.hideCancel = true
    picker?.setDoneButton(UIBarButtonItem(title: str.streSelect, style: .plain, target: nil, action: nil))
    picker?.setCancelButton(UIBarButtonItem(title: str.cancel, style: .plain, target: nil, action: nil))
//    picker?.toolbarButtonsColor = UIColor.black
 
    
    picker?.show()
}


func actionDatePicker(_ sender: UIButton, strTitle :String, selectDate :Date = Date(), completion: @escaping (_ index: Int, _ values: Date) -> Void) {
    
    let datePicker = ActionSheetDatePicker(title: strTitle,
                                           datePickerMode: .date,
                                           selectedDate: selectDate,
                                           doneBlock: { picker, date, origin in
        completion(0 , date as! Date)
    },
                                           cancel: { picker in
    },
                                           
                                           origin: sender)
    //        let secondsInWeek: TimeInterval = 7 * 24 * 60 * 60;
    //        datePicker?.minimumDate = Date(timeInterval: -secondsInWeek, since: Date())
    datePicker?.minimumDate = Date()
    if #available(iOS 13.4, *) {
        datePicker?.datePickerStyle = .wheels
    } else {
        // Fallback on earlier versions
    }
    datePicker?.setDoneButton(UIBarButtonItem(title: str.streSelect, style: .plain, target: nil, action: nil))
    datePicker?.setCancelButton(UIBarButtonItem(title: str.cancel, style: .plain, target: nil, action: nil))
//    datePicker?.toolbarButtonsColor = UIColor.black

//    if #available(iOS 14.0, *) {
//        datePicker?.datePickerStyle = .inline
//    }
    
    datePicker?.show()

}
