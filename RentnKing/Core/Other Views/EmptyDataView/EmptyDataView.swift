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
    
    /// Dispatch offline (Phase 3): this phone has never downloaded Dispatch and is offline.
    func dispatchNotDownloaded(){
        configure(imageName: "", title: "Dispatch isn't downloaded to this phone yet", subtitle: "Connect to the internet once to download today's work.", tintColor: UIColor.primary)
    }

    /// Dispatch offline (Phase 4): this order has no copy on this phone and the phone is offline.
    func orderNotDownloaded(){
        configure(imageName: "", title: "This order isn't downloaded to this phone yet", subtitle: "Connect to the internet once to open it.", tintColor: UIColor.primary)
    }

    /// Dispatch offline (Phase 4): Terms & Conditions are signed on the server's page.
    func termsNeedConnection(){
        configure(imageName: "", title: "Signing Terms & Conditions needs a connection", subtitle: "Connect to the internet to sign. The rest of the order keeps working offline.", tintColor: UIColor.primary)
    }

    /// The order has no usable signing link.
    func termsUnavailable(){
        configure(imageName: "", title: "Terms & Conditions aren't available for this order", subtitle: "", tintColor: UIColor.primary)
    }

    // Dispatch offline (Phase 5): the order's frozen agreement, signed locally.

    func termsNotRequired(){
        configure(imageName: "", title: "Terms & Conditions aren't required for this order", subtitle: "", tintColor: UIColor.primary)
    }

    func termsAlreadyAccepted(){
        configure(imageName: "", title: "Terms & Conditions are already accepted for this order", subtitle: "", tintColor: UIColor.primary)
    }

    func termsSignedOnThisPhone(synced: Bool){
        configure(imageName: "", title: "Signed on this phone",
                  subtitle: synced ? "Synced with Kabba." : "It syncs automatically when the phone is online.", tintColor: UIColor.primary)
    }

    func termsUnableToVerify(){
        configure(imageName: "", title: "Unable to Verify Order Terms — Refresh the Order Before Signing",
                  subtitle: "Connect to the internet and reopen this order so its terms can be downloaded again.", tintColor: UIColor.primary)
    }

    func termsAgreementUnavailable(){
        configure(imageName: "", title: "This order has no stored terms agreement to sign", subtitle: "Please contact the office.", tintColor: UIColor.primary)
    }

    func termsNotDownloaded(){
        configure(imageName: "", title: "Terms & Conditions for this order aren't downloaded to this phone yet",
                  subtitle: "Connect to the internet to load them.", tintColor: UIColor.primary)
    }

    func termsCouldNotLoad(){
        configure(imageName: "", title: "Couldn't load the Terms & Conditions", subtitle: "Check the connection and try again.", tintColor: UIColor.primary)
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


