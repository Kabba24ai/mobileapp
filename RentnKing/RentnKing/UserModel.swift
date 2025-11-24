//
//  UserModel.swift
//  RentnKing
//
//  Created by Jigar Khatri on 08/08/25.
//

import Foundation



class User : NSObject,NSCoding {
    var id: String?
    var email: String?
    var full_name: String?
    var token: String?
    
    override init() {
        super.init()
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(email, forKey: "email")
        coder.encode(token, forKey: "token")
        coder.encode(full_name, forKey: "full_name")

    }
    
    required init?(coder: NSCoder) {
        self.id = coder.decodeObject(forKey: "id") as? String
        self.full_name = coder.decodeObject(forKey: "full_name") as? String
        self.email = coder.decodeObject(forKey: "email") as? String
        self.token = coder.decodeObject(forKey: "token") as? String
    }
}
