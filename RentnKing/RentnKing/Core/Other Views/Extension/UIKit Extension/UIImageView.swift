//
//  UIImageView.swift
//  Now TV!
//
//  Created by Jigar Khatri on 10/03/23.
//

import Foundation
import UIKit
import Nuke
import NukeExtensions

extension UIImageView{
    
    func makeRequest(with url: URL) -> ImageRequest {
        ImageRequest(url: url)
    }

    func makeImageLoadingOptions() -> ImageLoadingOptions {
        ImageLoadingOptions(placeholder: UIImage(named: "icon_PlaceHoder"), transition: .fadeIn(duration: 0.25))
    }
    
    func setImage(strImg : String){
        let imgURL =  ("\(Application.imgURL)\(strImg)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)) ?? ""
        if let url = URL(string: imgURL.replacingOccurrences(of: " ", with: "%20")){
            NukeExtensions.loadImage(with: makeRequest(with: url), options: makeImageLoadingOptions(), into: self)
        }
    }
    
    func setImageURL(strImg : String){
        let imgURL =  ("\(strImg)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)) ?? ""
        if let url = URL(string: imgURL.replacingOccurrences(of: " ", with: "%20")){
            NukeExtensions.loadImage(with: makeRequest(with: url), options: makeImageLoadingOptions(), into: self)
        }
    }
    
//    
//    func setImageWithoutPlacehoder(strImg : String, faillImg : UIImageView){
//        let imgURL =  ("\(Application.imgURL)\(strImg)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)) ?? ""
//        if let url = URL(string: imgURL.replacingOccurrences(of: " ", with: "%20")){
//            Nuke.loadImage(with: url, options: ImageLoadingOptions(transition: .fadeIn(duration: 0.33), failureImage: faillImg.image), into: self)
//        }
//    }
//    
//    func setImageWithoutURL(strImg : String){
//        let imgURL =  ("\(strImg)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)) ?? ""
//        if let url = URL(string: imgURL.replacingOccurrences(of: " ", with: "%20")){
//            Nuke.loadImage(with: url, options: ImageLoadingOptions(placeholder: UIImage(named: "icon_PlaceHoder"), transition: .fadeIn(duration: 0.33)), into: self)
//        }
//    }
//    
//    func setPlaceHoderImage(){
//        let imgURL =  ("\(Application.imgURL)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)) ?? ""
//        if let url = URL(string: imgURL.replacingOccurrences(of: " ", with: "%20")){
//            Nuke.loadImage(with: url, options: ImageLoadingOptions(placeholder: UIImage(named: "icon_PlaceHoder"), transition: .fadeIn(duration: 0.33)), into: self)
//        }
//    }
}
