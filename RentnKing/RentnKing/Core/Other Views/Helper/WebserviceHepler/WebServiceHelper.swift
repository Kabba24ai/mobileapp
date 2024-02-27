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
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index : Int)
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index : Int)
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl : String)
}

class WebServiceHelper: NSObject,InternetAccessDelegate {

    var strMethodName = ""
    var selectIndex : Int = 0
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

                //Base user for calling service
                var headers: HTTPHeaders = [:]               
                
                //Calling service
                let manager = AF
                
                manager.sessionConfiguration.timeoutIntervalForRequest = 10
                if let encoded = self.strURL.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),let url = URL(string: encoded)
                 {
                    manager.request(url, method: methodType == "post" ? .post : .get, parameters: self.dictType, encoding: URLEncoding.default, headers: headers).responseData { response in
                        
                        switch response.result {
                        case .success(let data):
                            do {
                                let response = try JSONSerialization.jsonObject(with: data)
                                if let dict = response as? NSDictionary{
                                    let error : String = dict.getStringForID(key: "error")
                                    if error == "INVALID_TOKEN"{
                                        indicatorHide()
                                        webservice_Nool_Load = false
                                        
                                        //USER LOG OUT
                                        LogOutUser()
                                    }
                                    else{
                                        //Check condition for response success or not and notificatino show with coming alert in service response
                                        if self.validationForServiceResponse(dict){
                                            webservice_Nool_Load = false
                                            self.delegateWeb?.appDataDidSuccess(dict, request: self.strMethodName, index: self.selectIndex)
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
            }
        }else{
            webservice_Nool_Load = false

            var NoInternetNaNavigation: UINavigationController!
            if let topVC = UIApplication.getTopViewController() {
                if !(topVC is NoInternetViewController) {
                    let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TABBAR, bundle: nil)
                    if let newViewController = storyBoard.instantiateViewController(withIdentifier: "NoInternetViewController") as? NoInternetViewController{
                        newViewController.delegate = self
                        NoInternetNaNavigation = UINavigationController(rootViewController: newViewController)
                        NoInternetNaNavigation.modalPresentationStyle = .fullScreen
                        topVC.present(NoInternetNaNavigation, animated: true, completion: nil)
                    }
                }
            }
        }
    }
    
    
    
    
    
    // MARK: - StartDowload Method -
    func callAPI2(){
        
        if NetworkReachabilityManager()!.isReachable {
            
            do {
                
                webservice_Nool_Load = true
                DispatchQueue.main.async {
                    if self.indicatorShowOrHide == true{
                        indicatorShow()
                    }
                }
                
                
//                var jsonData = try JSONSerialization.data(withJSONObject: self.dictType, options: .prettyPrinted)
//                if jsonString != ""{
//                    jsonData = jsonString.data(using: String.Encoding(rawValue: String.Encoding.utf8.rawValue))!
//                }
//                let decoded = try JSONSerialization.jsonObject(with: jsonData, options: [])
//                if decoded is [String:String] {
//                    //print(dictFromJSON)
//                }
                
                //Base user for calling service
                self.strURL = strURL.replacingOccurrences(of: " ", with: "%20")
                let urlInNSString  = self.strURL
                //                let StringConvertInUTFform = NSString(string: urlInNSString).removingPercentEncoding!
                let strUrl = URL(string: "\(urlInNSString)")!
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
                else{
                    request.httpMethod = HTTPMethod.get.rawValue
                }
                
                
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                //Pass paramater with value data
                if methodType == "post" || methodType == "put"{
                    if dictType.count != 0{
                        var jsonData = try JSONSerialization.data(withJSONObject: self.dictType, options: .prettyPrinted)
                        request.httpBody = jsonData
                    }
                    else if arryType.count != 0{
                        var jsonData = try JSONSerialization.data(withJSONObject: self.arryType, options: .prettyPrinted)
                        request.httpBody = jsonData
                    }                    
                }
                
                //Calling service
                let manager = AF
                manager.sessionConfiguration.timeoutIntervalForRequest = 30
                
                manager.request(request).responseData     {
                    (response) in
                    
                    
                    switch response.result {
                    case .success(let data):
                        do {
                            let asJSON = try JSONSerialization.jsonObject(with: data)
                            // Handle as previously success
                            
                            if let dict = asJSON as? NSDictionary{
                                
                                //Check condition for response success or not and notificatino show with coming alert in service response
                                if self.validationForServiceResponse(dict){
                                    webservice_Nool_Load = false
                                    self.delegateWeb?.appDataDidSuccess(dict, request: self.strMethodName, index: self.selectIndex)
                                    
                                }else{
                                    webservice_Nool_Load = false
                                    let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                    self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
                                }
                            }
                            else{
                                webservice_Nool_Load = false
                                let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
                            }
                            
                        } catch {
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
            } catch {
                
                //Alert show for Header
                webservice_Nool_Load = false
                showAlertMessage(strMessage: "\(self.strMethodName) \(str.somethingWentWrong)")
            }
        }
        else{
            webservice_Nool_Load = false

            var NoInternetNaNavigation: UINavigationController!
            if let topVC = UIApplication.getTopViewController() {
                if !(topVC is NoInternetViewController) {
                    let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TABBAR, bundle: nil)
                    if let newViewController = storyBoard.instantiateViewController(withIdentifier: "NoInternetViewController") as? NoInternetViewController{
                        newViewController.delegate = self
                        NoInternetNaNavigation = UINavigationController(rootViewController: newViewController)
                        NoInternetNaNavigation.modalPresentationStyle = .fullScreen
                        topVC.present(NoInternetNaNavigation, animated: true, completion: nil)
                    }
                }
            }
        }
    }
    
    
    func callUploadingMultipleImages(){
        if NetworkReachabilityManager()!.isReachable {
            do {
                webservice_Nool_Load = true
                
                //Indication show hide with varible when user calling service
                (self.indicatorShowOrHide == true) ? (indicatorShow()) : (indicatorHide())
                
                print(self.arr_Mutlipleimages.count)
                let jsonData = try JSONSerialization.data(withJSONObject: self.dictType, options: .prettyPrinted)
                
                //Base user for calling service
                let urlInNSString  = self.strURL
                let StringConvertInUTFform = NSString(string: urlInNSString).removingPercentEncoding!
                let strUrl = URL(string: "\(StringConvertInUTFform)")!
                var request = URLRequest(url: strUrl)
                
                //Declaration for service for get,post or other..
                request.httpMethod = HTTPMethod.post.rawValue
                request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                
                
                
                //Pass paramater with value data
                request.httpBody = jsonData
                
                //Calling service
                let manager = AF
                manager.sessionConfiguration.timeoutIntervalForRequest = 30
                manager.upload(multipartFormData: { (multipartFormData) in
                    
                    for i in (0..<self.arr_Mutlipleimages.count) {
                        let obj = self.arr_Mutlipleimages[i]
                        
                        if obj["type"] as! String == "video"{
                            
                            
                            do {
                                let video = try Data(contentsOf: (obj["videoUrl"] as? URL)!)
                                print(video)
                                
                                let imgName : String = obj["name"] as? String ?? ""
                                let imgUploadKey : String = obj["key"] as? String ?? ""
                                
                                multipartFormData.append(video as Data, withName: "\(imgUploadKey)",fileName: imgName, mimeType: "image/jpeg")
                                
                            } catch {
                                print("Error")
                            }
                            
                        }
                        else{
                            let imgData : Data = ((obj["img"] as? UIImage)?.jpegData(compressionQuality: 0.25))!
                            let imgName : String = obj["name"] as? String ?? ""
                            let imgUploadKey : String = obj["key"] as? String ?? ""
                            
                            multipartFormData.append(imgData, withName: "\(imgUploadKey)",fileName: imgName, mimeType: "image/jpeg")
                        }
                        
                        
                    }
                    
                    
                    for (key, value) in self.dictType {
                        multipartFormData.append((value as AnyObject).data(using: String.Encoding.utf8.rawValue)!, withName: key)
                    }
                }, to: strUrl, method:.post).responseData { (response) in
                    switch response.result {
                    case .success(let data):
                        do {
                            let asJSON = try JSONSerialization.jsonObject(with: data)
                            // Handle as previously success
                            
                            if let dict = asJSON as? NSDictionary{
                                
                                //Check condition for response success or not and notificatino show with coming alert in service response
                                if self.validationForServiceResponse(dict){
                                    webservice_Nool_Load = false
                                    self.delegateWeb?.appDataDidSuccess(dict, request: self.strMethodName, index: self.selectIndex)
                                    
                                }else{
                                    webservice_Nool_Load = false
                                    let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                    self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
                                }
                            }
                            else{
                                webservice_Nool_Load = false
                                let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                                self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
                            }
                            
                        } catch {
                            webservice_Nool_Load = false
                            let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                            self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
                        }
                        
                    case .failure(_):
                        webservice_Nool_Load = false
                        let err = NSError(domain: "data not found", code: 401, userInfo: nil)
                        self.delegateWeb?.appDataDidFail(err, request: self.strMethodName, strUrl: self.strURL)
                    }
                }.uploadProgress { (progress) in
                    print("Progress: \(progress.fractionCompleted)")
                }
            }
            catch {
                //Alert show for Header
                webservice_Nool_Load = false
                showAlertMessage(strMessage: "\(strMethodName)- \(str.somethingWentWrong)")
            }
        }else{
            webservice_Nool_Load = false

            var NoInternetNaNavigation: UINavigationController!
            if let topVC = UIApplication.getTopViewController() {
                if !(topVC is NoInternetViewController) {
                    let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TABBAR, bundle: nil)
                    if let newViewController = storyBoard.instantiateViewController(withIdentifier: "NoInternetViewController") as? NoInternetViewController{
                        newViewController.delegate = self
                        NoInternetNaNavigation = UINavigationController(rootViewController: newViewController)
                        NoInternetNaNavigation.modalPresentationStyle = .fullScreen
                        topVC.present(NoInternetNaNavigation, animated: true, completion: nil)
                    }
                }
            }
        }
    }
    
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
}


func LogOutUser(){
    
    
}

