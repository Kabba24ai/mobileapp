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
    var selectTequserName : String = ""
    
    var objRentalReadyData : MachineModel!
    var arrRentalReady : [RentalReadyModel] = []
    var arrEmployesList : [EmployeesModel] = []
    var strMachineHours : String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.lblNoData.isHidden = true
        self.lblNoData.configureLable(textAlignment: .center, textColor: .primary.withAlphaComponent(0.6), fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 14.0, text: str.strNoRentalReadyData)

        //GET SATA
        //TEMP COMMENT//self.getRentalReadyAPI(RentalIDParameater: RentalIDParameater(equipment_unique_id: self.strID))

        //GET EMPLOYEE LIST DATA
        getEmployeeList { arr_data in
            self.arrEmployesList = arr_data
        }
    }
    
    

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        syncEquipmentWithAPI()
        
        //SET VIEW
        self.view.backgroundColor = .background
        setNeedsStatusBarAppearanceUpdate()
        
        //SET THE VIEW
        self.setTheView()
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
            if self.objRentalReadyData.arrCheckList.count != 0{
                self.tblView.isHidden = false
                self.lblNoData.isHidden = true
            }
            
            
            self.lblUpdate.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 18.0, text: str.strUpdated)
            self.lblUpdateName.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: self.objRentalReadyData.current_status_updated_by)
            self.lblUpdateName.textAlignment = .right
            
            self.lblUpdateTime.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text: self.objRentalReadyData.current_status_changed_at )
//            self.lblUpdateHours.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, fontSize: 16.0, text:  self.objRentalReadyData.has_machine_hour == 0 ? "" : "Hrs : \(self.objRentalReadyData.machine_hour)")

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
            self.viewHours.isHidden = false
            self.con_hours.constant = 45
