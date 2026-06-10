//
//  EmptyDataView.swift
//  BAYNOUNAH
//
//  Created by Jigar Khatri on 22/06/22.
//

import UIKit

class EmptyDataView: UIView {

    @IBOutlet private weak var contentView: UIView!
    
    @IBOutlet private weak var imageView: UIImageView!
    
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var subtitleLabel: UILabel!
    
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
        
        Bundle.main.loadNibNamed("EmptyDataView", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        contentView.backgroundColor = .clear
        
        contentView.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true

        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        subtitleLabel.configureLable(textColor: UIColor.secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 12.0, text: "")
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        
//        imageView.isHidden = true
        titleLabel.isHidden = true
        subtitleLabel.isHidden = true
    }
    
    private func configure(imageName: String = "", title: String = "", subtitle: String = "", tintColor : UIColor?){
        
        imageView.backgroundColor = .clear
        imageView.isHidden = false
        imageView.image = UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = tintColor
        
        titleLabel.configureLable(textColor: tintColor, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "")
        titleLabel.isHidden = title.count == 0
        titleLabel.text = title
        titleLabel.textAlignment = .center

        subtitleLabel.isHidden = subtitle.count == 0
        subtitleLabel.text = subtitle
        subtitleLabel.textAlignment = .center

        contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }
}

extension EmptyDataView{

    func noDataFound(){
        configure(imageName: "", title: "No results found.", subtitle:"", tintColor: UIColor.primary)
    }
    
    func noItemsFound(){
        configure(imageName: "", title: "No products in the cart.", subtitle:"", tintColor: UIColor.primary)
    }
    
//    func noLiveData(){
//        configure(imageName: "icon_Header", title: str.noLive, subtitle:"", tintColor: UIColor.primary)
//    }
////    func noPaymentDetails(){
////        configure(imageName: "icon_logo", title: str.noPaymentDetails, subtitle:"", tintColor: UIColor.primaryText)
////    }
//    func noData(){
//        configure(imageName: "icon_Header", title: str.strNoData, subtitle:"", tintColor: UIColor.primary)
//    }
////
//    func noSearch(){
//        configure(imageName: "icon_Header", title: str.noSearch, subtitle:"", tintColor: UIColor.primary)
//    }
////    func noContent(){
////        configure(imageName: "icon_logo", title: str.noContent, subtitle:"", tintColor: UIColor.primaryText)
////    }
//    func noDetails(){
//        configure(imageName: "icon_Header", title: str.noDetails, subtitle:"", tintColor: UIColor.primary)
//    }

}


