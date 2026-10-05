//
//  EquipmentAuditBoardViewController.swift
//  RentnKing
//
//  The live audit on the phone (2026-10-05): land on your section, scroll a
//  stable list, tap Verify, watch it turn green, move on.
//
//  Everything shown is Laravel's board (GET equipment-audits/{audit}) — the
//  web audit's own sections, AuditSort order, derived state and Verified By
//  defaults. The phone remembers only presentation choices: the working store
//  (where the employee is physically auditing, defaulting to their assigned
//  store), a section filter they picked, and who verifies in a section that
//  has no Section Auditor.
//
//  Normal verification is one tap. Anything else — a unit Kabba places
//  elsewhere, Off-Site, a rental found in the yard, Unresolved, a different
//  Verified By — is a deliberate step. Every write is online; a refusal
//  (stale screen, permission, validation) is shown as Kabba worded it and the
//  board refreshes so the employee decides again on current truth.
//

import UIKit

final class EquipmentAuditBoardViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
                                                UISearchBarDelegate, UIGestureRecognizerDelegate {

    private typealias Palette = EquipmentAuditRowCell.Palette

    private let auditUniqueId: String
    private let api: EquipmentAuditAPI

    private(set) var board: EquipmentAuditBoard?
    private var shownSections: [EquipmentAuditSection] = []
    private var query = ""
    private var busy: Set<String> = []
    private var lastUpdated: Date?
    private var lastLoadFailure: EquipmentAuditFailure?
    /// Laravel's confirmation of the last action ("TAK-SS-14 verified."), shown in the
    /// header for a few seconds. Never an overlay: the next row must stay tappable.
    private var lastConfirmation: (text: String, at: Date)?
    private static let confirmationSeconds: TimeInterval = 4
    private var isLoading = false
    private var refreshTimer: Timer?
    private var foregroundObserver: NSObjectProtocol?

    // Fixed header
    private let headerStack = UIStackView()
    private let titleLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressDetailLabel = UILabel()
    private let progressBar = UIProgressView(progressViewStyle: .bar)
    private let completionLabel = UILabel()
    private let workingButton = UIButton(type: .system)
    private let verifyingButton = UIButton(type: .system)
    private let searchBar = UISearchBar()
    private let freshnessLabel = UILabel()

    private let table = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let backgroundLabel = UILabel()
    private let loadingSpinner = UIActivityIndicatorView(style: .large)

    /// How often an open board re-reads the audit, so a colleague's work and a
    /// reassignment show up without pulling.
    static let refreshInterval: TimeInterval = 30

    init(auditUniqueId: String, api: EquipmentAuditAPI = .shared) {
        self.auditUniqueId = auditUniqueId
        self.api = api
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let observer = foregroundObserver { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.page
        view.accessibilityIdentifier = "equipmentAudit.board"
        buildHeader()
        buildTable()
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.load()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        tabBarController?.tabBar.isHidden = true
        configureNavigationBar()
        load()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.presentedViewController == nil, self.busy.isEmpty else { return }
            self.load()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func configureNavigationBar() {
        let custom = EquipmentAuditMemory.visibleSections(audit: auditUniqueId) != nil
        setNavigationBarForButtons(controller: self, title: "Equipment Audit", isTransperent: true,
                                   hideShadowImage: true, leftIcon: "icon_back",
                                   rightIcon: ["icon_Filter"], isFilter: custom) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        } rightActionHandler: { [weak self] _, _ in
            self?.openFilter()
        }
    }

    // MARK: Layout

    private func buildHeader() {
        headerStack.axis = .vertical
        headerStack.spacing = 6
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerStack)

        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = Palette.ink
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityIdentifier = "equipmentAudit.title"

        progressLabel.font = .systemFont(ofSize: 15, weight: .heavy)
        progressLabel.textColor = Palette.greenText
        progressLabel.accessibilityIdentifier = "equipmentAudit.progress"
        progressDetailLabel.font = .systemFont(ofSize: 13, weight: .medium)
        progressDetailLabel.textColor = Palette.subtle
        progressDetailLabel.textAlignment = .right
        progressDetailLabel.adjustsFontSizeToFitWidth = true
        let progressRow = UIStackView(arrangedSubviews: [progressLabel, progressDetailLabel])
        progressRow.spacing = 8

        progressBar.progressTintColor = Palette.green
        progressBar.trackTintColor = Palette.border
        progressBar.layer.cornerRadius = 2
        progressBar.clipsToBounds = true
        progressBar.heightAnchor.constraint(equalToConstant: 5).isActive = true

        completionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        completionLabel.numberOfLines = 0
        completionLabel.accessibilityIdentifier = "equipmentAudit.completion"

        for (button, id) in [(workingButton, "equipmentAudit.workingStore"), (verifyingButton, "equipmentAudit.verifyingAs")] {
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.setTitleColor(Palette.cyan, for: .normal)
            button.layer.cornerRadius = 15
            button.layer.borderWidth = 1
            button.layer.borderColor = Palette.cyan.withAlphaComponent(0.6).cgColor
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            button.accessibilityIdentifier = id
        }
        workingButton.addTarget(self, action: #selector(chooseWorkingStore), for: .touchUpInside)
        verifyingButton.addTarget(self, action: #selector(chooseVerifyingAs), for: .touchUpInside)
        // Its own line, in full: who is recorded for units in sections nobody owns.
        verifyingButton.layer.borderWidth = 0
        verifyingButton.contentEdgeInsets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        verifyingButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        verifyingButton.titleLabel?.numberOfLines = 0
        verifyingButton.contentHorizontalAlignment = .leading
        let workingRow = UIStackView(arrangedSubviews: [workingButton, UIView()])
        workingRow.alignment = .center
        let chips = UIStackView(arrangedSubviews: [workingRow, verifyingButton])
        chips.axis = .vertical
        chips.alignment = .fill
        chips.spacing = 4

        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = "Search name or Equipment ID"
        searchBar.delegate = self
        searchBar.autocapitalizationType = .allCharacters
        searchBar.autocorrectionType = .no
        searchBar.keyboardAppearance = .dark
        searchBar.searchTextField.textColor = Palette.ink
        searchBar.searchTextField.accessibilityIdentifier = "equipmentAudit.search"
        searchBar.overrideUserInterfaceStyle = .dark

        freshnessLabel.font = .systemFont(ofSize: 11, weight: .medium)
        freshnessLabel.textColor = Palette.subtle
        freshnessLabel.numberOfLines = 0
        freshnessLabel.accessibilityIdentifier = "equipmentAudit.freshness"

        [titleLabel, progressRow, progressBar, completionLabel, chips, searchBar, freshnessLabel].forEach(headerStack.addArrangedSubview)
        headerStack.setCustomSpacing(10, after: completionLabel)
        headerStack.setCustomSpacing(2, after: chips)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
        ])
    }

    private func buildTable() {
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = Palette.page
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 64
        table.sectionHeaderHeight = UITableView.automaticDimension
        table.estimatedSectionHeaderHeight = 54
        if #available(iOS 15.0, *) { table.sectionHeaderTopPadding = 0 }
        table.keyboardDismissMode = .onDrag
        table.register(EquipmentAuditRowCell.self, forCellReuseIdentifier: EquipmentAuditRowCell.reuseId)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "empty")
        table.accessibilityIdentifier = "equipmentAudit.rows"
        refreshControl.tintColor = Palette.cyan
        refreshControl.addTarget(self, action: #selector(pulled), for: .valueChanged)
        table.refreshControl = refreshControl
        view.addSubview(table)

        backgroundLabel.font = .systemFont(ofSize: 14, weight: .medium)
        backgroundLabel.textColor = Palette.subtle
        backgroundLabel.textAlignment = .center
        backgroundLabel.numberOfLines = 0
        backgroundLabel.accessibilityIdentifier = "equipmentAudit.empty"
        loadingSpinner.color = Palette.cyan

        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 6),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: Data

    @objc private func pulled() { load() }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        if board == nil { showBackground(spinner: true, text: nil) }

        api.loadBoard(audit: auditUniqueId) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            self.refreshControl.endRefreshing()
            switch result {
            case .success(let board):
                self.board = board
                self.lastUpdated = Date()
                self.lastLoadFailure = nil
            case .failure(let failure):
                self.lastLoadFailure = failure
                if failure.isAuditClosed {
                    self.alert(failure.message) { self.navigationController?.popViewController(animated: true) }
                    return
                }
            }
            self.render()
        }
    }

    // MARK: Rendering

    private var workingStoreId: Int? {
        guard let board = board else { return nil }
        return EquipmentAuditPresentation.resolveWorkingStoreId(remembered: EquipmentAuditMemory.workingStoreId(audit: auditUniqueId), board: board)
    }

    private var verifyingAsId: Int? { EquipmentAuditMemory.verifyingAs(audit: auditUniqueId) }

    private var visibleKeys: Set<String> {
        guard let board = board else { return [] }
        return Set(EquipmentAuditMemory.visibleSections(audit: auditUniqueId) ?? EquipmentAuditPresentation.defaultVisibleSectionKeys(board))
    }

    func render() {
        updateFreshness()
        guard let board = board else {
            shownSections = []
            table.reloadData()
            let failure = lastLoadFailure
            showBackground(spinner: false, text: failure?.isForbidden == true
                ? "Your account does not have access to Equipment Audits."
                : (failure?.message ?? "Pull to load the audit."))
            return
        }

        titleLabel.text = EquipmentAuditPresentation.auditTitle(board.audit)
        progressLabel.text = EquipmentAuditPresentation.overallProgress(board.audit.summary)
        progressDetailLabel.text = EquipmentAuditPresentation.overallDetail(board.audit.summary)
        progressBar.progress = board.audit.summary.total > 0 ? Float(board.audit.summary.verified) / Float(board.audit.summary.total) : 0
        completionLabel.text = EquipmentAuditPresentation.completionLine(board.audit.completion)
        completionLabel.textColor = board.audit.completion.ready ? Palette.greenText : Palette.amber

        let working = board.store(workingStoreId)
        workingButton.setTitle("📍 Working at: \(working?.name ?? "Not set") ▾", for: .normal)
        workingButton.isHidden = !board.can.verify
        // Only needed where a section has no Section Auditor to default to.
        let needsFallback = board.can.verify && board.sections.contains { s in s.rows.contains { $0.verifiedByDefault == nil && $0.state != .verified } }
        verifyingButton.isHidden = !needsFallback
        let fallback = EquipmentAuditPresentation.unassignedSectionVerifier(board, fallbackEmployeeId: verifyingAsId)
        verifyingButton.setTitle("Sections with no Section Auditor — Verified By: \(fallback?.name ?? "choose") ▾", for: .normal)

        shownSections = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? EquipmentAuditPresentation.orderedSections(board, visible: visibleKeys)
            : EquipmentAuditPresentation.search(board, query: query)
        table.reloadData()

        if shownSections.isEmpty {
            showBackground(spinner: false, text: query.isEmpty ? "No sections selected. Use the filter to choose sections." : "No unit in this audit matches “\(query)”.")
        } else {
            table.backgroundView = nil
        }
    }

    private func updateFreshness() {
        if let confirmation = lastConfirmation, Date().timeIntervalSince(confirmation.at) < Self.confirmationSeconds {
            freshnessLabel.text = "✓ " + confirmation.text
            freshnessLabel.textColor = Palette.greenText
            return
        }
        let time = lastUpdated.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) }
        if let failure = lastLoadFailure, failure.isOffline {
            freshnessLabel.text = time.map { "Offline · showing the audit as of \($0). Verifying needs a connection." } ?? EquipmentAuditPresentation.offlineMessage
            freshnessLabel.textColor = Palette.amber
        } else {
            let scope = query.isEmpty ? "" : " · Searching every section"
            freshnessLabel.text = time.map { "Updated \($0)\(scope)" } ?? (query.isEmpty ? nil : "Searching every section")
            freshnessLabel.textColor = Palette.subtle
        }
    }

    private func showBackground(spinner: Bool, text: String?) {
        let container = UIView()
        if spinner {
            loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(loadingSpinner)
            loadingSpinner.centerXAnchor.constraint(equalTo: container.centerXAnchor).isActive = true
            loadingSpinner.topAnchor.constraint(equalTo: container.topAnchor, constant: 60).isActive = true
            loadingSpinner.startAnimating()
        } else {
            loadingSpinner.stopAnimating()
        }
        if let text = text {
            backgroundLabel.text = text
            backgroundLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(backgroundLabel)
            NSLayoutConstraint.activate([
                backgroundLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 60),
                backgroundLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
                backgroundLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
            ])
        }
        table.backgroundView = container
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { shownSections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(shownSections[section].rows.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = shownSections[indexPath.section]
        guard indexPath.row < section.rows.count, let board = board else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "empty", for: indexPath)
            cell.backgroundColor = Palette.page
            cell.selectionStyle = .none
            cell.textLabel?.text = section.key == EquipmentAuditPresentation.unresolvedSectionKey
                ? "Nothing is Unresolved." : "No units here right now."
            cell.textLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            cell.textLabel?.textColor = Palette.subtle
            return cell
        }

        let row = section.rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: EquipmentAuditRowCell.reuseId, for: indexPath) as! EquipmentAuditRowCell
        let tap = EquipmentAuditRouting.primaryTap(row, workingStoreId: workingStoreId, board: board)
        let verifyTitle: String? = {
            switch tap {
            case .verifyHere, .mismatch: return "Verify"
            case .choose: return "Verify…"
            case .none: return nil
            }
        }()
        let menu = EquipmentAuditRouting.menu(row, workingStoreId: workingStoreId, board: board)
        cell.configure(row: row, verifyTitle: verifyTitle, hasMore: !menu.isEmpty, busy: busy.contains(row.equipment.uniqueId))
        cell.onVerify = { [weak self, weak cell] in self?.primaryTapped(row, from: cell) }
        cell.onMore = { [weak self, weak cell] in self?.presentMenu(row, from: cell) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = shownSections[indexPath.section]
        guard indexPath.row < section.rows.count else { return }
        presentMenu(section.rows[indexPath.row], from: tableView.cellForRow(at: indexPath))
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection index: Int) -> UIView? {
        let section = shownSections[index]
        let header = UIView()
        header.backgroundColor = UIColor(red: 0x14 / 255.0, green: 0x1C / 255.0, blue: 0x26 / 255.0, alpha: 1)
        header.accessibilityIdentifier = "equipmentAudit.section.\(section.key)"

        let title = UILabel()
        title.text = EquipmentAuditPresentation.sectionTitle(section)
        title.font = .systemFont(ofSize: 15, weight: .bold)
        title.textColor = section.kind == "unresolved" ? Palette.amber : Palette.ink
        title.numberOfLines = 0

        let progress = UILabel()
        progress.text = EquipmentAuditPresentation.sectionProgress(section)
        progress.font = .systemFont(ofSize: 12, weight: .medium)
        progress.textColor = Palette.subtle
        progress.accessibilityIdentifier = "equipmentAudit.sectionProgress.\(section.key)"

        var top: [UIView] = [title]
        if section.assignedToMe {
            let chip = PaddedLabel()
            chip.text = "ASSIGNED TO YOU"
            chip.font = .systemFont(ofSize: 10, weight: .heavy)
            chip.textColor = Palette.greenText
            chip.layer.borderColor = Palette.green.cgColor
            chip.layer.borderWidth = 1
            chip.layer.cornerRadius = 4
            chip.setContentHuggingPriority(.required, for: .horizontal)
            chip.setContentCompressionResistancePriority(.required, for: .horizontal)
            chip.accessibilityIdentifier = "equipmentAudit.assigned.\(section.key)"
            top.append(chip)
        }
        let topRow = UIStackView(arrangedSubviews: top)
        topRow.spacing = 8
        topRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [topRow, progress])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
        ])

        if board?.can.assignWork == true {
            header.tag = index
            header.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(sectionHeaderTapped(_:))))
        }
        return header
    }

    // MARK: Header controls

    @objc private func chooseWorkingStore() {
        guard let board = board else { return }
        var options = board.stores.map { EquipmentAuditPickerOption(id: $0.id, title: $0.name) }
        options.append(EquipmentAuditPickerOption(id: nil, title: "My section's store (default)",
                                                  subtitle: "Follows your Section Auditor assignment"))
        let picker = EquipmentAuditPickerViewController(title: "Working at", prompt: "Where are you physically auditing?",
                                                        options: options, selectedId: workingStoreId) { [weak self] option in
            guard let self = self else { return }
            EquipmentAuditMemory.setWorkingStoreId(option.id, audit: self.auditUniqueId)
            self.render()
        }
        present(picker.inSheet(), animated: true)
    }

    @objc private func chooseVerifyingAs() {
        pickEmployee(title: "Verified By", prompt: "Who verifies units in sections with no Section Auditor?", selected: verifyingAsId) { [weak self] person in
            guard let self = self else { return }
            EquipmentAuditMemory.setVerifyingAs(person.id, audit: self.auditUniqueId)
            self.render()
        }
    }

    private func openFilter() {
        guard let board = board else { return }
        let sheet = EquipmentAuditFilterViewController(board: board, selected: visibleKeys) { [weak self] keys in
            guard let self = self else { return }
            EquipmentAuditMemory.setVisibleSections(keys, audit: self.auditUniqueId)
            self.configureNavigationBar()
            self.render()
        }
        present(sheet.inSheet(), animated: true)
    }

    @objc private func sectionHeaderTapped(_ gesture: UITapGestureRecognizer) {
        guard let board = board, let index = gesture.view?.tag, index < shownSections.count else { return }
        let section = shownSections[index]
        let sheet = UIAlertController(title: "Section Auditor — \(section.label)",
                                      message: section.auditor.map { "Currently \($0.name ?? "")" } ?? "No Section Auditor yet.",
                                      preferredStyle: .actionSheet)
        if board.me.isEmployee, section.auditor?.id != board.me.id {
            sheet.addAction(UIAlertAction(title: "Assign Me (\(board.me.name))", style: .default) { [weak self] _ in
                self?.assignSection(section, employeeId: board.me.id)
            })
        }
        sheet.addAction(UIAlertAction(title: "Choose Employee…", style: .default) { [weak self] _ in
            self?.pickEmployee(title: "Section Auditor", prompt: section.label, selected: section.auditor?.id) { person in
                self?.assignSection(section, employeeId: person.id)
            }
        })
        if section.auditor != nil {
            sheet.addAction(UIAlertAction(title: "No Section Auditor", style: .destructive) { [weak self] _ in
                self?.assignSection(section, employeeId: nil)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet, from: gesture.view)
    }

    private func assignSection(_ section: EquipmentAuditSection, employeeId: Int?) {
        run(EquipmentAuditCommands.assignSectionAuditor(audit: auditUniqueId, sectionKey: section.key, employeeId: employeeId), unit: nil)
    }

    // MARK: Search

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText
        render()
        // Cleared (the ⓧ button): back to the list, keyboard out of the way of the rows.
        if searchText.isEmpty { DispatchQueue.main.async { searchBar.resignFirstResponder() } }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }

    // MARK: Row actions

    private func primaryTapped(_ row: EquipmentAuditRow, from source: UIView?) {
        guard let board = board else { return }
        switch EquipmentAuditRouting.primaryTap(row, workingStoreId: workingStoreId, board: board) {
        case .verifyHere(let storeId):
            withVerifier(for: row) { [weak self] person in
                guard let self = self else { return }
                self.run(EquipmentAuditCommands.verify(audit: self.auditUniqueId, row: row, observedStoreId: storeId, performedBy: person.id), unit: row)
            }
        case .mismatch(let mismatch):
            presentMismatch(row, mismatch)
        case .choose:
            presentMenu(row, from: source)
        case .none:
            break
        }
    }

    private func presentMenu(_ row: EquipmentAuditRow, from source: UIView?) {
        guard let board = board else { return }
        let items = EquipmentAuditRouting.menu(row, workingStoreId: workingStoreId, board: board)
        var lines = [row.stateLabel, "System: \(row.system.label)"]
        if let path = row.path { lines.append("Path: \(path)") }
        if let discrepancy = row.discrepancy { lines.append(discrepancy) }
        if let rental = row.rental, let order = rental.orderNumber { lines.append("Order \(order)\(rental.dueBack.map { " · due back \($0)" } ?? "")\(rental.overdue ? " · OVERDUE" : "")") }
        if row.state == .verified, let v = row.verification {
            lines.append("Verified by \(v.by?.name ?? "—")\(v.at.flatMap { EquipmentAuditPresentation.timeLabel($0) }.map { " · \($0)" } ?? "")")
        } else if let by = EquipmentAuditPresentation.verifier(for: row, board: board, fallbackEmployeeId: verifyingAsId) {
            lines.append("Verified By: \(by.name ?? "")\(row.verifierOverride ? " (this unit only)" : "")")
        }
        if let note = row.unresolved?.note { lines.append("Note: \(note)") }

        let sheet = UIAlertController(title: EquipmentAuditPresentation.rowTitle(row), message: lines.joined(separator: "\n"), preferredStyle: .actionSheet)
        for item in items {
            sheet.addAction(UIAlertAction(title: item.title, style: item == .markUnresolved ? .destructive : .default) { [weak self] _ in
                self?.handle(item, row: row)
            })
        }
        sheet.addAction(UIAlertAction(title: items.isEmpty ? "Close" : "Cancel", style: .cancel))
        presentSheet(sheet, from: source ?? table)
    }

    private func handle(_ item: EquipmentAuditMenuItem, row: EquipmentAuditRow) {
        guard let board = board else { return }
        switch item {
        case .verifyAtSystemStore(let storeId, _):
            withVerifier(for: row) { [weak self] person in
                guard let self = self else { return }
                self.run(EquipmentAuditCommands.verify(audit: self.auditUniqueId, row: row, observedStoreId: storeId, performedBy: person.id), unit: row)
            }
        case .foundAtWorkingStore(let mismatch):
            presentMismatch(row, mismatch)
        case .foundAtAnotherStore:
            let options = EquipmentAuditRouting.otherStores(for: row, board: board).map { EquipmentAuditPickerOption(id: $0.id, title: $0.name) }
            let picker = EquipmentAuditPickerViewController(title: "Found at", prompt: "Where is \(row.equipment.equipmentId) physically?",
                                                            options: options, selectedId: nil) { [weak self] option in
                guard let self = self, let current = self.board,
                      let mismatch = EquipmentAuditRouting.mismatch(row, observedStoreId: option.id, board: current) else { return }
                self.presentMismatch(row, mismatch)
            }
            present(picker.inSheet(), animated: true)
        case .confirmWithCustomer, .confirmOffSite:
            let title = item == .confirmWithCustomer ? "Confirm With Customer" : "Confirm Off-Site"
            let alert = UIAlertController(title: title, message: "Kabba shows: \(row.system.label)\n\nConfirm that is where \(row.equipment.equipmentId) is.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Confirm", style: .default) { [weak self] _ in
                self?.withVerifier(for: row) { person in
                    guard let self = self else { return }
                    self.run(EquipmentAuditCommands.verify(audit: self.auditUniqueId, row: row, observedStoreId: nil, performedBy: person.id), unit: row)
                }
            })
            present(alert, animated: true)
        case .rentalFoundInYard(let storeId, let store):
            promptNote(title: "Rental Found at \(store)",
                       message: "Kabba shows \(row.equipment.equipmentId) with a customer (\(row.system.label)). It will be marked Unresolved, seen at \(store), for the office to reconcile — the rental and order are not changed.") { [weak self] note in
                self?.withVerifier(for: row, foundAt: storeId) { person in
                    guard let self = self else { return }
                    self.run(EquipmentAuditCommands.markUnresolved(audit: self.auditUniqueId, row: row, note: note, seenAtStoreId: storeId, performedBy: person.id), unit: row)
                }
            }
        case .moveOffSite:
            withVerifier(for: row) { [weak self] person in self?.openOffSite(row, performedBy: person) }
        case .markUnresolved:
            promptNote(title: "Mark Unresolved",
                       message: "\(row.equipment.equipmentId) moves to the Unresolved queue until someone verifies it. Kabba's location is not changed.") { [weak self] note in
                self?.withVerifier(for: row) { person in
                    guard let self = self else { return }
                    self.run(EquipmentAuditCommands.markUnresolved(audit: self.auditUniqueId, row: row, note: note, seenAtStoreId: nil, performedBy: person.id), unit: row)
                }
            }
        case .changeVerifier:
            var options: [EquipmentAuditPickerOption] = []
            if row.verifierOverride {
                options.append(EquipmentAuditPickerOption(id: nil, title: "Section Auditor (default)", subtitle: "Clear this unit's Verified By"))
            }
            options += board.employees.map { EquipmentAuditPickerOption(id: $0.id, title: $0.name ?? "") }
            let picker = EquipmentAuditPickerViewController(title: "Verified By", prompt: "For \(row.equipment.equipmentId) only",
                                                            options: options, selectedId: row.verifiedByDefault?.id) { [weak self] option in
                guard let self = self else { return }
                self.run(EquipmentAuditCommands.assignVerifier(audit: self.auditUniqueId, row: row, employeeId: option.id), unit: row)
            }
            present(picker.inSheet(), animated: true)
        }
    }

    private func presentMismatch(_ row: EquipmentAuditRow, _ mismatch: EquipmentAuditMismatch) {
        let consequence = mismatch.canMove
            ? (mismatch.isReturnOnSite
                ? "Kabba's Return On-Site closes its Off-Site record (status unchanged) and verifies it at \(mismatch.observedStore)."
                : "Kabba's location is updated to \(mismatch.observedStore) and the unit is verified there. Both locations stay in the history.")
            : "Your account can't move equipment. It will be marked Unresolved, seen at \(mismatch.observedStore), for someone who can."
        let recorded = board.flatMap { EquipmentAuditPresentation.verifier(for: row, board: $0, fallbackEmployeeId: verifyingAsId, foundAtStoreId: mismatch.observedStoreId) }
        let verifiedBy = "Verified By: \(recorded?.name ?? "you'll be asked")"
        let alert = UIAlertController(title: mismatch.title, message: "\(mismatch.message)\n\(verifiedBy)\n\n\(consequence)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: mismatch.confirmTitle, style: .default) { [weak self] _ in
            guard let self = self else { return }
            if mismatch.canMove {
                self.withVerifier(for: row, foundAt: mismatch.observedStoreId) { person in
                    self.run(EquipmentAuditCommands.correctLocation(audit: self.auditUniqueId, row: row, observedStoreId: mismatch.observedStoreId, performedBy: person.id), unit: row)
                }
            } else {
                self.promptNote(title: "Mark Unresolved", message: "Seen at \(mismatch.observedStore). Kabba shows: \(mismatch.systemLocation).") { note in
                    self.withVerifier(for: row, foundAt: mismatch.observedStoreId) { person in
                        self.run(EquipmentAuditCommands.markUnresolved(audit: self.auditUniqueId, row: row, note: note, seenAtStoreId: mismatch.observedStoreId, performedBy: person.id), unit: row)
                    }
                }
            }
        })
        present(alert, animated: true)
    }

    private func openOffSite(_ row: EquipmentAuditRow, performedBy: EquipmentAuditPerson) {
        let form = EquipmentAuditOffSiteViewController(auditUniqueId: auditUniqueId, row: row, performedBy: performedBy, api: api) { [weak self] result, message in
            self?.applied(result, message: message, unit: row)
        }
        form.onClosedWithoutSaving = { [weak self] in self?.load() }
        present(form.inSheet(), animated: true)
    }

    // MARK: Verified By

    /// The row's Verified By: its override or Section Auditor; else this
    /// phone's choice for unassigned sections; else ask once and remember.
    private func withVerifier(for row: EquipmentAuditRow, foundAt storeId: Int? = nil, _ then: @escaping (EquipmentAuditPerson) -> Void) {
        guard let board = board else { return }
        if let person = EquipmentAuditPresentation.verifier(for: row, board: board, fallbackEmployeeId: verifyingAsId, foundAtStoreId: storeId) {
            then(person)
            return
        }
        let section = board.section(row.sectionKey)?.label ?? "This section"
        pickEmployee(title: "Verified By", prompt: "\(section) has no Section Auditor. Who is verifying?", selected: nil) { [weak self] person in
            guard let self = self else { return }
            EquipmentAuditMemory.setVerifyingAs(person.id, audit: self.auditUniqueId)
            self.render()
            then(person)
        }
    }

    private func pickEmployee(title: String, prompt: String, selected: Int?, _ then: @escaping (EquipmentAuditPerson) -> Void) {
        guard let board = board else { return }
        var people = board.employees
        if let me = people.firstIndex(where: { $0.id == board.me.id }) { people.insert(people.remove(at: me), at: 0) }
        let options = people.map { EquipmentAuditPickerOption(id: $0.id, title: $0.name ?? "", subtitle: $0.id == board.me.id ? "You" : nil) }
        let picker = EquipmentAuditPickerViewController(title: title, prompt: prompt, options: options, selectedId: selected) { option in
            guard let id = option.id, let person = board.employee(id) else { return }
            then(person)
        }
        present(picker.inSheet(), animated: true)
    }

    // MARK: Writes

    private func run(_ command: EquipmentAuditCommand, unit: EquipmentAuditRow?) {
        if let uid = unit?.equipment.uniqueId {
            guard !busy.contains(uid) else { return }
            busy.insert(uid)
            render()
        }
        api.perform(command) { [weak self] result in
            guard let self = self else { return }
            if let uid = unit?.equipment.uniqueId { self.busy.remove(uid) }
            switch result {
            case .success(let (outcome, message)):
                self.applied(outcome, message: message, unit: unit)
            case .failure(let failure):
                self.failed(failure)
            }
        }
    }

    /// Success: the row turns at once from Laravel's own answer, then the
    /// board is re-read so a unit that changed section moves there.
    private func applied(_ result: EquipmentAuditActionResult, message: String?, unit: EquipmentAuditRow?) {
        if let fresh = result.unit, let board = board {
            self.board = Self.replacing(fresh, in: board, audit: result.audit)
        }
        lastConfirmation = (message ?? "Saved.", Date())
        render()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmationSeconds + 0.1) { [weak self] in self?.updateFreshness() }
        load()
    }

    private func failed(_ failure: EquipmentAuditFailure) {
        render()
        if failure.isAuditClosed {
            alert(failure.message) { self.navigationController?.popViewController(animated: true) }
            return
        }
        alert(failure.message)
        if failure.isStale || failure.isForbidden || failure.statusCode == 409 {
            load()
        }
    }

    static func replacing(_ fresh: EquipmentAuditRow, in board: EquipmentAuditBoard, audit: EquipmentAuditHeader) -> EquipmentAuditBoard {
        let sections = board.sections.map { section -> EquipmentAuditSection in
            let rows = section.rows.map { $0.equipment.uniqueId == fresh.equipment.uniqueId ? fresh : $0 }
            return EquipmentAuditSection(key: section.key, label: section.label, kind: section.kind, storeId: section.storeId,
                                         auditor: section.auditor, assignedToMe: section.assignedToMe, counts: section.counts,
                                         unresolvedElsewhere: section.unresolvedElsewhere, rows: rows)
        }
        return EquipmentAuditBoard(audit: audit, me: board.me, can: board.can, mySectionKeys: board.mySectionKeys,
                                   sections: sections, stores: board.stores, employees: board.employees, generatedAt: board.generatedAt)
    }

    // MARK: Small helpers

    private func promptNote(title: String, message: String, _ then: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: message + "\n\nA note is required.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "e.g. Unable to establish actual location."
            field.autocapitalizationType = .sentences
            field.accessibilityIdentifier = "equipmentAudit.note"
        }
        var observer: NSObjectProtocol?
        let stopObserving = { if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil } }
        let confirm = UIAlertAction(title: "Mark Unresolved", style: .destructive) { _ in
            stopObserving()
            let note = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !note.isEmpty { then(note) }
        }
        // The server requires the note too; the button simply waits for one.
        confirm.isEnabled = false
        observer = NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: alert.textFields?.first, queue: .main) { _ in
            confirm.isEnabled = !(alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in stopObserving() })
        alert.addAction(confirm)
        present(alert, animated: true)
    }

    private func alert(_ message: String, then: (() -> Void)? = nil) {
        let alert = UIAlertController(title: "Equipment Audit", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in then?() })
        (presentedViewController == nil ? self : presentedViewController!).present(alert, animated: true)
    }

    private func presentSheet(_ sheet: UIAlertController, from source: UIView?) {
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = source ?? view
            popover.sourceRect = (source ?? view).bounds
        }
        present(sheet, animated: true)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}

/// A label with a little breathing room — the "ASSIGNED TO YOU" chip.
private final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
