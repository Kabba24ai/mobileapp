//
//  EquipmentAuditOffSiteViewController.swift
//  RentnKing
//
//  Move Off-Site from the mobile audit. The web audit opens Kabba's shared
//  Manage Equipment Location modal; a phone cannot host that web modal, so
//  this is the same workflow natively: the SAME fields (Equipment's
//  StoreOffSiteRequest), the same choices (the drivable suppliers and states
//  from the modal's own feed, EquipmentLocationFeed), and the same writer —
//  POST equipment-audits/{audit}/off-site validates with Equipment's rules and
//  messages and moves the unit with EquipmentOffSiteService. Nothing here
//  decides whether the form is complete; Laravel's messages are shown under
//  the fields they belong to.
//

import UIKit

final class EquipmentAuditOffSiteViewController: UIViewController, UITextFieldDelegate {

    private typealias Palette = EquipmentAuditRowCell.Palette

    private let auditUniqueId: String
    private let row: EquipmentAuditRow
    private let performedBy: EquipmentAuditPerson
    private let api: EquipmentAuditAPI
    private let onDone: (EquipmentAuditActionResult, String?) -> Void
    /// Closed on a refusal (stale unit, closed audit, no longer at a store): the board re-reads.
    var onClosedWithoutSaving: (() -> Void)?

    private var options: EquipmentAuditOffSiteOptions?
    private var form = EquipmentAuditOffSiteForm()
    /// Stable for this form: a resubmit after a dropped connection replays.
    private var operationId = EquipmentAuditCommands.newOperationId()

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let sourceControl = UISegmentedControl(items: ["Drivable Supplier", "Manual Entry"])
    private let supplierButton = UIButton(type: .system)
    private let supplierDetail = UILabel()
    private let stateButton = UIButton(type: .system)
    private let supplierGroup = UIStackView()
    private let manualGroup = UIStackView()
    private var fields: [String: UITextField] = [:]
    private var errorLabels: [String: UILabel] = [:]
    private let submit = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(auditUniqueId: String, row: EquipmentAuditRow, performedBy: EquipmentAuditPerson, api: EquipmentAuditAPI,
         onDone: @escaping (EquipmentAuditActionResult, String?) -> Void) {
        self.auditUniqueId = auditUniqueId
        self.row = row
        self.performedBy = performedBy
        self.api = api
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
        title = "Move Off-Site"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func inSheet() -> UINavigationController {
        let nav = UINavigationController(rootViewController: self)
        nav.modalPresentationStyle = .pageSheet
        nav.overrideUserInterfaceStyle = .dark
        nav.isModalInPresentation = true
        return nav
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.page
        view.accessibilityIdentifier = "equipmentAudit.offSite"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        buildForm()
        loadOptions()
    }

    @objc private func cancel() { dismiss(animated: true) }

    // MARK: Form

    private func label(_ text: String, size: CGFloat = 13, weight: UIFont.Weight = .semibold, color: UIColor = EquipmentAuditRowCell.Palette.subtle) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.numberOfLines = 0
        return l
    }

    private func errorLabel(for key: String) -> UILabel {
        let l = label("", size: 12, weight: .medium, color: Palette.red)
        l.isHidden = true
        l.accessibilityIdentifier = "equipmentAudit.offSite.error.\(key)"
        errorLabels[key] = l
        return l
    }

    private func textField(_ key: String, _ title: String, placeholder: String = "", keyboard: UIKeyboardType = .default) -> UIView {
        let field = UITextField()
        field.placeholder = placeholder
        field.keyboardType = keyboard
        field.borderStyle = .roundedRect
        field.backgroundColor = UIColor(red: 0x14 / 255.0, green: 0x1C / 255.0, blue: 0x26 / 255.0, alpha: 1)
        field.textColor = Palette.ink
        field.keyboardAppearance = .dark
        field.delegate = self
        // Return walks the form; the last field's Done puts the keyboard away so
        // nothing (the app-wide keyboard toolbar included) sits over Move Off-Site.
        field.returnKeyType = key == Self.fieldOrder.last ? .done : .next
        field.accessibilityIdentifier = "equipmentAudit.offSite.\(key)"
        field.heightAnchor.constraint(equalToConstant: 40).isActive = true
        fields[key] = field
        let group = UIStackView(arrangedSubviews: [label(title), field, errorLabel(for: key)])
        group.axis = .vertical
        group.spacing = 4
        return group
    }

