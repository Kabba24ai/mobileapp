//
//  kEnum.swift
//  RentnKing
//
//  Created by DEEPAK JAIN on 03/10/25.
//

enum kFileStorageName: String {
    case knone = ""
    case kCateoryList = "CateoryList"
    case kOrderList = "OrderList"
    case kScheduleOrderList = "kScheduleOrderList"
    case kEmployesList = "EmployesList"
    case kEquipmentList = "EquipmentList"
    case kOrderDetailUserData = "OrderDetailUserData"
    case kOrderDetailData = "kOrderDetailData"
    case kTermsConditionData = "kTermsConditionData"
    case kOrderNoteData = "kOrderNoteData"
    case kOrderDetailsData = "kOrderDetailsData"
    case kStoreList = "kStoreList"
    case kEquipmentSubmit = "kEquipmentSubmit"

    //CHECK LIST
    case kSaveCheckList = "CheckList"

    case kPriceList = "kPriceList"

}


enum kOrderStatusType: String {
    case knone = ""
    case kPending = "pending"
    case kAdd = "add"
    case kEdit = "edit"
    case kDelete = "delete"
}
