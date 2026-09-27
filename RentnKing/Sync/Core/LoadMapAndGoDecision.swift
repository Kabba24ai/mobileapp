//
//  LoadMapAndGoDecision.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Driver Delivery Process Flow (2026-09-27), spec §8 — Load Map & Go records
//  On My Way FIRST (a durable driver_checklist.update, identical online and
//  offline; the assignment locks on this phone at that moment) and only then
//  navigates. With service, Apple Maps opens separately and Kabba stays on the
//  Driver Checklist in the On My Way state. Without service — or when the
//  address cannot be geocoded — the Service Offline state is shown in the
//  app's own offline language: the status is saved, it will sync, the map
//  button stays so the driver can retry once service returns. Never a pretend
//  map, never a block, never a second store.
//

import Foundation

enum LoadMapAndGoDecision {

    enum Outcome: Equatable {
        /// Open the destination in Apple Maps.
        case openMaps
        /// Show the Service Offline alert; keep the map button for a retry.
        case serviceOffline
    }

    static func outcome(reachable: Bool) -> Outcome {
        reachable ? .openMaps : .serviceOffline
    }

    static let serviceOfflineTitle = "Service Offline"
    static let serviceOfflineMessage = "Navigation needs cellular or Wi-Fi service. Your On My Way status is saved on this phone and will sync automatically."
}
