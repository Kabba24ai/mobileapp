import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Phase 5 — the phone's session record, the offline rule, per-install persistence and the
/// one-time credential migration into the shared Keychain (pure logic; the Keychain itself is
/// exercised on device).
final class SessionStateTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = Fixtures.tempDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func loginBody(session: [String: Any]?) -> Data {
        var body: [String: Any] = ["success": true, "message": "ok",
                                   "user": ["id": 42, "unique_id": "PER-0042", "full_name": "Field Tech", "email": "tech@example.test", "status": "Active", "token": "1|secret"]]
        if let session = session { body["session"] = session }
        return Fixtures.json(body)
    }

    func testAnIdentifiedLoginProducesAPerInstallRecordWithServerExpiry() throws {
        let data = loginBody(session: ["token_type": "Bearer", "scope": "installation", "issued_at": "2026-08-25T10:00:00+00:00",
                                       "expires_at": "2026-09-24T10:00:00+00:00", "sliding_ttl_days": 30,
                                       "installation_id": "install-A", "platform": "ios", "app_version": "1.0.18", "app_build": "1001", "device_name": "iPhone"])
        let record = try XCTUnwrap(SessionRecord.decode(loginResponse: data))
        XCTAssertEqual(record.userId, "42")
        XCTAssertEqual(record.scope, "installation")
        XCTAssertEqual(record.installationId, "install-A")
        XCTAssertEqual(record.appBuild, "1001")
        XCTAssertEqual(record.slidingTTLDays, 30)
        XCTAssertEqual(record.expiresAt, KabbaISO8601.date(from: "2026-09-24T10:00:00+00:00"))
        XCTAssertFalse(record.isPastServerExpiry(now: KabbaISO8601.date(from: "2026-09-01T00:00:00+00:00")!))
        XCTAssertTrue(record.isPastServerExpiry(now: KabbaISO8601.date(from: "2026-09-25T00:00:00+00:00")!))
    }

    func testALegacyLoginWithoutASessionBlockIsALegacyRecordThatNeverExpires() throws {
        let record = try XCTUnwrap(SessionRecord.decode(loginResponse: loginBody(session: nil)))
        XCTAssertEqual(record.scope, "legacy")
        XCTAssertNil(record.expiresAt)
        XCTAssertNil(record.installationId)
        XCTAssertFalse(record.isPastServerExpiry(now: .distantFuture))
    }

    func testAFailedLoginProducesNoRecord() {
        XCTAssertNil(SessionRecord.decode(loginResponse: Fixtures.json(["success": false, "message": "nope"])))
    }

    func testTheRecordPersistsAcrossRelaunchAndIsClearedOnSignOut() throws {
        let store = SessionStore(directory: dir)
        let record = try XCTUnwrap(SessionRecord.decode(loginResponse: loginBody(session: ["scope": "installation", "installation_id": "install-A", "expires_at": "2026-09-24T10:00:00+00:00"]),
                                                        now: Date(timeIntervalSince1970: 1_700_000_000)))   // whole seconds: the file format is ISO-8601
        try store.save(record)

        let relaunched = SessionStore(directory: dir)
        XCTAssertEqual(relaunched.load(), record)
        XCTAssertFalse(String(decoding: try Data(contentsOf: store.fileURL), as: UTF8.self).contains("1|secret"), "the token is never part of the record")

        relaunched.clear()
        XCTAssertNil(SessionStore(directory: dir).load())
    }

    func testServerContactRefreshesTheSlidingExpiry() throws {
        var record = try XCTUnwrap(SessionRecord.decode(loginResponse: loginBody(session: ["scope": "installation", "expires_at": "2026-09-24T10:00:00+00:00"])))
        let now = KabbaISO8601.date(from: "2026-08-27T10:00:00+00:00")!
        record.noteServerContact(expiresAtHeader: "2026-09-26T10:00:00+00:00", at: now)
        XCTAssertEqual(record.expiresAt, KabbaISO8601.date(from: "2026-09-26T10:00:00+00:00"))
        XCTAssertEqual(record.lastServerContactAt, now)
        record.noteServerContact(expiresAtHeader: "garbage", at: now)
        XCTAssertEqual(record.expiresAt, KabbaISO8601.date(from: "2026-09-26T10:00:00+00:00"), "an unreadable header changes nothing")
    }

    // MARK: Offline rule

    func testOfflineCaptureIsAllowedWheneverASessionRecordExistsEvenPastServerExpiry() throws {
        let expired = try XCTUnwrap(SessionRecord.decode(loginResponse: loginBody(session: ["scope": "installation", "expires_at": "2026-09-24T10:00:00+00:00"])))
        let later = KabbaISO8601.date(from: "2026-10-01T00:00:00+00:00")!

        XCTAssertFalse(OfflineSessionPolicy.canCaptureOffline(nil))
        XCTAssertTrue(OfflineSessionPolicy.canCaptureOffline(expired), "connectivity loss or a passed expiry never blocks capture — the server decides at sync")
        XCTAssertTrue(OfflineSessionPolicy.syncNeedsReauthentication(expired, now: later))
        XCTAssertTrue(OfflineSessionPolicy.syncNeedsReauthentication(nil, now: later))
        XCTAssertFalse(OfflineSessionPolicy.syncNeedsReauthentication(expired, now: KabbaISO8601.date(from: "2026-09-01T00:00:00+00:00")!))
        XCTAssertTrue(OfflineSessionPolicy.statusLine(expired, now: later).contains("saved work is kept"))
        XCTAssertEqual(OfflineSessionPolicy.statusLine(nil, now: later), "Signed out — sign in to sync")
    }

    // MARK: Credential migration

    private func source(_ name: String, _ box: Box) -> SessionCredentialMigration.LegacySource {
        .init(name: name, read: { box.value }, purge: { box.value = nil; box.purged = true })
    }

    private final class Box { var value: String?; var purged = false; init(_ v: String?) { value = v } }

    func testALegacyTokenMovesIntoTheSharedStoreOnceAndEveryOldCopyIsPurged() {
        let shared = InMemorySessionCredentialStore()
        let defaults = Box("1|legacy"), privateKeychain = Box("1|legacy"), appGroup = Box("1|legacy")

        let outcome = SessionCredentialMigration.run(shared: shared, legacy: [source("user_defaults", defaults), source("private_keychain", privateKeychain), source("app_group_defaults", appGroup)])

        XCTAssertEqual(outcome.token, "1|legacy")
        XCTAssertEqual(outcome.migratedFrom, "user_defaults")
        XCTAssertEqual(shared.read(SessionCredentialMigration.accessTokenKey), "1|legacy")
        XCTAssertTrue(defaults.purged && privateKeychain.purged && appGroup.purged)
        XCTAssertEqual(Set(outcome.purged), ["user_defaults", "private_keychain", "app_group_defaults"])

        // Second run: nothing left to move.
        let again = SessionCredentialMigration.run(shared: shared, legacy: [source("user_defaults", defaults)])
        XCTAssertEqual(again.token, "1|legacy")
        XCTAssertNil(again.migratedFrom)
        XCTAssertTrue(again.purged.isEmpty)
    }

    func testTheSharedStoreWinsOverStaleLegacyCopiesWhichAreStillPurged() throws {
        let shared = InMemorySessionCredentialStore()
        try shared.write("2|current", key: SessionCredentialMigration.accessTokenKey)
        let appGroup = Box("1|stale")

        let outcome = SessionCredentialMigration.run(shared: shared, legacy: [source("app_group_defaults", appGroup)])
        XCTAssertEqual(outcome.token, "2|current")
        XCTAssertTrue(appGroup.purged, "no plaintext copy may outlive the shared item")
    }

    func testASharedWriteFailureKeepsTheLegacyCopyAndStillReturnsTheToken() {
        let shared = InMemorySessionCredentialStore()
        shared.failWrites = true
        let defaults = Box("1|legacy")

        let outcome = SessionCredentialMigration.run(shared: shared, legacy: [source("user_defaults", defaults)])
        XCTAssertEqual(outcome.token, "1|legacy", "a Keychain failure can never log an existing user out")
        XCTAssertNil(outcome.migratedFrom)
        XCTAssertFalse(defaults.purged)
        XCTAssertNil(shared.read(SessionCredentialMigration.accessTokenKey))
    }

    func testNoTokenAnywhereMeansSignedOut() {
        let outcome = SessionCredentialMigration.run(shared: InMemorySessionCredentialStore(), legacy: [source("user_defaults", Box(nil)), source("app_group_defaults", Box(""))])
        XCTAssertNil(outcome.token)
        XCTAssertTrue(outcome.purged.isEmpty)
    }
}
