//
//  QueueLinePresentationTests.swift
//  RentnKingHostedTests — runs inside the RentnKing app (Simulator or device)
//
//  Queue Line mobile UI cleanup (2026-09-13):
//    • Truck delivery → truck icon + "Delivery"; In-Store → store icon + "In Store".
//      Icon and label come from ONE rule, so they can never disagree; both
//      canonical assets exist in the app bundle.
//    • The card's single Update button acknowledges a tap immediately
//      (solid → hollow, disabled) and never lets a highlight undo that.
//

import XCTest
@testable import RentnKing

final class QueueLinePresentationTests: XCTestCase {

    // MARK: - Delivery / In-Store icon + label

    func testTruckDeliveryShowsTruckIconAndDeliveryLabel() {
        XCTAssertEqual(QueueLineTransportPresentation.icon(for: "Truck"), "icon_delivery_pending")
        XCTAssertEqual(QueueLineTransportPresentation.label(for: "Truck"), "Delivery : ")
    }

    func testInStorePickupShowsStoreIconAndInStoreLabel() {
        XCTAssertEqual(QueueLineTransportPresentation.icon(for: "Store"), "icon_store")
        XCTAssertEqual(QueueLineTransportPresentation.label(for: "Store"), "In Store : ")
    }

    /// The board's classification is unchanged: anything that is not "Store" has
    /// always been labelled Delivery — now the icon says the same thing.
    func testMissingOrUnknownModeKeepsTheDeliveryClassification() {
        for mode: String? in [nil, "", "truck", "store", "Pickup"] {
            XCTAssertEqual(QueueLineTransportPresentation.icon(for: mode), "icon_delivery_pending", "mode \(String(describing: mode))")
            XCTAssertEqual(QueueLineTransportPresentation.label(for: mode), "Delivery : ", "mode \(String(describing: mode))")
        }
    }

    func testIconAndLabelNeverDisagree() {
        for mode: String? in [nil, "", "Truck", "Store", "truck", "store", "Pickup"] {
            let storeIcon  = QueueLineTransportPresentation.icon(for: mode)  == QueueLineTransportPresentation.storeIcon
            let storeLabel = QueueLineTransportPresentation.label(for: mode) == QueueLineTransportPresentation.storeLabel
            XCTAssertEqual(storeIcon, storeLabel, "icon and label disagree for mode \(String(describing: mode))")
        }
    }

    /// The SAME assets Schedule, Dispatch, Driver Checklist and Order Details use —
    /// no new artwork was introduced, and both resolve in the app bundle.
    func testCanonicalIconAssetsExistInTheAppBundle() {
        XCTAssertNotNil(UIImage(named: QueueLineTransportPresentation.truckIcon), "truck icon asset missing")
        XCTAssertNotNil(UIImage(named: QueueLineTransportPresentation.storeIcon), "store icon asset missing")
        XCTAssertNotEqual(QueueLineTransportPresentation.truckIcon, QueueLineTransportPresentation.storeIcon)
    }

    // MARK: - Update button

    private func makeButton() -> QueueLineUpdateButton {
        QueueLineUpdateButton(fill: .cyan, ink: .black)
    }

