//
//  ImageUploadViewController.swift
//  RentnKing
//
//  Created by Jigar Khatri on 12/02/24.
// Order ID = ORD-YITQ-OM1D

import UIKit
import AVFoundation
import AVKit

protocol ImageVideoUploadDelegate : NSObject {
    func ImageVideoUploadSucess(selectIndex : Int, arrImage : [String])
}


class ImageUploadViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: ImageVideoUploadDelegate?

    //DECLARE VARIABLE
    @IBOutlet weak var tblView: UITableView!
    @IBOutlet weak var con_Submit: NSLayoutConstraint!
    @IBOutlet weak var viewSubmit: UIView!
    @IBOutlet weak var lblSubmit: UILabel!

    //LOADING
    let imageVideoPlaceholderMarker = Placeholder()
    var isLoading : Bool = false
    var strOrderID : String = ""

    //OTHER
    var selectIndex : Int = -1
    var isSelectdelete : Bool = false
    let imagePicker = UIImagePickerController()
    let videoPicker = UIImagePickerController()
    var objOrderData : OrdersModel!
    var objOrderDetail: OrdersListModel!
    var arrImageVideoLisr : [ImageVideoModel] = []
    var arrImageVideoList: [String: [ImageVideoModel]] = [:]
    var strType : String = ""
    private var playerVC: AVPlayerViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.imagePicker.delegate = self
        self.videoPicker.delegate = self
        self.viewSubmit.isHidden = true
        
        // Do any additional setup after loading the view.

        //SET VIEW
        self.setTheView()
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
        setNavigationBarFor(controller: self, title: self.strType == "delivery" ? "Delivery Image/Video Upload" : "Return Image/Video Upload", isTransperent: true, hideShadowImage: true, leftIcon: "icon_back", rightIcon: "", isDetailsScree: true) {
            
            //BACK SCREE
            self.navigationController?.popViewController(animated: true)
            
            
        } rightActionHandler: {
            
            
        }
        
        //SET BUTTON
        self.addDeleteButton()
        if self.arrImageVideoLisr.count == 0 {
//            self.getAPIData()
//            self.getLocalData()
            loadAllMediaData()
            indicatorHide()
        }
    }
    
    
    func loadImage(fileName: String) -> UIImage? {
        let fileURL = ImageVideoUploadDirectory.appendingPathComponent(self.strOrderID).appendingPathComponent(fileName)
        do {
            let imageData = try Data(contentsOf: fileURL)
            return UIImage(data: imageData)
        } catch {
            print("Error loading image : \(error)")
        }
        return nil
    }
    
    func loadAllMediaData() {
        indicatorShow()
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 🔹 Step 1: Fetch local DB data
            let arrLocalImageVideo = CoreDBManager.sharedDatabase.getUploadListData(
                strOrderID: self.strOrderID,
                strType: uploadType.video_image.rawValue,
                strVideoType: self.strType
            )
            
            // ✅ For faster lookup
            let localFileSet: Set<String> = Set(arrLocalImageVideo.compactMap { $0.name?.lowercased() })
            
            var mergedArrImageVideoList: [String: [ImageVideoModel]] = [:]
            var mergedArrImageVideoLisr: [ImageVideoModel] = []
            
            // 🔹 Step 2: Add API Data First
            for obj in self.objOrderDetail.arrProduct {
                let strOrderProductID: String = obj.unique_id ?? ""
                
                var arrData = obj.arrDeliveryMedia
                if self.strType == "pickup" {
                    arrData = obj.arrPickupMedia
                }
                
                if mergedArrImageVideoList[strOrderProductID] == nil {
                    mergedArrImageVideoList[strOrderProductID] = []
                }
                
                for objImage in arrData {
                    guard let mediaURL = objImage.media_url else { continue }
                    
                    if let normalizedApiFile = normalizeFileName(from: mediaURL) {
                        if localFileSet.contains(normalizedApiFile.lowercased()) {
                            print("✅ Already exists locally: \(normalizedApiFile)")
                            // Still add API reference so ordering is preserved
                            continue
                        }
                    }
                    
                    if objImage.media_type == "image" {
                        if let url = URL(string: mediaURL) {
                            let objData = ImageVideoModel(
                                type: "img",
                                image: UIImage(), // placeholder
                                strVideo: url,
                                strUrl: mediaURL,
                                productId: strOrderProductID
                            )
                            mergedArrImageVideoLisr.append(objData)
                            mergedArrImageVideoList[strOrderProductID]?.append(objData)
                        }
                    } else if objImage.media_type == "video" {
                        if let url = URL(string: mediaURL) {
                            let objData = ImageVideoModel(
                                type: "video",
                                image: UIImage(),
                                strVideo: url,
                                strUrl: mediaURL,
                                productId: strOrderProductID
                            )
                            mergedArrImageVideoLisr.append(objData)
                            mergedArrImageVideoList[strOrderProductID]?.append(objData)
                        }
                    }
                }
            }
            
            // 🔹 Step 3: Append Local Data After API Data
            for obj in arrLocalImageVideo {
                let strOrderProductID = obj.productID ?? ""
                if mergedArrImageVideoList[strOrderProductID] == nil {
                    mergedArrImageVideoList[strOrderProductID] = []
                }
                
                if obj.isImage == true {
                    let img = self.loadImage(fileName: obj.name ?? "") ?? UIImage()
                    let url: URL = URL(fileURLWithPath: "")
                    let objData = ImageVideoModel(
                        type: "img",
                        image: img,
                        strVideo: url,
                        strUrl: "",
                        productId: strOrderProductID
                    )
                    mergedArrImageVideoLisr.append(objData)
                    mergedArrImageVideoList[strOrderProductID]?.append(objData)
                } else {
                    let videoURL = ImageVideoUploadDirectory
                        .appendingPathComponent(self.strOrderID)
                        .appendingPathComponent(obj.name ?? "")
                    
                    if let videoThumbnil = self.getThumbnailImage(forUrl: videoURL) {
                        let objData = ImageVideoModel(
                            type: "video",
                            image: videoThumbnil,
                            strVideo: videoURL,
                            strUrl: "",
                            productId: strOrderProductID
                        )
                        mergedArrImageVideoLisr.append(objData)
                        mergedArrImageVideoList[strOrderProductID]?.append(objData)
                    }
                }
            }
            
            // 🔹 Step 4: Update UI
            DispatchQueue.main.async {
                self.arrImageVideoLisr = mergedArrImageVideoLisr
                self.arrImageVideoList = mergedArrImageVideoList
                
                self.tblView.reloadData()
                self.addDeleteButton()
                indicatorHide()
            }
        }
    }

     
