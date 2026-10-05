//
//  EquipmentAuditPicker.swift
//  RentnKing
//
//  One searchable list picker for the mobile Equipment Audit: Verified By
//  (employees), where a unit was found (stores), the Off-Site supplier and
//  state. Presented as a sheet; picking an option dismisses it.
//

import UIKit

struct EquipmentAuditPickerOption: Equatable {
    /// nil = a "none / default" choice (e.g. back to the Section Auditor).
    let id: Int?
    let title: String
    var subtitle: String? = nil
}

final class EquipmentAuditPickerViewController: UITableViewController, UISearchResultsUpdating {

    private let options: [EquipmentAuditPickerOption]
    private let selectedId: Int?
    private let onPick: (EquipmentAuditPickerOption) -> Void
    private var shown: [EquipmentAuditPickerOption]
    private let search = UISearchController(searchResultsController: nil)
    private let prompt: String?

    init(title: String, prompt: String? = nil, options: [EquipmentAuditPickerOption], selectedId: Int?, onPick: @escaping (EquipmentAuditPickerOption) -> Void) {
        self.options = options
        self.shown = options
        self.selectedId = selectedId
        self.onPick = onPick
        self.prompt = prompt
        super.init(style: .insetGrouped)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Wrapped in its own navigation controller, ready to present.
    func inSheet() -> UINavigationController {
        let nav = UINavigationController(rootViewController: self)
        nav.modalPresentationStyle = .pageSheet
        nav.overrideUserInterfaceStyle = .dark
        return nav
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "equipmentAudit.picker"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "option")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        if options.count > 8 {
            search.searchResultsUpdater = self
            search.obscuresBackgroundDuringPresentation = false
            search.searchBar.placeholder = "Search"
            navigationItem.searchController = search
            navigationItem.hidesSearchBarWhenScrolling = false
        }
    }

    @objc private func cancel() { close(then: nil) }

    /// An active search controller would swallow a plain dismiss — close the whole sheet.
    private func close(then completion: (() -> Void)?) {
        if search.isActive { search.isActive = false }
        (navigationController ?? self).dismiss(animated: true, completion: completion)
    }

    func updateSearchResults(for searchController: UISearchController) {
        let q = EquipmentAuditPresentation.normalized(searchController.searchBar.text ?? "")
        shown = q.isEmpty ? options : options.filter { EquipmentAuditPresentation.normalized($0.title + ($0.subtitle ?? "")).contains(q) }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { prompt }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shown.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let option = shown[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "option")
        cell.textLabel?.text = option.title
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = option.subtitle
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = option.id == selectedId && option.id != nil ? .checkmark : .none
        cell.accessibilityIdentifier = "equipmentAudit.picker.\(option.id.map(String.init) ?? "none")"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let option = shown[indexPath.row]
        close { self.onPick(option) }
    }
}
