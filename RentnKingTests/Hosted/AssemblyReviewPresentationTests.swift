//
//  AssemblyReviewPresentationTests.swift
//  RentnKingHostedTests — Queue Line Assembly Review screen + board entities (2026-09-14)
//
//  Runs inside the app (TEST_HOST) so the real UIKit screen is exercised:
//  every frozen Product Option rendered by its stored label (including
//  "No Bucket"), the ONE affirmative control (red X + hollow Available until
//  confirmed, green check + filled Available after), the derived STOP / GO
//  badge, the Continue button hollow-and-inactive at STOP and filled at GO,
//  the removed redundancies, and the board's one-card-per-entity grouping
//  with its least-advanced lane (QueueLineBoardAssembly).
//

import XCTest
import ObjectMapper
@testable import RentnKing

final class AssemblyReviewPresentationTests: XCTestCase {

    // MARK: Fixtures

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KabbaSyncCore/Fixtures/\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Fixture \(name).json not synced") }
        return try Data(contentsOf: url)
    }

    private struct Spec {
        let uid: String
        let name: String
        let options: [(String, String, String?)]
        let unitState: String?
        var stage: String = "pending"
        var equipment: Bool = true
        var role: String = "base"
        var dependsOn: String? = nil
        var equipmentName: String? = nil
        var equipmentDisplayId: String? = nil
    }

    /// A review built from the fixture member as a template: ONE dependent
    /// assembly (or several independent lines) whose Product Options cover the
    /// vocabulary the yard actually orders — labels exactly as stored.
    private func review(groups specs: [[Spec]]) throws -> AssemblyReviewEnvelope {
        var envelope = try JSONSerialization.jsonObject(with: fixture("queue_line_assembly")) as! [String: Any]
        var data = envelope["data"] as! [String: Any]
        let template = ((data["assemblies"] as! [[String: Any]])[0]["members"] as! [[String: Any]])[0]

        func member(_ s: Spec, key: String, count: Int) -> [String: Any] {
            var m = template
            m["order_product_unique_id"] = s.uid
            var identity = m["identity"] as! [String: Any]; identity["order_product_unique_id"] = s.uid; m["identity"] = identity
            var product = m["product"] as! [String: Any]; product["name"] = s.name; m["product"] = product
            m["lifecycle_stage"] = s.stage
            m["status"] = s.stage == "staged" ? "staged" : "pending"
            m["staged"] = s.stage == "staged"
            m["product_options"] = s.options.map { (key, label, state) -> [String: Any] in
                ["unique_id": key, "name": label, "included": false,
                 "availability": ["state": state as Any, "acknowledged_by": (state == nil ? NSNull() : "Field Employee") as Any, "acknowledged_at": NSNull(), "note": NSNull()]]
            }
            var availability = m["availability"] as! [String: Any]
            var unit = availability["unit"] as! [String: Any]
            unit["state"] = s.unitState as Any
            unit["equipment_unique_id"] = s.equipment ? "EQP-\(s.uid)" : NSNull()
            availability["unit"] = unit
            let states: [String?] = [s.unitState] + s.options.map { $0.2 }
            let effective: Any
            if states.contains("not_available") { effective = "not_available" }
            else if states.allSatisfy({ $0 == "available" }) { effective = "available" }
            else { effective = NSNull() }
            availability["effective_state"] = effective
            availability["required_count"] = states.count
            availability["acknowledged_count"] = states.compactMap { $0 }.count
            m["availability"] = availability
            m["stage_blockers"] = []
            if s.equipment {
                var equipment = template["equipment"] as! [String: Any]
                equipment["unique_id"] = "EQP-\(s.uid)"; equipment["name"] = s.equipmentName ?? "\(s.name) Unit"; equipment["display_id"] = s.equipmentDisplayId ?? "U-\(s.uid)"
                m["equipment"] = equipment
                m["warnings"] = []
            } else {
                m["equipment"] = NSNull()
                m["warnings"] = [["code": "needs_equipment", "label": "No equipment selected"]]
            }
            m["assembly"] = ["key": key, "kind": count > 1 ? "dependent" : "single", "stage": "pending", "lane": "pending", "member_count": count,
                             "stage_counts": ["pending": count, "staged": 0, "in_transit": 0, "equipment_delivered": 0],
                             "dependency": ["role": s.role, "depends_on": (s.dependsOn ?? NSNull()) as Any, "depends_on_name": (s.dependsOn.map { d -> Any in specs.flatMap { $0 }.first { $0.uid == d }?.name ?? d } ?? NSNull()) as Any],
                             "gate": ["ready": false, "required_count": 0, "confirmed_count": 0, "blockers": []]]
            return m
        }

        data["assemblies"] = specs.map { group -> [String: Any] in
            let key = "QLA-\(group[0].uid)"
            return ["key": key, "kind": group.count > 1 ? "dependent" : "single", "stage": "pending", "lane": "pending", "member_count": group.count,
                    "stage_counts": ["pending": group.count, "staged": 0, "in_transit": 0, "equipment_delivered": 0],
                    "gate": ["ready": false, "required_count": 0, "confirmed_count": 0, "blockers": []],
                    "members": group.map { member($0, key: key, count: group.count) }]
        }
        data["member_count"] = specs.flatMap { $0 }.count
        envelope["data"] = data
        return try AssemblyReviewEnvelope.decode(JSONSerialization.data(withJSONObject: envelope))
    }

    /// Skid Steer (Toothed Bucket, both confirmed) + Mini Excavator (No Bucket unconfirmed,
    /// 24 Inch Not Available) + Harley Rake without a unit — one dependent assembly.
    private func threeLineReview() throws -> AssemblyReviewEnvelope {
        try review(groups: [[
            Spec(uid: "OP-SKID", name: "Skid Steer", options: [("POPT-TOOTH", "Toothed Bucket", "available")], unitState: "available", stage: "staged"),
            Spec(uid: "OP-EXC", name: "Mini Excavator", options: [("POPT-NOBKT", "No Bucket", nil), ("POPT-24", "24 Inch - Bucket", "not_available")], unitState: "available", role: "related_child", dependsOn: "OP-SKID"),
            Spec(uid: "OP-RAKE", name: "Harley Rake", options: [], unitState: nil, equipment: false, role: "related_child", dependsOn: "OP-SKID"),
        ]])
    }

    private func loaded(_ envelope: AssemblyReviewEnvelope, focusKey: String? = nil) -> AssemblyReviewViewController {
        let vc = AssemblyReviewViewController()
        vc.orderUniqueId = envelope.data.order.uniqueId
        vc.focusAssemblyKey = focusKey
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.apply(envelope)
        vc.view.layoutIfNeeded()
        return vc
    }

    private func all(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(all) }

    private func view(_ vc: UIViewController, _ id: String) -> UIView? {
        all(vc.view).first { $0.accessibilityIdentifier == id }
    }

    private func label(_ vc: UIViewController, _ id: String) -> String? {
        (view(vc, id) as? UILabel)?.attributedText?.string ?? (view(vc, id) as? UILabel)?.text
    }

    private func texts(_ vc: UIViewController) -> [String] {
        all(vc.view).compactMap { ($0 as? UILabel)?.attributedText?.string ?? ($0 as? UILabel)?.text }
    }

    // MARK: Product Options

    func testEveryFrozenProductOptionRendersByItsStoredLabelIncludingNoBucket() throws {
        let vc = loaded(try threeLineReview())

        XCTAssertEqual(label(vc, "assembly.OP-SKID.option.POPT-TOOTH.title"), "Toothed Bucket", "the stored label, not a renamed one")
        XCTAssertEqual(label(vc, "assembly.OP-EXC.option.POPT-NOBKT.title"), "No Bucket", "No Bucket is shown explicitly — intentional fulfillment")
        XCTAssertEqual(label(vc, "assembly.OP-EXC.option.POPT-24.title"), "24 Inch - Bucket")
        XCTAssertNotNil(view(vc, "assembly.OP-RAKE.options.none"), "a line without options says so instead of inventing one")
        XCTAssertNotNil(view(vc, "assembly.OP-EXC.option.POPT-NOBKT.available"), "No Bucket has its own confirmation like any other option")

        // Nothing from the rental/setup structure appears as an option row.
        let lower = texts(vc).map { $0.lowercased() }
        for word in ["prepaid", "waiver", "thrown track", "fuel level", "hours"] {
            XCTAssertFalse(lower.contains { $0.contains(word) }, "'\(word)' must never be a confirmable row")
        }
    }

    // MARK: The affirmative control

    func testUnconfirmedIsARedXWithAHollowAvailableAndConfirmedIsAGreenCheckWithAFilledOne() throws {
        let vc = loaded(try threeLineReview())

        let unconfirmed = view(vc, "assembly.OP-EXC.option.POPT-NOBKT.available") as! UIButton
        XCTAssertFalse(unconfirmed.isSelected)
        XCTAssertEqual(unconfirmed.backgroundColor, .clear, "unconfirmed = hollow Available")
        XCTAssertEqual(unconfirmed.accessibilityValue, "not confirmed")
        XCTAssertEqual(view(vc, "assembly.OP-EXC.option.POPT-NOBKT.icon")?.accessibilityLabel, "Not confirmed")
        XCTAssertEqual((view(vc, "assembly.OP-EXC.option.POPT-NOBKT.icon") as? UIImageView)?.tintColor, UIColor.redText, "a red X")
        XCTAssertEqual(label(vc, "assembly.OP-EXC.option.POPT-NOBKT.state"), "Not yet confirmed")

        let confirmed = view(vc, "assembly.OP-SKID.option.POPT-TOOTH.available") as! UIButton
        XCTAssertTrue(confirmed.isSelected)
        XCTAssertNotEqual(confirmed.backgroundColor, .clear, "confirmed = filled Available")
        XCTAssertEqual(confirmed.accessibilityValue, "confirmed")
        XCTAssertEqual(view(vc, "assembly.OP-SKID.option.POPT-TOOTH.icon")?.accessibilityLabel, "Confirmed")
        XCTAssertNotEqual((view(vc, "assembly.OP-SKID.option.POPT-TOOTH.icon") as? UIImageView)?.tintColor, UIColor.redText, "a green check")

        // A reversal (Not Available) reads as unconfirmed: X + hollow, and says why.
        let reversed = view(vc, "assembly.OP-EXC.option.POPT-24.available") as! UIButton
        XCTAssertFalse(reversed.isSelected)
        XCTAssertEqual(reversed.backgroundColor, .clear)
        XCTAssertEqual(label(vc, "assembly.OP-EXC.option.POPT-24.state"), "Not Available by Field Employee")

        // The unit row uses the same control; no unit → nothing to confirm yet.
        XCTAssertEqual(label(vc, "assembly.OP-RAKE.unit.title"), "No equipment selected")
        XCTAssertEqual(label(vc, "assembly.OP-RAKE.unit.state"), "Assign a machine first")
        XCTAssertNil(view(vc, "assembly.OP-RAKE.unit.available"), "no Available control for a machine that does not exist")
        XCTAssertTrue((view(vc, "assembly.OP-RAKE.unit.assign") as! UIButton).isEnabled, "the ONE action is to assign one")
        XCTAssertTrue((view(vc, "assembly.OP-SKID.unit.available") as! UIButton).isSelected)

        // There is no separate Not Available button anywhere.
        XCTAssertTrue(all(vc.view).filter { $0.accessibilityIdentifier?.hasSuffix(".notAvailable") == true }.isEmpty)
        XCTAssertFalse(all(vc.view).contains { ($0 as? UIButton)?.currentTitle == "Not Available" })
    }

    func testEveryAvailableButtonIsTheSameFixedSizeWhateverTheRowTextBesideIt() throws {
        let vc = loaded(try threeLineReview())
        // Two assigned units + three options carry Available; the unassigned Harley Rake carries
        // Assign in the same slot — every one of the six controls is the one fixed size.
        let buttons = all(vc.view).compactMap { $0 as? UIButton }
            .filter { ($0.accessibilityIdentifier?.hasSuffix(".available") == true) || ($0.accessibilityIdentifier?.hasSuffix(".assign") == true) }
        XCTAssertEqual(buttons.count, 6, "two units + three options + one Assign")
        XCTAssertEqual(buttons.filter { $0.accessibilityIdentifier?.hasSuffix(".assign") == true }.count, 1)
        for button in buttons {
            XCTAssertEqual(button.frame.width, AssemblyReviewViewController.confirmButtonSize.width, accuracy: 0.5, "\(button.accessibilityIdentifier ?? "") must not stretch with the row")
            XCTAssertEqual(button.frame.height, AssemblyReviewViewController.confirmButtonSize.height, accuracy: 0.5)
        }
        XCTAssertEqual(AssemblyReviewViewController.confirmButtonSize, CGSize(width: 87, height: 29), "the Toothed Bucket button from the reviewed screenshot")
    }

    // MARK: STOP / GO + Continue

    func testStopGoIsDerivedOverTheAssemblyAndTheContinueButtonFollowsIt() throws {
        let stop = loaded(try threeLineReview())
        let key = "QLA-OP-SKID"
        XCTAssertEqual(view(stop, "assemblyReview.group.\(key).gate")?.accessibilityLabel, "STOP · 3 of 6 confirmed",
                       "skid unit + Toothed Bucket + excavator unit confirmed; No Bucket, 24 Inch and the rake's unit not")
        XCTAssertEqual(label(stop, "assemblyReview.group.\(key)"), "Assembly · 3 items")
        XCTAssertEqual(label(stop, "assemblyReview.group.\(key).progress"), "1 of 3 items staged")
        XCTAssertEqual((view(stop, "assemblyReview.group.\(key).stage") as? UILabel)?.text, "Pending", "one Pending member keeps the assembly Pending")
        for uid in ["OP-SKID", "OP-EXC", "OP-RAKE"] {
            let button = view(stop, "assembly.\(uid).continue") as! UIButton
            XCTAssertFalse(button.isEnabled, "\(uid): no checklist may open while the assembly is STOP")
            XCTAssertEqual(button.backgroundColor, .clear, "\(uid): hollow while blocked")
            XCTAssertEqual(button.accessibilityValue, "blocked")
        }

        let go = loaded(try review(groups: [[
            Spec(uid: "OP-SKID", name: "Skid Steer", options: [("POPT-TOOTH", "Toothed Bucket", "available")], unitState: "available"),
            Spec(uid: "OP-CUT", name: "Brush Cutter", options: [], unitState: "available", role: "related_child", dependsOn: "OP-SKID"),
        ]]))
        XCTAssertEqual(view(go, "assemblyReview.group.\(key).gate")?.accessibilityLabel, "GO · All 3 confirmed")
        for uid in ["OP-SKID", "OP-CUT"] {
            let button = view(go, "assembly.\(uid).continue") as! UIButton
            XCTAssertTrue(button.isEnabled)
            XCTAssertEqual(button.backgroundColor, UIColor.secondary, "\(uid): the established filled cyan primary action at GO")
            XCTAssertEqual(button.accessibilityValue, "enabled")
        }
        XCTAssertEqual(label(go, "assembly.OP-CUT.dependency"), "Goes with Skid Steer")
        XCTAssertNil(view(go, "assembly.OP-SKID.dependency"), "the base product needs no such line")
    }

    // MARK: Removed redundancies + layout

    func testTheScreenIsQuietNothingRepeatsWhatTheControlsAlreadySay() throws {
        let vc = loaded(try threeLineReview())
        let all = texts(vc)

        XCTAssertNotNil(view(vc, "assemblyReview.order"))
        XCTAssertNil(view(vc, "assemblyReview.customer"), "no repeated customer header")
        XCTAssertFalse(all.contains { $0.contains("Everything ordered has to be") }, "no generic instructional paragraph")
        XCTAssertTrue((view(vc, "assemblyReview.freshness") as? UILabel)?.isHidden ?? true, "freshness only when offline / pending sync")
        XCTAssertFalse(all.contains { $0.hasPrefix("Unit status:") }, "no redundant unit-status badge")
        for uid in ["OP-SKID", "OP-EXC", "OP-RAKE"] {
            XCTAssertNil(view(vc, "assembly.\(uid).effective"), "\(uid): no Item availability summary — STOP/GO replaces it")
            XCTAssertNil(view(vc, "assembly.\(uid).checklist"), "\(uid): no Checklist: … line")
            XCTAssertNil(view(vc, "assembly.\(uid).blockers"), "\(uid): no Cannot be staged paragraph")
            XCTAssertNil(view(vc, "assembly.\(uid).unbundle"), "\(uid): true dependencies cannot be unbundled")
            XCTAssertNil(view(vc, "assembly.\(uid).rebundle"))
            XCTAssertNotNil(view(vc, "assembly.\(uid).continue"))
        }
        XCTAssertFalse(all.contains { $0.hasPrefix("Checklist:") || $0.hasPrefix("Cannot be staged") || $0.hasPrefix("Item availability") })
        XCTAssertNil(view(vc, "assembly.OP-EXC.option.POPT-24.unbundle"), "Product Options are never unbundled")

        // Layout: the checklist action uses the card's full width (no Unbundle beside it).
        let card = view(vc, "assembly.OP-SKID")!
        let cont = view(vc, "assembly.OP-SKID.continue")!
        XCTAssertGreaterThan(cont.frame.width, card.frame.width - 40, "Continue spans the card")
    }

    func testTheFixtureReviewRendersTheDependentAssemblyAndFocusShowsOnlyTheTappedEntity() throws {
        let vc = loaded(try AssemblyReviewEnvelope.decode(fixture("queue_line_assembly")))
        let groups = vc.review!.assemblies
        XCTAssertEqual(groups.count, 1)
        XCTAssertNotNil(view(vc, "assemblyReview.group.\(groups[0].key)"))
        XCTAssertNotNil(view(vc, "assemblyReview.group.\(groups[0].key).gate"))
        XCTAssertEqual(label(vc, "assembly.\(groups[0].members[1].orderProductUniqueId).dependency"), "Goes with \(groups[0].members[0].product.name!)")
        XCTAssertNotNil(vc.employeeUniqueId, "who is acting comes from meta.employee")

        // Two entities on one order; the card that opened the review names one.
        let two = try review(groups: [
            [Spec(uid: "OP-SKID", name: "Skid Steer", options: [], unitState: nil), Spec(uid: "OP-CUT", name: "Brush Cutter", options: [], unitState: nil, role: "related_child", dependsOn: "OP-SKID")],
            [Spec(uid: "OP-BOOM", name: "Boom Lift", options: [], unitState: "available")],
        ])
        let focused = loaded(two, focusKey: "QLA-OP-BOOM")
        XCTAssertNotNil(view(focused, "assemblyReview.group.QLA-OP-BOOM"))
        XCTAssertNil(view(focused, "assemblyReview.group.QLA-OP-SKID"), "the independent Skid Steer assembly has its own card")
        XCTAssertEqual(view(focused, "assemblyReview.group.QLA-OP-BOOM.gate")?.accessibilityLabel, "GO · Confirmed", "the Boom Lift is GO on its own while the other assembly is STOP")
        XCTAssertEqual(label(focused, "assemblyReview.group.QLA-OP-BOOM"), "Item")
        XCTAssertTrue((view(focused, "assembly.OP-BOOM.continue") as! UIButton).isEnabled)

        let unfocused = loaded(two)
        XCTAssertNotNil(view(unfocused, "assemblyReview.group.QLA-OP-SKID"))
        XCTAssertNotNil(view(unfocused, "assemblyReview.group.QLA-OP-BOOM"))
        XCTAssertEqual(view(unfocused, "assemblyReview.group.QLA-OP-SKID.gate")?.accessibilityLabel, "STOP · 0 of 2 confirmed")
    }

    // MARK: Board grouping

    private func item(_ uid: String, order: String, name: String, stage: String, key: String, memberCount: Int = 1) -> QueueLineModel {
        Mapper<QueueLineModel>().map(JSON: [
            "order_product_unique_id": uid, "order_unique_id": order, "order_number": "9301", "customer_name": "Queue Customer",
            "identity": ["order_unique_id": order, "order_product_unique_id": uid],
            "product": ["name": name], "status": stage == "equipment_delivered" ? "completed" : (stage == "pending" ? "pending" : "staged"),
            "lifecycle_stage": stage,
            "assembly": ["key": key, "kind": memberCount > 1 ? "dependent" : "single", "stage": stage, "lane": "pending",
                         "member_count": memberCount, "stage_counts": ["pending": 0, "staged": 0, "in_transit": 0, "equipment_delivered": 0],
                         "dependency": ["role": "base"], "gate": ["ready": false, "required_count": 1, "confirmed_count": 0, "blockers": []]],
        ])!
    }

    func testTheBoardShowsOneCardPerEntityAndIndependentSameOrderLinesStaySeparate() {
        let items = [
            item("A1", order: "ORD-A", name: "Skid Steer", stage: "staged", key: "QLA-A1", memberCount: 3),
            item("A2", order: "ORD-A", name: "Brush Cutter", stage: "pending", key: "QLA-A1", memberCount: 3),
            item("A3", order: "ORD-A", name: "Auger", stage: "in_transit", key: "QLA-A1", memberCount: 3),
            item("A4", order: "ORD-A", name: "Boom Lift", stage: "staged", key: "QLA-A4"),
            item("B1", order: "ORD-B", name: "Excavator", stage: "staged", key: "QLA-B1"),
            item("C1", order: "ORD-C", name: "Roller", stage: "equipment_delivered", key: "QLA-C1"),
        ]
        let groups = QueueLineBoardAssembly.groups(items, queue: QueueLineLocalOverlay(), assembly: AssemblyLocalOverlay())

        XCTAssertEqual(groups.map(\.key), ["QLA-A1", "QLA-A4", "QLA-B1", "QLA-C1"], "the unrelated Boom Lift on order A is its own card; separate orders never merge")
        XCTAssertEqual(groups[0].lane, "pending", "one Pending member keeps the whole assembly in Pending")
        XCTAssertEqual(groups[0].members.count, 3)
        XCTAssertEqual(groups[0].beyondPending, 2)
        XCTAssertEqual(groups[0].primary.product?.name, "Brush Cutter", "the card leads with the member holding the assembly at Pending")
        XCTAssertEqual(QueueLineBoardAssembly.contextLine(for: groups[0]), "3 items · 2 of 3 staged · with Skid Steer, Auger")
        XCTAssertEqual(groups[1].lane, "staged", "the independent Boom Lift progresses on its own")
        XCTAssertNil(QueueLineBoardAssembly.contextLine(for: groups[1]), "a line on its own reads exactly as before")
        XCTAssertEqual(groups[2].lane, "staged")
        XCTAssertEqual(groups[3].lane, "completed")
    }

    func testAFilterThatHidesMembersStillReportsTheWholeAssembly() {
        let items = [item("A1", order: "ORD-A", name: "Skid Steer", stage: "pending", key: "QLA-A1", memberCount: 3)]
        let groups = QueueLineBoardAssembly.groups(items, queue: QueueLineLocalOverlay(), assembly: AssemblyLocalOverlay())
        XCTAssertEqual(groups[0].totalMembers, 3)
        XCTAssertEqual(QueueLineBoardAssembly.contextLine(for: groups[0]), "3 items · 0 of 3 staged · showing 1 of 3")
    }

    // MARK: Universal entry (2026-09-14) — every origin, one road

    /// The one member the review continues with — a single line, no options.
    private func simpleMember() throws -> AssemblyMember {
        let envelope = try review(groups: [[Spec(uid: "OP-PC", name: "Plate Compactor", options: [], unitState: "available")]])
        return envelope.data.assemblies[0].members[0]
    }

    func testEveryOriginContinuesIntoTheSameFocusedDeliveryChecklist() throws {
        let member = try simpleMember()
        let queue = try XCTUnwrap(ChecklistEntry.makeChecklist(for: member, origin: .queueLine))
        let list = try XCTUnwrap(ChecklistEntry.makeChecklist(for: member, origin: ChecklistEntry.Origin(kind: .orderList, selectIndex: 4)))
        let details = try XCTUnwrap(ChecklistEntry.makeChecklist(for: member, origin: ChecklistEntry.Origin(kind: .orderDetails, selectIndex: 2, fromCheckListScreen: true)))

        for vc in [queue, list, details] {
            XCTAssertTrue(vc.isDeliveryType, "Assembly Review gates the outbound leg")
            XCTAssertTrue(vc.queueLineFocusedStaging, "every review-entered checklist is focused on its member")
            XCTAssertEqual(vc.focusOrderProductUniqueId, "OP-PC")
            XCTAssertEqual(vc.strOrderUniqueId, member.orderUniqueId)
            XCTAssertEqual(vc.strOrderID, member.orderNumber)
            XCTAssertEqual(vc.queueLineEquipmentUniqueId, member.identity.equipmentUniqueId, "the member's identity unit is the unit the checklist opens on")
        }
        // Only the origin flags differ — the downstream behaviour each entry point had.
        XCTAssertTrue(queue.isQueueLine)
        XCTAssertFalse(queue.isOrderDetailsView)
        XCTAssertFalse(list.isQueueLine)
        XCTAssertFalse(list.isOrderDetailsView)
        XCTAssertEqual(list.selectIndex, 4)
        XCTAssertFalse(details.isQueueLine)
        XCTAssertTrue(details.isOrderDetailsView)
        XCTAssertTrue(details.fromCheckListScreen)
        XCTAssertEqual(details.selectIndex, 2)
    }

    func testTheReviewOpensOnceForAnOrderAndCarriesItsOrigin() {
        let nav = UINavigationController(rootViewController: UIViewController())

        let details = ChecklistEntry.openAssemblyReview(on: nav, orderUniqueId: "ORD-1", orderNumber: "9305",
                                                        origin: ChecklistEntry.Origin(kind: .orderDetails, selectIndex: 1), animated: false)
        XCTAssertEqual(details?.origin, ChecklistEntry.Origin(kind: .orderDetails, selectIndex: 1))
        XCTAssertEqual(details?.orderNumber, "9305")
        XCTAssertNil(details?.focusAssemblyKey, "Order Details shows every entity of the order, each with its own gate")
        XCTAssertEqual(nav.viewControllers.count, 2)

        // A second tap while this order's review is on top pushes nothing.
        XCTAssertNil(ChecklistEntry.openAssemblyReview(on: nav, orderUniqueId: "ORD-1", orderNumber: "9305", origin: .queueLine, animated: false))
        XCTAssertEqual(nav.viewControllers.count, 2, "repeated pushes are prevented")

        // A Queue Line card names its member and entity; the review is focused on them.
        let card = ChecklistEntry.openAssemblyReview(on: nav, orderUniqueId: "ORD-2", orderNumber: "9301",
                                                     focusOrderProductUniqueId: "OP-SKID", focusAssemblyKey: "QLA-OP-SKID",
                                                     origin: .queueLine, animated: false)
        XCTAssertEqual(card?.focusAssemblyKey, "QLA-OP-SKID")
        XCTAssertEqual(card?.focusOrderProductUniqueId, "OP-SKID")
        XCTAssertEqual(card?.origin, .queueLine)
        XCTAssertEqual(nav.viewControllers.count, 3)

        XCTAssertNil(ChecklistEntry.openAssemblyReview(on: nav, orderUniqueId: "", orderNumber: "", origin: .queueLine, animated: false), "no order, no review")
        XCTAssertNil(ChecklistEntry.openAssemblyReview(on: nil, orderUniqueId: "ORD-3", orderNumber: "1", origin: .queueLine, animated: false))
    }

    func testAfterTheChecklistNavigationReturnsToTheReviewFirstAndTheOriginStaysBeneath() {
        let origin = UIViewController()
        let review = AssemblyReviewViewController()
        let checklist = UIViewController()
        let upload = UIViewController()
        let nav = UINavigationController(rootViewController: origin)
        nav.setViewControllers([origin, review, checklist, upload], animated: false)

        var fellBack = false
        XCTAssertTrue(ChecklistEntry.returnToReview(on: nav, animated: false) { fellBack = true })
        XCTAssertFalse(fellBack)
        XCTAssertTrue(nav.topViewController === review, "the Assembly Review is the first stop after the checklist")
        XCTAssertEqual(nav.viewControllers.count, 2)
        XCTAssertTrue(nav.viewControllers.first === origin, "the origin stays beneath the review — Back returns there, wherever it was")

        // A legacy stack without a review keeps the caller's own navigation.
        let legacy = UINavigationController(rootViewController: UIViewController())
        legacy.pushViewController(UIViewController(), animated: false)
        fellBack = false
        XCTAssertFalse(ChecklistEntry.returnToReview(on: legacy, animated: false) { fellBack = true })
        XCTAssertTrue(fellBack)
        XCTAssertEqual(legacy.viewControllers.count, 2, "the fallback decides — nothing was popped for it")
    }

    func testAnInTransitMemberStillContinuesToItsChecklistWhileADeliveredOneDoesNot() throws {
        // The driver completes the SAME Delivery Checklist at the customer (Order Details →
        // Assembly Review → checklist → signature) while the unit is In Transit — the review
        // must not dead-end that flow. Its confirmations are frozen (the truck has left) and
        // the gate has nothing left to ask. Delivered equipment has no checklist to continue to.
        let envelope = try review(groups: [
            [Spec(uid: "OP-TRANSIT", name: "Skid Steer", options: [("POPT-TOOTH", "Toothed Bucket", "available")], unitState: "available", stage: "in_transit")],
            [Spec(uid: "OP-DONE", name: "Boom Lift", options: [], unitState: "available", stage: "equipment_delivered")],
        ])
        let vc = loaded(envelope)

        let transitContinue = try XCTUnwrap(view(vc, "assembly.OP-TRANSIT.continue") as? UIButton)
        XCTAssertTrue(transitContinue.isEnabled, "In Transit: the checklist may still be continued (completion at the customer)")
        XCTAssertEqual(transitContinue.accessibilityValue, "enabled")
        XCTAssertEqual(view(vc, "assemblyReview.group.QLA-OP-TRANSIT.gate")?.accessibilityLabel, "GO · Nothing left to confirm")
        XCTAssertFalse((view(vc, "assembly.OP-TRANSIT.unit.available") as? UIButton)?.isEnabled ?? true, "confirmations are frozen once the truck has left")
        XCTAssertFalse((view(vc, "assembly.OP-TRANSIT.option.POPT-TOOTH.available") as? UIButton)?.isEnabled ?? true)

        XCTAssertNil(view(vc, "assembly.OP-DONE.continue"), "delivered equipment has nothing left to continue to")
    }

    // MARK: Equipment identity + assignment (2026-09-14)

    func testTheMachineIsNamedTheWayTheYardNamesItAndItsIdentityChangesTheAssignment() throws {
        // A unit whose name is NOT the ordered product's name, a long name and a long tag,
        // and a plain one — the technician must be able to read which machine to pull.
        let envelope = try review(groups: [
            [Spec(uid: "OP-SKID", name: "Skid Steer", options: [], unitState: nil, equipmentName: "Kubota SVL75", equipmentDisplayId: "1234")],
            [Spec(uid: "OP-LONG", name: "Mini Excavator", options: [], unitState: "available",
                  equipmentName: "SANY SW405K High-Flow Cab Skid Steer Loader with Pilot Controls", equipmentDisplayId: "WH-0000-2026-LONG-TAG-0042")],
            [Spec(uid: "OP-PC", name: "Plate Compactor", options: [], unitState: nil)],
        ])
        let vc = loaded(envelope)

        XCTAssertEqual(label(vc, "assembly.OP-SKID.unit.title"), "Kubota SVL75 · #1234", "name first, then the tag — never the tag alone")
        XCTAssertEqual(label(vc, "assembly.OP-LONG.unit.title"), "SANY SW405K High-Flow Cab Skid Steer Loader with Pilot Controls · #WH-0000-2026-LONG-TAG-0042")
        XCTAssertEqual((view(vc, "assembly.OP-LONG.unit.title") as? UILabel)?.numberOfLines, 0, "a long identity wraps, it is never clipped")
        XCTAssertEqual(label(vc, "assembly.OP-PC.unit.title"), "Plate Compactor Unit · #U-OP-PC")
        XCTAssertFalse(texts(vc).contains { $0.hasPrefix("Unit: ") }, "the identity is the row itself — no second unit line")

        // The identity is the affordance for changing the assignment (no separate Reassign button).
        for uid in ["OP-SKID", "OP-LONG", "OP-PC"] {
            let change = try XCTUnwrap(view(vc, "assembly.\(uid).unit.reassign") as? UIButton, "\(uid) identity must be tappable")
            XCTAssertTrue(change.isEnabled)
            XCTAssertEqual(change.accessibilityLabel, "Change equipment")
            XCTAssertEqual(change.accessibilityValue, label(vc, "assembly.\(uid).unit.title"))
        }
        XCTAssertFalse(texts(vc).contains("Reassign"))

        // Availability is a separate subject from identity: the unconfirmed one still has its X + hollow Available.
        XCTAssertEqual((view(vc, "assembly.OP-SKID.unit.available") as? UIButton)?.accessibilityValue, "not confirmed")
        XCTAssertEqual((view(vc, "assembly.OP-LONG.unit.available") as? UIButton)?.accessibilityValue, "confirmed")
    }

    func testAMachineThatLeftTheYardIsNotReassignableFromTheReview() throws {
        let envelope = try review(groups: [
            [Spec(uid: "OP-TRANSIT", name: "Skid Steer", options: [], unitState: "available", stage: "in_transit")],
            [Spec(uid: "OP-DONE", name: "Boom Lift", options: [], unitState: "available", stage: "equipment_delivered")],
        ])
        let vc = loaded(envelope)
        XCTAssertNil(view(vc, "assembly.OP-TRANSIT.unit.reassign"), "In Transit: the machine cannot change (the checklist's own rule)")
        XCTAssertNil(view(vc, "assembly.OP-DONE.unit.reassign"))
        XCTAssertEqual(label(vc, "assembly.OP-TRANSIT.unit.title"), "Skid Steer Unit · #U-OP-TRANSIT", "still named the same way")
    }

    func testThePickerRowsAreTheChecklistsStatusSectionsInTheChecklistsFormat() {
        let rows = EquipmentAssignmentFlow.rows(for: [
            EquipmentCandidate(uniqueId: "E1", displayId: "1234", name: "Kubota SVL75", statusLabel: "Available", requiresReason: false),
            EquipmentCandidate(uniqueId: "E2", displayId: "5678", name: "SANY SW405K", statusLabel: "Maint. Hold", requiresReason: true),
            EquipmentCandidate(uniqueId: "E3", displayId: "9012", name: "Bobcat T66", statusLabel: "Available", requiresReason: false),
        ])
        XCTAssertEqual(rows, ["Section: Available", "Kubota SVL75    ||    1234", "Bobcat T66    ||    9012",
                              "Section: Maint. Hold", "SANY SW405K    ||    5678"])
    }
}
