//
//  Metadata.swift
//  Kabba
//
//  Created by Jigar Khatri on 07/10/23.
//

import Foundation

enum Application {
    //Base URL
    
    static var BaseURL: String {
        if let defaultsToExtension = UserDefaults(suiteName: "group.com.RentnKingNew.shared"), let baseURL = defaultsToExtension.string(forKey: "api_url"){
            return baseURL
        }
        return ""
    }
    
//    static let BaseURL = "https://api.rentnking.com/api/admin/v1/"

    static let phoneFormate = "(XXX) XXX-XXXX"
    
    //LOGIN TOKEN
//    static let token = "5|rKRPxe0Bq3zxJGgmi4wtjfyoS1w2KzYHmTJ9uHS7229379e6"

}
