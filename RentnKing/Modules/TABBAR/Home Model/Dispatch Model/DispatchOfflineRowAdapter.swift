//
//  DispatchOfflineRowAdapter.swift
//  RentnKing
//
//  Dispatch offline (Phase 3): a cached mission package's `dispatch.row` is
//  the SAME row the live Dispatch feed serves (Laravel builds both from one
//  mapping, parity-tested), so it maps through the unchanged SchedulesModel —
//  the Dispatch card, Driver Checklist and Assign Driver screen read it exactly
//  as they read a feed row.
//

import Foundation
import ObjectMapper

enum DispatchOfflineRowAdapter {

    static func schedulesModel(from row: JSONValue) -> SchedulesModel? {
        guard case .object = row, let json = row.anyValue as? [String: Any] else { return nil }
        return Mapper<SchedulesModel>().map(JSON: json)
    }
}
