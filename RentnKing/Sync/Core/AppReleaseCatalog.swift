//
//  AppReleaseCatalog.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Release metadata for Settings → About, kept free of UIKit/Bundle so the
//  selection rules are unit-testable on macOS (KabbaSyncCore):
//
//      Version     → the running bundle (never hard-coded here)
//      Build Date  → the build-time stamp the "Stamp Build Date" build phase
//                    writes into the app bundle (never a file mtime — those are
//                    stale on incremental builds and rewritten by export /
//                    App Store processing)
//      Notes       → the history entry whose version EQUALS the installed
//                    version — never "whichever entry is first"
//
//  A version without an entry gets the neutral fallback, never another
//  version's notes. `history` stays newest-first for presentation only; order
//  has no say in what counts as the current release.
//

import Foundation

/// One release entry shown in Settings → About / Full Archive.
struct AppRelease: Equatable {
    let version: String
    /// Historical date for the archive. nil = not recorded — the installed
    /// version shows the automatic build date instead, so the entry for the
    /// release being built never needs a hand-maintained date.
    let date: String?
    let notes: [String]

    init(version: String, date: String? = nil, notes: [String]) {
        self.version = version
        self.date = date
        self.notes = notes
    }
}

enum AppReleaseCatalog {

    /// Shown when the installed version has no entry — a missing entry is
    /// preferable to another version's notes.
    static let fallbackNotes = ["Various fixes and refinements"]

    /// Every release, NEWEST FIRST (presentation order only).
    static let history: [AppRelease] = [
        AppRelease(version: "1.0.22", notes: [
            "The equipment picker opens in the same Product Category as the machine already assigned — an unassigned line starts in the category of the product that was ordered",
            "Change the category to take a machine from anywhere in the fleet; the same substitution and reason rules still apply",
            "Search by name or Equipment ID within the category you are looking at",
            "Equipment reads in working order: Available first, then Maintenance Hold, Damaged and Rented, alphabetical within each",
            "Various fixes and refinements",
        ]),

        AppRelease(version: "1.0.21", notes: [
            "Assembly Review: every outbound equipment checklist now starts with a review of the whole assembly — the machine, bundled and related items, and every ordered Product Option — with a STOP / GO gate before the checklist",
            "Assign or change equipment right from Assembly Review; a newly assigned machine always starts unconfirmed",
            "Equipment reads as Name · #ID on the review, and tapping it changes the assignment",
            "A checklist Save stages only the item you worked on, never its siblings",
            "Various fixes and refinements",
        ]),

        AppRelease(version: "1.0.20", notes: [
            "Improved mobile equipment preparation with easier equipment substitutions",
            "Checklist restart support",
            "Stronger checklist and video accuracy",
            "Additional reliability improvements",
        ]),

        AppRelease(version: "1.0.17", date: "Tue - Aug 25 - 2026", notes: [
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

    // MARK: Selection

    /// The entry whose version equals `version` (whitespace-trimmed), wherever
    /// it sits in the array. nil when the version has no entry.
    static func release(for version: String, in releases: [AppRelease] = history) -> AppRelease? {
        let wanted = normalized(version)
        guard !wanted.isEmpty else { return nil }
        return releases.first { normalized($0.version) == wanted }
    }

    /// Notes for the installed version, or the neutral fallback.
    static func notes(for version: String, in releases: [AppRelease] = history) -> [String] {
        release(for: version, in: releases)?.notes ?? fallbackNotes
    }

    /// "1.0.20 (1005)" — marketing version, then the build in parentheses.
    static func versionDisplay(marketingVersion: String, build: String) -> String {
        "\(marketingVersion) (\(build))"
    }

    // MARK: Build date

    /// Resource the "Stamp Build Date" build phase writes at the app bundle root.
    static let buildStampResourceName = "KabbaBuildInfo"
    static let buildStampDateKey = "BuildDate"
    /// Shown when no stamp exists (a build that skipped the phase) — never a guess.
    static let buildDateUnavailable = "Unavailable"

    /// Parses the stamp value, ISO 8601 UTC, e.g. "2026-09-12T13:14:34Z".
    static func buildDate(fromStamp value: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Reads the stamp plist (as written by the build phase) → build date.
    static func buildDate(fromStampPlist data: Data) -> Date? {
        guard let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let value = dict[buildStampDateKey] as? String else { return nil }
        return buildDate(fromStamp: value)
    }

    /// "Sat - September 12 - 2026" — the pre-existing About format, in the
    /// viewer's time zone by default.
    static func formattedBuildDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = timeZone
        fmt.dateFormat = "EEE - MMMM d - yyyy"
        return fmt.string(from: date)
    }

    private static func normalized(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
