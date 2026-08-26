//
//  WebServiceHelper.swift
//  HealthyBlackMen
//
//  Created by Jigar Khatri on 30/04/21.
//

import UIKit
import Alamofire
import AVFoundation

/// Phase 5 — the two answers the extension must explain instead of "something went wrong".
/// (Phase 6A: the definition had been dropped by the Phase 5 edit while its uses stayed —
/// caught by the first real extension-target build.)
enum KabbaExtensionError: LocalizedError {
    /// HTTP 401: the shared session is gone (expired, revoked, or the main app signed out).
    case sessionExpired
    /// HTTP 426: this build is below the minimum the server supports.
    case updateRequired

    static func from(status: Int) -> KabbaExtensionError? {
        switch status {
        case 401: return .sessionExpired
        case 426: return .updateRequired
        default:  return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .sessionExpired: return "Your Kabba session has expired. Open the Kabba app, sign in again, then try again."
        case .updateRequired: return "This version of the Kabba app is no longer supported. Update it from the App Store to continue."
        }
    }
}

var webservice_Nool_Load : Bool = false

// MARK: - Protocol -
@objc protocol WebServiceHelperDelegate{
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index : Int)
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index : Int)
    func appDataDidFail(_ error: Error, request strRequest: String)
}

class WebServiceHelper: NSObject {

    var strMethodName = ""
    var selectIndex : Int = 0
    weak var delegate: WebServiceHelper?
    var strURL : String = ""
    var jsonString = ""
    var methodType : String = ""
    var dictType : [String : Any] = [:]
    var dictHeader : NSDictionary = [:]
    var indicatorShowOrHide : Bool = true
    var serviceWithAlert : Bool = false
    var serviceWithAlertDefault : Bool = false
    var serviceWithAlertErrorMessage : Bool = false
    var imageUpload : UIImage!
    var imageUploadName : String = ""
    var showLogForCallingAPI : Bool = true
    var strAuthorize : String = ""
    var strUploadType : String = ""

    var arr_MutlipleimagesAndVideo : NSMutableArray = []
    var arr_MutlipleimagesAndVideoType : NSMutableArray = []
    var arr_MutlipleimagesAndVideoName : NSMutableArray = []
    var arr_Mutlipleimages : [[String : Any]] = []
    var delegateWeb:WebServiceHelperDelegate?
    
    
    //MARK:- NO INTERNET CONNECTION DELEGATE METHOD
    func ReceiveInternetNotify(strMethodName: String) {
        callAPI()
    }
    
    struct Item: Decodable {
        let id: String
        let sortingId: String
        let name: String
    }

    struct ErrorData : Decodable {
        let status : String
        let msg: String
    }
    
    // MARK: - StartDowload Method -
    
