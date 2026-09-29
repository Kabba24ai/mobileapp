//
//  CustomerCallWizardViewController.swift
//  RentnKing — Driver Checklist → Call Customer (2026-09-29)
//
//  The guided customer call: three sequential pages the driver reads from
//  while on the phone — the delivery address, the equipment order (product +
//  Product Options) and the unloading situation. Every page shows the actual
//  information from the cached mission row (nothing is fetched, nothing is
//  copied into another store), so the driver verifies instead of remembering.
//
//  Two modes:
//    • call    — the whole call, always from Delivery Address; each verified
//                step is handed back at once (the Driver Checklist persists it
//                locally and queues the durable partial save) and the wizard
//                moves on; finishing the third step derives Confirmed.
//    • review  — after Confirmed: one page opened directly, read-only for the
//                address and the equipment, editable for the unloading choice
//                (a changed valid choice is handed back; Confirmed stands).
//
//  Built in code (no storyboard scene): the Driver Checklist pushes it.
//

import UIKit

/// What the wizard shows — all of it from the cached row the Driver Checklist already has.
struct CustomerCallWizardContext {
    let customerName: String
    let customerPhone: String
    let deliveryAddress: String
    let productName: String
    let productOptions: [String]
}

final class CustomerCallWizardViewController: UIViewController {

    enum Mode: Equatable {
        /// The sequential call, from step 1.
        case call
        /// One completed step, opened for review.
        case review(CustomerCallVerification.Step)
    }

    typealias Step = CustomerCallVerification.Step

    let context: CustomerCallWizardContext
    let mode: Mode
    /// The steps as verified so far (the wizard only ever ADDS to them).
    private(set) var verification: CustomerCallVerification
    private(set) var step: Step

    /// Called the moment a step is verified (or a saved unloading choice is changed):
    /// the Driver Checklist persists and syncs it. The wizard keeps going.
    var onStepVerified: (CustomerCallVerification) -> Void = { _ in }
    /// Called when the wizard is done (the call completed, or a review page closed).
    var onFinished: () -> Void = {}

    // Controls (internal so the hosted tests can drive them).
    let stepLabel = UILabel()
    let headingLabel = UILabel()
    let hintLabel = UILabel()
    let addressLabel = UILabel()
    let customerLabel = UILabel()
    let productLabel = UILabel()
    let optionsLabel = UILabel()
    let noteField = UITextView()
    let noteHintLabel = UILabel()
    let primaryButton = UIButton(type: .system)
    private(set) var choiceButtons: [UIButton] = []
    private var selectedChoice: String? = nil
    private var noteHeight: NSLayoutConstraint?

    private let scrollView = UIScrollView()
    private let content = UIStackView()

    static let verifyAddressTitle = "Verify Address"
    static let verifyEquipmentTitle = "Verify Equipment"
    static let confirmCallTitle = "Confirm Call"
    static let saveChoiceTitle = "Save"
    static let doneTitle = "Done"
    static let noOptionsText = "No Product Options on this order."

    init(context: CustomerCallWizardContext, verification: CustomerCallVerification, mode: Mode) {
        self.context = context
        self.verification = verification
        self.mode = mode
        switch mode {
        case .call: self.step = .address
        case .review(let step): self.step = step
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isReview: Bool {
        if case .review = mode { return true }
        return false
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        buildLayout()
        render()
        // The Other note sits at the bottom of the page: keep it above the keyboard (iOS 14 target).
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let overlap = max(0, view.bounds.maxY - view.convert(frame, from: nil).minY - view.safeAreaInsets.bottom)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
        if overlap > 0 { scrollView.scrollRectToVisible(noteField.convert(noteField.bounds, to: scrollView), animated: true) }
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.tabBarController?.tabBar.isHidden = true
        setNavigationBarForButtons(controller: self, title: "Call Customer", isTransperent: true, hideShadowImage: true,
                                   leftIcon: "icon_back", rightIcon: [], isFilter: false) { [weak self] in
            // Backing out keeps every step already verified (each was persisted as it happened).
            self?.navigationController?.popViewController(animated: true)
        } rightActionHandler: { _, _ in }
    }

    // MARK: - Layout

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        content.axis = .vertical
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])

