//
//  AppDelegate.swift
//  RentnKing
//
//  Created by Jigar Khatri on 07/10/23.
//

import UIKit
import EventKit

var pendingDelivertCount : Int = 0
var pendingPickupCount : Int = 0
var pastDelivertCount : Int = 0
var pastPickupCount : Int = 0

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?

    let store = EKEventStore()
    var event:EKEvent!


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        setupKeyboard(true)
        
        //CREATE FOLDER
        createLicenseUploadFolder()
        
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
        
        
        

        self.getScheduleCount()
        
        //EVENT
        //self.eventAccess(
        return true
    }

    /// set orientations you want to be allowed in this property by default
//    var orientationLock = checkDeviceiPad() ? UIInterfaceOrientationMask.all : UIInterfaceOrientationMask.portrait
    var orientationLock = UIInterfaceOrientationMask.portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return self.orientationLock
    }
}







extension AppDelegate :WebServiceHelperDelegate{
    func getScheduleCount(){

        //Declaration URL
        let strURL = "\(Url.scheduleListCound.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "scheduleListCound"
        webHelper.methodType = "get"
        webHelper.strURL = strURL
        webHelper.dictType = [:]
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = false
        webHelper.callAPI()
    }
    
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            print(data)
            if strRequest == "scheduleListCound"{
                if let dicData = data["data"] as? NSDictionary{
                    pendingDelivertCount = Int(dicData.getStringForID(key: "pendingDeliveryCount")) ?? 0
                    pendingPickupCount = Int(dicData.getStringForID(key: "pendingPickupCount")) ?? 0
                    pastDelivertCount = Int(dicData.getStringForID(key: "pastPendingDeliveryCount")) ?? 0
                    pastPickupCount = Int(dicData.getStringForID(key: "pastPendingPickupCount")) ?? 0
                    NotificationCenter.default.post(name: .scheduleCount, object: nil)

                    
                    UIApplication.shared.applicationIconBadgeNumber = pendingDelivertCount + pendingPickupCount + pastDelivertCount + pastPickupCount
                }
            }
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
    }
}

