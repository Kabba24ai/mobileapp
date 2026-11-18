//
//  CustomerPhoneActionHostedTests.swift
//  RentnKingHostedTests — the customer's phone number (mobile issue #10, 2026-11-15)
//
//  Call Customer → Delivery Address shows the customer's number as the Driver
//  Checklist does (phone icon + number), and tapping it opens the same Call /
//  Send Message sheet (CustomerPhoneAction). The tap verifies nothing, saves
//  nothing and keeps the wizard on its page; only Verify Address verifies.
//  (The Driver Checklist side of the same sheet: DriverDeliveryFlowHostedTests.)
//

import XCTest
import MessageUI
@testable import RentnKing

final class CustomerPhoneActionHostedTests: XCTestCase {

    private var shown: [UIViewController] = []
    private var opened: [URL] = []
    private var savedOpen: ((URL) -> Void)!
    private var savedCanText: (() -> Bool)!

    override func setUp() {
        super.setUp()
        shown = []
        opened = []
        savedOpen = CustomerPhoneAction.openURL
        savedCanText = CustomerPhoneAction.canSendText
        CustomerPhoneAction.presentOverride = { [unowned self] controller, _ in self.shown.append(controller) }
        CustomerPhoneAction.openURL = { [unowned self] in self.opened.append($0) }
        CustomerPhoneAction.canSendText = { false }
    }

    override func tearDown() {
        CustomerPhoneAction.presentOverride = nil
        CustomerPhoneAction.openURL = savedOpen
        CustomerPhoneAction.canSendText = savedCanText
        super.tearDown()
    }