        style(stepLabel, font: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 13, color: .secondaryText)
        stepLabel.accessibilityIdentifier = "callWizard.step"
        style(headingLabel, font: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 22, color: .secondary)
        headingLabel.accessibilityIdentifier = "callWizard.title"
        style(hintLabel, font: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 15, color: .primary)
        hintLabel.accessibilityIdentifier = "callWizard.hint"

        style(addressLabel, font: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 24, color: .primary)
        addressLabel.accessibilityIdentifier = "callWizard.address"
        style(customerLabel, font: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 16, color: .primary)
        customerLabel.accessibilityIdentifier = "callWizard.customer"
        style(productLabel, font: GlobalMainConstants.APP_FONT_Roboto_Bold, size: 22, color: .primary)
        productLabel.accessibilityIdentifier = "callWizard.product"
        style(optionsLabel, font: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 17, color: .primary)
        optionsLabel.accessibilityIdentifier = "callWizard.options"

        noteField.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 16)
        noteField.textColor = .primary
        noteField.backgroundColor = .clear
        noteField.layer.borderWidth = 1
        noteField.layer.borderColor = UIColor.secondary.cgColor
        noteField.layer.cornerRadius = 8
        noteField.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        noteField.accessibilityIdentifier = "callWizard.note"
        noteField.delegate = self
        noteHeight = noteField.heightAnchor.constraint(equalToConstant: 88)
        noteHeight?.isActive = true
        style(noteHintLabel, font: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 13, color: .secondaryText)
        noteHintLabel.text = "Describe the unloading situation (required for Other)."

        primaryButton.titleLabel?.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Medium, size: 17)
        primaryButton.setTitleColor(.background, for: .normal)
        primaryButton.setTitleColor(.background.withAlphaComponent(0.6), for: .disabled)
        primaryButton.layer.cornerRadius = 12
        primaryButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        primaryButton.accessibilityIdentifier = "callWizard.primary"
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
    }

    private func style(_ label: UILabel, font: String, size: CGFloat, color: UIColor) {
        label.font = SetTheFont(fontName: font, size: size)
        label.textColor = color
        label.numberOfLines = 0
    }

    private func card(_ views: [UIView]) -> UIView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.layer.borderWidth = 1
        stack.layer.borderColor = UIColor.secondary.cgColor
        stack.layer.cornerRadius = 12
        return stack
    }

    // MARK: - Rendering one page

    /// Rebuilds the page for `step` in the current mode.
    func render() {
        content.removeAllArrangedSubviews()
        choiceButtons = []

        stepLabel.text = isReview ? "Review" : "Step \(step.rawValue + 1) of 3"
        headingLabel.text = step.title
        content.addArrangedSubview(stepLabel)
        content.addArrangedSubview(headingLabel)

        switch step {
        case .address:
            hintLabel.text = "Read the delivery address to the customer and confirm it is where the equipment goes."
            addressLabel.text = context.deliveryAddress.isEmpty ? "No delivery address on this order." : context.deliveryAddress
            customerLabel.text = [context.customerName, context.customerPhone].filter { !$0.isEmpty }.joined(separator: " · ")
            content.addArrangedSubview(hintLabel)
            content.addArrangedSubview(card([addressLabel, customerLabel]))
            primaryButton.setTitle(isReview ? Self.doneTitle : Self.verifyAddressTitle, for: .normal)
            primaryButton.isEnabled = true

        case .equipment:
            hintLabel.text = "Confirm with the customer what was ordered — the machine and every option that comes with it."
            productLabel.text = context.productName.isEmpty ? "No product on this line." : context.productName
            optionsLabel.text = context.productOptions.isEmpty
                ? Self.noOptionsText
                : "Product Options:\n" + context.productOptions.map { "• \($0)" }.joined(separator: "\n")
            content.addArrangedSubview(hintLabel)
            content.addArrangedSubview(card([productLabel, optionsLabel]))
            primaryButton.setTitle(isReview ? Self.doneTitle : Self.verifyEquipmentTitle, for: .normal)
            primaryButton.isEnabled = true

        case .unloading:
            hintLabel.text = "Ask how and where the equipment will be unloaded. Choose one."
            content.addArrangedSubview(hintLabel)
            selectedChoice = verification.unloading?.code
            noteField.text = verification.unloading?.note ?? ""
            for (code, title) in UnloadingSituation.choices {
                let button = UIButton(type: .custom)
                button.setTitle("  \(title)", for: .normal)
                button.titleLabel?.font = SetTheFont(fontName: GlobalMainConstants.APP_FONT_Roboto_Regular, size: 16)
                button.titleLabel?.numberOfLines = 0
                button.setTitleColor(.primary, for: .normal)
                button.contentHorizontalAlignment = .left
                button.tintColor = .primary
                button.accessibilityIdentifier = "callWizard.situation.\(code)"
                button.accessibilityLabel = title
                button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
                button.addTarget(self, action: #selector(choiceTapped(_:)), for: .touchUpInside)
                choiceButtons.append(button)
                content.addArrangedSubview(button)
            }
            content.addArrangedSubview(noteHintLabel)
            content.addArrangedSubview(noteField)
            primaryButton.setTitle(isReview ? Self.saveChoiceTitle : Self.confirmCallTitle, for: .normal)
            refreshChoices()
        }

        content.setCustomSpacing(24, after: content.arrangedSubviews.last ?? hintLabel)
        content.addArrangedSubview(primaryButton)
        refreshPrimary()
    }

    /// The situation the page currently holds (nil until a choice is made).
    var draftUnloading: UnloadingSituation? {
        guard let code = selectedChoice else { return nil }
        return UnloadingSituation(code: code, note: noteField.text)
    }

    private func refreshChoices() {
        for (button, choice) in zip(choiceButtons, UnloadingSituation.choices) {
            let selected = choice.code == selectedChoice
            button.setImage(UIImage(systemName: selected ? "checkmark.circle.fill" : "circle"), for: .normal)
        }
        let isOther = selectedChoice == UnloadingSituation.otherCode
        noteField.isHidden = !isOther
        noteHintLabel.isHidden = !isOther
    }

    private func refreshPrimary() {
        let enabled: Bool
        switch step {
        case .address, .equipment: enabled = true
        case .unloading: enabled = draftUnloading?.isValid == true
        }
        primaryButton.isEnabled = enabled
        primaryButton.backgroundColor = enabled ? hexStringToUIColor(hex: "3DDC6E") : .darkGray
    }

    // MARK: - Actions

    @objc private func choiceTapped(_ sender: UIButton) {
        guard let index = choiceButtons.firstIndex(of: sender) else { return }
        selectedChoice = UnloadingSituation.choices[index].code
        refreshChoices()
        refreshPrimary()
        if selectedChoice == UnloadingSituation.otherCode { noteField.becomeFirstResponder() } else { noteField.resignFirstResponder() }
    }

    @objc func primaryTapped() {
        switch step {
        case .address:
            if !isReview {
                verification.addressVerified = true
                onStepVerified(verification)
                advance(to: .equipment)
            } else {
                finish()
            }
        case .equipment:
            if !isReview {
                verification.equipmentVerified = true
                onStepVerified(verification)
                advance(to: .unloading)
            } else {
                finish()
            }
        case .unloading:
            guard let choice = draftUnloading, choice.isValid else { refreshPrimary(); return }
            if verification.unloading != choice {
                verification.unloading = choice
                onStepVerified(verification)
            }
            finish()
        }
    }

    /// How long the primary button ignores touches after a page change: the same
    /// button verifies the next step, so a double-tap must not verify a page the
    /// driver has not read.
    static let pageChangeTouchLockout: TimeInterval = 0.6

    private func advance(to next: Step) {
        step = next
        noteField.resignFirstResponder()
        render()
        scrollView.setContentOffset(.zero, animated: false)
        primaryButton.isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pageChangeTouchLockout) { [weak self] in
            self?.primaryButton.isUserInteractionEnabled = true
        }
    }

    private func finish() {
        noteField.resignFirstResponder()
        onFinished()
        navigationController?.popViewController(animated: true)
    }
}

extension CustomerCallWizardViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        refreshPrimary()
    }

    /// The note never grows past the server's cap (a longer one would be refused and park the call).
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text ?? ""
        guard let swiftRange = Range(range, in: current) else { return true }
        let proposed = current.replacingCharacters(in: swiftRange, with: text)
        return UnloadingSituation.length(of: proposed) <= UnloadingSituation.noteMaxLength
    }
}
