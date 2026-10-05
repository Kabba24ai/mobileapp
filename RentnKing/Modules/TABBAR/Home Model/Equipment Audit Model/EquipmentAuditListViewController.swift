//
//  EquipmentAuditListViewController.swift
//  RentnKing
//
//  Equipment Audit — the entry screen (2026-10-05). The active audits this
//  account may open, each with its progress and the sections assigned to the
//  signed-in employee:
//
//      Skid Steer Audit · EA-00002
//      Bon Aqua — Assigned to You
//      12 of 16 Verified
//
//  Audits are started and completed on the web; any audit can still be opened
//  here in full when the account may view it.
//

import UIKit

final class EquipmentAuditListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {

    private typealias Palette = EquipmentAuditRowCell.Palette

    private let api: EquipmentAuditAPI
    private var index: EquipmentAuditIndex?
    private var failure: EquipmentAuditFailure?
    private var isLoading = false

    private let table = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    init(api: EquipmentAuditAPI = .shared) {
        self.api = api
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.page
        view.accessibilityIdentifier = "equipmentAudit.list"

        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = Palette.page
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 120
        table.register(UITableViewCell.self, forCellReuseIdentifier: "audit")
        refreshControl.tintColor = Palette.cyan
        refreshControl.addTarget(self, action: #selector(load), for: .valueChanged)
        table.refreshControl = refreshControl
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        messageLabel.font = .systemFont(ofSize: 14, weight: .medium)
        messageLabel.textColor = Palette.subtle
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.accessibilityIdentifier = "equipmentAudit.list.message"
        spinner.color = Palette.cyan
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        tabBarController?.tabBar.isHidden = true
        setNavigationBarFor(controller: self, title: "Equipment Audit", isTransperent: true, hideShadowImage: true,
                            leftIcon: "icon_back", rightIcon: "", isDetailsScree: false,
                            leftActionHandler: { [weak self] in self?.navigationController?.popViewController(animated: true) })
        load()
    }

    @objc private func load() {
        guard !isLoading else { return }
        isLoading = true
        if index == nil { showMessage(nil, spinner: true) }
        api.loadIndex { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            self.refreshControl.endRefreshing()
            switch result {
            case .success(let index):
                self.index = index
                self.failure = nil
            case .failure(let failure):
                self.failure = failure
                if failure.isForbidden { self.index = nil }
            }
            self.render()
        }
    }

    private func render() {
        table.reloadData()
        if let failure = failure, index == nil {
            showMessage(failure.isForbidden
                ? "Your account does not have access to Equipment Audits. Ask an administrator for View Equipment Audits."
                : failure.message, spinner: false)
        } else if let index = index, index.audits.isEmpty {
            showMessage("No Equipment Audit is in progress.\nAudits are started on the web.", spinner: false)
        } else {
            table.backgroundView = nil
        }
    }

    private func showMessage(_ text: String?, spinner showSpinner: Bool) {
        let container = UIView()
        if showSpinner {
            spinner.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(spinner)
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor).isActive = true
            spinner.topAnchor.constraint(equalTo: container.topAnchor, constant: 80).isActive = true
            spinner.startAnimating()
        }
        if let text = text {
            messageLabel.text = text
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(messageLabel)
            NSLayoutConstraint.activate([
                messageLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 80),
                messageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
                messageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
            ])
        }
        table.backgroundView = container
    }

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { index?.audits.count ?? 0 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let audit = index!.audits[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "audit", for: indexPath)
        cell.backgroundColor = Palette.page
        cell.selectionStyle = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.accessibilityIdentifier = "equipmentAudit.audit.\(audit.reference)"

        let card = UIView()
        card.backgroundColor = UIColor(red: 0x14 / 255.0, green: 0x1C / 255.0, blue: 0x26 / 255.0, alpha: 1)
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = (audit.mySections.isEmpty ? Palette.border : Palette.green).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(card)

        func line(_ text: String, _ size: CGFloat, _ weight: UIFont.Weight, _ color: UIColor) -> UILabel {
            let l = UILabel()
            l.text = text
            l.font = .systemFont(ofSize: size, weight: weight)
            l.textColor = color
            l.numberOfLines = 0
            return l
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(line("\(audit.title) · \(audit.reference)", 17, .bold, Palette.ink))
        if let lead = audit.lead?.name { stack.addArrangedSubview(line("Audit Lead: \(lead)", 12, .medium, Palette.subtle)) }
        for section in audit.mySections {
            let mine = line("\(section.label) — Assigned to You", 15, .semibold, Palette.greenText)
            mine.accessibilityIdentifier = "equipmentAudit.audit.\(audit.reference).mine.\(section.key)"
            stack.addArrangedSubview(mine)
            stack.addArrangedSubview(line("\(section.counts.verified) of \(section.counts.total) Verified", 13, .medium, Palette.ink))
        }
        stack.setCustomSpacing(8, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(line("Whole audit: \(EquipmentAuditPresentation.overallProgress(audit.summary)) · \(EquipmentAuditPresentation.overallDetail(audit.summary))",
                                      13, .medium, Palette.subtle))
        stack.addArrangedSubview(line(EquipmentAuditPresentation.completionLine(audit.completion), 12, .semibold,
                                      audit.completion.ready ? Palette.greenText : Palette.amber))
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 6),
            card.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -6),
            card.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
        ])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let audit = index?.audits[indexPath.row] else { return }
        navigationController?.pushViewController(EquipmentAuditBoardViewController(auditUniqueId: audit.uniqueId, api: api), animated: true)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}
