//
//  AddToCartButton.swift
//  Deonde
//
//  Created by Ankit Rupapara on 29/04/20.
//  Copyright © 2020 Ankit Rupapara. All rights reserved.
//

import UIKit

protocol AddToCartButtonDelegate {
    func itemAddedAtIndexPath(_ indexPath: IndexPath, count:Int)
    func itemRemovedAtIndexPath(_ indexPath: IndexPath, count:Int)
}

class AddToCartButton: UIView {

    var delegate: AddToCartButtonDelegate?
    var indexPath: IndexPath = IndexPath(row: 0, section: 0)
    
    var count: Int = 0 {
        didSet{
            configComponsnts()
            managebuttons()
        }
    }

    
    var maxLimit: Int = 0{
        didSet{
            if count > maxLimit{
                count = maxLimit
            }
            
            isSoldOut = maxLimit == 0
        }
    }
    
    var isSoldOut: Bool = false{
        didSet{
            configComponsnts()
            managebuttons()
        }
    }

    @IBOutlet private weak var contentView: UIView!
    @IBOutlet private weak var titleButton: UIButton!
    @IBOutlet private weak var addButton: UIButton!
    @IBOutlet private weak var removeButton: UIButton!
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
    }
    
    private func commonInit() {
        backgroundColor = .clear
        Bundle.main.loadNibNamed("AddToCartButton", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        count = 0
    }
    
    private func configComponsnts(){
        //SET VIEW
        contentView.viewCorneRadius(radius: 0.0, isRound: true)
      
        
        if isSoldOut{
            contentView.viewBorderCorneRadius(radius: contentView.frame.size.height / 2, borderColour: .clear)
            contentView.backgroundColor = .secondaryText
            
            titleButton.configureLable(bgColour: .clear, textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 10.0, text: str.soldOut)
            
            self.removeButton.isHidden = true
            self.addButton.isHidden = true
        }
        else{
            contentView.viewBorderCorneRadius(radius: contentView.frame.size.height / 2, borderColour: .clear)
            contentView.backgroundColor = .clear
            

            titleButton.configureLable(bgColour: .clear, textColor: .secondaryTextView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "")
            titleButton.backgroundColor = .clear
            
            addButton.configureLable(bgColour: .secondaryTextView, textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "+")
            addButton.isHidden = true
            addButton.btnCorneRadius(radius: 0, isRound: true)
            
            removeButton.configureLable(bgColour: .secondaryTextView, textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: "-")
            removeButton.isHidden = true
            removeButton.btnCorneRadius(radius: 0, isRound: true)
        }
    }
    
 
    
    
    @IBAction
    private func addButtonAction(){

        count += 1

        if let delegate = self.delegate{
            delegate.itemAddedAtIndexPath(indexPath, count: count)
        }
        else if let delegate = self.delegate{
            delegate.itemAddedAtIndexPath(IndexPath.init(), count: count)
        }

//        }
    }
    
    @IBAction
    private func removeButtonAction(){
        
        if count > 0 {
            count -= 1
        }
        
        if count == 0{
            count = 1
            return
        }
        
        
        if let delegate = self.delegate{
            delegate.itemRemovedAtIndexPath(indexPath, count: count)
        }
        else if let delegate = self.delegate{
            delegate.itemRemovedAtIndexPath(IndexPath.init(), count: count)
        }

    }
    
    private func managebuttons(){

        UIView.animate(withDuration: 0.1) {
            
            if self.isSoldOut{
                
                self.contentView.viewBorderCorneRadius(radius: self.contentView.frame.size.height / 2, borderColour: .clear)
                self.contentView.backgroundColor = .secondaryText

                self.titleButton.configureLable(bgColour: .clear, textColor: UIColor.background, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 10.0, text: str.soldOut)
                
                self.removeButton.isHidden = true
                self.addButton.isHidden = true
            }
            else{
                
                self.contentView.viewBorderCorneRadius(radius: self.contentView.frame.size.height / 2, borderColour: .clear)
                self.contentView.backgroundColor = .clear
                self.titleButton.setTitle( "\(self.count)", for: .normal)

                self.removeButton.isHidden = false
                self.addButton.isHidden = false
            }
            
            self.layoutIfNeeded()
        }
    }
}