//    func getLocalData(){
//        let arrDataVideo = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderID, strType: uploadType.video_image.rawValue, strVideoType: self.strType)
//        
//        for obj in arrDataVideo {
//            let strOrderProductID: String = obj.productID ?? ""
//            
//            // Make sure productId has an array initialized
//            if self.arrImageVideoList[strOrderProductID] == nil {
//                self.arrImageVideoList[strOrderProductID] = []
//            }
//            
//            if obj.isImage == true{
//                let img = self.loadImage(fileName: obj.name ?? "") ?? UIImage()
//                let url: URL = URL(fileURLWithPath: "")
//                let objData = ImageVideoModel(type: "img", image: img, strVideo: url, strUrl: "", productId: obj.productID ?? "")
//                self.arrImageVideoLisr.append(objData)
//                self.arrImageVideoList[strOrderProductID]?.append(objData)
//            }
//            else{
//                let videoURL = ImageVideoUploadDirectory.appendingPathComponent(self.strOrderID).appendingPathComponent(obj.name ?? "")
//                if let videoThumbnil = getThumbnailImage(forUrl: videoURL) {
//                    let objData = ImageVideoModel(type: "video", image: videoThumbnil, strVideo: videoURL, strUrl: "", productId: obj.productID ?? "")
//                    self.arrImageVideoLisr.append(objData)
//                    self.arrImageVideoList[strOrderProductID]?.append(objData)
//                }
//            }
//
//        }
//        
//        //RELOAD TABLE
//        self.tblView.reloadData()
//        self.addDeleteButton()
//
//    }
    func setTheView(){
        self.isLoading = false
        self.viewSubmit.isHidden = false
        self.stopLoading()
        
        //SET FONT
        self.con_Submit.constant = manageWidth(size: 45.0)
        self.viewSubmit.backgroundColor = .secondaryTextView
        self.lblSubmit.configureLable(textColor: .backgroundView, fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, fontSize: 16.0, text: str.strSubmit)
        
        
        //RELOAD TABLE
        self.addDeleteButton()
        self.tblView.reloadData()
    }
    
    func stopLoading(){
        indicatorHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1){
            self.imageVideoPlaceholderMarker.remove()
        }
    }
    
    func addDeleteButton(){
        if self.arrImageVideoLisr.count != 0{
            
            let button: UIButton = UIButton(type:.custom)
            button.backgroundColor = UIColor.clear
            button.setImage(UIImage(named: "icon_Delete"), for: .normal)
            buttonImageColor(btnImage: button, imageName: "icon_Delete", colorHex: isSelectdelete ? .redText : .secondary)
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            button.addTarget(self, action: #selector(deleteTab), for: .touchUpInside)

//            let fds =
//            
//            let rightBarButtonItem = UIBarButtonItem.init(image: UIImage(named: "icon_Delete"), style: .done, target: self, action: #selector(deleteTab))
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: button)
        }
        else{
            self.navigationItem.rightBarButtonItem = nil
        }
    }

    @objc func deleteTab(sender: UIBarButtonItem) {
        // Function body goes here
        if self.isSelectdelete{
            self.isSelectdelete = false
        }else{
            self.isSelectdelete = true
        }
        
        //RELOAD TABLE
        self.addDeleteButton()
        self.tblView.reloadData()
    }
}



//MARK: - BUTTON ACTION
extension ImageUploadViewController {
    