    func testStartsSolidEnabledAndLabelledUpdate() {
        let button = makeButton()
        XCTAssertEqual(button.look, .solid)
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.title(for: .normal), "Update")
        XCTAssertEqual(button.accessibilityIdentifier, "queueLineUpdate")
        XCTAssertEqual(button.backgroundColor, .cyan)
    }

    /// The feedback is synchronous — nothing waits for a screen to load.
    func testTapFeedbackIsImmediateHollowAndDisabled() {
        let button = makeButton()
        button.beginLoading()
        XCTAssertEqual(button.look, .loading)
        XCTAssertFalse(button.isEnabled, "a second tap must have nothing to land on")
        XCTAssertEqual(button.backgroundColor, .clear, "loading look is hollow")
        XCTAssertEqual(button.title(for: .disabled), "Update", "the label stays readable while loading")
    }

    func testHighlightNeverOverridesTheLoadingLook() {
        let button = makeButton()
        button.beginLoading()
        button.isHighlighted = true
        XCTAssertEqual(button.look, .loading)
        button.isHighlighted = false
        XCTAssertEqual(button.look, .loading)
        XCTAssertFalse(button.isEnabled)
    }

    func testPressedLookWhileHeldThenSolidAgain() {
        let button = makeButton()
        button.isHighlighted = true
        XCTAssertEqual(button.look, .pressed)
        button.isHighlighted = false
        XCTAssertEqual(button.look, .solid)
        XCTAssertTrue(button.isEnabled)
    }

    func testResetRestoresTheSolidTappableDefault() {
        let button = makeButton()
        button.beginLoading()
        button.reset()
        XCTAssertEqual(button.look, .solid)
        XCTAssertTrue(button.isEnabled)
        XCTAssertEqual(button.backgroundColor, .cyan)
    }

    /// The acknowledged look is DRAWN differently, not just flagged: the solid
    /// button's centre pixel is the fill, the loading button's centre pixel is the
    /// ground showing through the hollow outline. Writes both looks side by side
    /// to $KABBA_SHOT_DIR/update-button-looks.png (when set) for a visual review.
    func testAcknowledgedLookIsVisiblyHollow() {
        let ground = UIColor(red: 0.04, green: 0.07, blue: 0.10, alpha: 1)
        let canvas = UIView(frame: CGRect(x: 0, y: 0, width: 260, height: 70))
        canvas.backgroundColor = ground

        let solid = makeButton()
        let hollow = makeButton()
        hollow.beginLoading()
        for (i, button) in [solid, hollow].enumerated() {
            button.translatesAutoresizingMaskIntoConstraints = true
            button.frame = CGRect(x: 18 + CGFloat(i) * 120, y: 18, width: 104, height: 34)
            canvas.addSubview(button)
        }
        canvas.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(bounds: canvas.bounds).image { canvas.layer.render(in: $0.cgContext) }
        /// Reads one point by drawing it into a 1×1 RGBA context — independent of the
        /// renderer's own byte order and premultiplication.
        func rgb(at point: CGPoint) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            guard let cg = image.cgImage else { return (0, 0, 0) }
            var pixel = [UInt8](repeating: 0, count: 4)
            guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0, 0, 0) }
            let scale = image.scale
            let w = CGFloat(cg.width), h = CGFloat(cg.height)
            // CoreGraphics origin is bottom-left; flip the y of the UIKit point.
            let x = point.x * scale, y = h - point.y * scale
            ctx.draw(cg, in: CGRect(x: -x, y: -y, width: w, height: h))
            return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
        }
        // Sample just inside each button, away from its centred title glyphs.
        let solidPixel = rgb(at: CGPoint(x: solid.frame.minX + 8, y: solid.frame.midY))
        let hollowPixel = rgb(at: CGPoint(x: hollow.frame.minX + 8, y: hollow.frame.midY))
        XCTAssertGreaterThan(solidPixel.g, 0.6, "solid look should paint the cyan fill")
        XCTAssertGreaterThan(solidPixel.b, 0.6, "solid look should paint the cyan fill")
        XCTAssertLessThan(hollowPixel.g, 0.3, "loading look must be hollow (ground shows through)")
        XCTAssertLessThan(hollowPixel.b, 0.3, "loading look must be hollow (ground shows through)")

        if let dir = ProcessInfo.processInfo.environment["KABBA_SHOT_DIR"], !dir.isEmpty, let png = image.pngData() {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("update-button-looks.png"))
        }
    }

    /// The button is a fixed-height control that refuses to be squeezed — the
    /// customer name next to it truncates instead.
    func testKeepsItsSizeUnderCompression() {
        let button = makeButton()
        XCTAssertEqual(button.contentCompressionResistancePriority(for: .horizontal), .required)
        XCTAssertEqual(button.contentHuggingPriority(for: .horizontal), .required)
    }
}
