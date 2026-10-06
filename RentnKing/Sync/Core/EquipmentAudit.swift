//
//  EquipmentAudit.swift
//  RentnKing — Sync Core (Foundation only)
//
//  The mobile Equipment Audit (2026-10-05): the yard workflow over the web
//  audit engine — open the assigned audit, land on your section, tap Verify,
//  move on.
//
//  Laravel is the ONLY authority. The board (sections, AuditSort order, each
//  unit's derived state and episode validity, the Section Auditor and default
//  Verified By, and the actions this account may take on each unit) comes
//  from GET equipment-audits/{audit}, built by the web audit's own
//  EquipmentAuditPopulation::board(). Nothing here re-derives a state, a sort,
//  a section or a permission. What lives here is presentation (row lines,
//  section headers, the default filter, search) and the choice of which
//  screen a tap opens — routing, never a rule: the write endpoints re-check
//  everything, and a unit found somewhere Kabba does not show is always an
//  explicit, deliberate decision.
//
//  Writes are ONLINE ONLY (no Sync Engine queue). A verification records the
//  unit's movement episode at the moment it is written; a queued one written
//  hours later could count against an episode nobody looked at. Each tap
//  carries an operation id so a dropped connection retries without
//  recording twice.
//

import Foundation

// MARK: - Contract (api/admin/v1/equipment-audits)

struct EquipmentAuditPerson: Codable, Equatable {
    let id: Int
    let name: String?

    /// "John" from "John Yard" — the compact row form.
    var firstName: String { (name ?? "").split(separator: " ").first.map(String.init) ?? (name ?? "") }
}

struct EquipmentAuditCounts: Codable, Equatable {
    let total: Int
    let verified: Int
    let needsVerification: Int
    let unresolved: Int
}

struct EquipmentAuditCompletion: Codable, Equatable {
    let ready: Bool
    let needsVerification: Int
    let unresolved: Int
    let completeOn: String
}

struct EquipmentAuditCategory: Codable, Equatable {
    let id: Int
    let title: String
}

/// What this account may do anywhere in the module (EquipmentAuditPermissions::forUser).
struct EquipmentAuditCan: Codable, Equatable {
    let view: Bool
    let start: Bool
    let verify: Bool
    let correctLocation: Bool
    let complete: Bool
    let history: Bool
    let assignLead: Bool
    let assignWork: Bool
}

struct EquipmentAuditMe: Codable, Equatable {
    let id: Int
    let uniqueId: String?
    let name: String
    /// Whether this account can itself be recorded as Verified By.
    let isEmployee: Bool
}

struct EquipmentAuditHeader: Codable, Equatable {
    let uniqueId: String
    let reference: String
    let title: String
    let category: EquipmentAuditCategory
    let status: String
    let startedAt: String?
    let lead: EquipmentAuditPerson?
    let summary: EquipmentAuditCounts
    let completion: EquipmentAuditCompletion
}

struct EquipmentAuditSectionHeader: Codable, Equatable {
    let key: String
    let label: String
    let kind: String
    let storeId: Int?
    let auditor: EquipmentAuditPerson?
    let assignedToMe: Bool
    let counts: EquipmentAuditCounts
    /// Units Kabba places in this section that are waiting in the Unresolved queue.
    let unresolvedElsewhere: Int
}

struct EquipmentAuditListItem: Codable, Equatable {
    let uniqueId: String
    let reference: String
    let title: String
    let category: EquipmentAuditCategory
    let status: String
    let startedAt: String?
    let lead: EquipmentAuditPerson?
    let summary: EquipmentAuditCounts
    let completion: EquipmentAuditCompletion
    let mySections: [EquipmentAuditSectionHeader]
}

struct EquipmentAuditIndex: Codable, Equatable {
    let me: EquipmentAuditMe
    let can: EquipmentAuditCan
    let audits: [EquipmentAuditListItem]
}

enum EquipmentAuditRowState: String, Codable, Equatable {
    case verified
    case needsVerification = "needs_verification"
    case unresolved
}