    @IBAction func btnSubmitClicked(_ sender: UIButton) {
        self.view.endEditing(true)

        if self.arrImageVideoLisr.count == 0{
            showAlertMessage(strMessage: "Please select an image or video.")

        }
        if self.isNewImageVideoAdd() == false{
            showAlertMessage(strMessage: "Please select a new image or video.")
        }
        else{
            indicatorShow()
//            let arrData = CoreDBManager.sharedDatabase.getUploadListData(strOrderID: self.strOrderID, strType: uploadType.video_image.rawValue, strVideoType: self.strType)
//            if arrData.count != 0{
//                CoreDBManager.sharedDatabase.deleteUploadData(strOrderID: self.strOrderID, strType: uploadType.video_image.rawValue) { isSave in
//                    if isSave{
                        //SAVE IN TABLE
                        self.saveTheVideoandImageLocal()
//                    }
//                }
//            }
//            else{
//                //SAVE IN TABLE
//                self.saveTheVideoandImageLocal()
//            }
        }
    }
    
    func isNewImageVideoAdd() -> Bool{
        for obj in self.arrImageVideoLisr{
            if obj.type == "img"{
                if obj.image != UIImage(){
                    return true
                }
            }
            else{
              
                if obj.strVideo.absoluteString != ""{
                    return true
                }
            }
        }
        return false
    }
    
    func saveTheVideoandImageLocal(){
        createOrderFolder(strOrderID: self.strOrderID)
        
        let dataPath = ImageVideoUploadDirectory.appendingPathComponent(strOrderID)
        if FileManager.default.fileExists(atPath: dataPath.path) == true {
            //self.checkFileExists(orderID: self.strOrderID, dataPath: dataPath)
            
            let arrRecentSelectedImageVideo = self.arrImageVideoLisr.filter { $0.recentSelect == true }
            
            if arrRecentSelectedImageVideo.count != 0 {
                self.updateFileLocal(arr: arrRecentSelectedImageVideo, uploadPath: dataPath)
            }
        }
        else{
            createImageVideoUploadFolder()
            if FileManager.default.fileExists(atPath: dataPath.path) {
                self.updateFileLocal(arr: self.arrImageVideoLisr, uploadPath: dataPath)
            } else {
                indicatorHide()
                showAlertMessage(strMessage: "Unable to create the upload folder.")
            }
//            self.saveTheVideoandImageLocal()
        }

    }
    
    
    func updateFileLocal(arr : [ImageVideoModel], uploadPath : URL){
        var arrData = arr
        if arrData.count != 0{
            let obj = arrData[0]
            

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                //SAVE IMAGE
                if obj.type == "img"{
                    let imageName = "\(self.strOrderID)_\(Date().timeIntervalSince1970).jpg"
                    if self.saveImage(dataPath: uploadPath, image: obj.image, orderID: self.strOrderID, imageName: imageName){
                        
                        print(obj.productId)
                        
                        let saveParams = SaveImageVideoParameater.init(orderID: self.strOrderID, type: uploadType.video_image.rawValue, isImage: true, name: imageName, videoType: self.strType, productID: obj.productId)
                         
                        CoreDBManager.sharedDatabase.saveUploadDataList(objSaveData: saveParams) { isSave in
                            if isSave{
                                //REMOVE
                                arrData.remove(at: 0)

                                self.updateFileLocal(arr: arrData, uploadPath: uploadPath)

                            }
                        }
                    }
                    else{
                        self.updateFileLocal(arr: arrData, uploadPath: uploadPath)
                    }
                }
                else{
                    //SAVE VIDEO
                    let videoName = "\(self.strOrderID)_\(Date().timeIntervalSince1970).mov"
                    if self.saveVideo(dataPath: uploadPath, videoURL: obj.strVideo, orderID: self.strOrderID, videoName: videoName) {
                        
                        let saveParams = SaveImageVideoParameater.init(orderID: self.strOrderID, type: uploadType.video_image.rawValue, isImage: false, name: videoName, videoType: self.strType, productID: obj.productId)
                        
                        CoreDBManager.sharedDatabase.saveUploadDataList(objSaveData: saveParams) { isSave in
                         
                            if isSave{
                                //REMOVE
                                arrData.remove(at: 0)

                                self.updateFileLocal(arr: arrData, uploadPath: uploadPath)

                            }
                        }
                    }
                    else{
                        self.updateFileLocal(arr: arrData, uploadPath: uploadPath)
                    }
                }
            }
        }
        else{
            //SUCCESS
            indicatorHide()
            showAlertMessage(strMessage: "Uploaded Successfully", isDismiss: true)
           
            //UPLOAD LOCAL DATA
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0){
                GlobalMainConstants.appDelegate?.uploadAllData()
            }

           
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                self.navigationController?.popViewController(animated: true)
            }

        }
    }

    
    func saveImage(dataPath : URL, image: UIImage, orderID : String, imageName : String) -> Bool {
        guard let data = image.jpegData(compressionQuality: 1) ?? image.pngData() else {
            return false
        }
      
        do {
            try data.write(to: dataPath.appendingPathComponent(imageName))
            return true
        } catch {
            print(error.localizedDescription)
            return false
        }
    }

    func saveVideo(dataPath : URL, videoURL: URL, orderID : String, videoName : String) -> Bool {

        do {
            let videoData = try Data(contentsOf: videoURL)
            print(videoData)
            try videoData.write(to: dataPath.appendingPathComponent(videoName), options: .atomic)
            return true
        } catch {
            print("Error")
            return false
        }
       
    }

    
    func checkFileExists(orderID : String, dataPath : URL){
        if FileManager.default.fileExists(atPath: dataPath.path) == true {
            self.clearAllFiles(dataPath: dataPath)
        }
    }
    
    func clearAllFiles(dataPath : URL) {
        let fileManager = FileManager.default
        do {
            let fileName = try fileManager.contentsOfDirectory(atPath: dataPath.path)
                
            for file in fileName {
                // For each file in the directory, create full path and delete the file
                let filePath = URL(fileURLWithPath: dataPath.path).appendingPathComponent(file).absoluteURL
                try fileManager.removeItem(at: filePath)
            }
        } catch let error {
            print(error)
        }
    }
}

