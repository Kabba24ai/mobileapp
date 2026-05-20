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
    
    @IBOutlet weak var con_Upload: NSLayoutConstraint!  
    @IBOutlet weak var viewEcommerce: UIView!
    @IBOutlet weak var imgEcommerce: UIImageView!
    @IBOutlet weak var lblEcommerce: UILabel!
    
    @IBOutlet weak var viewSchedule: UIView!
    @IBOutlet weak var imgSchedule: UIImageView!
    @IBOutlet weak var lblSchedule: UILabel!
    
    @IBOutlet weak var viewScheduleCount: UIView!
    @IBOutlet weak var lblScheduleCount: UILabel!
    
    @IBOutlet weak var viewCRM: UIView!
    @IBOutlet weak var imgCRM: UIImageView!
    @IBOutlet weak var lblCRM: UILabel!
    
    @IBOutlet weak var viewProducts: UIView!
    @IBOutlet weak var imgProducts: UIImageView!
    @IBOutlet weak var lblProducts: UILabel!
    
    @IBOutlet weak var viewChecking: UIView!
    @IBOutlet weak var imgChecking: UIImageView!
    @IBOutlet weak var lblChecking: UILabel!

    @IBOutlet weak var viewInventory: UIView!
    @IBOutlet weak var imgInventory: UIImageView!
    @IBOutlet weak var lblInventory: UILabel!

    
    //SET NAVIGATION BAR
    @IBOutlet weak var con_NavigationBar : NSLayoutConstraint!
    @IBOutlet private weak var viewNavigation: NavigationBar!{
        didSet{
            viewNavigation.setSearchButton(isHidden: false)
            viewNavigation.delegate = self
        }
    }
    
    var timer : Timer!

    
    override func viewDidLoad() {
        super.viewDidLoad()
        isHomeScreen = true

        NotificationCenter.default.addObserver(self, selector: #selector(self.setcount), name: .scheduleCount, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(startUploadData), name: .startUploadData, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopUploadData), name: .stopUploadData, object: nil)
        
        // Do any additional setup after loading the view.
        
        //CEHCK NOTIFICAITON
        self.openDipLink()
        
        //SET TIMER
        if timer == nil{
            timer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(self.getTimeClockSettingAPI), userInfo: nil, repeats: true)
        }
    }
    
    
    func openDipLink() {
        
        //OPEN NOTIFICATION SCREEN
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if dicNotificationData.count != 0{
                GlobalMainConstants.appDelegate?.moveToNotificaitonScreen(dicData: dicNotificationData)
            }
        }
    }
    
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        GlobalMainConstants.appDelegate?.getScheduleCount()
        
        //UPLOAD LOCAL DATA
        self.stopUploadData()
        
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
        self.getTimeClockSettingAPI()
    }
    
    @objc func startUploadData(){
        self.con_Upload.constant = manageFont(font: 0)
    }
    
    @objc func stopUploadData(){
        self.con_Upload.constant = 0
    }
    
    func setTheView(){
        
        //SET IMG
        imgColor(imgColor: self.imgEcommerce, colorHex: .secondary)
        imgColor(imgColor: self.imgSchedule, colorHex: .secondary)
        imgColor(imgColor: self.imgProducts, colorHex: .secondary)
        imgColor(imgColor: self.imgCRM, colorHex: .secondary)
        imgColor(imgColor: self.imgChecking, colorHex: .secondary)
        imgColor(imgColor: self.imgInventory, colorHex: .secondary)

        //SET FONT
        self.lblEcommerce.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strEcommerce)
        self.lblSchedule.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strSchedule)
        self.lblProducts.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strEquipment)
        self.lblCRM.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strCRM)
        self.lblChecking.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strTimeClock)
        self.lblInventory.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: str.strInventory)

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
        
        self.viewChecking.backgroundColor = .clear
        self.viewChecking.viewBorderCorneRadius(borderColour: .secondary)
        self.viewChecking.viewCorneRadius(radius: 15, isRound: false)

        self.viewInventory.backgroundColor = .clear
        self.viewInventory.viewBorderCorneRadius(borderColour: .secondary)
        self.viewInventory.viewCorneRadius(radius: 15, isRound: false)

        //SET COUNT
        self.setcount()
    }
    
    
    @objc func setcount(){
        //SET SCHEDUKE CIUNT
        self.viewScheduleCount.backgroundColor = .redText
        self.viewScheduleCount.viewCorneRadius(radius: 0.0, isRound: true)
        self.lblScheduleCount.configureLable(textColor: .white, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 12.0, text: "")
        
        
        let scheduleCount = pendingDelivertCount + pendingPickupCount + pastDelivertCount + pastPickupCount
        self.viewScheduleCount.isHidden = true
        if scheduleCount != 0{
            self.viewScheduleCount.isHidden = false
            self.lblScheduleCount.text = "\(scheduleCount)"
        }
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
    
    @IBAction func btnTimeClockClicked(_ sender: UIButton) {
        
        if UserDefaults.standard.useMasterCode == UserDefaults.standard.masterCode{
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TIMECLOCK_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "TimeClockViewController") as? TimeClockViewController{
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
        else{
            //MOVE FORGOT SCREEN
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.TIMECLOCK_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "TimeClockLockViewController") as? TimeClockLockViewController{
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }

    }
    
    
    @IBAction func btnEquipmentClicked(_ sender: UIButton) {
        
        //MOVE FORGOT SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.EQUIPMENT_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "MachineProfileViewController") as? MachineProfileViewController{
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }
    
}
