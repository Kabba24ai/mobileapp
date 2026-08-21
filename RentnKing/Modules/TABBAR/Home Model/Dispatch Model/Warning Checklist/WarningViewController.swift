//
//  WarningViewController.swift
//  RentnKing
//
//  Driver Override – shown when an order is marked complete while one or more
//  required steps (T&C, license, photos/video, checklist) are still missing.
//  The driver must pick an exception reason for each missing step before the
//  delivery can be force-completed.
//

import UIKit
import Alamofire

class WarningViewController: UIViewController, UIGestureRecognizerDelegate {

    // MARK: - Inputs
    var strOrderID: String = ""          // shown in the nav title, e.g. "#053"
//    var strOrderUniqueId: String = ""
    var productUniqueId: String = ""

    /// Delivery vs Return — drives the "Delivery"/"Return" title prefix.
    var isReturn: Bool = false

    /// Which exception sections to show. A section appears only when its flag is true
    /// (i.e. that step is actually incomplete for this order).
    var showTerms: Bool = true
    var showLicense: Bool = true
    var showVideo: Bool = true
    var showChecklist: Bool = true

    /// Categories to display, in order, based on the visibility flags.
    private var visibleCategories: [DeliveryExceptionCategory] {
        var result: [DeliveryExceptionCategory] = []
        if showTerms      { result.append(.termsAndConditions) }
        if showLicense    { result.append(.driverLicense) }
        if showVideo      { result.append(.photosVideo) }
        if showChecklist  { result.append(.checklist) }
        return result
    }

    // MARK: - State
    private var selections: [DeliveryExceptionSelection] = []

