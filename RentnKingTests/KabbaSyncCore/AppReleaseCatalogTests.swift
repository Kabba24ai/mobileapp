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
        XCTAssertNil(AppReleaseCatalog.release(for: "1.0.21"))
        XCTAssertEqual(AppReleaseCatalog.notes(for: "1.0.21"), ["Various fixes and refinements"])
        XCTAssertEqual(AppReleaseCatalog.notes(for: "1.0.21"), AppReleaseCatalog.fallbackNotes)
        for release in AppReleaseCatalog.history {
            XCTAssertNotEqual(AppReleaseCatalog.notes(for: "1.0.21"), release.notes,
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
}
