//
//  QueueLineViewController.swift
//  RentnKing
//
//  Queue Line — yard staging board (DESIGN ONLY).
//  Uses the app's dark theme + standard navigation header (like the Schedule screen).
//  No data / networking / logic wired yet — static sample UI only.
//

import UIKit

final class QueueLineViewController: UIViewController, UIGestureRecognizerDelegate {

    // MARK: - Palette (app dark theme)
    private enum Palette {
        static let page     = UIColor.background
        static let laneBG   = UIColor(hex: 0x0E141C)
        static let card     = UIColor(hex: 0x141C26)
        static let border   = UIColor(hex: 0x2A3542)
        static let ink      = UIColor.primary
        static let subtle   = UIColor(hex: 0x9AA4B2)
        static let cyan     = UIColor.secondary
        static let amber    = UIColor.secondaryText
        static let blue     = UIColor(hex: 0x1B6EC2)
        static let green    = UIColor(hex: 0x1FA155)
        static let grayHead = UIColor(hex: 0x334155)
        static let navyBar  = UIColor(hex: 0x22303F)
    }

    private let headerStack = UIStackView()   // fixed header (tabs + day filter) — does NOT scroll
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // Segmented tabs (Pending / Staged / Completed)
    private let tabTitles = ["Pending", "Staged", "Completed"]
    private var tabButtons: [UIButton] = []
    private var laneContents: [UIView] = []
    private var selectedTab = 0

    // Data
    var arrQueueLine: [QueueLineModel] = []

    // Shimmer skeleton shown while the first load is in progress (same Placeholder lib as Dispatch).
    private let queuePlaceholder = Placeholder()
    private var isShowingSkeleton = false

    // Day filter (single-select)
    private let dayTitles = ["Today", "Tomorrow", "All"]
    private var dayChips: [UIButton] = []
    var arrEmployesList : [EmployeesModel] = []
    var arrCategoryList : [CategoryModel] = []
    var arrEquipmentList : [MachineModel] = []

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = Palette.page
        setupScaffold()

        // FIXED HEADER (does not scroll): Pending / Staged / Completed tabs.
        headerStack.addArrangedSubview(buildTabs())

