//
//  NotificaiotnFile.swift
//  Now TV!
//
//  Created by Jigar Khatri on 29/08/23.
//

import UIKit
import Foundation
import FirebaseCore
import FirebaseMessaging



extension AppDelegate : UNUserNotificationCenterDelegate{
    
    func setFireBase_Notificaiton(application: UIApplication){
        
        //SET UUID
        let uuid_key = "\(Bundle.main.bundleIdentifier ?? "")_uuid"
        if let uuid = KeychainWrapper.passwordStringForVPNID(uuid_key){
            if uuid == ""{
                KeychainWrapper.setPassword(UUID().uuidString, forVPNID: uuid_key)
                if let uuid = KeychainWrapper.passwordStringForVPNID(uuid_key){
                    strUUID = uuid
                }
            }
            else{
                strUUID = uuid
            }
        }
        else{
            KeychainWrapper.setPassword(UUID().uuidString, forVPNID: uuid_key)
            if let uuid = KeychainWrapper.passwordStringForVPNID(uuid_key){
                strUUID = uuid
            }
        }
        
        
        //FIREBASE CONFIGURE
        FirebaseApp.configure()
        Messaging.messaging().delegate = self

     
        
        //Push Notification Register
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
            (granted, error) in
            if let error = error {
                debugPrint("[AppDelegate] requestAuthorization error: \(error.localizedDescription)")
                return
            }
            UNUserNotificationCenter.current().getNotificationSettings(completionHandler: { settings in
                if settings.authorizationStatus != .authorized {
                    return
                }
                DispatchQueue.main.async(execute: {
                    UIApplication.shared.registerForRemoteNotifications()
                })
            })
            //Parse errors and track state
        }
        application.registerForRemoteNotifications()
    }
}


//MARK: - GET DEVICE TOKEN AND MOVE SCREEN
extension AppDelegate : MessagingDelegate{
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        let deviceTokenString = deviceToken.hexString
        #if DEBUG
        print(deviceTokenString)
        #endif
        ////        UIPasteboard.general.string = "device token \(deviceTokenString)"
        //        UserDefaults.standard.deviceToken = deviceTokenString
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) {
        
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        #if DEBUG
        print("\(String(describing: fcmToken))")
        #endif
        UserDefaults.standard.deviceToken = fcmToken
        
        let dataDict:[String: String] = ["token": fcmToken ?? ""]
        NotificationCenter.default.post(name: Notification.Name("FCMToken"), object: nil, userInfo: dataDict)
        // TODO: If necessary send token to application server.
        // Note: This callback is fired at each app startup and whenever a new token is generated.
        
        if UserDefaults.standard.user != nil{
            self.updateToken(DeviceTokenParameater: DeviceTokenParameater(device_token: strUUID, fcm_token: fcmToken ?? ""))
        }

        // Dispatch offline (Phase 2): this callback fires at every launch and on each FCM token
        // rotation — (re)register the installation for silent Dispatch wakes.
        registerDispatchInstallation(trigger: .tokenRefresh)
    }

    /// Registers THIS installation (X-Device-Id, added by the API client) with its FCM token for
    /// silent Dispatch wakes. Installation-scoped: logout / user switching never unregister, and
    /// there is no unregister call. Needs a signed-in session; a no-op otherwise.
    func registerDispatchInstallation(trigger: DispatchInstallationRegistration.Trigger) {
        let fcmToken = UserDefaults.standard.deviceToken
        guard let client = KabbaAPIClient.shared,
              DispatchInstallationRegistration.shouldRegister(fcmToken: fcmToken, hasSession: !(client.configuration.accessToken() ?? "").isEmpty),
              let token = fcmToken else {
            return
        }

        let request = DispatchInstallationRegistration.request(
            fcmToken: token,
            operationId: "op-install-" + UUID().uuidString.lowercased()
        )
        client.perform(request) { result in
            #if DEBUG
            switch result {
            case .response(let response):
                print("[DispatchWake] registration (\(trigger.rawValue)): \(DispatchInstallationRegistration.outcome(of: response))")
            case .failure(let error):
                print("[DispatchWake] registration (\(trigger.rawValue)) failed: \(error)")
            }
            #endif
        }
    }
    
    func application(application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: NSError) {
        print(error)
        //UIPasteboard.general.string = error.localizedDescription
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
      // If you are receiving a notification message while your app is in the background,
      // this callback will not be fired till the user taps on the notification launching the application.
      // TODO: Handle data of notification

      // Dispatch offline: a silent Dispatch wake is invisible — no badge, no UI. Phase 3 reconciles
      // the durable working set and answers iOS exactly once (newData / noData / failed) within
      // the background budget.
        if let trigger = DispatchWake.trigger(fromPushUserInfo: userInfo) {
            DispatchOfflineSync.handleWake(trigger, completionHandler: completionHandler)
            return
        }

      // With swizzling disabled you must let Messaging know about the message, for Analytics
      // Messaging.messaging().appDidReceiveMessage(userInfo)
        UIApplication.shared.applicationIconBadgeNumber += 1

    
      // Print full message.
      print(userInfo)

      completionHandler(UIBackgroundFetchResult.newData)
    }
    
    
    @available(iOS 10.0, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        completionHandler([UNNotificationPresentationOptions.alert,UNNotificationPresentationOptions.badge])

    }
        
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        //  let rootViewController = self.window!.rootViewController as! UINavigationController
        dicNotificationData = response.notification.request.content.userInfo as NSDictionary
        print(dicNotificationData)
        switch response.actionIdentifier {
        case UNNotificationDismissActionIdentifier:
            print("Dismiss Action")
        case UNNotificationDefaultActionIdentifier:
            print("Select")
            if isHomeScreen{
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    self.moveToNotificaitonScreen(dicData: dicNotificationData)
                }
            }
        default:
            print("default")
        }
        completionHandler()
    }
    
    
    func moveToNotificaitonScreen(dicData  : NSDictionary){
        if dicData.count == 0{
            return
        }
       
        //REDRIRECT TO SCREEN
        let ViewController = UIApplication.getTopViewController()
        if dicData.getStringForID(key: "order_unique_id") != ""{
            if let orderID = dicData.getStringForID(key: "order_unique_id"){

                //MOVE TO SHOW SCREEN
                dicNotificationData = [:]
                
                //SHOW DETAILS SCREEN
                let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
                if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
                    newViewController.strOrderUniqueId = orderID
                    newViewController.OrderID = dicData.getStringForID(key: "order_id")
                    newViewController.isPresent = true
                    let vieweNavigationController = UINavigationController(rootViewController: newViewController)
                    vieweNavigationController.modalPresentationStyle = .fullScreen
                    ViewController?.present(vieweNavigationController, animated: true, completion: nil)
                }

            }
        }

    }
}
