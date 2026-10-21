//
//  AppReleaseCatalogTests.swift
//  KabbaSyncCoreTests
//
//  Settings → About must never show another version's metadata: notes are
//  selected by EQUALITY with the installed version (not array position), an
//  unknown version gets the neutral fallback, and the build date is a parsed
//  build-time stamp formatted the pre-existing way. No test reads the clock or
//  the bundle.
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class AppReleaseCatalogTests: XCTestCase {

    // 1. The installed version 1.0.20 finds the 1.0.20 notes.
    func testInstalledVersion1020FindsItsOwnNotes() {
        let release = AppReleaseCatalog.release(for: "1.0.20")
        XCTAssertEqual(release?.version, "1.0.20")
        XCTAssertEqual(release?.notes, [
            "Improved mobile equipment preparation with easier equipment substitutions",
            "Checklist restart support",
            "Stronger checklist and video accuracy",
            "Additional reliability improvements",
        ])
        XCTAssertEqual(AppReleaseCatalog.notes(for: "1.0.20"), release?.notes)
        // The entry being built carries no hand-maintained date.
        XCTAssertNil(release?.date)
    }

    // 2. An older version finds its own historical notes (and keeps its date).
    func testOlderVersionFindsItsOwnHistoricalNotes() {
        let v17 = AppReleaseCatalog.release(for: "1.0.17")
        XCTAssertEqual(v17?.version, "1.0.17")
        XCTAssertEqual(v17?.date, "Tue - Aug 25 - 2026")
        XCTAssertEqual(v17?.notes.first,
                       "Prepare a delivery before the customer arrives: complete the checklist, tap Save, then add delivery photos/video")

        let v7 = AppReleaseCatalog.release(for: "1.0.7")
        XCTAssertEqual(v7?.date, "Fri - July 24 - 2026")
        XCTAssertEqual(v7?.notes.first, "New Queue Line module for staging equipment (Pending / Staged / Completed)")
    }

    // 3. Array order does not decide the current version.
    func testArrayOrderDoesNotAffectSelection() {
        let reversed = Array(AppReleaseCatalog.history.reversed())
        XCTAssertNotEqual(reversed.first?.version, "1.0.20", "precondition: 1.0.20 is no longer first")
        XCTAssertEqual(AppReleaseCatalog.release(for: "1.0.20", in: reversed), AppReleaseCatalog.release(for: "1.0.20"))
        XCTAssertEqual(AppReleaseCatalog.release(for: "1.0.17", in: reversed), AppReleaseCatalog.release(for: "1.0.17"))

        // The exact bug: a newer-looking entry left at index 0 must not win.
        let staleFirst = [
            AppRelease(version: "1.0.17", date: "Tue - Aug 25 - 2026", notes: ["old notes"]),
            AppRelease(version: "1.0.20", notes: ["current notes"]),
        ]
        XCTAssertEqual(AppReleaseCatalog.notes(for: "1.0.20", in: staleFirst), ["current notes"])
        XCTAssertEqual(AppReleaseCatalog.notes(for: "1.0.17", in: staleFirst), ["old notes"])
    }

    // 4. An unknown version never borrows another version's notes.
    func testUnknownVersionGetsTheNeutralFallbackOnly() {
        XCTAssertNil(AppReleaseCatalog.release(for: "9.9.99"))
        XCTAssertEqual(AppReleaseCatalog.notes(for: "9.9.99"), ["Various fixes and refinements"])
        XCTAssertEqual(AppReleaseCatalog.notes(for: "9.9.99"), AppReleaseCatalog.fallbackNotes)
        for release in AppReleaseCatalog.history {
            XCTAssertNotEqual(AppReleaseCatalog.notes(for: "9.9.99"), release.notes,
                              "fallback must not equal \(release.version)'s notes")
        }
        XCTAssertNil(AppReleaseCatalog.release(for: ""))
        XCTAssertNil(AppReleaseCatalog.release(for: "   "))
    }

    // Matching is exact after trimming — "1.0.2" is not "1.0.20".
    func testMatchingIsExactAfterTrimming() {
        XCTAssertEqual(AppReleaseCatalog.release(for: " 1.0.20\n")?.version, "1.0.20")
        XCTAssertNil(AppReleaseCatalog.release(for: "1.0.2"))
        XCTAssertNil(AppReleaseCatalog.release(for: "1.0.200"))
    }

    // 5. versionDisplay stays "marketingVersion (build)".
    func testVersionDisplayIsMarketingVersionThenBuild() {
        XCTAssertEqual(AppReleaseCatalog.versionDisplay(marketingVersion: "1.0.20", build: "1005"), "1.0.20 (1005)")
    }

    // 6. Build date: stamp parsing + the pre-existing "EEE - MMMM d - yyyy" format.
    func testBuildDateParsingAndFormatting() {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let expected = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 13, minute: 14, second: 34))!

        XCTAssertEqual(AppReleaseCatalog.buildDate(fromStamp: "2026-09-12T13:14:34Z"), expected)
        XCTAssertEqual(AppReleaseCatalog.buildDate(fromStamp: " 2026-09-12T13:14:34Z\n"), expected)
        XCTAssertNil(AppReleaseCatalog.buildDate(fromStamp: "Sep 12 2026"))
        XCTAssertNil(AppReleaseCatalog.buildDate(fromStamp: ""))

        XCTAssertEqual(AppReleaseCatalog.formattedBuildDate(expected, timeZone: utc), "Sat - September 12 - 2026")
        // Late-UTC stamps render as the viewer's local day.
        let lateUTC = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 2, minute: 0))!
        XCTAssertEqual(AppReleaseCatalog.formattedBuildDate(lateUTC, timeZone: TimeZone(identifier: "America/Chicago")!),
                       "Sat - September 12 - 2026")
    }

    // The stamp file exactly as the "Stamp Build Date" build phase writes it.
    func testBuildStampPlistRoundTrip() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>BuildDate</key>
        \t<string>2026-09-12T13:14:34Z</string>
        \t<key>BuildConfiguration</key>
        \t<string>Debug</string>
        </dict>
        </plist>
        """
        let date = AppReleaseCatalog.buildDate(fromStampPlist: Data(plist.utf8))
        XCTAssertNotNil(date)
        XCTAssertEqual(date.map { AppReleaseCatalog.formattedBuildDate($0, timeZone: TimeZone(identifier: "UTC")!) },
                       "Sat - September 12 - 2026")
        XCTAssertNil(AppReleaseCatalog.buildDate(fromStampPlist: Data("not a plist".utf8)))
        XCTAssertNil(AppReleaseCatalog.buildDate(fromStampPlist: Data("<plist version=\"1.0\"><dict/></plist>".utf8)))
        XCTAssertEqual(AppReleaseCatalog.buildStampResourceName, "KabbaBuildInfo")
        XCTAssertEqual(AppReleaseCatalog.buildDateUnavailable, "Unavailable")
    }

    // Catalog integrity: one entry per version, every entry has notes.
    func testHistoryHasUniqueVersionsAndNotes() {
        let versions = AppReleaseCatalog.history.map(\.version)
        XCTAssertEqual(Set(versions).count, versions.count, "duplicate version entries: \(versions)")
        for release in AppReleaseCatalog.history {
            XCTAssertFalse(release.notes.isEmpty, "\(release.version) has no notes")
        }
    }

    // 6. The history says what each build actually shipped. 1.0.26 (1012) was approved
    //    without Next Stop, so Next Stop belongs to 1.0.27 — never to 1.0.26.
    func testNextStopIsCreditedTo1027AndThe1026NotesAreWhat1012Shipped() {
        let v27 = AppReleaseCatalog.release(for: "1.0.27")
        XCTAssertEqual(v27?.notes.first,
                       "Finishing a delivery, return or manual dispatch now asks what you're doing next instead of sending you back to the board")
        XCTAssertEqual(v27?.notes.count, 4)

        XCTAssertEqual(AppReleaseCatalog.release(for: "1.0.26")?.notes, [
            "Fuel is charged at the machine's own fuel price and tank size; a DEF tank no longer replaces the diesel charge",
            "Machines with a DEF tank can record DEF separately from fuel, with the same tank levels, once enabled for your company",
            "Each piece of equipment on a return is charged only for its own fuel, cleaning and hours",
            "Totals update as soon as current prices load",
            "Various fixes and refinements",
        ], "1.0.26 must read exactly as build 1012 shipped it.")

        XCTAssertEqual(Set(AppReleaseCatalog.history.map(\.version)).count, AppReleaseCatalog.history.count,
                       "One entry per version.")
    }

    // 7. 1.0.28 (1014) is the route-evidence release: its notes are the App Store "What's New"
    //    text too, and 1.0.27's entry still reads exactly as build 1013 shipped it.
    func testThe1028NotesDescribeTheRouteEvidenceAndComeFirst() {
        XCTAssertEqual(AppReleaseCatalog.history.first?.version, "1.0.28", "Newest first, for presentation.")
        let v28 = AppReleaseCatalog.release(for: "1.0.28")
        XCTAssertEqual(v28?.notes.first,
                       "Your Next Stop answers (next customer or task, Return to Shop and Arrived at Shop) are now sent to the office with the time you tapped them")
        XCTAssertEqual(v28?.notes.last, "Various fixes and refinements")
        XCTAssertEqual(AppReleaseCatalog.release(for: "1.0.27")?.notes, [
            "Finishing a delivery, return or manual dispatch now asks what you're doing next instead of sending you back to the board",
            "Pick your next customer or task from the work still assigned to you, or head back to one of your shops",
            "The shop you picked stays your destination while you navigate, and is still there when you come back to the app",
            "Various fixes and refinements",
        ], "1.0.27 must read exactly as build 1013 shipped it.")
    }

    // MARK: - MOBILE-QUALITY-01 (item 04): one draft per release, traceable builds

    // 7. The App Store text is rendered from the SAME entry Settings shows — never a second draft.
    func testWhatsNewIsRenderedFromTheEntrySettingsShows() throws {
        let text = try XCTUnwrap(AppReleaseCatalog.appStoreWhatsNew(for: "1.0.27"))
        XCTAssertEqual(text, AppReleaseCatalog.notes(for: "1.0.27").map { "• \($0)" }.joined(separator: "\n"))
        XCTAssertNil(AppReleaseCatalog.appStoreWhatsNew(for: "9.9.9"), "no entry → no text, never another version's")
        for release in AppReleaseCatalog.history {
            let rendered = AppReleaseCatalog.appStoreWhatsNew(for: release.version) ?? ""
            XCTAssertLessThanOrEqual(rendered.count, AppReleaseCatalog.appStoreWhatsNewLimit, "\(release.version) is too long for App Store Connect")
        }
    }

    // 8. The version this project builds has its notes — a release can never ship the
    //    neutral fallback (or another version's text) by accident.
    func testTheProjectsVersionAndBuildAreConsistentAndHaveReleaseNotes() throws {
        let pbx = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RentnKing.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: pbx, encoding: .utf8)
        func values(_ key: String, ignoring placeholder: String) -> Set<String> {
            let regex = try! NSRegularExpression(pattern: "\\b\(key) = ([^;]+);")
            let matches = regex.matches(in: project, range: NSRange(project.startIndex..., in: project))
            return Set(matches.compactMap { Range($0.range(at: 1), in: project).map { String(project[$0]) } }).subtracting([placeholder])
        }
        let versions = values("MARKETING_VERSION", ignoring: "1.0")      // test targets keep 1.0 / 1
        let builds = values("CURRENT_PROJECT_VERSION", ignoring: "1")
        XCTAssertEqual(versions.count, 1, "app and extension must carry ONE marketing version: \(versions.sorted())")
        XCTAssertEqual(builds.count, 1, "app and extension must carry ONE build number: \(builds.sorted())")
        let version = try XCTUnwrap(versions.first)
        XCTAssertNotNil(AppReleaseCatalog.release(for: version), "\(version) has no release notes in AppReleaseCatalog.history")
    }

    // 9. A build tells support exactly what it is, including a build from a modified tree.
    func testBuildIdentityReadsTheStampAndSaysWhenTheTreeWasModified() throws {
        let stamp: [String: Any] = ["BuildDate": "2026-10-21T14:03:00Z", "BuildConfiguration": "Release",
                                    "SourceRevision": "44927ea635b8", "SourceState": "clean", "SourceBranch": "fix/fuel-def-readings-1.0.26"]
        let data = try PropertyListSerialization.data(fromPropertyList: stamp, format: .xml, options: 0)
        let identity = BuildIdentity(version: "1.0.27", build: "1013", stamp: AppReleaseCatalog.buildIdentity(fromStampPlist: data), channel: .appStore)
        XCTAssertEqual(identity.summary, "1.0.27 (1013) · Source 44927ea635b8 · Release · App Store · Built Oct 21, 2026 14:03 UTC")

        var modified = identity.stamp
        modified.sourceState = "modified"
        XCTAssertEqual(BuildIdentity(version: "1.0.27", build: "1013", stamp: modified, channel: .development).sourceLine,
                       "Source 44927ea635b8 + uncommitted changes")

        // A binary stamped before MOBILE-QUALITY-01 (no revision keys) says so, never guesses.
        let old = try PropertyListSerialization.data(fromPropertyList: ["BuildDate": "2026-10-18T02:00:00Z", "BuildConfiguration": "Release"], format: .xml, options: 0)
        XCTAssertEqual(BuildIdentity(version: "1.0.27", build: "1013", stamp: AppReleaseCatalog.buildIdentity(fromStampPlist: old), channel: .appStore).sourceLine,
                       "Source unknown")
        XCTAssertNil(AppReleaseCatalog.buildIdentity(fromStampPlist: Data()).sourceRevision)
    }

    // 10. How the copy reached the phone — what told Gary's computer-installed 1.0.27 (1013)
    //     apart from the office phones' App Store copy.
    func testInstallChannelDetection() {
        XCTAssertEqual(InstallChannel.detect(receiptName: "receipt", hasEmbeddedProvisioningProfile: false, isSimulator: false), .appStore)
        XCTAssertEqual(InstallChannel.detect(receiptName: "sandboxReceipt", hasEmbeddedProvisioningProfile: false, isSimulator: false), .testFlight)
        XCTAssertEqual(InstallChannel.detect(receiptName: nil, hasEmbeddedProvisioningProfile: true, isSimulator: false), .development)
        XCTAssertEqual(InstallChannel.detect(receiptName: "sandboxReceipt", hasEmbeddedProvisioningProfile: true, isSimulator: false), .development,
                       "a development profile wins over the receipt name")
        XCTAssertEqual(InstallChannel.detect(receiptName: nil, hasEmbeddedProvisioningProfile: false, isSimulator: true), .simulator)
    }
}
