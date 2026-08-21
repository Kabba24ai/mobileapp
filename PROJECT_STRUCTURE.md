# Project Structure — RentnKing / KABBA.AI

Full source tree (build artifacts, `.git`, SPM checkouts, and per-user Xcode data are
omitted; asset catalogs and CoreData model bundles are collapsed to a summary).

```text
RentnKing/  (repository root)
├── RentnKinExtension/
│   ├── Assets.xcassets/  (asset catalog — 5 image sets)
│   ├── Base.lproj/
│   │   └── MainInterface.storyboard
│   ├── Colour.xcassets/  (asset catalog — 0 image sets)
│   ├── Core/
│   │   ├── Font/
│   │   │   ├── HelveticaNeue.ttc
│   │   │   ├── Roboto-Black.ttf
│   │   │   ├── Roboto-Bold.ttf
│   │   │   ├── Roboto-Light.ttf
│   │   │   ├── Roboto-Medium.ttf
│   │   │   └── Roboto-Regular.ttf
│   │   ├── Navigation/
│   │   │   ├── NavigationControllerExtension.swift
│   │   │   └── UIBarButtonItemWithClouserExtension.swift
│   │   ├── Navigation Exrension/
│   │   │   ├── NavigationControllerExtension.swift
│   │   │   └── UIBarButtonItemWithClouserExtension.swift
│   │   ├── TagListView/
│   │   │   ├── CloseButton.swift
│   │   │   ├── TagListView.swift
│   │   │   └── TagView.swift
│   │   ├── UIKit Extension/
│   │   │   ├── UIColor+Extension.swift
│   │   │   ├── UILabel+Extension.swift
│   │   │   └── UIView.swift
│   │   ├── WebserviceHepler/
│   │   │   └── WebServiceHelper.swift
│   │   └── Metadata.swift
│   ├── Details Screen/
│   │   └── DetailsViewController.swift
│   ├── Media.xcassets/  (asset catalog — 0 image sets)
│   ├── Tags View/
│   │   ├── TagsModel.swift
│   │   └── TagsViewController.swift
│   ├── ActionModel.swift
│   ├── ActionViewController.swift
│   ├── Global.swift
│   ├── Info.plist
│   └── RentnKinExtension.entitlements
├── RentnKing/
│   ├── Assets.xcassets/  (asset catalog — 60 image sets)
│   ├── Base.lproj/
│   │   └── LaunchScreen.storyboard
│   ├── Colour.xcassets/  (asset catalog — 0 image sets)
│   ├── Core/
│   │   ├── CoreData/
│   │   │   ├── DataBase/
│   │   │   │   └── RentnKingDataBase.xcdatamodeld/  (1 files)
│   │   │   ├── CoreaDataModel.swift
│   │   │   ├── CoreDatabaseManager.swift
│   │   │   ├── CoreDatabaseManager.swift.zip
│   │   │   └── DownloadFile.swift
│   │   ├── FileData Helper/
│   │   │   ├── CategoryListFile.swift
│   │   │   ├── CheckListFile.swift
│   │   │   ├── CRMFile.swift
│   │   │   ├── EqupmentFile.swift
│   │   │   ├── kEnum.swift
│   │   │   ├── kScheduleOrderList.swift
│   │   │   ├── OrderDetailsFile.swift
│   │   │   ├── SDKUserDefault.swift
│   │   │   ├── SyncDeliveryPickupInputs.swift
│   │   │   ├── SyncDriverChecklist.swift
│   │   │   ├── SyncEquipment.swift
│   │   │   └── UpdateOrderNoteData.swift
│   │   ├── Font/
│   │   │   ├── HelveticaNeue.ttc
│   │   │   ├── Roboto-Black.ttf
│   │   │   ├── Roboto-Bold.ttf
│   │   │   ├── Roboto-Light.ttf
│   │   │   ├── Roboto-Medium.ttf
│   │   │   └── Roboto-Regular.ttf
│   │   ├── Frameworks/
│   │   │   ├── CLWaterWave/
│   │   │   │   ├── CLWaterWaveModel+Defaults.swift
│   │   │   │   ├── CLWaterWaveModel.swift
│   │   │   │   ├── CLWaterWaveModelDelegate.swift
│   │   │   │   └── CLWaterWaveView.swift
│   │   │   ├── Loding View/
│   │   │   │   ├── Coverable+UIKit.swift
│   │   │   │   ├── Coverable.swift
│   │   │   │   ├── LoadingPlaceholderView.swift
│   │   │   │   └── UIBezierPath.swift
│   │   │   ├── RHPlaceholderSource/
│   │   │   │   ├── Animations/
│   │   │   │   │   ├── Blink/
│   │   │   │   │   │   ├── BlinkAnimator.swift
│   │   │   │   │   │   ├── BlinkAnimatorConfigurable.swift
│   │   │   │   │   │   └── BlinkAnimatorConfiguration.swift
│   │   │   │   │   ├── Gradient/
│   │   │   │   │   │   ├── BackAndForthAnimation/
│   │   │   │   │   │   │   ├── BackAndForthLayerAnimatorGradient.swift
│   │   │   │   │   │   │   └── BackAndForthLayerAnimatorGradientConfiguration.swift
│   │   │   │   │   │   ├── Common/
│   │   │   │   │   │   │   ├── CAAnimationDelegateReceiver.swift
│   │   │   │   │   │   │   ├── LayerAnimatorGradientConfigurable.swift
│   │   │   │   │   │   │   └── LayerAnimatorGradientConfiguration.swift
│   │   │   │   │   │   ├── InstaAnimation/
│   │   │   │   │   │   │   ├── InstaLayerAnimatorGradient.swift
│   │   │   │   │   │   │   └── InstaLayerAnimatorGradientConfiguration.swift
│   │   │   │   │   │   └── RainbowAnimation/
│   │   │   │   │   │       ├── RainbowAnimatorGradient.swift
│   │   │   │   │   │       └── RainbowAnimatorGradientConfiguration.swift
│   │   │   │   │   └── Utils/
│   │   │   │   │       └── UIColor+HEX.swift
│   │   │   │   ├── LayerAnimating.swift
│   │   │   │   ├── Placeholder.swift
│   │   │   │   └── PlaceholderItem.swift
│   │   │   └── SpreadsheetView/
│   │   │       ├── Address.swift
│   │   │       ├── Array+BinarySearch.swift
│   │   │       ├── Borders.swift
│   │   │       ├── Cell.swift
│   │   │       ├── CellRange.swift
│   │   │       ├── CircularScrolling.swift
│   │   │       ├── Gridlines.swift
│   │   │       ├── IndexPath+Column.swift
│   │   │       ├── LayoutEngine.swift
│   │   │       ├── Location.swift
│   │   │       ├── ReuseQueue.swift
│   │   │       ├── ScrollPosition.swift
│   │   │       ├── ScrollView.swift
│   │   │       ├── SpreadsheetView+CirclularScrolling.swift
│   │   │       ├── SpreadsheetView+Layout.swift
│   │   │       ├── SpreadsheetView+Touches.swift
│   │   │       ├── SpreadsheetView+UIScrollView.swift
│   │   │       ├── SpreadsheetView+UIScrollViewDelegate.swift
│   │   │       ├── SpreadsheetView+UISnapshotting.swift
│   │   │       ├── SpreadsheetView+UIViewHierarchy.swift
│   │   │       ├── SpreadsheetView.h
│   │   │       ├── SpreadsheetView.swift
│   │   │       ├── SpreadsheetViewDataSource.swift
│   │   │       └── SpreadsheetViewDelegate.swift
│   │   ├── Google File/
│   │   │   ├── Live Key /
│   │   │   │   └── AuthKey_J9CRR5GHT3.p8
│   │   │   └── GoogleService-Info.plist
│   │   ├── Keychain/
│   │   │   ├── Keychain.swift
│   │   │   └── KeychainWrapper.swift
│   │   ├── Navigation/
│   │   │   ├── Navigation Bar/
│   │   │   │   ├── NavigationBar.swift
│   │   │   │   └── NavigationBar.xib
│   │   │   ├── NavigationController.swift
│   │   │   └── UIBarButtonItemWithClouser.swift
│   │   ├── Other Views/
│   │   │   ├── AlertPopUp/
│   │   │   │   ├── AlertPopUp.swift
│   │   │   │   └── AlertPopUp.xib
│   │   │   ├── CountryPicker/
│   │   │   │   ├── Controller/
│   │   │   │   │   └── CountryCodeViewController.swift
│   │   │   │   ├── Model/
│   │   │   │   │   ├── CountryPickerView.bundle/
│   │   │   │   │   │   ├── Data/
│   │   │   │   │   │   │   └── CountryCodes.json
│   │   │   │   │   │   └── Images/
│   │   │   │   │   │       ├── AC.png
│   │   │   │   │   │       ├── AD.png
│   │   │   │   │   │       ├── AE.png
│   │   │   │   │   │       ├── AF.png
│   │   │   │   │   │       ├── AG.png
│   │   │   │   │   │       ├── AI.png
│   │   │   │   │   │       ├── AL.png
│   │   │   │   │   │       ├── AM.png
│   │   │   │   │   │       ├── AO.png
│   │   │   │   │   │       ├── AQ.png
│   │   │   │   │   │       ├── AR.png
│   │   │   │   │   │       ├── AS.png
│   │   │   │   │   │       ├── AT.png
│   │   │   │   │   │       ├── AU.png
│   │   │   │   │   │       ├── AW.png
│   │   │   │   │   │       ├── AX.png
│   │   │   │   │   │       ├── AZ.png
│   │   │   │   │   │       ├── BA.png
│   │   │   │   │   │       ├── BB.png
│   │   │   │   │   │       ├── BD.png
│   │   │   │   │   │       ├── BE.png
│   │   │   │   │   │       ├── BF.png
│   │   │   │   │   │       ├── BG.png
│   │   │   │   │   │       ├── BH.png
│   │   │   │   │   │       ├── BI.png
│   │   │   │   │   │       ├── BJ.png
│   │   │   │   │   │       ├── BL.png
│   │   │   │   │   │       ├── BM.png
│   │   │   │   │   │       ├── BN.png
│   │   │   │   │   │       ├── BO.png
│   │   │   │   │   │       ├── BQ.png
│   │   │   │   │   │       ├── BR.png
│   │   │   │   │   │       ├── BS.png
│   │   │   │   │   │       ├── BT.png
│   │   │   │   │   │       ├── BV.png
│   │   │   │   │   │       ├── BW.png
│   │   │   │   │   │       ├── BY.png
│   │   │   │   │   │       ├── BZ.png
│   │   │   │   │   │       ├── CA.png
│   │   │   │   │   │       ├── CC.png
│   │   │   │   │   │       ├── CD.png
│   │   │   │   │   │       ├── CF.png
│   │   │   │   │   │       ├── CG.png
│   │   │   │   │   │       ├── CH.png
│   │   │   │   │   │       ├── CI.png
│   │   │   │   │   │       ├── CK.png
│   │   │   │   │   │       ├── CL.png
│   │   │   │   │   │       ├── CM.png
│   │   │   │   │   │       ├── CN.png
│   │   │   │   │   │       ├── CO.png
│   │   │   │   │   │       ├── CR.png
│   │   │   │   │   │       ├── CU.png
│   │   │   │   │   │       ├── CV.png
│   │   │   │   │   │       ├── CW.png
│   │   │   │   │   │       ├── CX.png
│   │   │   │   │   │       ├── CY.png
│   │   │   │   │   │       ├── CZ.png
│   │   │   │   │   │       ├── DE.png
│   │   │   │   │   │       ├── DJ.png
│   │   │   │   │   │       ├── DK.png
│   │   │   │   │   │       ├── DM.png
│   │   │   │   │   │       ├── DO.png
│   │   │   │   │   │       ├── DZ.png
│   │   │   │   │   │       ├── EC.png
│   │   │   │   │   │       ├── EE.png
│   │   │   │   │   │       ├── EG.png
│   │   │   │   │   │       ├── EH.png
│   │   │   │   │   │       ├── ER.png
│   │   │   │   │   │       ├── ES.png
│   │   │   │   │   │       ├── ET.png
│   │   │   │   │   │       ├── FI.png
│   │   │   │   │   │       ├── FJ.png
│   │   │   │   │   │       ├── FK.png
│   │   │   │   │   │       ├── FM.png
│   │   │   │   │   │       ├── FO.png
│   │   │   │   │   │       ├── FR.png
│   │   │   │   │   │       ├── FX.png
│   │   │   │   │   │       ├── GA.png
│   │   │   │   │   │       ├── GB.png
│   │   │   │   │   │       ├── GD.png
│   │   │   │   │   │       ├── GE.png
│   │   │   │   │   │       ├── GF.png
│   │   │   │   │   │       ├── GG.png
│   │   │   │   │   │       ├── GH.png
│   │   │   │   │   │       ├── GI.png
│   │   │   │   │   │       ├── GL.png
│   │   │   │   │   │       ├── GM.png
│   │   │   │   │   │       ├── GN.png
│   │   │   │   │   │       ├── GP.png
│   │   │   │   │   │       ├── GQ.png
│   │   │   │   │   │       ├── GR.png
│   │   │   │   │   │       ├── GS.png
│   │   │   │   │   │       ├── GT.png
│   │   │   │   │   │       ├── GU.png
│   │   │   │   │   │       ├── GW.png
│   │   │   │   │   │       ├── GY.png
│   │   │   │   │   │       ├── HK.png
│   │   │   │   │   │       ├── HM.png
│   │   │   │   │   │       ├── HN.png
│   │   │   │   │   │       ├── HR.png
│   │   │   │   │   │       ├── HT.png
│   │   │   │   │   │       ├── HU.png
│   │   │   │   │   │       ├── ID.png
│   │   │   │   │   │       ├── IE.png
│   │   │   │   │   │       ├── IL.png
│   │   │   │   │   │       ├── IM.png
│   │   │   │   │   │       ├── IN.png
│   │   │   │   │   │       ├── IO.png
│   │   │   │   │   │       ├── IQ.png
│   │   │   │   │   │       ├── IR.png
│   │   │   │   │   │       ├── IS.png
│   │   │   │   │   │       ├── IT.png
│   │   │   │   │   │       ├── JE.png
│   │   │   │   │   │       ├── JM.png
│   │   │   │   │   │       ├── JO.png
│   │   │   │   │   │       ├── JP.png
│   │   │   │   │   │       ├── KE.png
│   │   │   │   │   │       ├── KG.png
│   │   │   │   │   │       ├── KH.png
│   │   │   │   │   │       ├── KI.png
│   │   │   │   │   │       ├── KM.png
│   │   │   │   │   │       ├── KN.png
│   │   │   │   │   │       ├── KP.png
│   │   │   │   │   │       ├── KR.png
│   │   │   │   │   │       ├── KW.png
│   │   │   │   │   │       ├── KY.png
│   │   │   │   │   │       ├── KZ.png
│   │   │   │   │   │       ├── LA.png
│   │   │   │   │   │       ├── LB.png
│   │   │   │   │   │       ├── LC.png
│   │   │   │   │   │       ├── LI.png
│   │   │   │   │   │       ├── LK.png
│   │   │   │   │   │       ├── LR.png
│   │   │   │   │   │       ├── LS.png
│   │   │   │   │   │       ├── LT.png
│   │   │   │   │   │       ├── LU.png
│   │   │   │   │   │       ├── LV.png
│   │   │   │   │   │       ├── LY.png
│   │   │   │   │   │       ├── MA.png
│   │   │   │   │   │       ├── MC.png
│   │   │   │   │   │       ├── MD.png
│   │   │   │   │   │       ├── ME.png
│   │   │   │   │   │       ├── MF.png
│   │   │   │   │   │       ├── MG.png
│   │   │   │   │   │       ├── MH.png
│   │   │   │   │   │       ├── MK.png
│   │   │   │   │   │       ├── ML.png
│   │   │   │   │   │       ├── MM.png
│   │   │   │   │   │       ├── MN.png
│   │   │   │   │   │       ├── MO.png
│   │   │   │   │   │       ├── MP.png
│   │   │   │   │   │       ├── MQ.png
│   │   │   │   │   │       ├── MR.png
│   │   │   │   │   │       ├── MS.png
│   │   │   │   │   │       ├── MT.png
│   │   │   │   │   │       ├── MU.png
│   │   │   │   │   │       ├── MV.png
│   │   │   │   │   │       ├── MW.png
│   │   │   │   │   │       ├── MX.png
│   │   │   │   │   │       ├── MY.png
│   │   │   │   │   │       ├── MZ.png
│   │   │   │   │   │       ├── NA.png
│   │   │   │   │   │       ├── NC.png
│   │   │   │   │   │       ├── NE.png
│   │   │   │   │   │       ├── NF.png
│   │   │   │   │   │       ├── NG.png
│   │   │   │   │   │       ├── NI.png
│   │   │   │   │   │       ├── NL.png
│   │   │   │   │   │       ├── NO.png
│   │   │   │   │   │       ├── NP.png
│   │   │   │   │   │       ├── NR.png
│   │   │   │   │   │       ├── NU.png
│   │   │   │   │   │       ├── NZ.png
│   │   │   │   │   │       ├── OM.png
│   │   │   │   │   │       ├── PA.png
│   │   │   │   │   │       ├── PE.png
│   │   │   │   │   │       ├── PF.png
│   │   │   │   │   │       ├── PG.png
│   │   │   │   │   │       ├── PH.png
│   │   │   │   │   │       ├── PK.png
│   │   │   │   │   │       ├── PL.png
│   │   │   │   │   │       ├── PM.png
│   │   │   │   │   │       ├── PN.png
│   │   │   │   │   │       ├── PR.png
│   │   │   │   │   │       ├── PS.png
│   │   │   │   │   │       ├── PT.png
│   │   │   │   │   │       ├── PW.png
│   │   │   │   │   │       ├── PY.png
│   │   │   │   │   │       ├── QA.png
│   │   │   │   │   │       ├── RE.png
│   │   │   │   │   │       ├── RO.png
│   │   │   │   │   │       ├── RS.png
│   │   │   │   │   │       ├── RU.png
│   │   │   │   │   │       ├── RW.png
│   │   │   │   │   │       ├── SA.png
│   │   │   │   │   │       ├── SB.png
│   │   │   │   │   │       ├── SC.png
│   │   │   │   │   │       ├── SD.png
│   │   │   │   │   │       ├── SE.png
│   │   │   │   │   │       ├── SG.png
│   │   │   │   │   │       ├── SH.png
│   │   │   │   │   │       ├── SI.png
│   │   │   │   │   │       ├── SJ.png
│   │   │   │   │   │       ├── SK.png
│   │   │   │   │   │       ├── SL.png
│   │   │   │   │   │       ├── SM.png
│   │   │   │   │   │       ├── SN.png
│   │   │   │   │   │       ├── SO.png
│   │   │   │   │   │       ├── SR.png
│   │   │   │   │   │       ├── SS.png
│   │   │   │   │   │       ├── ST.png
│   │   │   │   │   │       ├── SV.png
│   │   │   │   │   │       ├── SX.png
│   │   │   │   │   │       ├── SY.png
│   │   │   │   │   │       ├── SZ.png
│   │   │   │   │   │       ├── TC.png
│   │   │   │   │   │       ├── TD.png
│   │   │   │   │   │       ├── TF.png
│   │   │   │   │   │       ├── TG.png
│   │   │   │   │   │       ├── TH.png
│   │   │   │   │   │       ├── TJ.png
│   │   │   │   │   │       ├── TK.png
│   │   │   │   │   │       ├── TL.png
│   │   │   │   │   │       ├── TM.png
│   │   │   │   │   │       ├── TN.png
│   │   │   │   │   │       ├── TO.png
│   │   │   │   │   │       ├── TR.png
│   │   │   │   │   │       ├── TT.png
│   │   │   │   │   │       ├── TV.png
│   │   │   │   │   │       ├── TW.png
│   │   │   │   │   │       ├── TZ.png
│   │   │   │   │   │       ├── UA.png
│   │   │   │   │   │       ├── UG.png
│   │   │   │   │   │       ├── UM.png
│   │   │   │   │   │       ├── US.png
│   │   │   │   │   │       ├── UY.png
│   │   │   │   │   │       ├── UZ.png
│   │   │   │   │   │       ├── VA.png
│   │   │   │   │   │       ├── VC.png
│   │   │   │   │   │       ├── VE.png
│   │   │   │   │   │       ├── VG.png
│   │   │   │   │   │       ├── VI.png
│   │   │   │   │   │       ├── VN.png
│   │   │   │   │   │       ├── VU.png
│   │   │   │   │   │       ├── WF.png
│   │   │   │   │   │       ├── WS.png
│   │   │   │   │   │       ├── XK.png
│   │   │   │   │   │       ├── YE.png
│   │   │   │   │   │       ├── YT.png
│   │   │   │   │   │       ├── YU.png
│   │   │   │   │   │       ├── ZA.png
│   │   │   │   │   │       ├── ZM.png
│   │   │   │   │   │       └── ZW.png
│   │   │   │   │   └── CountryCode.swift
│   │   │   │   └── View/
│   │   │   │       └── CountryPicker.storyboard
│   │   │   ├── CustomSwitch/
│   │   │   │   └── CustomSwitch.swift
│   │   │   ├── EmptyDataView/
│   │   │   │   ├── EmptyDataView.swift
│   │   │   │   └── EmptyDataView.xib
│   │   │   ├── Extension/
│   │   │   │   ├── Other Extension/
│   │   │   │   │   ├── StringNOhter+Extension.swift
│   │   │   │   │   └── UserDefault+Extension.swift
│   │   │   │   └── UIKit Extension/
│   │   │   │       ├── UIColor+Extension.swift
│   │   │   │       ├── UIImageView.swift
│   │   │   │       ├── UILabel+Extension.swift
│   │   │   │       └── UIView.swift
│   │   │   ├── Helper/
│   │   │   │   ├── WebserviceHepler/
│   │   │   │   │   └── WebServiceHelper.swift
│   │   │   │   ├── GetBandWidht.swift
│   │   │   │   ├── Metadata.swift
│   │   │   │   ├── UITextViewWithPlaceholder.swift
│   │   │   │   └── UserNotification.swift
│   │   │   └── XIB/
│   │   │       ├── Add Cart/
│   │   │       │   ├── AddToCartButton.swift
│   │   │       │   └── AddToCartButton.xib
│   │   │       └── Upload/
│   │   │           ├── UploadView.swift
│   │   │           └── UploadView.xib
│   │   ├── AppUpdateManager.swift
│   │   ├── CameraViewController.swift
│   │   ├── MTSlideToOpenView.swift
│   │   └── TextFile.swift
│   ├── Modules/
│   │   ├── SPLASH MODEL/
│   │   │   ├── Login Screen/
│   │   │   │   ├── InReviewViewController.swift
│   │   │   │   ├── LoginModel.swift
│   │   │   │   ├── LoginViewController.swift
│   │   │   │   └── SignupViewController.swift
│   │   │   └── Splash/
│   │   │       └── SplashViewController.swift
│   │   └── TABBAR/
│   │       ├── Equipment Model/
│   │       │   ├── MachineProfile/
│   │       │   │   ├── Machine Filter Screen/
│   │       │   │   │   └── MachineFilterViewController.swift
│   │       │   │   ├── MachineProfileModel.swift
│   │       │   │   └── MachineProfileViewController.swift
│   │       │   └── MachineProfile Details/
│   │       │       ├── Pages/
│   │       │       │   ├── Checklist/
│   │       │       │   │   └── ChecklistVC.swift
│   │       │       │   ├── Notes/
│   │       │       │   │   └── NotesVC.swift
│   │       │       │   ├── Parts List/
│   │       │       │   │   └── PartsListVC.swift
│   │       │       │   ├── Rantal Ready/
│   │       │       │   │   ├── RantalReadyModel.swift
│   │       │       │   │   └── RantalReadyVC.swift
│   │       │       │   ├── Service/
│   │       │       │   │   └── ServiceVC.swift
│   │       │       │   └── Rantal Ready.zip
│   │       │       ├── MachineDetailsViewController.swift
│   │       │       └── MachinePageViewController.swift
│   │       ├── Home Model/
│   │       │   ├── CRM Model/
│   │       │   │   └── CRM Listing/
│   │       │   │       ├── CRMListDetailViewController.swift
│   │       │   │       ├── CRMListModel.swift
│   │       │   │       └── CRMListViewController.swift
│   │       │   ├── Dispatch Model/
│   │       │   │   ├── AddDriverPopUp/
│   │       │   │   │   ├── AddDriverPopUp.swift
│   │       │   │   │   └── AddDriverPopUp.xib
│   │       │   │   ├── Assign Driver/
│   │       │   │   │   ├── AssignDriverModel.swift
│   │       │   │   │   └── AssignDriverViewController.swift
│   │       │   │   ├── Driver Checklist/
│   │       │   │   │   └── DriverChecklistViewController.swift
│   │       │   │   ├── Warning Checklist/
│   │       │   │   │   ├── WarningModel.swift
│   │       │   │   │   └── WarningViewController.swift
│   │       │   │   ├── DispatchListViewController.swift
│   │       │   │   └── DispatchModel.swift
│   │       │   ├── Order Model/
│   │       │   │   ├── Check List/
│   │       │   │   │   ├── SignatureView/
│   │       │   │   │   │   ├── EPExtensions.swift
│   │       │   │   │   │   ├── EPSignatureView.swift
│   │       │   │   │   │   ├── EPSignatureViewController.swift
│   │       │   │   │   │   └── EPSignatureViewController.xib
│   │       │   │   │   ├── CheckListModel.swift
│   │       │   │   │   ├── CheckListUpdateModel.swift
│   │       │   │   │   ├── CheckListUpdateViewController.swift
│   │       │   │   │   ├── CheckListViewController.swift
│   │       │   │   │   ├── EquipmentPicker.swift
│   │       │   │   │   └── viewSignature.swift
│   │       │   │   ├── Filter Screen/
│   │       │   │   │   └── FilterViewController.swift
│   │       │   │   ├── Image Upload/
│   │       │   │   │   ├── ImageUploadViewController.swift
│   │       │   │   │   ├── ImageVideoModel.swift
│   │       │   │   │   └── ImageView.swift
│   │       │   │   ├── License Upload/
│   │       │   │   │   ├── LicenseModel.swift
│   │       │   │   │   ├── LicenseTypeViewController.swift
│   │       │   │   │   └── LicenseUploadViewController.swift
│   │       │   │   ├── Machine Hours/
│   │       │   │   │   ├── MachineHoursModel.swift
│   │       │   │   │   └── MachineHoursViewController.swift
│   │       │   │   ├── Order Details/
│   │       │   │   │   ├── AddNote View/
│   │       │   │   │   │   ├── AddNoteView.swift
│   │       │   │   │   │   └── AddNoteView.xib
│   │       │   │   │   ├── Address View/
│   │       │   │   │   │   ├── AddressModel.swift
│   │       │   │   │   │   └── AddressViewController.swift
│   │       │   │   │   ├── Payment View/
│   │       │   │   │   │   ├── PaymentView.swift
│   │       │   │   │   │   └── PaymentView.xib
│   │       │   │   │   ├── NoteList.swift
│   │       │   │   │   ├── OrderDetailsModel.swift
│   │       │   │   │   └── OrderDetailsViewController.swift
│   │       │   │   ├── OrderListButtonAction.swift
│   │       │   │   ├── OrderListModel.swift
│   │       │   │   └── OrderListViewController.swift
│   │       │   ├── Place Order Model/
│   │       │   │   ├── Categories Model/
│   │       │   │   │   ├── CategoriesModel.swift
│   │       │   │   │   └── CategoriesViewController.swift
│   │       │   │   ├── CheckOut Model/
│   │       │   │   │   ├── Menu Popup/
│   │       │   │   │   │   └── MenuPopup.swift
│   │       │   │   │   ├── Checkout.swift
│   │       │   │   │   ├── CheckOutModel.swift
│   │       │   │   │   └── CheckOutViewController.swift
│   │       │   │   ├── Payment Model/
│   │       │   │   │   ├── OrderSuccessViewController.swift
│   │       │   │   │   ├── PaymentModel.swift
│   │       │   │   │   ├── PaymentViewController.swift
│   │       │   │   │   └── TermsAndConditionViewController.swift
│   │       │   │   ├── ProductDetails Model/
│   │       │   │   │   ├── ProductDetails.swift
│   │       │   │   │   └── ProductDetailsViewController.swift
│   │       │   │   └── ProductList Model/
│   │       │   │       ├── ProductList.swift
│   │       │   │       └── ProductListViewController.swift
│   │       │   ├── Queue Line Model/
│   │       │   │   ├── QueueLineModel.swift
│   │       │   │   ├── QueueLineStagePopup.swift
│   │       │   │   └── QueueLineViewController.swift
│   │       │   ├── Schedule Model/
│   │       │   │   └── Schedule List/
│   │       │   │       ├── ScheduleListModel.swift
│   │       │   │       └── ScheduleListViewController.swift
│   │       │   ├── Setting Model/
│   │       │   │   ├── AppReleaseModel.swift
│   │       │   │   └── SettingViewController.swift
│   │       │   ├── Time Clock Model/
│   │       │   │   └── Time Clock/
│   │       │   │       ├── ClockInViewController.swift
│   │       │   │       ├── TimeClockLockViewController.swift
│   │       │   │       ├── TimeClockModel.swift
│   │       │   │       └── TimeClockViewController.swift
│   │       │   ├── HomeModel.swift
│   │       │   └── HomeViewController.swift
│   │       └── TabbarViewController.swift
│   ├── Storyboard/
│   │   ├── Equipment.storyboard
│   │   ├── Home.storyboard
│   │   ├── Login.storyboard
│   │   ├── Order.storyboard
│   │   ├── Schedule.storyboard
│   │   ├── TabBar.storyboard
│   │   └── TimeClock.storyboard
│   ├── AppDelegate.swift
│   ├── BackgroundUploadManager.swift
│   ├── BackgroundURL.swift
│   ├── EventCalender.swift
│   ├── GlobalMain.swift
│   ├── Info.plist
│   ├── NotificaiotnFile.swift
│   ├── RentnKing.entitlements
│   └── UserModel.swift
├── RentnKing.xcodeproj/
│   ├── project.xcworkspace/
│   │   ├── xcshareddata/
│   │   │   ├── swiftpm/
│   │   │   │   ├── configuration/
│   │   │   │   └── Package.resolved
│   │   │   └── IDEWorkspaceChecks.plist
│   │   └── contents.xcworkspacedata
│   ├── xcshareddata/
│   │   └── xcschemes/
│   │       ├── RentnKinExtension.xcscheme
│   │       └── RentnKing.xcscheme
│   └── project.pbxproj
├── RentnKingTests/
│   ├── OfflineQueueModelTests.swift
│   ├── QueueLineModelTests.swift
│   └── README.md
├── .gitignore
├── APP_AUDIT_REPORT.md
└── PROJECT_OVERVIEW.md
```

_Generated from the working tree. See `PROJECT_OVERVIEW.md` for what each area does._
