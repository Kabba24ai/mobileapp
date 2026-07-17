//
//  UIBarButtonItemWithClouser.swift
//  BAYNOUNAH
//
//  Created by Jigar Khatri on 22/06/22.

import UIKit

class UIBarButtonItemWithClouserExtension: UIBarButtonItem {

    private var actionHandler: (() -> Void)?
    private var actionHandler2: ((_ SelectTag : Int) -> Void)?

    convenience init(title: String?, style: UIBarButtonItem.Style, actionHandler: (() -> Void)?) {
        self.init(title: title, style: style, target: nil, action: nil)
        self.target = self
        self.action = #selector(barButtonItemPressed(sender:))
        self.actionHandler = actionHandler
    }
    
    convenience init(image: UIImage?, landscapeImagePhone: UIImage?, style: UIBarButtonItem.Style, actionHandler: (() -> Void)?) {
        
        self.init(image: image, landscapeImagePhone: landscapeImagePhone, style: style, target: nil, action: nil)
        self.target = self
        self.action = #selector(barButtonItemPressed(sender:))
        self.actionHandler = actionHandler
    }
    

    
    convenience init(button: UIButton, actionHandler: (() -> Void)?) {
        self.init(customView: button)
        button.addTarget(self, action: #selector(barButtonItemPressed(sender:)), for: .touchUpInside)
        self.actionHandler = actionHandler
    }
    
    convenience init(button: UIButton, actionHandler2: ((_ SelectTag : Int) -> Void)?) {
        self.init(customView: button)
        self.tag = button.tag
        button.addTarget(self, action: #selector(barButtonItemPressed(sender:)), for: .touchUpInside)
        self.actionHandler2 = actionHandler2
    }
    
    convenience init(view: UIView, actionHandler2: ((_ SelectTag : Int) -> Void)?) {

        self.init(customView: view)
        self.target = self
        self.tag = view.tag
        let gesture = UITapGestureRecognizer(target: self, action:  #selector (self.someAction (_:)))
        view.addGestureRecognizer(gesture)
        self.actionHandler2 = actionHandler2

    }
    convenience init(view: UIView, actionHandler: (() -> Void)?) {
        self.init(customView: view)
        self.target = self
        self.action = #selector(barButtonItemPressed(sender:))
        self.actionHandler = actionHandler
    }
    
    @objc func someAction(_ sender:UITapGestureRecognizer){
        // do other task
        print("fgdfdf")
        if let actionHandler = self.actionHandler2{
            actionHandler(self.tag)
        }
        
    }

    
    @objc private func barButtonItemPressed(sender: UIBarButtonItem) {
        if let actionHandler = self.actionHandler{
            actionHandler()
        }
        else if let actionHandler = self.actionHandler2{
            actionHandler(self.tag)
        }
    }
}