        // Show the first tab (Pending) as selected immediately — before data loads — instead
        // of leaving all three tabs looking unselected during the shimmer.
        selectTab(selectedTab)
    }

    // MARK: - Data
    private func loadQueueLine() {
        // Parse the cached list OFF the main thread, then render on main — but only if it has
        // content, so an empty cache doesn't replace the shimmer skeleton with an empty state
        // before the API returns.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let cached = self.getQueueLineData()
            DispatchQueue.main.async {
                self.arrQueueLine = cached
                if !cached.isEmpty { self.renderLanes() }
            }
        }

        // On API completion (success or failure) render the latest persisted data. This hides
        // the skeleton and shows the genuine empty state only once we've actually heard back.
        callQueueLineAPI { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let fresh = self.getQueueLineData()
                DispatchQueue.main.async {
                    self.arrQueueLine = fresh
                    self.renderLanes()
                }
            }
        }
    }

    /// Splits items into the three lanes and rebuilds the scrolling content.
    private func renderLanes() {
        hideSkeletonLoading()   // stop the shimmer before showing real cards
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        laneContents.removeAll()

        let pendingItems   = arrQueueLine.filter { ($0.status ?? "") == "pending" }
        let stagedItems    = arrQueueLine.filter { ($0.status ?? "") == "staged" }
        let completedItems = arrQueueLine.filter { ($0.status ?? "") == "completed" || $0.completed == true }

        let pending = makeLaneContent(cards(for: pendingItems,
            empty: "Nothing pending — every order has a machine assigned, fueled, and staged."))
        let staged = makeLaneContent(cards(for: stagedItems,
            empty: "Nothing staged yet. Thumbs-up a Pending card once its machine is assigned, fueled, and keyed."))
        let completed = makeLaneContent(cards(for: completedItems,
            empty: "Nothing has left the yard yet today."))

        laneContents = [pending, staged, completed]
        laneContents.forEach { contentStack.addArrangedSubview($0) }
        selectTab(selectedTab)
    }

    // MARK: - Shimmer skeleton (loading placeholder)

    /// Fills the board with shimmering skeleton cards while the first load runs.
    private func showSkeletonLoading() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        queuePlaceholder.remove()

        var boxes: [UIView] = []
        for _ in 0..<6 {
            contentStack.addArrangedSubview(makeSkeletonCard(collecting: &boxes))
        }
        isShowingSkeleton = true

        // Register + animate once the boxes have real frames (the shield is sized from bounds).
        view.layoutIfNeeded()
        queuePlaceholder.register(boxes)
        queuePlaceholder.startAnimation()
    }

    private func hideSkeletonLoading() {
        guard isShowingSkeleton else { return }
        isShowingSkeleton = false
        queuePlaceholder.remove()
    }

    /// One skeleton card that mirrors the real card layout; collects its shimmer boxes.
    private func makeSkeletonCard(collecting boxes: inout [UIView]) -> UIView {
        func box(_ w: CGFloat, _ h: CGFloat) -> UIView {
            let v = UIView()
            v.backgroundColor = Palette.card
            v.layer.cornerRadius = 5
            v.translatesAutoresizingMaskIntoConstraints = false
            v.heightAnchor.constraint(equalToConstant: h).isActive = true
            v.widthAnchor.constraint(equalToConstant: w).isActive = true
            boxes.append(v)
            return v
        }

        // Header: id + customer ........ thumb
        let header = UIStackView(arrangedSubviews: [box(56, 14), box(130, 18), UIView(), box(24, 24)])
        header.axis = .horizontal; header.spacing = 8; header.alignment = .center

        // Machine row: image + (name / code / badge)
        let info = UIStackView(arrangedSubviews: [box(170, 18), box(120, 13), box(90, 22)])
        info.axis = .vertical; info.spacing = 8; info.alignment = .leading
        let machineRow = UIStackView(arrangedSubviews: [box(64, 64), info, UIView()])
        machineRow.axis = .horizontal; machineRow.spacing = 12; machineRow.alignment = .top

        // Footer: store ........ time
        let footer = UIStackView(arrangedSubviews: [box(150, 14), UIView(), box(120, 14)])
        footer.axis = .horizontal; footer.spacing = 8; footer.alignment = .center

        let stack = UIStackView(arrangedSubviews: [header, machineRow, footer])
        stack.axis = .vertical; stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 14, right: 0)

        let line = UIView(); line.backgroundColor = Palette.border
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let card = UIStackView(arrangedSubviews: [stack, line])
        card.axis = .vertical
        return card
    }

    private func cards(for items: [QueueLineModel], empty: String) -> [UIView] {
        guard !items.isEmpty else { return [makeEmptyState(empty)] }
        return items.map { makeCard(for: $0) }
    }

    // MARK: - Thumbs-up → stage / staged-info popup
    @objc private func thumbTapped(_ sender: QueueMenuButton) {
        guard let item = sender.item else { return }
        if item.staged == true {
            let vc = QueueLineStagedInfoViewController()
            vc.item = item
            vc.onChanged = { [weak self] in self?.loadQueueLine() }   // refresh after Return to Pending
            present(vc, animated: true)
        } else {
            let vc = QueueLineStageViewController()
            vc.item = item
            vc.employees = self.arrEmployesList
            vc.categories = self.arrCategoryList
            vc.allEquipment = self.arrEquipmentList
            vc.onChanged = { [weak self] in self?.loadQueueLine() }   // refresh after Mark as Staged
            // After staging succeeds, open the Delivery Checklist for the same order (prepare flow).
            vc.onStaged = { [weak self] staged in self?.openDeliveryChecklist(for: staged) }
            present(vc, animated: true)
        }
    }

    /// Opens the Delivery Checklist for a just-staged order (prepare-before-arrival flow).
    /// Uses the same controller/identifiers Orders uses, so the screen stays independently usable.
    private func openDeliveryChecklist(for item: QueueLineModel) {
        let storyBoard = UIStoryboard(name: GlobalMainConstants.ORDER_MODEL, bundle: nil)
        guard let vc = storyBoard.instantiateViewController(withIdentifier: "CheckListViewController") as? CheckListViewController else { return }
        vc.isQueueLine = true
        vc.isDeliveryType = true
        vc.selectIndex = 0
        vc.strOrderUniqueId = item.order_unique_id ?? ""
        vc.strOrderID = "\(item.order_number ?? "")"
        self.navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - Kebab action
    // Only "Change Equipment" is available for now, so tapping the kebab opens that popup
    // directly instead of a menu of not-yet-supported options.
    @objc private func menuTapped(_ sender: QueueMenuButton) {
        guard let item = sender.item else { return }
        self.openChangeEquipment(for: item)
    }

    /// Opens the "Confirm / Update Equipment" popup (design only).
    private func openChangeEquipment(for item: QueueLineModel) {
        let vc = QueueLineChangeEquipmentViewController()
        vc.item = item
        vc.employees = self.arrEmployesList
        vc.categories = self.arrCategoryList
        vc.allEquipment = self.arrEquipmentList
        vc.onChanged = { [weak self] in self?.loadQueueLine() }
        present(vc, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppUtility.PortraitMode()
        self.view.backgroundColor = Palette.page
        setNeedsStatusBarAppearanceUpdate()

        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true

        // App-standard header (back + filter/search), like the Schedule screen.
        setNavigationBarForButtons(controller: self, title: "Queue Line", isTransperent: true,
                                   hideShadowImage: true, leftIcon: "icon_back",
                                   rightIcon: [], isFilter: false) {
            self.navigationController?.popViewController(animated: true)
        } rightActionHandler: { _, _ in
            // design only
        }

        // Show the shimmer skeleton NOW (cheap to build) so it's visible instantly with the
        // transition — the heavy data parsing still happens off-main in viewDidAppear.
        if arrQueueLine.isEmpty {
            showSkeletonLoading()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Heavy cache parsing runs AFTER the push animation so navigation feels instant.
        loadQueueLine()             // parses cache off-main, then renders + refreshes from API
        loadSupportingListsOnce()   // employees / categories / equipment (for the Reassign popup)
    }

    /// Loads the employee / category / equipment lists once per visit, OFF the main thread
    /// (the equipment cache in particular maps many heavy MachineModel objects).
    private var didLoadSupportingLists = false
    private func loadSupportingListsOnce() {
        guard !didLoadSupportingLists else { return }
        didLoadSupportingLists = true
        DispatchQueue.global(qos: .utility).async {
            getEmployeeList  { arr in DispatchQueue.main.async { self.arrEmployesList  = arr } }
            getCategoryList  { arr in DispatchQueue.main.async { self.arrCategoryList  = arr } }
            getEquipmentList { arr in DispatchQueue.main.async { self.arrEquipmentList = arr } }
        }
    }

    // MARK: - Scaffold
    private func setupScaffold() {
        // Fixed header
        headerStack.axis = .vertical
        headerStack.spacing = 12
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerStack)

        // Scrolling content (cards only)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -14),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    // MARK: - Banner
    private func makeBanner(_ text: String) -> UIView {
        let container = UIView()
        container.backgroundColor = Palette.green.withAlphaComponent(0.14)
        container.layer.cornerRadius = 10
        container.layer.borderWidth = 1
        container.layer.borderColor = Palette.green.withAlphaComponent(0.55).cgColor

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = UIColor(hex: 0x59D08A)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
        ])
        return container
    }

    // MARK: - Filter bar (horizontally scrollable, cyan chips)
    private func makeFilterBar() -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(makeSegment(["All", "Today Only"], selected: 0))
        row.addArrangedSubview(makeDropdown("All Stores"))
        row.addArrangedSubview(makeSegment(["All", "Truck", "In-Store"], selected: 0))
        row.addArrangedSubview(makeSegment(["All", "Paid", "Pending"], selected: 0))
        row.addArrangedSubview(makeDropdown("All Categories"))
        row.addArrangedSubview(makeDropdown("All Products"))
        row.addArrangedSubview(makeTextChip("Wall Board View"))

        scroll.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scroll.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            row.heightAnchor.constraint(equalTo: scroll.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 34),
        ])
        return scroll
    }

    /// Segmented pill group — selected = cyan fill (black text), others = cyan outline.
    private func makeSegment(_ options: [String], selected: Int) -> UIView {
        let container = UIStackView()
        container.axis = .horizontal
        container.spacing = 0
        container.layer.cornerRadius = 8
        container.layer.borderWidth = 1
        container.layer.borderColor = Palette.cyan.cgColor
        container.clipsToBounds = true

        for (i, opt) in options.enumerated() {
            let label = PaddedLabel()
            label.text = opt
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.insets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            if i == selected {
                label.backgroundColor = Palette.cyan
                label.textColor = Palette.page
            } else {
                label.backgroundColor = .clear
                label.textColor = Palette.cyan
            }
            container.addArrangedSubview(label)
        }
        return container
    }

    /// Dropdown-style chip (cyan outline + chevron).
    private func makeDropdown(_ title: String) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 10)
        stack.layer.cornerRadius = 8
        stack.layer.borderWidth = 1
        stack.layer.borderColor = Palette.cyan.cgColor

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = Palette.ink

        let chevron = UIImageView(image: UIImage(systemName: "chevron.down"))
        chevron.tintColor = Palette.cyan
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(chevron)
        return stack
    }

    private func makeTextChip(_ title: String) -> UIView {
        let label = PaddedLabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = Palette.cyan
        label.insets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        return label
    }

    // MARK: - Tabs (Pending / Staged / Completed)
    private func buildTabs() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 10
        stack.distribution = .fillEqually

        for (i, title) in tabTitles.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
            button.layer.cornerRadius = 10
            button.layer.borderWidth = 1.5
            button.layer.borderColor = Palette.cyan.cgColor
            button.tag = i
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabButtons.append(button)
            stack.addArrangedSubview(button)
        }
        return stack
    }

    @objc private func tabTapped(_ sender: UIButton) {
        selectTab(sender.tag)
        loadQueueLine()   // refresh the list from the API on each tab tap
    }

    private func selectTab(_ index: Int) {
        selectedTab = index
        for (i, button) in tabButtons.enumerated() {
            let on = (i == index)
            button.backgroundColor = on ? Palette.cyan : .clear
            button.setTitleColor(on ? Palette.page : Palette.cyan, for: .normal)
        }
        for (i, content) in laneContents.enumerated() {
            content.isHidden = (i != index)
        }
    }

    // MARK: - Day filter row (truck/store checkboxes + Today / Tomorrow / All)
    private func makeDayFilterRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(CheckToggleView(iconName: "icon_delivery_pending", tint: Palette.cyan)) // check + truck
        row.addArrangedSubview(CheckToggleView(iconName: "icon_store", tint: Palette.cyan))            // check + store

        for (i, title) in dayTitles.enumerated() {
            let chip = makeDayChip(title, selected: i == 0)
            chip.tag = i
            chip.addTarget(self, action: #selector(dayTapped(_:)), for: .touchUpInside)
            dayChips.append(chip)
            row.addArrangedSubview(chip)
        }

        // Horizontal scroll so it never clips on narrow screens.
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scroll.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            row.heightAnchor.constraint(equalTo: scroll.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 40),
        ])
        return scroll
    }

    /// Pill chip for the day filter — Today selected (cyan fill), others cyan outline.
    private func makeDayChip(_ title: String, selected: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)
        button.layer.cornerRadius = 16
        button.clipsToBounds = true
        button.layer.borderWidth = 1.5
        button.layer.borderColor = Palette.cyan.cgColor
        applyDayStyle(button, selected: selected)
        return button
    }

    private func applyDayStyle(_ button: UIButton, selected: Bool) {
        button.backgroundColor = selected ? Palette.cyan : .clear
        button.setTitleColor(selected ? Palette.page : Palette.cyan, for: .normal)
    }

    @objc private func dayTapped(_ sender: UIButton) {
        for (i, chip) in dayChips.enumerated() {
            applyDayStyle(chip, selected: i == sender.tag)
        }
    }

    // MARK: - Lane content (shown for the selected tab)
    private func makeLaneContent(_ body: [UIView]) -> UIView {
        // Clean container — no border/background/hint (blends into the page).
        let card = UIView()
        card.backgroundColor = .clear

        let bodyStack = UIStackView(arrangedSubviews: body)
        bodyStack.axis = .vertical
        bodyStack.spacing = 12
        bodyStack.isLayoutMarginsRelativeArrangement = true
        bodyStack.layoutMargins = UIEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(bodyStack)
        NSLayoutConstraint.activate([
            bodyStack.topAnchor.constraint(equalTo: card.topAnchor),
            bodyStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            bodyStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            bodyStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
        return card
    }

    private func pillCount(_ text: String, color: UIColor) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = color
        label.layer.cornerRadius = 11
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 24).isActive = true
        label.heightAnchor.constraint(equalToConstant: 22).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    // MARK: - Card (data-driven)
    private func makeCard(for item: QueueLineModel) -> UIView {
        let bold = GlobalMainConstants.APP_FONT_Roboto_Bold
        let medium = GlobalMainConstants.APP_FONT_Roboto_Medium
        let regular = GlobalMainConstants.APP_FONT_Roboto_Regular

        // No border/box — flat like the Order List cell, with a single separator line at the end.
        let card = UIView()
        card.backgroundColor = .clear

        let stack = UIStackView()   // padded content
        stack.axis = .vertical
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 14, right: 0)

        let bottomLine = UIView()
        bottomLine.backgroundColor = Palette.border
        bottomLine.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let outer = UIStackView(arrangedSubviews: [stack, bottomLine])
        outer.axis = .vertical
        outer.spacing = 0
        outer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: card.topAnchor),
            outer.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            outer.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])

        // 1) Header: order#  customer .......... 👍 count  (styled like the Order List page)
        let idLabel = UILabel()
        idLabel.attributedText = attr(item.order_number ?? "", Palette.ink, rFont(regular, 14))
        idLabel.setContentHuggingPriority(.required, for: .horizontal)

        let customer = UILabel()
        customer.attributedText = attr(item.customer_name ?? "", Palette.ink, rFont(bold, 16))
        customer.setContentHuggingPriority(.required, for: .horizontal)

        let thumb = QueueMenuButton(type: .system)
        thumb.item = item
        thumb.setImage(UIImage(systemName: "hand.thumbsup.fill"), for: .normal)
        thumb.tintColor = Palette.cyan
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.widthAnchor.constraint(equalToConstant: 24).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: 24).isActive = true
        thumb.setContentHuggingPriority(.required, for: .horizontal)
        thumb.addTarget(self, action: #selector(thumbTapped(_:)), for: .touchUpInside)

        var headerViews: [UIView] = [idLabel, customer, UIView()]
        if (item.urgency ?? "").lowercased() == "rush" {
            headerViews.append(makeBadge("RUSH", bg: .redText, text: .white, bordered: false))
        }

        // Completed cards: no thumbs-up. Show a FAST TRACK tag when flagged.
        let isCompleted = (item.status ?? "") == "completed" || item.completed == true
        if isCompleted {
            if item.is_fast_track == true {
                headerViews.append(makeBadge("FAST TRACK", bg: Palette.amber, text: Palette.page, bordered: false))
            }
        } else {
            headerViews.append(thumb)

            // Kebab menu (Change Equipment, …)
            let kebab = QueueMenuButton(type: .system)
            kebab.item = item
            kebab.setImage(UIImage(systemName: "ellipsis"), for: .normal)
            kebab.tintColor = Palette.subtle
            kebab.translatesAutoresizingMaskIntoConstraints = false
            kebab.widthAnchor.constraint(equalToConstant: 22).isActive = true
            kebab.heightAnchor.constraint(equalToConstant: 24).isActive = true
            kebab.setContentHuggingPriority(.required, for: .horizontal)
            kebab.addTarget(self, action: #selector(menuTapped(_:)), for: .touchUpInside)
            headerViews.append(kebab)
        }

        let header = UIStackView(arrangedSubviews: headerViews)
        header.axis = .horizontal
        header.spacing = 8
        header.alignment = .center
        stack.addArrangedSubview(header)


        // 2) Machine row: product image + name / equipment code / status badge
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .white
        imageView.layer.cornerRadius = 8
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = Palette.border.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        if let url = item.product?.image_url, !url.isEmpty {
            imageView.setImage(strImg: url)
        } else {
            imageView.image = UIImage(systemName: "photo")
            imageView.tintColor = Palette.subtle.withAlphaComponent(0.6)
            imageView.contentMode = .center
        }

        let name = UILabel()
        name.numberOfLines = 0
        name.attributedText = attr(item.product?.name ?? "", Palette.ink, rFont(bold, 18))

        let eqName = item.equipment?.name ?? ""
        let eqId = item.equipment?.display_id.map { "#\($0)" } ?? ""
        let codeText = [eqName, eqId].filter { !$0.isEmpty }.joined(separator: "   ·   ")
        let code = UILabel()
        code.numberOfLines = 0
        code.attributedText = attr(codeText, UIColor(hex: 0xC7CED8), rFont(medium, 13))

        var machineViews: [UIView] = [name, code]
        for badge in statusBadges(for: item) { machineViews.append(leftAlign(badge)) }
        let info = UIStackView(arrangedSubviews: machineViews)
        info.axis = .vertical
        info.spacing = 6
        info.alignment = .fill

        let machineRow = UIStackView(arrangedSubviews: [imageView, info])
        machineRow.axis = .horizontal
        machineRow.spacing = 12
        machineRow.alignment = .top
        stack.addArrangedSubview(machineRow)


        // 3) Store (left) + date/time (right) on one line — store uses the app store icon.
        let storeName = item.store?.name ?? ""
        let deliveryLabel = (item.delivery?.transport_mode == "Store") ? "In Store : " : "Delivery : "
        // On Completed cards the Delivery / In Store icon + label match the time row (cyan icon, ink text).
        let storeLabelColor = isCompleted ? Palette.ink : Palette.cyan
        let storeIconTint = isCompleted ? Palette.cyan : Palette.amber
        let storeLeft = iconRowAsset("icon_store", storeIconTint, labelValue(deliveryLabel, storeName, labelColor: storeLabelColor))
        let timeText = formatDeliveryDateTime(date: item.delivery?.date, time: item.delivery?.time)
        let timeRight = iconRow("clock", Palette.cyan, attr(timeText, Palette.ink, rFont(medium, 13)))
        let infoLine = UIStackView(arrangedSubviews: [storeLeft, UIView(), timeRight])
        infoLine.axis = .horizontal
        infoLine.spacing = 8
        infoLine.alignment = .center
        stack.addArrangedSubview(infoLine)

        return card
    }

    /// Equipment status badges: tappable amber "Maint. Hold" or green-filled "Available",
    /// plus a red "Wrong Location — at <place>" when the machine is at the wrong store.
    private func statusBadges(for item: QueueLineModel) -> [UIView] {
        guard let eq = item.equipment else { return [] }
        var badges: [UIView] = []

        // Completed cards show Maint. Hold as a plain (non-tappable) badge.
        let isCompleted = (item.status ?? "") == "completed" || item.completed == true

        if eq.status == "maintenance", let label = eq.status_label, !label.isEmpty {
            if isCompleted {
                badges.append(makeBadge(label, bg: .clear, text: Palette.amber, bordered: true))   // non-tappable
            } else {
                badges.append(maintHoldBadge(text: label, item: item))                             // tappable
            }
        } else if let ready = eq.rental_ready, !ready.isEmpty {
            badges.append(makeBadge("Available", bg: Palette.green, text: .white, bordered: false)) // filled green
        }

        if eq.wrong_location == true {
            let loc = eq.location ?? ""
            let text = loc.isEmpty ? "Wrong Location" : "Wrong Location — at \(loc)"
            badges.append(makeBadge(text, bg: .clear, text: .redText, bordered: true))
        }
        return badges
    }

    /// Tappable "Maint. Hold" badge (amber outline). Calls `maintHoldTapped`.
    private func maintHoldBadge(text: String, item: QueueLineModel) -> UIView {
        let button = QueueMenuButton(type: .system)
        button.item = item
        button.setTitle(text, for: .normal)
        button.setTitleColor(Palette.amber, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        button.layer.cornerRadius = 6
        button.layer.borderWidth = 1
        button.layer.borderColor = Palette.amber.withAlphaComponent(0.6).cgColor
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.addTarget(self, action: #selector(maintHoldTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func maintHoldTapped(_ sender: QueueMenuButton) {
        guard let item = sender.item else { return }
        // TODO: handle Maintenance Hold tap for `item` here.
        _ = item
        
        
        
        //MOVE FORGOT SCREEN
        let storyBoard: UIStoryboard = UIStoryboard(name: GlobalMainConstants.EQUIPMENT_MODEL, bundle: nil)
        if let newViewController = storyBoard.instantiateViewController(withIdentifier: "MachineDetailsViewController") as? MachineDetailsViewController{
            newViewController.isQueueLine = true
            newViewController.objRentalReadyData = item.equipment_collection
            newViewController.strID = item.equipment_collection?.unique_id ?? ""
            newViewController.strTitleName = "\(item.equipment_collection?.equipment_name ?? "") (\(item.equipment_collection?.equipment_id ?? ""))"
            newViewController.arrRentalReady = item.equipment_collection?.arrAnswerRentalCheckList ?? []
            self.navigationController?.pushViewController(newViewController, animated: true)
        }
    }

    /// "2026-07-07" + "09:00:00" → "Tue Jul 7  ·  9:00 AM".
    private func formatDeliveryDateTime(date: String?, time: String?) -> String {
        guard let date = date, !date.isEmpty else { return "" }
        let hasTime = (time != nil && !(time ?? "").isEmpty)
        let inFmt = DateFormatter()
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.dateFormat = hasTime ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd"
        let combined = hasTime ? "\(date) \(time ?? "")" : date
        guard let parsed = inFmt.date(from: combined) else { return combined }
        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "en_US_POSIX")
        outFmt.dateFormat = hasTime ? "EEE MMM d  ·  h:mm a" : "EEE MMM d"
        return outFmt.string(from: parsed)
    }

    /// Same as iconRow but with an asset image (e.g. the app's icon_store), template-tinted.
    private func iconRowAsset(_ asset: String, _ tint: UIColor, _ text: NSAttributedString) -> UIView {
        let iv = UIImageView(image: UIImage(named: asset)?.withRenderingMode(.alwaysTemplate))
        iv.tintColor = tint
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 16).isActive = true
        iv.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.attributedText = text
        label.numberOfLines = 1

        let row = UIStackView(arrangedSubviews: [iv, label])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        return row
    }

    // MARK: - Card helpers
    private func rFont(_ name: String, _ size: Double) -> UIFont {
        SetTheFont(fontName: name, size: size)
    }

    private func attr(_ text: String, _ color: UIColor, _ font: UIFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.foregroundColor: color, .font: font])
    }

    private func labelValue(_ label: String, _ value: String, labelColor: UIColor = Palette.cyan) -> NSAttributedString {
        let f = rFont(GlobalMainConstants.APP_FONT_Roboto_Medium, 13)
        let s = NSMutableAttributedString(string: label, attributes: [.foregroundColor: labelColor, .font: f])
        s.append(NSAttributedString(string: value, attributes: [.foregroundColor: Palette.ink, .font: f]))
        return s
    }

    private func makeDivider() -> UIView {
        let v = UIView()
        v.backgroundColor = Palette.border
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func iconRow(_ symbol: String, _ tint: UIColor, _ text: NSAttributedString) -> UIView {
        let iv = UIImageView(image: UIImage(systemName: symbol))
        iv.tintColor = tint
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 16).isActive = true
        iv.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.attributedText = text
        label.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [iv, label])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        return row
    }

    // MARK: - Empty state
    private func makeEmptyState(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = Palette.subtle
        label.numberOfLines = 0
        label.textAlignment = .center
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])
        return container
    }

    // MARK: - Small builders
    private func makeBadge(_ text: String, bg: UIColor, text textColor: UIColor, bordered: Bool) -> UIView {
        let label = PaddedLabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = textColor
        label.backgroundColor = bg
        label.insets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        if bordered {
            label.layer.borderWidth = 1
            label.layer.borderColor = textColor.withAlphaComponent(0.6).cgColor
        }
        return label
    }

    private func makeSquareBadge(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 22).isActive = true
        label.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return label
    }

    private func makeCountBadge(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        label.layer.cornerRadius = 11
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 22).isActive = true
        label.heightAnchor.constraint(equalToConstant: 22).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private func leftAlign(_ view: UIView) -> UIView {
        let row = UIStackView(arrangedSubviews: [view, UIView()])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    private func attributed(_ a: String, _ ac: UIColor, _ aw: UIFont.Weight,
                            _ b: String, _ bc: UIColor, _ bw: UIFont.Weight, size: CGFloat) -> NSAttributedString {
        let s = NSMutableAttributedString(string: a, attributes: [
            .foregroundColor: ac, .font: UIFont.systemFont(ofSize: size, weight: aw)])
        s.append(NSAttributedString(string: b, attributes: [
            .foregroundColor: bc, .font: UIFont.systemFont(ofSize: size, weight: bw)]))
        return s
    }
}

// MARK: - Helpers

/// Kebab button that remembers which item it belongs to.
private final class QueueMenuButton: UIButton {
    var item: QueueLineModel?
}

/// A tappable checkbox (icon_Check / icon_unCheck) next to a truck/store icon.
private final class CheckToggleView: UIView {
    private let checkView = UIImageView()
    private let tint: UIColor
    var isChecked = true { didSet { refresh() } }

    init(iconName: String, tint: UIColor) {
        self.tint = tint
        super.init(frame: .zero)

        checkView.contentMode = .scaleAspectFit
        checkView.translatesAutoresizingMaskIntoConstraints = false
        checkView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        checkView.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let icon = UIImageView(image: UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = tint
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let stack = UIStackView(arrangedSubviews: [checkView, icon])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func toggle() { isChecked.toggle() }

    private func refresh() {
        checkView.image = UIImage(named: isChecked ? "icon_Check" : "icon_unCheck")?
            .withRenderingMode(.alwaysTemplate)
        checkView.tintColor = tint
    }
}

/// Label with configurable content insets (used for chips / bars / badges).
private final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets.zero
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right,
                      height: s.height + insets.top + insets.bottom)
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: 1.0)
    }
}
