//
//  SyncPassReport.swift
//  RentnKing — Sync Core (Foundation only)
//
//  What one Sync Now actually did (MOBILE-QUALITY-01, item 02). Before this,
//  Sync Now only kicked the engine: when everything left was a permanent
//  rejection nothing was sent, nothing changed on screen, and the button looked
//  dead. The report compares the queue before and after the pass and says, in
//  employee terms:
//
//      • what reached Kabba during this Sync Now;
//      • what Kabba refused during this Sync Now;
//      • what is still waiting for a connection;
//      • what failed temporarily and will retry by itself (and when);
//      • what needs a person (rejected earlier — Sync Now never resends those);
//      • when sending is paused (sign in / update the app).
//
//  Pure: built from operation snapshots, so it is unit-testable.
//

import Foundation

struct SyncPassReport: Equatable {
    /// Records that reached Kabba during this pass.
    var sent = 0
    /// Records Kabba refused during this pass (now Needs Attention).
    var rejectedNow = 0
    /// Records this phone could not send during this pass (parked without an answer from Kabba).
    var parkedNow = 0
    /// Not sent: the last attempt could not reach Kabba.
    var waitingForConnection = 0
    /// Not sent: Kabba failed temporarily; the engine retries by itself.
    var temporaryFailures = 0
    /// Not sent yet for another reason (queued behind a failure, never tried).
    var stillQueued = 0
    /// Still being sent (a large upload continuing in the background).
    var inProgress = 0
    /// Every rejected record now on the phone, including those refused during this pass.
    var needsAttention = 0
    /// Earliest automatic retry among the waiting records.
    var nextRetryAt: Date?
    var pause: SyncPause = .none
    /// The pass did not finish before the screen stopped waiting for it.
    var timedOut = false

    var waiting: Int { waitingForConnection + temporaryFailures + stillQueued }

    /// True when nothing was eligible to send (everything left needs a person, or nothing was there).
    var nothingToSend: Bool {
        sent == 0 && rejectedNow == 0 && parkedNow == 0 && waiting == 0 && inProgress == 0
    }

    // MARK: Build

    /// - Parameters:
    ///   - before: every record's state just before the pass.
    ///   - after: every record just after it.
    static func make(before: [String: SyncState], after: [SyncOperation], pause: SyncPause, timedOut: Bool = false) -> SyncPassReport {
        var r = SyncPassReport()
        r.pause = pause
        r.timedOut = timedOut
        for op in after {
            let was = before[op.id]
            switch op.state {
            case .synced:
                if was != nil && was != .synced { r.sent += 1 }
            case .needsAttention:
                r.needsAttention += 1
                if was != nil && was != .needsAttention {
                    if op.attempts.lastStatusCode == nil { r.parkedNow += 1 } else { r.rejectedNow += 1 }
                }
            case .syncing:
                r.inProgress += 1
            case .pending:
                switch SyncRecordProblem.of(op) {
                case .waitingForConnection: r.waitingForConnection += 1
                case .temporaryFailure:     r.temporaryFailures += 1
                default:                    r.stillQueued += 1
                }
                if let gate = op.attempts.nextAttemptAt, r.nextRetryAt.map({ gate < $0 }) ?? true {
                    r.nextRetryAt = gate
                }
            case .superseded:
                break
            }
        }
        // A pass stops at the first failure that is not the record's fault, so whatever
        // was queued behind it is held by the same cause.
        if r.waitingForConnection > 0 {
            r.waitingForConnection += r.stillQueued
            r.stillQueued = 0
        } else if r.temporaryFailures > 0 {
            r.temporaryFailures += r.stillQueued
            r.stillQueued = 0
        }
        return r
    }

    // MARK: Employee wording

    /// The headline: one short sentence.
    var headline: String {
        if pause == .authentication { return "Sync is paused — sign in again to send." }
        if pause == .appUpdate { return "Sync is paused — update the app to send." }
        if nothingToSend && !timedOut {
            return needsAttention > 0 ? "Nothing new to send." : "Nothing waiting to send — everything is synced."
        }
        if timedOut || inProgress > 0 {
            return sent > 0 ? "Sent \(Self.records(sent)) — still sending the rest." : "Still sending…"
        }
        if sent > 0 { return "Sent \(Self.records(sent)) to Kabba." }
        if waitingForConnection > 0 { return "Couldn't reach Kabba." }
        if temporaryFailures > 0 { return "Kabba is temporarily unavailable." }
        if rejectedNow > 0 { return "Kabba refused \(Self.records(rejectedNow))." }
        if parkedNow > 0 { return "This phone could not send \(Self.records(parkedNow))." }
        return "Nothing was sent yet."
    }

    /// Supporting lines, most important first. `timeFormatter` renders `nextRetryAt`.
    func lines(timeFormatter: (Date) -> String) -> [String] {
        var out: [String] = []
        let refusalIsHeadline = headline.hasPrefix("Kabba refused")
        if rejectedNow > 0 && !refusalIsHeadline {
            out.append("Kabba refused \(Self.records(rejectedNow)) during this sync.")
        }
        if parkedNow > 0 && !headline.hasPrefix("This phone could not send") {
            out.append("This phone could not send \(Self.records(parkedNow)) during this sync.")
        }
        if inProgress > 0 {
            out.append("\(Self.records(inProgress)) still uploading — \(inProgress == 1 ? "it finishes" : "they finish") in the background.")
        }
        if waitingForConnection > 0 {
            out.append("\(Self.records(waitingForConnection)) waiting for a connection. \(waitingForConnection == 1 ? "It is" : "They are") saved on this phone and will send automatically.")
        }
        if temporaryFailures > 0 {
            var line = "\(Self.records(temporaryFailures)) failed temporarily and will retry automatically"
            if let next = nextRetryAt { line += " (next try \(timeFormatter(next)))" }
            out.append(line + ".")
        }
        if stillQueued > 0 { out.append("\(Self.records(stillQueued)) still queued to send.") }
        if needsAttention > 0 {
            let them = needsAttention == 1 ? "it" : "them"
            out.append("\(Self.records(needsAttention)) need\(needsAttention == 1 ? "s" : "") your attention. Sync Now does not resend \(them) — a person decides. Tap a record to review it.")
        }
        return out
    }

    static func records(_ n: Int) -> String {
        let word = n == 1 ? "record" : "records"
        return "\(n) \(word)"
    }
}