struct EquipmentAuditRow: Codable, Equatable {
    struct Unit: Codable, Equatable {
        struct Status: Codable, Equatable { let value: String; let label: String }
        let uniqueId: String
        let equipmentId: String
        let name: String
        let status: Status?
    }

    struct System: Codable, Equatable {
        /// store | customer_rentals | off_site | no_location
        let kind: String
        let label: String
        let storeId: Int?
        let sectionKey: String
    }

    struct Verification: Codable, Equatable {
        let type: String?
        let observedLabel: String?
        let by: EquipmentAuditPerson?
        let enteredBy: EquipmentAuditPerson?
        let at: String?
        let locationCorrected: Bool
        let notes: String?
    }

    struct Unresolved: Codable, Equatable {
        let note: String?
        let by: EquipmentAuditPerson?
        let at: String?
        let systemThen: String?
        let seenAt: String?
    }

    struct Rental: Codable, Equatable {
        let orderNumber: String?
        let customerName: String?
        let dueBack: String?
        let overdue: Bool
    }

    /// Decided by Laravel per account and unit — the phone hides what is false.
    struct Actions: Codable, Equatable {
        let verify: Bool
        /// physical | customer_rental | off_site — what Verify confirms.
        let verifyType: String?
        let foundAtStore: Bool
        let correctLocation: Bool
        let moveOffSite: Bool
        let markUnresolved: Bool
        let changeVerifier: Bool
    }

    let equipment: Unit
    /// The stale-screen guard: sent back with every action on this unit.
    let expectedKey: String
    let sectionKey: String
    let system: System
    let state: EquipmentAuditRowState
    let stateLabel: String
    let verification: Verification?
    let unresolved: Unresolved?
    let path: String?
    let discrepancy: String?
    let verifiedByDefault: EquipmentAuditPerson?
    let verifierOverride: Bool
    let rental: Rental?
    let actions: Actions
}

struct EquipmentAuditSection: Codable, Equatable {
    let key: String
    let label: String
    let kind: String
    let storeId: Int?
    let auditor: EquipmentAuditPerson?
    let assignedToMe: Bool
    let counts: EquipmentAuditCounts
    let unresolvedElsewhere: Int
    let rows: [EquipmentAuditRow]
}

struct EquipmentAuditStore: Codable, Equatable {
    let id: Int
    let name: String
}

struct EquipmentAuditBoard: Codable, Equatable {
    let audit: EquipmentAuditHeader
    let me: EquipmentAuditMe
    let can: EquipmentAuditCan
    let mySectionKeys: [String]
    let sections: [EquipmentAuditSection]
    let stores: [EquipmentAuditStore]
    let employees: [EquipmentAuditPerson]
    let generatedAt: String?

    func section(_ key: String) -> EquipmentAuditSection? { sections.first { $0.key == key } }

    func row(equipmentUniqueId: String) -> EquipmentAuditRow? {
        for section in sections {
            if let row = section.rows.first(where: { $0.equipment.uniqueId == equipmentUniqueId }) { return row }
        }
        return nil
    }

    func store(_ id: Int?) -> EquipmentAuditStore? { id.flatMap { id in stores.first { $0.id == id } } }
    func employee(_ id: Int?) -> EquipmentAuditPerson? { id.flatMap { id in employees.first { $0.id == id } } }
}

struct EquipmentAuditActionResult: Codable, Equatable {
    let eventId: Int?
    let replayed: Bool
    let audit: EquipmentAuditHeader
    let unit: EquipmentAuditRow?
}

/// GET …/units/{equipment}/off-site — Kabba's Manage Equipment Location feed (the web modal's own).
struct EquipmentAuditOffSiteOptions: Codable, Equatable {
    struct Unit: Codable, Equatable { let uniqueId: String; let equipmentId: String; let name: String }
    struct Location: Codable, Equatable { let state: String; let label: String? }
    struct Actions: Codable, Equatable { let moveOffSite: Bool }
    struct Supplier: Codable, Equatable {
        let id: Int
        let name: String
        let address: String?
        let city: String?
        let zip: String?
        let contact: String?
        let phone: String?

