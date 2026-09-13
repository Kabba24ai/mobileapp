//
//  QueueLineFilter.swift
//  RentnKing
//
//  Queue Line board filters (2026-09-13): Delivery Store (sticky) + Type
//  (session only). The board keeps ONE complete cached feed and applies the
//  filter at render time, so the same scope holds across the three tabs, a
//  refresh, the offline cache and a return from the checklist. Store
//  attribution is the feed's canonical `store` block (delivery_store_id) —
//  the same column the web board's store filter and the API's `?store=` use.
//

import UIKit

// MARK: - Model

/// Type filter over the canonical transport mode. "Store" is In-Store and
/// everything else is a truck delivery — the same predicate the card icon
/// uses, so what the icon shows and what the filter keeps can never disagree.
enum QueueLineTypeFilter: String, CaseIterable, Equatable {
    case all, truck, store

    var title: String {
        switch self {
        case .all: return "All"
        case .truck: return "Truck"
        case .store: return "In Store"
        }
    }

    func matches(transportMode: String?) -> Bool {
        switch self {
        case .all: return true
        case .truck: return !QueueLineTransportPresentation.isInStore(transportMode)
        case .store: return QueueLineTransportPresentation.isInStore(transportMode)
        }
    }
}

struct QueueLineFilter: Equatable {
    /// nil = every store.
    var storeUniqueId: String? = nil
    var type: QueueLineTypeFilter = .all

    var isActive: Bool { storeUniqueId != nil || type != .all }

    /// Store AND Type.
    func includes(storeUniqueId itemStore: String?, transportMode: String?) -> Bool {
        if let wanted = storeUniqueId, wanted != (itemStore ?? "") { return false }
        return type.matches(transportMode: transportMode)
    }

    func apply(_ items: [QueueLineModel]) -> [QueueLineModel] {
        items.filter { includes(storeUniqueId: $0.store?.unique_id, transportMode: $0.delivery?.transport_mode) }
    }

    // Active-filter line under the header.
    static func storeLine(name: String) -> String { "Delivery Store: \(name)" }
    var typeLine: String { "Type: \(type.title)" }

    /// Empty-lane wording while a filter hides everything; nil when no filter is active.
    func emptyMessage(lane: String, storeName: String) -> String? {
        guard isActive else { return nil }
        let scope = [storeUniqueId == nil ? "all stores" : storeName,
                     type == .all ? nil : type.title].compactMap { $0 }.joined(separator: " · ")
        return "Nothing \(lane) for \(scope). Change the filter to see other stores or types."
    }
}

/// A store as the filter sees it: unique id + display name.
struct QueueLineFilterStore: Equatable {
    let uniqueId: String
    let name: String
}

/// The remembered Delivery Store, resolved against whatever store list is known.
enum QueueLineStoreMemory {

    struct Resolution: Equatable {
        let storeUniqueId: String?
        let name: String
        /// True when a KNOWN store list no longer contains the remembered store —
        /// the caller persists All so the stale id is not re-evaluated every visit.
        let forgotten: Bool
    }

    static let allName = "All"

    /// Empty / nil id → All. A known (non-empty) store list without the id → All,
    /// forgotten. An unknown list (offline, nothing cached yet) keeps the id and
    /// shows the name the feed or the memory carries.
    static func resolve(rememberedId: String?, rememberedName: String?,
                        stores: [QueueLineFilterStore], feedStores: [QueueLineFilterStore] = []) -> Resolution {
        guard let id = rememberedId, !id.isEmpty else {
            return Resolution(storeUniqueId: nil, name: allName, forgotten: false)
        }
        if let match = stores.first(where: { $0.uniqueId == id }) {
            return Resolution(storeUniqueId: id, name: match.name, forgotten: false)
        }
        if !stores.isEmpty {
            return Resolution(storeUniqueId: nil, name: allName, forgotten: true)
        }
        let carried = feedStores.first(where: { $0.uniqueId == id })?.name ?? rememberedName ?? ""
        return Resolution(storeUniqueId: id, name: carried.isEmpty ? "Selected store" : carried, forgotten: false)
    }

    // Persistence — the app's UserDefaults convention (UserDefault+Extension.swift).

    static func remembered(in defaults: UserDefaults = .standard) -> (id: String?, name: String?) {
        (defaults.queueLineStoreFilter, defaults.queueLineStoreFilterName)
    }

    /// `nil` id = All, stored explicitly as "" so the choice itself is remembered.
    static func remember(storeUniqueId: String?, name: String, in defaults: UserDefaults = .standard) {
        defaults.queueLineStoreFilter = storeUniqueId ?? ""
        defaults.queueLineStoreFilterName = storeUniqueId == nil ? "" : name
    }
}

// MARK: - Filter sheet

