//
//  Metadata.swift
//  BAYNOUNAH
//
//  Created by Jigar Khatri on 22/06/22.
//

import Foundation
import UIKit

func checkVersionIsLive() -> Bool{
    if Bundle.main.bundleIdentifier == Application.aapBundilID_Dev {
        return false
    }
    else if Bundle.main.bundleIdentifier == Application.aapBundilID_Live {
        return true
    }
    else{
        return true
    }
    
        
}
enum Application {
    
    static let appName: String = str.appName
    static let aapBundilID_Dev = ""
    static let aapBundilID_Live = ""

    static let PageLimit = 20
    static let PageOrderLimit = 10
    static let currency = "$"

    //freevison
//    static let key = "c0bec2a92d0f9869a3255b9c41a4d0c8"
//    static let userID = "188"

    //baynounah
//    static let key = "VBWyGJmApmCgFHV1U2LJ7cDMsrnWKhKZ"
//    static let userID = "186"
    
    
    static let key = "832f918504051a03051f6106f4a1927c"
    static let userID = "191"

    static let OS = "ios"
    static let DEVICE_TYPE = checkDeviceiPad() ? "tablet " : "mobile"

    
    static let channelID = "312"
    static let Series_genre_id = "319"
    static let Movies_genre_id = "320"


    //catchup
    static let categories = "categories"
    static let custom_carousel = "custom_carousel"
    static let custom_categories = "custom_categories"
    static let custom_seasons = "custom_seasons"
    static let custom_videos = "custom_videos"
    static let favorite_carousel = "favorite_carousel"

    //films
    static let latest_episode = "latest_episode"
    static let latest_videos_in_show = "latest_videos_in_show"
    static let most_favorite_shows = "most_favorite_shows"
    static let most_in_country = "most_in_country"
    static let most_searched = "most_searched"
    static let most_searched_in_country = "most_searched_in_country"
    static let most_viewed_in_country = "most_viewed_in_country"
    static let original_content = "original_content"

    //plays
    static let recommendation_module = "recommendation_module"
    static let resume_watching = "resume_watching"
    static let shows_by_cast = "shows_by_cast"
    static let Shows_by_category = "Shows_by_category"

    static let live_channels = "live_channels"
    static let most_watched = "most_watched"



    


    
    
    //TYPE
    static let TvOnAir = "tv_on_air"
    static let RadioOnAir = "radio_on_air"
    static let Catchup = "catchup"
    
    static let TvLive = "live_channels"
    static let RadioLive = "radio_channels"
    
    

    //APP STORE URL
    static let appURL = "itms-apps://itunes.apple.com/app/"
    static let appStoreId = ""

    //OTHER KEY
    static let googleApiKey = ""
    static let VERSION = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")"

    
    //Base URL
//    static let BaseURLDEV = "https://rentalapp.rentnking.com/api/"
    static let BaseURL = "https://archive.rentnking.com/api/v1/"

    //IMAGE / VIDEO URL
    static let imgURLDEV = "https://rentalapp.rentnking.com/storage/"
    static let imgURL = "https://rentnking.com/storage/"
    static let TermsURL = "https://rentnking.com/checkout/"


 
    //DATE FORMET
    static let strDateFormet = "MMM dd, yyyy"
    static let passServertDAte = "MM/dd/yyyy"
    static let pickerDateFormet = "yyyy-MM-dd"
    static let yearOf = 10
    static let HHMMSS = "HH:mm:ss"
    static let HHMM = "HH:mm"
    static let HMMA = "h:mm a"
    
    static let serverDateFormet = "yyyy-MM-dd'T'HH:mm:ss.ssssssZ"
    static let MMM_dd = "MMM dd"
    
    static let phoneFormate = "(XXX) XXX-XXXX"

 
    //GOOGLE KEY
    static let googleKey = "40382089760-cj1ne660eu2ebi0415utu7o3hlm6eh52.apps.googleusercontent.com"
    

}


enum API_ERROR {
    static let objError : [String : String] = ["USER_NOT_FOUND": "User not found",
                                               "AUTH_NOT_VALID" : "These credentials do not match our records.",
                                               "USER_EXISTS" : "User already exist"]
}



//IN-APP TYPE
enum RegisteredPurchase: String {
    case consumablePurchase
    case renewingPurchase
}




class NetworkActivityIndicatorManager: NSObject {

    private static var loadingCount = 0

    class func networkOperationStarted() {

        #if os(iOS)
        if loadingCount == 0 {
            UIApplication.shared.isNetworkActivityIndicatorVisible = true
        }
        loadingCount += 1
        #endif
    }

    class func networkOperationFinished() {
        #if os(iOS)
        if loadingCount > 0 {
            loadingCount -= 1
        }
        if loadingCount == 0 {
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
        }
        #endif
    }
}



struct AppUtility {

    static func PortraitMode(){
        //SET PORTRAIT MODE
        AppUtility.lockOrientation(.portrait)
        let value = UIInterfaceOrientation.portrait.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")

    }
    
    static func lockOrientation(_ orientation: UIInterfaceOrientationMask) {
    
        if let delegate = UIApplication.shared.delegate as? AppDelegate {
            delegate.orientationLock = orientation
        }
    }

    /// OPTIONAL Added method to adjust lock and rotate to the desired orientation
    static func lockOrientation(_ orientation: UIInterfaceOrientationMask, andRotateTo rotateOrientation:UIInterfaceOrientation) {
        self.lockOrientation(orientation)
            UIDevice.current.setValue(rotateOrientation.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()

    }
}
