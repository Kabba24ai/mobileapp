//
//  SupplierAddViewController.swift
//  RentnKing
//
//  Supplier Directory — Add Supplier (2026-11-13). Short by default: the
//  company name (the only required field), its phone, email and website.
//  Address, each contact role and Category & Tags open on demand.
//
//  Add Supplier first asks Kabba for likely duplicates (same name, phone,
//  email or website). If there are any, the employee can open the existing
//  record instead, or confirm the new one is a different supplier. The new
//  supplier is created in Kabba's own supplier table — Active — and opens at
//  once; it is the same record the office sees under Maintenance Management →
//  Suppliers. Adding needs a connection: offline nothing is saved, and the
//  form says so.
//

import UIKit

final class SupplierAddViewController: UIViewController, UITextFieldDelegate, UIGestureRecognizerDelegate {

    typealias Palette = EquipmentAuditRowCell.Palette

    private let api: SupplierDirectoryAPI
    private(set) var options: SupplierOptions?
    private(set) var draft = SupplierDraft()
    /// One create attempt = one operation id, so a retried tap is a replay, never a second supplier.
    private(set) var operationId = UUID().uuidString
    private var isSaving = false

    /// Called after Kabba added the supplier (the directory reloads).
    var onCreated: ((SupplierDetailEnvelope) -> Void)?
    /// Seam for tests: how an alert / sheet is shown.
    var presentSheet: (UIViewController) -> Void = { _ in }

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private(set) var fields: [String: UITextField] = [:]
    private var errorLabels: [String: UILabel] = [:]
    private let generalError = UILabel()
    private let offlineNotice = UILabel()
    let saveButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let stateButton = UIButton(type: .system)
    private let categoryButton = UIButton(type: .system)
    private let tagsButton = UIButton(type: .system)

    init(api: SupplierDirectoryAPI = .shared) {
        self.api = api
        super.init(nibName: nil, bundle: nil)
        self.presentSheet = { [weak self] vc in self?.present(vc, animated: true) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.page
        view.accessibilityIdentifier = "suppliers.add.form"
        overrideUserInterfaceStyle = .dark
        buildForm()
        loadOptions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        tabBarController?.tabBar.isHidden = true
        setNavigationBarFor(controller: self, title: "Add Supplier", isTransperent: true, hideShadowImage: true,
                            leftIcon: "icon_back", rightIcon: "", isDetailsScree: false,
                            leftActionHandler: { [weak self] in self?.navigationController?.popViewController(animated: true) })
    }

    // MARK: Building blocks

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
        l.accessibilityIdentifier = "suppliers.add.error.\(key)"
        errorLabels[key] = l
        return l
    }

    private func textField(_ key: String, _ title: String, placeholder: String = "", keyboard: UIKeyboardType = .default,
                           content: UITextContentType? = nil, capitalization: UITextAutocapitalizationType = .words) -> UIView {
        let field = UITextField()
        field.placeholder = placeholder
        field.keyboardType = keyboard
        field.textContentType = content
        field.autocapitalizationType = capitalization
        field.autocorrectionType = .no
        field.borderStyle = .roundedRect
        field.backgroundColor = UIColor(red: 0x14 / 255.0, green: 0x1C / 255.0, blue: 0x26 / 255.0, alpha: 1)
        field.textColor = Palette.ink
        field.keyboardAppearance = .dark
        field.returnKeyType = .next
        field.delegate = self
        field.accessibilityIdentifier = "suppliers.add.\(key)"
        field.heightAnchor.constraint(equalToConstant: 42).isActive = true
        fields[key] = field
        let group = UIStackView(arrangedSubviews: [label(title), field, errorLabel(for: key)])
        group.axis = .vertical
        group.spacing = 4
        return group
    }

