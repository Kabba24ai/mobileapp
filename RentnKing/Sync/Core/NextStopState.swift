//
//  NextStopState.swift
//  RentnKing — Sync Core (Foundation only)
//
//  A driver's workday is a chain of destinations. Dispatch already owns every
//  CANONICAL destination — an order leg (delivery/return) and a Manual Dispatch
//  task each have their own record, assignment and lifecycle — so Next Stop
//  never copies those. The ONE stop Dispatch does not model is the trip back to
//  a shop, and that is all this state represents.
//
//  It is pure workflow state, not a queued server operation: nothing here is
//  submitted, retried or reconciled, and no Sync Engine handler reads it. The
//  timestamps are recorded because the driver's own actions produced them (and
//  Phase 2 Driver Performance may later read them), but Phase 1 ships no
//  analytics and nothing depends on them.
//
//  Codable uses an EXPLICIT "kind" discriminator rather than compiler-
//  synthesized enum payload keys: this file is written by one app version and
//  read by the next, and an unrecognised kind decodes as `.idle` so a downgrade
//  can never strand a driver in a state it cannot parse.
//

import Foundation

/// The shop a driver is driving back to, snapshotted from the tenant's own
/// active store list at the moment of choosing. Snapshotted (not referenced by
/// id alone) so the destination still reads correctly offline and after the
/// cached store list is refreshed.
public struct NextStopShop: Codable, Equatable {
    public let uniqueId: String
    public let name: String
    public let fullAddress: String

    public init(uniqueId: String, name: String, fullAddress: String) {
        self.uniqueId = uniqueId
        self.name = name
        self.fullAddress = fullAddress
    }
}

/// Where the driver is in a shop stop. `.idle` means there is no shop stop —
/// either the driver has not chosen one, or they have moved on to a real
/// Dispatch mission.
public enum NextStopState: Equatable {
    case idle
    case shopSelected(shop: NextStopShop, selectedAt: Date)
    case arrivedAtShop(shop: NextStopShop, selectedAt: Date, arrivedAt: Date)

    /// The shop this stop is about, if any.
    public var shop: NextStopShop? {
        switch self {
        case .idle:
            return nil
        case let .shopSelected(shop, _):
            return shop
        case let .arrivedAtShop(shop, _, _):
            return shop
        }
    }
}

/// The only legal moves. Written as pure functions so the rules are testable
/// without a disk, a screen or a tenant.
public enum NextStopTransition {

    /// The driver picked a shop. A second choice REPLACES the first — a driver
    /// who changes their mind has one shop stop, never two.
    public static func selectShop(_ shop: NextStopShop, at date: Date) -> NextStopState {
        return .shopSelected(shop: shop, selectedAt: date)
    }

    /// The driver says they are there. Only a selected shop can be arrived at:
    /// `.idle` has no shop to arrive at, and an already-recorded arrival keeps
    /// its first timestamp so a second tap cannot move it.
    public static func arrive(_ state: NextStopState, at date: Date) -> NextStopState {
        switch state {
        case let .shopSelected(shop, selectedAt):
            return .arrivedAtShop(shop: shop, selectedAt: selectedAt, arrivedAt: date)
        case .idle, .arrivedAtShop:
            return state
        }
    }

    /// The shop stop is over — the driver chose a real Dispatch mission. Always
    /// `.idle`: the mission itself is canonical Dispatch work and carries no
    /// Next Stop state.
    public static func finishShopStop(_ state: NextStopState) -> NextStopState {
        return .idle
    }
}

// MARK: - Explicit Codable

extension NextStopState: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind, shop, selectedAt, arrivedAt
    }

    private enum Kind: String {
        case idle, shopSelected, arrivedAtShop
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try c.encode(Kind.idle.rawValue, forKey: .kind)
        case let .shopSelected(shop, selectedAt):
            try c.encode(Kind.shopSelected.rawValue, forKey: .kind)
            try c.encode(shop, forKey: .shop)
            try c.encode(selectedAt, forKey: .selectedAt)
        case let .arrivedAtShop(shop, selectedAt, arrivedAt):
            try c.encode(Kind.arrivedAtShop.rawValue, forKey: .kind)
            try c.encode(shop, forKey: .shop)
            try c.encode(selectedAt, forKey: .selectedAt)
            try c.encode(arrivedAt, forKey: .arrivedAt)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .kind) ?? Kind.idle.rawValue

        // An unknown kind, or a payload a newer version shaped differently, is
        // read as "no shop stop" rather than throwing.
        guard let kind = Kind(rawValue: raw) else { self = .idle; return }

        switch kind {
        case .idle:
            self = .idle
        case .shopSelected:
            guard let shop = try c.decodeIfPresent(NextStopShop.self, forKey: .shop),
                  let selectedAt = try c.decodeIfPresent(Date.self, forKey: .selectedAt) else {
                self = .idle; return
            }
            self = .shopSelected(shop: shop, selectedAt: selectedAt)
        case .arrivedAtShop:
            guard let shop = try c.decodeIfPresent(NextStopShop.self, forKey: .shop),
                  let selectedAt = try c.decodeIfPresent(Date.self, forKey: .selectedAt),
                  let arrivedAt = try c.decodeIfPresent(Date.self, forKey: .arrivedAt) else {
                self = .idle; return
            }
            self = .arrivedAtShop(shop: shop, selectedAt: selectedAt, arrivedAt: arrivedAt)
        }
    }
}
