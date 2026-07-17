//
//  UILabel+Extension.swift
//  BAYNOUNAH
//
//  Created by Jigar Khatri on 22/06/22.
//

import UIKit

extension UILabel {
    var requiredWidth: CGFloat {
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: frame.height))
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.font = font
        label.text = text
        label.attributedText = attributedText
        label.sizeToFit()
        return label.frame.width
    }

    var requiredHeight: CGFloat {
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: frame.width, height: CGFloat.greatestFiniteMagnitude))
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.font = font
        label.text = text
        label.attributedText = attributedText
        label.sizeToFit()
        return label.frame.height
    }
    
    func configureLable(textColor:UIColor?, fontName:String, fontSize : Double, text:String) {
        self.textAlignment = .left
        self.textColor = textColor
        self.font = SetTheFont(fontName: fontName, size: fontSize)
        self.text = text
        self.numberOfLines = 0
    }
    
    func configureHTMLLable(textColor:UIColor?, fontName:String, fontSize : Double) {
//        self.textColor = textColor
        self.font = SetTheFont(fontName: fontName, size: fontSize)
        self.textAlignment = .center
    }
    
    func addTextSpacing(spacing: CGFloat, color: UIColor) {
        guard let text = text else { return }

        let attributedString = NSMutableAttributedString(string: text)
        attributedString.addAttribute(NSAttributedString.Key.kern, value: spacing, range: NSRange(location: 0, length: text.count))
        attributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: color , range: NSRange(location: 0, length: text.count))

        attributedText = attributedString
    }
    
    func setAttributedHtmlText(_ html: String) {
//        #if targetEnvironment(simulator)
//        self.text = html
//        #else
//        if let attributedText = html.attributedHtmlString {
//            self.attributedText = attributedText
//        }
//        #endif
    }
    
    func lblAttributes(str : String ,location : Int, lenght : Int){

        let attributedString = NSMutableAttributedString(string: str, attributes: [
            .foregroundColor: UIColor.primary!,
            .font: SetTheFont(fontName: GlobalConstants.APP_FONT_Roboto_Regular, size: 23),
          .kern: 0.0
        ])
        attributedString.addAttribute(.foregroundColor, value: UIColor.primary!, range: NSRange(location: location, length: lenght))
        self.attributedText = attributedString
//        self.setAttributedTitle(attributedString, for: .normal)
    }
    
}


extension UIButton{
    func configureLable(bgColour : UIColor?, textColor:UIColor?, fontName:String, fontSize : Double, text:String) {
        self.backgroundColor = UIColor.clear
        self.backgroundColor = bgColour
        self.setTitleColor(textColor , for: .normal)
        self.titleLabel?.font = SetTheFont(fontName: fontName, size: fontSize)
        self.setTitle(text, for: .normal)
    }
    
    func btnCorneRadius(radius : CGFloat, isRound : Bool){
        self.layer.masksToBounds = true
        if isRound{
            self.layer.cornerRadius = self.frame.size.height / 2
        }
        else{
            self.layer.cornerRadius = radius
        }
    }
    
    
    func btnnBorder (bgColour : UIColor?){
        self.layer.borderWidth = 1
        self.layer.borderColor =  bgColour?.cgColor
    }

    
    func btnUnderLineAttributes(str : String){
        
        let yourAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.primary ?? UIColor.white,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        
        let attributeString = NSMutableAttributedString(
            string: str,
            attributes: yourAttributes
        )
        self.setAttributedTitle(attributeString, for: .normal)
    }
    
    
    func btnAttributes(str : String ,location : Int, lenght : Int){
//        let yourAttributes: [NSAttributedString.Key: Any] = [
//            .foregroundColor: UIColor.primary ?? UIColor.white,
//            .underlineStyle: NSUnderlineStyle.single.rawValue
//        ]


        let attributedString = NSMutableAttributedString(string: str, attributes: [
            .foregroundColor: UIColor.primary!,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
          .kern: 0.0
        ])
        attributedString.addAttribute(.foregroundColor, value: UIColor.secondary!, range: NSRange(location: location, length: lenght))
        self.setAttributedTitle(attributedString, for: .normal)
    }
    
    func dropButtonShadow(bgColour : UIColor?) {
        layer.masksToBounds = false
        layer.shadowColor = bgColour?.cgColor
        layer.shadowOffset = CGSize(width: 0.0, height: 0.0)
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 12
        layer.shadowPath = UIBezierPath(rect: self.bounds).cgPath
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
    }
}


extension UITextField{
    func configureText(bgColour : UIColor, textColor:UIColor?, fontName:String, fontSize : Double, text:String, placeholder : String) {
        self.backgroundColor = bgColour
        self.textAlignment = .left

        self.textColor = textColor
        self.font = SetTheFont(fontName: fontName, size: fontSize)
        self.text = text
        
        self.attributedPlaceholder = NSAttributedString(string: placeholder,
                                                        attributes: [NSAttributedString.Key.foregroundColor:  UIColor.primary?.withAlphaComponent(1.0) ?? UIColor.black ,NSAttributedString.Key.font:  SetTheFont(fontName: fontName, size: fontSize)])
    }
    
    func configureTextWhite(bgColour : UIColor, textColor:UIColor?, fontName:String, fontSize : Double, text:String, placeholder : String) {
        self.backgroundColor = bgColour
        self.textAlignment = .left

        self.textColor = UIColor.primary
        self.font = SetTheFont(fontName: fontName, size: fontSize)
        self.text = text
        
        self.attributedPlaceholder = NSAttributedString(string: placeholder,
                                                        attributes: [NSAttributedString.Key.foregroundColor:  UIColor.primary! ,NSAttributedString.Key.font:  SetTheFont(fontName: fontName, size: fontSize)])
    }
}


extension UITextView{
    func configureText(bgColour : UIColor, textColor:UIColor, fontName:String, fontSize : Double, text:String) {
        self.backgroundColor = UIColor.clear
        self.backgroundColor = bgColour
        self.textAlignment = .left

        self.textColor = textColor
        self.font = SetTheFont(fontName: fontName, size: fontSize)
        self.text = text
    }
    
    
    func setAttributedHtmlText(_ html: String) {
        #if targetEnvironment(simulator)
        self.text = html
        #else
//        if let attributedText = html.attributedHtmlString {
//            self.attributedText = attributedText
//        }
        #endif
    }
}




