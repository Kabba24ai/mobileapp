import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class InstallationIdentityTests: XCTestCase {

    func testIdentifierIsStableAcrossInstancesAndMatchesTheServerWhitelist() throws {
        let dir = Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = InstallationIdentity(directory: dir).identifier()
        let second = InstallationIdentity(directory: dir).identifier()

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("install-"))
        XCTAssertTrue(InstallationIdentity.isValid(first))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("installation_id").path))
    }

    func testDifferentInstallsGetDifferentIdentifiers() {
        let a = InstallationIdentity(directory: Fixtures.tempDirectory("a")).identifier()
        let b = InstallationIdentity(directory: Fixtures.tempDirectory("b")).identifier()
        XCTAssertNotEqual(a, b)
    }

    func testValidation() {
        XCTAssertFalse(InstallationIdentity.isValid("short"))
        XCTAssertFalse(InstallationIdentity.isValid("has spaces in it"))
        XCTAssertTrue(InstallationIdentity.isValid("install-0123456789ABCDEF"))
    }

    func testISO8601RoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_756_140_843)
        let string = KabbaISO8601.string(from: date)
        XCTAssertEqual(try XCTUnwrap(KabbaISO8601.date(from: string)).timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(KabbaISO8601.date(from: "2026-08-25T14:14:03.123-05:00")).timeIntervalSince1970, 1_787_685_243.123, accuracy: 0.01) // 2026-08-25T19:14:03.123Z
        XCTAssertNil(KabbaISO8601.date(from: "yesterday-ish"))
    }
}