//MARK: - UITableView Delegate Datasource method
extension ImageUploadViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.objOrderDetail.arrProduct.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let viewHeader = UIView()
        viewHeader.backgroundColor = .clear
        
        let lbl = UILabel(frame: CGRect.init(x: 20, y: 12, width: self.tblView.frame.size.width - 40, height: 25))
        lbl.textColor = .white
        lbl.text = self.objOrderDetail.arrProduct[section].product_name ?? ""
        if self.objOrderDetail.arrProduct[section].objProductData?.product_type == "Rental"{
            viewHeader.addSubview(lbl)
        }

        return viewHeader
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if self.objOrderDetail.arrProduct[section].objProductData?.product_type == "Retail"{
            return 0
        }
        return 45
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if let cell = tableView.dequeueReusableCell(withIdentifier: "OrderProductTableCell", for: indexPath) as? OrderProductTableCell {
            cell.selectionStyle = .none
            cell.viewBG.backgroundColor = .clear
            
            let productId = self.objOrderDetail.arrProduct[indexPath.section].unique_id ?? ""
            cell.objCollectionView.accessibilityValue = productId
            
            let list = arrImageVideoList[productId] ?? []
            cell.setData(productId: productId, items: list, deleteSelection: self.isSelectdelete, parentVC: self)
            
            
            let noOfLines = ((Double(list.count) + 1.0) / 3.0).rounded(.up)
            cell.constraint_collectionView_Height.constant = ((((self.tblView.frame.size.width - CGFloat(80)) / 3) + 12) * noOfLines)
            
            
            //FOR UPDATE THUMBNIL IMAGE
            cell.completionUpdateThumbnilImage = { (productid, indax, thumbnilImage) in
                // ✅ Update model to cache result
                self.arrImageVideoList[productid]?[indax].image = thumbnilImage
                
                let objData = self.arrImageVideoList[productid]?[indax]

                for (indx, dic_value) in self.arrImageVideoLisr.enumerated() {
                    if dic_value.productId == productid {
                        if dic_value.type == "video" {
                            if dic_value.strVideo == objData?.strVideo {
                                self.arrImageVideoLisr[indx].image = thumbnilImage
                                break
                            }
                        }
                    }
                }
            }
            
            //FOR IMAGE VIDEO PREVIEW
            cell.completionVideoPlay = { (video_url) in
                self.playVideo(path: video_url)
            }
            
            cell.completionImagePreview = { (image_data) in
                self.imagePreview(objData: image_data)
            }
            
            cell.completionCloseClicked = { (sender) in
                self.btnCloseClicked(sender)
            }
            
            
            return cell
            
        }
        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if self.objOrderDetail.arrProduct[indexPath.section].objProductData?.product_type == "Retail"{
            return 0
        }

        return UITableView.automaticDimension
    }
    
    
//    func playVideo(path : URL){
//        let player = AVPlayer(url: path)
//        let playerController = AVPlayerViewController()
//        playerController.player = player
//        present(playerController, animated: true) {
//            player.play()
//        }
//    }
    
    func playVideo(path: URL) {
        let asset = AVURLAsset(url: path)
        let item = AVPlayerItem(asset: asset)

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { note in
            print("Failed:", note.userInfo as Any)
            print("ErrorLog:", item.errorLog() as Any)
        }

        let player = AVPlayer(playerItem: item)
        let vc = AVPlayerViewController()
        vc.player = player
        vc.modalPresentationStyle = .fullScreen

        self.playerVC = vc // keep strong ref (safe)

        present(vc, animated: true) {
            player.play()
        }
    }
    
    func imagePreview(objData: ImageVideoModel) {
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        if let imgView = storyBoard.instantiateViewController(withIdentifier: "ImageView") as? ImageView {
            if objData.strUrl != "" && objData.isUpload {
                imgView.strURL = objData.strUrl
            }
            else{
                if objData.strUrl != "" {
                    imgView.strURL = objData.strUrl
                }
                else {
                    imgView.showImage = objData.image
                }
            }
            
            let countryCodeNavigationController = UINavigationController(rootViewController: imgView)
            navigationController?.present(countryCodeNavigationController, animated: true, completion: nil)
        }
    }
    
    @objc func btnCloseClicked(_ sender : UIButton) {

        //CALL API
        let alert = UIAlertController(title: Application.appName, message: "Are you sure you want to remove?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
            
            let productidd = sender.accessibilityValue ?? ""
            let objData = self.arrImageVideoList[productidd]?[sender.tag]

            //REMOVE ITEM
            self.arrImageVideoList[productidd]?.remove(at: sender.tag)
            
            
            for (indx, dic_value) in self.arrImageVideoLisr.enumerated() {
                if dic_value.productId == productidd {
                    if dic_value.type == "img" {
                        if dic_value.image == objData?.image {
                            self.arrImageVideoLisr.remove(at: indx)
                            break
                        }
                    }
                    else {
                        if dic_value.strVideo == objData?.strVideo {
                            self.arrImageVideoLisr.remove(at: indx)
                            break
                        }
                    }
                }
            }
            
            if objData?.strUrl != "" && objData?.isUpload ?? false {
//                self.removeImageVideo(ImageVideoRemoveParameater: ImageVideoRemoveParameater(order_id: self.strOrderID, file_name: objData?.strUrl ?? ""))
            }
            else{
                //RELOAD
                self.addDeleteButton()
                self.tblView.reloadData()
            }
            
        }))
        alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
}

