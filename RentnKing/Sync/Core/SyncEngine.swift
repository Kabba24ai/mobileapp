//
//  SyncEngine.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The canonical offline synchronization subsystem.
//
//  Invariants:
//   • enqueue() returns only after the operation is durably on disk — the UI
//     may say "Saved" the moment it returns.
//   • Every operation carries an operation_id generated ONCE; retries, app
//     restarts and reboots reuse it, so Laravel executes each operation once.
//   • Retry exhaustion never destroys data. Temporary failures back off and
//     retry forever; permanent rejections park the operation as Needs
//     Attention with its payload, files and timestamps intact; only an explicit
//     person-initiated discard removes a record.
//   • A 401 pauses sending until authentication is restored; a 426 pauses
//     until the app is updated. Operations stay stored either way.
//   • The store is the truth. Triggers (app active, connectivity, timers,
//     background refresh) only call kick(); a missed trigger is harmless
//     because the next launch reloads the queue and drains it.
//
//  All state is confined to one serial queue; public reads hop onto it.
//

import Foundation

enum SyncEngineEvent: Equatable {
    case operationChanged(SyncOperation)
    case pauseChanged(SyncPause)
    /// A drain pass ended (queue empty, paused, or waiting for backoff).
    case drainFinished
}

enum SyncEngineError: Error, Equatable {
    case unknownOperation(String)
    case payloadMustBeObject
    case calledOnEngineQueue
}

final class SyncEngine {

    let store: SyncOperationStore
    let httpClient: SyncHTTPClient
    let policy: SyncRetryPolicy

    /// Invoked on the engine queue. App layer hops to main and re-posts as needed.
    var eventHandler: ((SyncEngineEvent) -> Void)?
    /// Sanitized diagnostic lines ("[sync] driver_checklist.update 3F… → synced"). Never payloads.
    var logger: ((String) -> Void)?

    private var handlers: [String: SyncOperationHandler] = [:]
    private var operations: [String: SyncOperation] = [:]
    private var _pause: SyncPause = .none
    private var draining = false
    private var retryTimer: DispatchWorkItem?

    private let clock: () -> Date
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Bool>()

    init(store: SyncOperationStore,
         httpClient: SyncHTTPClient,
         handlers: [SyncOperationHandler] = [],
         policy: SyncRetryPolicy = .default,
         clock: @escaping () -> Date = { Date() },
         queueLabel: String = "ai.kabba.sync.engine") {
        self.store = store
        self.httpClient = httpClient
        self.policy = policy
        self.clock = clock
        self.queue = DispatchQueue(label: queueLabel, qos: .utility)
        self.queue.setSpecific(key: queueKey, value: true)
        for handler in handlers {
            self.handlers[handler.operationType] = handler
        }
        loadFromStore()
    }

    // MARK: - Registration

    func register(_ handler: SyncOperationHandler) {
        onQueueSync { handlers[handler.operationType] = handler }
    }

    // MARK: - Public API

    /// Durably records a new operation and schedules a sync attempt. Returns after the
    /// record is on disk. Must not be called from the engine queue.
    @discardableResult
    func enqueue(type: String,
                 payload: JSONValue,
                 identity: SyncBusinessIdentity = SyncBusinessIdentity(),
                 capturedAt: Date,
                 assets: [SyncAsset] = [],
                 displayTitle: String? = nil,
                 operationId: String = UUID().uuidString) throws -> SyncOperation {
        guard case .object = payload else { throw SyncEngineError.payloadMustBeObject }
        guard !isOnQueue else { throw SyncEngineError.calledOnEngineQueue }

        let operation = SyncOperation(id: operationId,
                                      type: type,
                                      capturedAt: capturedAt,
                                      queuedAt: clock(),
                                      identity: identity,
                                      payload: payload,
                                      assets: assets,
                                      displayTitle: displayTitle)

        try queue.sync {
            try store.save(operation)              // durable BEFORE we return
            operations[operation.id] = operation
        }
        log("queued \(operation.type) \(short(operation.id))")
        emit(.operationChanged(operation))
        kick(reason: "enqueue")
        return operation
    }

