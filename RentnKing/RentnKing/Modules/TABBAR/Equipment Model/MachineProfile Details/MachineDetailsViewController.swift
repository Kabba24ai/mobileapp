//
//  MachineDetailsViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 19/03/25.
//

import UIKit

class MachineDetailsViewController: UIViewController , MachinePageViewControllerDelegate, UIGestureRecognizerDelegate{
 
    @IBOutlet weak var objHeaderCollection: UICollectionView!

    //Other declaationdeclaration
    var indexpath_Header : NSIndexPath = NSIndexPath(row: 0, section: 0)
    var arr_Header = [str.strNoteGeneral, str.strRentalReady, str.strCheckList, str.strPartsList, str.strService]
    var strTitleName : String = ""
    var strID : String = ""
    var arrRentalReady : [RentalReadyModel] = []
    var objRentalReadyData : MachineModel!

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
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true
        
        //SET NAVIGATION BAR
        setNavigationBarFor(controller: self, title: "\(strTitleName)", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCEREEN
            self.navigationController?.popViewController(animated: true)

        } rightActionHandler: {
        }
        
    }
    
    //MARK: - Page view controller -
    var ProspectiveCustomersPageViewController: MachinePageViewController? {
        didSet {
            ProspectiveCustomersPageViewController?.tutorialDelegate = self
            ProspectiveCustomersPageViewController?.strID = self.strID
            ProspectiveCustomersPageViewController?.arrRentalReady = self.arrRentalReady
            ProspectiveCustomersPageViewController?.objRentalReadyData = self.objRentalReadyData
        }
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let ProspectiveCustomersViewController = segue.destination as? MachinePageViewController {
            self.ProspectiveCustomersPageViewController = ProspectiveCustomersViewController
        }
    }
    
    
    //MARK: - Pageview controller Delegate -
    func MachinePageViewController(_ MachinePageViewController: MachinePageViewController, didUpdatePageCount count: Int) {
        
    }
    
    func MachinePageViewController(_ MachinePageViewController: MachinePageViewController, didUpdatePageIndex index: Int) {
        indexpath_Header = NSIndexPath(row: index, section: 0)
        objHeaderCollection.reloadData()
        ProspectiveCustomersPageViewController?.scrollToViewController(index: index)
    }
}

 
//MARK: - Collection View -
extension MachineDetailsViewController : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        return arr_Header.count
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        let obj = self.arr_Header[indexPath.row]
        let label = UILabel(frame: CGRect.zero)
        label.text = "   \(obj)   "
        label.sizeToFit()
        
        var width : CGFloat = 80
        if label.frame.width > 80{
            width = label.frame.width
        }
        
        return CGSize(width: width, height: collectionView.frame.size.height)
//        return CGSize(width: CGFloat(GlobalMainConstants.windowWidth/2), height: collectionView.frame.size.height)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    }
    
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell  = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        cell.backgroundColor = .clear
        
        let lbl_Title : UILabel = cell.viewWithTag(100) as! UILabel
        let view_Bottom : UIView = cell.viewWithTag(101)!
        
        //SET FONT
        lbl_Title.configureLable(textAlignment: .center, textColor: .primary.withAlphaComponent(0.7), fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 16.0, text: arr_Header[indexPath.row])
        
        
        //Manage view
        view_Bottom.isHidden = true
        view_Bottom.backgroundColor = .secondary
        if indexpath_Header.row == indexPath.row{
            view_Bottom.isHidden = false
            lbl_Title.configureLable(textAlignment: .center, textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: arr_Header[indexPath.row])
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        ProspectiveCustomersPageViewController?.scrollToPreviewsViewController(indexCall:indexPath.row)
        indexpath_Header = indexPath as NSIndexPath
        objHeaderCollection.reloadData()
    }
}