////MARK: - Collection View -
//extension ImageUploadViewController : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout{
//    
//    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
//        if isLoading{
//            return 10
//        }
//        else{
//            return self.arrImageVideoLisr.count + 1
//        }
//    }
//
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
//        return UIEdgeInsets(top: 0, left: 30, bottom: 0, right: 30)
//    }
//    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
//        return 10
//    }
//    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//        return CGSize(width: (collectionView.frame.size.width - CGFloat(80)) / 3 , height: ((collectionView.frame.size.width - CGFloat(80)) / 3))
//    }
//
//    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
//
//        let cell  = collectionView.dequeueReusableCell(withReuseIdentifier: "CategoryCell", for: indexPath) as! CategoryCell
//        cell.backgroundColor = UIColor.clear
//        cell.viewBG.backgroundColor = .clear
//        cell.viewCloseMain.isHidden = true
//        cell.imgAdd.isHidden = true
//        
//        if isLoading{
//            self.imageVideoPlaceholderMarker.register(cell.getAnimableSubviews())
//            self.imageVideoPlaceholderMarker.startAnimation()
//            return cell
//        }
//        
//        //SET VIEW
//        cell.viewBG.viewCorneRadius(radius: 10, isRound: false)
//        cell.viewBG.viewBorderCorneRadius(borderColour: .secondaryView)
//        
//        
//        //SET TITLE AND TIME
//        cell.imgAdd.isHidden = false
//        if indexPath.row == self.arrImageVideoLisr.count {
//            cell.imgCategory.backgroundColor = .clear
//            cell.imgAdd.image = UIImage(named: "icon_addImageVideo")
//            cell.imgCategory.image = UIImage(named: "")
//            
//        }
//        else{
//            //SET IMG
//            cell.imgCategory.backgroundColor = .white
//            let objData = self.arrImageVideoLisr[indexPath.row]
//            cell.imgCategory.image = objData.image
//            
//            if  objData.type == "video"{
//                cell.imgAdd.image = UIImage(named: "icon_play")
//                
//                if objData.strUrl != "" && objData.isUpload{
//                    cell.imgCategory.image = getThumbnailImage(forUrl: URL(string: objData.strUrl)!)
//                }
//                
//            }
//            else{
//                cell.imgAdd.image = UIImage(named: "icon_view")
//                
//                if objData.strUrl != "" && objData.isUpload{
//                    cell.imgCategory.setImageURL(strImg: objData.strUrl)
//                }
//            }
//
//        }
//        
//        // BUTTON ACTION
//        cell.btnSelect.tag = indexPath.row
//        cell.btnSelect.accessibilityValue = collectionView.accessibilityValue ?? ""
//        cell.btnSelect.addTarget(self, action: #selector(self.btnSelectClicked(_:)), for: .touchUpInside)
//
//        
//        //SET CLOSE BUTTON
//        cell.viewClose.backgroundColor = .secondary
//        cell.viewClose.viewCorneRadius(radius: 0, isRound: true)
//        cell.viewCloseMain.isHidden = true
//        cell.imgAdd.isHidden = false
//        cell.btnClose.isHidden = true
//        if self.isSelectdelete{
//            if indexPath.row != self.arrImageVideoLisr.count {
//                cell.imgAdd.isHidden = true
//                cell.viewCloseMain.isHidden = false
//                cell.btnClose.isHidden = false
//                
//                // BUTTON ACTION
//                cell.btnClose.tag = indexPath.row
//                cell.btnClose.addTarget(self, action: #selector(self.btnCloseClicked(_:)), for: .touchUpInside)
//            }
//        }
//        
//        return cell
//    }
//    
//    @objc func btnCloseClicked(_ sender : UIButton) {
//
//        //CALL API
//        let alert = UIAlertController(title: Application.appName, message: "Are you sure you want to remove?", preferredStyle: .alert)
//        alert.addAction(UIAlertAction(title: str.yes, style: .default,handler: { (Action) in
//            
//            let objData = self.arrImageVideoLisr[sender.tag]
//
//            //REMOVE ITEM
//            self.arrImageVideoLisr.remove(at: sender.tag)
//            if objData.strUrl != "" && objData.isUpload{
//                self.removeImageVideo(ImageVideoRemoveParameater: ImageVideoRemoveParameater(order_id: self.strOrderID, file_name: "order-images/17077984059500241.jpeg"))
//            }
//            else{
//                //RELOAD
//                self.addDeleteButton()
//                self.tblView.reloadData()
//            }
//            
//        }))
//        alert.addAction(UIAlertAction(title: str.no, style: .cancel, handler: nil))
//        self.present(alert, animated: true)
//    }
//    
//    @objc func btnSelectClicked(_ sender : UIButton) {
//        if sender.tag != self.arrImageVideoLisr.count {
//            let objData = self.arrImageVideoLisr[sender.tag]
//            if  objData.type == "video" {
//                if objData.strUrl != "" && objData.isUpload{
//                    self.playVideo(path: URL(string: objData.strUrl)!)
//                }
//                else{
//                    self.playVideo(path: objData.strVideo)
//                }
//            }
//            else{
//                //LOGIN SCREEN
//                let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
//                if let imgView = storyBoard.instantiateViewController(withIdentifier: "ImageView") as? ImageView {
//                    if objData.strUrl != "" && objData.isUpload{
//                        imgView.strURL = objData.strUrl
//                    }
//                    else{
//                        imgView.showImage = objData.image
//                    }
//                    
//                    let countryCodeNavigationController = UINavigationController(rootViewController: imgView)
//                    navigationController?.present(countryCodeNavigationController, animated: true, completion: nil)
//                }
//            }
//        }
//        else{
//            self.selectType(senderr: sender)
//        }
//    }
//    
//    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
//        
//    }
//
//    func playVideo(path : URL){
//        let player = AVPlayer(url: path)
//        let playerController = AVPlayerViewController()
//        playerController.player = player
//        present(playerController, animated: true) {
//            player.play()
//        }
//    }
//}




