import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

final class LegacyChecklistMigrationTests: XCTestCase {

    private func legacyItem(type: String = "Delivery", signature: Data? = Data("SIGBYTES".utf8)) -> [String: Any] {
        var item: [String: Any] = [
            "order_product_unique_id": "ORD-SCH-LEG-0001",
            "order_unique_id": "ORD-LEG-0001",
            "equipment_unique_id": "EQP-LEG-0001",
            "checklist[]": "[{\"question_unique_id\":\"CAQST-1\",\"answer_unique_id\":\"CAANS-1\"}]",
            "start_hours": "12.0", "user_id": "7", "note": "", "type": type, "version": "1.0.17 (1000)",
            "dSignature": type == "Delivery" ? (signature?.base64EncodedString() ?? "") : "",
            "rSignature": type == "Return" ? (signature?.base64EncodedString() ?? "") : "",
            "_attempts": 3,
        ]
        if type == "Return" { item["store_id"] = "2"; item["end_hours"] = "20.0" }
        return item
    }

    func testAValidLegacyItemConvertsVerbatimWithItsSignature() throws {
        let converted = try LegacyChecklistQueueMigration.convert(legacyItem()).get()
        XCTAssertEqual(converted.leg, .delivery)
        XCTAssertEqual(converted.payload["order_product_unique_id"]?.stringValue, "ORD-SCH-LEG-0001")
        XCTAssertEqual(converted.payload["checklist[]"]?.stringValue, "[{\"question_unique_id\":\"CAQST-1\",\"answer_unique_id\":\"CAANS-1\"}]", "legacy id space untouched")
        XCTAssertNil(converted.payload["_attempts"], "the dead-letter counter does not survive")
        XCTAssertNil(converted.payload["dSignature"], "the signature leaves the JSON and becomes an asset")
        XCTAssertEqual(converted.signatureJPEG, Data("SIGBYTES".utf8))
        XCTAssertEqual(converted.identity.orderProductUniqueId, "ORD-SCH-LEG-0001")
    }

    func testUnconvertibleItemsAreReportedNotDropped() {
        var noProduct = legacyItem(); noProduct["order_product_unique_id"] = ""
        XCTAssertEqual(LegacyChecklistQueueMigration.convert(noProduct), .failure(.missingOrderProduct))
        var noType = legacyItem(); noType["type"] = "Weird"
        XCTAssertEqual(LegacyChecklistQueueMigration.convert(noType), .failure(.missingType))
        var badJSON = legacyItem(); badJSON["checklist[]"] = "\"question_unique_id\": \"x\""
        XCTAssertEqual(LegacyChecklistQueueMigration.convert(badJSON), .failure(.invalidChecklistJSON))
    }

    func testMigratedItemsBecomeDurableOperationsTargetingTheLegacyEndpoints() throws {
        let dir = Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try FileSyncOperationStore(rootDirectory: dir)
        let client = FakeSyncHTTPClient()
        let engine = makeEngine(store: store, client: client)

        let delivery = try LegacyChecklistQueueMigration.enqueue(try LegacyChecklistQueueMigration.convert(legacyItem()).get(), into: engine)
        let ret = try LegacyChecklistQueueMigration.enqueue(try LegacyChecklistQueueMigration.convert(legacyItem(type: "Return")).get(), into: engine)

        XCTAssertEqual(delivery.type, "legacy_customer_checklist.submit")
        XCTAssertEqual(delivery.assets.count, 1)
        XCTAssertEqual(try LegacyChecklistQueueMigration.request(for: delivery).path, "orders/customer-checklists/save-delivery")
        XCTAssertEqual(try LegacyChecklistQueueMigration.request(for: ret).path, "orders/customer-checklists/save-return")
        XCTAssertEqual(try LegacyChecklistQueueMigration.request(for: delivery).headers["X-Operation-Id"], delivery.id)
        XCTAssertEqual(try LegacyChecklistQueueMigration.request(for: delivery).attachments.first?.fieldName, "signature_media")

        // Relaunch: both still there, signatures on disk.
        let relaunched = try FileSyncOperationStore(rootDirectory: dir)
        XCTAssertEqual(try relaunched.loadAll().count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.assetsDirectory.appendingPathComponent(delivery.assets[0].relativePath).path))
    }

    func testContextStoreCachesAndSurvivesRelaunch() throws {
        let dir = Fixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let json: [String: Any] = [
            "identity": ["checklist_execution_id": "ORD-CHK-CACHE", "cycle": 1, "status": "open", "leg": "delivery",
                         "order_unique_id": "ORD-1", "order_number": "1", "order_product_unique_id": "ORD-SCH-C", "product_name": "P"],
            "equipment": ["assignment": "none", "equipment_unique_id": NSNull()],
            "template": ["template_id": NSNull(), "template_name": NSNull(), "revision": NSNull(), "question_source": "none"],
            "requirements": ["signature_required": true, "employee_required": true, "store_required": false, "equipment_required": true, "required_question_ids": []],
            "questions": [],
            "operational": ["hour_tracking": false, "is_product_clean": false, "rental_prepaid_cleaning": 0, "start_hours": 0, "end_hours": 0,
                            "fuel_initial_reading": "", "fuel_final_reading": "", "delivery_clean_id": "", "return_clean_id": "", "delivery_notes": "", "pickup_notes": "",
                            "delivery_by": NSNull(), "pickup_by": NSNull(), "pickup_store_id": NSNull()],
            "server_state": ["is_delivered": false, "is_returned": false, "delivery_status": "Pending", "pickup_status": "Pending",
                             "delivery_signature_present": false, "return_signature_present": false, "execution_status": "open",
                             "prepared_at": NSNull(), "completed_at": NSNull(), "captured_at": NSNull(), "can_complete": true, "blocked_reason": NSNull()],
            "employee": NSNull(), "server_time": "2026-08-25T12:00:00+00:00",
        ]
        let context = try ChecklistContext.decode(envelopeData: Fixtures.json(["success": true, "data": json]))

        let store = try ChecklistContextStore(rootDirectory: dir)
        try store.save(context)
        XCTAssertEqual(store.load(orderProductUniqueId: "ORD-SCH-C", leg: .delivery)?.executionId, "ORD-CHK-CACHE")
        XCTAssertNil(store.load(orderProductUniqueId: "ORD-SCH-C", leg: .return), "legs are cached independently")

        let relaunched = try ChecklistContextStore(rootDirectory: dir)
        let cached = relaunched.load(orderProductUniqueId: "ORD-SCH-C", leg: .delivery)
        XCTAssertEqual(cached?.executionId, "ORD-CHK-CACHE")
        XCTAssertNotNil(cached?.cachedAt)
        XCTAssertEqual(relaunched.all().count, 1)

        relaunched.remove(orderProductUniqueId: "ORD-SCH-C", leg: .delivery)
        XCTAssertNil(relaunched.load(orderProductUniqueId: "ORD-SCH-C", leg: .delivery))
    }
}
