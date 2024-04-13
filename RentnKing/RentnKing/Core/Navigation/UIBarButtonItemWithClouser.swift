//
//  UIBarButtonItemWithClouser.swift
//  BAYNOUNAH
//
//  Created by Jigar Khatri on 22/06/22.

import UIKit

class UIBarButtonItemWithClouser: UIBarButtonItem {

    private var actionHandler: (() -> Void)?
    private var actionHandler2: ((_ SelectTag : Int) -> Void)?
    private var actionHandler3: ((_ sender : UIBarButtonItem, _ SelectTag : Int) -> Void)?

    
    private let lblBadge = UILabel()
    public func setBadge(with value: Int) {
        self.badgeValue = value
    }
    
    public func setFilter(isFilter : Bool) {
        if isFilter {
            lblBadge.isHidden = false
            lblBadge.text = ""
        }
        else{
            lblBadge.isHidden = true
        }
    }

    private var badgeValue: Int? {
        didSet {
            if let value = badgeValue,
                value > 0 {
                lblBadge.isHidden = false
                lblBadge.text = "\(value)"
            } else {
                lblBadge.isHidden = true
            }
        }
    }


    
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
        
        self.lblBadge.frame = CGRect(x: 25, y: 0, width: 15, height: 15)
        self.lblBadge.backgroundColor = .red
        self.lblBadge.clipsToBounds = true
        self.lblBadge.layer.cornerRadius = 7
        self.lblBadge.textColor = UIColor.white
        self.lblBadge.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 10)
        self.lblBadge.textAlignment = .center
        self.lblBadge.isHidden = true
        self.lblBadge.minimumScaleFactor = 0.1
        self.lblBadge.adjustsFontSizeToFitWidth = true
        button.addSubview(lblBadge)
        
        self.actionHandler = actionHandler
    }
    
    convenience init(button: UIButton, actionHandler2: ((_ SelectTag : Int) -> Void)?) {
        self.init(customView: button)
        self.tag = button.tag
        
        self.lblBadge.frame = CGRect(x: 25, y: 0, width: 15, height: 15)
        self.lblBadge.backgroundColor = .red
        self.lblBadge.clipsToBounds = true
        self.lblBadge.layer.cornerRadius = 7
        self.lblBadge.textColor = UIColor.white
        self.lblBadge.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 10)
        self.lblBadge.textAlignment = .center
        self.lblBadge.isHidden = true
        self.lblBadge.minimumScaleFactor = 0.1
        self.lblBadge.adjustsFontSizeToFitWidth = true
        button.addSubview(lblBadge)
        
        
        button.addTarget(self, action: #selector(barButtonItemPressed(sender:)), for: .touchUpInside)
        self.actionHandler2 = actionHandler2
    }
    
    convenience init(button: UIButton, actionHandler3: ((_ sender : UIBarButtonItem, _ SelectTag : Int) -> Void)?) {
        self.init(customView: button)
        self.tag = button.tag
        
        self.lblBadge.frame = CGRect(x: 25, y: 0, width: 15, height: 15)
        self.lblBadge.backgroundColor = .red
        self.lblBadge.clipsToBounds = true
        self.lblBadge.layer.cornerRadius = 7
        self.lblBadge.textColor = UIColor.white
        self.lblBadge.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 10)
        self.lblBadge.textAlignment = .center
        self.lblBadge.isHidden = true
        self.lblBadge.minimumScaleFactor = 0.1
        self.lblBadge.adjustsFontSizeToFitWidth = true
        button.addSubview(lblBadge)
        
        
        button.addTarget(self, action: #selector(barButtonItemPressed(sender:)), for: .touchUpInside)
        self.actionHandler3 = actionHandler3
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
        else if let actionHandler = self.actionHandler3{
            actionHandler(sender, self.tag)
        }
    }
}




class BadgedButtonItem: UIBarButtonItem {

    public func setBadge(with value: Int) {
        self.badgeValue = value
    }

    private var badgeValue: Int? {
        didSet {
            if let value = badgeValue,
                value > 0 {
                lblBadge.isHidden = false
                lblBadge.text = "\(value)"
            } else {
                lblBadge.isHidden = true
            }
        }
    }

    var tapAction: (() -> Void)?

    private let filterBtn = UIButton()
    private let lblBadge = UILabel()

    override init() {
        super.init()
        setup()
    }

    init(with image: UIImage?) {
        super.init()
        setup(image: image)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    private func setup(image: UIImage? = nil) {

        self.filterBtn.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        self.filterBtn.adjustsImageWhenHighlighted = false
        self.filterBtn.setImage(image, for: .normal)
        self.filterBtn.addTarget(self, action: #selector(buttonPressed), for: .touchUpInside)

        self.lblBadge.frame = CGRect(x: 20, y: 0, width: 15, height: 15)
        self.lblBadge.backgroundColor = .red
        self.lblBadge.clipsToBounds = true
        self.lblBadge.layer.cornerRadius = 7
        self.lblBadge.textColor = UIColor.white
        self.lblBadge.font = UIFont.systemFont(ofSize: 10)
        self.lblBadge.textAlignment = .center
        self.lblBadge.isHidden = true
        self.lblBadge.minimumScaleFactor = 0.1
        self.lblBadge.adjustsFontSizeToFitWidth = true
        self.filterBtn.addSubview(lblBadge)
        self.customView = filterBtn
    }

    @objc func buttonPressed() {
        if let action = tapAction {
            action()
        }
    }

}

