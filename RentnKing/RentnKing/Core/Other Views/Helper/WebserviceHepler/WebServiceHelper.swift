//
//  WebServiceHelper.swift
//  HealthyBlackMen
//
//  Created by Jigar Khatri on 30/04/21.
//

import UIKit
import Alamofire
import AVFoundation

var webservice_Nool_Load : Bool = false

// MARK: - Protocol -
@objc protocol WebServiceHelperDelegate{
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index : Int, orderid: String)
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index : Int)
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl : String)
}

class WebServiceHelper: NSObject {

    var strMethodName = ""
    var selectIndex : Int = 0
    var strOrderID : String = ""
    weak var delegate: WebServiceHelper?
    var strURL : String = ""
    var jsonString = ""
    var methodType : String = ""
    var dictType : [String : Any] = [:]
    var arryType : [[String : Any]] = []
    var dictHeader : NSDictionary = [:]
    var indicatorShowOrHide : Bool = true
    var isFavouretScreen : Bool = true
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
                DispatchQueue.main.async {
                    if self.indicatorShowOrHide == true{
                        indicatorShow()
                    }
                }

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
                if let accessToken = UserDefaults.standard.accessToken{
                    request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                }
                request.addValue(UserDefaults.standard.language, forHTTPHeaderField: "lang")

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
                    