    private func wizard(phone: String, name: String = "Pat Phone", mode: CustomerCallWizardViewController.Mode = .call,
                        verification: CustomerCallVerification = .notStarted) -> (CustomerCallWizardViewController, UINavigationController) {
        let context = CustomerCallWizardContext(customerName: name, customerPhone: phone,
                                                deliveryAddress: "1200 Test Ridge Rd, Knoxville, TN 37919",
                                                productName: "Test Excavator", productOptions: [])
        let wizard = CustomerCallWizardViewController(context: context, verification: verification, mode: mode)
        let nav = UINavigationController(rootViewController: wizard)
        wizard.loadViewIfNeeded()
        wizard.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)     // the smallest supported phone
        wizard.view.layoutIfNeeded()
        return (wizard, nav)
    }

    private var sheet: UIAlertController? { shown.last as? UIAlertController }

    /// Presses an alert button through the action's own handler, the way UIKit would.
    private func press(_ title: String, in alert: UIAlertController, file: StaticString = #filePath, line: UInt = #line) throws {
        let action = try XCTUnwrap(alert.actions.first { $0.title == title }, "the sheet offers \(title)", file: file, line: line)
        typealias Handler = @convention(block) (UIAlertAction) -> Void
        guard let block = action.value(forKey: "handler") else { return }       // Cancel: no handler
        unsafeBitCast(block as AnyObject, to: Handler.self)(action)
    }

    func testDeliveryAddressShowsTheNameAndTheNumberAsATappableControlInTheAddressCard() throws {
        let (wizard, _) = wizard(phone: "(865) 555-0142")
        XCTAssertEqual(wizard.stepLabel.text, "Step 1 of 3")
        XCTAssertEqual(wizard.customerLabel.text, "Pat Phone", "the name stays")
        XCTAssertEqual(wizard.phoneLabel.text, "(865) 555-0142", "the number as Kabba sent it, as the Driver Checklist shows it")
        XCTAssertFalse(wizard.phoneButton.isHidden)
        XCTAssertTrue(wizard.phoneButton.isEnabled)
        XCTAssertEqual(wizard.phoneButton.accessibilityIdentifier, "callWizard.phone")
        XCTAssertEqual(wizard.phoneButton.accessibilityLabel, "Call or text (865) 555-0142")
        XCTAssertFalse(wizard.phoneLabel.isAccessibilityElement, "VoiceOver reads the number once, as the button")
        XCTAssertGreaterThanOrEqual(wizard.phoneButton.bounds.height, 44, "a full-size tap target")
        let card = try XCTUnwrap(wizard.addressLabel.superview as? UIStackView, "the address card")
        XCTAssertTrue(wizard.phoneButton.isDescendant(of: card), "inside the address card")
        XCTAssertTrue(wizard.customerLabel.isDescendant(of: card))
        let numberFrame = wizard.phoneLabel.convert(wizard.phoneLabel.bounds, to: wizard.view)
        let buttonFrame = wizard.phoneButton.convert(wizard.phoneButton.bounds, to: wizard.view)
        XCTAssertTrue(buttonFrame.contains(numberFrame), "the button covers the number itself")
        XCTAssertTrue(wizard.view.hitTest(CGPoint(x: numberFrame.midX, y: numberFrame.midY), with: nil) === wizard.phoneButton,
                      "a tap on the number reaches the button")
        XCTAssertEqual(wizard.primaryButton.currentTitle, CustomerCallWizardViewController.verifyAddressTitle, "Verify Address stays")
    }

    func testTappingTheNumberOffersCallAndSendMessageAndVerifiesNothing() throws {
        let (wizard, nav) = wizard(phone: "(865) 555-0142")
        var handedBack = 0
        wizard.onStepVerified = { _ in handedBack += 1 }

        wizard.phoneButton.sendActions(for: .touchUpInside)
        let sheet = try XCTUnwrap(sheet, "the Call / Send Message sheet")
        XCTAssertEqual(sheet.preferredStyle, .actionSheet)
        XCTAssertEqual(sheet.actions.map(\.title), ["Call (865) 555-0142", "Send Message", "Cancel"], "the Driver Checklist's sheet")
        XCTAssertEqual(wizard.verification, .notStarted, "tapping the number verifies nothing")
        XCTAssertEqual(handedBack, 0, "and hands nothing back to be saved")
        XCTAssertEqual(wizard.step, .address)
        XCTAssertTrue(nav.topViewController === wizard, "the wizard stays open")

        try press("Call (865) 555-0142", in: sheet)
        XCTAssertEqual(opened.map(\.absoluteString), ["tel:+18655550142"], "iOS asks before it dials")
        try press("Send Message", in: sheet)
        XCTAssertEqual(shown.count, 1, "no Messages sheet where the phone cannot text")
        try press("Cancel", in: sheet)
        XCTAssertEqual(opened.count, 1, "one call, no more")
        XCTAssertEqual(wizard.verification, .notStarted)
        XCTAssertEqual(handedBack, 0)
        XCTAssertEqual(wizard.step, .address)

        wizard.primaryTapped()                                          // Verify Address — the only thing that verifies
        XCTAssertEqual(wizard.verification, CustomerCallVerification(addressVerified: true))
        XCTAssertEqual(handedBack, 1)
        XCTAssertEqual(wizard.step, .equipment)
    }

    func testAReviewedAddressOffersTheSameNumberAndStaysReadOnly() throws {
        let done = CustomerCallVerification(addressVerified: true, equipmentVerified: true,
                                            unloading: UnloadingSituation(code: "easy_access", note: nil))
        let (wizard, _) = wizard(phone: "(865) 555-0142", mode: .review(.address), verification: done)
        var handedBack = 0
        wizard.onStepVerified = { _ in handedBack += 1 }
        XCTAssertEqual(wizard.primaryButton.currentTitle, CustomerCallWizardViewController.doneTitle)
        wizard.phoneButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(sheet?.actions.map(\.title), ["Call (865) 555-0142", "Send Message", "Cancel"])
        XCTAssertEqual(wizard.verification, done)
        XCTAssertEqual(handedBack, 0)
    }

    func testANumberWithItsOwnCountryCodeIsDialledWithIt() throws {
        let (wizard, _) = wizard(phone: "+44 20 7946 0958")
        wizard.phoneButton.sendActions(for: .touchUpInside)
        let sheet = try XCTUnwrap(sheet)
        XCTAssertEqual(sheet.actions.first?.title, "Call +44 20 7946 0958")
        try press("Call +44 20 7946 0958", in: sheet)
        XCTAssertEqual(opened.map(\.absoluteString), ["tel:+442079460958"], "never +1+44")
    }

    func testWithoutANumberToDialTheCardSaysSoAndOffersNothingToTap() {
        let (none, _) = wizard(phone: "  ")
        XCTAssertEqual(none.phoneLabel.text, CustomerCallWizardViewController.noPhoneText)
        XCTAssertTrue(none.phoneButton.isHidden, "nothing to tap")
        XCTAssertTrue(none.phoneLabel.isAccessibilityElement)
        XCTAssertEqual(none.customerLabel.text, "Pat Phone")
        XCTAssertEqual(none.primaryButton.currentTitle, CustomerCallWizardViewController.verifyAddressTitle)

        let (junk, _) = wizard(phone: "N/A")
        XCTAssertEqual(junk.phoneLabel.text, "N/A", "what Kabba holds is still shown")
        XCTAssertTrue(junk.phoneButton.isHidden)

        let (noName, _) = wizard(phone: "(865) 555-0142", name: "")
        XCTAssertTrue(noName.customerLabel.isHidden, "no empty line for a missing name")
        XCTAssertFalse(noName.phoneButton.isHidden)
        XCTAssertTrue(shown.isEmpty && opened.isEmpty)
    }

    func testTheSharedActionExplainsAMissingOrIncompleteNumber() throws {
        let presenter = UIViewController()
        CustomerPhoneAction.present(phone: nil, from: presenter)
        XCTAssertEqual(sheet?.title, CustomerPhoneAction.noNumberTitle)
        XCTAssertEqual(sheet?.preferredStyle, .alert)
        XCTAssertEqual(sheet?.actions.map(\.title), ["OK"])
        CustomerPhoneAction.present(phone: "555-01", from: presenter)
        XCTAssertEqual(sheet?.title, CustomerPhoneAction.undiallableTitle)
        XCTAssertTrue(sheet?.message?.contains("555-01") == true)
        XCTAssertTrue(opened.isEmpty, "nothing dialled")
    }

    func testASecondTapWhileSomethingIsShowingDoesNothing() {
        final class Busy: UIViewController {
            let other = UIViewController()
            override var presentedViewController: UIViewController? { other }
        }
        XCTAssertNil(CustomerPhoneAction.present(phone: "(865) 555-0142", from: Busy()))
        XCTAssertTrue(shown.isEmpty, "never a second sheet over the first")
    }
}
