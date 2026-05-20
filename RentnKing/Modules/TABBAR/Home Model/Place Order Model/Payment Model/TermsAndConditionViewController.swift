//
//  TermsAndConditionViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 31/01/24.
//

import UIKit
import WebKit

protocol TermsDelegate : NSObject {
    func termsSucess(selectIndex : Int)
}


class TermsAndConditionViewController: UIViewController, UIGestureRecognizerDelegate {

    @IBOutlet var objWebKit: WKWebView!

    var signUrl : String = ""
    var isOrderFrom : Bool = false
    var selectIndex : Int = -1
    weak var delegate: TermsDelegate?
    var orderID : String = ""

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
        setNavigationBarFor(controller: self, title: "Terms & Condition", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)

            
        } rightActionHandler: {
            
          
        }
        
        //SET  VIEW
        self.setTheView()
        
    }
    
    func setTheView(){
        
        //SET WEBVIEW
        indicatorShow()
//        self.objWebKit.uiDelegate = self
        self.objWebKit.navigationDelegate = self
        let request  = URLRequest(url: URL(string:self.signUrl)!)
        self.objWebKit.load(request)

    }
}


//extension TermsAndConditionViewController:WKUIDelegate{
//    
//}

extension TermsAndConditionViewController:WKNavigationDelegate{
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error)
    {
        indicatorHide()
        showAlertMessage(strMessage: "\(str.somethingWentWrong)")
    }
    
    
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!)
    {
        indicatorHide()
        
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        print("dicCommit :")
        
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        print(navigationAction.request.url!)
        if   (navigationAction.request.url?.absoluteString.contains("success"))!
        {
            
            showAlertMessage(strMessage: "Terms and Conditions update successfully")
            if self.isOrderFrom{
                self.delegate?.termsSucess(selectIndex: self.selectIndex)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                if self.isOrderFrom{
                    self.navigationController?.popViewController(animated: true)
                }
                else{
                    //TERMS AND CONDITION
                    let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
                    if let newViewController = storyBoard.instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController{
                        newViewController.strOrderID = self.orderID
                        newViewController.isOrderScreen = true
                        self.navigationController?.pushViewController(newViewController, animated: true)
                    }
                }
            }
            
        }
        
        decisionHandler(.allow)
        
    }
    
}


