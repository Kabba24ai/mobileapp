//
//  OrderListButtonAction.swift
//  RentnKing
//
//  Created by Jigar Khatri on 11/08/25.
//

import UIKit
import MessageUI


extension OrderListViewController : MFMessageComposeViewControllerDelegate, TermsDelegate{
 
    
    @objc func btnCallClicked(_ sender : UIButton) {
        
        if self.arrOrderList.count == 0{
            return
        }
        
        //GET DATA
        let objData = self.arrOrderList[sender.tag]
        
        var getNumber = objData.objDeliveryAddress?.phone ?? ""
        getNumber = getNumber.replacingOccurrences(of: "+1", with: "")
        
        let pickerAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        
      
        let cancel = UIAlertAction.init(title: "Cancel", style: UIAlertAction.Style.cancel, handler: { (action) in
            
            pickerAlert.dismiss(animated: true, completion: nil)
        })
        
        let call = UIAlertAction.init(title: "Call \(objData.objDeliveryAddress?.phone ?? "")", style: UIAlertAction.Style.default, handler: { (action) in
            
               guard let number = URL(string: "tel://+1\(getNumber)") else { return }
               UIApplication.shared.open(number)

        })
        
        let sendMessage = UIAlertAction.init(title: "Send Message", style: UIAlertAction.Style.default, handler: { (action) in
          
            if (MFMessageComposeViewController.canSendText()) {
                let controller = MFMessageComposeViewController()
                controller.body = ""
                controller.recipients = ["+1\(getNumber)"]
                controller.messageComposeDelegate = self
                self.present(controller, animated: true, completion: nil)
            }
        })
        
        
        
        pickerAlert.addAction(call)
        pickerAlert.addAction(sendMessage)
        pickerAlert.addAction(cancel)
        
        if let presenter = pickerAlert.popoverPresentationController {
            presenter.sourceView = sender
            presenter.sourceRect = sender.frame
        }
        self.present(pickerAlert, animated: true, completion: nil)
        

    }
    
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        //... handle sms screen actions
        self.dismiss(animated: true, completion: nil)
    }
    
    
    //TERMS AND CONDITION
    @objc func btnTermsAndConditionClicked(_ sender : UIButton) {
        if self.arrOrderList.count == 0{
            return
        }
        
        //GET DATA
        let objData = self.arrOrderList[sender.tag]
        if objData.terms_status == "Exempt"{
            return
        }
        
        //TERMS AND CONDITION
        if objData.terms_page != ""{
            let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.HOME_MODEL, bundle: nil)
            if let newViewController = storyBoard.instantiateViewController(withIdentifier: "TermsAndConditionViewController") as? TermsAndConditionViewController{
                newViewController.isOrderFrom = true
                newViewController.delegate = self
                newViewController.selectIndex = sender.tag
                newViewController.signUrl = objData.terms_page ?? ""
                self.navigationController?.pushViewController(newViewController, animated: true)
            }
        }
    }
    
    func termsSucess(selectIndex: Int) {
        if self.arrOrderList.count == 0{
            return
        }
        var objData = self.arrOrderList[selectIndex]
        objData.terms_status = "Accepted"
        
        //UODATE TERMS
        self.arrOrderList.remove(at: selectIndex)
        self.arrOrderList.insert(objData, at: selectIndex)
        
        
        //RELOAD CELL
        self.tblView.reloadRows(at: [IndexPath(row: selectIndex, column: 0)], with: .none)
    }
}
