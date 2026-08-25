import Foundation
import XCTest
#if canImport(KabbaSyncCore)
@testable import KabbaSyncCore
#endif

/// Phase 4 — legacy Core Data upload queue → per-file media operations (pure conversion).
final class LegacyMediaMigrationTests: XCTestCase {

    private func record(type: String = "video_image", videoType: String = "delivery", product: String = "ORD-SCH-A",
                        name: String = "ORD-0001_1757921034.jpg", isImage: Bool = true, side: String = "",
                        expiry: String = "", by: String = "", status: String = "Pending", order: String = "ORD-0001") -> LegacyUploadRecord {
        LegacyUploadRecord(orderID: order, type: type, videoType: videoType, productID: product, name: name, isImage: isImage,
                           imageSide: side, licenseExpiryDate: expiry, autoInjectBy: by, status: status)
    }

    func testDeliveryPhotoKeepsOrderProductAssociation() throws {
        let plan = try LegacyMediaQueueMigration.convert(record()).get()
        XCTAssertEqual(plan.kind, .delivery)
        XCTAssertEqual(plan.orderUniqueId, "ORD-0001")
        XCTAssertEqual(plan.orderProductUniqueId, "ORD-SCH-A")
        XCTAssertEqual(plan.mimeType, "image/jpeg")
        XCTAssertEqual(plan.legacyRelativePath, "ImageVideo/ORD-0001/ORD-0001_1757921034.jpg")
        XCTAssertNil(plan.side)
    }

    func testReturnVideoMapsToPickupWithQuickTimeMime() throws {
        let plan = try LegacyMediaQueueMigration.convert(record(videoType: "pickup", name: "ORD-0001_1.mov", isImage: false)).get()
        XCTAssertEqual(plan.kind, .pickup)
        XCTAssertEqual(plan.mimeType, "video/quicktime")
        XCTAssertEqual(plan.fileExtension, "mov")
    }

    func testLicenseSideExpiryAndAttributionArePreserved() throws {
        let plan = try LegacyMediaQueueMigration.convert(record(type: "image", videoType: "", product: "", name: "ORD-0001_front.png", side: "front", expiry: "2029-01-31", by: "42")).get()
        XCTAssertEqual(plan.kind, .license)
        XCTAssertNil(plan.orderProductUniqueId)
        XCTAssertEqual(plan.side, "front")
        XCTAssertEqual(plan.licenseExpiryDate, "2029-01-31")
        XCTAssertEqual(plan.autoInjectBy, "42")
        XCTAssertEqual(plan.legacyRelativePath, "LicenseUpload/ORD-0001_front.png")
    }

    func testUnconvertibleRecordsAreReportedNotDropped() {
        XCTAssertEqual(LegacyMediaQueueMigration.convert(record(status: "SUCCESS")), .failure(.notPending))
        XCTAssertEqual(LegacyMediaQueueMigration.convert(record(product: "")), .failure(.missingOrderProduct))
        XCTAssertEqual(LegacyMediaQueueMigration.convert(record(name: "")), .failure(.missingFileName))
        XCTAssertEqual(LegacyMediaQueueMigration.convert(record(order: "")), .failure(.missingOrder))
        XCTAssertEqual(LegacyMediaQueueMigration.convert(record(type: "image", side: "")), .failure(.missingSide))
        XCTAssertEqual(LegacyMediaQueueMigration.convert(record(type: "hours")), .failure(.unknownType))
    }

    func testCaptureForAPlanGetsAFreshClientMediaIdAndTheFileTime() throws {
        let plan = try LegacyMediaQueueMigration.convert(record()).get()
        let asset = SyncAsset(relativePath: "ORD-SCH-A/abc.jpg", mimeType: plan.mimeType, fieldName: "media")
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let capture = LegacyMediaQueueMigration.capture(for: plan, asset: asset, capturedAt: when)
        XCTAssertEqual(capture.clientMediaId, asset.clientMediaId)
        XCTAssertEqual(capture.capturedAt, when)
        XCTAssertEqual(capture.orderProductUniqueId, "ORD-SCH-A")
        XCTAssertTrue(capture.localValidationProblems().isEmpty)
        XCTAssertEqual(MediaOperationBuilder.payload(capture)["client_media_id"]?.stringValue, asset.clientMediaId)
    }
}
