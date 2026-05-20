//
//  UserNotification.swift
//  OGI
//
//  Created by Jigar Khatri on 30/04/21.
//

import UIKit
import UserNotifications

class UserNotification: NSObject{
    
    override init() {
        super.init()
//        UNUserNotificationCenter.current().delegate = self
    }
    
    static let shared = UserNotification()
    
    func requestNotificationPermission(completionHandler: @escaping (_ status:UNAuthorizationStatus ) -> ()){
        
        UNUserNotificationCenter.current().getNotificationSettings { (notificationSettings) in
            switch notificationSettings.authorizationStatus {
            case .notDetermined:
                self.requestAuthorization(completionHandler: { (success) in
                    completionHandler((success ? .authorized : .denied))
                })
                break
            default:
                completionHandler(notificationSettings.authorizationStatus)
                break
            }
        }
    }
    
    private func requestAuthorization(completionHandler: @escaping (_ success: Bool) -> ()) {
        // Request Authorization
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { (success, error) in
            if let error = error {
                print("Request Authorization Failed (\(error), \(error.localizedDescription))")
            }
            completionHandler(success)
        }
    }
    
    func scheduleLocalNotification(title:String, subTitle:String?, body:String?, date:Date?, imageBundlePath:URL?, identifier:String) {
        
        requestNotificationPermission { (status) in
            
            switch status {
            case .authorized:
                do {
                
                    // Create Notification Content
                    let notificationContent = UNMutableNotificationContent()

                    // Configure Notification Content
                    notificationContent.title = title
                    notificationContent.subtitle = subTitle ?? ""
                    notificationContent.body = body ?? ""
                    notificationContent.sound = .default
                    
                    if let _url = imageBundlePath {
                        let attachment = try! UNNotificationAttachment(identifier: "image", url: _url, options: [UNNotificationAttachmentOptionsThumbnailHiddenKey:NSNumber(booleanLiteral: false)])
                        notificationContent.attachments = [attachment]
                    }
                    

                    // Add Trigger
                    var notificationTrigger :UNNotificationTrigger? = nil
                    
                    if let _date = date{
                        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: _date)
                        notificationTrigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
                    }
                    
                    // Create Notification Request
                    let notificationRequest = UNNotificationRequest(identifier: identifier, content: notificationContent, trigger: notificationTrigger)

                    // Add Request to User Notification Center
                    UNUserNotificationCenter.current().add(notificationRequest) { (error) in
                        if let error = error {
                            print("Unable to Add Notification Request (\(error), \(error.localizedDescription))")
                        }
                    }
                    
                    break
                }
                
            default:
                break
            }
        }
    }
}

//extension UserNotification: UNUserNotificationCenterDelegate{
//
//    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
//        completionHandler([.alert,.sound])
//    }
//
//}
