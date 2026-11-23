//
//  ChecklistEmployeeDefaultTests.swift
//  KabbaSyncCore — Delivered By / Returned By defaults (2026-11-23, Rent 'n King order #5657)
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class ChecklistEmployeeDefaultTests: XCTestCase {

    private typealias Line = ChecklistEmployeeLine
    private let mike = 44, amber = 21, bob = 7, signedIn = 30
    private var everyone: Set<Int> { [mike, amber, bob, signedIn] }

    /// #5657 as production recorded it at 08:36: the skid steer is assigned to Mike (#44); the
    /// grapple — the LAST line, delivered from the store — has no driver. Nobody picked anyone.
    private var order5657: [Line] {
        [Line(employeeId: mike, chosen: false, assignedDriverId: mike),
         Line(employeeId: nil, chosen: false, assignedDriverId: nil)]
    }

    func testOrder5657CombinedNamesTheSkidSteersDriverInsteadOfTheGrapplesBlank() {
        let pick = ChecklistEmployeeDefault.combined(Line(employeeId: nil, chosen: false, assignedDriverId: nil),
                                                     lines: order5657, signedInUserId: amber, activeEmployeeIds: everyone)
        XCTAssertEqual(pick, .init(employeeId: mike, source: .otherLineDriver),
                       "the combined field took the grapple's blank; now the other line's driver")
    }

    func testOrder5657SeparateLinesEachNameADriver() {
        XCTAssertEqual(ChecklistEmployeeDefault.line(0, of: order5657, signedInUserId: amber, activeEmployeeIds: everyone),
                       .init(employeeId: mike, source: .assignedDriver))
        XCTAssertEqual(ChecklistEmployeeDefault.line(1, of: order5657, signedInUserId: amber, activeEmployeeIds: everyone),
                       .init(employeeId: mike, source: .otherLineDriver))
    }

    func testAPickOnAnEarlierScreenIsInheritedBeforeAnyDriver() {
        var lines = order5657
        lines[0] = Line(employeeId: amber, chosen: true, assignedDriverId: mike)        // Amber picked herself on line 1
        lines[1].assignedDriverId = bob                                                // even when the grapple has a driver
        XCTAssertEqual(ChecklistEmployeeDefault.line(1, of: lines, signedInUserId: signedIn, activeEmployeeIds: everyone),
                       .init(employeeId: amber, source: .earlierPick))
        XCTAssertEqual(ChecklistEmployeeDefault.combined(Line(employeeId: bob, chosen: false, assignedDriverId: nil),
                                                         lines: lines, signedInUserId: signedIn, activeEmployeeIds: everyone),
                       .init(employeeId: amber, source: .earlierPick), "a combined field that only copied a line follows the pick")
    }

    func testAPickIsNeverReplaced() {
        let lines = [Line(employeeId: bob, chosen: true, assignedDriverId: mike)]
        XCTAssertEqual(ChecklistEmployeeDefault.line(0, of: lines, signedInUserId: signedIn, activeEmployeeIds: everyone),
                       .init(employeeId: bob, source: .chosen))
        XCTAssertEqual(ChecklistEmployeeDefault.combined(Line(employeeId: amber, chosen: true, assignedDriverId: nil),
                                                         lines: lines, signedInUserId: signedIn, activeEmployeeIds: everyone),
                       .init(employeeId: amber, source: .chosen))
        XCTAssertEqual(ChecklistEmployeeDefault.line(0, of: lines, signedInUserId: signedIn, activeEmployeeIds: [mike]),
                       .init(employeeId: bob, source: .chosen), "a person's pick stands even if the phone's list is stale")
    }

    func testOnlyALaterPickIsNotInheritedBackwards() {
        let lines = [Line(employeeId: nil, chosen: false, assignedDriverId: mike),
                     Line(employeeId: bob, chosen: true, assignedDriverId: nil)]
        XCTAssertEqual(ChecklistEmployeeDefault.line(0, of: lines, signedInUserId: signedIn, activeEmployeeIds: everyone),
                       .init(employeeId: mike, source: .assignedDriver), "picks flow forward to later screens only")
        XCTAssertEqual(ChecklistEmployeeDefault.combined(Line(employeeId: nil, chosen: false, assignedDriverId: nil),
                                                         lines: lines, signedInUserId: signedIn, activeEmployeeIds: everyone),
                       .init(employeeId: bob, source: .earlierPick), "the combined field sits after every line")
    }

    func testTheLastLinesOwnDriverComesFirstForACombinedChecklist() {
        let lines = [Line(employeeId: mike, chosen: false, assignedDriverId: mike),
                     Line(employeeId: bob, chosen: false, assignedDriverId: bob)]
        XCTAssertEqual(ChecklistEmployeeDefault.combined(Line(employeeId: nil, chosen: false, assignedDriverId: nil),
                                                         lines: lines, signedInUserId: signedIn, activeEmployeeIds: everyone),
                       .init(employeeId: bob, source: .assignedDriver), "unchanged when the last line has a driver")
    }

    func testWithoutAnyDriverTheSignedInEmployeeIsSuggested() {
        let unassigned = [Line(employeeId: nil, chosen: false, assignedDriverId: nil),
                          Line(employeeId: nil, chosen: false, assignedDriverId: nil)]
        XCTAssertEqual(ChecklistEmployeeDefault.line(1, of: unassigned, signedInUserId: signedIn, activeEmployeeIds: everyone),
                       .init(employeeId: signedIn, source: .signedInUser))
        XCTAssertEqual(ChecklistEmployeeDefault.combined(Line(employeeId: nil, chosen: false, assignedDriverId: nil),
                                                         lines: unassigned, signedInUserId: signedIn, activeEmployeeIds: everyone),
                       .init(employeeId: signedIn, source: .signedInUser))
    }

    func testSuggestionsMustBeActiveWhenThePhoneKnowsTheList() {
        let lines = [Line(employeeId: nil, chosen: false, assignedDriverId: mike)]
        XCTAssertEqual(ChecklistEmployeeDefault.line(0, of: lines, signedInUserId: signedIn, activeEmployeeIds: [signedIn]),
                       .init(employeeId: signedIn, source: .signedInUser), "an inactive driver is not suggested")
        XCTAssertEqual(ChecklistEmployeeDefault.line(0, of: lines, signedInUserId: signedIn, activeEmployeeIds: [bob]),
                       .init(employeeId: nil, source: .none), "nor a signed-in account that is not an active employee")
        XCTAssertEqual(ChecklistEmployeeDefault.line(0, of: lines, signedInUserId: signedIn, activeEmployeeIds: nil),
                       .init(employeeId: mike, source: .assignedDriver), "no list on the phone yet (offline): the driver as Kabba sent it")
    }

    func testSingleLineAndEdgeCases() {
        let single = [Line(employeeId: mike, chosen: false, assignedDriverId: mike)]
        XCTAssertEqual(ChecklistEmployeeDefault.line(0, of: single, signedInUserId: nil, activeEmployeeIds: everyone),
                       .init(employeeId: mike, source: .assignedDriver))
        XCTAssertEqual(ChecklistEmployeeDefault.line(3, of: single, signedInUserId: signedIn, activeEmployeeIds: everyone),
                       .init(employeeId: nil, source: .none))
        XCTAssertEqual(ChecklistEmployeeDefault.combined(Line(employeeId: nil, chosen: false, assignedDriverId: nil),
                                                         lines: [], signedInUserId: nil, activeEmployeeIds: nil),
                       .init(employeeId: nil, source: .none))
        XCTAssertNil(Line(employeeId: 0, chosen: true, assignedDriverId: nil).pick, "users.id 0 is nobody")
    }

    func testStoredTextIds() {
        XCTAssertEqual(ChecklistEmployeeLine.id("44"), 44)
        XCTAssertNil(ChecklistEmployeeLine.id(""))
        XCTAssertNil(ChecklistEmployeeLine.id("0"), "the checklist stores \"0\" for an unassigned line")
        XCTAssertNil(ChecklistEmployeeLine.id("Mike"))
    }

    // MARK: - Employee list paging

    func testEveryPageIsReadUpToTheCap() {
        XCTAssertEqual(EmployeeDirectoryPaging.nextPage(after: 1, lastPage: 3), 2)
        XCTAssertNil(EmployeeDirectoryPaging.nextPage(after: 3, lastPage: 3))
        XCTAssertNil(EmployeeDirectoryPaging.nextPage(after: 1, lastPage: nil), "an older Kabba without pagination is one page")
        XCTAssertNil(EmployeeDirectoryPaging.nextPage(after: EmployeeDirectoryPaging.maximumPages, lastPage: 10_000))
    }

    func testLastPageIsReadWhateverItsJSONType() {
        XCTAssertEqual(EmployeeDirectoryPaging.lastPage(in: ["last_page": 2]), 2)
        XCTAssertEqual(EmployeeDirectoryPaging.lastPage(in: ["last_page": NSNumber(value: 4)]), 4)
        XCTAssertEqual(EmployeeDirectoryPaging.lastPage(in: ["last_page": "5"]), 5)
        XCTAssertNil(EmployeeDirectoryPaging.lastPage(in: nil))
        XCTAssertNil(EmployeeDirectoryPaging.lastPage(in: ["current_page": 1]))
    }
}
