//
//  SettingsAboutUITests.swift
//  RentnKingUITests — on-device check that Settings → About shows the metadata
//  of the INSTALLED binary:
//
//      Version:     "<marketing> (<build>)" from the bundle
//      Build Date:  the automatic build stamp (never "Unavailable", never a
//                   hand-typed release date, never the old "Release Date:" row)
//      Notes:       the catalog entry for the installed marketing version —
//                   never another version's notes
//
//  Runs the signed app on a real iPhone against staging through the DEBUG-only
//  StagingTestHarness, exactly like AuthFlowUITests. AppReleaseCatalog (Sync/Core,
//  Foundation only) is compiled into this bundle so the expected notes are
//  derived from the version the screen shows — the test stays valid for every
//  future version without edits.
//
//  Env (runner):  KABBA_BASE_URL, KABBA_EMAIL, KABBA_PASSWORD
//  Optional:      KABBA_EXPECT_VERSION     e.g. "1.0.20 (1005)"          → exact match
//                 KABBA_EXPECT_BUILD_DATE  e.g. "Sat - September 12 - 2026" → exact match
//

import XCTest

final class SettingsAboutUITests: XCTestCase {

    private var env: [String: String] = [:]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        env = ProcessInfo.processInfo.environment
        addUIInterruptionMonitor(withDescription: "system-permission") { alert in
            for label in ["Allow", "Allow While Using App", "OK", "Don’t Allow", "Don't Allow"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
    }

    func test_about_shows_installed_version_build_date_and_matching_notes() {
        let base = env["KABBA_BASE_URL"] ?? ""
        XCTAssertFalse(base.isEmpty, "KABBA_BASE_URL not provided")

        let app = XCUIApplication()
        app.launchArguments += [
            "-KabbaBaseURL", base,
            "-KabbaCompanyCode", "KABBA",
            "-KabbaEmail", env["KABBA_EMAIL"] ?? "",
            "-KabbaPassword", env["KABBA_PASSWORD"] ?? "",
        ]
        app.launch()
        app.tap()   // let the interruption monitor dismiss any system permission dialog

        // Sign in (the harness pre-filled the fields). Signed in ⇔ Login gone.
        let login = app.buttons["login.button"]
        XCTAssertTrue(login.waitForExistence(timeout: 40), "staging Login screen did not appear")
        login.tap()
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, login.exists { usleep(400_000) }
        XCTAssertFalse(login.exists, "still on the Login screen after sign-in")

        // Settings = last tab.
        let settingsTab = app.tabBars.buttons.element(boundBy: app.tabBars.buttons.count - 1)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "tab bar not found")
        settingsTab.tap()

        // Version: "<marketing> (<build>)"
        let versionLabel = staticText(app, beginningWith: "Version:")
        XCTAssertTrue(versionLabel.waitForExistence(timeout: 10), "Version row not found")
        let versionValue = value(after: "Version:", in: versionLabel.label)
        XCTAssertTrue(matches(versionValue, #"^\d+(\.\d+)+ \(\d+\)$"#), "unexpected version display: \(versionLabel.label)")
        if let expect = env["KABBA_EXPECT_VERSION"], !expect.isEmpty {
            XCTAssertEqual(versionValue, expect)
        }

        // Build Date: automatic, formatted, never stale or missing.
        let buildDateLabel = staticText(app, beginningWith: "Build Date:")
        XCTAssertTrue(buildDateLabel.exists, "Build Date row not found")
        XCTAssertFalse(staticText(app, beginningWith: "Release Date:").exists, "the old Release Date row is still shown")
        let buildDateValue = value(after: "Build Date:", in: buildDateLabel.label)
        XCTAssertNotEqual(buildDateValue, "Unavailable", "the installed bundle carries no build stamp")
        XCTAssertNotEqual(buildDateValue, "Tue - Aug 25 - 2026", "stale hand-typed release date")
        XCTAssertTrue(matches(buildDateValue, #"^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) - [A-Z][a-z]+ \d{1,2} - \d{4}$"#),
                      "unexpected build date format: \(buildDateLabel.label)")
        if let expect = env["KABBA_EXPECT_BUILD_DATE"], !expect.isEmpty {
            XCTAssertEqual(buildDateValue, expect)
        }

        // Release Notes: exactly the catalog entry for the DISPLAYED version.
        let marketing = String(versionValue.split(separator: " ").first ?? "")
        let expectedNotes = AppReleaseCatalog.notes(for: marketing).map { "~ \($0)" }.joined(separator: "\n")
        let notesLabel = staticText(app, beginningWith: "~ ")
        XCTAssertTrue(notesLabel.exists, "Release Notes not found")
        XCTAssertEqual(notesLabel.label, expectedNotes, "notes do not belong to \(marketing)")
        for other in AppReleaseCatalog.history where other.version != marketing {
            XCTAssertNotEqual(notesLabel.label, other.notes.map { "~ \($0)" }.joined(separator: "\n"),
                              "Settings is showing \(other.version)'s notes for \(marketing)")
        }

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "settings-about"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Helpers

    private func staticText(_ app: XCUIApplication, beginningWith prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func value(after key: String, in label: String) -> String {
        guard label.hasPrefix(key) else { return label }
        return String(label.dropFirst(key.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
