//
//  ActionModel.swift
//  Kabba
//
//  Created by Jigar Khatri on 21/09/23.
//

import Foundation
import ObjectMapper
import UIKit

struct TagListModel: Mappable{
    internal var id: Int?
    internal var unique_id: String?
    internal var name: String?
    
    init?(map:Map) {
        mapping(map: map)
    }

    mutating func mapping(map:Map){
        id <- map["id"]
        unique_id <- map["unique_id"]
        name <- map["name"]
    }
}

//LOGIN SCREEN ..........................

extension ActionViewController :WebServiceHelperDelegate{
    
    struct contectParameater: Codable {
//        var name: String
        var first_name: String
        var last_name: String
        var email: String
        var phone: String
        var company: String
        var tags: String
        var note: String
    }
    
    
     func getTagsAPI(){
         //SET INDICATOR
         self.objTagIndicator.isHidden = false
         self.btnAdd.isHidden = true
         self.objTagIndicator.startAnimating()
         
         //Declaration URL
         let strURL = "\(Url.contactTags.absoluteString!)"
 
 
         //Create object for webservicehelper and start to call method
         let webHelper = WebServiceHelper()
         webHelper.strMethodName = "contactTags"
         webHelper.methodType = "post"
         webHelper.strURL = strURL
         webHelper.dictType = [:]
         webHelper.dictHeader = NSDictionary()
         webHelper.delegateWeb = self
         webHelper.showLogForCallingAPI = true
         webHelper.serviceWithAlert = true
         webHelper.indicatorShowOrHide = true
         webHelper.callAPI()
     }
     
    
    func submitContectsAPI(contectParameater:contectParameater){
        guard let parameater = try? contectParameater.asDictionary() else {
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.createContact.absoluteString!)"
        
        
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "createContact"
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
    
   
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
       
        //set
        self.ViewSave.isHidden = false
        self.objIndicator.isHidden = true
        self.objIndicator.stopAnimating()
        
        if data.getStringForID(key: "success") == "1"{
            if strRequest == "contactTags"{
                //SET INDICATOR
                self.objTagIndicator.isHidden = true
                self.btnAdd.isHidden = false
                self.objTagIndicator.stopAnimating()
                
                if let arrData = data["customer_tags"] as? NSArray{
                    self.arrTags = []
                    self.arrTags = Mapper<TagListModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                }
            }
            else if strRequest == "createContact"{
                let alert = UIAlertController(title: "", message: data.getStringForID(key: "message"), preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { _ in
                    self.extensionContext!.completeRequest(returningItems: nil, completionHandler: nil)
                }))
                self.present(alert, animated: true, completion: nil)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.extensionContext!.completeRequest(returningItems: nil, completionHandler: nil)
                    alert.dismiss(animated: true, completion: nil)
                }
            }
        }
        else{
            self.showAlertMessage(strMessage: data.getStringForID(key: "message"))
        }

    }

    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int){
        if strRequest == "contactTags"{
            print(arr)
            
        }
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String) {
        self.ViewSave.isHidden = false
        self.objIndicator.isHidden = true
        self.objIndicator.stopAnimating()
  
        //SET INDICATOR
        self.objTagIndicator.isHidden = true
        self.btnAdd.isHidden = false

        

        DispatchQueue.main.asyncAfter(deadline: .now()){
            self.showAlertMessage(strMessage: "\(strRequest)-\(somethingWentWrong)")
        }
    }
    
    //............................... ALERT MESSAGE ...............................................//
    func showAlertMessage(strMessage: String) {
        let alert = UIAlertController(title: "", message: strMessage, preferredStyle: UIAlertController.Style.alert)

        alert.addAction(UIAlertAction(title: "Ok", style: UIAlertAction.Style.default, handler: nil))
        self.present(alert, animated: true, completion: nil)
       
    }
}