        var detail: String {
            [[address, city, zip].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", "), contact, phone]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        }
    }
    struct State: Codable, Equatable { let id: Int; let name: String }
    struct Reference: Codable, Equatable { let suppliers: [Supplier]; let states: [State] }

    let equipment: Unit
    let location: Location
    let actions: Actions
    let reference: Reference
}

enum EquipmentAuditDecoding {
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    /// Decodes the canonical envelope's `data`.
    static func decode<T: Decodable>(_ type: T.Type, envelope data: Data) throws -> T {
        guard let root = JSONValue.parse(data), let payload = root["data"], case .object = payload else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "No data object in the response"))
        }
        return try decoder().decode(type, from: payload.serialized())
    }
}

// MARK: - Presentation

enum EquipmentAuditPresentation {

    static let unresolvedSectionKey = "unresolved"

    /// Sections shown by default: the employee's own (and the shared Unresolved
    /// work queue), or every section when nothing is assigned to them.
    static func defaultVisibleSectionKeys(_ board: EquipmentAuditBoard) -> [String] {
        guard !board.mySectionKeys.isEmpty else { return board.sections.map(\.key) }
        let wanted = Set(board.mySectionKeys + [unresolvedSectionKey])
        return board.sections.map(\.key).filter { wanted.contains($0) }
    }

    /// The employee's sections first, then the rest — each group in the web board's order.
    static func orderedSections(_ board: EquipmentAuditBoard, visible: Set<String>) -> [EquipmentAuditSection] {
        let shown = board.sections.filter { visible.contains($0.key) }
        return shown.filter(\.assignedToMe) + shown.filter { !$0.assignedToMe }
    }

    /// Where this employee is physically auditing: their first assigned store section.
    static func defaultWorkingStoreId(_ board: EquipmentAuditBoard) -> Int? {
        board.sections.first { $0.assignedToMe && $0.kind == "store" }?.storeId
    }

    /// A remembered working store that no longer exists falls back to the default.
    static func resolveWorkingStoreId(remembered: Int?, board: EquipmentAuditBoard) -> Int? {
        if let id = remembered, board.store(id) != nil { return id }
        return defaultWorkingStoreId(board)
    }

    // Section headers

    /// "Bon Aqua — John Yard" / "Waverly — No Section Auditor".
    static func sectionTitle(_ section: EquipmentAuditSection) -> String {
        "\(section.label) — \(section.auditor?.name ?? "No Section Auditor")"
    }

    /// "12 Verified · 3 Need Verification · 1 Unresolved". A location section's
    /// Unresolved units wait in the Unresolved queue, so they are counted from there.
    static func sectionProgress(_ section: EquipmentAuditSection) -> String {
        let unresolved = section.key == unresolvedSectionKey ? section.counts.unresolved : section.unresolvedElsewhere
        var parts = ["\(section.counts.verified) Verified", "\(section.counts.needsVerification) Need Verification"]
        if unresolved > 0 { parts.append("\(unresolved) Unresolved") }
        return parts.joined(separator: " · ")
    }

    /// "12 of 16 Verified".
    static func overallProgress(_ summary: EquipmentAuditCounts) -> String {
        "\(summary.verified) of \(summary.total) Verified"
    }

    static func overallDetail(_ summary: EquipmentAuditCounts) -> String {
        var parts = ["\(summary.needsVerification) Need Verification"]
        if summary.unresolved > 0 { parts.append("\(summary.unresolved) Unresolved") }
        return parts.joined(separator: " · ")
    }

    /// Completion stays on the web; the phone shows whether it could happen.
    static func completionLine(_ completion: EquipmentAuditCompletion) -> String {
        if completion.ready { return "Ready to complete — finish it on the web." }
        var blockers: [String] = []
        if completion.needsVerification > 0 { blockers.append("\(completion.needsVerification) Need Verification") }
        if completion.unresolved > 0 { blockers.append("\(completion.unresolved) Unresolved") }
        return "Not ready to complete: " + blockers.joined(separator: " · ")
    }

    /// "Skid Steer Audit · EA-00002".
    static func auditTitle(_ header: EquipmentAuditHeader) -> String { "\(header.title) · \(header.reference)" }

