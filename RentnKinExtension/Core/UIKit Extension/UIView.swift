//
//  UIView.swift
//  Belboy
//
//  Created by Jigar Khatri on 30/04/21.
//

import UIKit

public enum UIViewBorderSide {
    case Top, Bottom, Left, Right
}

extension UIView {
    func roundCorners(corners: UIRectCorner, radius: CGFloat) {
        let path = UIBezierPath(roundedRect: bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        layer.mask = mask
    }
    
    //For layout change animation
    func animateConstraintWithDuration(duration: TimeInterval = 0.5) {
        UIView.animate(withDuration: duration, animations: { [weak self] in
            self?.layoutIfNeeded() ?? ()
        })
    }
    
    func zoomIn(duration: TimeInterval = 0.2) {
        self.transform = CGAffineTransform(scaleX: 0.0, y: 0.0)
        UIView.animate(withDuration: duration, delay: 0.0, options: [.curveLinear], animations: { () -> Void in
            self.transform = CGAffineTransform.identity
        }) { (animationCompleted: Bool) -> Void in
        }
    }
    
    /**
     Simply zooming out of a view: set view scale to Identity and zoom out to 0 on 'duration' time interval.
     
     - parameter duration: animation duration
     */
    func zoomOut(duration: TimeInterval = 0.2) {
        self.transform = CGAffineTransform.identity
        UIView.animate(withDuration: duration, delay: 0.0, options: [.curveLinear], animations: { () -> Void in
            self.transform = CGAffineTransform(scaleX: 0.0, y: 0.0)
        }) { (animationCompleted: Bool) -> Void in
        }
    }
    
    public func addBorder(side: UIViewBorderSide, color: UIColor, width: CGFloat) {
        let border = CALayer()
        border.backgroundColor = color.cgColor
        switch side {
        case .Top:
            border.frame = CGRect(x: 0, y: 0, width: frame.size.width, height: width)
        case .Bottom:
            border.frame = CGRect(x: 0, y: self.frame.size.height - width, width: self.frame.size.width, height: width)
        case .Left:
            border.frame = CGRect(x: 0, y: 0, width: width, height: self.frame.size.height)
        case .Right:
            border.frame = CGRect(x: self.frame.size.width - width, y: 0, width: width, height: self.frame.size.height)
        }
        self.layer.addSublayer(border)
    }
}


//GRADIENT
class ActualGradientButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    private lazy var gradientLayer: CAGradientLayer = {
        let l = CAGradientLayer()
        l.frame = self.bounds
        l.colors = [UIColor.clear.cgColor, UIColor.primary?.cgColor ?? UIColor.clear.cgColor]
        l.startPoint = CGPoint(x: 0.0, y: 0.0)
        l.endPoint = CGPoint(x: 0, y: 0.5)
//        l.cornerRadius = self.layer.frame.size.height / 2
        layer.insertSublayer(l, at: 0)
        return l
    }()
}


extension UIView {
    func fadeIn(_ duration: TimeInterval = 0.8, delay: TimeInterval = 0.0, completion: @escaping ((Bool) -> Void) = {(finished: Bool) -> Void in}) {

        UIView.animate(withDuration: duration, delay: delay, options: UIView.AnimationOptions.curveEaseIn, animations: {
            self.alpha = 1.0
    }, completion: completion)  }

    func fadeOut(_ duration: TimeInterval = 0.8, delay: TimeInterval = 1.0, completion: @escaping (Bool) -> Void = {(finished: Bool) -> Void in}) {
        UIView.animate(withDuration: duration, delay: delay, options: UIView.AnimationOptions.curveEaseIn, animations: {
            self.alpha = 0.3
    }, completion: completion)
   }
    
    
    func fadeOut2(_ duration: TimeInterval = 0.8, delay: TimeInterval = 0.0, completion: @escaping (Bool) -> Void = {(finished: Bool) -> Void in}) {
        UIView.animate(withDuration: duration, delay: delay, options: UIView.AnimationOptions.curveEaseIn, animations: {
            self.alpha = 0.3
        }, completion: completion)
    }
}

extension UIView{
    func setTheTextView(bgColor : UIColor = .clear, size : CGFloat = 2){
        self.backgroundColor = .clear
        self.viewCorneRadius(radius: 10, isRound: false)
        self.viewBorderCorneRadius(borderColour: bgColor, size : size)
    }
    
    func viewCorneRadius(radius : CGFloat, isRound : Bool){
        self.layer.masksToBounds = true
        if isRound{
            self.layer.cornerRadius = self.frame.size.height / 2
        }
        else{
            self.layer.cornerRadius = radius
        }
        self.layer.layoutIfNeeded()
    }
    
