//
//  Text.swift
//  BAYNOUNAH
//
//  Created by Jigar Khatri on 22/06/22.
//

import Foundation
import CoreGraphics

extension String {
        
    var boolValue: Bool {
        return NSString(string: self).boolValue
    }
    
    var floatValue: CGFloat {
        return CGFloat((self as NSString).doubleValue)
    }
    
    var priceFormat: String{
        if let doubleValue = Double(self) {
            var value = String(format: "%.2f",doubleValue)
            if UserDefaults.standard.language == "nb"{
                value = value.replacingOccurrences(of: ".", with: ",")
            }
            return value
        }
        else{
            return ""
        }
    }
    
    var utfData: Data {
        return Data(utf8)
    }
    
    var attributedHtmlString: NSAttributedString? {
        
        do {
            return try NSAttributedString(data: utfData, options: [
              .documentType: NSAttributedString.DocumentType.html,
              .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil)
        } catch {
            print("Error:", error)
            return nil
        }
    }

    
    var htmlDecoded: String {
        
        var str: String = ""
        do {
            if let data = self.data(using: .unicode) {
                str = try NSAttributedString(data: data, options: [
                    NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.html
                ], documentAttributes: nil).string
                return "\(str) "
            }
        } catch {
            return str
        }
        
        return str
        
//        let decoded = try? NSAttributedString(data: Data(utf8), options: [
//            .documentType: NSAttributedString.DocumentType.html,
//            .characterEncoding: String.Encoding.utf8.rawValue
//            ], documentAttributes: nil).string
//
//        return decoded ?? self
    }
    
    func toDate(withFormat format: String = "yyyy-MM-dd HH:mm:ss")-> Date?{
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        let date = dateFormatter.date(from: self)
        
        return date
        
    }
    
    func amPmTime(withFormat format: String = "HH:mm:ss")-> String{
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        if let date = dateFormatter.date(from: self){
            dateFormatter.dateFormat = "HH:mm"
            return dateFormatter.string(from: date)
        }
        else{
            return ""
        }
        
    }
    
    func toString(withFormat format: String = "yyyy-MM-dd HH:mm:ss")-> String?{
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        if let date = dateFormatter.date(from: self){
            dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
            let dateString = dateFormatter.string(from: date)
            return dateString
        }
        else{
            return nil
        }
    }
    
    
    func toDateString(withFormat format: String = "yyyy-MM-dd HH:mm:ss")-> String?{
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        if let date = dateFormatter.date(from: self){
            dateFormatter.dateFormat = "dd/MM/yyyy"
            let dateString = dateFormatter.string(from: date)
            return dateString
        }
        else{
            return nil
        }
    }
}

extension String{
    func index(from: Int) -> Index {
        return self.index(startIndex, offsetBy: from)
    }

    func substring(from: Int) -> String {
        let fromIndex = index(from: from)
        return String(self[fromIndex...])
    }

    func substring(to: Int) -> String {
        let toIndex = index(from: to)
        return String(self[..<toIndex])
    }

    func substring(with r: Range<Int>) -> String {
        let startIndex = index(from: r.lowerBound)
        let endIndex = index(from: r.upperBound)
        return String(self[startIndex..<endIndex])
    }
}

extension String{
    
    func localized() -> String {
        
        var output: String = self
        
        if let path = Bundle.main.path(forResource: UserDefaults.standard.language, ofType: "lproj") {
            if let bundle = Bundle(path: path){
                output = bundle.localizedString(forKey: self, value: "", table: nil)
            }
        }
        
        return output
    }
}


extension Encodable {
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            throw NSError()
        }
        return dictionary
    }
    
    var dictionary: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)).flatMap { $0 as? [String: Any] }
    }
}



