//
//  LoginModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 07/01/26.
//

import Foundation
import UIKit


extension LoginViewController : WebServiceHelperDelegate{
    struct CustomerParameater: Codable {
        var code : String
    }
    
    func getCustomerDataAPI(CustomerParameater : CustomerParameater){
        guard let parameater = try? CustomerParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "https://api.rentnking.com/api/admin/v1/clients"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "clients"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }

    
    func loginAPI(LoginParameater : LoginParameater){
        guard let parameater = try? LoginParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.login.absoluteString!)"
        print(strURL)
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "login"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callAPI()
    }

    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int, orderid: String, strChecklistType: String) {
        indicatorHide()
        print(KabbaAPIClient.redactedForLog(data))   // never the token

        if data.getStringForID(key: "success") == "1"{ 
            if strRequest == "clients"{
                if let userData = data["client"] as? NSDictionary{
                    UserDefaults.standard.baseURL = userData.getStringForID(key: "api_url")
                   
                }
            }
            else if strRequest == "login"{
                if let userData = data["user"] as? NSDictionary{
                    
                    //SAVE USER DATA
                    let userObj = User()
                    userObj.id = userData.getStringForID(key: "id")
                    userObj.email = userData.getStringForID(key: "email")
                    userObj.full_name = userData.getStringForID(key: "full_name")
                    
                    
                    
                    //SAVE OBJECT
                    UserDefaults.standard.user = userObj
                    // Phase 5: written to the shared Keychain item the extension reads too.
                    // Phase 6A: proven readable BEFORE anything can use it. A credential that did not
                    // persist must not reach Home only to be bounced by a 401 a moment later — every
                    // request after this point (device-token, Home, the Sync Engine) reads it back.
                    let token: String = userData.getStringForID(key: "token") ?? ""
                    UserDefaults.standard.accessToken = token
                    let stored = UserDefaults.standard.accessToken
                    KabbaAPIClient.traceLogin(response: data, tokenPresent: !token.isEmpty, storedAndReadBack: stored == token && !token.isEmpty)
                    guard !token.isEmpty, stored == token else {
                        UserDefaults.standard.user = nil
                        UserDefaults.standard.accessToken = nil
                        let code = KabbaSessionKeychain.shared.lastDiagnostics?.steps.last.map { " (Keychain \($0.status))" } ?? ""
                        showAlertMessage(strMessage: "Kabba could not store your sign-in securely on this phone\(code). Please try again.")
                        return
                    }
                    // Phase 5: remember the server's description of this session (expiry, scope) — never the token.
                    KabbaSession.start(loginResponse: data)
                    
                    //SET DATA TO EXTENSION (base URL only — the token is no longer copied here)
                    defaultsToExtension?.set(Application.BaseURL_NEW, forKey: "api_url")
                    defaultsToExtension?.removeObject(forKey: "auth_token")

                    // Sync Engine: lift any authentication pause and drain what was captured while signed out.
                    KabbaSync.sessionDidStart()
                    defaultsToExtension?.synchronize()
                    
                    if UserDefaults.standard.user != nil{
                        GlobalMainConstants.appDelegate?.updateToken(DeviceTokenParameater: AppDelegate.DeviceTokenParameater(device_token: strUUID, fcm_token: UserDefaults.standard.deviceToken ?? ""))
                    }
                    
                    
                    //MOVE TO TABBAR
                    let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TABBAR, bundle: nil)
                    let tabBariewController = storyBoard.instantiateViewController(withIdentifier: "TabbarViewController") as! TabbarViewController
                    GlobalMainConstants.appDelegate?.window?.rootViewController = tabBariewController
                    GlobalMainConstants.appDelegate?.window?.makeKeyAndVisible()

                }
            }
        }
        else{
            indicatorHide()
            if strRequest != "clients"{
                showAlertMessage(strMessage: data.getStringForID(key: "message"))
            }
            else if strRequest == "clients"{
                showAlertMessage(strMessage: "Please enter a valid company code.")
            }

            
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        showAlertMessage(strMessage: "The email address or password you entered is incorrect. Please try again.")
    }
}