//MARK: - UIImagePicker View Delegate Datasource method

extension ImageUploadViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func selectType(senderr: UIButton){
        let imageAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        
      
        let Capture = UIAlertAction.init(title: "Select Video", style: .default, handler: { (action) in
            self.openVideoPicker(senderr: senderr)

        })
        
        let chosefromlib = UIAlertAction.init(title: "Select Image", style: .default, handler: { (action) in
            self.openImagePicker(senderr: senderr)

        })
        
        
        let cancel = UIAlertAction.init(title: "Cancel", style: .destructive, handler: { (action) in
            
            imageAlert.dismiss(animated: true, completion: nil)
        })
        
        
        imageAlert.addAction(Capture)
        imageAlert.addAction(chosefromlib)
        imageAlert.addAction(cancel)
        
        if let presenter = imageAlert.popoverPresentationController {
            presenter.sourceView = senderr
            presenter.sourceRect = senderr.frame
        }
        self.present(imageAlert, animated: true, completion: nil)

    }
    func openImagePicker(senderr: UIButton) {
        
        let imageAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        
      
        let Capture = UIAlertAction.init(title: "Take Photo", style: .default, handler: { (action) in
            
            
            if(UIImagePickerController .isSourceTypeAvailable(UIImagePickerController.SourceType.camera)) {
                self.imagePicker.sourceType = .camera
                self.imagePicker.cameraDevice = .rear
                self.imagePicker.showsCameraControls = true
                self.imagePicker.allowsEditing = true
                self.imagePicker.accessibilityValue = senderr.accessibilityValue ?? ""
                
                GlobalMainConstants.appDelegate?.window?.rootViewController?.present(self.imagePicker, animated: true, completion: nil)
            }
            else{
                showAlertMessage(strMessage: str.notSupportCamera)
            }
        })
        
        let chosefromlib = UIAlertAction.init(title: "Choose Photo", style: .default, handler: { (action) in
            
            self.imagePicker.sourceType = .photoLibrary
            self.imagePicker.allowsEditing = true
            self.imagePicker.accessibilityValue = senderr.accessibilityValue ?? ""
            GlobalMainConstants.appDelegate?.window?.rootViewController?.present(self.imagePicker, animated: true, completion: nil)
        })
        
        
        let cancel = UIAlertAction.init(title: "Cancel", style: .destructive, handler: { (action) in
            
            imageAlert.dismiss(animated: true, completion: nil)
        })
        
        
        imageAlert.addAction(Capture)
        imageAlert.addAction(chosefromlib)
        imageAlert.addAction(cancel)
        
        if let presenter = imageAlert.popoverPresentationController {
            presenter.sourceView = senderr
            presenter.sourceRect = senderr.frame
        }
        self.present(imageAlert, animated: true, completion: nil)
    }
    
    func openVideoPicker(senderr: UIButton) {
        
        let imageAlert = UIAlertController.init(title: nil, message: nil, preferredStyle: .actionSheet)
        
      
        let Capture = UIAlertAction.init(title: "Take Video", style: .default, handler: { (action) in
            
            if(UIImagePickerController .isSourceTypeAvailable(UIImagePickerController.SourceType.camera)) {
                self.videoPicker.sourceType = .camera
                self.videoPicker.cameraDevice = .rear
                self.videoPicker.mediaTypes = ["public.movie"]
                self.videoPicker.videoMaximumDuration = 30
                self.videoPicker.cameraFlashMode = .auto
                self.videoPicker.videoQuality = .typeHigh
                self.videoPicker.showsCameraControls = true
                self.videoPicker.allowsEditing = true
                self.videoPicker.accessibilityValue = senderr.accessibilityValue ?? ""
                
                GlobalMainConstants.appDelegate?.window?.rootViewController?.present(self.videoPicker, animated: true, completion: nil)
            }
            else{
                showAlertMessage(strMessage: str.notSupportCamera)
            }
        })
        
        let chosefromlib = UIAlertAction.init(title: "Choose Video", style: .default, handler: { (action) in
            
            self.videoPicker.sourceType = .photoLibrary
            self.videoPicker.mediaTypes = ["public.movie"]
            self.videoPicker.videoMaximumDuration = 30
            self.videoPicker.videoQuality = .typeHigh
            self.videoPicker.allowsEditing = true
            self.videoPicker.accessibilityValue = senderr.accessibilityValue ?? ""
            GlobalMainConstants.appDelegate?.window?.rootViewController?.present(self.videoPicker, animated: true, completion: nil)
        })
        
        
        let cancel = UIAlertAction.init(title: "Cancel", style: .destructive, handler: { (action) in
            
            imageAlert.dismiss(animated: true, completion: nil)
        })
        
        
        imageAlert.addAction(Capture)
        imageAlert.addAction(chosefromlib)
        imageAlert.addAction(cancel)
        
        if let presenter = imageAlert.popoverPresentationController {
            presenter.sourceView = senderr
            presenter.sourceRect = senderr.frame
        }
        self.present(imageAlert, animated: true, completion: nil)
    }
    
