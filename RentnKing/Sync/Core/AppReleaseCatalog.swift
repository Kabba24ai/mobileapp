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
        AppRelease(version: "1.0.29", notes: [
            "Settings › Sync shows what is waiting to send and what needs your attention; open a refused record to see why, what it holds, and remove it from the phone with one confirmation",
            "Sync Now tells you what it sent, what is waiting for a connection and what needs attention",
            "A checklist can no longer be sent with another machine's answers; the app tells you which line to reopen",
            "Driver's license: Save shows a short confirmation and goes straight back to Order Details, and reopening shows the photos and expiration saved on the phone with their sync status",
            "Queue Line: tap an order number to open its Order Details; Back returns you to the same place",
            "Queue Line cards show Paid or Pending, and paid orders come first within each scheduled day",
            "Settings › About: tap the version to see exactly which build is installed",
            "Various fixes and refinements",
        ]),
        AppRelease(version: "1.0.28", notes: [
            "Your Next Stop answers (next customer or task, Return to Shop and Arrived at Shop) are now sent to the office with the time you tapped them",
            "Answers given without a connection stay on the phone and are sent once you're back online",
            "Manual Dispatch status changes keep the time you tapped them, even when they are sent later",
            "Work saved without a connection is sent in the order you did it, even after the app is closed and reopened",
            "Various fixes and refinements",
        ]),
        AppRelease(version: "1.0.27", notes: [
            "Finishing a delivery, return or manual dispatch now asks what you're doing next instead of sending you back to the board",
            "Pick your next customer or task from the work still assigned to you, or head back to one of your shops",
            "The shop you picked stays your destination while you navigate, and is still there when you come back to the app",
            "Various fixes and refinements",
        ]),
        AppRelease(version: "1.0.26", notes: [
            "Fuel is charged at the machine's own fuel price and tank size; a DEF tank no longer replaces the diesel charge",
            "Machines with a DEF tank can record DEF separately from fuel, with the same tank levels, once enabled for your company",
            "Each piece of equipment on a return is charged only for its own fuel, cleaning and hours",
            "Totals update as soon as current prices load",
            "Various fixes and refinements",
        ]),
        AppRelease(version: "1.0.25", notes: [
            "Each piece of equipment on an order keeps its own checklist — finish one, two or all of them",
            "Combine shares only the employee, signature and return location with the equipment you completed",
            "Equipment you did not touch is never submitted; partly entered equipment is pointed out before Preview",
            "Unfinished equipment and your shared selections stay saved after a partial submit",
            "Various fixes and refinements",
        ]),
        AppRelease(version: "1.0.24", notes: [
            "Equipment Audit on the phone: open an audit, see your assigned section and verify units with one tap",
            "Search by name or Equipment ID and filter the board by section",
            "Record a location mismatch, mark a unit Unresolved or move it Off-Site with the same rules as the web audit",
            "Clear messages when there is no connection — an audit action is never recorded offline",
            "Various fixes and refinements",
        ]),
        AppRelease(version: "1.0.23", notes: [
            "Improved driver delivery workflow with stronger offline support",
            "Guided customer-call verification before departure",
            "Better handling when equipment assignments change",
            "More reliable synchronization during deliveries",
            "Various fixes and refinements",
        ]),
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

    // MARK: App Store "What's New" (MOBILE-QUALITY-01, item 04)
    //
    // ONE authoritative draft per release: the catalog entry above. The App Store's
    // "What's New" text is rendered from it (Scripts/whats-new.sh), so the phone's
    // Settings → About and the App Store say the same thing. App Store Connect is
    // still edited by hand — nothing publishes this text automatically.

    /// App Store Connect's limit for "What's New in This Version".
    static let appStoreWhatsNewLimit = 4000

    /// "• note" per line — the text to paste into App Store Connect. nil when the version
    /// has no entry (the release must not ship with another version's notes).
    static func appStoreWhatsNew(for version: String, in releases: [AppRelease] = history) -> String? {
        guard let entry = release(for: version, in: releases), !entry.notes.isEmpty else { return nil }
        return entry.notes.map { "• \($0)" }.joined(separator: "\n")
    }

    // MARK: Build identity

    static let buildStampConfigurationKey = "BuildConfiguration"
    static let buildStampRevisionKey = "SourceRevision"
    static let buildStampSourceStateKey = "SourceState"
    static let buildStampBranchKey = "SourceBranch"

    /// What the build-time stamp says about the source this binary was built from.
    static func buildIdentity(fromStampPlist data: Data) -> BuildIdentity.Stamp {
        guard let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return BuildIdentity.Stamp()
        }
        func value(_ key: String) -> String? {
            guard let v = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return v
        }
        return BuildIdentity.Stamp(buildDate: value(buildStampDateKey).flatMap(buildDate(fromStamp:)),
                                   configuration: value(buildStampConfigurationKey),
                                   sourceRevision: value(buildStampRevisionKey),
                                   sourceState: value(buildStampSourceStateKey),
                                   sourceBranch: value(buildStampBranchKey))
    }
}

/// How this copy of the app reached the phone — the question behind "my phone shows
/// different notes than the office phones" (a computer-installed build vs the App Store).
enum InstallChannel: String, Equatable {
    case appStore = "App Store"
    case testFlight = "TestFlight"
    /// Installed from a computer (Xcode / development or ad-hoc signing).
    case development = "Installed from a computer"
    case simulator = "Simulator"

    /// - Parameters:
    ///   - receiptName: the App Store receipt's file name ("sandboxReceipt" under TestFlight).
    ///   - hasEmbeddedProvisioningProfile: development and ad-hoc builds carry one; App Store builds never do.
    static func detect(receiptName: String?, hasEmbeddedProvisioningProfile: Bool, isSimulator: Bool) -> InstallChannel {
        if isSimulator { return .simulator }
        if hasEmbeddedProvisioningProfile { return .development }
        if receiptName == "sandboxReceipt" { return .testFlight }
        return .appStore
    }
}

/// Everything support needs to tell two builds of the same version apart, on one line.
struct BuildIdentity: Equatable {

    struct Stamp: Equatable {
        var buildDate: Date?
        var configuration: String?
        var sourceRevision: String?
        /// "clean" / "modified" (built with uncommitted changes).
        var sourceState: String?
        var sourceBranch: String?
    }

    let version: String
    let build: String
    let stamp: Stamp
    let channel: InstallChannel

    /// "Source 44927ea635b8" or "Source 44927ea635b8 + uncommitted changes" / "Source unknown".
    var sourceLine: String {
        guard let revision = stamp.sourceRevision else { return "Source unknown" }
        return "Source \(revision)" + (stamp.sourceState == "modified" ? " + uncommitted changes" : "")
    }

    /// "1.0.28 (1014) · Source 44927ea635b8 · Release · App Store · Built Oct 21, 2026 14:03 UTC"
    var summary: String {
        var parts = [AppReleaseCatalog.versionDisplay(marketingVersion: version, build: build), sourceLine]
        if let configuration = stamp.configuration { parts.append(configuration) }
        parts.append(channel.rawValue)
        if let date = stamp.buildDate { parts.append("Built " + Self.utc(date)) }
        return parts.joined(separator: " · ")
    }

    private static func utc(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "MMM d, yyyy HH:mm 'UTC'"
        return fmt.string(from: date)
    }
}
