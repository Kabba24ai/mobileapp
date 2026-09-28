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
        var includedOptions: Set<String> = []
    }

    /// A review built from the fixture member as a template: ONE dependent
    /// assembly (or several independent lines) whose Product Options cover the
    /// vocabulary the yard actually orders — labels exactly as stored.
    private func review(groups specs: [[Spec]], orderNumber: String? = nil) throws -> AssemblyReviewEnvelope {
        var envelope = try JSONSerialization.jsonObject(with: fixture("queue_line_assembly")) as! [String: Any]
        var data = envelope["data"] as! [String: Any]
        if let orderNumber = orderNumber {
            var order = data["order"] as! [String: Any]; order["order_number"] = orderNumber; data["order"] = order
        }
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
                ["unique_id": key, "name": label, "included": s.includedOptions.contains(key),
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
        XCTAssertEqual(label(vc, "assembly.OP-EXC.option.POPT-NOBKT.state") ?? "", "", "an unconfirmed option carries no helper copy — the red X and Available say it")

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

    /// 2026-09-18: the sections follow the operational order — Available, Maint. Hold, Damaged,
    /// Rented — not the alphabet (which would put Damaged before Maint. Hold); within a section
    /// the server's order (name, then Equipment ID) is kept verbatim.
    func testThePickerSectionsReadAvailableHoldDamagedRentedWithTheServersOrderInsideEach() {
        let unit = { (id: String, name: String, status: String) in EquipmentCandidate(uniqueId: id, displayId: id, name: name, statusLabel: status, requiresReason: false) }
        let rows = EquipmentAssignmentFlow.rows(for: [
            unit("ATT-SS-F-1", "Skid Steer - Forks", "Available"), unit("ATT-SS-F-4", "Skid Steer - Forks", "Available"), unit("ATT-SS-G-1", "Skid Steer - Grapple", "Available"),
            unit("ATT-SS-F-7", "Skid Steer - Forks", "Maint. Hold"), unit("ATT-SS-T-1", "Skid Steer - Trencher", "Maint. Hold"),
            unit("ATT-SS-B-1", "Skid Steer - Broom", "Damaged"), unit("ATT-SS-F-3", "Skid Steer - Forks", "Damaged"),
            unit("ATT-SS-A-1", "Skid Steer - Auger", "Rented"), unit("ATT-SS-F-9", "Skid Steer - Forks", "Rented"),
        ])
        XCTAssertEqual(rows, [
            "Section: Available", "Skid Steer - Forks    ||    ATT-SS-F-1", "Skid Steer - Forks    ||    ATT-SS-F-4", "Skid Steer - Grapple    ||    ATT-SS-G-1",
            "Section: Maint. Hold", "Skid Steer - Forks    ||    ATT-SS-F-7", "Skid Steer - Trencher    ||    ATT-SS-T-1",
            "Section: Damaged", "Skid Steer - Broom    ||    ATT-SS-B-1", "Skid Steer - Forks    ||    ATT-SS-F-3",
            "Section: Rented", "Skid Steer - Auger    ||    ATT-SS-A-1", "Skid Steer - Forks    ||    ATT-SS-F-9",
        ])
    }

    /// The review host's picker opens in the category Laravel resolved (the current unit's, else
    /// the ordered product's), shows it on the Category pill above the Search pill, and every
    /// re-read goes back to the server with (category, term): a search stays within the category,
    /// a category change clears the term and refetches, "All categories" is the whole fleet. The
    /// checklist host passes no source and keeps its one-row header. Nothing here decides eligibility.
    func testThePickerOpensInTheServersCategoryChangingItRefetchesAndSearchStaysWithinIt() {
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        let flow = EquipmentAssignmentFlow(host: host)
        let att = EquipmentCategoryOption(uniqueId: "PCAT-ATT", title: "Attachments - Skid Steer")
        let exc = EquipmentCategoryOption(uniqueId: "PCAT-EXC", title: "Excavators")
        let unit = { (id: String, name: String, status: String) in EquipmentCandidate(uniqueId: id, displayId: id, name: name, statusLabel: status, requiresReason: true) }
        let forks1 = unit("ATT-SS-F-1", "Skid Steer - Forks", "Available")
        let forks7 = unit("ATT-SS-F-7", "Skid Steer - Forks", "Maint. Hold")
        let broom = unit("ATT-SS-B-1", "Skid Steer - Broom", "Damaged")
        let auger = unit("ATT-SS-A-1", "Skid Steer - Auger", "Rented")
        let attUnits = [forks1, forks7, broom, auger]
        let excavator = unit("EXC-1", "Mini Excavator", "Available")
        var asked: [String] = []
        let source = EquipmentAssignmentFlow.CandidateSource(
            fetch: { category, term, deliver in
                asked.append("\(category?.uniqueId ?? "all")|\(term)")
                switch (category?.uniqueId, term) {
                case ("PCAT-ATT", "Forks"): deliver([forks1, forks7])
                case ("PCAT-ATT", _): deliver(attUnits)
                case ("PCAT-EXC", _): deliver([excavator])
                default: deliver(attUnits + [excavator])
                }
            },
            categories: { deliver in deliver([att, exc]) })

        // Opens scoped to Laravel's default, Category pill + Search pill, sections in operational order.
        flow.pick(from: attUnits, category: att, source: source) { _ in }
        XCTAssertTrue(flow.categoryIsOffered)
        XCTAssertEqual(flow.categoryPillTitle, "Attachments - Skid Steer")
        XCTAssertEqual(flow.currentCategory, att)
        XCTAssertTrue(flow.searchIsOffered)
        XCTAssertEqual(flow.searchPillTitle, "🔍 \(EquipmentAssignmentFlow.searchTitle)")
        XCTAssertEqual(flow.currentRows, ["Section: Available", forks1.pickerRow, "Section: Maint. Hold", forks7.pickerRow,
                                          "Section: Damaged", broom.pickerRow, "Section: Rented", auger.pickerRow])
        XCTAssertEqual(asked, [], "the opening list came with the pick — no second read")

        // Search stays within the category.
        let searched = expectation(description: "searched")
        flow.performSearch("Forks") { searched.fulfill() }
        wait(for: [searched], timeout: 5)
        XCTAssertEqual(asked, ["PCAT-ATT|Forks"])
        XCTAssertEqual(flow.currentRows, ["Section: Available", forks1.pickerRow, "Section: Maint. Hold", forks7.pickerRow])
        XCTAssertEqual(flow.searchPillTitle, "🔍 “Forks” · Show all")

        // Changing the category clears the term and refetches that category whole.
        let changed = expectation(description: "category changed")
        flow.selectCategory(exc) { changed.fulfill() }
        wait(for: [changed], timeout: 5)
        XCTAssertEqual(asked.last, "PCAT-EXC|")
        XCTAssertEqual(flow.currentCategory, exc)
        XCTAssertEqual(flow.categoryPillTitle, "Excavators")
        XCTAssertEqual(flow.currentSearchTerm, "")
        XCTAssertEqual(flow.searchPillTitle, "🔍 \(EquipmentAssignmentFlow.searchTitle)")
        XCTAssertEqual(flow.currentRows, ["Section: Available", excavator.pickerRow])

        // Re-choosing the same category asks nothing; "All categories" is the whole eligible fleet.
        let same = expectation(description: "same category")
        flow.selectCategory(exc) { same.fulfill() }
        wait(for: [same], timeout: 5)
        XCTAssertEqual(asked.count, 2)
        let all = expectation(description: "all categories")
        flow.selectCategory(nil) { all.fulfill() }
        wait(for: [all], timeout: 5)
        XCTAssertEqual(asked.last, "all|")
        XCTAssertNil(flow.currentCategory)
        XCTAssertEqual(flow.categoryPillTitle, EquipmentCategoryOption.allTitle)
        XCTAssertTrue(flow.currentRows.contains(excavator.pickerRow) && flow.currentRows.contains(auger.pickerRow))

        // Show all after a search returns to the current category's full list.
        let again = expectation(description: "searched again")
        flow.performSearch("Forks") { again.fulfill() }
        wait(for: [again], timeout: 5)
        XCTAssertEqual(asked.last, "all|Forks")
        flow.clearSearch()
        XCTAssertEqual(flow.currentSearchTerm, "")
        XCTAssertTrue(flow.currentRows.contains(excavator.pickerRow))

        // Checklist host: no source → no Category pill, the plain one-row header.
        flow.pick(from: attUnits) { _ in }
        XCTAssertFalse(flow.categoryIsOffered)
        XCTAssertNil(flow.categoryPillTitle)
        XCTAssertFalse(flow.searchIsOffered)
        XCTAssertEqual(flow.searchPillTitle, EquipmentAssignmentFlow.title)
    }

    // MARK: 1.0.21 (1007) · the heading carries exactly one hash

    func testTheHeadingReadsOrderHashNumberWhetherTheStoredNumberHasAHashOrNot() throws {
        for stored in ["4287", "#4287"] {
            let vc = loaded(try review(groups: [[Spec(uid: "OP-A", name: "3 Ton", options: [], unitState: nil, equipment: false)]], orderNumber: stored))
            XCTAssertEqual(label(vc, "assemblyReview.order"), "Order #4287", "stored as '\(stored)'")
        }
    }

    // MARK: 1.0.21 (1007) · candidate discovery beyond the prioritized first page

    /// The checklist host passes no provider and keeps its plain picker; the review host's
    /// picker offers Search: the server's matches replace the wheel (in the server's order) and
    /// "Show all" restores the prioritized first page. Nothing here decides eligibility.
    func testThePickerOffersSearchOnlyWithAProviderAndSearchReplacesTheWheelWithTheServersMatches() {
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        let flow = EquipmentAssignmentFlow(host: host)
        let firstPage = [EquipmentCandidate(uniqueId: "D1", displayId: "QLA-SK3", name: "Skid Steer Spare", statusLabel: "Available", requiresReason: false)]
            + (1...24).map { EquipmentCandidate(uniqueId: "F\($0)", displayId: String(format: "QLA-F%02d", $0), name: String(format: "A Filler %02d", $0), statusLabel: "Available", requiresReason: true) }
        let beyond = EquipmentCandidate(uniqueId: "Z1", displayId: "QLA-ALT1", name: "Other Machine Spare", statusLabel: "Available", requiresReason: true)

        // Checklist host: the category-scoped fleet list is complete → no search, the plain title.
        flow.pick(from: firstPage) { _ in }
        XCTAssertFalse(flow.searchIsOffered)
        XCTAssertFalse(flow.searchPillIsInteractive)
        XCTAssertEqual(flow.searchPillTitle, EquipmentAssignmentFlow.title)
        XCTAssertEqual(flow.currentRows.count, 26, "25 units + the Available section header")

        // Review host: the prioritized first page (direct spare first) plus Search.
        var asked: [String] = []
        flow.pick(from: firstPage, search: { term, deliver in asked.append(term); deliver(term == "Other Machine" ? [beyond] : []) }) { _ in }
        XCTAssertTrue(flow.searchIsOffered)
        XCTAssertTrue(flow.searchPillIsInteractive)
        XCTAssertEqual(flow.searchPillTitle, "🔍 \(EquipmentAssignmentFlow.searchTitle)")
        XCTAssertEqual(flow.currentRows.prefix(2), ["Section: Available", "Skid Steer Spare    ||    QLA-SK3"], "direct match still heads the wheel")
        XCTAssertFalse(flow.currentRows.contains(beyond.pickerRow), "the alternate sits beyond the first page")

        let searched = expectation(description: "search delivered")
        flow.performSearch("Other Machine") { searched.fulfill() }
        wait(for: [searched], timeout: 5)
        XCTAssertEqual(asked, ["Other Machine"])
        XCTAssertEqual(flow.currentRows, ["Section: Available", "Other Machine Spare    ||    QLA-ALT1"], "the wheel now holds the server's matches")
        XCTAssertEqual(flow.currentSearchTerm, "Other Machine")
        XCTAssertEqual(flow.searchPillTitle, "🔍 “Other Machine” · Show all")

        flow.clearSearch()
        XCTAssertEqual(flow.currentSearchTerm, "")
        XCTAssertEqual(flow.currentRows.count, 26, "Show all restores the prioritized first page")
        XCTAssertFalse(flow.currentRows.contains(beyond.pickerRow))
    }

    // MARK: - Driver Delivery Process Flow (2026-09-27), Task 11 — the driver origin

    // MARK: - Status badges as Back shortcuts; unconfirmed rows without helper copy (2026-09-28)

    /// The review pushed over a root screen — a badge tap must land back on that root.
    private func pushed(_ vc: AssemblyReviewViewController) -> (root: UIViewController, nav: UINavigationController) {
        let root = UIViewController()
        let nav = UINavigationController(rootViewController: root)
        nav.pushViewController(vc, animated: false)
        return (root, nav)
    }

    /// Taps the badge's own control (the badge stays a label; the control is its overlay).
    private func tapBadge(_ vc: UIViewController, _ id: String) -> Bool {
        guard let badge = view(vc, id), let button = badge.subviews.compactMap({ $0 as? UIButton }).first else { return false }
        button.sendActions(for: .touchUpInside)
        return true
    }

    private func badgeStyle(_ vc: UIViewController, _ id: String) -> (text: UIColor?, background: UIColor?) {
        let label = view(vc, id) as? UILabel
        return (label?.textColor, label?.backgroundColor)
    }

    func testInTransitBadgesOnTheHeaderAndTheCardPopToThePreviousScreenLikeTheBackArrow() throws {
        let envelope = try review(groups: [[Spec(uid: "OP-T", name: "Skid Steer", options: [("POPT-TOOTH", "Toothed Bucket", "available")],
                                                 unitState: "available", stage: "in_transit")]])
        for id in ["assemblyReview.group.QLA-OP-T.stage", "assembly.OP-T.stage"] {
            let vc = loaded(envelope)
            XCTAssertEqual(label(vc, id), "In Transit", id)
            let (root, nav) = pushed(vc)
            let opsBefore = KabbaSync.engine?.snapshot().count
            let unitButton = view(vc, "assembly.OP-T.unit.available") as? UIButton
            XCTAssertTrue(tapBadge(vc, id), "\(id) is tappable")
            XCTAssertTrue(nav.topViewController === root, "\(id) returns to the previous screen, like the back arrow")
            XCTAssertEqual(KabbaSync.engine?.snapshot().count, opsBefore, "navigation only: no operation recorded")
            XCTAssertEqual(unitButton?.accessibilityValue, "confirmed", "navigation only: the confirmation is untouched")
            XCTAssertEqual(label(vc, "assembly.OP-T.stage"), "In Transit", "navigation only: the stage is untouched")
        }
    }

    func testEquipmentDeliveredBadgesOnTheHeaderAndTheCardPopToThePreviousScreenLikeTheBackArrow() throws {
        let envelope = try review(groups: [[Spec(uid: "OP-D", name: "Boom Lift", options: [], unitState: "available", stage: "equipment_delivered")]])
        for id in ["assemblyReview.group.QLA-OP-D.stage", "assembly.OP-D.stage"] {
            let vc = loaded(envelope)
            XCTAssertEqual(label(vc, id), "Equipment Delivered", id)
            let (root, nav) = pushed(vc)
            let opsBefore = KabbaSync.engine?.snapshot().count
            XCTAssertTrue(tapBadge(vc, id), "\(id) is tappable")
            XCTAssertTrue(nav.topViewController === root, "\(id) returns to the previous screen, like the back arrow")
            XCTAssertEqual(KabbaSync.engine?.snapshot().count, opsBefore, "navigation only: no operation recorded")
            XCTAssertEqual(label(vc, "assembly.OP-D.stage"), "Equipment Delivered", "navigation only: the stage is untouched")
        }
    }

    func testTheDriversPostDepartureReviewBadgesPopBackAndTheUnitStaysLocked() throws {
        // The driver's own On My Way promotes the line to In Transit and locks the review;
        // the badge is a way back, never a way around the lock.
        let product = "OP-GONE"
        let envelope = try review(groups: [[Spec(uid: product, name: "Skid Steer", options: [], unitState: "available", stage: "staged")]])
        let vc = loadedDriver(envelope, product: product, enteredFrom: .driverChecklist, isRevisit: true,
                              ops: [driverOp(product, status: "On My Way")])
        XCTAssertEqual(label(vc, "assembly.\(product).stage"), "In Transit")
        XCTAssertNil(view(vc, "assembly.\(product).unit.reassign"), "post-departure: the unit cannot be changed")
        let (root, nav) = pushed(vc)
        XCTAssertTrue(tapBadge(vc, "assembly.\(product).stage"))
        XCTAssertTrue(nav.topViewController === root)
        XCTAssertNil(view(vc, "assembly.\(product).unit.reassign"), "still locked after the tap")
        XCTAssertFalse((view(vc, "assembly.\(product).unit.available") as? UIButton)?.isEnabled ?? true, "still read-only after the tap")
    }

    func testPendingAndStagedBadgesAreNotBackShortcuts() throws {
        let envelope = try review(groups: [[Spec(uid: "OP-P", name: "Skid Steer", options: [], unitState: nil, stage: "pending")],
                                           [Spec(uid: "OP-S", name: "Auger", options: [], unitState: "available", stage: "staged")]])
        let vc = loaded(envelope)
        for id in ["assembly.OP-P.stage", "assembly.OP-S.stage", "assemblyReview.group.QLA-OP-P.stage"] {
            XCTAssertFalse(tapBadge(vc, id), "\(id): a pre-departure badge is a status, not a control")
        }
    }

    func testInTransitReadsBlackOnTheLightBlueBadgeAndEquipmentDeliveredIsUnchanged() throws {
        let envelope = try review(groups: [[Spec(uid: "OP-T", name: "Skid Steer", options: [], unitState: "available", stage: "in_transit")],
                                           [Spec(uid: "OP-D", name: "Boom Lift", options: [], unitState: "available", stage: "equipment_delivered")]])
        let vc = loaded(envelope)
        for id in ["assemblyReview.group.QLA-OP-T.stage", "assembly.OP-T.stage"] {
            let style = badgeStyle(vc, id)
            XCTAssertEqual(style.text, .black, "\(id): black text")
            XCTAssertEqual(style.background, UIColor.secondary, "\(id): the light-blue badge itself is unchanged")
        }
        XCTAssertEqual(badgeStyle(vc, "assembly.OP-D.stage").text, .white, "Equipment Delivered keeps its styling")
    }

    func testUnconfirmedRowsShowNoHelperCopyWhileEverythingElseAboutThemIsUnchanged() throws {
        var line = Spec(uid: "OP-U", name: "Mini Excavator",
                        options: [("POPT-NOBKT", "No Bucket", nil), ("POPT-INC", "Included Bucket", nil), ("POPT-24", "24 Inch - Bucket", "available")],
                        unitState: nil, stage: "pending")
        line.includedOptions = ["POPT-INC"]
        let vc = loaded(try review(groups: [[line]]))

        // No helper copy under the unconfirmed unit or options (included or not) — the rows keep their names.
        for id in ["assembly.OP-U.unit.state", "assembly.OP-U.option.POPT-NOBKT.state", "assembly.OP-U.option.POPT-INC.state"] {
            XCTAssertEqual(label(vc, id) ?? "", "", id)
            XCTAssertTrue(view(vc, id)?.isHidden ?? true, "\(id): an empty state line takes no room")
        }
        XCTAssertEqual(label(vc, "assembly.OP-U.unit.title"), "Mini Excavator Unit · #U-OP-U")
        XCTAssertEqual(label(vc, "assembly.OP-U.option.POPT-INC.title"), "Included Bucket")
        XCTAssertFalse(texts(vc).contains { $0.localizedCaseInsensitiveContains("not yet confirmed") }, "no 'Not yet confirmed' anywhere")

        // The red X, the Available button and STOP are exactly as before.
        XCTAssertEqual(view(vc, "assembly.OP-U.unit.icon")?.accessibilityLabel, "Not confirmed")
        XCTAssertEqual((view(vc, "assembly.OP-U.unit.available") as? UIButton)?.accessibilityValue, "not confirmed")
        XCTAssertEqual((view(vc, "assembly.OP-U.option.POPT-NOBKT.available") as? UIButton)?.accessibilityValue, "not confirmed")
        XCTAssertTrue(view(vc, "assemblyReview.group.QLA-OP-U.gate")?.accessibilityLabel?.hasPrefix("STOP") == true)

        // A confirmed row still says so.
        XCTAssertTrue((label(vc, "assembly.OP-U.option.POPT-24.state") ?? "").hasPrefix("Available"), "confirmed presentation unchanged")
        XCTAssertFalse(view(vc, "assembly.OP-U.option.POPT-24.state")?.isHidden ?? true)
    }

    private func driverOrigin(_ product: String, enteredFrom: DeliveryWorkflowStage = .assemblyReview, isRevisit: Bool = false,
                              serverTrip: DriverStageServerState? = nil, observedAt: Date? = nil) -> ChecklistEntry.Origin {
        ChecklistEntry.Origin(kind: .driver(orderProductUniqueId: product, enteredFrom: enteredFrom, isRevisit: isRevisit),
                              selectIndex: 0, fromCheckListScreen: true,
                              missionServerTrip: serverTrip, missionServerObservedAt: observedAt)
    }

    /// The review as Dispatch or Screen 2 opens it for the driver: focused on the mission
    /// line, the engine replaced by `ops`, notices captured instead of presented.
    private func loadedDriver(_ envelope: AssemblyReviewEnvelope, product: String, enteredFrom: DeliveryWorkflowStage = .assemblyReview,
                              isRevisit: Bool = false, ops: [SyncOperation] = [],
                              serverTrip: DriverStageServerState? = nil, observedAt: Date? = nil) -> AssemblyReviewViewController {
        let vc = AssemblyReviewViewController()
        vc.orderUniqueId = envelope.data.order.uniqueId
        vc.orderNumber = envelope.data.order.orderNumber ?? ""
        vc.focusOrderProductUniqueId = product
        vc.origin = driverOrigin(product, enteredFrom: enteredFrom, isRevisit: isRevisit, serverTrip: serverTrip, observedAt: observedAt)
        vc.operationsSnapshot = { ops }
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        vc.apply(envelope)
        vc.view.layoutIfNeeded()
        return vc
    }

    private func driverOp(_ product: String, status: String, minutesAgo: Double = 5) -> SyncOperation {
        SyncOperation(type: EffectiveFieldState.driverChecklistType, capturedAt: Date().addingTimeInterval(-60 * minutesAgo),
                      identity: SyncBusinessIdentity(orderProductUniqueId: product),
                      payload: .object(["order_product_unique_id": .string(product), "checklist_type": .string("delivery"),
                                        "equipment_driver_status": .string(status)]))
    }

    /// A Dispatch list holding the mission row (un-loaded, like the adapter tests).
    private func dispatchList(product: String, order: String) -> DispatchListViewController {
        let list = DispatchListViewController()
        list.arrDispatchList = [Mapper<SchedulesModel>().map(JSON: [
            "unique_id": product, "is_delivered": false, "product_name": "Skid Steer",
            "order": ["unique_id": order, "order_number": "9305"],
            "delivery_employee": ["id": 7, "name": "Gary Driver"],
        ])!]
        list.operationsSnapshot = { [] }
        list.cachedAssemblyReview = { _ in nil }
        return list
    }

    func testTheDriverOriginContinuesToTheDriverChecklistOnlyAtGoAndSiblingsOfferNoForwardAction() throws {
        let stop = loadedDriver(try threeLineReview(), product: "OP-SKID")
        XCTAssertFalse(texts(stop).contains("Continue to Checklist"), "the yard's forward action is not the driver's")
        let blocked = try XCTUnwrap(view(stop, "assembly.OP-SKID.continue") as? UIButton)
        XCTAssertEqual(blocked.currentTitle, "Continue to Driver Checklist")
        XCTAssertFalse(blocked.isEnabled, "STOP: the driver cannot start Screen 2")
        XCTAssertEqual(blocked.accessibilityValue, "blocked")
        XCTAssertNil(view(stop, "assembly.OP-EXC.continue"), "the mission is ONE member; siblings ride along")
        XCTAssertNil(view(stop, "assembly.OP-RAKE.continue"))

        // At GO the button is live and opens Screen 2 for the mission line through Dispatch.
        let go = try review(groups: [[Spec(uid: "OP-SKID", name: "Skid Steer", options: [("POPT-TOOTH", "Toothed Bucket", "available")], unitState: "available")]])
        let list = dispatchList(product: "OP-SKID", order: go.data.order.uniqueId)
        let nav = UINavigationController(rootViewController: list)
        let vc = loadedDriver(go, product: "OP-SKID")
        nav.pushViewController(vc, animated: false)
        let cont = try XCTUnwrap(view(vc, "assembly.OP-SKID.continue") as? UIButton)
        XCTAssertTrue(cont.isEnabled)
        cont.sendActions(for: .touchUpInside)
        let screen2 = try XCTUnwrap(nav.topViewController as? DriverChecklistViewController, "GO → the Driver Checklist for this line")
        XCTAssertEqual(screen2.productUniqueId, "OP-SKID")
        XCTAssertEqual(screen2.checklistType, "delivery")
    }

    func testARevisitFromTheDriverChecklistBacksToItWhateverTheGateSays() throws {
        let list = dispatchList(product: "OP-SKID", order: "ORD-1")
        let screen2 = DriverChecklistViewController()
        let nav = UINavigationController(rootViewController: list)
        nav.pushViewController(screen2, animated: false)
        let vc = loadedDriver(try threeLineReview(), product: "OP-SKID", enteredFrom: .driverChecklist, isRevisit: true)
        nav.pushViewController(vc, animated: false)

        let back = try XCTUnwrap(view(vc, "assembly.OP-SKID.continue") as? UIButton)
        XCTAssertEqual(back.currentTitle, "Back to Driver Checklist")
        XCTAssertTrue(back.isEnabled, "a revisit always returns — STOP shows on Screen 2 as a disabled Load Map & Go")
        XCTAssertTrue((view(vc, "assembly.OP-SKID.unit.available") as! UIButton).isEnabled, "before departure the review stays operational")
        XCTAssertNotNil(view(vc, "assembly.OP-SKID.unit.reassign"))
        back.sendActions(for: .touchUpInside)
        XCTAssertTrue(nav.topViewController === screen2, "pops to the Driver Checklist beneath")
        XCTAssertEqual(nav.viewControllers.count, 2)
    }

    func testTheDriverOriginIsReadOnlyOnceThePhoneOrTheServerSaysTheTruckLeft() throws {
        let product = "OP-SKID"
        let confirmed = [Spec(uid: product, name: "Skid Steer", options: [("POPT-TOOTH", "Toothed Bucket", "available")], unitState: "available")]
        let cases: [(name: String, envelope: AssemblyReviewEnvelope, enteredFrom: DeliveryWorkflowStage, ops: [SyncOperation])] = [
            ("this phone is On My Way, server still pending", try review(groups: [confirmed]), .driverChecklist, [driverOp(product, status: "On My Way")]),
            ("this phone is Arrived", try review(groups: [confirmed]), .driverChecklist, [driverOp(product, status: "On My Way", minutesAgo: 10), driverOp(product, status: "Arrived")]),
            ("the server says in transit (another phone departed)", try review(groups: [[Spec(uid: product, name: "Skid Steer", options: [("POPT-TOOTH", "Toothed Bucket", "available")], unitState: "available", stage: "in_transit")]]), .driverChecklist, []),
            ("Screen 2 knew the row was On My Way (no local op)", try review(groups: [confirmed]), .onMyWay, []),
        ]
        for c in cases {
            var notices: [UIAlertController] = []
            let vc = loadedDriver(c.envelope, product: product, enteredFrom: c.enteredFrom, isRevisit: true, ops: c.ops)
            vc.presentNoticeOverride = { notices.append($0) }

            XCTAssertFalse((view(vc, "assembly.\(product).unit.available") as! UIButton).isEnabled, c.name)
            XCTAssertFalse((view(vc, "assembly.\(product).option.POPT-TOOTH.available") as! UIButton).isEnabled, c.name)
            XCTAssertNil(view(vc, "assembly.\(product).unit.reassign"), "no Change — \(c.name)")
            XCTAssertNil(view(vc, "assembly.\(product).unit.assign"), c.name)
            XCTAssertNil(view(vc, "assembly.\(product).continue"), "no forward action after departure — \(c.name)")

            let locked = try XCTUnwrap(view(vc, "assembly.\(product).unit.locked") as? UIButton, "the lock explanation is one tap away — \(c.name)")
            locked.sendActions(for: .touchUpInside)
            XCTAssertEqual(notices.last?.message, AssemblyPolicy.driverLockedExplanation, c.name)
            let optionLocked = try XCTUnwrap(view(vc, "assembly.\(product).option.POPT-TOOTH.locked") as? UIButton)
            optionLocked.sendActions(for: .touchUpInside)
            XCTAssertEqual(notices.count, 2, c.name)
        }

        // A yard origin with the same local On My Way is locked by the EXISTING rule (the local
        // step promotes the member to In Transit) — unchanged by the driver origin.
        let yard = AssemblyReviewViewController()
        yard.orderUniqueId = "ORD-YARD"
        yard.focusAssemblyKey = nil
        yard.operationsSnapshot = { [self.driverOp(product, status: "On My Way")] }
        yard.loadViewIfNeeded()
        yard.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        yard.apply(try review(groups: [confirmed]))
        yard.view.layoutIfNeeded()
        XCTAssertFalse((view(yard, "assembly.\(product).unit.available") as! UIButton).isEnabled, "yard: In Transit locally")
        XCTAssertNil(view(yard, "assembly.\(product).unit.reassign"))
        XCTAssertNil(view(yard, "assembly.\(product).unit.locked"), "the lock explanation belongs to the driver origin")
    }

    /// Review of T10/T11 (C2): a retained local On My Way the server has since been observed
    /// to recall (Delivery Status → Pending, a new assignment) must not lock the review — the
    /// driver has to be able to confirm the new unit and reach Screen 2 again. The review
    /// derives the stage from the SAME inputs Dispatch had: the row's server copy and when it
    /// was asked for, carried in the origin.
    func testAnOfficeRecallObservedByTheOpenerUnlocksTheReviewDespiteARetainedLocalDeparture() throws {
        let product = "OP-SKID"
        let envelope = try review(groups: [[Spec(uid: product, name: "Skid Steer", options: [], unitState: "available")]])
        var departed = driverOp(product, status: "On My Way", minutesAgo: 30)
        departed.state = .synced
        departed.acknowledgment = SyncAcknowledgment(acknowledgedAt: Date().addingTimeInterval(-25 * 60), statusCode: 200,
                                                     requestId: nil, replayed: false, serverReceivedAt: nil, data: nil)
        let recalledRow = DriverStageServerState(readyToGoAt: nil, arrivedAt: nil, isArrived: false)   // the office recalled the trip
        let observedAfterRecall = Date().addingTimeInterval(-5 * 60)

        let vc = loadedDriver(envelope, product: product, enteredFrom: .assemblyReview, ops: [departed],
                              serverTrip: recalledRow, observedAt: observedAfterRecall)
        XCTAssertTrue((view(vc, "assembly.\(product).unit.available") as! UIButton).isEnabled, "recalled: editable again")
        XCTAssertNotNil(view(vc, "assembly.\(product).unit.reassign"))
        XCTAssertNil(view(vc, "assembly.\(product).unit.locked"))
        let cont = try XCTUnwrap(view(vc, "assembly.\(product).continue") as? UIButton, "the way forward exists again")
        XCTAssertEqual(cont.currentTitle, "Continue to Driver Checklist")
        XCTAssertTrue(cont.isEnabled, "GO")

        // The same local step with NO recall observed (the opener saw the departed row) locks.
        let departedRow = DriverStageServerState(readyToGoAt: "2026-09-27 09:40:00", arrivedAt: nil, isArrived: false)
        let locked = loadedDriver(envelope, product: product, enteredFrom: .onMyWay, ops: [departed],
                                  serverTrip: departedRow, observedAt: observedAfterRecall)
        XCTAssertFalse((view(locked, "assembly.\(product).unit.available") as! UIButton).isEnabled)
        XCTAssertNil(view(locked, "assembly.\(product).continue"))
    }

    func testOfflineCandidatesComeFromTheWarmedFleetScopedToTheUnitsCategoryAndWarnWhenTheReplacementNeedsService() throws {
        let engine = try XCTUnwrap(KabbaSync.engine, "the hosted app bootstraps the Sync Engine")
        let product = "OP-SKID"
        let envelope = try review(groups: [[Spec(uid: product, name: "Skid Steer", options: [], unitState: "available",
                                                  equipmentName: "Kubota SVL75", equipmentDisplayId: "1234")]])
        for op in engine.snapshot() where op.identity.orderProductUniqueId == product { try? engine.discard(operationId: op.id) }
        defer { for op in engine.snapshot() where op.identity.orderProductUniqueId == product { try? engine.discard(operationId: op.id) } }

        let vc = loadedDriver(envelope, product: product)
        vc.operationsSnapshot = { engine.snapshot() }
        vc.candidatesRequest = { _, _, _, deliver in deliver(nil) }            // offline: the canonical read fails
        let machine = { (uid: String, tag: String, name: String, category: Int, productId: Int) -> MachineModel in
            Mapper<MachineModel>().map(JSON: ["unique_id": uid, "equipment_id": tag, "equipment_name": name, "current_status": "Available",
                                              "product_category_id": category, "assigned_product_id": productId])!
        }
        vc.warmedEquipment = { [
            machine("EQP-\(product)", "1234", "Kubota SVL75", 7, 501),          // the current unit, category 7
            machine("EQP-SAME", "5678", "Bobcat T66", 7, 501),                  // same product family → no reason
            machine("EQP-OTHER", "9012", "SANY SW405K", 7, 777),                // same category, other product → reason
            machine("EQP-EXC", "3456", "Kubota KX040", 8, 900),                 // another category → not offered
        ] }
        var offered: [EquipmentCandidate] = []
        var preselected: String?
        var choose: ((EquipmentCandidate) -> Void)?
        vc.pickerOverride = { candidates, preselect, onPicked in offered = candidates; preselected = preselect; choose = onPicked }
        var warnings: [String] = []
        vc.confirmOverride = { _, message, proceed in warnings.append(message); proceed() }
        var reasonsAsked: [String] = []
        vc.equipmentFlow.reasonPromptOverride = { candidate, done in reasonsAsked.append(candidate.uniqueId); done("Direct match unavailable") }

        (view(vc, "assembly.\(product).unit.reassign") as! UIButton).sendActions(for: .touchUpInside)

        XCTAssertEqual(offered.map(\.uniqueId), ["EQP-\(product)", "EQP-SAME", "EQP-OTHER"], "the warmed fleet, scoped to the unit's category")
        XCTAssertEqual(preselected, "EQP-\(product)")
        XCTAssertEqual(offered.map(\.requiresReason), [true, true, true],
                       "offline the review has no ordered-product id: every replacement asks for a reason (over-asking never parks an operation)")

        let replacement = try XCTUnwrap(offered.first { $0.uniqueId == "EQP-SAME" })
        try XCTUnwrap(choose)(replacement)

        XCTAssertEqual(warnings.count, 1, "the replacement's customer-site checklist is not cached: say so before recording")
        XCTAssertTrue(warnings[0].lowercased().contains("service"), warnings[0])
        XCTAssertEqual(reasonsAsked, ["EQP-SAME"], "then the reason, then the record")
        let op = try XCTUnwrap(engine.snapshot().first {
            $0.type == EffectiveFieldState.equipmentSubstitutionType && $0.identity.orderProductUniqueId == product
        }, "the switch is recorded durably through the canonical operation")
        XCTAssertEqual(op.payload["equipment_unique_id"]?.stringValue, "EQP-SAME")
        XCTAssertEqual(op.payload["reason"]?.stringValue, "Direct match unavailable")

        XCTAssertEqual(label(vc, "assembly.\(product).unit.title"), "Bobcat T66 · #5678", "the replacement shows now, from the durable record")
        XCTAssertEqual((view(vc, "assembly.\(product).unit.available") as? UIButton)?.accessibilityValue, "not confirmed")
        XCTAssertTrue(view(vc, "assemblyReview.group.QLA-\(product).gate")?.accessibilityLabel?.hasPrefix("STOP") == true, "the new machine must be confirmed before departure")
    }

    /// Review of 009dbf4 (C1): the recalled local departure must not EXCLUDE the mission line
    /// from its own gate either — an unconfirmed replacement is STOP, Continue disabled, and the
    /// unit can be changed again (I1: the change is not refused as In Transit).
    func testARecalledDepartureDoesNotExcludeTheMissionFromItsOwnGateAndTheUnitCanChange() throws {
        let product = "OP-SKID"
        let unconfirmed = try review(groups: [[Spec(uid: product, name: "Skid Steer", options: [], unitState: nil,
                                                    equipmentName: "Kubota SVL75", equipmentDisplayId: "1234")]])
        var departed = driverOp(product, status: "On My Way", minutesAgo: 30)
        departed.state = .synced
        departed.acknowledgment = SyncAcknowledgment(acknowledgedAt: Date().addingTimeInterval(-25 * 60), statusCode: 200,
                                                     requestId: nil, replayed: false, serverReceivedAt: nil, data: nil)
        let recalledRow = DriverStageServerState(readyToGoAt: nil, arrivedAt: nil, isArrived: false)
        let vc = loadedDriver(unconfirmed, product: product, enteredFrom: .assemblyReview, ops: [departed],
                              serverTrip: recalledRow, observedAt: Date().addingTimeInterval(-5 * 60))

        XCTAssertTrue(view(vc, "assemblyReview.group.QLA-\(product).gate")?.accessibilityLabel?.hasPrefix("STOP") == true,
                      "the line counts in its own gate — nothing is confirmed")
        let cont = try XCTUnwrap(view(vc, "assembly.\(product).continue") as? UIButton)
        XCTAssertFalse(cont.isEnabled, "no departure on an unconfirmed replacement")
        XCTAssertNotEqual(view(vc, "assembly.\(product).stage")?.accessibilityLabel, "In Transit", "the recalled step is not standing")

        // I1: the unit can be changed again — the picker opens (offline fallback through the seams).
        vc.candidatesRequest = { _, _, _, deliver in deliver(nil) }
        vc.warmedEquipment = { [Mapper<MachineModel>().map(JSON: ["unique_id": "EQP-\(product)", "equipment_id": "1234", "equipment_name": "Kubota SVL75",
                                                                    "current_status": "Available", "product_category_id": 7])!,
                                Mapper<MachineModel>().map(JSON: ["unique_id": "EQP-B", "equipment_id": "5678", "equipment_name": "Bobcat T66",
                                                                    "current_status": "Available", "product_category_id": 7])!] }
        var offered: [EquipmentCandidate] = []
        vc.pickerOverride = { candidates, _, _ in offered = candidates }
        let change = try XCTUnwrap(view(vc, "assembly.\(product).unit.reassign") as? UIButton)
        change.sendActions(for: .touchUpInside)
        XCTAssertEqual(offered.map(\.uniqueId), ["EQP-\(product)", "EQP-B"], "not refused as In Transit")
    }
}
