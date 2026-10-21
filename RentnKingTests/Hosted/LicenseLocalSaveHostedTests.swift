//
//  LicenseLocalSaveHostedTests.swift
//  RentnKingHostedTests — MOBILE-QUALITY-01 item 06 inside the app: saving a driver's
//  license offline returns straight to Order Details with no alert to dismiss; reopening
//  shows the copy saved on this phone (Pending Sync, with its expiration) even when the
//  order record holds an older image; saving again without changes uploads nothing, and
//  retaking one side replaces its waiting copy instead of adding a second upload.
//
//  Uses the app's own Sync Engine (the license screens use KabbaMediaSync); the base URL
//  points nowhere, so every record stays on the phone. Each test removes its records.
//

import XCTest
import UIKit
import ObjectMapper
@testable import RentnKing

final class LicenseLocalSaveHostedTests: XCTestCase {

    private var savedBaseURL: String?
    private var order = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard KabbaSync.engine != nil else { throw XCTSkip("Sync Engine not bootstrapped in this host") }
        savedBaseURL = UserDefaults.standard.baseURL
        UserDefaults.standard.baseURL = "https://license-local-save.invalid/api/admin/v1/"
        order = "ORD-LIC-\(UUID().uuidString.prefix(8))"
    }

    override func tearDown() {
        if let engine = KabbaSync.engine {
            for op in engine.snapshot() where op.identity.orderUniqueId == order {
                try? engine.discard(operationId: op.id)
            }
        }
        UserDefaults.standard.baseURL = savedBaseURL
        super.tearDown()
    }

    private func licenseOps() -> [SyncOperation] {
        KabbaSync.engine?.snapshot().filter { $0.type == EffectiveFieldState.licenseMediaType && $0.identity.orderUniqueId == order } ?? []
    }

    private func image(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 24)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 24))
        }
    }

    private func uploadScreen(serverLicense: [[String: Any]] = []) throws -> LicenseUploadViewController {
        let screen = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "LicenseUploadViewController") as? LicenseUploadViewController)
        screen.strOrderID = order
        screen.arrLicense = serverLicense.compactMap { LicenseModel(JSON: $0) }
        return screen
    }

    private func find<T: UIView>(_ type: T.Type, id: String, in view: UIView) -> T? {
        if let match = view as? T, match.accessibilityIdentifier == id { return match }
        for sub in view.subviews { if let hit = find(type, id: id, in: sub) { return hit } }
        return nil
    }

    func testAnOfflineSaveReturnsStraightToOrderDetailsWithNoAlert() throws {
        let details = UIViewController()
        let holder = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "OrderDetailsViewController") as? OrderDetailsViewController)
        let nav = UINavigationController(rootViewController: details)
        nav.pushViewController(holder, animated: false)
        let screen = try uploadScreen()
        nav.pushViewController(screen, animated: false)
        screen.loadViewIfNeeded()
        screen.imgFront.image = image(.red)
        screen.imgBack.image = image(.blue)
        screen.changedSides = ["front", "back"]

        screen.btnSubmitClicked(UIButton())

        XCTAssertTrue(nav.topViewController === holder, "back on Order Details at once — no timed pop, no extra Back")
        XCTAssertNil(nav.presentedViewController, "no blocking alert to dismiss")
        XCTAssertNil(screen.presentedViewController)
        XCTAssertEqual(licenseOps().count, 2, "both sides durably on this phone")
        XCTAssertEqual(Set(licenseOps().compactMap { $0.payload["side"]?.stringValue }), ["front", "back"])
    }

    func testReopeningShowsThePhonesCopyOverAnOlderServerImageWithItsExpiry() throws {
        let save = try KabbaMediaSync.saveLicense(orderUniqueId: order, changedSides: ["front", "back"],
                                                  licenseExpiryDate: "2028-04-01", autoInjectBy: "12") { side in
            self.image(side == "front" ? .red : .blue).jpegData(compressionQuality: 0.5)
        }
        XCTAssertEqual(save.queuedSides, ["front", "back"])

        // The order record still holds an OLD license image — it must not replace the local copy.
        let screen = try uploadScreen(serverLicense: [["side": "front", "media_url": "https://license-local-save.invalid/old-front.jpg"],
                                                      ["side": "back", "media_url": "https://license-local-save.invalid/old-back.jpg"]])
        screen.loadViewIfNeeded()

        XCTAssertNotNil(screen.imgFront.image)
        XCTAssertNotNil(screen.imgBack.image)
        XCTAssertFalse(screen.viewEditFront.isHidden)
        let frontBadge = try XCTUnwrap(find(UILabel.self, id: "license.status.front", in: screen.view))
        XCTAssertEqual(frontBadge.text, "Pending Sync")
        XCTAssertFalse(frontBadge.isHidden)
        XCTAssertEqual(find(UILabel.self, id: "license.status.back", in: screen.view)?.text, "Pending Sync")
        let expiry = try XCTUnwrap(find(UILabel.self, id: "license.expiry", in: screen.view))
        XCTAssertEqual(expiry.text, "Expires April 2028")

        // The expiration screen fills in what this phone saved.
        let type = try XCTUnwrap(UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
            .instantiateViewController(withIdentifier: "LicenseTypeViewController") as? LicenseTypeViewController)
        type.strOrderID = order
        type.loadViewIfNeeded()
        type.prefillSavedLicenseDetails()
        XCTAssertEqual(type.txtMonth.text, "Apr")
        XCTAssertEqual(type.txtYear.text, "2028")
        XCTAssertEqual(type.strSelectedEmpID, "12")
    }

    func testSavingAgainWithoutChangesUploadsNothingAndRetakingOneSideReplacesItsWaitingCopy() throws {
        _ = try KabbaMediaSync.saveLicense(orderUniqueId: order, changedSides: ["front", "back"]) { side in
            self.image(side == "front" ? .red : .blue).jpegData(compressionQuality: 0.5)
        }
        let first = licenseOps()
        XCTAssertEqual(first.count, 2)

        // Reopen, Submit Only without retaking anything: nothing new is queued.
        let again = try KabbaMediaSync.saveLicense(orderUniqueId: order, changedSides: []) { _ in Data([1]) }
        XCTAssertEqual(again.queuedSides, [])
        XCTAssertEqual(KabbaMediaSync.licenseSavedMessage(again), "Driver's license already saved on this phone.")
        XCTAssertEqual(Set(licenseOps().map(\.id)), Set(first.map(\.id)))

        // Retake the front: its waiting copy is replaced; the back is untouched.
        let oldFront = try XCTUnwrap(first.first { $0.payload["side"]?.stringValue == "front" })
        let oldBack = try XCTUnwrap(first.first { $0.payload["side"]?.stringValue == "back" })
        let retake = try KabbaMediaSync.saveLicense(orderUniqueId: order, changedSides: ["front"]) { _ in
            self.image(.green).jpegData(compressionQuality: 0.5)
        }
        XCTAssertEqual(retake.queuedSides, ["front"])
        let now = licenseOps()
        XCTAssertEqual(now.count, 2, "one copy per side — never a second upload of the same side")
        XCTAssertTrue(now.contains { $0.id == oldBack.id })
        if KabbaSync.engine?.operation(id: oldFront.id)?.state == .syncing {
            // A copy already being sent is left to land (Laravel keeps the last image per side).
        } else {
            XCTAssertFalse(now.contains { $0.id == oldFront.id }, "the waiting front was replaced")
        }
        XCTAssertEqual(KabbaMediaSync.licenseSavedMessage(retake), "Driver's license saved on this phone. Will sync when available.")
    }

    // MARK: - Independent review fixes

    func testNewDetailsNeverUploadAnImageThatDidNotLoad() throws {
        // The license exists only on Kabba and its image never loaded here (offline): the screen shows
        // a placeholder. New details for an unchanged side must not upload that placeholder.
        var encoded: [String] = []
        XCTAssertThrowsError(try KabbaMediaSync.saveLicense(orderUniqueId: order, changedSides: [],
                                                            licenseExpiryDate: "2029-01-01", autoInjectBy: "12",
                                                            trustedImageSides: []) { side in encoded.append(side); return Data([1, 2, 3]) }) { error in
            XCTAssertEqual(error as? KabbaMediaSync.Failure, .imageNotAvailable(side: "front"))
            XCTAssertEqual(KabbaMediaSync.licenseSaveFailureMessage(error),
                           "The front of the license isn't loaded on this phone. Reconnect and open the license again, or retake the front.")
        }
        XCTAssertTrue(encoded.isEmpty, "the screen image was never even encoded")
        XCTAssertTrue(licenseOps().isEmpty, "nothing queued")

        // Kabba's image confirmed loaded on screen: it may be re-sent with the new details.
        let save = try KabbaMediaSync.saveLicense(orderUniqueId: order, changedSides: [],
                                                  licenseExpiryDate: "2029-01-01", autoInjectBy: "12",
                                                  trustedImageSides: ["front", "back"]) { _ in self.image(.gray).jpegData(compressionQuality: 0.5) }
        XCTAssertEqual(save.queuedSides, ["front", "back"])
    }

    func testAnUnchangedSideReusesItsExactSavedFileAndSubmitOnlyKeepsTheSavedDetails() throws {
        _ = try KabbaMediaSync.saveLicense(orderUniqueId: order, changedSides: ["front", "back"],
                                           licenseExpiryDate: "2028-04-01", autoInjectBy: "17") { side in
            self.image(side == "front" ? .red : .blue).jpegData(compressionQuality: 0.5)
        }
        let local = KabbaMediaSync.localLicense(orderUniqueId: order)
        let savedBack = try XCTUnwrap(KabbaMediaSync.licenseImageData(try XCTUnwrap(local["back"])))

        // Retake only the front from the first screen ("Submit Only" carries no details).
        let save = try KabbaMediaSync.saveLicense(orderUniqueId: order, changedSides: ["front"]) { _ in
            self.image(.green).jpegData(compressionQuality: 0.5)
        }
        XCTAssertEqual(save.queuedSides, ["front"])
        let now = KabbaMediaSync.localLicense(orderUniqueId: order)
        XCTAssertEqual(now["front"]?.expiryDate, "2028-04-01", "the saved expiration travels with the new front")
        XCTAssertEqual(now["front"]?.autoInjectBy, "17")
        XCTAssertEqual(now["back"]?.operationId, local["back"]?.operationId, "the untouched back is not re-sent")

        // New details for both sides: the unchanged back goes with its EXACT saved bytes, not a re-encode.
        var encodedSides: [String] = []
        _ = try KabbaMediaSync.saveLicense(orderUniqueId: order, changedSides: [], licenseExpiryDate: "2030-06-01", autoInjectBy: "17") { side in
            encodedSides.append(side)
            return Data([0])
        }
        XCTAssertTrue(encodedSides.isEmpty, "both sides already had files on this phone")
        let after = KabbaMediaSync.localLicense(orderUniqueId: order)
        XCTAssertEqual(KabbaMediaSync.licenseImageData(try XCTUnwrap(after["back"])), savedBack)
        XCTAssertEqual(LocalLicense.expiryDate(after), "2030-06-01")
        XCTAssertEqual(licenseOps().count, 2, "one copy per side")
    }
}

