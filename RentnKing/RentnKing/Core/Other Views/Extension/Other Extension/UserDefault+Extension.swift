//
//  NSUserDefault+Extension.swift
//  BAYNOUNAH
//
//  Created by Jigar Khatri on 22/06/22.
//

import Foundation
import ObjectMapper

//Never user NSUDKey enum directly, use UserDefaults's Extenion's property only
enum NSUDKey {
    static let deviceToken = "deviceToken"
    static let language = "language"
    static let userData = "userData"
    static let profile = "profile"
}


extension Notification.Name {
    static let languageUpdate = Notification.Name("languageUpdate")
    static let cartUpdated = Notification.Name("cartUpdated")
    static let scheduleCount = Notification.Name("scheduleCount")

}


extension UserDefaults{
//    var user: User? {
//
//        get {
//            guard dictionaryRepresentation().keys.contains(NSUDKey.userData)
//                else { return nil }
//
//            guard let data = data(forKey: NSUDKey.userData)
//                else { return nil }
//
//        
//            do {
//                if let archivedCategoryNames = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? User {
//                    return archivedCategoryNames
//                }
//            } catch {
//                return nil
//            }
//            
//            return nil
//
//        }
//        set{
//            if newValue == nil {
//                removeObject(forKey: NSUDKey.userData)
//            }
//            else{
//                
//                do {
//                    let data = try NSKeyedArchiver.archivedData(withRootObject: newValue!, requiringSecureCoding: false)
//                    set(data, forKey: NSUDKey.userData)
//                    
//                } catch {
//                }
//            }
//            synchronize()
//        }
//    }
//    
    
    
    var language: String{
        get {
            if let result = string(forKey: NSUDKey.language){
                return result
            }
            else{
                
                if let currentLanguages = NSLocale.preferredLanguages.first{
                    
                    let languageCode = currentLanguages.substring(to: 2)
                    
                    if Bundle.main.localizations.contains(languageCode){
                        set(languageCode, forKey: NSUDKey.language)
                        synchronize()
                        
                        return languageCode
                    }
                    else{
                        if let firstLanguage = Bundle.main.localizations.first{
                            set(firstLanguage, forKey: NSUDKey.language)
                            synchronize()
                            
                            return firstLanguage
                        }
                        else{
                            return "Base"
                        }
                    }
                }
                else{
                    return "Base"
                }
            }
        }
        set {
            set(newValue, forKey: NSUDKey.language)
            synchronize()
            languageChangeNotification()

            NotificationCenter.default.post(name: .languageUpdate, object: nil, userInfo: nil)
        }
    }
    
    var deviceToken: String?{
        get {
            return string(forKey: NSUDKey.deviceToken)
        }
        set {
            if newValue == nil {
                removeObject(forKey: NSUDKey.deviceToken)
            }
            else{
                set(newValue, forKey: NSUDKey.deviceToken)
            }
            synchronize()
        }
    }
    
  
}
