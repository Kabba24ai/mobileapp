//
//  RantalReadyVC.swift
//  RentnKing
//
//  Created by Jigar Khatri on 19/03/25.
//

import UIKit

class RantalReadyVC: UIViewController {

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!
    @IBOutlet weak var lblNoData: UILabel!

    @IBOutlet weak var lblUpdate: UILabel!
    @IBOutlet weak var lblUpdateName: UILabel!
    
    @IBOutlet weak var lblUpdateHours: UILabel!
    @IBOutlet weak var lblUpdateTime: UILabel!
    
    @IBOutlet weak var lblMachineHrTitle: UILabel!
    @IBOutlet weak var txtMachineHr: UITextField!
    
    @IBOutlet weak var lblEmployee: UILabel!
    @IBOutlet weak var viewEmployee: UIView!
    @IBOutlet weak var txtSelctEmployee: UITextField!
    
    @IBOutlet weak var lblCheckListTitle: UILabel!

    @IBOutlet weak var btnDamaged: UIButton!
    @IBOutlet weak var btnMainHold: UIButton!
    @IBOutlet weak var btnRentalReady: UIButton!

    @IBOutlet weak var viewHours: UIView!
    @IBOutlet weak var con_hours: NSLayoutConstraint!

    //OTHER
    let rantalReadyPlaceholderMarker = Placeholder()
    var isLoading : Bool = true

    var strID : String = ""
    var selectTequID : String = ""
    
    var objRentalReadyData : RentalReadyModel!
    var arrEmployesList : [EmployeesModel] = []
    var strMachineHours : String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.lblNoData.isHidden = true
        self.lblNoData.configureLable(textAlignment: .center, textColor: .primary.withAlphaComponent(0.6), fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: str.strNoRentalReadyData)