    private func pickerButton(_ button: UIButton, title: String, id: String, action: Selector) -> UIView {
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.setTitleColor(Palette.ink, for: .normal)
        button.setTitleColor(Palette.subtle, for: .disabled)
        button.backgroundColor = UIColor(red: 0x14 / 255.0, green: 0x1C / 255.0, blue: 0x26 / 255.0, alpha: 1)
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = Palette.border.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        button.heightAnchor.constraint(equalToConstant: 42).isActive = true
        button.accessibilityIdentifier = id
        button.addTarget(self, action: action, for: .touchUpInside)
        let group = UIStackView(arrangedSubviews: [label(title), button])
        group.axis = .vertical
        group.spacing = 4
        return group
    }

    /// A heading that opens and closes its fields (closed by default).
    private func expandable(_ title: String, id: String, _ content: [UIView]) -> UIView {
        let body = UIStackView(arrangedSubviews: content)
        body.axis = .vertical
        body.spacing = 12
        body.isHidden = true
        body.accessibilityIdentifier = "\(id).fields"

        let header = UIButton(type: .system)
        header.contentHorizontalAlignment = .leading
        header.setTitle("▸  " + title, for: .normal)
        header.setTitleColor(Palette.cyan, for: .normal)
        header.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        header.heightAnchor.constraint(equalToConstant: 40).isActive = true
        header.accessibilityIdentifier = id
        header.addAction(UIAction { [weak header, weak body] _ in
            guard let body = body else { return }
            // Put the keyboard (and its toolbar) away so the section's fields can be seen.
            header?.window?.endEditing(true)
            let opening = body.isHidden
            UIView.animate(withDuration: 0.2) { body.isHidden = !opening; body.alpha = opening ? 1 : 0 }
            header?.setTitle((opening ? "▾  " : "▸  ") + title, for: .normal)
        }, for: .touchUpInside)

        let divider = UIView()
        divider.backgroundColor = Palette.border
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let group = UIStackView(arrangedSubviews: [divider, header, body])
        group.axis = .vertical
        group.spacing = 6
        return group
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
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
        ])

        offlineNotice.font = .systemFont(ofSize: 13, weight: .semibold)
        offlineNotice.textColor = Palette.amber
        offlineNotice.numberOfLines = 0
        offlineNotice.isHidden = true
        offlineNotice.accessibilityIdentifier = "suppliers.add.offline"
        stack.addArrangedSubview(offlineNotice)

        stack.addArrangedSubview(textField("name", "Company name (required)", placeholder: "Supplier company name", content: .organizationName))
        stack.addArrangedSubview(textField("phone", "Company phone", placeholder: "(555) 555-0100", keyboard: .phonePad, content: .telephoneNumber))
        stack.addArrangedSubview(textField("email", "Email", placeholder: "orders@supplier.com", keyboard: .emailAddress, content: .emailAddress, capitalization: .none))
        stack.addArrangedSubview(textField("website", "Website", placeholder: "supplier.com", keyboard: .URL, content: .URL, capitalization: .none))

        stack.addArrangedSubview(expandable("Address", id: "suppliers.add.section.address", [
            textField("address", "Street", content: .fullStreetAddress),
            textField("city", "City", content: .addressCity),
            pickerButton(stateButton, title: "State", id: "suppliers.add.state", action: #selector(pickState)),
            errorLabel(for: "state_id"),
            textField("zip_code", "ZIP", keyboard: .numbersAndPunctuation, content: .postalCode, capitalization: .none),
        ]))
        for (key, title) in SupplierDraft.contactRoles {
            stack.addArrangedSubview(expandable(title, id: "suppliers.add.section.\(key)", [
                textField(key + "_name", "Name", content: .name),
                textField(key + "_phone", "Phone", keyboard: .phonePad, content: .telephoneNumber),
                textField(key + "_email", "Email", keyboard: .emailAddress, content: .emailAddress, capitalization: .none),
            ]))
        }
        stack.addArrangedSubview(expandable("Category & Tags", id: "suppliers.add.section.classification", [
            pickerButton(categoryButton, title: "Category", id: "suppliers.add.category", action: #selector(pickCategory)),
            errorLabel(for: "supplier_category_id"),
            pickerButton(tagsButton, title: "Tags", id: "suppliers.add.tags", action: #selector(pickTags)),
            errorLabel(for: "tags"),
        ]))

        generalError.font = .systemFont(ofSize: 13, weight: .medium)
        generalError.textColor = Palette.red
        generalError.numberOfLines = 0
        generalError.isHidden = true
        generalError.accessibilityIdentifier = "suppliers.add.error.general"
        stack.addArrangedSubview(generalError)

        saveButton.setTitle("Add Supplier", for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        saveButton.setTitleColor(.black, for: .normal)
        saveButton.backgroundColor = Palette.cyan
        saveButton.layer.cornerRadius = 12
        saveButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        saveButton.accessibilityIdentifier = "suppliers.add.save"
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        spinner.color = .black
        spinner.translatesAutoresizingMaskIntoConstraints = false
        saveButton.addSubview(spinner)
        spinner.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor).isActive = true
        spinner.trailingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: -16).isActive = true
        stack.addArrangedSubview(saveButton)
        stack.addArrangedSubview(label("New suppliers are added as Active. Payment terms, tax details and other office settings are managed in Kabba on the office computer.",
                                       size: 12, weight: .medium))
        refreshPickers()
    }

    // MARK: Options (category, tags, state)

    private func loadOptions() {
        api.options { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let options):
                self.options = options
                self.offlineNotice.isHidden = true
            case .failure(let failure):
                self.offlineNotice.text = failure.isOffline ? SupplierDirectoryPresentation.offlineAdd
                    : failure.isForbidden ? SupplierDirectoryPresentation.forbidden : failure.message
                self.offlineNotice.isHidden = false
            }
            self.refreshPickers()
        }
    }

    private func refreshPickers() {
        let states = options?.states ?? []
        let state = states.first { $0.id == draft.stateId }
        stateButton.setTitle(state.map { $0.name } ?? (options == nil ? "Available when connected" : "Choose a state"), for: .normal)
        let category = options?.categories.first { $0.id == draft.categoryId }
        categoryButton.setTitle(category?.name ?? (options == nil ? "Available when connected" : "Choose a category"), for: .normal)
        let tagNames = (options?.tags ?? []).filter { draft.tagIds.contains($0.id) }.map(\.name)
        tagsButton.setTitle(tagNames.isEmpty ? (options == nil ? "Available when connected" : "Choose tags") : tagNames.joined(separator: ", "), for: .normal)
        [stateButton, categoryButton, tagsButton].forEach { $0.isEnabled = options != nil }
    }

    @objc private func pickState() {
        guard let states = options?.states else { return }
        let picker = EquipmentAuditPickerViewController(title: "State",
                                                        options: [EquipmentAuditPickerOption(id: nil, title: "None")]
                                                            + states.map { EquipmentAuditPickerOption(id: $0.id, title: $0.name, subtitle: $0.abbreviation) },
                                                        selectedId: draft.stateId) { [weak self] option in
            self?.draft.stateId = option.id
            self?.refreshPickers()
        }
        presentSheet(picker.inSheet())
    }

    @objc private func pickCategory() {
        guard let categories = options?.categories else { return }
        let picker = EquipmentAuditPickerViewController(title: "Category",
                                                        options: [EquipmentAuditPickerOption(id: nil, title: "None")]
                                                            + categories.map { EquipmentAuditPickerOption(id: $0.id, title: $0.name) },
                                                        selectedId: draft.categoryId) { [weak self] option in
            self?.draft.categoryId = option.id
            self?.refreshPickers()
        }
        presentSheet(picker.inSheet())
    }

    @objc private func pickTags() {
        guard let tags = options?.tags else { return }
        let picker = SupplierTagsPickerViewController(tags: tags, selected: Set(draft.tagIds)) { [weak self] chosen in
            self?.draft.tagIds = tags.map(\.id).filter { chosen.contains($0) }
            self?.refreshPickers()
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.overrideUserInterfaceStyle = .dark
        presentSheet(nav)
    }

    // MARK: Save

    /// The form's fields into the draft (pickers write the draft directly).
    func collect() {
        func text(_ key: String) -> String { fields[key]?.text ?? "" }
        draft.name = text("name")
        draft.phone = text("phone")
        draft.email = text("email")
        draft.website = text("website")
        draft.address = text("address")
        draft.city = text("city")
        draft.zipCode = text("zip_code")
        for (key, _) in SupplierDraft.contactRoles {
            draft.contacts[key] = SupplierContactDraft(name: text(key + "_name"), phone: text(key + "_phone"), email: text(key + "_email"))
        }
    }

    @objc func save() {
        guard !isSaving else { return }
        view.endEditing(true)
        collect()
        showErrors([:], general: nil)
        let problems = draft.validationErrors()
        guard problems.isEmpty else {
            showErrors(problems.mapValues { [$0] }, general: nil)
            return
        }
        setSaving(true)
        api.duplicates(for: draft) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let matches) where !matches.isEmpty:
                self.setSaving(false)
                self.offerDuplicates(matches)
            case .failure(let failure) where failure.isOffline:
                self.setSaving(false)
                self.showErrors([:], general: SupplierDirectoryPresentation.offlineAdd)
            case .failure(let failure) where failure.isForbidden:
                self.setSaving(false)
                self.showErrors([:], general: SupplierDirectoryPresentation.forbidden)
            default:
                // No likely duplicate (or the check itself failed — Kabba checks again on create).
                self.create(acknowledgeDuplicates: false)
            }
        }
    }

    private func create(acknowledgeDuplicates: Bool) {
        setSaving(true)
        api.create(draft, acknowledgeDuplicates: acknowledgeDuplicates, operationId: operationId) { [weak self] result in
            guard let self = self else { return }
            self.setSaving(false)
            switch result {
            case .success(let envelope):
                self.finished(envelope)
            case .failure(let failure) where failure.isPossibleDuplicate:
                self.offerDuplicates(failure.duplicates)
            case .failure(let failure):
                if failure.isOffline {
                    self.showErrors([:], general: failure.message == SupplierDirectoryFailure.offline.message
                        ? SupplierDirectoryPresentation.offlineAdd
                        : "The connection dropped before Kabba confirmed the supplier. Search the directory before adding it again.")
                } else {
                    // A refusal is final for this attempt: the next tap is a new operation.
                    self.operationId = UUID().uuidString
                    self.showErrors(failure.validationErrors, general: failure.validationErrors.isEmpty ? failure.message : nil)
                }
            }
        }
    }

    /// Likely matches: open one of them instead, or confirm this is a different supplier.
    private func offerDuplicates(_ matches: [SupplierDuplicate]) {
        let lines = matches.map { match -> String in
            let detail = SupplierDirectoryPresentation.duplicateLine(match)
            return detail.isEmpty ? "• \(match.name)" : "• \(match.name) — \(detail)"
        }
        let sheet = UIAlertController(title: "This supplier may already be in Kabba",
                                      message: lines.joined(separator: "\n"), preferredStyle: .actionSheet)
        for match in matches {
            sheet.addAction(UIAlertAction(title: "Open \(match.name)", style: .default) { [weak self] _ in self?.openExisting(match) })
        }
        sheet.addAction(UIAlertAction(title: "Add as a Different Supplier", style: .default) { [weak self] _ in
            self?.create(acknowledgeDuplicates: true)
        })
        sheet.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
        sheet.popoverPresentationController?.sourceView = saveButton
        sheet.popoverPresentationController?.sourceRect = saveButton.bounds
        sheet.view.accessibilityIdentifier = "suppliers.add.duplicates"
        presentSheet(sheet)
    }

    private func openExisting(_ match: SupplierDuplicate) {
        let detail = SupplierDetailViewController(uniqueId: match.uniqueId, title: match.name, api: api)
        replaceForm(with: detail)
    }

    private func finished(_ envelope: SupplierDetailEnvelope) {
        onCreated?(envelope)
        let detail = SupplierDetailViewController(uniqueId: envelope.supplier.uniqueId, title: envelope.supplier.name, initial: envelope, api: api)
        let nav = navigationController
        replaceForm(with: detail)
        let saved = UIAlertController(title: "Supplier Saved", message: "\(envelope.supplier.name) was added to Kabba.", preferredStyle: .alert)
        saved.addAction(UIAlertAction(title: "OK", style: .default))
        saved.view.accessibilityIdentifier = "suppliers.add.saved"
        // Shown once the record is on screen — presenting mid-transition would be dropped.
        let show = { [weak detail] in detail?.present(saved, animated: true) }
        if let coordinator = nav?.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in show() }
        } else {
            show()
        }
    }

    /// The form leaves the stack: Back from the supplier returns to the directory.
    private func replaceForm(with next: UIViewController) {
        guard let nav = navigationController else { return }
        var stack = nav.viewControllers
        if let index = stack.firstIndex(of: self) { stack.replaceSubrange(index..., with: [next]) } else { stack.append(next) }
        nav.setViewControllers(stack, animated: nav.isViewLoaded && nav.view.window != nil)
    }

    /// A problem inside a closed section opens it.
    private func openSection(containing view: UIView) {
        var current: UIView? = view.superview
        while let v = current, v !== stack {
            if v.accessibilityIdentifier?.hasSuffix(".fields") == true, v.isHidden {
                v.isHidden = false
                v.alpha = 1
            }
            current = v.superview
        }
    }

    private func setSaving(_ saving: Bool) {
        isSaving = saving
        saveButton.isEnabled = !saving
        saveButton.alpha = saving ? 0.7 : 1
        saving ? spinner.startAnimating() : spinner.stopAnimating()
    }

    /// Errors under their fields; anything without a field on the form goes to the general line.
    func showErrors(_ errors: [String: [String]], general: String?) {
        errorLabels.values.forEach { $0.isHidden = true; $0.text = nil }
        var leftovers: [String] = []
        for (key, messages) in errors {
            let fieldKey = key.hasPrefix("tags.") ? "tags" : key
            if let l = errorLabels[fieldKey] {
                l.text = messages.first
                l.isHidden = false
                openSection(containing: l)
            } else if let first = messages.first {
                leftovers.append(first)
            }
        }
        let text = ([general].compactMap { $0 } + leftovers).joined(separator: "\n")
        generalError.text = text
        generalError.isHidden = text.isEmpty
        if let first = errors.keys.sorted().first, let field = fields[first] { field.becomeFirstResponder() }
    }

    // MARK: Keyboard

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let visible = stack.allTextFields.filter { !$0.isHiddenInHierarchy }
        if let index = visible.firstIndex(of: textField), index + 1 < visible.count {
            visible[index + 1].becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}

