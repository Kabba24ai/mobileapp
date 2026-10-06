//
//  EquipmentAuditTests.swift
//  KabbaSyncCoreTests — mobile Equipment Audit (2026-10-05)
//
//  Contract decode of the shared Laravel fixtures (index, live board, action
//  result, Off-Site options, refusals) and the phone's pure presentation and
//  routing: the default filter and working store from the Section Auditor
//  assignment, the two-line rows, section progress, search across every
//  section, which screen a tap opens, the per-row menu and the exact request
//  bodies. The phone never re-derives a state, a sort or a permission — the
//  tests assert it renders the server's.
//

import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class EquipmentAuditTests: XCTestCase {

    // MARK: Fixtures

    private func fixture(_ name: String) throws -> Data {
        let candidates = [
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name).json"),
            Bundle(for: EquipmentAuditTests.self).url(forResource: name, withExtension: "json"),
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }
        throw XCTSkip("Fixture \(name).json not synced — run Scripts/sync-contract-fixtures.sh")
    }

    private func board() throws -> EquipmentAuditBoard {
        try EquipmentAuditDecoding.decode(EquipmentAuditBoard.self, envelope: fixture("equipment_audit_board"))
    }

    private func row(_ board: EquipmentAuditBoard, _ equipmentId: String) -> EquipmentAuditRow {
        board.sections.flatMap(\.rows).first { $0.equipment.equipmentId == equipmentId }!
    }

    private var bonAqua: Int { 3 }
    private var waverly: Int { 4 }

    /// A board where this account may verify but not correct locations.
    private func verifierOnly(_ board: EquipmentAuditBoard) throws -> EquipmentAuditBoard {
        var json = try JSONSerialization.jsonObject(with: fixture("equipment_audit_board")) as! [String: Any]
        var data = json["data"] as! [String: Any]
        var sections = data["sections"] as! [[String: Any]]
        for i in sections.indices {
            var rows = sections[i]["rows"] as! [[String: Any]]
            for j in rows.indices {
                var actions = rows[j]["actions"] as! [String: Any]
                actions["correct_location"] = false
                actions["move_off_site"] = false
                rows[j]["actions"] = actions
            }
            sections[i]["rows"] = rows
        }
        data["sections"] = sections
        json["data"] = data
        return try EquipmentAuditDecoding.decode(EquipmentAuditBoard.self, envelope: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: Contract

    func testTheActiveAuditListDecodesWithTheSectionsAssignedToMe() throws {
        let index = try EquipmentAuditDecoding.decode(EquipmentAuditIndex.self, envelope: fixture("equipment_audit_index"))

        XCTAssertEqual(index.me.name, "John Yard")
        XCTAssertTrue(index.me.isEmployee)
        XCTAssertTrue(index.can.verify)
        XCTAssertEqual(index.audits.count, 1)
        let audit = index.audits[0]
        XCTAssertEqual(audit.title, "Skid Steer Audit")
        XCTAssertEqual(audit.completion.completeOn, "web")
        XCTAssertFalse(audit.completion.ready)
        XCTAssertEqual(audit.mySections.map(\.label), ["Bon Aqua", "Unresolved"])
        XCTAssertTrue(audit.mySections.allSatisfy(\.assignedToMe))
        XCTAssertEqual(EquipmentAuditPresentation.overallProgress(audit.summary), "1 of 7 Verified")
    }

    func testTheBoardDecodesSectionsRowsAndActionsExactlyAsServed() throws {
        let b = try board()

        XCTAssertEqual(b.sections.map(\.key), ["store:3", "store:4", "customer_rentals", "off_site", "unresolved"])
        XCTAssertEqual(b.mySectionKeys, ["store:3", "unresolved"])
        // The server's AuditSort order is kept untouched — a verified unit keeps its place.
        XCTAssertEqual(b.sections[0].rows.map(\.equipment.equipmentId), ["SS-1", "TAK-SS-14", "TAK-SS-16", "SS-9"])
        XCTAssertEqual(b.sections[0].rows.map(\.state), [.verified, .needsVerification, .needsVerification, .needsVerification])

        let verified = row(b, "SS-1")
        XCTAssertEqual(verified.verification?.by?.name, "John Yard")
        XCTAssertEqual(verified.verification?.enteredBy?.name, "Terminal Account")
        XCTAssertFalse(verified.actions.verify, "nothing left to do on a verified unit")

        let lost = row(b, "SS-8")
        XCTAssertEqual(lost.state, .unresolved)
        XCTAssertEqual(lost.sectionKey, "unresolved")
        XCTAssertEqual(lost.system.sectionKey, "store:4", "it is Waverly's unit, waiting in the Unresolved queue")
        XCTAssertEqual(lost.path, "Waverly → Unresolved")

        let rental = row(b, "SS-110")
        XCTAssertEqual(rental.actions.verifyType, "customer_rental")
        XCTAssertFalse(rental.actions.foundAtStore, "an audit never places a rented unit at a store")
        XCTAssertEqual(rental.rental?.customerName, "Jane Renter")

        XCTAssertEqual(b.stores.map(\.name), ["Bon Aqua", "Waverly"])
        XCTAssertTrue(b.employees.contains(EquipmentAuditPerson(id: b.me.id, name: "John Yard")))
    }

    func testAnActionResultCarriesTheUnitsNewRowAndTheAuditTotals() throws {
        let result = try EquipmentAuditDecoding.decode(EquipmentAuditActionResult.self, envelope: fixture("equipment_audit_verified"))

        XCTAssertFalse(result.replayed)
        XCTAssertNotNil(result.eventId)
        XCTAssertEqual(result.unit?.equipment.equipmentId, "TAK-SS-14")
        XCTAssertEqual(result.unit?.state, .verified)
        XCTAssertEqual(result.audit.summary.verified, 2)
    }

    func testTheOffSiteFormReadsTheCanonicalSuppliersAndStates() throws {
        let options = try EquipmentAuditDecoding.decode(EquipmentAuditOffSiteOptions.self, envelope: fixture("equipment_audit_off_site_options"))

        XCTAssertTrue(options.actions.moveOffSite)
        XCTAssertEqual(options.location.state, "at_store")
        XCTAssertEqual(options.reference.suppliers.first?.name, "Parman Tractor")
        XCTAssertEqual(options.reference.suppliers.first?.detail, "11262 Moss Branch Road, Bon Aqua, 37025 · Joe Parman · (615) 555-2000")
        XCTAssertEqual(options.reference.states.first?.name, "Tennessee")
    }

    func testRefusalsKeepTheLedgersCodesAndAreNeverRetried() throws {
        let stale = APIErrorClassifier.classify(statusCode: 409, body: try fixture("equipment_audit_stale_screen"))
        XCTAssertEqual(stale.code, "STALE_SCREEN")
        XCTAssertTrue(stale.isConflict)
        XCTAssertEqual(stale.details?["context"]?["current_location"]?.stringValue, "Bon Aqua")

        let mismatch = APIErrorClassifier.classify(statusCode: 409, body: try fixture("equipment_audit_discrepancy_confirmation_required"))
        XCTAssertEqual(mismatch.code, "DISCREPANCY_CONFIRMATION_REQUIRED")
        XCTAssertEqual(mismatch.details?["context"]?["observed_location"]?.stringValue, "Waverly")

        let invalid = APIErrorClassifier.classify(statusCode: 422, body: try fixture("equipment_audit_validation_failure"))
        XCTAssertTrue(invalid.isValidationFailure)
        XCTAssertEqual(invalid.validationErrors["notes"], ["A note is required to mark equipment Unresolved."])
    }

    // MARK: Sections — the assignment decides the default

    func testTheDefaultFilterIsMySectionsPlusTheUnresolvedQueue() throws {
        let b = try board()
        XCTAssertEqual(EquipmentAuditPresentation.defaultVisibleSectionKeys(b), ["store:3", "unresolved"])
    }

    func testWithNoAssignmentEverySectionIsShown() throws {
        let b = try board()
        let sections = b.sections.map {
            EquipmentAuditSection(key: $0.key, label: $0.label, kind: $0.kind, storeId: $0.storeId, auditor: nil, assignedToMe: false,
                                  counts: $0.counts, unresolvedElsewhere: $0.unresolvedElsewhere, rows: $0.rows)
        }
        let unassigned = EquipmentAuditBoard(audit: b.audit, me: b.me, can: b.can, mySectionKeys: [],
                                             sections: sections, stores: b.stores, employees: b.employees, generatedAt: b.generatedAt)
        XCTAssertEqual(EquipmentAuditPresentation.defaultVisibleSectionKeys(unassigned), b.sections.map(\.key))
        XCTAssertNil(EquipmentAuditPresentation.defaultWorkingStoreId(unassigned))
    }

    func testMySectionsComeFirstAndTheRestKeepTheBoardOrder() throws {
        let b = try board()
        let all = Set(b.sections.map(\.key))
        XCTAssertEqual(EquipmentAuditPresentation.orderedSections(b, visible: all).map(\.key),
                       ["store:3", "unresolved", "store:4", "customer_rentals", "off_site"])
        XCTAssertEqual(EquipmentAuditPresentation.orderedSections(b, visible: ["off_site", "store:4"]).map(\.key), ["store:4", "off_site"])
    }

    func testTheWorkingStoreIsMyAssignedStoreAndAForgottenStoreFallsBack() throws {
        let b = try board()
        XCTAssertEqual(EquipmentAuditPresentation.defaultWorkingStoreId(b), bonAqua)
        XCTAssertEqual(EquipmentAuditPresentation.resolveWorkingStoreId(remembered: waverly, board: b), waverly, "an explicit choice is kept")
        XCTAssertEqual(EquipmentAuditPresentation.resolveWorkingStoreId(remembered: 999, board: b), bonAqua)
    }

    func testSectionHeadersReadSectionAuditorAndProgress() throws {
        let b = try board()
        XCTAssertEqual(EquipmentAuditPresentation.sectionTitle(b.sections[0]), "Bon Aqua — John Yard")
        XCTAssertEqual(EquipmentAuditPresentation.sectionProgress(b.sections[0]), "1 Verified · 3 Need Verification")
        XCTAssertEqual(EquipmentAuditPresentation.sectionTitle(b.sections[1]), "Waverly — No Section Auditor")
        XCTAssertEqual(EquipmentAuditPresentation.sectionProgress(b.sections[1]), "0 Verified · 0 Need Verification · 1 Unresolved",
                       "Waverly's unit waiting in the Unresolved queue is still counted for Waverly")
        XCTAssertEqual(EquipmentAuditPresentation.sectionProgress(b.section("unresolved")!), "0 Verified · 0 Need Verification · 1 Unresolved")
        XCTAssertEqual(EquipmentAuditPresentation.completionLine(b.audit.completion), "Not ready to complete: 5 Need Verification · 1 Unresolved")
        XCTAssertEqual(EquipmentAuditPresentation.completionLine(EquipmentAuditCompletion(ready: true, needsVerification: 0, unresolved: 0, completeOn: "web")),
                       "Ready to complete — finish it on the web.")
    }

    // MARK: Rows

    func testRowsReadInTwoCompactLines() throws {
        let b = try board()
        let utc = TimeZone(identifier: "UTC")!
        let sameDay = KabbaISO8601.date(from: "2026-10-05T20:00:00+00:00")!

        XCTAssertEqual(EquipmentAuditPresentation.rowTitle(row(b, "TAK-SS-14")), "Cab - Tak TL8 — TAK-SS-14")
        XCTAssertEqual(EquipmentAuditPresentation.rowDetail(row(b, "TAK-SS-14")), "Needs Verification · System: Bon Aqua")
        XCTAssertEqual(EquipmentAuditPresentation.rowDetail(row(b, "SS-1"), now: sameDay, timeZone: utc), "Verified · Bon Aqua · John · 11:17 AM")
        XCTAssertEqual(EquipmentAuditPresentation.rowDetail(row(b, "SS-1"), now: sameDay.addingTimeInterval(86_400 * 2), timeZone: utc),
                       "Verified · Bon Aqua · John · Oct 5, 11:17 AM")
        XCTAssertEqual(EquipmentAuditPresentation.rowDetail(row(b, "SS-8")), "Unresolved · Unable to establish actual location.")
        XCTAssertEqual(EquipmentAuditPresentation.rowDetail(row(b, "SS-4")), "Needs Verification · Off-Site — Humphreys County Fair")
        XCTAssertEqual(EquipmentAuditPresentation.rowDetail(row(b, "SS-110")), "Needs Verification · With Jane Renter",
                       "a rental names who has it (the System label would truncate first)")
    }

    // MARK: Search — every section, by name or ID

    func testSearchFindsAUnitByIdOrNameWhereverKabbaPlacesIt() throws {
        let b = try board()

        XCTAssertEqual(EquipmentAuditPresentation.search(b, query: "tak ss 14").flatMap(\.rows).map(\.equipment.equipmentId), ["TAK-SS-14"])
        XCTAssertEqual(EquipmentAuditPresentation.search(b, query: "ss8").flatMap(\.rows).map(\.equipment.equipmentId), ["SS-8"],
                       "found in the Unresolved queue even when the filter hides it")
        XCTAssertEqual(EquipmentAuditPresentation.search(b, query: "Cat 259").map(\.key), ["customer_rentals"])
        XCTAssertEqual(EquipmentAuditPresentation.search(b, query: "bobcat").flatMap(\.rows).map(\.equipment.equipmentId), ["SS-1", "SS-4", "SS-8"])
        XCTAssertEqual(EquipmentAuditPresentation.search(b, query: "  ").flatMap(\.rows).count, 7)
        XCTAssertTrue(EquipmentAuditPresentation.search(b, query: "nothing like it").isEmpty)
    }

    // MARK: Tap routing

    func testTheNormalCaseIsOneTap() throws {
        let b = try board()
        XCTAssertEqual(EquipmentAuditRouting.primaryTap(row(b, "TAK-SS-14"), workingStoreId: bonAqua, board: b), .verifyHere(storeId: bonAqua))
        XCTAssertEqual(EquipmentAuditRouting.primaryTap(row(b, "TAK-SS-14"), workingStoreId: nil, board: b), .verifyHere(storeId: bonAqua),
                       "no working store chosen: verified where Kabba shows it")
        XCTAssertEqual(EquipmentAuditRouting.primaryTap(row(b, "SS-1"), workingStoreId: bonAqua, board: b), .none, "already verified")
    }

    func testAUnitKabbaPlacesElsewhereNeedsAnExplicitDecision() throws {
        let b = try board()

        guard case .mismatch(let m) = EquipmentAuditRouting.primaryTap(row(b, "TAK-SS-14"), workingStoreId: waverly, board: b) else {
            return XCTFail("a Bon Aqua unit found while working Waverly is a mismatch")
        }
        XCTAssertEqual(m.title, "Location Mismatch")
        XCTAssertEqual(m.message, "System Location: Bon Aqua\nObserved Location: Waverly")
        XCTAssertTrue(m.canMove)
        XCTAssertEqual(m.confirmTitle, "Verify & Move to Waverly")

        guard case .mismatch(let noPermission) = EquipmentAuditRouting.primaryTap(row(try verifierOnly(b), "TAK-SS-14"), workingStoreId: waverly, board: b) else {
            return XCTFail("still a mismatch without Correct Location")
        }
        XCTAssertFalse(noPermission.canMove)
        XCTAssertEqual(noPermission.confirmTitle, "Mark Unresolved…", "without Correct Location the mismatch is recorded as Unresolved")
    }

    func testAnOffSiteUnitFoundInTheYardReturnsOnSite() throws {
        let b = try board()
        guard case .mismatch(let m) = EquipmentAuditRouting.primaryTap(row(b, "SS-4"), workingStoreId: bonAqua, board: b) else {
            return XCTFail("an Off-Site unit at the working store is a mismatch")
        }
        XCTAssertTrue(m.isReturnOnSite)
        XCTAssertEqual(m.title, "Off-Site Unit Found")
        XCTAssertEqual(m.confirmTitle, "Return On-Site to Bon Aqua")
        XCTAssertEqual(EquipmentAuditRouting.primaryTap(row(b, "SS-4"), workingStoreId: nil, board: b), .choose)
    }

    func testRentalsAreADeliberateChoiceNeverATapToMove() throws {
        let b = try board()
        XCTAssertEqual(EquipmentAuditRouting.primaryTap(row(b, "SS-110"), workingStoreId: bonAqua, board: b), .choose)
        XCTAssertEqual(EquipmentAuditRouting.menu(row(b, "SS-110"), workingStoreId: bonAqua, board: b),
                       [.confirmWithCustomer, .rentalFoundInYard(storeId: bonAqua, store: "Bon Aqua"), .markUnresolved, .changeVerifier])
    }

    func testTheRowMenuOffersOnlyWhatTheServerAllows() throws {
        let b = try board()
        let mismatch = EquipmentAuditRouting.mismatch(row(b, "TAK-SS-14"), observedStoreId: waverly, board: b)!

        XCTAssertEqual(EquipmentAuditRouting.menu(row(b, "TAK-SS-14"), workingStoreId: waverly, board: b),
                       [.verifyAtSystemStore(storeId: bonAqua, store: "Bon Aqua"), .foundAtWorkingStore(mismatch), .foundAtAnotherStore,
                        .moveOffSite, .markUnresolved, .changeVerifier])
        XCTAssertEqual(EquipmentAuditRouting.menu(row(b, "TAK-SS-14"), workingStoreId: bonAqua, board: b),
                       [.verifyAtSystemStore(storeId: bonAqua, store: "Bon Aqua"), .foundAtAnotherStore, .moveOffSite, .markUnresolved, .changeVerifier])
        XCTAssertFalse(EquipmentAuditRouting.menu(row(try verifierOnly(b), "TAK-SS-14"), workingStoreId: bonAqua, board: b).contains(.moveOffSite))
        XCTAssertEqual(EquipmentAuditRouting.menu(row(b, "SS-1"), workingStoreId: bonAqua, board: b), [], "a verified unit has nothing to do")
        XCTAssertEqual(EquipmentAuditRouting.otherStores(for: row(b, "TAK-SS-14"), board: b).map(\.name), ["Waverly"])
        XCTAssertEqual(EquipmentAuditRouting.otherStores(for: row(b, "SS-4"), board: b).map(\.name), ["Bon Aqua", "Waverly"])
    }

    // MARK: Verified By

    func testVerifiedByIsTheRowsDefaultThenThePhonesChoiceThenTheSectionAuditorHoldingThePhone() throws {
        let b = try board()
        XCTAssertEqual(EquipmentAuditPresentation.verifier(for: row(b, "TAK-SS-14"), board: b, fallbackEmployeeId: nil)?.name, "John Yard",
                       "the Section Auditor is implied")
        // Off-Site has no Section Auditor: John, who owns Bon Aqua and holds the phone, is the one walking the yard.
        XCTAssertNil(row(b, "SS-4").verifiedByDefault)
        XCTAssertEqual(EquipmentAuditPresentation.verifier(for: row(b, "SS-4"), board: b, fallbackEmployeeId: nil)?.id, b.me.id)
        let other = b.employees.first { $0.id != b.me.id }!
        XCTAssertEqual(EquipmentAuditPresentation.verifier(for: row(b, "SS-4"), board: b, fallbackEmployeeId: other.id), other, "the phone's choice wins")
        XCTAssertEqual(EquipmentAuditPresentation.verifier(for: row(b, "TAK-SS-14"), board: b, fallbackEmployeeId: other.id)?.name, "John Yard",
                       "the row's own default wins")

        // Found somewhere Kabba does not show: the auditor of the store where it was found.
        let waverlyUnit = row(b, "SS-8")   // Kabba: Waverly (no Section Auditor in the fixture), Unresolved
        XCTAssertEqual(EquipmentAuditPresentation.verifier(for: waverlyUnit, board: b, fallbackEmployeeId: nil, foundAtStoreId: bonAqua)?.name, "John Yard",
                       "seen at Bon Aqua by Bon Aqua's auditor")
        XCTAssertEqual(EquipmentAuditPresentation.verifier(for: row(b, "SS-4"), board: b, fallbackEmployeeId: other.id, foundAtStoreId: bonAqua)?.name, "John Yard",
                       "Return On-Site to Bon Aqua: Bon Aqua's auditor, not the phone's fallback")
        XCTAssertEqual(EquipmentAuditPresentation.verifier(for: row(b, "SS-4"), board: b, fallbackEmployeeId: other.id, foundAtStoreId: waverly), other,
                       "Waverly has no Section Auditor: the usual fallback")

        // A shared phone signed in as someone who owns no section: nobody is assumed — it asks.
        let unassigned = EquipmentAuditBoard(audit: b.audit, me: b.me, can: b.can, mySectionKeys: [], sections: b.sections,
                                             stores: b.stores, employees: b.employees, generatedAt: b.generatedAt)
        XCTAssertNil(EquipmentAuditPresentation.verifier(for: row(unassigned, "SS-4"), board: unassigned, fallbackEmployeeId: nil))
    }

    // MARK: Failures — never promise a retry that will not happen

    func testAFailedAuditWriteSaysWhatHappenedAndNeverPromisesARetry() {
        let offline = EquipmentAuditPresentation.failureMessage(statusCode: nil, transport: .offline, serverMessage: "")
        XCTAssertTrue(offline.contains("nothing was recorded"))
        let dropped = EquipmentAuditPresentation.failureMessage(statusCode: nil, transport: .connectionLost, serverMessage: "")
        XCTAssertTrue(dropped.contains("Pull to refresh to see whether it was recorded"), "it may have landed — never claim it did not")
        for status in [500, 502, 503, 429] {
            let message = EquipmentAuditPresentation.failureMessage(statusCode: status, transport: nil, serverMessage: "Kabba is temporarily unavailable. Will retry.")
            XCTAssertTrue(message.contains("nothing was recorded"), "\(status)")
            XCTAssertFalse(message.lowercased().contains("will retry"), "audit writes are never retried in the background")
        }
        XCTAssertEqual(EquipmentAuditPresentation.failureMessage(statusCode: 409, transport: nil, serverMessage: "This unit changed since your screen loaded."),
                       "This unit changed since your screen loaded.", "Kabba's own refusal is shown as worded")
    }

    // MARK: Commands

    func testCommandsCarryTheStaleScreenGuardAndTheVerifiedByEmployee() throws {
        let b = try board()
        let unit = row(b, "TAK-SS-14")

        let verify = EquipmentAuditCommands.verify(audit: b.audit.uniqueId, row: unit, observedStoreId: bonAqua, performedBy: 6, operationId: "EA-0000000000000001")
        XCTAssertEqual(verify.path, "equipment-audits/\(b.audit.uniqueId)/verify")
        XCTAssertEqual(verify.operationId, "EA-0000000000000001")
        XCTAssertEqual(verify.body, .object([
            "equipment": .string(unit.equipment.uniqueId),
            "expected_key": .string(unit.expectedKey),
            "performed_by": .number(6),
            "verification_type": .string("physical"),
            "observed_store_id": .number(Double(bonAqua)),
        ]))

        let move = EquipmentAuditCommands.correctLocation(audit: "A", row: unit, observedStoreId: waverly, performedBy: 6)
        XCTAssertEqual(move.path, "equipment-audits/A/correct-location")
        XCTAssertEqual(move.body["observed_store_id"], .number(Double(waverly)))
        XCTAssertNil(move.body["notes"])

        let unresolved = EquipmentAuditCommands.markUnresolved(audit: "A", row: row(b, "SS-110"), note: "Found on the lot.", seenAtStoreId: bonAqua, performedBy: 6)
        XCTAssertEqual(unresolved.path, "equipment-audits/A/unresolved")
        XCTAssertEqual(unresolved.body["notes"], .string("Found on the lot."))
        XCTAssertEqual(unresolved.body["observed_store_id"], .number(Double(bonAqua)))

        let clear = EquipmentAuditCommands.assignVerifier(audit: "A", row: unit, employeeId: nil)
        XCTAssertEqual(clear.body["employee_id"], .null, "nil clears the override")
        XCTAssertEqual(EquipmentAuditCommands.assignSectionAuditor(audit: "A", sectionKey: "store:3", employeeId: 6).body["section_key"], .string("store:3"))

        XCTAssertNotNil(EquipmentAuditCommands.newOperationId().range(of: "^[A-Za-z0-9-]{16,64}$", options: .regularExpression),
                        "accepted by MobileRequestContext's X-Operation-Id rule")
        XCTAssertNotEqual(EquipmentAuditCommands.newOperationId(), EquipmentAuditCommands.newOperationId())
    }

    func testTheOffSiteFormSendsExactlyEquipmentsFieldsAndNoValidationOfItsOwn() throws {
        let b = try board()
        var form = EquipmentAuditOffSiteForm()
        form.source = .supplier
        form.supplierId = 1
        form.locationName = "ignored for a supplier"
        form.reason = "  Hydraulic repair "
        XCTAssertEqual(form.payload, ["location_source": .string("supplier"), "supplier_id": .number(1), "reason": .string("Hydraulic repair")])

        form = EquipmentAuditOffSiteForm()
        form.source = .manual
        form.locationName = "Humphreys County Fair"
        form.addressLine1 = "1 Fair Way"
        form.city = "Waverly"
        form.stateId = 1
        XCTAssertEqual(form.payload, ["location_source": .string("manual"), "location_name": .string("Humphreys County Fair"),
                                      "address_line_1": .string("1 Fair Way"), "city": .string("Waverly"), "state_id": .number(1)])

        // An empty form is still sent: Laravel answers with Equipment's own messages.
        let empty = EquipmentAuditCommands.moveOffSite(audit: "A", row: row(b, "TAK-SS-14"), form: EquipmentAuditOffSiteForm(), performedBy: 6)
        XCTAssertEqual(empty.path, "equipment-audits/A/off-site")
        XCTAssertEqual(empty.body["location_source"], .string("supplier"))
        XCTAssertEqual(empty.body["expected_key"], .string(row(b, "TAK-SS-14").expectedKey))
    }
}