    // Rows

    /// "Cab - Tak TL8 — TAK-SS-14".
    static func rowTitle(_ row: EquipmentAuditRow) -> String {
        "\(row.equipment.name) — \(row.equipment.equipmentId)"
    }

    /// The second line, by state:
    ///   Needs Verification · System: Bon Aqua
    ///   Verified · Bon Aqua · John · 9:42 AM
    ///   Unresolved · Unable to establish actual location.
    static func rowDetail(_ row: EquipmentAuditRow, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        switch row.state {
        case .verified:
            let v = row.verification
            return ["Verified",
                    v?.observedLabel ?? row.system.label,
                    v?.by?.firstName,
                    v?.at.flatMap { timeLabel($0, now: now, timeZone: timeZone) }]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        case .unresolved:
            let note = row.unresolved?.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            return note?.isEmpty == false ? "Unresolved · \(note!)" : "Unresolved"
        case .needsVerification:
            var line: String
            switch row.system.kind {
            case "store":
                line = "Needs Verification · System: \(row.system.label)"
            case "customer_rentals":
                // Whether it is overdue (first, so it never truncates), then who has it.
                line = "Needs Verification · " + (row.rental?.overdue == true ? "OVERDUE · " : "")
                    + "With \(row.rental?.customerName ?? "Customer")"
            default:
                line = "Needs Verification · \(row.system.label)"   // "Off-Site — County Fair", "No Location"
            }
            if row.verifierOverride, let by = row.verifiedByDefault?.firstName, !by.isEmpty { line += " · By \(by)" }
            return line
        }
    }

    /// "9:42 AM" today, "Oct 3, 9:42 AM" otherwise.
    static func timeLabel(_ iso: String, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        guard let date = KabbaISO8601.date(from: iso) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "h:mm a" : "MMM d, h:mm a"
        return f.string(from: date)
    }

    // Search — by equipment name or ID, across EVERY section (the unit may be
    // standing in front of you while Kabba places it somewhere else).

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    static func matches(_ row: EquipmentAuditRow, query: String) -> Bool {
        let q = normalized(query)
        guard !q.isEmpty else { return true }
        return normalized(row.equipment.equipmentId).contains(q) || normalized(row.equipment.name).contains(q)
    }

    /// Sections holding at least one match, each with only its matching rows.
    static func search(_ board: EquipmentAuditBoard, query: String) -> [EquipmentAuditSection] {
        board.sections.compactMap { section in
            let rows = section.rows.filter { matches($0, query: query) }
            guard !rows.isEmpty else { return nil }
            return EquipmentAuditSection(key: section.key, label: section.label, kind: section.kind, storeId: section.storeId,
                                         auditor: section.auditor, assignedToMe: section.assignedToMe, counts: section.counts,
                                         unresolvedElsewhere: section.unresolvedElsewhere, rows: rows)
        }
    }

    // Verified By

    /// Who an action on the row is recorded for: the row's own default (its
    /// override, else its Section Auditor); for a unit in a section nobody
    /// owns, the employee this phone was told is verifying, else the signed-in
    /// employee when they are a Section Auditor on this audit (the one walking
    /// the yard); else nobody — the phone then asks once.
    ///
    /// A unit found at a store Kabba does NOT show (a mismatch, Return On-Site,
    /// a rental standing in the yard) was seen by whoever audits THAT store, so
    /// its Section Auditor is the default there — not the auditor of the place
    /// Kabba wrongly shows. A per-unit Verified By override always wins.
    static func verifier(for row: EquipmentAuditRow, board: EquipmentAuditBoard, fallbackEmployeeId: Int?,
                         foundAtStoreId: Int? = nil) -> EquipmentAuditPerson? {
        if row.verifierOverride, let chosen = row.verifiedByDefault { return chosen }
        if let store = foundAtStoreId,
           let auditor = board.sections.first(where: { $0.kind == "store" && $0.storeId == store })?.auditor {
            return auditor
        }
        return row.verifiedByDefault ?? unassignedSectionVerifier(board, fallbackEmployeeId: fallbackEmployeeId)
    }

