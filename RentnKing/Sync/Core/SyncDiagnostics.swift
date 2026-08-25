//
//  SyncDiagnostics.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Sanitized, employee/developer-facing views of the queue. Never exposes
//  payload contents, images or credentials — only identities, states, times,
//  codes and a scrubbed error line.
//

import Foundation

enum SyncPause: String, Codable, Equatable {
    case none
    /// A 401 was received; nothing is sent until authenticationRestored().
    case authentication
    /// A 426 was received; nothing is sent until the app is updated.
    case appUpdate
}

struct SyncSummary: Equatable {
    var pending = 0
    var syncing = 0
    var synced = 0
    var needsAttention = 0
    var pause: SyncPause = .none

    var outstanding: Int { pending + syncing }
    var total: Int { pending + syncing + synced + needsAttention }

    /// "2 pending · 1 needs attention" / "All synced"
    var line: String {
        var parts: [String] = []
        if outstanding > 0 { parts.append("\(outstanding) pending") }
        if needsAttention > 0 { parts.append("\(needsAttention) need\(needsAttention == 1 ? "s" : "") attention") }
        if parts.isEmpty { return synced > 0 ? "All synced" : "Nothing to sync" }
        return parts.joined(separator: " · ")
    }
}

struct SyncDiagnosticEntry: Equatable, Identifiable {
    var id: String { operationId }
    let operationId: String
    let type: String
    let title: String
    let state: SyncState
    let capturedAt: Date
    let queuedAt: Date
    let attemptCount: Int
    let lastAttemptedAt: Date?
    let nextAttemptAt: Date?
    let lastStatusCode: Int?
    let lastErrorCode: String?
    let errorSummary: String?
    let lastRequestId: String?
    let identitySummary: String
    let acknowledgedAt: Date?
    let replayed: Bool
    let assetCount: Int

    /// Employee wording for the state.
    var stateLabel: String {
        switch state {
        case .pending, .syncing: return "Pending Sync"
        case .synced:            return "Synced"
        case .needsAttention:    return "Needs Attention"
        }
    }
}

enum SyncDiagnostics {

    static func summary(of operations: [SyncOperation], pause: SyncPause) -> SyncSummary {
        var s = SyncSummary()
        s.pause = pause
        for op in operations {
            switch op.state {
            case .pending:        s.pending += 1
            case .syncing:        s.syncing += 1
            case .synced:         s.synced += 1
            case .needsAttention: s.needsAttention += 1
            }
        }
        return s
    }

    /// Needs-attention first, then outstanding by capture time, then synced newest first.
    static func entries(_ operations: [SyncOperation]) -> [SyncDiagnosticEntry] {
        func rank(_ s: SyncState) -> Int {
            switch s {
            case .needsAttention: return 0
            case .syncing:        return 1
            case .pending:        return 2
            case .synced:         return 3
            }
        }
        return operations
            .sorted {
                let ra = rank($0.state), rb = rank($1.state)
                if ra != rb { return ra < rb }
                if $0.state == .synced { return $0.queuedAt > $1.queuedAt }
                return $0.queuedAt < $1.queuedAt
            }
            .map(entry(for:))
    }

    static func entry(for op: SyncOperation) -> SyncDiagnosticEntry {
        SyncDiagnosticEntry(operationId: op.id,
                            type: op.type,
                            title: op.displayTitle ?? op.type,
                            state: op.state,
                            capturedAt: op.capturedAt,
                            queuedAt: op.queuedAt,
                            attemptCount: op.attempts.attemptCount,
                            lastAttemptedAt: op.attempts.lastAttemptedAt,
                            nextAttemptAt: op.attempts.nextAttemptAt,
                            lastStatusCode: op.attempts.lastStatusCode,
                            lastErrorCode: op.attempts.lastErrorCode,
                            errorSummary: sanitize(op.attentionReason ?? op.attempts.lastErrorMessage),
                            lastRequestId: op.attempts.lastRequestId,
                            identitySummary: op.identity.summary,
                            acknowledgedAt: op.acknowledgment?.acknowledgedAt,
                            replayed: op.acknowledgment?.replayed ?? false,
                            assetCount: op.assets.count)
    }

    /// Scrubs anything credential-like from a free-text error and caps its length.
    static func sanitize(_ message: String?) -> String? {
        guard var text = message?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let patterns = [
            "(?i)bearer\\s+[A-Za-z0-9._~+/=-]+",     // bearer tokens
            "[A-Za-z0-9+/=_-]{40,}",                   // long opaque tokens / base64 blobs
            "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", // emails
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "[redacted]")
            }
        }
        if text.count > 240 {
            text = String(text.prefix(240)) + "…"
        }
        return text
    }
}
