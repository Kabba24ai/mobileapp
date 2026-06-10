//
//  EventCalender.swift
//  RentnKing
//
//  Created by Jigar Khatri on 02/03/24.
//

import Foundation
import EventKit
import UIKit




//MARK: - ADD CALENDER EVENT
extension AppDelegate {
    
    func eventAccess(){
        
        
        // 1
        let eventStore = EKEventStore()
        
        // 2
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized: break
        case .denied: break
        case .notDetermined:
            // 3
            if #available(iOS 17.0, *) {
                eventStore.requestFullAccessToEvents { Status, error in
                }
            } else {
                // Fallback on earlier versions
                eventStore.requestAccess(to: .event) { (granted, error) in
                }

            }
        default:
            print("Case default")
        }
    }

    
    func checkEventAccess() -> Bool{
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized:
            return true
        case .denied:
            return false
        
        default:
            print("Case default")
        }
        return false
    }
    
    func Event_Permission(){
        let alert = UIAlertController(title: "Calendar access is required to add this event.", message: "Open Settings -> SocrPro -> Calendars -> turn ON the switch.", preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: "Open Settings",style: UIAlertAction.Style.default, handler: {(_: UIAlertAction!) in
            
            //MOVE TO SETTING
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
            
        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.default, handler: { _ in
            //Cancel Action
        }))
        
        GlobalMainConstants.appDelegate?.window?.rootViewController?.present(alert, animated: true, completion: nil)
    }


