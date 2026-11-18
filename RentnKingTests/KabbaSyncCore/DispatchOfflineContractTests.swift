//
//  DispatchOfflineContractTests.swift
//  Dispatch offline Phase 3 — the manifest + package contract, decoded from
//  the SHARED Laravel fixtures, and the strict per-package validation.
//

import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class DispatchOfflineContractTests: XCTestCase {

    private typealias F = DispatchOfflineFixtures

    // MARK: - Manifest

    func testTheSharedManifestFixtureDecodes() throws {
        let manifest = try DispatchOfflineManifest.decode(envelope: F.data("dispatch_offline_manifest"))

        XCTAssertTrue(DispatchOfflineValidation.isRevision(manifest.revision))
        XCTAssertTrue(manifest.includesOpenOverdue)
        XCTAssertTrue(DispatchOfflineValidation.isDate(manifest.throughDate))
        XCTAssertEqual(manifest.missions.count, 1)
        let entry = manifest.missions[0]
        XCTAssertEqual(entry.missionKey, "\(entry.orderProductUniqueId):\(entry.leg.rawValue)")
        XCTAssertTrue(DispatchOfflineValidation.isRevision(entry.revision))
        XCTAssertTrue(DispatchOfflineValidation.isDate(entry.effectiveDate))
    }

    func testAnEmptyManifestIsValid() throws {
        let manifest = try DispatchOfflineManifest.decode(envelope: F.manifestBody([]))
        XCTAssertEqual(manifest.missions, [])
    }

    func testAMalformedManifestIsRejectedAsAWhole() {
        let good = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a"))
        var bad: [(String, Data)] = []

        var dup = [good, good]
        bad.append(("duplicate key", F.manifestBody(dup)))
        dup = [F.Mission(opuid: "ORD-SCH-B", revision: "not-hex")]
        bad.append(("non-hex revision", F.manifestBody(dup)))

        let wrongKey = JSONValue.parse(F.manifestBody([good]))!
            .setting(["data", "missions"], .array([F.manifestEntry(good).setting(["mission_key"], .string("ORD-SCH-A:return"))]))
        bad.append(("key does not match id + leg", try! wrongKey.serialized()))
        let badLeg = JSONValue.parse(F.manifestBody([good]))!
            .setting(["data", "missions"], .array([F.manifestEntry(good).setting(["leg"], .string("pickup"))]))
        bad.append(("unknown leg", try! badLeg.serialized()))
        bad.append(("not JSON", Data("<html>".utf8)))
        bad.append(("no data", Data("{\"success\":true}".utf8)))

        for (label, body) in bad {
            XCTAssertThrowsError(try DispatchOfflineManifest.decode(envelope: body), label)
        }
    }

    // MARK: - Packages

    func testTheSharedPackagesFixtureDecodes() throws {
        let raw = F.data("dispatch_offline_packages")
        let template = F.packageTemplate
        let key = template["mission_key"]!.stringValue!
        let fixtureNotActive = JSONValue.parse(raw)!["data"]!["not_active"]!.arrayValue!.compactMap(\.stringValue)
        let fixtureFailed = (JSONValue.parse(raw)!["data"]!["failed"]?.arrayValue ?? []).compactMap { f -> String? in
            guard let id = f["order_product_unique_id"]?.stringValue, let leg = f["leg"]?.stringValue else { return nil }
            return "\(id):\(leg)"
        }
        let response = try DispatchOfflinePackagesResponse.decode(envelope: raw, requested: Set([key] + fixtureNotActive + fixtureFailed))

        XCTAssertEqual(response.packages.count, 1)
        XCTAssertEqual(response.rejected, [])
        let package = response.packages[0]
        XCTAssertEqual(package.missionKey, key)
        XCTAssertEqual(package.leg, .delivery)
        XCTAssertTrue(DispatchOfflineValidation.isRevision(package.revision))
        XCTAssertEqual(package.row["unique_id"]?.stringValue, package.orderProductUniqueId)
        XCTAssertEqual(package.row["order"]?["customer_phone"]?.stringValue, "555-0199", "the legacy order phone, not the address phone")
        XCTAssertEqual(package.row["equipment"]?["equipment_store"]?["store_name"]?.stringValue, "HQ")
        XCTAssertEqual(package.row["pickup_employee"]?["full_name"]?.stringValue, "Blake Driver")
        XCTAssertEqual(package.row["delivery_checklist"]?["driver_checks"], .array([.number(1), .number(2)]))
        XCTAssertNil(package.row["is_delivery_overdue"], "day-dependent flags are derived on the phone")
        XCTAssertEqual(response.notActive, fixtureNotActive)
        XCTAssertEqual(fixtureNotActive, [package.orderProductUniqueId + ":return"])
        // Review 3 #3: a mission whose package could not be built is reported apart from not_active.
        XCTAssertEqual(fixtureFailed.count, 1, "the shared fixture pins the failed-entry shape")
        if let failedKey = fixtureFailed.first {
            XCTAssertEqual(response.unavailable, [failedKey: "package_build_failed"])
            XCTAssertFalse(fixtureNotActive.contains(failedKey))
        }

        // The raw package object is kept losslessly (checklist_context / terms for Phases 4–5).
        XCTAssertEqual(package.object, template)
        XCTAssertEqual(JSONValue.parse(try package.object.serialized()), template)
        XCTAssertNotNil(package.object["checklist_context"]?["questions"])
        XCTAssertNotNil(package.object["terms"]?["status"])
    }

    func testEachValidationRuleRejectsOnlyThatPackage() throws {
        let good = F.Mission(opuid: "ORD-SCH-GOOD", revision: F.revision("good"))
        let requested: Set<String> = [good.key, "ORD-SCH-BAD:delivery"]
        let base = F.package(F.Mission(opuid: "ORD-SCH-BAD", revision: F.revision("bad")))

        let variants: [(String, JSONValue)] = [
            ("key not requested", F.package(F.Mission(opuid: "ORD-SCH-OTHER", revision: F.revision("o")))),
            ("key ≠ id:leg", base.setting(["mission_key"], .string("ORD-SCH-BAD:return"))),
            ("bad leg", base.setting(["leg"], .string("pickup"))),
            ("non-hex revision", base.setting(["revision"], .string("41"))),
            ("dispatch id mismatch", base.setting(["dispatch", "order_product_unique_id"], .string("ORD-SCH-X"))),
            ("dispatch leg mismatch", base.setting(["dispatch", "leg"], .string("return"))),
            ("row missing", base.setting(["dispatch", "row"], .null)),
            ("row id mismatch", base.setting(["dispatch", "row", "unique_id"], .string("ORD-SCH-X"))),
            ("checklist identity mismatch", base.setting(["checklist_context", "identity", "order_product_unique_id"], .string("ORD-SCH-X"))),
            ("checklist leg mismatch", base.setting(["checklist_context", "identity", "leg"], .string("return"))),
            ("terms missing", base.setting(["terms"], .null)),
        ]

        for (label, bad) in variants {
            let body = F.packagesBody([F.package(good), bad])
            let response = try DispatchOfflinePackagesResponse.decode(envelope: body, requested: requested)
            XCTAssertEqual(response.packages.map(\.missionKey), [good.key], "\(label): the good package still decodes")
            XCTAssertEqual(response.rejected.count, 1, "\(label): exactly that package is rejected")
        }
    }

    func testAPackageTheServerCouldNotBuildIsUnavailableNeverInactive() throws {
        let good = F.Mission(opuid: "ORD-SCH-GOOD", revision: F.revision("good"))
        let requested: Set<String> = [good.key, "ORD-SCH-BAD:delivery", "ORD-SCH-GONE:delivery"]
        let body = F.packagesBody([F.package(good)], notActive: ["ORD-SCH-GONE:delivery"],
                                  failed: ["ORD-SCH-BAD:delivery", "ORD-SCH-NOT-ASKED:delivery", good.key])

        let response = try DispatchOfflinePackagesResponse.decode(envelope: body, requested: requested)

        XCTAssertEqual(response.packages.map(\.missionKey), [good.key], "the sibling package is kept")
        XCTAssertEqual(response.unavailable, ["ORD-SCH-BAD:delivery": "package_build_failed"],
                       "only requested missions that were not delivered")
        XCTAssertEqual(response.notActive, ["ORD-SCH-GONE:delivery"], "not_active keeps its own meaning")
        let olderServer = try JSONValue.parse(F.packagesBody([F.package(good)]))!.setting(["data", "failed"], .null).serialized()
        XCTAssertEqual(try DispatchOfflinePackagesResponse.decode(envelope: olderServer, requested: requested).unavailable,
                       [:], "a server without the field")
    }

    func testAChecklistContextIsOpaqueInPhase3() throws {
        // A checklist-schema change must not hide a Dispatch card: only identity is checked.
        let m = F.Mission(opuid: "ORD-SCH-A", revision: F.revision("a"))
        let package = F.package(m).setting(["checklist_context", "questions"], .string("unexpected shape"))
        let response = try DispatchOfflinePackagesResponse.decode(envelope: F.packagesBody([package]), requested: [m.key])
        XCTAssertEqual(response.packages.count, 1)
    }

    // MARK: - Requests

    func testTheManifestRequestIsAGetWithAFreshOperationId() {
        let a = DispatchOfflineAPI.manifestRequest()
        let b = DispatchOfflineAPI.manifestRequest()
        XCTAssertEqual(a.method, "GET")
        XCTAssertEqual(a.path, "dispatch/offline/manifest")
        XCTAssertNil(a.jsonBody)
        XCTAssertNotEqual(a.operationId, b.operationId)
        XCTAssertTrue(a.operationId.hasPrefix("op-dispatch-offline-"))
    }

    func testPackagesAreRequestedInBatchesOfAtMostOneHundred() {
        let entries = (0..<250).map { i in
            DispatchOfflineManifest.Entry(missionKey: "ORD-SCH-\(i):delivery", orderProductUniqueId: "ORD-SCH-\(i)",
                                          leg: .delivery, effectiveDate: "2026-09-22", revision: F.revision("\(i)"))
        }
        let requests = DispatchOfflineAPI.packagesRequests(for: entries)

        XCTAssertEqual(requests.map { $0.jsonBody?["missions"]?.arrayValue?.count }, [100, 100, 50])
        XCTAssertEqual(Set(requests.map(\.operationId)).count, 3)
        for request in requests {
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.path, "dispatch/offline/packages")
        }
        XCTAssertEqual(requests[0].jsonBody?["missions"]?.arrayValue?[0],
                       .object(["order_product_unique_id": .string("ORD-SCH-0"), "leg": .string("delivery")]))
        XCTAssertEqual(DispatchOfflineAPI.packagesRequests(for: []), [])
    }
}
