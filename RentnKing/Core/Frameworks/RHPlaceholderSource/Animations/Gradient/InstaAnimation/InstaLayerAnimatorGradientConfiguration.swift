import UIKit
 // TODO [🌶]: duplication
public struct InstaLayerAnimatorGradientConfiguration: LayerAnimatorGradientConfigurable {
    
    //ADD CUSTOME COLOUR HERE
    public private(set) var animationDuration: CFTimeInterval = 2
    public private(set) var fromColor: CGColor = UIColor.backgroundDark.cgColor 
    public private(set) var toColor: CGColor = UIColor.primary.withAlphaComponent(0.5).cgColor 
    
//    public private(set) var toColor: CGColor = UIColor(red: 112, green: 112, blue: 112).cgColor

}


