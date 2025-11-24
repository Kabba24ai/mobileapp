//
//  ServiceVC.swift
//  RentnKing
//
//  Created by Jigar Khatri on 19/03/25.
//

import UIKit

class ServiceVC: UIViewController {

    @IBOutlet weak var lblTitle: UILabel!

    //OTHER
    let servicePlaceholderMarker = Placeholder()
    var isLoading : Bool = true

    var strID : String = ""

    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    


    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        
        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
        self.lblTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16, text: "Service Vomming Soon")
    }
}
