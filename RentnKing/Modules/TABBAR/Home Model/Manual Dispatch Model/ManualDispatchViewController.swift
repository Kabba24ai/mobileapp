//
//  ManualDispatchViewController.swift
//  RentnKing
//
//  Manual Dispatch — order-free driver tasks board. SIBLING module to Queue
//  Line: fully programmatic UIKit (no storyboard scene / xib / prototype cell),
//  launched from the Home tile via ManualDispatchViewController(). Consumes the
//  admin/v1 /dispatch/manual endpoints; auth rides the shared Bearer token.
//

import UIKit

/// A UIButton that carries the manual task it acts on (mirrors QueueMenuButton).
final class ManualActionButton: UIButton {
    var item: ManualDispatchModel?
}

/// A card container that carries its manual task, so a tap gesture can open detail.
final class ManualCardView: UIView {
    var item: ManualDispatchModel?
}

final class ManualDispatchViewController: UIViewController, UIGestureRecognizerDelegate {

    // MARK: - Palette (app dark theme — same tokens Queue Line uses)
    private enum Palette {
        static let page   = UIColor.background
        static let card   = UIColor(hex: 0x141C26)
        static let border = UIColor(hex: 0x2A3542)
        static let ink    = UIColor.primary
        static let subtle = UIColor(hex: 0x9AA4B2)
        static let indigo = UIColor(hex: 0x6366F1)   // MANUAL accent
        static let blue   = UIColor(hex: 0x1B6EC2)
        static let green  = UIColor(hex: 0x1FA155)
        static let amber  = UIColor.secondaryText
        static let red    = UIColor(hex: 0xDC2626)
    }

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // Data
    var arrManualDispatch: [ManualDispatchModel] = []
    var dateFilter = "All"   // Today | Tomorrow | All

    // Shimmer skeleton (same Placeholder lib as Queue Line / Dispatch)
    private let placeholder = Placeholder()
    private var isShowingSkeleton = false

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = Palette.page
        setupScaffold()
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

        setNavigationBarForButtons(controller: self, title: "Manual Dispatch", isTransperent: true,
                                   hideShadowImage: true, leftIcon: "icon_back",
                                   rightIcon: [], isFilter: false) {
            self.navigationController?.popViewController(animated: true)
        } rightActionHandler: { _, _ in
            // no right action
        }

        if arrManualDispatch.isEmpty {
            showSkeletonLoading()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadManualDispatch()
    }

