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
    
    /// Pre-Phase-5 app-private Keychain item — read only to migrate it into the shared item.
    private static let tokenKeychain = Keychain(service: "com.rentnking.auth")
        .accessibility(.afterFirstUnlockThisDeviceOnly)

    /// Migration runs once per process; afterwards reads go straight to the shared item.
    private static var sharedTokenMigrationChecked = false

    /// Phase 5: the bearer token lives in ONE shared Keychain item (KabbaSessionKeychain —
    /// app-group access group, after-first-unlock, this device only) that the share
    /// extension reads too. Older copies (plaintext UserDefaults, the app-private Keychain,
    /// the app-group `auth_token` default) are moved into it once and purged — but only
    /// after the shared write succeeded, so a Keychain failure can never log anyone out.
    var accessToken: String?{
        get {
            let shared = KabbaSessionKeychain.shared
            if UserDefaults.sharedTokenMigrationChecked {
                return shared.read(KabbaSessionKeychain.accessTokenKey)
            }
            let group = UserDefaults(suiteName: KabbaSharedClientHeaders.appGroup)
            let outcome = SessionCredentialMigration.run(shared: shared, legacy: [
                .init(name: "user_defaults",
                      read: { [weak self] in self?.string(forKey: NSUDKey.accessToken).flatMap { $0.isEmpty ? nil : $0 } },
                      purge: { [weak self] in self?.removeObject(forKey: NSUDKey.accessToken); self?.synchronize() }),
                .init(name: "private_keychain",
                      read: { (try? UserDefaults.tokenKeychain.getString(NSUDKey.accessToken)).flatMap { $0 }.flatMap { $0.isEmpty ? nil : $0 } },
                      purge: { try? UserDefaults.tokenKeychain.remove(NSUDKey.accessToken) }),
                .init(name: "app_group_defaults",
                      read: { group?.string(forKey: "auth_token").flatMap { $0.isEmpty ? nil : $0 } },
                      purge: { group?.removeObject(forKey: "auth_token"); group?.synchronize() }),
            ])
            // Stop re-checking once the shared item holds the token (or there is no token anywhere);
            // a failed shared write keeps returning the legacy value and retries on the next read.
            UserDefaults.sharedTokenMigrationChecked = outcome.token == nil || shared.read(KabbaSessionKeychain.accessTokenKey) != nil
            return outcome.token
        }
        set {
            let shared = KabbaSessionKeychain.shared
            if let value = newValue, !value.isEmpty {
                try? shared.write(value, key: KabbaSessionKeychain.accessTokenKey)
            } else {
                shared.remove(KabbaSessionKeychain.accessTokenKey)
            }
            // Never leave a copy of the token anywhere else.
            removeObject(forKey: NSUDKey.accessToken)
            try? UserDefaults.tokenKeychain.remove(NSUDKey.accessToken)
            let group = UserDefaults(suiteName: KabbaSharedClientHeaders.appGroup)
            group?.removeObject(forKey: "auth_token")
            group?.synchronize()
            synchronize()
            UserDefaults.sharedTokenMigrationChecked = true
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
