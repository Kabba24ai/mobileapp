//
//  AppReleaseModel.swift
//  RentnKing
//
//  Release-notes model + provider. The newest release derives its version and
//  date automatically from the app bundle / build, so bumping the build in
//  Xcode is enough — no manual edits to the version or date here.
//

import Foundation

/// One release entry shown in Settings → About / Full Archive.
struct AppRelease {
    let version: String
    let date: String
    let notes: [String]
}

/// Central source of app version + release notes.
enum AppReleaseInfo {

    /// Marketing version from the bundle, e.g. "1.0.7".
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Build number from the bundle, e.g. "1001".
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    /// "1.0.7 (1001)" — shown next to "Version:".
    static var versionDisplay: String { "\(version) (\(build))" }

    /// The date the app binary was built, formatted "Fri - July 24 - 2026".
    static var buildDate: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEE - MMMM d - yyyy"
        return fmt.string(from: buildDateRaw ?? Date())
    }

    /// Build timestamp, read from the compiled Info.plist's modification date.
    private static var buildDateRaw: Date? {
        guard let infoPath = Bundle.main.path(forResource: "Info", ofType: "plist"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: infoPath),
              let date = attrs[.modificationDate] as? Date else { return nil }
        return date
    }

    /// All releases, NEWEST FIRST.
    /// The newest entry uses the automatic version + build date; add older
    /// releases below it with their historical (hardcoded) version and date.
    static let all: [AppRelease] = [
        AppRelease(version: "1.0.16", date: "Fri - Aug 21 - 2026", notes: [
            "Prepare a delivery before the customer arrives: complete the checklist, tap Save, then add delivery photos/video",
            "Mark as Staged now opens the Delivery Checklist automatically",
            "Reopening a prepared checklist restores all saved answers, ready for the customer's review and signature",
            "Clearer message when equipment can't be staged yet (e.g. fuel not full)",
            "More reliable checklist sync so completed checklists always upload",
            "Various fixes and refinements",
        ]),

        AppRelease(version: "1.0.15", date: "Mon - Aug 17 - 2026", notes: [
            "Driver Checklist: added a Call Customer toggle — the call steps are skipped when the customer already has the equipment",
            "Checklist now shows the correct questions for delivery and return separately",
            "Various fixes and refinements",
        ]),

        AppRelease(version: "1.0.12", date: "Tue - Aug 11 - 2026", notes: [
            "Queue Line: added “Change Equipment” to switch a unit for an order, with a reason and confirmation",
            "Automatically selects the default category when changing equipment in the Queue Line and Checklist",
            "Improved the checklist delivery and return flow",
            "Updated the Dispatch screen colours to clearly differentiate Delivery and Return",
            "Added an option to change equipment during the checklist process, with UI corrections",
            "Driver Checklist: fuel and key options appear only when the equipment has them",
            "Various fixes and refinements",
        ]),

        AppRelease(version: "1.0.10", date: "Tue - Aug 4 - 2026", notes: [
            "Updated the checklist logic to ensure both delivery and return are completed.",
            "Added the cleaning process and related calculations to the checklist.",
            "Cleared the default “Add Note” text when the user starts typing.",
            "Implemented various fixes and refinements.",
        ]),
        
        AppRelease(version: "1.0.9", date: "Fri - July 31 - 2026", notes: [
            "Storage is freed automatically once an order's delivery and return are both complete",
            "Dispatch: the delivery/return button turns green once the driver completes their checklist",
            "Updated the driver checklist fuel and key options",
            "Queue Line shows a loading placeholder while it opens",
            "Checklist items now appear in a consistent order",
            "Various fixes and refinements",
        ]),
        AppRelease(version: "1.0.8", date: "Wed - July 29 - 2026", notes: [
            "Queue Line and Equipment screens now open quickly (were slow to load)",
            "Fixed fuel and hours entry on the checklist",
            "Fixed an issue on the Equipment screen",
            "More reliable checklist, driver, and photo/video uploads on poor connections",
            "Login is now stored securely in the device Keychain",
        ]),
        AppRelease(version: "1.0.7", date: "Fri - July 24 - 2026", notes: [
            "New Queue Line module for staging equipment (Pending / Staged / Completed)",
            "Fixed an issue where some checklist submissions did not sync to the server",
            "Checklist reports now upload reliably and retry automatically when back online",
            "Automatic cleanup of uploaded photos & videos to save device storage",
            "Stability improvements and bug fixes",
        ]),
    ]

    /// The current (newest) release.
    static var latest: AppRelease? { all.first }
}
