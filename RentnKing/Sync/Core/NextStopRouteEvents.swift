//
//  NextStopRouteEvents.swift
//  RentnKing — Sync Core (Foundation only)
//
//  Next Stop route events (2026-10-20). The driver's answers on the Next Stop
//  screen — the next mission they chose, Return to Shop, Arrived at <shop> —
//  are the evidence Kabba's Driver Efficiency report uses to rebuild the route
//  the driver actually drove (Customer A → Customer B, Customer → Store,
//  Store → Customer). Phase 1 kept them on the phone; this synchronizes them.
//
//  Each answer is ONE Sync Engine operation (next_stop.event): durable on the
//  phone before anything else happens, sent whenever there is signal, with the
//  moment the driver actually tapped as captured_at, and idempotent on the
//  server by operation id — so an offline stretch, a retry or a replay records
//  each answer exactly once, in the order the driver gave them.
//
//  Record-only. Nothing here changes a mission, a checklist, an assignment or
//  the shop stop itself (NextStopState stays local workflow state); the server
//  stores the answer as history and nothing else.
//

import Foundation

/// A place a Next Stop answer names, the way the backend identifies it.
public enum NextStopPlace: Equatable {
    /// An order line's Delivery or Return leg.
    case orderLeg(orderProductUniqueId: String, isReturn: Bool)
    /// A Manual Dispatch task.
    case manualTask(uniqueId: String)
    /// A shop (one of the tenant's stores).
    case shop(storeUniqueId: String)

    var wireType: String {
        switch self {
        case .orderLeg:   return "order_product"
        case .manualTask: return "manual_task"
        case .shop:       return "store"
        }
    }

    var wireUniqueId: String {
        switch self {
        case let .orderLeg(id, _):  return id
        case let .manualTask(id):   return id
        case let .shop(id):         return id
        }
    }

    var wireLeg: String? {
        guard case let .orderLeg(_, isReturn) = self else { return nil }
        return isReturn ? "return" : "delivery"
    }

    var isShop: Bool {
        if case .shop = self { return true }
        return false
    }
}

/// One answer the driver gave on the Next Stop screen.
public struct NextStopRouteEvent: Equatable {

    public enum Kind: String {
        case nextMission = "next_mission"
        case returnToShop = "return_to_shop"
        case arrivedAtShop = "arrived_at_shop"
    }

    public let kind: Kind
    /// Where the driver was: the mission just finished, or the shop they are at.
    public let from: NextStopPlace?
    /// Where they said they were going.
    public let to: NextStopPlace
    /// A mission chosen while still heading to a shop that was never reached.
    public let headingToShop: Bool
    /// When the driver tapped (the phone's clock).
    public let occurredAt: Date

    /// "Next Customer / Mission" → the mission the driver chose. nil for a shop.
    public static func nextMission(from: NextStopPlace?, to: NextStopPlace, headingToShop: Bool, at: Date) -> NextStopRouteEvent? {
        guard !to.isShop, !to.wireUniqueId.isEmpty else { return nil }
        return NextStopRouteEvent(kind: .nextMission, from: from, to: to, headingToShop: headingToShop, occurredAt: at)
    }

    /// "Return to Shop" → the shop the driver chose.
    public static func returnToShop(from: NextStopPlace?, shopUniqueId: String, at: Date) -> NextStopRouteEvent? {
        guard !shopUniqueId.isEmpty else { return nil }
        return NextStopRouteEvent(kind: .returnToShop, from: from, to: .shop(storeUniqueId: shopUniqueId), headingToShop: false, occurredAt: at)
    }

    /// "Arrived at <shop>".
    public static func arrivedAtShop(shopUniqueId: String, at: Date) -> NextStopRouteEvent? {
        guard !shopUniqueId.isEmpty else { return nil }
        return NextStopRouteEvent(kind: .arrivedAtShop, from: nil, to: .shop(storeUniqueId: shopUniqueId), headingToShop: false, occurredAt: at)
    }

    /// The JSON body (captured_at and operation_id are added from the operation itself).
    var payload: [String: JSONValue] {
        var body: [String: JSONValue] = [
            "event": .string(kind.rawValue),
            "to_type": .string(to.wireType),
            "to_unique_id": .string(to.wireUniqueId),
            "heading_to_shop": .bool(headingToShop),
        ]
        if let leg = to.wireLeg { body["to_leg"] = .string(leg) }
        if let from = from, !from.wireUniqueId.isEmpty {
            body["from_type"] = .string(from.wireType)
            body["from_unique_id"] = .string(from.wireUniqueId)
            if let leg = from.wireLeg { body["from_leg"] = .string(leg) }
        }
        return body
    }

    /// What Settings › Sync shows for this operation.
    var displayTitle: String {
        switch kind {
        case .nextMission:   return "Next Stop · Next mission"
        case .returnToShop:  return "Next Stop · Return to Shop"
        case .arrivedAtShop: return "Next Stop · Arrived at shop"
        }
    }
}

/// The next_stop.event operation: request shape and durable enqueue.
enum NextStopRouteEventOperation {

    static let operationType = "next_stop.event"
    static let path = "dispatch/next-stop/events"

    static func request(for operation: SyncOperation) throws -> SyncHTTPRequest {
        guard var body = operation.payload.objectValue,
              body["event"]?.stringValue?.isEmpty == false,
              body["to_type"]?.stringValue?.isEmpty == false,
              body["to_unique_id"]?.stringValue?.isEmpty == false else {
            throw SyncHandlerError.invalidPayload("Next Stop event payload is missing its event or destination")
        }
        body["operation_id"] = .string(operation.id)
        // The moment the driver tapped — not when the phone found signal.
        body["captured_at"] = .string(KabbaISO8601.string(from: operation.capturedAt))
        return SyncHTTPRequest(method: "POST",
                               path: path,
                               headers: ["X-Operation-Id": operation.id],
                               jsonBody: .object(body),
                               operationId: operation.id)
    }

    /// Durably records one answer. Returns after the record is on disk.
    ///
    /// `employeeId` is the driver signed in when they tapped: it travels with
    /// the answer, and the server refuses it under anybody else's session, so
    /// an answer left unsent at a sign-out can never be credited to the next
    /// driver on the phone.
    ///
    /// Its own ordering key (no order or task identity): an answer never waits
    /// behind, or holds up, a mission's own checklist or status operations. A
    /// refusal parks only the answer (Needs Attention, preserved) — the engine
    /// keeps draining everything else.
    @discardableResult
    static func enqueue(into engine: SyncEngine,
                        event: NextStopRouteEvent,
                        employeeId: Int?,
                        operationId: String = UUID().uuidString) throws -> SyncOperation {
        var payload = event.payload
        if let employeeId = employeeId, employeeId > 0 {
            payload["employee_id"] = .number(Double(employeeId))
        }
        return try engine.enqueue(type: operationType,
                                  payload: .object(payload),
                                  identity: SyncBusinessIdentity(employeeId: employeeId.map(String.init)),
                                  capturedAt: event.occurredAt,
                                  displayTitle: event.displayTitle,
                                  operationId: operationId)
    }
}