    /// The default Verified By for sections without a Section Auditor.
    static func unassignedSectionVerifier(_ board: EquipmentAuditBoard, fallbackEmployeeId: Int?) -> EquipmentAuditPerson? {
        if let chosen = board.employee(fallbackEmployeeId) { return chosen }
        guard board.me.isEmployee, !board.mySectionKeys.isEmpty else { return nil }
        return board.employee(board.me.id) ?? EquipmentAuditPerson(id: board.me.id, name: board.me.name)
    }

    static let offlineMessage = "No connection to Kabba. Equipment Audit needs a connection to record work — nothing was recorded. Reconnect and try again."

    /// What an audit write that did not succeed tells the employee. Audit
    /// writes are never queued or retried in the background, so nothing here
    /// may promise a retry (the app-wide wording does — it belongs to the
    /// Sync Engine). Server refusals (409/422/403…) keep Kabba's own message.
    static func failureMessage(statusCode: Int?, transport: TransportFailure?, serverMessage: String) -> String {
        if let transport = transport {
            switch transport {
            case .timeout, .connectionLost:
                // The request may have reached Kabba before the connection dropped.
                return "Kabba didn't confirm this before the connection dropped. Pull to refresh to see whether it was recorded."
            default:
                return offlineMessage
            }
        }
        if let status = statusCode, status >= 500 || status == 429 {
            return "Kabba couldn't record this right now — nothing was recorded. Try again in a moment."
        }
        return serverMessage
    }
}

// MARK: - Tap routing (which screen opens — never a rule)

struct EquipmentAuditMismatch: Equatable {
    let systemLocation: String
    let observedStoreId: Int
    let observedStore: String
    /// The account may correct the location (Correct Location); otherwise the
    /// only way to record the mismatch is Unresolved, seen at the observed store.
    let canMove: Bool
    /// Kabba shows the unit Off-Site: moving it is Return On-Site.
    let isReturnOnSite: Bool

    var title: String { isReturnOnSite ? "Off-Site Unit Found" : "Location Mismatch" }

    var message: String { "System Location: \(systemLocation)\nObserved Location: \(observedStore)" }

    var confirmTitle: String {
        guard canMove else { return "Mark Unresolved…" }
        return isReturnOnSite ? "Return On-Site to \(observedStore)" : "Verify & Move to \(observedStore)"
    }
}

enum EquipmentAuditTap: Equatable {
    /// The normal case — Kabba's store is where it was found: one tap.
    case verifyHere(storeId: Int)
    /// Found at the working store while Kabba shows another place.
    case mismatch(EquipmentAuditMismatch)
    /// A rental, an Off-Site unit or a unit with no location: a deliberate choice.
    case choose
    case none
}

enum EquipmentAuditMenuItem: Equatable {
    case verifyAtSystemStore(storeId: Int, store: String)
    case foundAtWorkingStore(EquipmentAuditMismatch)
    case foundAtAnotherStore
    case confirmWithCustomer
    case confirmOffSite
    /// A rented unit standing in the yard: Unresolved, seen at the store — the rental is never touched.
    case rentalFoundInYard(storeId: Int, store: String)
    case moveOffSite
    case markUnresolved
    case changeVerifier

    var title: String {
        switch self {
        case .verifyAtSystemStore(_, let store): return "Verify at \(store)"
        case .foundAtWorkingStore(let m): return m.isReturnOnSite ? "Found at \(m.observedStore) — Return On-Site…" : "Found at \(m.observedStore)…"
        case .foundAtAnotherStore: return "Found at another store…"
        case .confirmWithCustomer: return "Confirm With Customer"
        case .confirmOffSite: return "Confirm Off-Site"
        case .rentalFoundInYard(_, let store): return "Found at \(store) — Mark Unresolved…"
        case .moveOffSite: return "Move Off-Site…"
        case .markUnresolved: return "Mark Unresolved…"
        case .changeVerifier: return "Verified By…"
        }
    }
}

enum EquipmentAuditRouting {

