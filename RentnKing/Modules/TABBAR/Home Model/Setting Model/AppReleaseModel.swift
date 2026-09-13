//
//  AppReleaseModel.swift
//  RentnKing
//
//  Bundle-facing source of the Settings → About metadata. Everything here is
//  READ from the running app; the rules (which notes belong to which version,
//  the fallback, the date format) live in AppReleaseCatalog (Sync/Core) where
//  they are unit-tested. Nothing below is hand-maintained per release:
//
//      Version / Build → CFBundleShortVersionString / CFBundleVersion
//      Build Date      → KabbaBuildInfo.plist, stamped by the "Stamp Build Date"
//                        build phase of the RentnKing target
//      Release Notes   → the catalog entry matching the installed version
//

import Foundation

/// Central source of app version + release metadata for the installed build.
enum AppReleaseInfo {

    /// Marketing version from the bundle, e.g. "1.0.20".
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Build number from the bundle, e.g. "1005".
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    /// "1.0.20 (1005)" — shown next to "Version:".
    static var versionDisplay: String {
        AppReleaseCatalog.versionDisplay(marketingVersion: version, build: build)
    }

    /// The build-time stamp of THIS binary (nil when the bundle carries none).
    static var buildDateRaw: Date? {
        guard let url = Bundle.main.url(forResource: AppReleaseCatalog.buildStampResourceName, withExtension: "plist"),
              let data = try? Data(contentsOf: url) else { return nil }
        return AppReleaseCatalog.buildDate(fromStampPlist: data)
    }

    /// "Sat - September 12 - 2026" — shown next to "Build Date:". "Unavailable"
    /// when the bundle has no stamp; never a guessed or borrowed date.
    static var buildDate: String {
        buildDateRaw.map { AppReleaseCatalog.formattedBuildDate($0) } ?? AppReleaseCatalog.buildDateUnavailable
    }

    /// Every release, newest first (Full Archive).
    static var all: [AppRelease] { AppReleaseCatalog.history }

    /// The entry for the INSTALLED version — nil when it has none.
    static var current: AppRelease? { AppReleaseCatalog.release(for: version) }

    /// Notes for the installed version, or the neutral fallback.
    static var currentNotes: [String] { AppReleaseCatalog.notes(for: version) }

    /// Archive date: the installed version shows its automatic build date,
    /// historical entries their recorded date.
    static func displayDate(for release: AppRelease) -> String {
        release.version == version ? buildDate : (release.date ?? "")
    }
}
