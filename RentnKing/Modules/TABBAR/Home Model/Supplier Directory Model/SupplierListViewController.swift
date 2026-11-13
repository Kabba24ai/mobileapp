//
//  SupplierListViewController.swift
//  RentnKing
//
//  Supplier Directory — the directory (2026-11-13). Alphabetical Active
//  suppliers; type to search the company, any contact, a phone number, an
//  email, a category or a tag — or switch the search to Parts to find who
//  supplies a part. Inactive suppliers are one menu choice away. Pages load as
//  the list scrolls; pull to refresh. Without a connection the suppliers this
//  phone already opened stay listed (read-only). Add Supplier is always at the
//  bottom for an account that may add one.
//

import UIKit

final class SupplierListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
                                        UISearchBarDelegate, UIGestureRecognizerDelegate {

    typealias Palette = EquipmentAuditRowCell.Palette

    private let api: SupplierDirectoryAPI
    private(set) var suppliers: [SupplierSummary] = []
    private(set) var pagination: SupplierPagination?
    private(set) var capabilities: SupplierCapabilities?
    private(set) var failure: SupplierDirectoryFailure?
    private(set) var isShowingOfflineCopy = false
    private(set) var status: SupplierStatusFilter = .active
    private var searchText = ""
    private var scope: SupplierSearchScope = .supplier
    private var isLoading = false
    /// Answers to an older search are ignored.
    private var generation = 0
    private var searchDebounce: Timer?

    private let searchBar = UISearchBar()
    let table = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let footerSpinner = UIActivityIndicatorView(style: .medium)
    private let offlineBanner = UILabel()
    let addButton = UIButton(type: .system)

    init(api: SupplierDirectoryAPI = .shared) {
        self.api = api
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { searchDebounce?.invalidate() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.page
        view.accessibilityIdentifier = "suppliers.list"
        overrideUserInterfaceStyle = .dark

        searchBar.placeholder = "Company, contact, phone or email"
        searchBar.searchBarStyle = .minimal
        searchBar.scopeButtonTitles = ["Suppliers", "Parts"]
        searchBar.showsScopeBar = true
        searchBar.delegate = self
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.keyboardAppearance = .dark
        searchBar.searchTextField.textColor = Palette.ink
        searchBar.searchTextField.accessibilityIdentifier = "suppliers.search"
        searchBar.sizeToFit()

        offlineBanner.font = .systemFont(ofSize: 13, weight: .semibold)
        offlineBanner.textColor = Palette.amber
        offlineBanner.numberOfLines = 0
        offlineBanner.isHidden = true
        offlineBanner.accessibilityIdentifier = "suppliers.offline"

        table.backgroundColor = Palette.page
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.keyboardDismissMode = .onDrag
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 88
        table.register(UITableViewCell.self, forCellReuseIdentifier: "supplier")
        table.accessibilityIdentifier = "suppliers.table"
        refreshControl.tintColor = Palette.cyan
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        table.refreshControl = refreshControl
        footerSpinner.color = Palette.cyan
        footerSpinner.frame = CGRect(x: 0, y: 0, width: 44, height: 44)

        addButton.setTitle("＋  Add Supplier", for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        addButton.setTitleColor(.black, for: .normal)
        addButton.backgroundColor = Palette.cyan
        addButton.layer.cornerRadius = 12
        addButton.accessibilityIdentifier = "suppliers.add"
        addButton.addTarget(self, action: #selector(addSupplier), for: .touchUpInside)
        addButton.isHidden = true

        let header = UIStackView(arrangedSubviews: [searchBar, offlineBanner])
        header.axis = .vertical
        header.spacing = 4
        header.isLayoutMarginsRelativeArrangement = true
        header.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 4, right: 8)

        [header, table, addButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: header.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),
            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            addButton.heightAnchor.constraint(equalToConstant: 50),
        ])

        messageLabel.font = .systemFont(ofSize: 15, weight: .medium)
        messageLabel.textColor = Palette.subtle
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.accessibilityIdentifier = "suppliers.message"
        spinner.color = Palette.cyan

        load(page: 1)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        tabBarController?.tabBar.isHidden = true
        setNavigationBarFor(controller: self, title: "Suppliers", isTransperent: true, hideShadowImage: true,
                            leftIcon: "icon_back", rightIcon: "", isDetailsScree: false,
                            leftActionHandler: { [weak self] in self?.navigationController?.popViewController(animated: true) })
        installStatusMenu()
    }

    // MARK: Status filter (Active / Inactive / All)

    private func installStatusMenu() {
        let actions = SupplierStatusFilter.allCases.map { filter in
            UIAction(title: filter.title, state: filter == status ? .on : .off) { [weak self] _ in self?.setStatus(filter) }
        }
        let item = UIBarButtonItem(image: UIImage(systemName: status == .active ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"),
                                   menu: UIMenu(title: "Show", children: actions))
        item.tintColor = Palette.cyan
        item.accessibilityIdentifier = "suppliers.statusMenu"
        item.accessibilityLabel = "Show: \(status.title)"
        navigationItem.rightBarButtonItem = item
    }

    func setStatus(_ filter: SupplierStatusFilter) {
        guard filter != status else { return }
        status = filter
        installStatusMenu()
        load(page: 1)
    }

    // MARK: Search

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchDebounce?.invalidate()
        searchDebounce = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.applySearch(searchText)
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchDebounce?.invalidate()
        searchBar.resignFirstResponder()
        applySearch(searchBar.text ?? "")
    }

    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        scope = SupplierSearchScope(rawValue: selectedScope) ?? .supplier
        searchBar.placeholder = scope == .part ? "Part name or part number" : "Company, contact, phone or email"
        load(page: 1)
    }

    func applySearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != searchText else { return }
        searchText = trimmed
        load(page: 1)
    }

    // MARK: Loading

    @objc private func refresh() { load(page: 1) }

    func load(page: Int) {
        if page == 1 {
            generation += 1
        } else if isLoading || pagination?.hasMore != true {
            return
        }
        let request = generation
        isLoading = true
        if page == 1, suppliers.isEmpty { showMessage(nil, spinner: true) }
        if page > 1 { footerSpinner.startAnimating(); table.tableFooterView = footerSpinner }

        api.search(searchText, scope: scope, status: status, page: page) { [weak self] result in
            guard let self = self, request == self.generation else { return }
            self.isLoading = false
            self.refreshControl.endRefreshing()
            self.footerSpinner.stopAnimating()
            self.table.tableFooterView = nil
            switch result {
            case .success(let answer):
                self.suppliers = page == 1 ? answer.suppliers : self.suppliers + answer.suppliers.filter { new in !self.suppliers.contains { $0.uniqueId == new.uniqueId } }
                self.pagination = answer.pagination
                self.capabilities = answer.can
                self.failure = nil
                self.isShowingOfflineCopy = false
            case .failure(let failure):
                self.failure = failure
                if failure.isOffline, page == 1 {
                    // Read-only: the suppliers this phone already opened or listed.
                    self.suppliers = SupplierDirectoryPresentation.filter(self.api.offlineCopy.allSummaries(),
                                                                          search: self.scope == .part ? "" : self.searchText,
                                                                          status: self.status)
                    self.pagination = nil
                    self.isShowingOfflineCopy = true
                } else if failure.isForbidden {
                    self.suppliers = []
                    self.capabilities = .none
                }
            }
            self.render()
        }
    }

    private func render() {
        table.reloadData()
        offlineBanner.text = SupplierDirectoryPresentation.offlineList
        offlineBanner.isHidden = !isShowingOfflineCopy
        // The server decides; before its first answer the button waits (offline: shown, explains on tap).
        addButton.isHidden = !(capabilities?.create ?? isShowingOfflineCopy)

        if let failure = failure, failure.isForbidden {
            showMessage(SupplierDirectoryPresentation.forbidden, spinner: false)
        } else if suppliers.isEmpty, isShowingOfflineCopy {
            showMessage(scope == .part ? "Searching by part needs a connection." : "No suppliers are saved on this phone yet.", spinner: false)
        } else if let failure = failure, suppliers.isEmpty {
            showMessage(failure.message + "\nPull to refresh to try again.", spinner: false)
        } else if suppliers.isEmpty {
            showMessage(SupplierDirectoryPresentation.emptyMessage(search: searchText, scope: scope, status: status), spinner: false)
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
            spinner.topAnchor.constraint(equalTo: container.topAnchor, constant: 60).isActive = true
            spinner.startAnimating()
        }
        if let text = text {
            messageLabel.text = text
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(messageLabel)
            NSLayoutConstraint.activate([
                messageLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 60),
                messageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
                messageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
            ])
        }
        table.backgroundView = container
    }

    // MARK: Add

    @objc func addSupplier() {
        let form = SupplierAddViewController(api: api)
        form.onCreated = { [weak self] _ in self?.load(page: 1) }
        navigationController?.pushViewController(form, animated: true)
    }

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { suppliers.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let supplier = suppliers[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "supplier", for: indexPath)
        cell.backgroundColor = Palette.page
        cell.selectionStyle = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.accessibilityIdentifier = "suppliers.row.\(supplier.uniqueId)"

        let card = UIView()
        card.backgroundColor = UIColor(red: 0x14 / 255.0, green: 0x1C / 255.0, blue: 0x26 / 255.0, alpha: 1)
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = Palette.border.cgColor
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
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = line(supplier.name, 17, .bold, Palette.ink)
        if supplier.isPreferred {
            let row = UIStackView(arrangedSubviews: [title, line("★ Preferred", 12, .semibold, Palette.amber)])
            row.spacing = 8
            row.alignment = .firstBaseline
            title.setContentHuggingPriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(row)
        } else {
            stack.addArrangedSubview(title)
        }
        let subtitle = SupplierDirectoryPresentation.subtitle(supplier)
        if !subtitle.isEmpty { stack.addArrangedSubview(line(subtitle, 13, .medium, Palette.subtle)) }
        let classification = ([supplier.category].compactMap { $0 } + supplier.tags).joined(separator: " · ")
        if !classification.isEmpty { stack.addArrangedSubview(line(classification, 12, .medium, Palette.cyan)) }
        if !supplier.isActive { stack.addArrangedSubview(line(supplier.status, 12, .bold, Palette.amber)) }
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 5),
            card.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -5),
            card.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
        ])
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= suppliers.count - 5, !isShowingOfflineCopy { load(page: (pagination?.currentPage ?? 1) + 1) }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let supplier = suppliers[indexPath.row]
        navigationController?.pushViewController(SupplierDetailViewController(uniqueId: supplier.uniqueId, title: supplier.name, api: api), animated: true)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}
