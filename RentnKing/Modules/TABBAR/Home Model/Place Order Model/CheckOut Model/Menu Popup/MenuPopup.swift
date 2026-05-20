//
//  MenuPopup.swift
//  Belboy
//
//  Created by Apple on 16/05/19.
//  Copyright © 2019 iCoderzSolutions. All rights reserved.
//

import UIKit
import ObjectMapper

protocol MenuProtocol : AnyObject {
    func SelctMenuIndex(Index : Int)
}

class MenuPopup: UIViewController {
    
    weak var delegate : MenuProtocol? = nil
    var arr_MenuList: [String] = ["Add Custom Value"]
    var indexRecommended : Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()

       
    }

}


class cellMenuList: UITableViewCell{
    @IBOutlet var lblName: UILabel!
}

extension MenuPopup: UITableViewDelegate,UITableViewDataSource
{
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return arr_MenuList.count
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        
        let cell = tableView.dequeueReusableCell(withIdentifier:"cellMenuList", for: indexPath) as! cellMenuList
        cell.backgroundColor = .primaryView
        
        //SET FONT
        cell.lblName.configureLable(textColor: UIColor.backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: self.arr_MenuList[indexPath.row])
        
        return cell
    }
    
    func  tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        delegate?.SelctMenuIndex(Index: indexPath.row)
        self.dismiss(animated: true, completion: nil)
    }
    
}



