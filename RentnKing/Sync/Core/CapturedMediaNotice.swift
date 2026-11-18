//
//  CapturedMediaNotice.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Customer-site bounce fix (2026-11-13): the Photo/Video screen must never make
//  media this phone saved look missing just because it is still on its way to
//  Kabba. The grid shows the server's copy plus files the Sync Engine still
//  holds; a file Kabba has acknowledged is removed from the phone, so until the
//  screen's order copy is refreshed the grid can be empty for a line whose video
//  WAS captured. This is the ONE line under each equipment heading that says
//  where that line's captured media stands, from the durable operations:
//
//      Video saved on this phone · uploads automatically   (pending / syncing)
//      Video saved on this phone · office review needed    (needs attention)
//      Video received by Kabba                              (synced, not yet in this copy)
//
//  Videos outrank photos (Delivery requires a video), healthy work outranks
//  parked work, and nothing is shown when the screen's copy already holds the
//  media or nothing was captured. Never claims more than the records say.
//

import Foundation

struct CapturedMediaNotice: Equatable {

    enum Stage: Equatable {
        /// Durably on this phone, waiting for (or in) an upload.
        case savedOnPhone
        /// Kabba refused it terminally; the driver's work stands, the office reconciles.
        case needsAttention
        /// Kabba acknowledged it; the screen's order copy just predates it.
        case receivedByKabba
    }

    let stage: Stage
    let isVideo: Bool

    var text: String {
        let noun = isVideo ? "Video" : "Photo"
        switch stage {
        case .savedOnPhone:    return "\(noun) saved on this phone · uploads automatically"
        case .needsAttention:  return "\(noun) saved on this phone · office review needed"
        case .receivedByKabba: return "\(noun) received by Kabba"
        }
    }

    /// The notice for ONE order product on ONE leg, or nil when there is nothing to say.
    /// - `serverCopyHasVideo` / `serverCopyHasMedia`: what the screen's order copy already shows
    ///   for this line (its delivery or pickup media items).
    static func notice(operations: [SyncOperation],
                       orderUniqueId: String,
                       orderProductUniqueId: String,
                       kind: MediaKind,
                       serverCopyHasVideo: Bool,
                       serverCopyHasMedia: Bool) -> CapturedMediaNotice? {
        guard kind != .license, !orderUniqueId.isEmpty, !orderProductUniqueId.isEmpty else { return nil }

        let captured = operations.filter { op in
            op.type == kind.operationType
                && op.identity.orderUniqueId == orderUniqueId
                && op.identity.orderProductUniqueId == orderProductUniqueId
                && EffectiveFieldState.countsAsDurableEvidence(op.state)
        }
        guard !captured.isEmpty else { return nil }

        func isVideo(_ op: SyncOperation) -> Bool { op.assets.contains { $0.mimeType.hasPrefix("video/") } }

        // Videos first: on Delivery the video is the requirement; a photo beside it changes nothing.
        for videoPass in [true, false] {
            let pass = captured.filter { isVideo($0) == videoPass }
            guard !pass.isEmpty else { continue }
            if pass.contains(where: { $0.state == .pending || $0.state == .syncing }) {
                return CapturedMediaNotice(stage: .savedOnPhone, isVideo: videoPass)
            }
            if pass.contains(where: { $0.state == .needsAttention }) {
                return CapturedMediaNotice(stage: .needsAttention, isVideo: videoPass)
            }
            // Only synced records remain: say so only while the screen's copy cannot show them.
            let copyShowsIt = videoPass ? serverCopyHasVideo : serverCopyHasMedia
            if pass.contains(where: { $0.state == .synced }), !copyShowsIt {
                return CapturedMediaNotice(stage: .receivedByKabba, isVideo: videoPass)
            }
            if videoPass { return nil } // the copy already shows the video — photos add nothing to say
        }
        return nil
    }
}
