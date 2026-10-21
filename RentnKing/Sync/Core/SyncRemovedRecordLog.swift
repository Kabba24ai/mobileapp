//
//  SyncRemovedRecordLog.swift
//  RentnKing — Sync Core (Foundation only)
//
//  A short, content-free trace of the records a person removed from the Sync
//  queue (MOBILE-QUALITY-01, item 01). Removal deletes the record and its files
//  — answers, photos, signatures and license images are NOT archived: keeping
//  customer documents on a phone after the employee chose to delete them is
//  exactly what we must not do. What stays, for 30 days, is enough to answer
//  "where did that record go?":
//
//      what it was (title, type, order / line references), when it was
//      captured, why Kabba refused it (code, request id), what it held
//      (counts only: "12 checklist answers · 3 photos"), who removed it, when.
//
//  The office keeps its own record of the refusal (Mobile Sync Issues), which
//  this log never replaces.
//

import Foundation

struct SyncRemovedRecord: Codable, Equatable, Identifiable {
    var id: String { operationId }
    let operationId: String
    let type: String
    let title: String
    let identitySummary: String
    let capturedAt: Date
    let removedAt: Date
    /// The signed-in employee who removed it (id + display name), when known.
    let removedByUserId: String?
    let removedByName: String?
    /// The state it was in when removed (needs_attention / pending).
    let stateWhenRemoved: SyncState
    let errorCode: String?
    let requestId: String?
    /// Counts only, e.g. "12 checklist answers · 3 photos · a signature".
    let contentsSummary: String
    /// Kabba's HTTP answer when it refused it (nil = Kabba never answered). Additive.
    var statusCode: Int? = nil
    /// Why it went, when it was not a review decision (e.g. replaced by a newer copy). Additive.
    var reason: String? = nil

    /// What can be said about Kabba for this record, from what was stored when it was removed.
    var kabbaLine: String {
        if stateWhenRemoved == .needsAttention {
            return statusCode != nil || errorCode != nil ? "Kabba refused it\(errorCode.map { " (\($0))" } ?? "")." : "This phone could not send it."
        }
        return "Kabba had not confirmed it."
    }

    static func of(_ op: SyncOperation, removedAt: Date, byUserId: String?, byName: String?, reason: String? = nil) -> SyncRemovedRecord {
        SyncRemovedRecord(operationId: op.id,
                          type: op.type,
                          title: op.displayTitle ?? op.type,
                          identitySummary: op.identity.summary,
                          capturedAt: op.capturedAt,
                          removedAt: removedAt,
                          removedByUserId: byUserId,
                          removedByName: byName,
                          stateWhenRemoved: op.state,
                          errorCode: op.attempts.lastErrorCode,
                          requestId: op.attempts.lastRequestId,
                          contentsSummary: SyncRecordContents.of(op).summary,
                          statusCode: op.attempts.lastStatusCode,
                          reason: reason)
    }
}

/// File-backed, bounded, newest-first. Thread-safe; every call reads and writes the file
/// under one lock, so the log on disk is always the truth.
final class SyncRemovedRecordLog {

    static let retention: TimeInterval = 30 * 24 * 3600
    static let capacity = 100

    private let fileURL: URL
    private let lock = NSLock()
    private let clock: () -> Date

    init(directory: URL, clock: @escaping () -> Date = { Date() }) {
        self.fileURL = directory.appendingPathComponent("removed-records.json")
        self.clock = clock
    }

    /// Records within the retention window, newest first.
    func entries() -> [SyncRemovedRecord] {
        lock.lock(); defer { lock.unlock() }
        return pruned(read())
    }

    func append(_ record: SyncRemovedRecord) throws {
        lock.lock(); defer { lock.unlock() }
        var all = read().filter { $0.operationId != record.operationId }
        all.insert(record, at: 0)
        try write(pruned(all))
    }

    private func pruned(_ records: [SyncRemovedRecord]) -> [SyncRemovedRecord] {
        let cutoff = clock().addingTimeInterval(-Self.retention)
        return Array(records
            .filter { $0.removedAt >= cutoff }
            .sorted { $0.removedAt > $1.removedAt }
            .prefix(Self.capacity))
    }

    private func read() -> [SyncRemovedRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SyncRemovedRecord].self, from: data)) ?? []
    }

    private func write(_ records: [SyncRemovedRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileSyncOperationStore.writeProtected(try encoder.encode(records), to: fileURL)
    }
}