    /// Ask the engine to drain now. `ignoreBackoff` clears retry gates first — use it for
    /// real-world triggers (connectivity restored, app became active), not for timers.
    func kick(reason: String, ignoreBackoff: Bool = false) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if ignoreBackoff {
                for (id, var op) in self.operations where op.state == .pending && op.attempts.nextAttemptAt != nil {
                    op.attempts.nextAttemptAt = nil
                    self.operations[id] = op
                    self.persistQuietly(op)
                }
            }
            self.log("kick (\(reason))")
            self.drain()
        }
    }

    /// A person chose to retry a Needs Attention operation (or force a pending one).
    func retryNow(operationId: String) {
        queue.async { [weak self] in
            guard let self = self, var op = self.operations[operationId] else { return }
            guard op.state == .needsAttention || op.state == .pending else { return }
            op.state = .pending
            op.attentionReason = nil
            op.attempts.nextAttemptAt = nil
            self.operations[operationId] = op
            self.persistQuietly(op)
            self.emit(.operationChanged(op))
            self.log("retry requested \(self.short(operationId))")
            self.drain()
        }
    }

    /// Explicit, person-initiated removal. The ONLY path that deletes an un-synced operation.
    func discard(operationId: String) throws {
        try onQueueSync {
            guard operations[operationId] != nil else { throw SyncEngineError.unknownOperation(operationId) }
            try store.delete(id: operationId)
            operations[operationId] = nil
            log("discarded \(short(operationId))")
        }
    }

    func authenticationLost() {
        queue.async { [weak self] in self?.setPause(.authentication) }
    }

    func authenticationRestored() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self._pause == .authentication { self.setPause(.none) }
            for (id, var op) in self.operations where op.state == .pending {
                op.attempts.nextAttemptAt = nil
                self.operations[id] = op
                self.persistQuietly(op)
            }
            self.drain()
        }
    }

    func appUpdated() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self._pause == .appUpdate { self.setPause(.none) }
            self.drain()
        }
    }

    var pause: SyncPause { onQueueSync { _pause } }

    func snapshot() -> [SyncOperation] {
        onQueueSync { operations.values.sorted { $0.queuedAt < $1.queuedAt } }
    }

    func operation(id: String) -> SyncOperation? {
        onQueueSync { operations[id] }
    }

    func summary() -> SyncSummary {
        onQueueSync { SyncDiagnostics.summary(of: Array(operations.values), pause: _pause) }
    }

    func diagnostics() -> [SyncDiagnosticEntry] {
        onQueueSync { SyncDiagnostics.entries(Array(operations.values)) }
    }

    /// Removes acknowledged operations older than the retention window. Never touches
    /// pending / needs-attention records.
    func pruneSynced(now: Date? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let cutoff = (now ?? self.clock()).addingTimeInterval(-self.policy.syncedRetention)
            for (id, op) in self.operations where op.state == .synced {
                if let acked = op.acknowledgment?.acknowledgedAt, acked < cutoff {
                    try? self.store.delete(id: id)
                    self.operations[id] = nil
                }
            }
        }
    }

    // MARK: - Drain loop (engine queue only)

    private func drain() {
        guard !draining else { return }
        guard _pause == .none else { emit(.drainFinished); return }

        let now = clock()
        guard var op = nextEligible(now: now) else {
            emit(.drainFinished)
            scheduleRetryTimer()
            return
        }

        guard let handler = handlers[op.type] else {
            var failed = op
            applyFailure(&failed, APIError.invalidRequest("No handler for operation type \(op.type)"), now: now)
            persistQuietly(failed)
            operations[failed.id] = failed
            emit(.operationChanged(failed))
            drain()
            return
        }

        draining = true
        op.state = .syncing
        op.attempts.attemptCount += 1
        op.attempts.lastAttemptedAt = now
        operations[op.id] = op
        persistQuietly(op)
        emit(.operationChanged(op))

        let request: SyncHTTPRequest
        do {
            request = try handler.makeRequest(for: op)
        } catch let error as SyncHandlerError {
            switch error {
            case .notAuthenticated(let why):
                // No session → keep the operation, pause everything until login.
                op.state = .pending
                op.attempts.lastErrorMessage = why
                op.attempts.lastDisposition = .waitForAuthentication
                operations[op.id] = op
                persistQuietly(op)
                emit(.operationChanged(op))
                draining = false
                setPause(.authentication)
                emit(.drainFinished)
            case .invalidPayload(let why):
                applyFailure(&op, APIError.invalidRequest(why), now: now)
                operations[op.id] = op
                persistQuietly(op)
                emit(.operationChanged(op))
                draining = false
                drain()
            }
            return
        } catch {
            applyFailure(&op, APIError.invalidRequest(error.localizedDescription), now: now)
            operations[op.id] = op
            persistQuietly(op)
            emit(.operationChanged(op))
            draining = false
            drain()
            return
        }

        let operationId = op.id
        log("sending \(op.type) \(short(operationId)) attempt \(op.attempts.attemptCount)")

        httpClient.perform(request) { [weak self] result in
            guard let self = self else { return }
            self.queue.async {
                self.handle(result, operationId: operationId, handler: handler)
            }
        }
    }

    private func handle(_ result: SyncHTTPResult, operationId: String, handler: SyncOperationHandler) {
        defer {
            draining = false
        }

        guard var op = operations[operationId] else {
            // Discarded while in flight — nothing to record.
            queue.async { [weak self] in self?.drain() }
            return
        }

        let now = clock()
        var continueDraining = true

        switch result {
        case .failure(let error):
            continueDraining = applyFailure(&op, error, now: now)

        case .response(let response):
            switch handler.interpret(response, for: op, now: now) {
            case .acknowledged(let ack):
                op.state = .synced
                op.acknowledgment = ack
                op.attentionReason = nil
                op.attempts.nextAttemptAt = nil
                op.attempts.lastStatusCode = ack.statusCode
                op.attempts.lastRequestId = ack.requestId
                op.attempts.lastErrorCode = nil
                op.attempts.lastErrorMessage = nil
                op.attempts.lastTransportFailure = nil
                op.attempts.lastDisposition = nil
                log("synced \(op.type) \(short(op.id))\(ack.replayed ? " (replayed)" : "")")
            case .failed(let error):
                continueDraining = applyFailure(&op, error, now: now)
            }
        }

        operations[op.id] = op
        persistQuietly(op)
        emit(.operationChanged(op))

        if continueDraining {
            queue.async { [weak self] in self?.drain() }
        } else {
            emit(.drainFinished)
            scheduleRetryTimer()
        }
    }

    /// Records the failure on the operation and returns whether the drain should move on
    /// to the next operation (true) or stop and wait (false).
    @discardableResult
    private func applyFailure(_ op: inout SyncOperation, _ error: APIError, now: Date) -> Bool {
        op.attempts.lastStatusCode = error.statusCode
        op.attempts.lastErrorCode = error.code
        op.attempts.lastErrorMessage = error.message
        op.attempts.lastRequestId = error.requestId
        op.attempts.lastTransportFailure = error.transport

        let disposition = error.disposition
        op.attempts.lastDisposition = disposition

        switch disposition {
        case .retry:
            // Temporary: keep it, back off, and STOP this pass — the network/server is the
            // problem, not the operation, so hammering the next one helps nobody.
            op.state = .pending
            op.attempts.nextAttemptAt = now.addingTimeInterval(policy.delay(afterAttempt: op.attempts.attemptCount))
            log("retry later \(op.type) \(short(op.id)) — \(error.code ?? error.transport?.rawValue ?? "transport")")
            return false

        case .waitForAuthentication:
            op.state = .pending
            op.attempts.nextAttemptAt = nil
            setPause(.authentication)
            log("paused for authentication after \(short(op.id))")
            return false

        case .waitForAppUpdate:
            op.state = .pending
            op.attempts.nextAttemptAt = nil
            setPause(.appUpdate)
            log("paused for app update after \(short(op.id))")
            return false

        case .needsAttention:
            // Permanent: park it with everything intact; the queue keeps moving.
            op.state = .needsAttention
            op.attempts.nextAttemptAt = nil
            op.attentionReason = attentionReason(for: error)
            log("needs attention \(op.type) \(short(op.id)) — \(error.code ?? "HTTP \(error.statusCode ?? 0)")")
            return true
        }
    }

    private func attentionReason(for error: APIError) -> String {
        var reason = error.employeeMessage
        if let code = error.code, !reason.contains(code) {
            reason += " (\(code))"
        }
        if let first = error.validationErrors.values.first?.first {
            reason += " — \(first)"
        }
        return reason
    }

    /// Earliest pending operation whose backoff gate has opened. Operations sharing an
    /// ordering key (same order product, etc.) are only ever sent in capture order.
    private func nextEligible(now: Date) -> SyncOperation? {
        let pending = operations.values
            .filter { $0.state == .pending }
            .sorted { $0.queuedAt < $1.queuedAt }

        var seenKeys = Set<String>()
        for op in pending {
            let key = op.orderingKey
            let firstForKey = !seenKeys.contains(key)
            seenKeys.insert(key)
            guard firstForKey else { continue }
            if let gate = op.attempts.nextAttemptAt, gate > now { continue }
            return op
        }
        return nil
    }

    private func scheduleRetryTimer() {
        retryTimer?.cancel()
        retryTimer = nil
        guard _pause == .none else { return }

        let now = clock()
        let gates = operations.values
            .filter { $0.state == .pending }
            .compactMap { $0.attempts.nextAttemptAt }
        guard let earliest = gates.min() else { return }

        let delay = max(0.05, earliest.timeIntervalSince(now))
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.retryTimer = nil
            self.log("retry timer fired")
            self.drain()
        }
        retryTimer = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Persistence / bootstrap

    private func loadFromStore() {
        queue.sync {
            let loaded = (try? store.loadAll()) ?? []
            let now = clock()
            for var op in loaded {
                // A record still marked `.syncing` at launch was interrupted mid-request (the
                // process that owned it is gone). Re-sending is safe thanks to the operation id,
                // so it goes straight back to pending. `policy.staleSyncingTimeout` is only
                // consulted for the diagnostic line — the reset is unconditional.
                if op.state == .syncing {
                    let age = op.attempts.lastAttemptedAt.map { now.timeIntervalSince($0) } ?? .infinity
                    log("recovering interrupted \(op.type) \(short(op.id)) (age \(Int(age.isFinite ? age : 0))s, stale after \(Int(policy.staleSyncingTimeout))s)")
                    op.state = .pending
                    op.attempts.nextAttemptAt = nil
                    persistQuietly(op)
                }
                operations[op.id] = op
            }
            log("loaded \(operations.count) operation(s) from store")
        }
    }

    private func persistQuietly(_ op: SyncOperation) {
        do {
            try store.save(op)
        } catch {
            log("persist failed for \(short(op.id)): \(error.localizedDescription)")
        }
    }

    private func setPause(_ pause: SyncPause) {
        guard _pause != pause else { return }
        _pause = pause
        emit(.pauseChanged(pause))
    }

    // MARK: - Utilities

    private var isOnQueue: Bool { DispatchQueue.getSpecific(key: queueKey) == true }

    private func onQueueSync<T>(_ body: () throws -> T) rethrows -> T {
        if isOnQueue { return try body() }
        return try queue.sync(execute: body)
    }

    private func emit(_ event: SyncEngineEvent) {
        eventHandler?(event)
    }

    private func log(_ line: String) {
        logger?("[sync] " + line)
    }

    private func short(_ id: String) -> String {
        String(id.prefix(8))
    }
}
