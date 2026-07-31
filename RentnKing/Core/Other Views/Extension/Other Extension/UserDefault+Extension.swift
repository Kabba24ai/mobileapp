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
    static let masterCode = "masterCode"
    static let useMasterCode = "useMasterCode"
    static let language = "language"
    static let userData = "userData"
    static let profile = "profile"
    static let accessToken = "access_token"
    static let baseURL = "base_url"

}


extension Notification.Name {
    static let languageUpdate = Notification.Name("languageUpdate")
    static let cartUpdated = Notification.Name("cartUpdated")
    static let scheduleCount = Notification.Name("scheduleCount")
    static let notificationCount = Notification.Name("notificationCount")

    static let startUploadData = Notification.Name("startUploadData")
    static let stopUploadData = Notification.Name("stopUploadData")
    static let updateCheckList = Notification.Name("updateCheckList")
    static let refreshMachineProfileList = Notification.Name("refreshMachineProfileList")

}


extension UserDefaults{
    var user: User? {

        get {
            guard dictionaryRepresentation().keys.contains(NSUDKey.userData)
                else { return nil }

            guard let data = data(forKey: NSUDKey.userData)
                else { return nil }

        
            do {
                if let archivedCategoryNames = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? User {
                    return archivedCategoryNames
                }
            } catch {
                return nil
            }
            
            return nil

        }
        set{
            if newValue == nil {
                removeObject(forKey: NSUDKey.userData)
            }
            else{
                
                do {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: newValue!, requiringSecureCoding: false)
                    set(data, forKey: NSUDKey.userData)
                    
                } catch {
                }
            }
            synchronize()
        }
    }
    
    var baseURL: String?{
        get {
            return string(forKey: NSUDKey.baseURL)
        }
        set {
            if newValue == nil {
                removeObject(forKey: NSUDKey.baseURL)
            }
            else{
                set(newValue, forKey: NSUDKey.baseURL)
            }
            synchronize()
        }
    }
    
    /// Keychain store for the auth token — encrypted at rest, device-only (not iCloud-backed),
    /// and readable by background uploads after the device's first unlock.
    private static let tokenKeychain = Keychain(service: "com.rentnking.auth")
        .accessibility(.afterFirstUnlockThisDeviceOnly)

    var accessToken: String?{
        get {
            // One-time migration: move any legacy token from UserDefaults into the Keychain.
            // Only drop the UserDefaults copy if the Keychain write succeeds, so a Keychain
            // failure can never log an existing user out.
            if let legacy = string(forKey: NSUDKey.accessToken), !legacy.isEmpty {
                do {
                    try UserDefaults.tokenKeychain.set(legacy, key: NSUDKey.accessToken)
                    removeObject(forKey: NSUDKey.accessToken)
                    synchronize()
                } catch {
                    // keep the legacy value; migration will be retried on the next read
                }
                return legacy
            }
            return try? UserDefaults.tokenKeychain.getString(NSUDKey.accessToken)
        }
        set {
            if let value = newValue, !value.isEmpty {
                try? UserDefaults.tokenKeychain.set(value, key: NSUDKey.accessToken)
            } else {
                try? UserDefaults.tokenKeychain.remove(NSUDKey.accessToken)
            }
            // Never leave a copy of the token in plaintext UserDefaults.
            removeObject(forKey: NSUDKey.accessToken)
            synchronize()
        }
    }
    
    
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
    
    
    var masterCode: String?{
        get {
            return string(forKey: NSUDKey.masterCode)
        }
        set {
            if newValue == nil {
                removeObject(forKey: NSUDKey.masterCode)
            }
            else{
                set(newValue, forKey: NSUDKey.masterCode)
            }
            synchronize()
        }
    }
  
    
    
    var useMasterCode: String?{
        get {
            return string(forKey: NSUDKey.useMasterCode)
        }
        set {
            if newValue == nil {
                removeObject(forKey: NSUDKey.useMasterCode)
            }
            else{
                set(newValue, forKey: NSUDKey.useMasterCode)
            }
            synchronize()
        }
    }
  
}
