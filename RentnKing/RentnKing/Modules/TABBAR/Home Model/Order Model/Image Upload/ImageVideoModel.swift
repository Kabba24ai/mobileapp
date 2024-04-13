//
//  ImageVideoModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 12/02/24.
//

import Foundation
import UIKit
import ObjectMapper

class ImageVideoModel: NSObject{
    var type: String
    var image : UIImage
    var strVideo : URL
    var strUrl : String
    var isUpload : Bool

    init(type: String, image: UIImage, strVideo: URL, strUrl: String, isUpload: Bool = false) {
        self.type = type
        self.image = image
        self.strVideo = strVideo
        self.strUrl = strUrl
        self.isUpload = isUpload
    }
}






extension ImageUploadViewController: WebServiceHelperDelegate {
    
    
    func getOrderDetails(OrdersDetailsParameater : OrdersDetailsParameater, isLoading : Bool){
        guard let parameater = try? OrdersDetailsParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.orderDetails.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "orderDetails"
        webHelper.methodType = "post"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = isLoading
        webHelper.callAPI()
    }
    
    
    struct ImageVideoUploadParameater: Codable {
        var order_id : String
    }

    func callImageVideoUploadAPI(ImageVideoUploadParameater : ImageVideoUploadParameater) {
        guard let parameater = try? ImageVideoUploadParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }
        
        //Declaration URL
        let strURL = "\(Url.uploadImageVideo.absoluteString!)"

        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        
      
        //SET IMAGE
        var arr_Mutlipleimages : [[String : Any]] = []
        for obj in self.arrImageVideoLisr{
            if obj.type == "img"{
                if obj.image != UIImage(){
                    let dicData = ["img": obj.image ,
                                   "name": "\(Date().timeIntervalSince1970).jpeg",
                                   "type": "img",
                                   "key": "file[]"] as [String : Any]
                    arr_Mutlipleimages.append(dicData)
                }
            }
            else{
                if obj.strVideo.absoluteString != ""{
                    let dicData = ["img": "" ,
                                   "videoUrl": obj.strVideo ,
                                   "name": "\(Date().timeIntervalSince1970).mp4",
                                   "type": "video",
                                   "key": "file[]"] as [String : Any]
                    arr_Mutlipleimages.append(dicData)
                }
            }
        }

        webHelper.arr_Mutlipleimages = arr_Mutlipleimages
        webHelper.strMethodName = "uploadImageVideo"
        webHelper.strURL = strURL
        webHelper.dictType = parameater
        webHelper.dictHeader = NSDictionary()
        webHelper.delegateWeb = self
        webHelper.showLogForCallingAPI = true
        webHelper.serviceWithAlert = true
        webHelper.indicatorShowOrHide = true
        webHelper.callUploadingMultipleImages()
    }
    
    
    struct ImageVideoRemoveParameater: Codable {
        var order_id : String
        var file_name : String
    }
    func removeImageVideo(ImageVideoRemoveParameater : ImageVideoRemoveParameater){
        guard let parameater = try? ImageVideoRemoveParameater.asDictionary() else {
            showAlertMessage(strMessage: str.invalidRequestParamater)
            return
        }

        //Declaration URL
        let strURL = "\(Url.removeImageVideo.absoluteString!)"
        
       
        //Create object for webservicehelper and start to call method
        let webHelper = WebServiceHelper()
        webHelper.strMethodName = "removeImageVideo"
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
        indicatorHide()

        if data.getStringForID(key: "success") == "1"{
            if strRequest == "orderDetails"{
                self.arrImageVideoLisr = []
                if let dicData = data["data"] as? NSDictionary{
                   
                    //SET DATA
                    let map = Map(mappingType: .fromJSON, JSON: dicData as! [String : Any])
                    self.objOrderData = OrdersModel(map: map)

                    for objImage in objOrderData.order_image_links{
                        let isImageType = objImage.isImageType()
                        let url: URL = URL(fileURLWithPath: "")
                        let objData = ImageVideoModel(type: isImageType ? "img" : "video", image: UIImage(), strVideo: url, strUrl: objImage, isUpload: true)
                        
                        self.arrImageVideoLisr.append(objData)
                    }
                    
                    //SET THE VIEW
                    self.setTheView()
                }
                else{
                    //SET THE VIEW
                    self.setTheView()
                }
            }
            else if strRequest == "uploadImageVideo"{
                
                if let dicData = data["data"] as? [String]{                    
                    showAlertMessage(strMessage: "Upload successfully")
                    self.delegate?.ImageVideoUploadSucess(selectIndex: self.selectIndex, arrImage: dicData)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                        self.navigationController?.popViewController(animated: true)
                    }
                }
            }
            else if strRequest == "removeImageVideo"{
                print(data)
                
                //RELOAD
                self.addDeleteButton()
                self.objCollectionView.reloadData()

//                self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID), isLoading: true)

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
        self.getOrderDetails(OrdersDetailsParameater: OrdersDetailsParameater(order_id: self.strOrderID, product_id: ""), isLoading: true)

        showAlertMessage(strMessage: "\(strRequest) \(str.somethingWentWrong)")
    }
}



extension String {
    public func isImageType() -> Bool {
        // image formats which you want to check
        let imageFormats = ["jpg", "jpeg", "png", "gif", "WebP", "SVG"]

        if URL(string: self) != nil  {

            let extensi = (self as NSString).pathExtension

            return imageFormats.contains(extensi)
        }
        return false
    }
}