    /// Per-category UI references so we can update them after a pick.
    private struct Row {
        let dropdown: UIButton
        let chevron: UIImageView
        let noteField: UITextView
        let notePlaceholder: UILabel
    }
    private var rows: [DeliveryExceptionCategory: Row] = [:]

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.backgroundView ?? .black
        selections = visibleCategories.map { DeliveryExceptionSelection(category: $0, reason: nil, note: nil) }
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        setupNavigation()
    }

    // MARK: - Navigation bar
    private func setupNavigation() {
        // Normalise to a single leading "#"
        var titleText = strOrderID.trimmingCharacters(in: .whitespaces)
        while titleText.hasPrefix("#") { titleText.removeFirst() }
        titleText = titleText.isEmpty ? "" : "#\(titleText)"

        setNavigationBarForButtons(controller: self,
                                   title: titleText,
                                   isTransperent: true,
                                   hideShadowImage: true,
                                   leftIcon: "icon_back",
                                   rightIcon: [],
                                   isFilter: false,
                                   leftActionHandler: { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        })

//        // "+View Billing" text button on the right
//        let billing = UIBarButtonItem(title: "+View Billing", style: .plain, target: self, action: #selector(viewBillingTapped))
//        billing.setTitleTextAttributes([
//            .foregroundColor: UIColor.secondaryView ?? .orange,
//            .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 14.0)
//        ], for: .normal)
//        billing.setTitleTextAttributes([
//            .foregroundColor: UIColor.secondaryView ?? .orange,
//            .font: SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 14.0)
//        ], for: .highlighted)
//        navigationItem.rightBarButtonItem = billing
    }

    // MARK: - UI building
    private func buildUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        // Small "Driver Override" pinned to the very bottom of the screen
        let lblFooter = UILabel()
        lblFooter.text = "Driver Override"
        lblFooter.textColor = UIColor.systemRed.withAlphaComponent(0.85)
        lblFooter.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 13.0)
        lblFooter.textAlignment = .center
        lblFooter.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lblFooter)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: lblFooter.topAnchor, constant: -8),

            lblFooter.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            lblFooter.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            lblFooter.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24)
        ])

        // Title — "Warning! Order Not Complete!"
        let lblTitle = UILabel()
        lblTitle.text = "Warning!\nOrder Not Complete!"
        lblTitle.textColor = .systemRed
        lblTitle.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 22.0)
        lblTitle.textAlignment = .center
        lblTitle.numberOfLines = 0
        contentStack.addArrangedSubview(lblTitle)
        contentStack.setCustomSpacing(28, after: lblTitle)

        // One section per *incomplete* exception category
        for category in visibleCategories {
            contentStack.addArrangedSubview(makeSection(for: category))
        }

        // Buttons — primary (filled) commit action + secondary (outlined) cancel
        let btnComplete = makePrimaryButton(title: isReturn ? "Return Complete - Next Mission" : "Delivery Complete - Next Mission")
        btnComplete.addTarget(self, action: #selector(deliveryCompleteTapped), for: .touchUpInside)

        let btnBack = makeSecondaryButton(title: "Back to Order")
        btnBack.addTarget(self, action: #selector(backToOrderTapped), for: .touchUpInside)

        contentStack.setCustomSpacing(32, after: contentStack.arrangedSubviews.last ?? contentStack)
        contentStack.addArrangedSubview(btnComplete)
        contentStack.addArrangedSubview(btnBack)
    }

    /// Builds the label + dropdown + (hidden) notes field for one category.
    private func makeSection(for category: DeliveryExceptionCategory) -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 8
        section.alignment = .fill

        let lbl = UILabel()
        lbl.text = category.title(isReturn: isReturn)
        lbl.textColor = .white
        lbl.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 16.0)
        section.addArrangedSubview(lbl)

        // Dropdown (bordered box)
        let dropdown = UIButton(type: .system)
        dropdown.tag = category.rawValue
        dropdown.contentHorizontalAlignment = .left
        dropdown.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 36)
        dropdown.setTitle("Select reason", for: .normal)
        dropdown.setTitleColor(UIColor.white.withAlphaComponent(0.5), for: .normal)
        dropdown.titleLabel?.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 14.0)
        dropdown.titleLabel?.lineBreakMode = .byTruncatingTail
        dropdown.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
        dropdown.layer.borderWidth = 1
        dropdown.layer.cornerRadius = 6
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        dropdown.heightAnchor.constraint(equalToConstant: 44).isActive = true
        dropdown.addTarget(self, action: #selector(dropdownTapped(_:)), for: .touchUpInside)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.down"))
        chevron.tintColor = UIColor.white.withAlphaComponent(0.6)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        dropdown.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.centerYAnchor.constraint(equalTo: dropdown.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: dropdown.trailingAnchor, constant: -12),
            chevron.widthAnchor.constraint(equalToConstant: 14),
            chevron.heightAnchor.constraint(equalToConstant: 14)
        ])
        section.addArrangedSubview(dropdown)

        // Notes field (hidden until "Other" is selected)
        let noteField = UITextView()
        noteField.backgroundColor = .clear
        noteField.textColor = .white
        noteField.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 14.0)
        noteField.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
        noteField.layer.borderWidth = 1
        noteField.layer.cornerRadius = 6
        noteField.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        noteField.delegate = self
        noteField.tag = category.rawValue
        noteField.isHidden = true
        noteField.translatesAutoresizingMaskIntoConstraints = false
        noteField.heightAnchor.constraint(equalToConstant: 70).isActive = true

        let notePlaceholder = UILabel()
        notePlaceholder.text = "Add note (required)"
        notePlaceholder.textColor = UIColor.white.withAlphaComponent(0.5)
        notePlaceholder.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 14.0)
        notePlaceholder.translatesAutoresizingMaskIntoConstraints = false
        noteField.addSubview(notePlaceholder)
        NSLayoutConstraint.activate([
            notePlaceholder.topAnchor.constraint(equalTo: noteField.topAnchor, constant: 10),
            notePlaceholder.leadingAnchor.constraint(equalTo: noteField.leadingAnchor, constant: 12)
        ])
        section.addArrangedSubview(noteField)

        rows[category] = Row(dropdown: dropdown, chevron: chevron, noteField: noteField, notePlaceholder: notePlaceholder)
        return section
    }

    /// CTA colour: delivery → green, return → amber (same logic as the dispatch buttons).
    private var ctaColor: UIColor {
        return hexStringToUIColor(hex: "128A4C")
//        return isReturn ? (UIColor.secondaryText ?? UIColor(red: 0.96, green: 0.78, blue: 0.30, alpha: 1.0))
//                        : UIColor(red: 0.404, green: 0.792, blue: 0.404, alpha: 1.0)
    }

    private func makePrimaryButton(title: String) -> UIButton {
        let button = UIButton(type: .custom)
        button.configureLable(bgColour: ctaColor,
                              textColor: .primary,
                              fontName: GlobalMainConstants.APP_FONT_Roboto_Bold,
                              fontSize: 16.0,
                              text: title)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.titleLabel?.lineBreakMode = .byClipping
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        button.btnCorneRadius(radius: 10, isRound: false)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        return button
    }

    private func makeSecondaryButton(title: String) -> UIButton {
        let button = UIButton(type: .custom)
        button.configureLable(bgColour: .clear,
                              textColor: ctaColor,
                              fontName: GlobalMainConstants.APP_FONT_Roboto_Bold,
                              fontSize: 16.0,
                              text: title)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.titleLabel?.lineBreakMode = .byClipping
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        button.btnCorneRadius(radius: 10, isRound: false)
        button.btnnBorder(bgColour: ctaColor)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        return button
    }

    // The universal reason that auto-fills every other still-empty dropdown.
    private let unsafeReason = "Unsafe Delivery Location / Safety Concern"

    /// Reasons sorted A→Z, with "Other (Requires Notes)" kept last.
    private func sortedReasons(for category: DeliveryExceptionCategory) -> [String] {
        return category.reasons.sorted { a, b in
            let aOther = a.lowercased().contains("other")
            let bOther = b.lowercased().contains("other")
            if aOther != bOther { return !aOther }   // "Other..." always last
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    // MARK: - Actions
    @objc private func dropdownTapped(_ sender: UIButton) {
        guard let category = DeliveryExceptionCategory(rawValue: sender.tag) else { return }
        view.endEditing(true)

        let sheet = UIAlertController(title: category.title(isReturn: isReturn), message: nil, preferredStyle: .actionSheet)
        for reason in sortedReasons(for: category) {
            sheet.addAction(UIAlertAction(title: reason, style: .default, handler: { [weak self] _ in
                self?.select(reason: reason, for: category)
            }))
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // iPad popover anchoring
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        present(sheet, animated: true)
    }

    private func select(reason: String, for category: DeliveryExceptionCategory) {
        applyReason(reason, to: category)

        // "Unsafe Delivery Location / Safety Concern" applies to the whole delivery,
        // so auto-fill it into every other dropdown that is still empty.
        if reason == unsafeReason {
            for selection in selections
            where selection.category != category
                && selection.reason == nil
                && selection.category.reasons.contains(unsafeReason) {
                applyReason(unsafeReason, to: selection.category)
            }
        }
    }

    /// Updates the model + UI for a single category's selected reason.
    private func applyReason(_ reason: String, to category: DeliveryExceptionCategory) {
        guard let index = selections.firstIndex(where: { $0.category == category }),
              let row = rows[category] else { return }

        selections[index].reason = reason
        row.dropdown.setTitle(reason, for: .normal)
        row.dropdown.setTitleColor(.white, for: .normal)

        let needsNote = category.requiresNote(for: reason)
        row.noteField.isHidden = !needsNote
        if !needsNote {
            row.noteField.text = ""
            row.notePlaceholder.isHidden = false
            selections[index].note = nil
        }
    }

    @objc private func backToOrderTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func deliveryCompleteTapped() {
        view.endEditing(true)

        // Validate: every category needs a reason, and "Other" needs a note.
        for selection in selections {
            guard let reason = selection.reason, !reason.isEmpty else {
                showAlertMessage(strMessage: "Please select a reason for \"\(selection.category.title(isReturn: isReturn))\".")
                return
            }
            if selection.category.requiresNote(for: reason) {
                let note = (selection.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if note.isEmpty {
                    showAlertMessage(strMessage: "Please add a note for \"\(selection.category.title(isReturn: isReturn))\".")
                    return
                }
            }
        }

        // Persist the override locally (offline-first), then submit + show the API message.
        saveOverrideInputsLocally()
        self.submitOverrideToServer()
    }

    /// Submits the override to the server and shows the API success/error message
    /// (no success animation here — that's shown on the Order Details "all complete" flow).
    private func submitOverrideToServer() {
        let type = isReturn ? "pickup" : "delivery"

        let successMessage = isReturn ? "Return completed successfully." : "Delivery completed successfully."

        // Offline → it's already saved locally and will sync when back online.
        guard NetworkReachabilityManager()?.isReachable == true else {
            self.popToDispatchList(autoDismissMessage: successMessage)
            return
        }

        indicatorShow()
        submitDeliveryPickupInputsNow(order_product_unique_id: productUniqueId, type: type) { [weak self] success, message in
            indicatorHide()
            if success {
                self?.popToDispatchList(autoDismissMessage: successMessage)
            } else {
                // Keep the error visible until the user taps OK
                self?.popToDispatchList(thenShow: message.isEmpty ? str.somethingWentWrong : message)
            }
        }
    }

    /// Pops to the dispatch list, then shows an alert that the user dismisses.
    private func popToDispatchList(thenShow message: String) {
        popToDispatchList()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            showAlertMessage(strMessage: message)
        }
    }

    /// Pops to the dispatch list, then shows a message that auto-dismisses after ~1.5s.
    private func popToDispatchList(autoDismissMessage message: String) {
        popToDispatchList()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            let alert = UIAlertController(title: Application.appName, message: message, preferredStyle: .alert)
            getTopViewController?.present(alert, animated: true) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    alert.dismiss(animated: true)
                }
            }
        }
    }

    private func popToDispatchList() {
        if let target = navigationController?.viewControllers.first(where: { $0 is DispatchListViewController }) {
            navigationController?.popToViewController(target, animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    /// Status string for a category: the chosen override reason if it was shown
    /// (i.e. incomplete), otherwise the "completed" value for that step.
    private func statusValue(for category: DeliveryExceptionCategory, completed: String) -> String {
        guard let sel = selections.first(where: { $0.category == category }) else {
            return completed   // not shown → step was already complete
        }
        let reason = sel.reason ?? ""
        if category.requiresNote(for: reason) {
            let note = (sel.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return note.isEmpty ? reason : "\(reason): \(note)"
        }
        return reason
    }

    private func saveOverrideInputsLocally() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let inputsDate = formatter.string(from: Date())

        print("=============WAR==============>>>> \(self.productUniqueId)")

        saveDeliveryPickupInputsLocally(
            order_product_unique_id: productUniqueId,
            type: isReturn ? "pickup" : "delivery",
            inputs_date: inputsDate,
            tnc_status: statusValue(for: .termsAndConditions, completed: "accepted"),
            drivers_license_status: statusValue(for: .driverLicense, completed: "verified"),
            video_status: statusValue(for: .photosVideo, completed: "completed"),
            checklist_status: statusValue(for: .checklist, completed: "completed")
        )
    }

    @objc private func viewBillingTapped() {
        // Hook for billing screen — handled by the presenting flow if needed.
    }

}

// MARK: - UITextViewDelegate (notes)
extension WarningViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        guard let category = DeliveryExceptionCategory(rawValue: textView.tag),
              let index = selections.firstIndex(where: { $0.category == category }),
              let row = rows[category] else { return }
        selections[index].note = textView.text
        row.notePlaceholder.isHidden = !textView.text.isEmpty
    }
}
