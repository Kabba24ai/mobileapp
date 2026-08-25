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
    case kDispatchJobList   = "kDispatchJobList"
    case kQueueLineList     = "kQueueLineList"
    case kEmployesList = "EmployesList"
    case kEquipmentList = "EquipmentList"
    case kERentalReadyList = "EquipmentList_Rental_Ready"
    case kOrderDetailUserData = "OrderDetailUserData"
    case kOrderDetailData = "kOrderDetailData"
    case kTermsConditionData = "kTermsConditionData"
    case kOrderNoteData = "kOrderNoteData"
    case kOrderDetailsData = "kOrderDetailsData"
    case kStoreList = "kStoreList"
    case kEquipmentSubmit = "kEquipmentSubmit"
    case kCheckListOrderDetailsData = "kCheckListOrderDetailsData"
    case kCheckListOtherData = "kCheckListOtherData"
    case kCustomerList = "CustomerList"
    case kCustomerTagList = "CustomerTagList"

    //CHECK LIST
    case kSaveCheckList = "CheckList"

    // Local-only "Pending / prepared" delivery checklist (staged before the customer arrives).
    // Deliberately separate from kCheckListOrderDetailsData/kCheckListOtherData (which mean
    // "completed") and from kSaveCheckList (the final-upload queue).
    case kPendingCheckList = "kPendingCheckList"
    case kPendingCheckListOther = "kPendingCheckListOther"

    case kPriceList = "kPriceList"
    case kProductSettings = "kProductSettings"
    case kDriverChecklistSubmit = "kDriverChecklistSubmit"
    case kDeliveryPickupInputsSubmit = "kDeliveryPickupInputsSubmit"

}


enum kOrderStatusType: String {
    case knone = ""
    case kPending = "pending"
    case kAdd = "add"
    case kEdit = "edit"
    case kDelete = "delete"
}

enum kDriverCheckListStatus: String {
    case knone = ""
    case kReadytoGo = "Ready to Go"
    case kOnMyWay = "On the Way"
    case kArrived = "Arrived"
}
