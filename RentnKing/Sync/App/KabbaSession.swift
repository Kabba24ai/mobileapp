//
//  KabbaSession.swift
//  RentnKing — Sync App layer (Foundation only)
//
//  Phase 5 — the app's view of its own session: the SessionRecord the server
//  described at login (persisted in the protected KabbaSync directory), the
//  offline rule, and the server-side revocation of THIS device's token on
//  logout. The token itself lives in KabbaSessionKeychain (shared with the
//  extension) behind UserDefaults.accessToken.
//

import Foundation

/// Sync Core seam: the shared Keychain IS the credential store.
extension KabbaSessionKeychain: SessionCredentialStore {}

enum KabbaSession {

    private(set) static var store: SessionStore?

    /// Called once from KabbaSync.bootstrap.
    static func configure(rootDirectory: URL) {
        store = SessionStore(directory: rootDirectory)
    }

    static var current: SessionRecord? { store?.load() }

    /// Login succeeded: remember what the server said about this session (never the token).
    @discardableResult
    static func start(loginResponse body: NSDictionary, now: Date = Date()) -> SessionRecord? {
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let record = SessionRecord.decode(loginResponse: data, now: now) else { return nil }
        try? store?.save(record)
        return record
    }

    /// An authenticated response carried X-Session-Expires-At (sliding expiry refreshed).
    static func noteServerContact(expiresAtHeader: String?, now: Date = Date()) {
        guard var record = current else { return }
        record.noteServerContact(expiresAtHeader: expiresAtHeader, at: now)
        try? store?.save(record)
    }

    /// Logout / server 401: forget the record. Queued operations are NOT touched.
    static func end() {
        store?.clear()
    }

    static func canCaptureOffline() -> Bool { OfflineSessionPolicy.canCaptureOffline(current) }

    static func statusLine(now: Date = Date()) -> String { OfflineSessionPolicy.statusLine(current, now: now) }

    /// Operations still waiting on the phone — quoted in the sign-in / update prompts so the
    /// employee knows nothing was lost.
    static func pendingWorkCount() -> Int {
        KabbaSync.engine?.summary().outstanding ?? 0
    }

    /// Best-effort revocation of THIS device's token before it is dropped locally. Fire-and-forget:
    /// the local sign-out never waits for (or depends on) the server.
    static func revokeCurrentOnServer(completion: ((Bool) -> Void)? = nil) {
        guard let client = KabbaSync.client else { completion?(false); return }
        client.send(method: "POST", path: "logout") { result in
            switch result {
            case .success(let response): completion?(response.isSuccessStatus)
            case .failure:               completion?(false)
            }
        }
    }
}
