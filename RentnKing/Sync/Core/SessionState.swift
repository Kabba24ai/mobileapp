//
//  SessionState.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Phase 5 — the phone's record of its own session, and the offline rule.
//
//  Laravel is the ONLY authority on whether a credential is still valid, and it
//  can only say so when the phone reaches it. So:
//
//   • Offline capture is allowed whenever a session record exists — loss of
//     connectivity never logs anyone out and never blocks checklist / media /
//     licence capture; the operations queue durably and are judged at sync.
//   • The server's `session.expires_at` (and the X-Session-Expires-At header it
//     refreshes on every authenticated response) lets the phone WARN that the
//     next sync will need a sign-in; it never deletes anything.
//   • A real 401 at sync pauses the engine and sends the employee to sign in;
//     the queue is untouched and resumes after login (SyncEngine).
//

import Foundation

struct SessionRecord: Codable, Equatable {
    var userId: String
    var email: String?
    var fullName: String?
    /// "installation" (per-install, sliding expiry) | "legacy" (api_user, no expiry)
    var scope: String
    var installationId: String?
    var platform: String?
    var appVersion: String?
    var appBuild: String?
    var issuedAt: Date
    /// Server-side expiry as last reported (nil = never expires).
    var expiresAt: Date?
    var slidingTTLDays: Int?
    /// The last time Laravel answered an authenticated request from this session.
    var lastServerContactAt: Date?

    /// Builds the record from the login response body (`user` + additive `session`).
    static func decode(loginResponse data: Data, now: Date = Date()) -> SessionRecord? {
        guard let root = JSONValue.parse(data), root["success"]?.boolValue == true,
              let user = root["user"], let userId = user["id"]?.stringValue, !userId.isEmpty else { return nil }
        let session = root["session"]
        return SessionRecord(
            userId: userId,
            email: user["email"]?.stringValue,
            fullName: user["full_name"]?.stringValue,
            scope: session?["scope"]?.stringValue ?? "legacy",
            installationId: session?["installation_id"]?.stringValue,
            platform: session?["platform"]?.stringValue,
            appVersion: session?["app_version"]?.stringValue,
            appBuild: session?["app_build"]?.stringValue,
            issuedAt: session?["issued_at"]?.stringValue.flatMap(KabbaISO8601.date(from:)) ?? now,
            expiresAt: session?["expires_at"]?.stringValue.flatMap(KabbaISO8601.date(from:)),
            slidingTTLDays: session?["sliding_ttl_days"]?.stringValue.flatMap { Int($0) },
            lastServerContactAt: now
        )
    }

    /// Every authenticated response refreshes the sliding expiry (X-Session-Expires-At).
    mutating func noteServerContact(expiresAtHeader: String?, at now: Date) {
        lastServerContactAt = now
        if let raw = expiresAtHeader, let date = KabbaISO8601.date(from: raw) {
            expiresAt = date
        }
    }

    func isPastServerExpiry(now: Date) -> Bool {
        guard let expiresAt = expiresAt else { return false }
        return expiresAt <= now
    }
}

/// The offline-session rule in one place (documented in MOBILE_API_CONTRACT.md §12).
enum OfflineSessionPolicy {
    /// A signed-in phone keeps capturing offline, full stop. The server decides at sync.
    static func canCaptureOffline(_ record: SessionRecord?) -> Bool {
        record != nil
    }

    /// True when the phone already knows the server will refuse the next sync — used to
    /// warn ("sign in to sync"), never to block capture or delete anything.
    static func syncNeedsReauthentication(_ record: SessionRecord?, now: Date) -> Bool {
        guard let record = record else { return true }
        return record.isPastServerExpiry(now: now)
    }

    static func statusLine(_ record: SessionRecord?, now: Date) -> String {
        guard let record = record else { return "Signed out — sign in to sync" }
        guard let expiresAt = record.expiresAt else { return "Signed in" }
        if expiresAt <= now { return "Session expired — sign in to resume syncing (saved work is kept)" }
        let days = Int(expiresAt.timeIntervalSince(now) / 86_400)
        return days <= 3 ? "Session expires in \(max(days, 0)) day\(days == 1 ? "" : "s") without connectivity" : "Signed in"
    }
}

/// Persists the SessionRecord in the protected KabbaSync directory (no token — the token
/// lives in the Keychain).
final class SessionStore {
    static let filename = "session.json"

    let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(directory: URL, fileManager: FileManager = .default) {
        self.fileURL = directory.appendingPathComponent(SessionStore.filename)
        self.fileManager = fileManager
    }

    func load() -> SessionRecord? {
        lock.withLock {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return try? KabbaISO8601.makeDecoder().decode(SessionRecord.self, from: data)
        }
    }

    func save(_ record: SessionRecord) throws {
        try lock.withLock {
            try FileSyncOperationStore.ensureProtectedDirectory(fileURL.deletingLastPathComponent(), fileManager: fileManager)
            try FileSyncOperationStore.writeProtected(try KabbaISO8601.makeEncoder().encode(record), to: fileURL)
        }
    }

    func clear() {
        lock.withLock { try? fileManager.removeItem(at: fileURL) }
    }
}

// MARK: - Credential storage seam (Keychain in the app, in-memory in tests)

protocol SessionCredentialStore: AnyObject {
    func read(_ key: String) -> String?
    func write(_ value: String, key: String) throws
    func remove(_ key: String)
}

final class InMemorySessionCredentialStore: SessionCredentialStore {
    private var values: [String: String] = [:]
    private let lock = NSLock()
    var failWrites = false

    init() {}

    func read(_ key: String) -> String? { lock.withLock { values[key] } }
    func write(_ value: String, key: String) throws {
        if failWrites { throw NSError(domain: "InMemorySessionCredentialStore", code: -1) }
        lock.withLock { values[key] = value }
    }
    func remove(_ key: String) { lock.withLock { values[key] = nil } }
}

/// One-time move of the bearer token from wherever an older build kept it
/// (plaintext UserDefaults, the app-private Keychain, the app-group defaults
/// copy the share extension read) into the ONE shared Keychain item.
enum SessionCredentialMigration {
    static let accessTokenKey = "access_token"

    struct LegacySource {
        let name: String
        let read: () -> String?
        let purge: () -> Void
    }

    struct Outcome: Equatable {
        var token: String?
        var migratedFrom: String?
        var purged: [String]
    }

    /// The shared store wins when it already holds a token; otherwise the first legacy
    /// value is written there. A legacy copy is purged ONLY once the shared write
    /// succeeded (or the shared store already had the token) — a Keychain failure can
    /// never log an existing user out.
    static func run(shared: SessionCredentialStore, legacy: [LegacySource]) -> Outcome {
        var outcome = Outcome(token: shared.read(accessTokenKey), migratedFrom: nil, purged: [])

        if outcome.token == nil {
            for source in legacy {
                if let value = source.read(), !value.isEmpty {
                    do {
                        try shared.write(value, key: accessTokenKey)
                        outcome.token = value
                        outcome.migratedFrom = source.name
                        break
                    } catch {
                        // Keep every legacy copy and keep the app working with the legacy value;
                        // the move is retried on the next read.
                        outcome.token = value
                        return outcome
                    }
                }
            }
        }

        guard outcome.token != nil else { return outcome }

        for source in legacy where source.read() != nil {
            source.purge()
            outcome.purged.append(source.name)
        }
        return outcome
    }
}
