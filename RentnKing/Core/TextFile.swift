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
    var strDispatch = "Dispatch".localized()
    var strInStore = "Queue Line".localized()
    var strTimeClock = "Time Clock".localized()
    var strInventory = "Inventory".localized()
    var strMachineProfile = "Machine Profile".localized()
    
    //CUSTOMER
    var strCustomer = "Customer".localized()
    var strCustomerDetails = "Details".localized()
    var strAccount = "Account:".localized()
    var strCompanyName = "Company Name".localized()
    var strContactInfo = "Contact Information".localized()
    var strEmailAddress = "Email Address".localized()
    var strCompanyWebsite = "Company Website".localized()
    var strPersonalPhone = "Personal Phone".localized()
    var strCompanyPhone = "Company Phone".localized()
    var strAddressInfo = "Address Information".localized()
    var strBillingAddress = "Billing Address".localized()
    var strDeliveryAddress = "Delivery Address".localized()
    
    var strTags = "Tags".localized()
    var strNotes = "Notes".localized()
    var strNoNoteAvailable = "No Notes Available".localized()
    
    
    
    
    
    
    
    
    
    
    //MACHINE PROFILE
    var strNoteGeneral = "Note - General".localized()
    var strRentalReady = "Rental Ready".localized()
    var strCheckList = "Checklist".localized()
    var strPartsList = "Parts List".localized()
    var strService = "Service".localized()

    var strNoRentalReadyData = "Please add a Rental Ready Checklist to this machine.".localized()
    var strUpdated = "Last Updated".localized()
    var strMachineHours = "Machine Hours".localized()
    var strTechMgt = "Tech / Mgt".localized()
    var strSelectTechMgt = "Select Tech / Mgmt.".localized()
    var strChecklistItem = "Checklist Items".localized()

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
    var strSelectMemberID = "Enter ID".localized()
    
    var strUpdateStatus = "Update Status".localized()
    var strChangeStatus = "Change Status".localized()

    
    //PRODUCT
    var soldOut = "Sold Out".localized()
    var strSelectData = "Select Date".localized()
    var productOptions = "Product Options".localized()
    var addCart = "Add to Cart".localized()
    var strRemoveOptions = "No Thanks, I'll Take The Risk".localized()
    var deliveryOptions = "Delivery Options".localized()
    var wantToDelivery = "I Want Delivery".localized()
    var willPickup = "I'll Pick It Up".localized()
    var strChargeTax = "Charge Sales Tax".localized()
    var strTaxFree = "Tax Free".localized()

    var errorSelectDate = "Please select a date.".localized()
    var errorSelectPickup = "Please select pickup.".localized()
    var errorSelectDelivery = "Please select delivery.".localized()
    var errorSelectPickupDelivery = "Please select pickup and delivery.".localized()
    var errorSelectStoreLocation = "Please select a store location.".localized()

    //CHECK OUT
    var strCheckOut = "Check Out".localized()
    
    var sttScheduleDate = "Date:".localized()
    var strPrice = "Product Cost".localized()
    var strOptionsTotal = "Options:".localized()
    var strDistance = "Distance Range:".localized()

    var strRemove = "Remove".localized()
    var strUpdate = "Update".localized()
    var strNext = "Preview".localized()

    var strSubtotal = "Subtotal".localized()
    var strTax = "Tax".localized()
    var strTotalAmount = "Total".localized()

    var strCustomValue = "Add Custom Value".localized()
    var strEnterValue = "Enter Amount".localized()
    var strCustomAmount = "Custom Amount".localized()

    
    //PAYMENT
    var strPaymentTitle = "Payment".localized()
    
    var BillingInfo = "Billing Information".localized()
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
    var strPayCard = "Pay Using Credit or Debit Card".localized()
    var strCOD = "Cash on Delivery (COD)".localized()
    var codMessage = "COD orders are not reserved or locked in until payment is received. To secure your order, please pay by credit card or call sales.".localized()
    
    var strSelectState = "Select State".localized()

    var DeliveryInfo = "Delivery Information".localized()
    var sameAsBilling = "Same as Billing Information".localized()

    
    var enterFirstName = "Enter first name".localized()
    var enterLastName = "Enter last name".localized()
    var enterEamil = "Enter email".localized()
    var enterPhone = "Enter phone".localized()
    var enterAddress = "Enter address".localized()
    var selectState = "Select State".localized()
    var selectUser = "Select User".localized()
    var enterCity = "Enter city".localized()
    var enterZipCode = "Enter zip code".localized()
    var enterOrderNote = "Notes about your order, e.g. special notes for delivery".localized()
    

    var strCreditCard = "Card Number".localized()
    var strMonth = "MM".localized()
    var strYear = "YY".localized()
    var strCVC = "CVC".localized()

    //PROCESS PAYMENT POPUP
    var strProcessPayment = "Process Payment".localized()
    var strBalanceDue = "Balance Due".localized()
    var strPaymentMethod = "Payment Method".localized()
    var strSelectPaymentMethod = "Select Payment Method".localized()
    var strCheckNumber = "Check Number".localized()
    var strEnterCheckNumber = "Enter Check Number".localized()
    var strPersonResponsible = "Person Responsible".localized()
    var strSelectPersonResponsible = "Select Person Responsible".localized()
    var strNotesOptional = "Notes".localized()
    var strPay = "Pay".localized()

    // Payment method options
    var strPayMethodCreditDebit = "Credit / Debit Card".localized()
    var strPayMethodCash = "Cash".localized()
    var strPayMethodCheck = "Check".localized()
    var strPayMethodBankTransfer = "Bank Transfer".localized()
    var strPayMethodOther = "Other".localized()

    // Payment validation messages
    var errSelectPaymentMethod = "Please select a payment method.".localized()
    var errEnterFirstName = "Please enter the payment first name.".localized()
    var errEnterLastName = "Please enter the payment last name.".localized()
    var errEnterCardNumber = "Please enter the card number.".localized()
    var errValidCardNumber = "Please enter a valid card number.".localized()
    var errSelectMonth = "Please select a month.".localized()
    var errSelectYear = "Please select a year.".localized()
    var errEnterCVC = "Please enter the CVC.".localized()
    var errSelectPerson = "Please select the responsible person.".localized()
    var errenterCheck = "Please enter the check number.".localized()

    
    
    //ORDER
    var strOderTitle = "ORDERS".localized()
    var strLinces = "License".localized()
    var strUploadLicense = "Upload License".localized()
    var strTerms = "T&C".localized()
    var strHoursStart = "Start".localized()
    var strHoursEnd = "End".localized()
    var strCheckListDeliv = "CheckList Deliv".localized()
    var strCheckListRet = "CheckList Ret".localized()
    var strPhotoAndVideoDeli = "Photo/Video Deliv".localized()
    var strPhotoAndVideoRec = "Photo/Video Ret".localized()
    var strDeliveyStatus = "Deliv ".localized()
    var strPickupStatus = "Ret ".localized()
    var strSearch = "Search".localized()
    var strSearchEqupment = "Search by equipment ID or name".localized()
    
    var strEquipIDSearch = "By Equip ID".localized()
    var strSelectStore = "All Stores".localized()
    var strCurrentlyAssigned = "Currently Assigned".localized()
    var strOrderIDSearch = "Order ID".localized()
    var strSearchProduct = "Search Products".localized()
    var strDeliveryNote = "Order / Delivery Instructions".localized()
    var strAddNote = "Add Note".localized()
    var strAddNoteBtn = "Add Note".localized()
    var strUser = "User".localized()

    
    
    var strSubmit = "Submit".localized()
    var strSubmitOnly = "Submit Only".localized()
    var strSubmitAutoInjection = "Submit + Enable Auto Injection".localized()
    var strRemoveChecklist = "Remove Checklist".localized()
    var strFrontImage = "Front Side of License".localized()
    var strBackImage = "Back Side of License".localized()
    var strUploadFrontImage = "Upload Front of License".localized()
    var strUploadBackImage = "Upload Back of License".localized()
    var strLicenseBottomText = "How should this license be saved?".localized()
    var strLicenseTypeTopText = "Enter the license expiration date to enable License Auto Injection for future orders.".localized()

    var strUplodFirst = "Tap to upload the front of your license".localized()
    var strUplodSecod = "Tap to upload the back of your license".localized()
    var notSupportCamera = "Your device doesn't support the camera.".localized()

    //MACHINE HOURSE
    var strStartHourse = "Start Hours".localized()
    var strAllocatedHourse = "Allocated Hours".localized()
    var strEndtHourse = "End Hours".localized()
    var strTotalHourse = "Total Hours".localized()
    var strAdditionalHourse = "Prorated Additional Hours".localized()
    var strHourseFee = "Prorated Hourly Fee".localized()
    var strTotalCharge = "Total Charge".localized()

    //CHECK LIST
    var strDelivered = "Delivered".localized()
    var strReturned = "Returned".localized()
    var strBalance = "Balance".localized()
    var strValue = "Value".localized()
    var strCustomerOwes = "Customer Owes".localized()
    var strTotalCheckList = "Total Charge".localized()

    var strDelivredNote = "Delivery Note".localized()
    var strReturnedNote = "Return Note".localized()
    var deliveryNote = "Enter delivery note".localized()
    var returenNote = "Enter return note".localized()

    var strDelivredEmployess = "Delivered By".localized()
    var strReturnedEmployess = "Returned By".localized()
    var strSelectEmployess = "Select Employee".localized()
    var strReturnedLocation = "Returned Location".localized()
    var strSelectLocation = "Select Location".localized()

    
    
    //ORDER DETAILS
    var strProductList = "Product List".localized()
    var SubAmount = "Subtotal".localized()
    var TotalAmount = "Total Amount".localized()
    var paymentStatus = "Payment Status".localized()
    var COD = "".localized()
    var strSubAmount = "".localized()

    //SCHEDULE
    var strScheduleTitle = "Schedule".localized()
    var strDelivery = "Delivery".localized()
    var strPickup = "Return".localized()

    var strPending = "Pending".localized()
    var strCompleted = "Completed".localized()

    
    var strDispatchTitle = "Dispatch".localized()

    //NO INTERNET
    var noNetTitle = "No Internet Connection".localized()
    var noNetTitle2 = "Please check your network connection and try again.".localized()
    var strRetry = "Retry".localized()
    var yes = "Yes".localized()
    var no = "No".localized()
    
    //OTHERS
    var somethingWentWrong = "Operational Error".localized()
    var invalidRequestParamater = "Invalid request parameter".localized()
    
    var moveToOrder = "Move To Order".localized()

    
    //Driver CheckList
    var strDriverCheckListTitle = "Driver Checklist\nPerform Before Leaving".localized()
    var strCallCustomer = "1. Call Customer".localized()
    var strDoubleCheck = "2. Double Check Equipment Fuel".localized()
    var strKeys = "3. Keys".localized()
    var strReadyToGo = "Load Map & Go".localized()
    var strSelectEquipmentFuel = "Select Equipment Fuel".localized()
    var strSelectKeys = "Select Keys".localized()
    
}