//    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
//        picker.dismiss(animated: true, completion: nil)
//        print("in here")
//        if let pickedVideo = info[UIImagePickerController.InfoKey(rawValue: UIImagePickerController.InfoKey.mediaURL.rawValue)] as? URL {
//                print(pickedVideo)
//            do {
//                print("Converted")
//               // let VideoData = try Data(contentsOf: pickedVideo)
//                uploadVideo(VideoData: try Data(contentsOf: pickedVideo), URL: pickedVideo)
//                
//            } catch let error {
//                print(error.localizedDescription)
//            }
//            
//            }
//       
//    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true) {
            
            let strOrderProductID = picker.accessibilityValue ?? ""
            
            if let movieUrl = info[.mediaURL] as? URL {
                do {
                    let video = try Data(contentsOf: movieUrl)
                    print(video)

                    
                } catch {
                    print("Error")
                }

                
                //UPDATE IMAGE DAT
                let objData = ImageVideoModel(type: "video", image: self.getThumbnailImage(forUrl: movieUrl)!, strVideo: movieUrl, strUrl: "", productId: strOrderProductID, recentSelect: true)
                self.arrImageVideoLisr.append(objData)
                
                // Make sure productId has an array initialized
                if self.arrImageVideoList[strOrderProductID] == nil {
                    self.arrImageVideoList[strOrderProductID] = []
                }
                
                self.arrImageVideoList[strOrderProductID]?.append(objData)
                
                //RELOAD
                self.addDeleteButton()
                self.tblView.reloadData()

            }
            else if let PickedImage: UIImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {
                DispatchQueue.main.async {

                    //UPDATE IMAGE DAT
                    let url: URL = URL(fileURLWithPath: "")
                    let objData = ImageVideoModel(type: "img", image: PickedImage, strVideo: url, strUrl: "", productId: strOrderProductID, recentSelect: true)
                    self.arrImageVideoLisr.append(objData)
                    
                    // Make sure productId has an array initialized
                    if self.arrImageVideoList[strOrderProductID] == nil {
                        self.arrImageVideoList[strOrderProductID] = []
                    }
                    
                    self.arrImageVideoList[strOrderProductID]?.append(objData)
                    
                    //RELOAD
                    self.addDeleteButton()
                    self.tblView.reloadData()
                }
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) {
        }
    }
    
    
    func getThumbnailImage(forUrl url: URL) -> UIImage? {
        let asset: AVAsset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)

        do {
            let thumbnailImage = try imageGenerator.copyCGImage(at: CMTimeMake(value: 1, timescale: 30), actualTime: nil)
            return UIImage(cgImage: thumbnailImage)
        } catch let error {
            print(error)
        }

        return nil
    }
}




//MARK: - CUSTOM TABLE CELL
class OrderProductTableCell: UITableViewCell {
        
    var orderProductID: String = ""
    var isSelectdelete : Bool = false
    var superParentVC: UIViewController?
    var arrProductList: [ImageVideoModel] = []
    var completionVideoPlay: ((URL) -> Void)?
    var completionImagePreview: ((ImageVideoModel) -> Void)?
    var completionCloseClicked: ((UIButton) -> Void)?
    var completionUpdateThumbnilImage: ((String, Int, UIImage) -> Void)?

    @IBOutlet weak var viewBG: UIView!
    @IBOutlet weak var objCollectionView: UICollectionView!
    @IBOutlet weak var constraint_collectionView_Height: NSLayoutConstraint!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        objCollectionView.delegate = self
        objCollectionView.dataSource = self
        objCollectionView.isScrollEnabled = false

    }
    
    func setData(productId: String, items: [ImageVideoModel], deleteSelection: Bool, parentVC: UIViewController?) {
        self.orderProductID = productId
        self.arrProductList = items
        self.isSelectdelete = deleteSelection
        self.superParentVC = parentVC
        objCollectionView.reloadData()
    }
    
}