    func callAPI(){
        
        if NetworkReachabilityManager()!.isReachable {
            do {
                
                webservice_Nool_Load = true
                //CONVERT DIC TO DATA
                var jsonData = try JSONSerialization.data(withJSONObject: self.dictType, options: .prettyPrinted)
                if jsonString != ""{
                    jsonData = jsonString.data(using: String.Encoding(rawValue: String.Encoding.utf8.rawValue))!
                }
                
                //SET REWUEST
                let strUrl = URL(string: "\(self.strURL)")!
                var request = URLRequest(url: strUrl)
                
                //Declaration for service for get,post or other..
                if methodType == "post"{
                    request.httpMethod = HTTPMethod.post.rawValue
                }
                else  if methodType == "delete"{
                    request.httpMethod = HTTPMethod.delete.rawValue
                }
                else if methodType == "put"{
                    request.httpMethod = HTTPMethod.put.rawValue
                }
                else if methodType == "patch"{
                    request.httpMethod = HTTPMethod.patch.rawValue
                }
                else if methodType == "delete"{
                    request.httpMethod = HTTPMethod.delete.rawValue
                }
                else{
                    request.httpMethod = HTTPMethod.get.rawValue
                }
                
                
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                // Phase 5: the bearer token comes from the shared Keychain item the main app writes;
                // the pre-Phase-5 app-group `auth_token` copy is read only until the main app has
                // launched once after the upgrade and purged it.
                if let token = KabbaSessionKeychain.shared.read(KabbaSessionKeychain.accessTokenKey)
                    ?? UserDefaults(suiteName: KabbaSharedClientHeaders.appGroup)?.string(forKey: "auth_token"), !token.isEmpty {
                    request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                // Phase 5: the same request-context headers as the main app (X-Request-Id, X-Mobile-*, X-Device-Id).
                for (name, value) in KabbaSharedClientHeaders.headers(requestIdPrefix: "ios-ext") {
                    request.setValue(value, forHTTPHeaderField: name)
                }
                
                //Pass paramater with value data
                //if methodType == "post" || methodType == "put"{
                if dictType.count != 0{
                    request.httpBody = jsonData
                }
                //}
                
                
                //Calling service
                let manager = AF
                manager.sessionConfiguration.timeoutIntervalForRequest = 10
                manager.request(request).responseData{
                    (response) in
                    
                    // Phase 5: HTTP status is authoritative for the session / version contract.
                    if let status = response.response?.statusCode, let contractError = KabbaExtensionError.from(status: status) {
                        webservice_Nool_Load = false
                        self.delegateWeb?.appDataDidFail(contractError, request: self.strMethodName)
                        return
                    }

                    switch response.result {
                    case .success(let data):
                        do {
                            let response = try JSONSerialization.jsonObject(with: data)
                            if let dict = response as? NSDictionary{
                                let error : String = dict.getStringForID(key: "error")
                                if error == "INVALID_TOKEN"{
                                    webservice_Nool_Load = false
                                }
                                else{
                                    //Check condition for response success or not and notificatino show with coming alert in service response
                                    if self.validationForServiceResponse(dict){
                                        webservice_Nool_Load = false
                                        self.delegateWeb?.appDataDidSuccess(dict, request: self.strMethodName, index: self.selectIndex)
                                    }else{
                                        webservice_Nool_Load = false
                                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                        self.delegateWeb?.appDataDidFail(err, request: self.strMethodName)
                                    }
                                }
                            }
                            else if let arr = response as? NSArray{
                                self.delegateWeb?.appDataArraySuccess(arr, request: self.strMethodName, index: self.selectIndex)
                            }
                            else{
                                webservice_Nool_Load = false
                                let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                self.delegateWeb?.appDataDidFail(err, request: self.strMethodName)

                            }
                        }
                        catch {
                            webservice_Nool_Load = false
                            let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                            self.delegateWeb?.appDataDidFail(err, request: self.strMethodName)
                        }
                        
                    case .failure(_):
                        webservice_Nool_Load = false
                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                        self.delegateWeb?.appDataDidFail(err, request: self.strMethodName)
                    }
                }
                
            }
            catch {
                //Alert show for Header
                webservice_Nool_Load = false
            }
            
        }
    }
    
    
    
//    func callAPI(){
//        
//        if NetworkReachabilityManager()!.isReachable {
//            do {
//                
//                webservice_Nool_Load = true
//                DispatchQueue.main.async {
//                    if self.indicatorShowOrHide == true{
//                    }
//                }
//
//                //Base user for calling service
//                var headers: HTTPHeaders = [:]
//                if dictHeader.count != 0{
//                    if strMethodName == "sendMessage"{
//                        headers = ["Secret-token" : "SGivAH19nOc7BER9s21es08vY1J5QCmV"]
//                    }
//                }
//                
//                //Calling service
//                let manager = AF
//                manager.sessionConfiguration.timeoutIntervalForRequest = 10
//                
//                manager.request(self.strURL, method: methodType == "post" ? .post : .get, parameters: self.dictType, encoding: URLEncoding.default, headers: headers).responseData { response in
//                    
//                    switch response.result {
//                    case .success(let data):
//                        do {
//                            let response = try JSONSerialization.jsonObject(with: data)
//                            if let dict = response as? NSDictionary{
//                                let error : String = dict.getStringForID(key: "error")
//                                if error == "INVALID_TOKEN"{
//                                    webservice_Nool_Load = false
//                                    
//                                }
//                                else{
//                                    //Check condition for response success or not and notificatino show with coming alert in service response
//                                    if self.validationForServiceResponse(dict){
//                                        webservice_Nool_Load = false
//                                        self.delegateWeb?.appDataDidSuccess(dict, request: self.strMethodName, index: self.selectIndex)
//                                    }else{
//                                        webservice_Nool_Load = false
//                                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
//                                        self.delegateWeb?.appDataDidFail(err, request: self.strMethodName)
//                                    }
//                                }
//                            }
//                            else if let arr = response as? NSArray{
//                                self.delegateWeb?.appDataArraySuccess(arr, request: self.strMethodName, index: self.selectIndex)
//                            }
//                            else{
//                                webservice_Nool_Load = false
//                                let err = NSError(domain: "data not found", code: 401, userInfo: nil)
//                                self.delegateWeb?.appDataDidFail(err, request: self.strMethodName)
//
//                            }
//                        }
//                        catch {
//                            webservice_Nool_Load = false
//                            let err = NSError(domain: "data not found", code: 401, userInfo: nil)
//                            self.delegateWeb?.appDataDidFail(err, request: self.strMethodName)
//
//                        }
//
//                    case .failure(_):
//                        webservice_Nool_Load = false
//                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
//                        self.delegateWeb?.appDataDidFail(err, request: self.strMethodName)
//                    }
//                 }
//                
//            }
//
//        }else{
//            webservice_Nool_Load = false
//
//        }
//    }
    
    
    
    // MARK: - Other Method -
    func validationForServiceResponse(_ response: NSDictionary) -> Bool{

        DispatchQueue.main.async {
            //Indication show hide with varible when user calling service
            if self.indicatorShowOrHide == true{
            }
        }

        if response["code"] != nil{
            let responseKey = Int(response.getStringForID(key: "code")) ?? 0
            
            //101 invalide user or already registartion with current credincial
            switch responseKey {
            case 100,101,102:
                if self.serviceWithAlert || self.serviceWithAlertErrorMessage {

                    //Alert show for Header
                    print("\(response["msg"] ?? "")")
//                    showAlertMessage(strMessage: "\(response["msg"] ?? "")")
                }

                return false
            case 401:
                
                //Alert show for Header
                print("\(response["msg"] ?? "")")
//                showAlertMessage(strMessage: "\(response["msg"] ?? "")")
                return false
            case 105:
//                //USER LOG OUT
//                LogOtuUser()
//
                return false
            default:
                if self.serviceWithAlert {
                    
//                  messageBar.MessageShow(title: response["msg"]! as! String as NSString, alertType: MessageView.Layout.cardView, alertTheme: .success, TopBottom: true)
                }else if self.serviceWithAlertDefault {

//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
//                        let alert = UIAlertController(title: Application.appName, message: response["msg"]! as? String, preferredStyle: UIAlertController.Style.alert)
//                        alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
//                        GlobalConstants.appDelegate?.window?.rootViewController?.present(alert, animated: true, completion: nil)
//                    })
                }
                break
            }
        }
        return true
    }
}

