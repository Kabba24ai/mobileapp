//
//  NavigationBar.swift
//  Now TV!
//
//  Created by Jigar Khatri on 28/02/23.
//

import UIKit

protocol NavigationDelegate {
    func selectSearch()
}

class NavigationBar: UIView {

    var delegate: NavigationDelegate?

    @IBOutlet private weak var contentView: UIView!
    @IBOutlet private weak var imgSearch: UIImageView!
    @IBOutlet private weak var btnSearch: UIButton!

    
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
        clipsToBounds = true
        
        Bundle.main.loadNibNamed("NavigationBar", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        contentView.backgroundColor = .clear
        setSearchButton(isHidden: false)
    }
}


//MARK: - BUTTON ACTION
extension NavigationBar{
    func setSearchButton(isHidden:Bool){
        self.btnSearch.isHidden = isHidden
        self.imgSearch.isHidden = isHidden
    }
    @IBAction func btnSearchClicked(_ sender: UIButton) {
        if let delegate = self.delegate{
            delegate.selectSearch()
        }
    }
}