    /// What the row's Verify button does for an employee working at `workingStoreId`.
    static func primaryTap(_ row: EquipmentAuditRow, workingStoreId: Int?, board: EquipmentAuditBoard) -> EquipmentAuditTap {
        let a = row.actions
        guard a.verify || a.foundAtStore || a.markUnresolved else { return .none }

        switch row.system.kind {
        case "store":
            if let mismatch = mismatch(row, observedStoreId: workingStoreId, board: board), a.foundAtStore {
                return .mismatch(mismatch)
            }
            if a.verify, let store = row.system.storeId { return .verifyHere(storeId: store) }
            return .choose
        case "off_site", "no_location":
            if a.foundAtStore, let mismatch = mismatch(row, observedStoreId: workingStoreId, board: board) {
                return .mismatch(mismatch)
            }
            return .choose
        default:
            return .choose
        }
    }

    /// The mismatch for finding the row's unit at `observedStoreId`, or nil when
    /// that is where Kabba already shows it (or no store was given).
    static func mismatch(_ row: EquipmentAuditRow, observedStoreId: Int?, board: EquipmentAuditBoard) -> EquipmentAuditMismatch? {
        guard let id = observedStoreId, let store = board.store(id) else { return nil }
        if row.system.kind == "store", row.system.storeId == id { return nil }
        return EquipmentAuditMismatch(systemLocation: row.system.label, observedStoreId: id, observedStore: store.name,
                                      canMove: row.actions.correctLocation, isReturnOnSite: row.system.kind == "off_site")
    }

    /// Every deliberate action the account may take on the row (the "…" menu).
    static func menu(_ row: EquipmentAuditRow, workingStoreId: Int?, board: EquipmentAuditBoard) -> [EquipmentAuditMenuItem] {
        let a = row.actions
        var items: [EquipmentAuditMenuItem] = []

        switch row.system.kind {
        case "store":
            if a.verify, let id = row.system.storeId { items.append(.verifyAtSystemStore(storeId: id, store: row.system.label)) }
        case "customer_rentals":
            if a.verify { items.append(.confirmWithCustomer) }
            if a.markUnresolved, let id = workingStoreId, let store = board.store(id) {
                items.append(.rentalFoundInYard(storeId: id, store: store.name))
            }
        case "off_site":
            if a.verify { items.append(.confirmOffSite) }
        default:
            break
        }

        if a.foundAtStore {
            if let mismatch = mismatch(row, observedStoreId: workingStoreId, board: board) { items.append(.foundAtWorkingStore(mismatch)) }
            items.append(.foundAtAnotherStore)
        }
        if a.moveOffSite { items.append(.moveOffSite) }
        if a.markUnresolved { items.append(.markUnresolved) }
        if a.changeVerifier { items.append(.changeVerifier) }
        return items
    }

    /// Stores the unit could have been found at instead of where Kabba shows it.
    static func otherStores(for row: EquipmentAuditRow, board: EquipmentAuditBoard) -> [EquipmentAuditStore] {
        board.stores.filter { !(row.system.kind == "store" && row.system.storeId == $0.id) }
    }
}

// MARK: - Commands (paths + JSON bodies)

struct EquipmentAuditCommand: Equatable {
    let path: String
    let body: JSONValue
    /// Stable for the life of one tap: a retry after a dropped connection replays it.
    let operationId: String
}

/// Move Off-Site fields — exactly Equipment's own (StoreOffSiteRequest). The
/// server validates them with Equipment's rules and messages; nothing here
/// decides whether they are enough.
struct EquipmentAuditOffSiteForm: Equatable {
    enum Source: String { case supplier, manual }

    var source: Source = .supplier
    var supplierId: Int?
    var locationName = ""
    var addressLine1 = ""
    var addressLine2 = ""
    var city = ""
    var stateId: Int?
    var zipCode = ""
    var contactName = ""
    var contactPhone = ""
    var reason = ""
    var notes = ""

