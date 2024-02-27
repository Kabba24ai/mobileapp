//
//  ImageView.swift
//  RentnKing
//
//  Created by Jigar Khatri on 13/02/24.
//

import UIKit

class ImageView: UIViewController, UIGestureRecognizerDelegate {
    @IBOutlet weak var imgShow: UIImageView!

    var strURL : String = ""
    var showImage = UIImage()
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
        //SET NAVIGAITON AND TABBAR
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true
        
        //SET NAVIGATION BAR
        setNavigationBarFor(controller: self, title: "", isTransperent: true, hideShadowImage: true, leftIcon: "icon_closeSmall", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.dismiss(animated: true)

            
        } rightActionHandler: {
            
            
        }
        
        //SET IMAGE
        self.imgShow.backgroundColor = .white
        if self.strURL != "" {
            self.imgShow.setImageURL(strImg: self.strURL)
        }
        else{
            self.imgShow.image = showImage
        }
    }
}