    func viewBorderCorneRadius(borderColour : UIColor?, size : CGFloat = 2){
        self.layer.borderWidth = size
        self.layer.borderColor =  borderColour?.cgColor
    }

    func viewBorderCorneRadius2(borderSize : CGFloat, borderColour : UIColor?){
        self.layer.borderWidth = borderSize
        self.layer.borderColor =  borderColour?.cgColor
    }

   
    
    func viewShadow(bgColour : UIColor?) {
        layer.masksToBounds = false
        layer.shadowColor = bgColour?.cgColor
        layer.shadowOffset = CGSize(width: 0.0, height: 0.0)
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 10
        layer.shadowPath = UIBezierPath(rect: self.bounds).cgPath
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
    }

    func dropShadow(bgColour : UIColor?, radius : CGFloat) {
        layer.applySketchShadow(color: .black, alpha: 0.25, x: 0, y: 2, blur: 4, spread: 0)
        
//        layer.masksToBounds = false
//        layer.shadowColor = UIColor.black.cgColor
//        layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
//        layer.shadowOpacity = 0.25
//        layer.shadowRadius = radius
//        layer.shadowPath = UIBezierPath(rect: self.bounds).cgPath
//        layer.shouldRasterize = true
//        layer.rasterizationScale = UIScreen.main.scale
        layer.cornerRadius = radius
    }
    
    func dropShadow2(bgColour : UIColor?, radius : CGFloat) {
        layer.applySketchShadow(color: .black, alpha: 0.25, x: 0, y: 2, blur: 4, spread: 0)
        layer.borderWidth = 1
        layer.borderColor =  bgColour?.cgColor
        layer.cornerRadius = radius
    }
    
    func bgColour(bgColour : UIColor?, alpha : CGFloat) {
        self.backgroundColor = bgColour
        self.alpha = alpha
        viewCorneRadius(radius: 0.0, isRound: true)
    }
}

class customSliderTrim: UISlider {
    override func draw(_ rect: CGRect) {
        self.setMinimumTrackImage(UIImage.fromColor(color: #colorLiteral(red: 115/255.0, green: 201/255.0, blue: 230/255.0, alpha: 1), in: 5), for: .normal)
        self.setMaximumTrackImage(UIImage.fromColor(color: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0.2984693878), in: 5), for: .normal)
        self.setThumbImage(#imageLiteral(resourceName: "icon_progress"), for: .normal)
    }
}

class customSliderProgress: UISlider {
    override func draw(_ rect: CGRect) {
        self.setMinimumTrackImage(UIImage.fromColor(color: #colorLiteral(red: 0.6588235294, green: 0.9960784314, blue: 0.1882352941, alpha: 1), in: 5), for: .normal)
        self.setMaximumTrackImage(UIImage.fromColor(color: #colorLiteral(red: 1, green: 1, blue: 1, alpha: 0.2984693878), in: 5), for: .normal)
        self.setThumbImage(#imageLiteral(resourceName: "icon_progress"), for: .normal)
    }
}


extension UIImage {
    static func fromColor(color: UIColor, in height: Int) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: 2, height: height)
        
        
        let layer:CALayer =  CALayer()
        layer.frame = rect
        layer.masksToBounds = true
        layer.cornerRadius = 2.5
        layer.backgroundColor = color.cgColor;
        
        
        UIGraphicsBeginImageContext(layer.frame.size)
        layer.render(in: UIGraphicsGetCurrentContext()!)
        let  image :UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return image;

        
        
//
//        UIGraphicsBeginImageContext(layer.frame.size)
//        let context = UIGraphicsGetCurrentContext()
//        context!.setFillColor(color.cgColor)
//        context!.fill(rect)
//        let img = UIGraphicsGetImageFromCurrentImageContext()
//        UIGraphicsEndImageContext()
//
//        return img!
    }
    
    func resizeImage(newSize: CGSize) -> UIImage? {
        let scale = newSize.width / self.size.width
        let newHeight = self.size.height * scale
        UIGraphicsBeginImageContext(CGSize(width: newSize.width , height: newHeight))
        self.draw(in: CGRect(x: 0, y: 0, width: newSize.width , height: newHeight))
        return self
    }
}



extension CALayer {
  func applySketchShadow(color: UIColor = .black, alpha: Float = 0.5, x: CGFloat = 0, y: CGFloat = 2,
 blur: CGFloat = 4, spread: CGFloat = 0)
  {
    masksToBounds = false
    shadowColor = color.cgColor
    shadowOpacity = alpha
    shadowOffset = CGSize(width: x, height: y)
    shadowRadius = blur / 2.0
    if spread == 0 {
      shadowPath = nil
    } else {
      let dx = -spread
      let rect = bounds.insetBy(dx: dx, dy: dx)
      shadowPath = UIBezierPath(rect: rect).cgPath
    }
  }
}