                    switch response.result {
                    case .success(let data):
                        do {
                            let response = try JSONSerialization.jsonObject(with: data)
                            if let dict = response as? NSDictionary{
                                let error : String = dict.getStringForID(key: "error")
                                if error == "INVALID_TOKEN"{
                                    indicatorHide()
                                    webservice_Nool_Load = false
                                }
                                else{
                                    //Check condition for response success or not and notificatino show with coming alert in service response
                                    if self.validationForServiceResponse(dict){
                                        webservice_Nool_Load = false
                                        self.delegateWeb?.appDataDidSuccess(dict, request: self.strMethodName, index: self.selectIndex, orderid: "")
                                    }else{
                                        webservice_Nool_Load = false
                                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                        self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
                                    }
                                }
                            }
                            else if let arr = response as? NSArray{
                                self.delegateWeb?.appDataArraySuccess(arr, request: self.strMethodName, index: self.selectIndex)
                            }
                            else{
                                webservice_Nool_Load = false
                                let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)

                            }
                        }
                        catch {
                            webservice_Nool_Load = false
                            let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                            self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)

                        }
                        
                    case .failure(_):
                        webservice_Nool_Load = false
                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                        self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
                    }
                 }
                
            }
            catch {
                
                //Alert show for Header
                webservice_Nool_Load = false
                showAlertMessage(strMessage: "\(self.strMethodName) \(str.somethingWentWrong)")
            }

        }else{
//            webservice_Nool_Load = false
//            indicatorHide()
//            
//            let ViewController = UIApplication.getTopViewController()
//            var NoInternetNaNavigation: UINavigationController!
//            if let topVC = UIApplication.getTopViewController() {
//                if !(topVC is NoInternetViewController){
//                    let storyBoard: UIStoryboard = UIStoryboard(name: GlobalConstants.LOGIN_MODEL, bundle: nil)
//                    if let newViewController = storyBoard.instantiateViewController(withIdentifier: "NoInternetViewController") as? NoInternetViewController{
//                        NoInternetNaNavigation = UINavigationController(rootViewController: newViewController)
//                        NoInternetNaNavigation.modalPresentationStyle = .fullScreen
//                        topVC.present(NoInternetNaNavigation, animated: true, completion: nil)
//                    }
//                }
//            }
        }
    }
    
    
    // MARK: - StartDowload Method -
    func callAPIwithCompletation(completion: @escaping (_ data: NSDictionary?, _ arr: NSArray?, _ isDic: Bool, _ error: Error?) -> Void){
        
        if NetworkReachabilityManager()!.isReachable {
            do {
                
                webservice_Nool_Load = true
                DispatchQueue.main.async {
                    if self.indicatorShowOrHide == true{
                        indicatorShow()
                    }
                }

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
                if let accessToken = UserDefaults.standard.accessToken{
                    request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                }
                request.addValue(UserDefaults.standard.language, forHTTPHeaderField: "lang")

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
                    
                    switch response.result {
                    case .success(let data):
                        do {
                            let response = try JSONSerialization.jsonObject(with: data)
                            if let dict = response as? NSDictionary{
                                let error : String = dict.getStringForID(key: "error")
                                if error == "INVALID_TOKEN"{
                                    indicatorHide()
                                    webservice_Nool_Load = false
                                }
                                else{
                                    //Check condition for response success or not and notificatino show with coming alert in service response
                                    if self.validationForServiceResponse(dict){
                                        webservice_Nool_Load = false
                                        completion(dict, nil, true, nil)
                                    }else{
                                        webservice_Nool_Load = false
                                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                        completion(nil, nil, false, err)
                                    }
                                }
                            }
                            else if let arr = response as? NSArray{
                                completion(nil, arr, false, nil)
                            }
                            else{
                                webservice_Nool_Load = false
                                let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                completion(nil, nil, false, err)
                            }
                        }
                        catch {
                            webservice_Nool_Load = false
                            let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                            completion(nil, nil, false, err)
                        }
                        
                    case .failure(_):
                        webservice_Nool_Load = false
                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                        completion(nil, nil, false, err)
                    }
                 }
                
            }
            catch {
                
                //Alert show for Header
                webservice_Nool_Load = false
                showAlertMessage(strMessage: "\(self.strMethodName) \(str.somethingWentWrong)")
            }

        }
    }
    
    func startUploadingMultipleImages() {
        var str_accessToken = ""
        
        if let accessToken = UserDefaults.standard.accessToken {
            str_accessToken = accessToken
        }
        
        if NetworkReachabilityManager()!.isReachable {
            do {
                webservice_Nool_Load = true
                
                //Indication show hide with varible when user calling service
                (self.indicatorShowOrHide == true) ? (indicatorShow()) : (indicatorHide())
                
                print(self.arr_Mutlipleimages.count)
                
                // Create upload request using Alamofire
                AF.upload(multipartFormData: { multipartFormData in
                    // Add images to request
                    for i in 0..<self.arr_Mutlipleimages.count {
                        let obj = self.arr_Mutlipleimages[i]
                        if let image = obj["img"] as? UIImage,
                           let imgData = image.jpegData(compressionQuality: 0.25) {
                            let imgName = obj["name"] as? String ?? "image\(i).jpg"
                            let imgUploadKey = obj["key"] as? String ?? "image"
                            
                            multipartFormData.append(imgData,
                                                     withName: imgUploadKey,
                                                     fileName: imgName,
                                                     mimeType: "image/jpeg")
                        }
                    }
                    
                    // Add text parameters
                    for (key, value) in self.dictType {
                        print(key)
                        print(value)
                        if let stringValue = value as? String {
                            if let data = stringValue.data(using: .utf8) {
                                multipartFormData.append(data, withName: key)
                            }
                        }
                        else if let array = value as? [[String: Any]] {
                            do {
                                
                                let jsonData = try JSONSerialization.data(withJSONObject: array, options: .prettyPrinted)
                                multipartFormData.append(jsonData, withName: key)

                            } catch {
                                print("Error serializing JSON:", error)
                            }
                        }
                    }
                }, to: strURL, method: methodType == "patch" ? .patch : .post, headers: [
                    "Authorization": "Bearer \(str_accessToken)"
                ])
                .uploadProgress { progress in
                    print("Upload Progress: \(progress.fractionCompleted * 100)%")
                }
                .responseData { response in
                    switch response.result {
                    case .success(let data):
                        do {
                            let response = try JSONSerialization.jsonObject(with: data)
                            if let dict = response as? NSDictionary{
                                //Check condition for response success or not and notificatino show with coming alert in service response
                                if self.validationForServiceResponse(dict){
                                    webservice_Nool_Load = false

                                    self.delegateWeb?.appDataDidSuccess(dict, request: self.strMethodName, index: self.selectIndex, orderid: self.strOrderID)
                                }else{
                                    webservice_Nool_Load = false
                                    let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                    self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
                                }
                            }
                        }
                        catch {
                            webservice_Nool_Load = false
                            let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                            self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)

                            
                        }
                        
                    case .failure(_):
                        webservice_Nool_Load = false
                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                        self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
                    }
                }
            }
            catch {
                //Alert show for Header
                webservice_Nool_Load = false
                showAlertMessage(strMessage: "\(self.strMethodName) \(str.somethingWentWrong)")

            }
        }
    }