    // MARK: - Scaffold
    private func setupScaffold() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -14),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    // MARK: - Data
    private func loadManualDispatch() {
        // Parse cache off-main; render only if non-empty so the skeleton stays
        // until the API returns (matches Queue Line).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let cached = self.getManualDispatchData()
            DispatchQueue.main.async {
                self.arrManualDispatch = cached
                if !cached.isEmpty { self.renderList() }
            }
        }

        callManualDispatchListAPI { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let fresh = self.getManualDispatchData()
                DispatchQueue.main.async {
                    self.arrManualDispatch = fresh
                    self.renderList()
                }
            }
        }
    }

    /// Deterministic ordering: priority ascending (nulls last), then date.
    private func sortedItems() -> [ManualDispatchModel] {
        return arrManualDispatch.sorted { a, b in
            let pa = a.priority ?? Int.max
            let pb = b.priority ?? Int.max
            if pa != pb { return pa < pb }
            return (a.date ?? "") < (b.date ?? "")
        }
    }

    private func renderList() {
        hideSkeletonLoading()
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let items = sortedItems()
        guard !items.isEmpty else {
            contentStack.addArrangedSubview(makeEmptyState("No manual dispatch tasks assigned to you."))
            return
        }
        for (idx, item) in items.enumerated() {
            contentStack.addArrangedSubview(makeCard(for: item, index: idx))
        }
        // Keep the rendered order so button/gesture tags resolve correctly.
        arrManualDispatch = items
    }

    // MARK: - Card
    private func makeCard(for item: ManualDispatchModel, index: Int) -> UIView {
        let card = ManualCardView()
        card.item = item
        card.backgroundColor = Palette.card
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = Palette.border.cgColor

        // Row 1: MANUAL badge + type ......... status pill
        let badge = pill(text: "MANUAL", bg: Palette.indigo.withAlphaComponent(0.18), fg: Palette.indigo)
        let type = UILabel()
        type.text = (item.type ?? "").uppercased()
        type.font = .systemFont(ofSize: 12, weight: .bold)
        type.textColor = Palette.subtle
        let status = pill(text: item.status ?? "", bg: statusColor(item.status).withAlphaComponent(0.18), fg: statusColor(item.status))
        let header = UIStackView(arrangedSubviews: [badge, type, UIView(), status])
        header.axis = .horizontal; header.spacing = 8; header.alignment = .center

        // Row 2: description
        let desc = UILabel()
        desc.text = item.description ?? item.type
        desc.font = .systemFont(ofSize: 16, weight: .semibold)
        desc.textColor = Palette.ink
        desc.numberOfLines = 0

        // Row 3: location
        let loc = UILabel()
        loc.text = [item.location_name, item.locationLine].compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: " · ")
        loc.font = .systemFont(ofSize: 13)
        loc.textColor = Palette.subtle
        loc.numberOfLines = 0

        // Row 4: date · time · priority
        let meta = UILabel()
        let when = [item.date, item.time].compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: " · ")
        let pr = item.priority.map { "Priority \($0)" } ?? "Priority: Normal"
        meta.text = [when, pr].filter { !$0.isEmpty }.joined(separator: "   •   ")
        meta.font = .systemFont(ofSize: 12)
        meta.textColor = Palette.amber

        let info = UIStackView(arrangedSubviews: [header, desc, loc, meta])
        info.axis = .vertical; info.spacing = 6

        // Row 5: actions (advance + cancel), only for non-terminal tasks
        let actions = UIStackView()
        actions.axis = .horizontal; actions.spacing = 10; actions.alignment = .center
        if !ManualDispatchStatus.isTerminal(item.status) {
            if let next = ManualDispatchStatus.next(after: item.status) {
                let advance = actionButton(title: next, bg: Palette.blue, item: item)
                advance.tag = index
                advance.addTarget(self, action: #selector(advanceTapped(_:)), for: .touchUpInside)
                actions.addArrangedSubview(advance)
            }
            actions.addArrangedSubview(UIView())
            let cancel = actionButton(title: "Cancel", bg: .clear, fg: Palette.red, bordered: true, item: item)
            cancel.tag = index
            cancel.addTarget(self, action: #selector(cancelTapped(_:)), for: .touchUpInside)
            actions.addArrangedSubview(cancel)
        }

        let stack = UIStackView(arrangedSubviews: actions.arrangedSubviews.isEmpty ? [info] : [info, actions])
        stack.axis = .vertical; stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        // Tap anywhere on the card (except the action buttons, which consume the
        // touch) opens the detail screen.
        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped(_:)))
        card.addGestureRecognizer(tap)
        return card
    }

    // MARK: - Actions
    @objc private func cardTapped(_ gesture: UITapGestureRecognizer) {
        guard let item = (gesture.view as? ManualCardView)?.item else { return }
        let vc = ManualDispatchDetailViewController()
        vc.item = item
        vc.onChanged = { [weak self] in self?.loadManualDispatch() }
        self.navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func advanceTapped(_ sender: ManualActionButton) {
        guard let item = sender.item, let next = ManualDispatchStatus.next(after: item.status),
              let uid = item.unique_id else { return }
        confirm(message: "Mark this task as \(next)?") { [weak self] in
            updateManualDispatchStatus(uniqueId: uid, status: next) { ok in
                if ok { self?.loadManualDispatch() }
            }
        }
    }

    @objc private func cancelTapped(_ sender: ManualActionButton) {
        guard let item = sender.item, let uid = item.unique_id else { return }
        confirm(message: "Cancel this manual dispatch task?") { [weak self] in
            updateManualDispatchStatus(uniqueId: uid, status: ManualDispatchStatus.cancelled) { ok in
                if ok { self?.loadManualDispatch() }
            }
        }
    }

    private func confirm(message: String, onYes: @escaping () -> Void) {
        let alert = UIAlertController(title: Application.appName, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: str.yes, style: .default) { _ in onYes() })
        alert.addAction(UIAlertAction(title: str.no, style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - UI helpers
    private func pill(text: String, bg: UIColor, fg: UIColor) -> UIView {
        let label = PaddingLabelManual()
        label.text = text
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = fg
        label.backgroundColor = bg
        label.layer.cornerRadius = 5
        label.layer.masksToBounds = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private func actionButton(title: String, bg: UIColor, fg: UIColor = .white, bordered: Bool = false, item: ManualDispatchModel) -> ManualActionButton {
        let b = ManualActionButton()
        b.item = item
        b.setTitle(title, for: .normal)
        b.setTitleColor(fg, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        b.backgroundColor = bg
        b.layer.cornerRadius = 8
        if bordered {
            b.layer.borderWidth = 1
            b.layer.borderColor = fg.withAlphaComponent(0.5).cgColor
        }
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        return b
    }

    private func statusColor(_ status: String?) -> UIColor {
        switch status {
        case ManualDispatchStatus.assigned:  return Palette.blue
        case ManualDispatchStatus.onMyWay:   return Palette.indigo
        case ManualDispatchStatus.arrived:   return UIColor(hex: 0x8B5CF6)
        case ManualDispatchStatus.completed: return Palette.green
        case ManualDispatchStatus.cancelled: return Palette.red
        default:                             return Palette.subtle
        }
    }

    private func makeEmptyState(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14)
        label.textColor = Palette.subtle
        label.textAlignment = .center
        label.numberOfLines = 0
        let wrap = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 60),
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -24),
            label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -60),
        ])
        return wrap
    }

    // MARK: - Skeleton
    private func showSkeletonLoading() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        placeholder.remove()
        var boxes: [UIView] = []
        for _ in 0..<6 { contentStack.addArrangedSubview(makeSkeletonCard(collecting: &boxes)) }
        isShowingSkeleton = true
        view.layoutIfNeeded()
        placeholder.register(boxes)
        placeholder.startAnimation()
    }

    private func hideSkeletonLoading() {
        guard isShowingSkeleton else { return }
        isShowingSkeleton = false
        placeholder.remove()
    }

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
        let header = UIStackView(arrangedSubviews: [box(64, 16), box(120, 14), UIView(), box(70, 20)])
        header.axis = .horizontal; header.spacing = 8; header.alignment = .center
        let body = UIStackView(arrangedSubviews: [box(220, 18), box(160, 13), box(180, 12)])
        body.axis = .vertical; body.spacing = 8; body.alignment = .leading
        let stack = UIStackView(arrangedSubviews: [header, body])
        stack.axis = .vertical; stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        let card = UIView()
        card.backgroundColor = Palette.card
        card.layer.cornerRadius = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        return card
    }
}

/// Small padded label used for the MANUAL / status pills.
final class PaddingLabelManual: UILabel {
    private let inset = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: inset)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + inset.left + inset.right, height: s.height + inset.top + inset.bottom)
    }
}

// Local hex initializer — the app's UIColor(hex:) lives as a file-private
// extension inside each Queue Line file, so this module declares its own
// (same convention, file-private, no collision with the Queue Line ones).
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: 1.0)
    }
}