//MARK: - Collection View -
extension OrderProductTableCell : UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout{
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.arrProductList.count + 1
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 30, bottom: 0, right: 30)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 10
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: (collectionView.frame.size.width - CGFloat(80)) / 3 , height: ((collectionView.frame.size.width - CGFloat(80)) / 3))
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell  = collectionView.dequeueReusableCell(withReuseIdentifier: "CategoryCell", for: indexPath) as! CategoryCell
        cell.backgroundColor = UIColor.clear
        cell.viewBG.backgroundColor = .clear
        cell.viewCloseMain.isHidden = true
        cell.imgAdd.isHidden = true
        cell.loader.isHidden = true
        
        //SET VIEW
        cell.viewBG.viewCorneRadius(radius: 10, isRound: false)
        cell.viewBG.viewBorderCorneRadius(borderColour: .secondaryView)
        
        
        //SET TITLE AND TIME
        cell.imgAdd.isHidden = false
        if indexPath.row == self.arrProductList.count {
            cell.imgCategory.backgroundColor = .clear
            cell.imgAdd.image = UIImage(named: "icon_addImageVideo")
            cell.imgCategory.image = UIImage(named: "")
            
        }
        else{
            //SET IMG
            cell.imgCategory.backgroundColor = .white
            let objData = self.arrProductList[indexPath.row]
            if objData.strUrl != "" {
                cell.imgCategory.setImageURL(strImg: objData.strUrl)
            }
            else {
                cell.imgCategory.image = objData.image
            }
            
            if objData.type == "video" {
                cell.imgAdd.image = UIImage(named: "icon_play")

                if objData.strUrl != "" {
                    // Remote video
                    if let url = URL(string: objData.strUrl) {
                        if objData.image != UIImage() {
                            cell.imgCategory.image = objData.image
                        }
                        else {
                            cell.loader.isHidden = false
                            cell.loader.startAnimating()
                            DispatchQueue.global().async {
                                if let thumbnail = getThumbnailImage(forUrl: url) {
                                    DispatchQueue.main.async {
                                        self.completionUpdateThumbnilImage?(collectionView.accessibilityValue ?? "", indexPath.row, thumbnail)

                                        // ✅ Reload just this cell
                                        if let visibleCell = collectionView.cellForItem(at: indexPath) as? CategoryCell {
                                            visibleCell.imgCategory.image = thumbnail
                                            cell.loader.isHidden = true
                                        }
                                    }
                                }
                            }
                        }
                        
                    }
                } else {
                    // Local video (already handled in loadAllMediaData)
                    cell.imgCategory.image = objData.image
                }
            }
            
            
            
            
            
            
            
            
            
            
            
//            if  objData.type == "video"{
//                cell.imgAdd.image = UIImage(named: "icon_play")
//                
//                if objData.strUrl != "" && objData.isUpload {
//                    cell.imgCategory.image = getThumbnailImage(forUrl: URL(string: objData.strUrl)!)
//                }
//                
//            }
            else{
                cell.imgAdd.image = UIImage(named: "icon_view")
                
                if objData.strUrl != "" && objData.isUpload{
                    cell.imgCategory.setImageURL(strImg: objData.strUrl)
                }
            }

        }
        
        // BUTTON ACTION
        cell.btnSelect.tag = indexPath.row
        cell.btnSelect.accessibilityValue = collectionView.accessibilityValue ?? ""
        cell.btnSelect.addTarget(self, action: #selector(self.btnSelectClicked(_:)), for: .touchUpInside)

        
        //SET CLOSE BUTTON
        cell.viewClose.backgroundColor = .secondary
        cell.viewClose.viewCorneRadius(radius: 0, isRound: true)
        cell.viewCloseMain.isHidden = true
        cell.imgAdd.isHidden = false
        cell.btnClose.isHidden = true
        if self.isSelectdelete{
            if indexPath.row != self.arrProductList.count {
                cell.imgAdd.isHidden = true
                cell.viewCloseMain.isHidden = false
                cell.btnClose.isHidden = false
                
                // BUTTON ACTION
                cell.btnClose.tag = indexPath.row
                cell.btnClose.accessibilityValue = collectionView.accessibilityValue ?? ""
                cell.btnClose.addTarget(self, action: #selector(self.btnCloseClicked(_:)), for: .touchUpInside)
            }
        }
        
        return cell
    }
    
    @objc func btnCloseClicked(_ sender : UIButton) {
        //CALL API
        self.completionCloseClicked?(sender)
    }
    
    @objc func btnSelectClicked(_ sender : UIButton) {
        if sender.tag != self.arrProductList.count {
            let objData = self.arrProductList[sender.tag]
            if  objData.type == "video" {
                if objData.strUrl != "" && objData.isUpload{
                    if let urlVideo = URL(string: objData.strUrl) {
                        self.completionVideoPlay?(urlVideo)
                    }
                }
                else {
                    self.completionVideoPlay?(objData.strVideo)
                }
            }
            else{
                self.completionImagePreview?(objData)
            }
        }
        else{
            (self.superParentVC as? ImageUploadViewController)?.selectType(senderr: sender)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
    }

}