//    func callCheckListAPI(){
//        
//        if NetworkReachabilityManager()!.isReachable {
//            
//            do {
//                
//                webservice_Nool_Load = true
//                DispatchQueue.main.async {
//                    if self.indicatorShowOrHide == true{
//                        indicatorShow()
//                    }
//                }
//
//                //CONVERT DIC TO DATA
//                var jsonData = try JSONSerialization.data(withJSONObject: self.dictType, options: .prettyPrinted)
//                if jsonString != ""{
//                    jsonData = jsonString.data(using: String.Encoding(rawValue: String.Encoding.utf8.rawValue))!
//                }
//                
//                //SET REWUEST
//                let strUrl = URL(string: "\(self.strURL)")!
//                var request = URLRequest(url: strUrl)
//
//                //Declaration for service for get,post or other..
//                if methodType == "post"{
//                    request.httpMethod = HTTPMethod.post.rawValue
//                }
//                else  if methodType == "delete"{
//                    request.httpMethod = HTTPMethod.delete.rawValue
//                }
//                else if methodType == "put"{
//                    request.httpMethod = HTTPMethod.put.rawValue
//                }
//                else if methodType == "patch"{
//                    request.httpMethod = HTTPMethod.patch.rawValue
//                }
//                else if methodType == "delete"{
//                    request.httpMethod = HTTPMethod.delete.rawValue
//                }
//                else{
//                    request.httpMethod = HTTPMethod.get.rawValue
//                }
//
//                
//                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//                if let accessToken = UserDefaults.standard.accessToken{
//                    request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
//                }
//                request.addValue(UserDefaults.standard.language, forHTTPHeaderField: "lang")
//
//                //Pass paramater with value data
//                //if methodType == "post" || methodType == "put"{
//                    if dictType.count != 0{
//                        request.httpBody = jsonData
//                    }
//                //}
//                
//             
//                
//                //Calling service
//                let manager = AF
//                manager.sessionConfiguration.timeoutIntervalForRequest = 30
//                manager.upload(multipartFormData: { (multipartFormData) in
//                    
//                    for obj in self.arr_Mutlipleimages {
//
//                        let imgData : Data = ((obj["img"] as? UIImage)?.jpegData(compressionQuality: 0.25)) ?? Data()
//                        let imgName : String = obj["name"] as? String ?? ""
//                        let imgUploadKey : String = obj["key"] as? String ?? ""
//
//                        multipartFormData.append(imgData, withName: imgUploadKey,fileName: imgName, mimeType: "image/jpeg")
//
//                    }
//
//
//                }, to: strUrl, method:.post).responseData { (response) in
//
//                    
//                    switch response.result {
//                    case .success(let data):
//                        do {
//                            let asJSON = try JSONSerialization.jsonObject(with: data)
//                            // Handle as previously success
//                            
//                            if let dict = asJSON as? NSDictionary{
//                                
//                                //Check condition for response success or not and notificatino show with coming alert in service response
//                                if self.validationForServiceResponse(dict){
//                                    webservice_Nool_Load = false
//                                    self.delegateWeb?.appDataDidSuccess(dict, request: self.strMethodName, index: self.selectIndex)
//                                    
//                                }else{
//                                    webservice_Nool_Load = false
//                                    let err = NSError(domain: "data not found", code: 401, userInfo: nil)
//                                    self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
//                                }
//                            }
//                            else{
//                                webservice_Nool_Load = false
//                                let err = NSError(domain: "data not found", code: 401, userInfo: nil)
//                                self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
//                            }
//                            
//                        } catch {
//                            webservice_Nool_Load = false
//                            let err = NSError(domain: "data not found", code: 401, userInfo: nil)
//                            self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
//                        }
//                        
//                    case .failure(_):
//                        webservice_Nool_Load = false
//                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
//                        self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
//                    }
//                }
//            } catch {
//                
//                //Alert show for Header
//                webservice_Nool_Load = false
//                showAlertMessage(strMessage: "\(self.strMethodName) \(str.somethingWentWrong)")
//            }
//        }
//        else{
//            webservice_Nool_Load = false
//
//            var NoInternetNaNavigation: UINavigationController!
//            if let topVC = UIApplication.getTopViewController() {
//                if !(topVC is NoInternetViewController) {
//                    let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TABBAR, bundle: nil)
//                    if let newViewController = storyBoard.instantiateViewController(withIdentifier: "NoInternetViewController") as? NoInternetViewController{
//                        newViewController.delegate = self
//                        NoInternetNaNavigation = UINavigationController(rootViewController: newViewController)
//                        NoInternetNaNavigation.modalPresentationStyle = .fullScreen
//                        topVC.present(NoInternetNaNavigation, animated: true, completion: nil)
//                    }
//                }
//            }
//        }
//    }
    
    // MARK: - Other Method -
    func validationForServiceResponse(_ response: NSDictionary) -> Bool{

        DispatchQueue.main.async {
            //Indication show hide with varible when user calling service
            if self.indicatorShowOrHide == true && self.isFavouretScreen == true{
                indicatorHide()
            }
        }

        if response["code"] != nil{
            let responseKey = Int(response.getStringForID(key: "code")) ?? 0
            
            //101 invalide user or already registartion with current credincial
            switch responseKey {
            case 100,101,102:
                if self.serviceWithAlert || self.serviceWithAlertErrorMessage {
                    indicatorHide()

                    //Alert show for Header
                    showAlertMessage(strMessage: "\(response["msg"] ?? "")")
                }

                return false
            case 401:
                indicatorHide()

                //USER LOG OUT
                LogOutUser()
                
                //Alert show for Header
                showAlertMessage(strMessage: "\(response["msg"] ?? "")")
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
                    indicatorHide()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                        let alert = UIAlertController(title: Application.appName, message: response["msg"]! as? String, preferredStyle: UIAlertController.Style.alert)
                        alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
                        GlobalMainConstants.appDelegate?.window?.rootViewController?.present(alert, animated: true, completion: nil)
                    })
                }
                break
            }
        }
        return true
    }
    
    
    //MARK: - UPLOAD MULTIPLE IMAGES
    func callUploadingMultipleImages() {
        if NetworkReachabilityManager()!.isReachable {
            
            webservice_Nool_Load = true
            DispatchQueue.main.async {
                if self.indicatorShowOrHide == true {
                    indicatorShow()
                }
            }
            
            // Prepare URL
            let strUrl = URL(string: self.strURL)!
            
            // Headers
            var headers: HTTPHeaders = [
                "Accept": "application/json",
                "Content-Type": "multipart/form-data",
                "lang": UserDefaults.standard.language
            ]
            
            if let accessToken = UserDefaults.standard.accessToken {
                headers["Authorization"] = "Bearer \(accessToken)"
            }
            
            AF.upload(multipartFormData: { multipartFormData in

                for (key, value) in self.dictType {
                    if let strVal = value as? String {
                        multipartFormData.append(strVal.data(using: .utf8)!, withName: key)
                    }
                }
                
                // Add multiple images
                for obj in self.arr_Mutlipleimages {
                    let imgData: Data = ((obj["img"] as? UIImage)?.jpegData(compressionQuality: 0.25)) ?? Data()
                    let imgName: String = obj["name"] as? String ?? "\(Date().timeIntervalSince1970).jpeg"
                    let imgKey: String = obj["key"] as? String ?? "media[]"
                    
                    multipartFormData.append(imgData,
                                             withName: imgKey,
                                             fileName: imgName,
                                             mimeType: "image/jpeg")
                }
                
            }, to: strUrl, method: .post, headers: headers)
            .responseData { response in
                webservice_Nool_Load = false
                switch response.result {
                case .success(let data):
                    do {
                        let asJSON = try JSONSerialization.jsonObject(with: data, options: [])
                        if let dict = asJSON as? NSDictionary {
                            if self.validationForServiceResponse(dict) {
                                self.delegateWeb?.appDataDidSuccess(dict,
                                                                    request: self.strMethodName,
                                                                    index: self.selectIndex,
                                                                    orderid: self.strOrderID)
                            } else {
                                let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                self.delegateWeb?.appDataDidFail(err,
                                                                 request: self.strMethodName,
                                                                 strUrl: self.strURL)
                            }
                        }
                    } catch {
                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                        self.delegateWeb?.appDataDidFail(err,
                                                         request: self.strMethodName,
                                                         strUrl: self.strURL)
                    }
                case .failure(_):
                    let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                    self.delegateWeb?.appDataDidFail(err,
                                                     request: self.strMethodName,
                                                     strUrl: self.strURL)
                }
            }
            
        } else {
            webservice_Nool_Load = false
            // Handle No Internet just like your other methods
        }
    }

}


func LogOutUser(){
    
    
}





class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private let reachabilityManager = NetworkReachabilityManager()
    
    /// Called when network becomes reachable again
    var onNetworkRestored: (() -> Void)?
    
    private var wasReachable = true
    
    private init() {
        startListening()
    }
    
    func startListening() {
        reachabilityManager?.startListening(onUpdatePerforming: { [weak self] status in
            guard let self = self else { return }
            
            switch status {
            case .reachable(_):
                print("✅ Internet is reachable")
                
                // Detect transition from offline → online
                if !self.wasReachable {
                    print("🌐 Internet restored!")
                    self.onNetworkRestored?()
                }
                self.wasReachable = true
                
            case .notReachable:
                print("❌ Internet lost")
                self.wasReachable = false
                
            case .unknown:
                print("⚠️ Unknown network state")
            }
        })
    }
    
    func isReachable() -> Bool {
        return reachabilityManager?.isReachable ?? false
    }
}
