//
//  CoreaDataModel.swift
//  SAMUH
//
//  Created by Jigar Khatri on 15/07/21.
//

import Foundation


struct DownloadVideoParameater: Codable {
    var download_percentage : String
    var isDownload : String
    var profile_id : String
    var show_id : String
    var video_id : String
    var video_name : String
    var video_url : String
    var download_URL : String
    var isPush : String
    var episode_id : String
    var episode_name : String
    var video_img: String
    var userID: String
    var subTitleUrl: String
    var expiry_date: String
    var download_ID: String
}



struct SaveDownloadParameater: Codable {
    var profile_id : String
    var profile_name : String
    var profile_image : String
    var show_id : String
    var show_name : String
    var show_image : String
    var video_id : String
    var video_name : String
    var video_url : String
    var download_URL : String
    var isShow : String
    var episode_id : String
    var episode_name : String
    var video_img: String
    var userID: String
    var subTitleUrl: String
    var expiry_date: String
    var download_ID: String
}


struct SaveSubTitleParameater: Codable {
    var defaultType : String
    var lung : String
    var subTitleUrl : String
    var video_id : String
}
