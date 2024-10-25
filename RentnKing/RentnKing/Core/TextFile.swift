//
//  TextFile.swift
//  User
//
//  Created by jigar on 11/01/21.
//

import Foundation
func languageChangeNotification(){
    str = Text()
    NotificationCenter.default.post(name: .languageUpdate, object: nil, userInfo: nil)
}

var str = Text()

 

struct Text {
    var appName  = "RentnKing".localized()
    var VERSION = "VERSION".localized()
    var appLoading = "Loading...".localized()
    
    //OTHER TEXT
    var ok = "Ok".localized()
    var streSelect = "Select".localized()
    var cancel = "Cancel".localized()

    //TABBAR
    var home = "Home".localized()
    var setting = "Settings".localized()
    
    //HOME
    var strEcommerce = "Ecommerce".localized()
    var strSchedule = "Schedule".localized()
    var strEquipment = "Equipment".localized()
    var strCRM = "CRM".localized()
    var strTimeClock = "Time Clock".localized()

    //CATEGORY
    var strCategorie = "Categories".localized()
    var strOrders = "Orders".localized()
    var strProducts = "Products".localized()
    var strReserveNow = "Reserve Now / Learn More".localized()
    
    
    //TIME CLOCK
    var strMasterCode = "Admin / Access Code".localized()
    var strMasterCodeText = "Please enter".localized()
    var strTeamName = "Team Member Name".localized()
    var strSelectTeamName = "Select name".localized()
    
    var strMemberID = "Member ID".localized()
    var strSelectMemberID = "Enter id".localized()
    
    var strUpdateStatus = "Update Status".localized()
    var strChangeStatus = "Change Status".localized()

    
    //PRODUCT
    var soldOut = "Sold Out".localized()
    var strSelectData = "Select Date".localized()
    var productOptions = "Product Options".localized()
    var addCart = "ADD TO CART".localized()
    var strRemoveOptions = "No Thanks, I'll Take The Risk".localized()
    var deliveryOptions = "Delivery Options".localized()
    var wantToDelivery = "I Want Delivery".localized()
    var willPickup = "I'll Picku it Up".localized()
    var strChargeTax = "Charge Sales Tax".localized()
    var strTaxFree = "Tax Free".localized()

    var errorSelectDate = "Please Select Date".localized()
    var errorSelectPickup = "Please Select Pickup".localized()
    var errorSelectDelivery = "Please Select Delivevery".localized()
    var errorSelectPickupDelivery = "Please Select pickup and delivery".localized()
    var errorSelectStoreLocation = "Please Select store location".localized()

    //CHECK OUT
    var strCheckOut = "Check Out".localized()
    
    var sttScheduleDate = "Schedule Date :".localized()
    var strPrice = "Price :".localized()
    var strOptionsTotal = "Options Total :".localized()
    
    var strRemove = "Remove".localized()
    var strUpdate = "Update".localized()

    var strSubtotal = "Subtotal".localized()
    var strTax = "Tax".localized()
    var strTotalAmount = "Total".localized()

    var strCustomValue = "Add Custom Value".localized()
    var strEnterValue = "Enter amout".localized()
    var strCustomAmount = "Custom Amount".localized()

    
    //PAYMENT
    var strPaymentTitle = "Payment".localized()
    
    var BillingInfo = "Billing information".localized()
    var strFirstName = "First Name".localized()
    var strLastName = "Last Name".localized()
    var strPhone = "Phone".localized()
    var strEmail = "Email".localized()
    var strAddress = "Address".localized()
    var strState = "State".localized()
    var strCity = "City".localized()
    var strZipCode = "Zip Code".localized()
    var strOrderNote = "Order Notes".localized()
    var strPaymentMothod = "Payment Method".localized()
    var strPayCard = "Pay Using Credit or Debit".localized()
    var strCOD = "Cash on delivery (COD)".localized()
    var codMessage = "COD Orders are not reserved  / locked in until paid. If you want to lock in your order, please pay using a credit card or call sales.".localized()
    
    var strSelectState = "Select State".localized()

    var DeliveryInfo = "Delivery information".localized()
    var sameAsBilling = "Same as billing information".localized()

    
    var enterFirstName = "Enter first name".localized()
    var enterLastName = "Enter last name".localized()
    var enterEamil = "Enter email".localized()
    var enterPhone = "Enter phone".localized()
    var enterAddress = "Enter address".localized()
    var selectState = "Select State".localized()
    var enterCity = "Enter city".localized()
    var enterZipCode = "Enter zip code".localized()
    var enterOrderNote = "Notes about your order, e.g. special notes for delivery".localized()
    

    var strCreditCard = "Card Number".localized()
    var strMonth = "MM".localized()
    var strYear = "YY".localized()
    var strCVC = "CVC".localized()

    
    
    //ORDER
    var strOderTitle = "ORDERS".localized()
    var strLinces = "License".localized()
    var strTerms = "T&C".localized()
    var strHoursStart = "Start".localized()
    var strHoursEnd = "End".localized()
    var strCheckList = "CheckList".localized()
    var strPhotoAndVideo = "Photo/Video".localized()
    var strDeliveyStatus = "Deliv ".localized()
    var strPickupStatus = "Ret ".localized()
    var strSearch = "Search".localized()
    var strSearchProduct = "Search Product".localized()

    
    
    var strSubmit = "Submit".localized()
    var strUplodFirst = "Click to upload license front".localized()
    var strUplodSecod = "Click to upload license back".localized()
    var notSupportCamera = "Your device don’t support camera.".localized()

    //MACHINE HOURSE
    var strStartHourse = "Start Hours".localized()
    var strAllocatedHourse = "Hours Allocated".localized()
    var strEndtHourse = "End Hours".localized()
    var strTotalHourse = "Total Hours".localized()
    var strAdditionalHourse = "Additional Hours Prorated".localized()
    var strHourseFee = "Prorated Hourly Fee".localized()
    var strTotalCharge = "Total Charge".localized()

    //CHECK LIST
    var strDelivered = "Delivered".localized()
    var strReturned = "Returned".localized()
    var strBalance = "Balance".localized()
    var strValue = "Value".localized()
    var strCustomerOwes = "Customer Owes".localized()
    var strTotalCheckList = "Total Charge".localized()

    
    
    //ORDER DETAILS
    var strProductList = "Product List".localized()
    var SubAmount = "Sub amount".localized()
    var TotalAmount = "Total amount".localized()
    var paymentStatus = "Payment Status".localized()
    var COD = "".localized()
    var strSubAmount = "".localized()

    //SCHEDULE
    var strScheduleTitle = "Schedule".localized()
    var strDelivery = "Delivery".localized()
    var strPickup = "Pickup".localized()

    var strPending = "Pending".localized()
    var strCompleted = "Completed".localized()

    
    //NO INTERNET
    var noNetTitle = "No Internet".localized()
    var noNetTitle2 = "Please check your network connectivity and try again".localized()
    var strRetry = "Retry".localized()
    var yes = "Yes".localized()
    var no = "No".localized()
    
    //OTHERS
    var somethingWentWrong = "Something went wrong!".localized()
    var invalidRequestParamater = "Invalid request parameter".localized()

    
}