//    func DepartureEvent(_ objData : ScheduleModal, isNew : Bool, completion: @escaping (_ isDone: Bool?) -> Void) {
//        let store = EKEventStore()
//        let event:EKEvent = EKEvent(eventStore: store)
//        let startTime = Util.changeDateFormate(fromFormat: timeFormatewithAmPm, toFormat: timeFormate, toDate: "\(objData.departure_time ?? "")")
//        let endTime = Util.changeDateFormate(fromFormat: timeFormatewithAmPm, toFormat: timeFormate, toDate: "\(objData.arrival_time ?? "")")
//
//        if startTime == "" || endTime == ""{
//            completion(true)
//            return
//        }
//
//        event.title = "\(objData.title ?? "") - Departure"
//        event.startDate = convertDateFormEventData(selectDate: "\(objData.edate ?? "") \(startTime)")
//        event.endDate = convertDateFormEventData(selectDate: "\(objData.edate ?? "") \(endTime)")
//        if objData.notes ?? "" != ""{
//            //NOTES
//            let htmlData = NSString(string: "\(objData.notes ?? "")").data(using: String.Encoding.unicode.rawValue)
//            let options = [NSAttributedString.DocumentReadingOptionKey.documentType:
//                NSAttributedString.DocumentType.html]
//            let attributedString = try? NSMutableAttributedString(data: htmlData ?? Data(),
//                                                                  options: options,
//                                                                  documentAttributes: nil)
//            event.notes = attributedString?.string
//        }
//        event.calendar = store.defaultCalendarForNewEvents
//
//
//        //ADD LOCATION
//        if objData.lat ?? "" != "" && objData.lng ?? "" != "" {
//            let lat = Double("\(objData.lat ?? "")") ?? 0.0
//            let lon = Double("\(objData.lng ?? "")") ?? 0.0
//            let location = CLLocation(latitude: lat, longitude: lon)
//            let structuredLocation = EKStructuredLocation(title: "\(objData.complexname ?? "")")  // same title with ekEvent.location
//            structuredLocation.geoLocation = location
//            event.structuredLocation = structuredLocation
//        }
//
//        // Set default alarm minutes before event
//        let alarm1hour = EKAlarm(relativeOffset: (-3600 * 5)) //1 hour
//        let alarm1day = EKAlarm(relativeOffset: -86400) //1 day
//        event.addAlarm(alarm1day)
//        event.addAlarm(alarm1hour)
//
//        do {
//            try store.save(event, span: .thisEvent, commit: true)
//            print("Saved event with ID: \(event.eventIdentifier ?? ""))")
//
//            //ADD EVENT IN TABLE
//            if isNew{
//                //UPDATE EVENT TABLE
//                let objEvent = EventDepartureModel(id: "\(objData.Id ?? "")", type: "Departure", event_id: "\(event.eventIdentifier ?? "")")
//                arrEventDepartureList.append(objEvent)
//                UserDefaults.standard.encode(for:arrEventDepartureList, using: String(describing: EventDepartureModel.self))
//
//
//                completion(true)
//
//            }
//            else{
//                completion(true)
//            }
//        } catch let error as NSError {
//            print(objData.edate ?? "")
//            print(startTime)
//            print(endTime)
//            print("failed to save event with error --> Departure : \(error)")
//            completion(true)
//        }
//    }
//
//    func ArrivalEvent(_ objData : ScheduleModal, isNew : Bool, completion: @escaping (_ isDone: Bool?) -> Void) {
//
//        let store = EKEventStore()
//
//        let event:EKEvent = EKEvent(eventStore: store)
//        let startTime = Util.changeDateFormate(fromFormat: timeFormatewithAmPm, toFormat: timeFormate, toDate: "\(objData.arrival_time ?? "")")
//        let endTime = Util.changeDateFormate(fromFormat: timeFormatewithAmPm, toFormat: timeFormate, toDate: "\(objData.start_time ?? "")")
//        if startTime == "" || endTime == ""{
//            completion(true)
//            return
//        }
//
//        event.title = "\(objData.title ?? "") - Arrival"
//        event.startDate = convertDateFormEventData(selectDate: "\(objData.edate ?? "") \(startTime)")
//        event.endDate = convertDateFormEventData(selectDate: "\(objData.edate ?? "") \(endTime)")
//
//        if objData.notes ?? "" != ""{
//            //NOTES
//            let htmlData = NSString(string: "\(objData.notes ?? "")").data(using: String.Encoding.unicode.rawValue)
//            let options = [NSAttributedString.DocumentReadingOptionKey.documentType:
//                NSAttributedString.DocumentType.html]
//            let attributedString = try? NSMutableAttributedString(data: htmlData ?? Data(),
//                                                                  options: options,
//                                                                  documentAttributes: nil)
//            event.notes = attributedString?.string
//        }
//
//        event.calendar = store.defaultCalendarForNewEvents
//
//        //ADD LOCATION
//        if objData.lat ?? "" != "" && objData.lng ?? "" != "" {
//            let lat = Double("\(objData.lat ?? "")") ?? 0.0
//            let lon = Double("\(objData.lng ?? "")") ?? 0.0
//            let location = CLLocation(latitude: lat, longitude: lon)
//            let structuredLocation = EKStructuredLocation(title: "\(objData.complexname ?? "")")  // same title with ekEvent.location
//            structuredLocation.geoLocation = location
//            event.structuredLocation = structuredLocation
//        }
//
//        // Set default alarm minutes before event
//        let alarm1hour = EKAlarm(relativeOffset: (-3600 * 5)) //1 hour
//        let alarm1day = EKAlarm(relativeOffset: -86400) //1 day
//        event.addAlarm(alarm1day)
//        event.addAlarm(alarm1hour)
//
//
//        do {
//            try store.save(event, span: .thisEvent, commit: true)
//            print("Saved event with ID: \(event.eventIdentifier ?? ""))")
//
//            if isNew{
//                //UPDATE EVENT TABLE
//                let objEvent = EventArrivalModel(id: "\(objData.Id ?? "")", type: "Arrival", event_id: "\(event.eventIdentifier ?? "")")
//                arrEventArrivalList.append(objEvent)
//                UserDefaults.standard.encode(for:arrEventArrivalList, using: String(describing: EventArrivalModel.self))
//
//            }
//            else{
//                completion(true)
//            }
//
//        } catch let error as NSError {
//            print(objData.edate ?? "")
//            print(startTime)
//            print(endTime)
//            print("failed to save event with error --> Arrival: \(error)")
//            completion(true)
//        }
//    }
//
//    func StartGameEvent(_ objData : ScheduleModal, isNew : Bool, completion: @escaping (_ isDone: Bool?) -> Void) {
//        print(objData.edate ?? "")
//
//        let store = EKEventStore()
//
//        let event:EKEvent = EKEvent(eventStore: store)
//        let startTime = Util.changeDateFormate(fromFormat: timeFormatewithAmPm, toFormat: timeFormate, toDate: "\(objData.start_time ?? "")")
//        let endTime = Util.changeDateFormate(fromFormat: timeFormatewithAmPm, toFormat: timeFormate, toDate: "\(objData.end_time ?? "")")
//        if startTime == "" || endTime == ""{
//            completion(true)
//            return
//        }
//
//        event.title = "\(objData.title ?? "") - Start"
//        event.startDate = convertDateFormEventData(selectDate: "\(objData.edate ?? "") \(startTime)")
//        event.endDate = convertDateFormEventData(selectDate: "\(objData.edate ?? "") \(endTime)")
//        if objData.notes ?? "" != ""{
//            //NOTES
//            let htmlData = NSString(string: "\(objData.notes ?? "")").data(using: String.Encoding.unicode.rawValue)
//            let options = [NSAttributedString.DocumentReadingOptionKey.documentType:
//                NSAttributedString.DocumentType.html]
//            let attributedString = try? NSMutableAttributedString(data: htmlData ?? Data(),
//                                                                  options: options,
//                                                                  documentAttributes: nil)
//            event.notes = attributedString?.string
//        }
//        event.calendar = store.defaultCalendarForNewEvents
//        event.calendar.title = "\(GlobalConstants.appName)"
//        event.calendar.cgColor = hexStringToUIColor(hex: GlobalConstants.APPCOLOUR_BLUE).cgColor
//
//
//        //ADD LOCATION
//        if objData.lat ?? "" != "" && objData.lng ?? "" != "" {
//            let lat = Double("\(objData.lat ?? "")") ?? 0.0
//            let lon = Double("\(objData.lng ?? "")") ?? 0.0
//            let location = CLLocation(latitude: lat, longitude: lon)
//            let structuredLocation = EKStructuredLocation(title: "\(objData.complexname ?? "")")  // same title with ekEvent.location
//            structuredLocation.geoLocation = location
//            event.structuredLocation = structuredLocation
//        }
//
//        // Set default alarm minutes before event
//        let alarm1hour = EKAlarm(relativeOffset: (-3600 * 5)) //1 hour
//        let alarm1day = EKAlarm(relativeOffset: -86400) //1 day
//        event.addAlarm(alarm1day)
//        event.addAlarm(alarm1hour)
//
//        do {
//            try store.save(event, span: .thisEvent, commit: true)
//            print("Saved event with ID: \(event.eventIdentifier ?? ""))")
//
//            //UPDATE EVENT TABLE
//            if isNew{
//                //UPDATE EVENT TABLE
//                let objEvent = EventGameStartModel(id: "\(objData.Id ?? "")", type: "Start", event_id: "\(event.eventIdentifier ?? "")")
//                arrEventStartList.append(objEvent)
//                UserDefaults.standard.encode(for:arrEventStartList, using: String(describing: EventGameStartModel.self))
//            }
//            else{
//                completion(true)
//            }
//
//        } catch let error as NSError {
//            print(objData.edate ?? "")
//            print(startTime)
//            print(endTime)
//            print("failed to save event with error --> Start: \(error)")
//            self.SetTheCalenderGameStartEvent()
//
//        }
//    }
//
//    func removeCalender(_ eventId : String, completion: @escaping (_ isDone: Bool?) -> Void) {
//        let store = EKEventStore()
//
//        let eventToRemove = store.event(withIdentifier: eventId)
//        if eventToRemove != nil {
//            do {
//                try store.remove(eventToRemove!, span: .thisEvent, commit: true)
//                print("Remove Event")
//                completion(true)
//            } catch {
//                // Display error to user
//                completion(false)
//            }
//        }
//        completion(false)
//    }
}
