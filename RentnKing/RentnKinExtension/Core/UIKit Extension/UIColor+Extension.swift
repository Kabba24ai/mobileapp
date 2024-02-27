//
//  UIColor+Extension.swift
//  BAYNOUNAH
//
//  Created by Jigar Khatri on 22/06/22.
//

import UIKit


//Never user Color enum directly, use UIColor's Extenion's property only
enum Color {
    static let background = UIColor(named: "backgroundEX")
    static let primary = UIColor(named: "primaryEX")
    static let secondary = UIColor(named: "secondaryEX")

}

extension UIColor{
    static let background = Color.background
    static let primary = Color.primary
    static let secondary = Color.secondary
}


extension UIColor {

    // Check if the color is light or dark, as defined by the injected lightness threshold.
    // Some people report that 0.7 is best. I suggest to find out for yourself.
    // A nil value is returned if the lightness couldn't be determined.
    func isLight(threshold: Float = 0.5) -> Bool? {
        let originalCGColor = self.cgColor

        // Now we need to convert it to the RGB colorspace. UIColor.white / UIColor.black are greyscale and not RGB.
        // If you don't do this then you will crash when accessing components index 2 below when evaluating greyscale colors.
        let RGBCGColor = originalCGColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)
        guard let components = RGBCGColor?.components else {
            return nil
        }
        guard components.count >= 3 else {
            return nil
        }

        let brightness = Float(((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000)
        return (brightness > threshold)
    }
}