    var payload: [String: JSONValue] {
        var out: [String: JSONValue] = ["location_source": .string(source.rawValue)]
        func put(_ key: String, _ text: String) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out[key] = .string(t) }
        }
        switch source {
        case .supplier:
            if let id = supplierId { out["supplier_id"] = .number(Double(id)) }
        case .manual:
            put("location_name", locationName)
            put("address_line_1", addressLine1)
            put("address_line_2", addressLine2)
            put("city", city)
            if let id = stateId { out["state_id"] = .number(Double(id)) }
            put("zip_code", zipCode)
            put("contact_name", contactName)
            put("contact_phone", contactPhone)
        }
        put("reason", reason)
        put("notes", notes)
        return out
    }
}

enum EquipmentAuditCommands {

    static let indexPath = "equipment-audits"

    static func boardPath(_ audit: String) -> String { "equipment-audits/\(audit)" }

    static func offSiteOptionsPath(_ audit: String, equipment: String) -> String {
        "equipment-audits/\(audit)/units/\(equipment)/off-site"
    }

    static func newOperationId() -> String { "EA-" + UUID().uuidString.replacingOccurrences(of: "-", with: "") }

    private static func unit(_ row: EquipmentAuditRow, performedBy: Int) -> [String: JSONValue] {
        ["equipment": .string(row.equipment.uniqueId),
         "expected_key": .string(row.expectedKey),
         "performed_by": .number(Double(performedBy))]
    }

    private static func make(_ audit: String, _ action: String, _ body: [String: JSONValue], _ operationId: String?) -> EquipmentAuditCommand {
        EquipmentAuditCommand(path: "equipment-audits/\(audit)/\(action)", body: .object(body), operationId: operationId ?? newOperationId())
    }

    /// Confirm what Kabba shows (verifyType from the row: physical at its store, customer_rental, off_site).
    static func verify(audit: String, row: EquipmentAuditRow, observedStoreId: Int?, performedBy: Int, operationId: String? = nil) -> EquipmentAuditCommand {
        var body = unit(row, performedBy: performedBy)
        body["verification_type"] = .string(row.actions.verifyType ?? "physical")
        if let store = observedStoreId { body["observed_store_id"] = .number(Double(store)) }
        return make(audit, "verify", body, operationId)
    }

    /// Verify & Move / Return On-Site to the store where it was found.
    static func correctLocation(audit: String, row: EquipmentAuditRow, observedStoreId: Int, performedBy: Int, notes: String? = nil, operationId: String? = nil) -> EquipmentAuditCommand {
        var body = unit(row, performedBy: performedBy)
        body["observed_store_id"] = .number(Double(observedStoreId))
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty { body["notes"] = .string(notes) }
        return make(audit, "correct-location", body, operationId)
    }

    static func markUnresolved(audit: String, row: EquipmentAuditRow, note: String, seenAtStoreId: Int?, performedBy: Int, operationId: String? = nil) -> EquipmentAuditCommand {
        var body = unit(row, performedBy: performedBy)
        body["notes"] = .string(note)
        if let store = seenAtStoreId { body["observed_store_id"] = .number(Double(store)) }
        return make(audit, "unresolved", body, operationId)
    }

    static func moveOffSite(audit: String, row: EquipmentAuditRow, form: EquipmentAuditOffSiteForm, performedBy: Int, operationId: String? = nil) -> EquipmentAuditCommand {
        make(audit, "off-site", unit(row, performedBy: performedBy).merging(form.payload) { current, _ in current }, operationId)
    }

    /// Verified By for this one unit; nil clears the override (back to the Section Auditor).
    static func assignVerifier(audit: String, row: EquipmentAuditRow, employeeId: Int?, operationId: String? = nil) -> EquipmentAuditCommand {
        make(audit, "verifier", ["equipment": .string(row.equipment.uniqueId),
                                 "employee_id": employeeId.map { .number(Double($0)) } ?? .null], operationId)
    }

    static func assignSectionAuditor(audit: String, sectionKey: String, employeeId: Int?, operationId: String? = nil) -> EquipmentAuditCommand {
        make(audit, "section-auditor", ["section_key": .string(sectionKey),
                                        "employee_id": employeeId.map { .number(Double($0)) } ?? .null], operationId)
    }
}
