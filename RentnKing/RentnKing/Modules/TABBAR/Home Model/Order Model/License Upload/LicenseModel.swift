//
//  LicenseModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 03/02/24.
//

import Foundation
import UIKit



extension LicenseUploadViewController: WebServiceHelperDelegate {
    struct LicenseParameater: Codable {
        var order_id : String
    }

    func callLicenseUploadAPI(LicenseParameater : LicenseParameater) {
        guard let parameater = try? LicenseParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.uploadLicense.absoluteString!)"

        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        
      
        //SET IMAGE
        let dicImgFront = ["img": self.imgFront.image ?? UIImage(),
                           "name": "\(Date().timeIntervalSince1970).jpeg",
                           "key": "file[]",
                           "type": "img"] as [String : Any]
        
        let dicImgBack = ["img": self.imgBack.image ?? UIImage(),
                          "name": "\(Date().timeIntervalSince1970).jpeg",
                          "key": "file[]",
                          "type": "img"] as [String : Any]
        
        webHelper.arr_Mutlipleimages.append(dicImgFront)
        webHelper.arr_Mutlipleimages.append(dicImgBack)
        webHelper.strMethodName = "uploadLicense"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callUploadingMultipleImages()
    }
    
    func appDataDidSuccess(_ data: NSDictionary, request strRequest: String, index: Int) {
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            print(data)
            if strRequest == "uploadLicense"{
                
                if let dicData = data["data"] as? [String]{
                    showAlertMessage(strMessage: "Upload license update successfully")
                    self.delegate?.linceUploadSucess(selectIndex: self.selectIndex, arrImage: dicData)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                        self.navigationController?.popViewController(animated: true)
                    }
                }
               
            }
        }
        else{
            indicatorHide()
            //SET THE VIEW
            showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
        }
    }
    
    func appDataArraySuccess(_ arr: NSArray, request strRequest: String, index: Int) {
    }
    
    func appDataDidFail(_ error: Error, request strRequest: String, strUrl: String) {
        indicatorHide()
        self.setTheView()

        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}

