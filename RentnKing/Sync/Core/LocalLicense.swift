//
//  LocalLicense.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The driver's license this phone holds for an order (MOBILE-QUALITY-01, item 06).
//  The license screens used to show the order's SERVER record over the copy just
//  saved on this phone (an older or empty record replaced the local image), never
//  showed the expiration again, and queued two more uploads on every Save. The
//  phone's own record is the Sync Engine's license_media.upload operations, so:
//
//    • each side shows its LATEST local copy — Pending Sync, Needs Attention (kept
//      for review), or Synced with Kabba's own copy of the file — before anything
//      the order record says;
//    • the expiration and the auto-injection employee come from that copy;
//    • a Save only queues a side whose image changed, or whose expiration /
//      employee differs from what its latest copy carries; a side still WAITING
//      to send is replaced by the new copy instead of uploaded twice (Laravel
//      keeps one image per side — the last one — anyway).
//

import Foundation

struct LocalLicenseSide: Equatable {
    let side: String
    let operationId: String
    let state: SyncState
    /// The protected file while the phone still has it (removed once Kabba accepted it).
    let asset: SyncAsset?
    /// yyyy-MM-dd, when the save carried one.
    let expiryDate: String?
    let autoInjectBy: String?
    /// Kabba's copy of the file, from its acknowledgment (synced only).
    let serverMediaURL: String?

    /// The one-word state the screen shows beside the image.
    var statusLabel: String {
        switch state {
        case .pending, .syncing: return "Pending Sync"
        case .needsAttention:    return "Needs Attention"
        case .synced:            return "Synced"
        case .superseded:        return ""
        }
    }

    /// Still waiting to send and not in flight: a newer save of the same side may replace it.
    var isReplaceable: Bool { state == .pending }
}

enum LocalLicense {

    static let sides = ["front", "back"]

    /// The latest local copy of each side for this order (retired copies never count).
    static func sides(orderUniqueId: String, operations: [SyncOperation]) -> [String: LocalLicenseSide] {
        var out: [String: LocalLicenseSide] = [:]
        let ordered = operations
            .filter { $0.type == EffectiveFieldState.licenseMediaType && $0.identity.orderUniqueId == orderUniqueId && $0.state != .superseded }
            .sorted { $0.queuedAt < $1.queuedAt }
        for op in ordered {
            guard let side = op.payload["side"]?.stringValue?.lowercased(), sides.contains(side) else { continue }
            out[side] = LocalLicenseSide(
                side: side,
                operationId: op.id,
                state: op.state,
                asset: op.assets.first,
                expiryDate: nonEmpty(op.payload["license_expiry_date"]?.stringValue),
                autoInjectBy: nonEmpty(op.payload["auto_inject_by"]?.stringValue),
                serverMediaURL: nonEmpty(op.acknowledgment?.data?["media"]?["url"]?.stringValue))
        }
        return out
    }

    /// The expiration the phone holds for the license (the front's, else the back's).
    static func expiryDate(_ sides: [String: LocalLicenseSide]) -> String? {
        sides["front"]?.expiryDate ?? sides["back"]?.expiryDate
    }

    /// Which sides a Save must queue: a side whose image the employee changed, or — when
    /// the save carries an expiration / employee — a side whose latest copy does not carry
    /// exactly those. An unchanged side whose copy already says the same is never re-sent.
    static func sidesToQueue(changed: Set<String>,
                             expiryDate: String?,
                             autoInjectBy: String?,
                             existing: [String: LocalLicenseSide]) -> [String] {
        let expiry = nonEmpty(expiryDate)
        let employee = nonEmpty(autoInjectBy)
        return sides.filter { side in
            if changed.contains(side) { return true }
            guard let copy = existing[side] else {
                // Nothing on the phone for this side: only a save with license details sends it.
                return expiry != nil || employee != nil
            }
            if expiry == nil && employee == nil { return false }
            return copy.expiryDate != expiry || copy.autoInjectBy != employee
        }
    }

    /// The waiting copies a new save of `side` replaces (never one in flight, refused or synced).
    static func replacedBy(side: String, orderUniqueId: String, operations: [SyncOperation]) -> [String] {
        operations
            .filter { $0.type == EffectiveFieldState.licenseMediaType && $0.identity.orderUniqueId == orderUniqueId
                && $0.state == .pending && $0.payload["side"]?.stringValue?.lowercased() == side }
            .map(\.id)
    }

    /// "April 2028" from "2028-04-01"; nil when the value is not a date.
    static func displayExpiry(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = TimeZone(identifier: "UTC")
        parse.dateFormat = "yyyy-MM-dd"
        guard let date = parse.date(from: value) else { return nil }
        let show = DateFormatter()
        show.locale = Locale(identifier: "en_US_POSIX")
        show.timeZone = TimeZone(identifier: "UTC")
        show.dateFormat = "MMMM yyyy"
        return show.string(from: date)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }
}