private extension UIView {
    var allTextFields: [UITextField] {
        subviews.flatMap { ($0 as? UITextField).map { [$0] } ?? $0.allTextFields }
    }

    var isHiddenInHierarchy: Bool {
        var view: UIView? = self
        while let v = view { if v.isHidden { return true }; view = v.superview }
        return false
    }
}

/// Choose any number of tags.
final class SupplierTagsPickerViewController: UITableViewController {
    private let tags: [SupplierOption]
    private var selected: Set<Int>
    private let onDone: (Set<Int>) -> Void

    init(tags: [SupplierOption], selected: Set<Int>, onDone: @escaping (Set<Int>) -> Void) {
        self.tags = tags
        self.selected = selected
        self.onDone = onDone
        super.init(style: .insetGrouped)
        title = "Tags"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "suppliers.tags"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "tag")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
    }

    @objc private func cancel() { dismiss(animated: true) }
    @objc private func done() { onDone(selected); dismiss(animated: true) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(tags.count, 1) }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "tag", for: indexPath)
        guard !tags.isEmpty else {
            cell.textLabel?.text = "No tags are set up in Kabba yet."
            cell.selectionStyle = .none
            cell.accessoryType = .none
            return cell
        }
        let tag = tags[indexPath.row]
        cell.textLabel?.text = tag.name
        cell.accessoryType = selected.contains(tag.id) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !tags.isEmpty else { return }
        let id = tags[indexPath.row].id
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}
