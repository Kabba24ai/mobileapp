//
//  WarningModel.swift
//  RentnKing
//
//  Driver Override – delivery exception reasons shown on the Warning screen.
//

import Foundation

/// The four delivery-exception categories shown on the Warning screen,
/// each with its own list of selectable reasons.
enum DeliveryExceptionCategory: Int, CaseIterable {
    case termsAndConditions
    case driverLicense
    case photosVideo
    case checklist

    /// Section heading / picker title, prefixed with "Delivery" or "Return" by type.
    func title(isReturn: Bool) -> String {
        let prefix = isReturn ? "Return" : "Delivery"
        switch self {
        case .termsAndConditions: return "Terms & Conditions Not Completed"
        case .driverLicense:      return "\(prefix) License Not Uploaded"
        case .photosVideo:        return "\(prefix) Photos / Video Not Uploaded"
        case .checklist:          return "\(prefix) Checklist Not Completed"
        }
    }

    /// Selectable exception reasons for this category.
    var reasons: [String] {
        switch self {
        case .termsAndConditions:
            return [
                "Unsafe Delivery Location / Safety Concern",
                "Customer Not Present",
                "Customer Refused To Sign",
                "No Internet / Cellular Service",
                "Customer Representative Not Authorized To Sign",
                "Emergency Delivery Authorized By Management",
                "System Error / App Failure",
                "Other (Requires Notes)"
            ]
        case .driverLicense:
            return [
                "Unsafe Delivery Location / Safety Concern",
                "Customer Not Present",
                "Customer Refused To Provide License",
                "No Internet / Cellular Service",
                "Camera Failure / Device Issue",
                "Emergency Delivery Authorized By Management",
                "System Error / App Failure",
                "Other (Requires Notes)"
            ]
        case .photosVideo:
            return [
                "Unsafe Delivery Location / Safety Concern",
                "Photos/Video Captured - Upload Pending",
                "Camera Failure / Device Issue",
                "Emergency Delivery Authorized By Management",
                "Other (Requires Notes)"
            ]
        case .checklist:
            return [
                "Unsafe Delivery Location / Safety Concern",
                "No Internet / Cellular Service",
                "Checklist Items Photographed",
                "Emergency Delivery Authorized By Management",
                "System Error / App Failure"
            ]
        }
    }

    /// Whether the given reason requires the driver to enter a note.
    func requiresNote(for reason: String) -> Bool {
        return reason.lowercased().contains("other")
    }
}

/// Captures the driver's override selection for one category.
struct DeliveryExceptionSelection {
    let category: DeliveryExceptionCategory
    var reason: String?
    var note: String?
}
