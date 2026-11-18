//
//  CustomerPhoneAction.swift
//  RentnKing — the customer's phone number (mobile issue #10, 2026-11-15)
//
//  The Call / Send Message sheet the Driver Checklist has always shown when the
//  driver taps the customer's number, in one place, so Call Customer → Delivery
//  Address opens exactly the same thing. Tapping a number only offers the
//  choice: nothing is verified, saved or sent until the driver picks Call
//  (iOS then asks before dialling) or Send Message (the driver sends it).
//

import UIKit
import MessageUI

enum CustomerPhoneAction {

    static let sendMessageTitle = "Send Message"
    static let cancelTitle = "Cancel"
    static let noNumberTitle = "No phone number"
    static let noNumberMessage = "This order has no phone number to call or text."
    static let undiallableTitle = "Can't call this number"

    static func callTitle(_ number: CustomerPhoneNumber) -> String { "Call \(number.spoken)" }

    // Seams (hosted tests): what the sheet's buttons reach outside the app, and where the sheet goes.
    static var openURL: (URL) -> Void = { UIApplication.shared.open($0) }
    static var canSendText: () -> Bool = { MFMessageComposeViewController.canSendText() }
    static var presentOverride: ((UIViewController, UIViewController) -> Void)?

    /// Offers Call / Send Message for `raw` from `presenter`; with no number to dial it says so
    /// instead. A second tap while something is already showing does nothing.
    @discardableResult
    static func present(phone raw: String?, from presenter: UIViewController) -> UIAlertController? {
        guard presenter.presentedViewController == nil else { return nil }
        let alert: UIAlertController
        if let number = CustomerPhoneNumber(raw) {
            alert = sheet(for: number, presenter: presenter)
        } else {
            let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            alert = UIAlertController(title: text.isEmpty ? noNumberTitle : undiallableTitle,
                                      message: text.isEmpty ? noNumberMessage : "“\(text)” isn't a complete phone number. Check the order in Kabba.",
                                      preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        }
        // As the Driver Checklist always did: a bottom sheet with Cancel on iPhone (no source view —
        // on iOS 26 one would turn it into a popover without Cancel), centred on iPad.
        if UIDevice.current.userInterfaceIdiom == .pad, let popover = alert.popoverPresentationController, let view = presenter.view {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        show(alert, from: presenter)
        return alert
    }

    /// The sheet itself: Call <number>, Send Message, Cancel.
    static func sheet(for number: CustomerPhoneNumber, presenter: UIViewController) -> UIAlertController {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: callTitle(number), style: .default) { _ in
            if let url = number.callURL { openURL(url) }
        })
        sheet.addAction(UIAlertAction(title: sendMessageTitle, style: .default) { [weak presenter] _ in
            guard canSendText(), let presenter else { return }
            let compose = MFMessageComposeViewController()
            compose.body = ""
            compose.recipients = [number.dialable]
            compose.messageComposeDelegate = MessageComposeCloser.shared
            show(compose, from: presenter)
        })
        sheet.addAction(UIAlertAction(title: cancelTitle, style: .cancel))
        return sheet
    }

    private static func show(_ controller: UIViewController, from presenter: UIViewController) {
        if let presentOverride { presentOverride(controller, presenter) } else { presenter.present(controller, animated: true) }
    }
}

/// Closes the Messages sheet whatever the driver did (sent, cancelled, failed) — the screen
/// underneath is left exactly as it was.
private final class MessageComposeCloser: NSObject, MFMessageComposeViewControllerDelegate {
    static let shared = MessageComposeCloser()
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }
}