        //GET DATA
        self.getRentalReadyAPI(RentalIDParameater: RentalIDParameater(id: self.strID))
        self.getEmployeesListAPI()
    }
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        
        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
    }

    
    func setTheView(){
        self.isLoading = false
        indicatorHide()
        self.stopLoading()

        //SET FONT
        if self.objRentalReadyData != nil{
            //CHECK DATA
            self.tblView.isHidden = true
            self.lblNoData.isHidden = false
            if self.objRentalReadyData.checkList?.arrQuestions?.count != 0 && self.objRentalReadyData.checkList?.arrQuestions?.count != nil{
                self.tblView.isHidden = false
                self.lblNoData.isHidden = true
            }
            
            
            self.lblUpdate.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: str.strUpdated)
            self.lblUpdateName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: self.objRentalReadyData.objEmploye == nil ? "" : self.objRentalReadyData.objEmploye?.name ?? "")

            self.lblUpdateTime.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: self.objRentalReadyData.status_change ?? "")
            self.lblUpdateHours.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text:  self.objRentalReadyData.has_machine_hour == 0 ? "" : "Hrs : \(self.objRentalReadyData.machine_hour)")

            self.lblMachineHrTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: str.strMachineHours)
            self.txtMachineHr.configureText(textAlignment: .center, keyboardTye: .numbersAndPunctuation, bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: self.strMachineHours, placeholder: "0")
            self.txtMachineHr.tag = 100
            self.txtMachineHr.delegate = self
            self.txtMachineHr.backgroundColor = .clear

            self.lblEmployee.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: str.strTechMgt)
            self.txtSelctEmployee.configureText(bgColour: .clear, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: "", placeholder: str.strSelectTechMgt)

            self.lblCheckListTitle.configureLable(textColor: .secondary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: str.strChecklistItem)

            //SET VIEW
            self.viewEmployee.setTheTextView(bgColor: .secondary )
            self.setTheButton()
            
            self.tblView.reloadData()
            
            //SET HOURS
            self.viewHours.isHidden = true
            self.con_hours.constant = 0
            if self.objRentalReadyData.has_machine_hour != 0 {
                self.viewHours.isHidden = false
                self.con_hours.constant = 45
            }
            
           //SET HEADER
           DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
               //SET TABLE HEADER
               let vw_Table = self.tblView.tableHeaderView
               vw_Table?.frame = CGRect(x: 0, y: 0, width: self.tblView.frame.size.width, height: self.lblCheckListTitle.frame.origin.y + self.lblCheckListTitle.frame.size.height)
               
               self.tblView.tableHeaderView = vw_Table
               
               //RELOAD TABLE
               DispatchQueue.main.asyncAfter(deadline: .now()) {
                   self.tblView.reloadData()
               }
               
           }
        }
   
    }
    
    func setTheButton(){
        self.btnDamaged.configureLable(bgColour:.lightGray, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Damaged")
        self.btnMainHold.configureLable(bgColour: .lightGray, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Maint. Hold")
        self.btnRentalReady.configureLable(bgColour: .lightGray, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Rental Ready")
        
        self.btnDamaged.viewCorneRadius(radius: 10, isRound: false)
        self.btnMainHold.viewCorneRadius(radius: 10, isRound: false)
        self.btnRentalReady.viewCorneRadius(radius: 10, isRound: false)
        
        
        
      
        self.btnDamaged.isEnabled = false
        self.btnMainHold.isEnabled = false
        self.btnRentalReady.isEnabled = false
        if self.checkType().contains(where: { $0 == "Damaged"}) == true{
            self.btnDamaged.isEnabled = true
            self.btnDamaged.configureLable(bgColour:  .redText, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Damaged")
        }
        else if self.checkType().contains(where: { $0 == "Maint. Hold"}) == true{
            self.btnMainHold.isEnabled = true
            self.btnMainHold.configureLable(bgColour: .secondaryText , textColor: .background, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Maint. Hold")

        }
        else if self.checkType().contains(where: { $0 == "Rental Ready"}) == true{
            self.btnRentalReady.isEnabled = true
            self.btnRentalReady.configureLable(bgColour: .greenText , textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Rental Ready")

        }
    }
    
   
    func checkType() -> [String]{
        var arrTrpe : [String] = []
        for objDetails in self.objRentalReadyData.checkList?.arrQuestions ?? []{
            let MenuID = objDetails.objQuestion?.arrAnswer.map{$0.answer}
            if objDetails.objQuestion?.objSelectAnswer != nil{
                if let index = MenuID?.firstIndex(of: objDetails.objQuestion?.objSelectAnswer.answer ?? ""){
                    arrTrpe.append(objDetails.objQuestion?.arrAnswer[index].rentalAnswer_value ?? "")
                }
            }
        }
        
        return arrTrpe
    }
    
    func stopLoading(){
        indicatorHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.rantalReadyPlaceholderMarker.remove()
        }
    }
}



//MARK: -- UITEXTFIELD DELEGATE
extension RantalReadyVC : UITextFieldDelegate{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool{
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        if textField.tag == 100 {
            let inverseSet = NSCharacterSet(charactersIn:"0123456789.").inverted
            let components = string.components(separatedBy: inverseSet)
            let filtered = components.joined(separator: "")
            
            if filtered == string {
                guard let text = textField.text else { return false }
                let newString = (text as NSString).replacingCharacters(in: range, with: string)
                self.strMachineHours = newString
                
            }
            else{
                return false
            }
            
            
            return true
            
        } else {
            return false
        }
    }
}


//MARK: - BUTTON ACTION
extension RantalReadyVC{
    
    @IBAction func btnSelectEmployeClicked(_ sender: UIButton) {
        self.view.endEditing(true)
        
        if self.arrEmployesList.count == 0{
            return
        }
        
        actionPicker(sender, strTitle: "Select Tech / Mgt", arrData: self.arrEmployesList.compactMap { $0.name}, selectValue: self.txtSelctEmployee.text ?? "") { index, selectValue in
            
            self.txtSelctEmployee.text = selectValue
            self.selectTequID = "\(self.arrEmployesList[index].id ?? 0)"
        }
    }
    
    
    @IBAction func btnUpdateDataClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if self.objRentalReadyData.has_machine_hour == 1{
            if self.strMachineHours == ""{
                showAlert("Please enter the machine hours")
                return
            }
        }
       
        if self.selectTequID == ""{
            showAlert("Please select tech/mgt.")
            return
        }
        else{
            self.updateRentalReady(UpdateRentalParameater: UpdateRentalParameater(inventory_id: "\(self.objRentalReadyData.id ?? 0)", machine_hour: self.strMachineHours, employee_id: self.selectTequID), arrData: self.getRentalReadyArray())
        }
    }
    
    func getRentalReadyArray() -> [[String : Any]]{
        var arrRentalReady : [[String : Any]] = []
        for objDetails in self.objRentalReadyData.checkList?.arrQuestions ?? []{
            let MenuID = objDetails.objQuestion?.arrAnswer.map{$0.answer}
            if objDetails.objQuestion?.objSelectAnswer != nil{
                if let index = MenuID?.firstIndex(of: objDetails.objQuestion?.objSelectAnswer.answer ?? ""){
                    let dicData : [String : Any] = ["question_id" : "\(objDetails.objQuestion?.id ?? 0)" ,
                                                    "answer" : "\(objDetails.objQuestion?.arrAnswer[index].answer ?? "")",
                                                    "status" : "\(objDetails.objQuestion?.arrAnswer[index].rentalAnswer_value ?? "")"]
                    arrRentalReady.append(dicData)
                }
            }
            
        }
        return arrRentalReady
    }
}




class RantalReadyell : UITableViewCell{

    @IBOutlet weak var lblTitle: UILabel!
    @IBOutlet weak var lblType: UILabel!

    @IBOutlet weak var lblSelectText: UILabel!
    @IBOutlet weak var imgSelect: UIImageView!
    @IBOutlet weak var btnSelect: UIButton!


    @IBOutlet weak var viewLine: UIView!

    
    func getAnimableSubviews() -> [UIView] {
        return [UIView](getAllSubviews())
    }
    
    private func getAllSubviews() -> [UIView] {
        return [
            lblTitle,
            lblSelectText,
            imgSelect,
            viewLine
        ]
    }
}


//MARK: -- UITABEL DELEGATE --

extension RantalReadyVC : UITableViewDelegate, UITableViewDataSource{
    
    //HEADER SECTION
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1

    }
    
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isLoading{
            return 10
        }
        else{
            if self.objRentalReadyData != nil{
                return self.objRentalReadyData.checkList?.arrQuestions?.count ?? 0
            }
            else{
                return 0
            }
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
      
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let cell = tableView.dequeueReusableCell(withIdentifier: "RantalReadyell") as? RantalReadyell{
            cell.backgroundColor = UIColor.clear
            cell.viewLine.isHidden = false

            if isLoading {
                cell.viewLine.isHidden = true
                self.rantalReadyPlaceholderMarker.register(cell.getAnimableSubviews())
                self.rantalReadyPlaceholderMarker.startAnimation()
                return cell
            }
            
            if self.objRentalReadyData == nil {
                return cell
            }
            
            if self.objRentalReadyData.checkList?.arrQuestions?.count == 0 {
                return cell
            }
            
            let  objDetails = self.objRentalReadyData.checkList?.arrQuestions?[indexPath.row]
                        

            cell.lblTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text: "\(objDetails?.objQuestion?.question ?? "")")

            
            //SET VALUE
            cell.lblSelectText.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")
            let MenuID = objDetails?.objQuestion?.arrAnswer.map{$0.answer}
            if objDetails?.objQuestion?.objSelectAnswer != nil{
                if let index = MenuID?.firstIndex(of: objDetails?.objQuestion?.objSelectAnswer.answer ?? ""){
                    cell.lblSelectText.text = objDetails?.objQuestion?.arrAnswer[index].answer ?? ""
                    
                    
                    cell.lblType.configureLable(textColor: .primary.withAlphaComponent(0.7), fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: objDetails?.objQuestion?.arrAnswer[index].rentalAnswer_value ?? "")
                    if objDetails?.objQuestion?.arrAnswer[index].rentalAnswer_value == "Damaged"{
                        cell.lblType.textColor = .redText
                    }
                }
            }
            
            
            
            //SET TYPE
            imgColor(imgColor: cell.imgSelect, colorHex: .primary)
            
            //BUTTON ACTION
            cell.btnSelect.tag = indexPath.row
            cell.btnSelect.addTarget(self, action: #selector(self.btnSelectClicked(_:)), for: .touchUpInside)

            return cell
        }

        return UITableViewCell()
    }

    @objc func btnSelectClicked(_ sender: UIButton) {
        if self.objRentalReadyData == nil {
            return
        }
        
        if self.objRentalReadyData.checkList?.arrQuestions?.count == 0 {
            return
        }
        
        var  objDetails = self.objRentalReadyData.checkList?.arrQuestions?[sender.tag]
               
        //SELECT VALUE
        var strSelectValue : String = ""
        let MenuID = objDetails?.objQuestion?.arrAnswer.map{$0.answer}
        if objDetails?.objQuestion?.objSelectAnswer != nil{
            if let index = MenuID?.firstIndex(of: objDetails?.objQuestion?.objSelectAnswer.answer ?? ""){
                strSelectValue = objDetails?.objQuestion?.arrAnswer[index].answer ?? ""
            }
        }
        
        actionPicker(sender, strTitle: "Select", arrData: objDetails?.objQuestion?.arrAnswer.compactMap { $0.answer} ?? [], selectValue: strSelectValue) { index, selectValue in
            
            var objStatus = objDetails?.objQuestion?.objSelectAnswer
            objStatus?.answer = objDetails?.objQuestion?.arrAnswer[index].answer ?? ""
            objDetails?.objQuestion?.objSelectAnswer = objStatus
            
            
            //UPDATE
            self.objRentalReadyData.checkList?.arrQuestions?.remove(at: sender.tag)
            self.objRentalReadyData.checkList?.arrQuestions?.insert(objDetails!, at: sender.tag)
            
            
         
            //RELOAD TABLE
            self.tblView.reloadData()
            
            
            //RELOAD TABLE
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2){
                self.setTheButton()
            }
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    }
}
