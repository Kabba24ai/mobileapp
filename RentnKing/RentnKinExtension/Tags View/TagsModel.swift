//
//  TagsModel.swift
//  RentnKinExtension
//
//  Created by Jigar Khatri on 19/10/23.
//

import Foundation
import ObjectMapper
import UIKit

var somethingWentWrong = "Something went wrong!"

//LOGIN SCREEN ..........................

extension TagsViewController :WebServiceHelperDelegate{
    
    struct contectParameater: Codable {
        var name: String
        var email: String
        var phone: String
        var phone_2: String
        var contactTag: String
        var note: String
    }
    
    
     func getTagsAPI(){
 
         //Declaration URL
         let strURL = "\(Url.contactTags.absoluteString!)"
 
 
         //Create object for webservicehelper and start to call method
         let webHelper = WebServiceHelper()
         webHelper.strMethodName = "contactTags"
         webHelper.methodType = "get"
         webHelper.strURL = strURL
         webHelper.dictType = [:]
         webHelper.dictHeader = NSDictionary()
         webHelper.delegateWeb = self
         webHelper.showLogForCallingAPI = true
         webHelper.serviceWithAlert = true
         webHelper.indicatorShowOrHide = true
         webHelper.callAPI()
     }
     
    
    struct createTagParameater: Codable {
        var name: String
    }
    
    func submitTagAPI(createTagParameater:createTagParameater){
        guard let parameater = try? createTagParameater.asDictionary() else {
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.createTags.absoluteString!)"
        
        
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "createTags"
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
        //SET INDICATOR
        self.viewTag.isHidden = true
        self.objTagIndicator.isHidden = true
        self.objTagIndicator.stopAnimating()
        
        if data.getStringForID(key: "success") == "1"{
            if strRequest == "contactTags"{
                
                if let arrData = data["data"] as? NSArray{
                    self.arrTags = []
                    self.arrTags = Mapper<TagListModel>().mapArray(JSONArray: arrData as! [[String : Any]])
                    if self.arrTags.count != 0{
                        self.arrTags = self.arrTags.sorted(by: {$0.name?.lowercased() ?? "" < $1.name?.lowercased() ?? ""})
                    }
                }
         
            

                //RELAOD
                self.tblView.reloadData()
            }
            else if strRequest == "createTags"{
                self.showAlertMessage(strMessage: data.getStringForID(key: "message"))
                
                DispatchQueue.main.async {
                    self.getTagsAPI()
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
        self.viewTagSubmit.isHidden = false
        self.objTagIndicator.isHidden = true
        self.objTagIndicator.stopAnimating()

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
