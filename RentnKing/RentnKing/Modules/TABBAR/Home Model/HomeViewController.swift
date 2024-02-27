//
//  HomeViewController.swift
//  Kabba Extension
//
//  Created by Jigar Khatri on 07/10/23.
//

import UIKit

class HomeViewController: UIViewController, UIGestureRecognizerDelegate, NavigationDelegate {
    func selectSearch() {
    }
    
    @IBOutlet weak var viewEcommerce: UIView!
    @IBOutlet weak var imgEcommerce: UIImageView!
    @IBOutlet weak var lblEcommerce: UILabel!
    
    @IBOutlet weak var viewSchedule: UIView!
    @IBOutlet weak var imgSchedule: UIImageView!
    @IBOutlet weak var lblSchedule: UILabel!
    
    @IBOutlet weak var viewCRM: UIView!
    @IBOutlet weak var imgCRM: UIImageView!
    @IBOutlet weak var lblCRM: UILabel!
    
    @IBOutlet weak var viewProducts: UIView!
    @IBOutlet weak var imgProducts: UIImageView!
    @IBOutlet weak var lblProducts: UILabel!
    

    //SET NAVIGATION BAR
    @IBOutlet weak var con_NavigationBar : NSLayoutConstraint!
    @IBOutlet private weak var viewNavigation: NavigationBar!{
        didSet{
            viewNavigation.setSearchButton(isHidden: false)
            viewNavigation.delegate = self
        }
    }
    
    
    
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
          
          //SET NAVIGAITON AND TABBAR
          self.con_NavigationBar.constant = GlobalMainConstants.NavigationHeight
          self.navigationController?.setNavigationBarHidden(true, animated: animated)
          self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
          self.navigationController?.interactivePopGestureRecognizer?.delegate = self
          self.tabBarController?.tabBar.isHidden = false
      
          //sET THE VIEW
          self.setTheView()
      }
     
    func setTheView(){
        
        //SET IMG
        imgColor(imgColor: self.imgEcommerce, colorHex: .secondary)
        imgColor(imgColor: self.imgSchedule, colorHex: .secondary)
        imgColor(imgColor: self.imgProducts, colorHex: .secondary)
        imgColor(imgColor: self.imgCRM, colorHex: .secondary)
        
        //SET FONT
        self.lblEcommerce.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strEcommerce)
        self.lblSchedule.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strSchedule)
        self.lblProducts.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strEquipment)
        self.lblCRM.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strCRM)

        //SET VIEW
        self.viewEcommerce.backgroundColor = .clear
        self.viewEcommerce.viewBorderCorneRadius(borderColour: .secondary)
        self.viewEcommerce.viewCorneRadius(radius: 15, isRound: false)
        
        self.viewSchedule.backgroundColor = .clear
        self.viewSchedule.viewBorderCorneRadius(borderColour: .secondary)
        self.viewSchedule.viewCorneRadius(radius: 15, isRound: false)
        
        self.viewProducts.backgroundColor = .clear
        self.viewProducts.viewBorderCorneRadius(borderColour: .secondary)
        self.viewProducts.viewCorneRadius(radius: 15, isRound: false)
        
        self.viewCRM.backgroundColor = .clear
        self.viewCRM.viewBorderCorneRadius(borderColour: .secondary)
        self.viewCRM.viewCorneRadius(radius: 15, isRound: false)
    }
}




//MARK: - BUTTON ACTION
extension HomeViewController{
    
    @IBAction func btnEcommerceClicked(_ sender: UIButton) {
        
        //MOVE FORGOT SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "CategoriesViewController") as? CategoriesViewController{
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
    @IBAction func btnScheduleClicked(_ sender: UIButton) {
        
        //MOVE FORGOT SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.SCHEDULE_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "ScheduleListViewController") as? ScheduleListViewController{
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
}
