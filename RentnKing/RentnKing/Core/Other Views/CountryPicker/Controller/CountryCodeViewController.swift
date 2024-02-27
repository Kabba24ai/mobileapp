//
//  CountryCodeViewController.swift
//  Blaxity
//
//  Created by Apple on 11/07/19.
//  Copyright © 2019 Apple. All rights reserved.
//

import UIKit

protocol CountryCodeDelegate : NSObject {
    func pickedCountryCode(selectedCountryCode : CountryCode)
}

//COUNTRYCODE SCREEN
var searchCountryByName = "Search country by name or code".localized()
var selectCountryCode = "Select country code".localized()

class CountryCodeViewController: UIViewController {
    @IBOutlet private var tblView: UITableView!
    weak var delegate: CountryCodeDelegate?
    private let cellIdenetifier = "cellIdenetifier"

    var arrCountryCodeList: [CountryCode] = [] {
        didSet {
            setup()
        }
    }
 
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.layoutIfNeeded()
        //SET VIEW
        self.view.backgroundColor = .background

        //GET DATA
        arrCountryCodeList = CountryCode.shared.all()
        
        //SET NAVIGATION BAR
        setButtonTitleNavigationBarFor(controller: self, title: selectCountryCode, isTransperent: true, hideShadowImage: true, leftIcon: "icon_close", rightIcon: "") {
            self.navigationController?.dismiss(animated: true, completion: nil)
        } rightActionHandler: {

        }
        
        //SET SEARCH BAR
        configureSearchController(navigationItem: navigationItem)

    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        
        
    }
    
    private func setup() {
        tblView.reloadData()
    }
    
    @discardableResult
    private func configureSearchController(navigationItem: UINavigationItem) -> UISearchController{
        
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        
        searchController.searchBar.placeholder = searchCountryByName
        searchController.searchBar.tintColor = .secondary
        searchController.searchBar.textField?.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 14.0)
        searchController.searchBar.textField?.textAlignment = isRTL ? .right : .left
        
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        return searchController
    }
}


//MARK: - SEARCH DELEGATE
extension CountryCodeViewController: UISearchResultsUpdating{
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text else {
            arrCountryCodeList = CountryCode.shared.all()
            return
        }
        
        if searchText.count == 0 {
            arrCountryCodeList = CountryCode.shared.all()
        }
        else{
            let filteredArray = CountryCode.shared.all().filter({ $0.name.range(of: searchText, options: .caseInsensitive) != nil })
            
            if filteredArray.count == 0{
                let filteredNumber = CountryCode.shared.all().filter({ $0.code.range(of: searchText, options: .caseInsensitive) != nil })
                arrCountryCodeList = filteredNumber
            }
            else{
                arrCountryCodeList = filteredArray
            }
        }
    }
}



//MARK: -- TABLE CELL --
class CountryCell : UITableViewCell{
    @IBOutlet weak var lblName: UILabel!
    @IBOutlet weak var lblCode: UILabel!
    @IBOutlet weak var imgCode: UIImageView!
    @IBOutlet weak var viewLine: UIView!
}

//MARK: - TABLEVIEW DELEGATE
extension CountryCodeViewController : UITableViewDelegate , UITableViewDataSource{
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return arrCountryCodeList.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "CountryCell") as! CountryCell
        cell.backgroundColor = UIColor.clear
        
        cell.imgCode.viewCorneRadius(radius: 5.0, isRound: false)
        cell.imgCode.image = UIImage(named: arrCountryCodeList[indexPath.row].flagImg)
        cell.lblName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: arrCountryCodeList[indexPath.row].name)
        cell.lblCode.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: arrCountryCodeList[indexPath.row].code)
        
        //SET VIEW
        cell.viewLine.bgColour(bgColour: UIColor.background, alpha: 0.8)
        cell.viewLine.viewCorneRadius(radius: 0.0, isRound: true)
        cell.layoutIfNeeded()
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        self.delegate?.pickedCountryCode(selectedCountryCode: arrCountryCodeList[indexPath.row])
        self.navigationController?.dismiss(animated: true, completion: nil)
    }
}



extension UISearchBar {

    var textField : UITextField? {
        if #available(iOS 13.0, *) {
            return self.searchTextField
        } else {
            // Fallback on earlier versions
            for view : UIView in (self.subviews[0]).subviews {
                if let textField = view as? UITextField {
                    textField.textColor = .primary
                    return textField
                }
            }
        }
        return nil
    }
}
