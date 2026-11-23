//
//  ChecklistEmployeeDefault.swift
//  KabbaSyncCore — who a customer checklist names as Delivered By / Returned By (2026-11-23)
//
//  Rent 'n King order #5657: a combined delivery checklist (cab skid steer + grapple) took its
//  one Delivered By from the LAST line only. The grapple had no driver, so the field was blank,
//  Preview refused ("Please select who delivered the equipment.") and, opened from Dispatch, the
//  picker did nothing. This decides the default for every line and for the combined checklist:
//
//    1. a person's pick on this checklist (that line's, or an earlier line's)
//    2. the line's assigned driver for the leg (order_products.delivery_by / pickup_by), then the
//       driver of another line of the same checklist
//    3. the signed-in employee
//
//  A default is only a starting point: the picker always offers every active employee, and a
//  pick always wins. Defaults and picks are local to the checklist; nothing here reassigns a
//  dispatch or changes who is signed in. The id submitted is the numeric users.id.
//

import Foundation

/// One equipment line's Delivered By (or Returned By) on a checklist.
public struct ChecklistEmployeeLine: Equatable {
    /// The users.id the line names now; nil when none.
    public var employeeId: Int?
    /// True only when a person picked `employeeId` on a checklist screen (never for a default).
    public var chosen: Bool
    /// The line's assigned driver for this leg; nil when the line has none.
    public var assignedDriverId: Int?

    public init(employeeId: Int?, chosen: Bool, assignedDriverId: Int?) {
        self.employeeId = employeeId
        self.chosen = chosen
        self.assignedDriverId = assignedDriverId
    }

    /// A text id as the checklist stores it ("" / "0" = nobody).
    public static func id(_ text: String) -> Int? {
        guard let id = Int(text.trimmingCharacters(in: .whitespaces)), id > 0 else { return nil }
        return id
    }

    /// The person picked for this line, if a person picked one.
    var pick: Int? {
        guard chosen, let id = employeeId, id > 0 else { return nil }
        return id
    }
}

public enum ChecklistEmployeeDefault {

    public enum Source: String, Equatable {
        /// A person picked this employee for this line (or for the combined checklist).
        case chosen
        /// A person picked this employee on an earlier line of the same checklist.
        case earlierPick
        /// The line's assigned driver for the leg.
        case assignedDriver
        /// The assigned driver of another line of the same checklist.
        case otherLineDriver
        /// The employee signed in on this phone.
        case signedInUser
        /// Nobody can be suggested; the field stays empty until a person picks.
        case none
    }

    public struct Pick: Equatable {
        public let employeeId: Int?
        public let source: Source

        public init(employeeId: Int?, source: Source) {
            self.employeeId = employeeId
            self.source = source
        }

        static let nobody = Pick(employeeId: nil, source: .none)
    }

    /// The default for line `index` of a separate (per-line) checklist.
    ///
    /// - Parameter activeEmployeeIds: the active employees this phone knows; nil when it has no
    ///   list yet (an id is then taken as it is). A suggested driver or signed-in employee who is
    ///   not on a known list is skipped; a person's pick never is.
    public static func line(_ index: Int, of lines: [ChecklistEmployeeLine],
                            signedInUserId: Int?, activeEmployeeIds: Set<Int>?) -> Pick {
        guard lines.indices.contains(index) else { return .nobody }
        if let id = lines[index].pick { return Pick(employeeId: id, source: .chosen) }
        if let id = lines[..<index].reversed().lazy.compactMap(\.pick).first {
            return Pick(employeeId: id, source: .earlierPick)
        }
        if let id = usable(lines[index].assignedDriverId, activeEmployeeIds) {
            return Pick(employeeId: id, source: .assignedDriver)
        }
        let others = Array(lines[..<index].reversed()) + Array(lines[(index + 1)...])
        if let id = others.lazy.compactMap({ usable($0.assignedDriverId, activeEmployeeIds) }).first {
            return Pick(employeeId: id, source: .otherLineDriver)
        }
        if let id = usable(signedInUserId, activeEmployeeIds) { return Pick(employeeId: id, source: .signedInUser) }
        return .nobody
    }

    /// The ONE employee a combined checklist submits with every line.
    ///
    /// The combined field sits under the last line, so its own pick comes first, then the latest
    /// line pick (scanning back from the last line), then the last line's driver, then the
    /// driver of a line before it, then the signed-in employee.
    public static func combined(_ combined: ChecklistEmployeeLine, lines: [ChecklistEmployeeLine],
                                signedInUserId: Int?, activeEmployeeIds: Set<Int>?) -> Pick {
        if let id = combined.pick { return Pick(employeeId: id, source: .chosen) }
        if let id = lines.reversed().lazy.compactMap(\.pick).first { return Pick(employeeId: id, source: .earlierPick) }
        if let id = usable(lines.last?.assignedDriverId, activeEmployeeIds) {
            return Pick(employeeId: id, source: .assignedDriver)
        }
        if let id = lines.dropLast().reversed().lazy.compactMap({ usable($0.assignedDriverId, activeEmployeeIds) }).first {
            return Pick(employeeId: id, source: .otherLineDriver)
        }
        if let id = usable(signedInUserId, activeEmployeeIds) { return Pick(employeeId: id, source: .signedInUser) }
        return .nobody
    }

    static func usable(_ id: Int?, _ active: Set<Int>?) -> Int? {
        guard let id = id, id > 0 else { return nil }
        guard let active = active else { return id }
        return active.contains(id) ? id : nil
    }
}

/// Kabba's `POST users` list is paginated (`per_page`, `pagination.last_page`). The phone reads
/// EVERY page before it replaces its cached list, so an employee beyond the first page can still
/// be picked, and a failed page never shrinks the list it already has.
public enum EmployeeDirectoryPaging {
    /// Pages per refresh at most (100 per page → 5,000 employees); a server that keeps
    /// reporting more pages cannot keep the phone fetching forever.
    public static let maximumPages = 50

    /// The page to read after `page`, or nil when `page` was the last one. A response without
    /// pagination (an older Kabba) is one page.
    public static func nextPage(after page: Int, lastPage: Int?) -> Int? {
        guard let lastPage = lastPage, page < lastPage, page < maximumPages else { return nil }
        return page + 1
    }

    /// `pagination.last_page` from a users response, whether Kabba sent it as a number or text.
    public static func lastPage(in pagination: [String: Any]?) -> Int? {
        switch pagination?["last_page"] {
        case let n as Int: return n
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }
}
