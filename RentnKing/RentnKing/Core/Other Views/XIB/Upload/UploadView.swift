//
//  UploadView.swift
//  RentnKing
//
//  Created by Jigar Khatri on 16/04/24.
//

import UIKit

class UploadView: UIView {
    
    @IBOutlet private weak var contentView: UIView!
    @IBOutlet weak var viewUploadBG: UIView!
    @IBOutlet weak var lblUpload: UILabel!

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
        Bundle.main.loadNibNamed("UploadView", owner: self, options: nil)
        addSubview(contentView)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth,.flexibleHeight]

        self.viewUploadBG.viewCorneRadius(radius: 10, isRound: false)
        self.viewUploadBG.backgroundColor = .greenText
        self.lblUpload.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: "Uploading.. ", numberOfLines: 0)

    }
}