    private func pickerButton(_ button: UIButton, id: String, action: Selector) {
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.setTitleColor(Palette.ink, for: .normal)
        button.backgroundColor = UIColor(red: 0x14 / 255.0, green: 0x1C / 255.0, blue: 0x26 / 255.0, alpha: 1)
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = Palette.border.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.accessibilityIdentifier = id
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func buildForm() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
        ])

        stack.addArrangedSubview(label("\(row.equipment.name) · \(row.equipment.equipmentId)", size: 16, weight: .bold, color: Palette.ink))
        stack.addArrangedSubview(label("Current location: \(row.system.label) · Verified By: \(performedBy.name ?? "")", size: 13, weight: .medium))

        // Equipment's own notice for this transition (the shared web modal's wording).
        let notice = label("Records where the equipment physically is and sets its status to Damaged. Its on-site store is kept as return context.",
                           size: 13, weight: .medium, color: Palette.amber)
        stack.addArrangedSubview(notice)

        sourceControl.selectedSegmentIndex = 0
        sourceControl.accessibilityIdentifier = "equipmentAudit.offSite.source"
        sourceControl.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)
        stack.addArrangedSubview(sourceControl)

        pickerButton(supplierButton, id: "equipmentAudit.offSite.supplier", action: #selector(pickSupplier))
        supplierButton.setTitle("Select a supplier within drivable range ▾", for: .normal)
        supplierDetail.font = .systemFont(ofSize: 12, weight: .medium)
        supplierDetail.textColor = Palette.subtle
        supplierDetail.numberOfLines = 0
        supplierGroup.axis = .vertical
        supplierGroup.spacing = 4
        [label("Drivable Supplier *"), supplierButton, supplierDetail, errorLabel(for: "supplier_id")].forEach(supplierGroup.addArrangedSubview)
        stack.addArrangedSubview(supplierGroup)

        manualGroup.axis = .vertical
        manualGroup.spacing = 14
        pickerButton(stateButton, id: "equipmentAudit.offSite.state", action: #selector(pickState))
        stateButton.setTitle("State ▾", for: .normal)
        let stateGroup = UIStackView(arrangedSubviews: [label("State"), stateButton, errorLabel(for: "state_id")])
        stateGroup.axis = .vertical
        stateGroup.spacing = 4
        [textField("location_name", "Location Name *", placeholder: "e.g. Humphreys County Fair"),
         textField("address_line_1", "Address Line 1 *"),
         textField("address_line_2", "Address Line 2"),
         textField("city", "City"),
         stateGroup,
         textField("zip_code", "ZIP", keyboard: .numbersAndPunctuation),
         textField("contact_name", "Contact Name"),
         textField("contact_phone", "Contact Phone", keyboard: .phonePad)].forEach(manualGroup.addArrangedSubview)
        manualGroup.isHidden = true
        stack.addArrangedSubview(manualGroup)

        stack.addArrangedSubview(textField("reason", "Reason", placeholder: "e.g. Warranty hydraulic repair"))
        stack.addArrangedSubview(textField("notes", "Notes"))
        stack.addArrangedSubview(errorLabel(for: "_general"))

        submit.setTitle("Move Off-Site", for: .normal)
        submit.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        submit.setTitleColor(.white, for: .normal)
        submit.backgroundColor = UIColor(red: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x06 / 255.0, alpha: 1)
        submit.layer.cornerRadius = 10
        submit.heightAnchor.constraint(equalToConstant: 48).isActive = true
        submit.accessibilityIdentifier = "equipmentAudit.offSite.submit"
        submit.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        submit.isEnabled = false
        spinner.color = Palette.cyan
        stack.addArrangedSubview(submit)
        stack.addArrangedSubview(spinner)
    }

    private func loadOptions() {
        spinner.startAnimating()
        api.loadOffSiteOptions(audit: auditUniqueId, equipment: row.equipment.uniqueId) { [weak self] result in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            switch result {
            case .success(let options):
                self.options = options
                guard options.actions.moveOffSite else {
                    self.close(message: "Kabba no longer shows this unit at a store, so it cannot be sent Off-Site from here.")
                    return
                }
                self.submit.isEnabled = true
                if options.reference.suppliers.isEmpty {
                    self.supplierDetail.text = "No drivable suppliers are set up — use Manual Entry."
                }
            case .failure(let failure):
                self.close(message: failure.message)
            }
        }
    }

    @objc private func sourceChanged() {
        form.source = sourceControl.selectedSegmentIndex == 0 ? .supplier : .manual
        supplierGroup.isHidden = form.source != .supplier
        manualGroup.isHidden = form.source != .manual
    }

    @objc private func pickSupplier() {
        guard let suppliers = options?.reference.suppliers else { return }
        let picker = EquipmentAuditPickerViewController(title: "Drivable Supplier", options: suppliers.map {
            EquipmentAuditPickerOption(id: $0.id, title: $0.name, subtitle: $0.detail.isEmpty ? nil : $0.detail)
        }, selectedId: form.supplierId) { [weak self] option in
            guard let self = self else { return }
            self.form.supplierId = option.id
            self.supplierButton.setTitle(option.title, for: .normal)
            self.supplierDetail.text = option.subtitle
        }
        present(picker.inSheet(), animated: true)
    }

    @objc private func pickState() {
        guard let states = options?.reference.states else { return }
        let picker = EquipmentAuditPickerViewController(title: "State", options: states.map { EquipmentAuditPickerOption(id: $0.id, title: $0.name) },
                                                        selectedId: form.stateId) { [weak self] option in
            self?.form.stateId = option.id
            self?.stateButton.setTitle(option.title, for: .normal)
        }
        present(picker.inSheet(), animated: true)
    }

    // MARK: Submit

    @objc private func submitTapped() {
        view.endEditing(true)
        form.locationName = fields["location_name"]?.text ?? ""
        form.addressLine1 = fields["address_line_1"]?.text ?? ""
        form.addressLine2 = fields["address_line_2"]?.text ?? ""
        form.city = fields["city"]?.text ?? ""
        form.zipCode = fields["zip_code"]?.text ?? ""
        form.contactName = fields["contact_name"]?.text ?? ""
        form.contactPhone = fields["contact_phone"]?.text ?? ""
        form.reason = fields["reason"]?.text ?? ""
        form.notes = fields["notes"]?.text ?? ""

        showErrors([:], general: nil)
        submit.isEnabled = false
        spinner.startAnimating()
        let command = EquipmentAuditCommands.moveOffSite(audit: auditUniqueId, row: row, form: form, performedBy: performedBy.id, operationId: operationId)
        api.perform(command) { [weak self] result in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            self.submit.isEnabled = true
            switch result {
            case .success(let (outcome, message)):
                self.dismiss(animated: true) { self.onDone(outcome, message) }
            case .failure(let failure):
                // A refusal was not recorded: a corrected resubmit is a new request.
                if !failure.isOffline { self.operationId = EquipmentAuditCommands.newOperationId() }
                if failure.isValidation {
                    self.showErrors(failure.validationErrors, general: nil)
                } else if failure.isStale || failure.isAuditClosed {
                    self.close(message: failure.message)
                } else {
                    self.showErrors([:], general: failure.message)
                }
            }
        }
    }

    private func showErrors(_ errors: [String: [String]], general: String?) {
        for (key, label) in errorLabels {
            let message = key == "_general" ? general : errors[key]?.first
            label.text = message
            label.isHidden = message == nil
        }
        // A message for a field this form does not show still reaches the employee.
        let shownKeys = Set(errorLabels.keys)
        if let stray = errors.first(where: { !shownKeys.contains($0.key) })?.value.first, let general = errorLabels["_general"] {
            general.text = stray
            general.isHidden = false
        }
    }

    private func close(message: String) {
        let alert = UIAlertController(title: "Move Off-Site", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            let closed = self?.onClosedWithoutSaving
            self?.dismiss(animated: true) { closed?() }
        })
        present(alert, animated: true)
    }

    private static let fieldOrder = ["location_name", "address_line_1", "address_line_2", "city", "zip_code",
                                     "contact_name", "contact_phone", "reason", "notes"]

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let key = fields.first(where: { $0.value === textField })?.key,
              let index = Self.fieldOrder.firstIndex(of: key) else {
            textField.resignFirstResponder()
            return true
        }
        // The next field that is on screen (manual-entry fields are hidden for a supplier).
        let next = Self.fieldOrder[(index + 1)...].compactMap { fields[$0] }.first { !$0.isHiddenInStack }
        if let next = next { next.becomeFirstResponder() } else { textField.resignFirstResponder() }
        return true
    }
}

private extension UIView {
    /// Hidden itself or inside a hidden stack (the manual-entry group).
    var isHiddenInStack: Bool {
        var view: UIView? = self
        while let v = view { if v.isHidden { return true }; view = v.superview }
        return false
    }
}
