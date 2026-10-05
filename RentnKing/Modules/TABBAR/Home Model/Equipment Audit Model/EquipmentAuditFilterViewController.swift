//
//  EquipmentAuditFilterViewController.swift
//  RentnKing
//
//  Which audit sections the board shows — any combination. "My Sections" is
//  the default (the employee's assigned sections and the Unresolved queue, or
//  everything when nothing is assigned) and keeps following the Section
//  Auditor assignment; a hand-picked set is remembered for this audit. The
//  filter only hides sections: search still covers every unit, and audit
//  membership and totals never change.
//

import UIKit

final class EquipmentAuditFilterViewController: UITableViewController {

    private let board: EquipmentAuditBoard
    private var selected: Set<String>
    /// nil = back to the default ("My Sections").
    private let onApply: ([String]?) -> Void

    init(board: EquipmentAuditBoard, selected: Set<String>, onApply: @escaping ([String]?) -> Void) {
        self.board = board
        self.selected = selected
        self.onApply = onApply
        super.init(style: .insetGrouped)
        title = "Show Sections"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func inSheet() -> UINavigationController {
        let nav = UINavigationController(rootViewController: self)
        nav.modalPresentationStyle = .pageSheet
        nav.overrideUserInterfaceStyle = .dark
        return nav
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "equipmentAudit.filter"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "section")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        let apply = UIBarButtonItem(title: "Apply", style: .done, target: self, action: #selector(apply))
        apply.accessibilityIdentifier = "equipmentAudit.filter.apply"
        navigationItem.rightBarButtonItem = apply

        let mine = UIBarButtonItem(title: "My Sections", style: .plain, target: self, action: #selector(useDefault))
        mine.accessibilityIdentifier = "equipmentAudit.filter.mine"
        let all = UIBarButtonItem(title: "All", style: .plain, target: self, action: #selector(showAllSections))
        all.accessibilityIdentifier = "equipmentAudit.filter.all"
        toolbarItems = [mine, UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), all]
        navigationController?.isToolbarHidden = false
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func apply() {
        let keys = board.sections.map(\.key).filter { selected.contains($0) }
        // Choosing exactly the default set is the default — it keeps following the assignment.
        let isDefault = keys == EquipmentAuditPresentation.defaultVisibleSectionKeys(board)
        dismiss(animated: true) { self.onApply(isDefault ? nil : keys) }
    }

    @objc private func useDefault() {
        dismiss(animated: true) { self.onApply(nil) }
    }

    @objc private func showAllSections() {
        selected = Set(board.sections.map(\.key))
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Search always looks through every section."
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { board.sections.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = board.sections[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "section")
        cell.textLabel?.text = section.assignedToMe ? "\(section.label) — Assigned to You" : section.label
        cell.detailTextLabel?.text = "\(section.counts.total) units · " + EquipmentAuditPresentation.sectionProgress(section)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = selected.contains(section.key) ? .checkmark : .none
        cell.accessibilityIdentifier = "equipmentAudit.filter.\(section.key)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let key = board.sections[indexPath.row].key
        if selected.contains(key) { selected.remove(key) } else { selected.insert(key) }
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}