//            if self.objRentalReadyData.has_machine_hour != 0 {
//                self.viewHours.isHidden = false
//                self.con_hours.constant = 45
//            }
            
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
        self.btnDamaged.accessibilityValue = "Damaged"
        self.btnMainHold.accessibilityValue = "Maint. Hold"
        self.btnRentalReady.accessibilityValue = "Available"
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
        for objDetails in self.arrRentalReady{
            let MenuID = objDetails.arrAnswer?.compactMap { $0.unique_id } ?? []
            if let index = MenuID.firstIndex(of: objDetails.selected_answer ?? ""){
                arrTrpe.append(objDetails.arrAnswer?[index].type ?? "")
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
            self.selectTequserName = self.arrEmployesList[index].name ?? ""
        }
    }
    
    
    @IBAction func btnUpdateDataClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if self.selectTequID == ""{
            showAlert("Please select tech/mgt.")
            return
        }
        else {
            let strHours = Int(self.txtMachineHr.text ?? "") ?? 0
            
            var dic_Equipment = SubmitEqipmentModel.init(JSON: [:])
            dic_Equipment?.id = Int(randomNumber(length: 5))
            dic_Equipment?.status = kOrderStatusType.kPending.rawValue
            dic_Equipment?.equipment_unique_id = self.strID
            dic_Equipment?.user_id = self.selectTequID
            dic_Equipment?.user_name = self.selectTequserName
            dic_Equipment?.equipment_hours = "\(strHours)"
            dic_Equipment?.checklist = self.getRentalReadyArray()
            dic_Equipment?.equipment_status = sender.accessibilityValue ?? ""
            self.updateDataNoInternetCase(equipmet_dic: dic_Equipment)
            
            self.navigationController?.popViewController(animated: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                showAlertMessage(strMessage: "Successfully Updated")
                NotificationCenter.default.post(name: .refreshMachineProfileList, object: nil)
            }
            
            /*
             //TEMP COMMENT

            let dicData : [String : Any] = [
                "equipment_unique_id": self.strID,
                "user_id": self.selectTequID,
                "equipment_hours" : "0",
                "checklist": self.getRentalReadyArray()
            ]
            
            self.updateRentalReady(dicRentalReadyList: dicData)
            */
        }
    }
    
    
    // MARK: - ADD / UPDATE LOCALLY (OFFLINE CASE)
    func updateDataNoInternetCase(equipmet_dic: SubmitEqipmentModel?) {
        guard let dic_equipmet = equipmet_dic else { return }
        
        let storageKey = "\(kFileStorageName.kEquipmentSubmit.rawValue)"
        var arrEquipmentData: [SubmitEqipmentModel] = SDKUserDefault.getMappableArray(SubmitEqipmentModel.self, for: storageKey) ?? []
        
        // Check if note already exists
        if let index = arrEquipmentData.firstIndex(where: { $0.equipment_unique_id == dic_equipmet.equipment_unique_id }) {
            // Replace existing note (edit case)
            arrEquipmentData[index] = dic_equipmet
            print("Updated existing note")
        } else {
            // Append new note
            arrEquipmentData.append(dic_equipmet)
            print("Added new")
        }
        
        if !getEquipmentData().isEmpty {
            let arr_data = getEquipmentData()
            var updatedArray = arr_data

            if let index = updatedArray.firstIndex(where: { $0.unique_id == equipmet_dic?.equipment_unique_id }) {
                updatedArray[index].current_status = equipmet_dic?.equipment_status ?? ""
                updatedArray[index].current_status_changed_at = getCurrentDate()
                updatedArray[index].current_status_updated_by = equipmet_dic?.user_name ?? ""
            }

            //SAVE ARRAY
            SDKUserDefault.saveMappableArray(updatedArray, for: kFileStorageName.kEquipmentList.rawValue)
        }
        
        // Save updated array
        SDKUserDefault.saveMappableArray(arrEquipmentData, for: storageKey)
    }
    
    
    func getRentalReadyArray() -> [[String : Any]]{
        var arrRentalReady : [[String : Any]] = []
        for objDetails in self.arrRentalReady {
            let MenuID = objDetails.arrAnswer?.compactMap { $0.unique_id } ?? []
            if let index = MenuID.firstIndex(of: objDetails.selected_answer ?? ""){
                let dicData : [String : Any] = ["question_unique_id" : "\(objDetails.unique_id ?? "")" ,
                                                "answer_unique_id" : "\(objDetails.arrAnswer?[index].unique_id ?? "")",
                                                "note" : ""]
                arrRentalReady.append(dicData)
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
                return self.arrRentalReady.count
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
            
        
            
            if self.arrRentalReady.count == 0 {
                return cell
            }
            
            let  objDetails = self.arrRentalReady[indexPath.row]
                        

            cell.lblTitle.configureLable(textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 20.0, text:  "\(objDetails.question_name ?? "")")

            
            //SET VALUE
            cell.lblSelectText.configureLable(textAlignment: .center, textColor: .primary, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: "Select")


            
            let MenuID = objDetails.arrAnswer?.compactMap { $0.unique_id } ?? []
            if let index = MenuID.firstIndex(of: objDetails.selected_answer ?? ""){
                let objAnswer = objDetails.arrAnswer?[index]
                
                cell.lblSelectText.text = objAnswer?.answer_name ?? ""
                
                
                cell.lblType.configureLable(textColor: .primary.withAlphaComponent(0.7), fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, fontSize: 14.0, text: objAnswer?.type ?? "")
                if objAnswer?.type == "Damaged"{
                    cell.lblType.textColor = .redText
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
        
        if self.arrRentalReady.count == 0 {
            return
        }
        
        var  objDetails = self.arrRentalReady[sender.tag]
               
        //SELECT VALUE
        var strSelectValue : String = ""
        let MenuID = objDetails.arrAnswer?.compactMap { $0.unique_id } ?? []
        if let index = MenuID.firstIndex(of: objDetails.selected_answer ?? ""){
            let objAnswer = objDetails.arrAnswer?[index]
            strSelectValue = objAnswer?.answer_name ?? ""
        }
        
        actionPicker(sender, strTitle: "Select", arrData: objDetails.arrAnswer?.compactMap { $0.answer_name} ?? [], selectValue: strSelectValue) { index, selectValue in
            
            objDetails.selected_answer = objDetails.arrAnswer?[index].unique_id ?? ""
            
            
            //UPDATE
            self.arrRentalReady.remove(at: sender.tag)
            self.arrRentalReady.insert(objDetails, at: sender.tag)
            
         
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