/// Compact modal: Delivery Store (All + every active store) and Type (All /
/// Truck / In Store), Reset + Apply. Same dimmed-card presentation as the
/// Dispatch store popup.
final class QueueLineFilterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    var filter = QueueLineFilter()
    /// Seeded by the board from its cache; refreshed from the stores endpoint on open.
    var stores: [QueueLineFilterStore] = []
    /// (filter, store display name)
    var onApply: ((QueueLineFilter, String) -> Void)?

    private enum Palette {
        static let page   = UIColor.background
        static let ink    = UIColor.primary
        static let cyan   = UIColor.secondary
        static let subtle = UIColor(red: 0x9A / 255.0, green: 0xA4 / 255.0, blue: 0xB2 / 255.0, alpha: 1)
        static let border = UIColor(red: 0x2A / 255.0, green: 0x35 / 255.0, blue: 0x42 / 255.0, alpha: 1)
    }

    private let dimView = UIView()
    private let card = UIView()
    private let table = UITableView()
    private var tableHeight: NSLayoutConstraint?
    private var typeButtons: [UIButton] = []
    private var draft = QueueLineFilter()

    private var rows: [QueueLineFilterStore] {
        [QueueLineFilterStore(uniqueId: "", name: QueueLineStoreMemory.allName)] + stores
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overCurrentContext
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        draft = filter
        buildUI()
        loadStores()
    }

    func showPopup() {
        UIView.animate(withDuration: 0.25) { self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.55) }
    }

    @objc private func dismissPopup() {
        UIView.animate(withDuration: 0.2, animations: { self.dimView.backgroundColor = .clear }) { _ in
            self.dismiss(animated: false)
        }
    }

    // MARK: UI

    private func font(_ name: String, _ size: Double) -> UIFont { SetTheFont(fontName: name, size: size) }

    private func buildUI() {
        view.backgroundColor = .clear

        dimView.frame = view.bounds
        dimView.backgroundColor = .clear
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissPopup)))
        view.addSubview(dimView)

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = Palette.page
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = Palette.cyan.withAlphaComponent(0.35).cgColor
        card.clipsToBounds = true
        view.addSubview(card)

        let title = UILabel()
        title.attributedText = NSAttributedString(string: "Filter Queue Line",
                                                  attributes: [.foregroundColor: Palette.cyan, .font: font(GlobalMainConstants.APP_FONT_Roboto_Bold, 18)])
        title.textAlignment = .center

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = Palette.cyan
        close.accessibilityIdentifier = "queueLineFilter.close"
        close.accessibilityLabel = "Close"
        close.addTarget(self, action: #selector(dismissPopup), for: .touchUpInside)
        close.setContentHuggingPriority(.required, for: .horizontal)
        close.widthAnchor.constraint(equalToConstant: 28).isActive = true

        let header = UIStackView(arrangedSubviews: [UIView(), title, close])
        header.axis = .horizontal
        header.alignment = .center
        header.arrangedSubviews[0].widthAnchor.constraint(equalTo: close.widthAnchor).isActive = true

        // Delivery Store — All + every active store, one selected.
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.separatorColor = Palette.border
        table.separatorInset = .zero
        table.rowHeight = 44
        table.register(UITableViewCell.self, forCellReuseIdentifier: "store")
        table.accessibilityIdentifier = "queueLineFilter.stores"
        let tableH = table.heightAnchor.constraint(equalToConstant: 44)
        tableHeight = tableH
        tableH.isActive = true

        // Type — All / Truck / In Store.
        let types = UIStackView()
        types.axis = .horizontal
        types.distribution = .fillEqually
        types.spacing = 0
        types.layer.cornerRadius = 8
        types.layer.borderWidth = 1.5
        types.layer.borderColor = Palette.cyan.cgColor
        types.clipsToBounds = true
        for option in QueueLineTypeFilter.allCases {
            let b = UIButton(type: .custom)
            b.setTitle(option.title, for: .normal)
            b.titleLabel?.font = font(GlobalMainConstants.APP_FONT_Roboto_Bold, 14)
            b.heightAnchor.constraint(equalToConstant: 38).isActive = true
            b.accessibilityIdentifier = "queueLineFilter.type.\(option.rawValue)"
            b.tag = QueueLineTypeFilter.allCases.firstIndex(of: option) ?? 0
            b.addTarget(self, action: #selector(typeTapped(_:)), for: .touchUpInside)
            typeButtons.append(b)
            types.addArrangedSubview(b)
        }

        let reset = UIButton(type: .system)
        reset.setTitle("Reset", for: .normal)
        reset.titleLabel?.font = font(GlobalMainConstants.APP_FONT_Roboto_Bold, 15)
        reset.setTitleColor(Palette.cyan, for: .normal)
        reset.layer.cornerRadius = 10
        reset.layer.borderWidth = 1.5
        reset.layer.borderColor = Palette.cyan.cgColor
        reset.heightAnchor.constraint(equalToConstant: 46).isActive = true
        reset.accessibilityIdentifier = "queueLineFilter.reset"
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)

        let apply = UIButton(type: .system)
        apply.setTitle("Apply", for: .normal)
        apply.titleLabel?.font = font(GlobalMainConstants.APP_FONT_Roboto_Bold, 15)
        apply.setTitleColor(Palette.page, for: .normal)
        apply.backgroundColor = Palette.cyan
        apply.layer.cornerRadius = 10
        apply.heightAnchor.constraint(equalToConstant: 46).isActive = true
        apply.accessibilityIdentifier = "queueLineFilter.apply"
        apply.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [reset, apply])
        buttons.axis = .horizontal
        buttons.spacing = 12
        buttons.distribution = .fillEqually

        let content = UIStackView(arrangedSubviews: [header, sectionTitle("Delivery Store"), table, sectionTitle("Type"), types, buttons])
        content.axis = .vertical
        content.spacing = 12
        content.setCustomSpacing(18, after: header)
        content.setCustomSpacing(6, after: content.arrangedSubviews[1])
        content.setCustomSpacing(18, after: table)
        content.setCustomSpacing(6, after: content.arrangedSubviews[3])
        content.setCustomSpacing(22, after: types)
        content.isLayoutMarginsRelativeArrangement = true
        content.layoutMargins = UIEdgeInsets(top: 16, left: 18, bottom: 18, right: 18)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])

        refreshType()
        refreshTable()
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let l = UILabel()
        l.attributedText = NSAttributedString(string: text.uppercased(), attributes: [
            .foregroundColor: Palette.subtle, .font: font(GlobalMainConstants.APP_FONT_Roboto_Medium, 12), .kern: 1.0])
        return l
    }

    private func loadStores() {
        getStoreList { [weak self] list in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var seen = Set<String>()
                let fresh: [QueueLineFilterStore] = list.compactMap { s in
                    guard let id = s.unique_id, !id.isEmpty, !seen.contains(id) else { return nil }
                    seen.insert(id)
                    return QueueLineFilterStore(uniqueId: id, name: s.name ?? id)
                }
                if !fresh.isEmpty { self.stores = fresh }
                self.refreshTable()
            }
        }
    }

    private func refreshTable() {
        table.reloadData()
        // Up to five rows visible, then the list scrolls inside the card.
        tableHeight?.constant = CGFloat(min(rows.count, 5)) * 44
        table.isScrollEnabled = rows.count > 5
        UIView.animate(withDuration: 0.15) { self.view.layoutIfNeeded() }
    }

    private func refreshType() {
        for (i, b) in typeButtons.enumerated() {
            let on = QueueLineTypeFilter.allCases[i] == draft.type
            b.backgroundColor = on ? Palette.cyan : .clear
            b.setTitleColor(on ? Palette.page : Palette.cyan, for: .normal)
            b.accessibilityTraits = on ? [.button, .selected] : [.button]
        }
    }

    // MARK: Actions

    @objc private func typeTapped(_ sender: UIButton) {
        draft.type = QueueLineTypeFilter.allCases[sender.tag]
        refreshType()
    }

    @objc private func resetTapped() {
        draft = QueueLineFilter()
        refreshType()
        table.reloadData()
    }

    @objc private func applyTapped() {
        let name = rows.first(where: { $0.uniqueId == (draft.storeUniqueId ?? "") })?.name ?? QueueLineStoreMemory.allName
        let chosen = draft
        onApply?(chosen, name)
        dismissPopup()
    }

    // MARK: Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "store", for: indexPath)
        let store = rows[indexPath.row]
        let selected = (draft.storeUniqueId ?? "") == store.uniqueId
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        cell.textLabel?.text = store.name
        cell.textLabel?.font = font(selected ? GlobalMainConstants.APP_FONT_Roboto_Bold : GlobalMainConstants.APP_FONT_Roboto_Medium, 15)
        cell.textLabel?.textColor = selected ? Palette.cyan : Palette.ink
        cell.accessoryType = selected ? .checkmark : .none
        cell.tintColor = Palette.cyan
        cell.accessibilityIdentifier = "queueLineFilter.store.\(store.uniqueId.isEmpty ? "all" : store.uniqueId)"
        cell.accessibilityLabel = store.name
        cell.accessibilityTraits = selected ? [.button, .selected] : [.button]
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let store = rows[indexPath.row]
        draft.storeUniqueId = store.uniqueId.isEmpty ? nil : store.uniqueId
        tableView.reloadData()
    }
}
