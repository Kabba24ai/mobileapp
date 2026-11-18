//
//  ManualDispatchDetailViewController.swift
//  RentnKing
//
//  Detail screen for a single Manual Dispatch task. Programmatic UIKit, pushed
//  from the Dispatch list's manual card. Reuses the shared openAddressInMap(...)
//  maps helper and the standard tel:// call pattern. Order-free: it never reads
//  or touches any order/rental/checklist data.
//
//  Restored from the original Manual Dispatch module (removed by a vendor
//  commit) and adapted for Dispatch parity (Phase 6A):
//   - the model is the Sync Core DispatchManualJob (the mixed-feed DTO);
//   - status transitions go through the canonical Sync Engine
//     (ManualDispatchSyncHandler — durable, idempotent, Pending Sync /
//     Synced / Needs Attention) instead of ad-hoc networking.
//

import UIKit
import MessageUI

final class ManualDispatchDetailViewController: UIViewController, UIGestureRecognizerDelegate, MFMessageComposeViewControllerDelegate {

    var item: DispatchManualJob?
    /// Called after a status change was enqueued so the list can refresh + pop back.
    var onChanged: (() -> Void)?

    private enum Palette {
        static let page   = UIColor.background
        static let card   = UIColor(hex: 0x141C26)
        static let border = UIColor(hex: 0x2A3542)
        static let ink    = UIColor.primary
        static let subtle = UIColor(hex: 0x9AA4B2)
        static let indigo = UIColor(hex: 0x6366F1)
        static let blue   = UIColor(hex: 0x1B6EC2)
        static let green  = UIColor(hex: 0x1FA155)
        static let red    = UIColor(hex: 0xDC2626)
        static let amber  = UIColor(hex: 0xD97706)
    }

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.page
        setupScaffold()
        rebuild()
        // Coming back from Maps re-derives the effective status, so a task
        // whose On My Way is still Pending Sync renders "Navigate", not a
        // second "On My Way – Navigate".
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appBecameActive() {
        rebuild()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuild()
        AppUtility.PortraitMode()
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self
        self.tabBarController?.tabBar.isHidden = true

        setNavigationBarForButtons(controller: self, title: "Task Details", isTransperent: true,
                                   hideShadowImage: true, leftIcon: "icon_back",
                                   rightIcon: [], isFilter: false) {
            self.navigationController?.popViewController(animated: true)
        } rightActionHandler: { _, _ in }
    }

    private func setupScaffold() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
        ])
    }

    /// Effective status = server feed status ∨ durable local Sync Engine
    /// evidence (Pending Sync / syncing / synced / Needs Attention) — so the
    /// screen shows On My Way the moment the transition is durably saved on
    /// this phone, without waiting for Laravel.
    private func currentEffectiveStatus() -> String? {
        return DispatchManualStatus.effectiveStatus(serverStatus: item?.status,
                                                    operations: KabbaSync.engine?.snapshot() ?? [],
                                                    manualTaskUniqueId: item?.unique_id)
    }

    /// The task's items with durable local confirmations applied — a tap
    /// shows on the row the moment it is saved on this phone.
    private func currentEffectiveItems() -> [DispatchManualJob.ItemRef] {
        return DispatchManualItemProgress.effectiveItems(serverItems: item?.items ?? [],
                                                         operations: KabbaSync.engine?.snapshot() ?? [],
                                                         manualTaskUniqueId: item?.unique_id)
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let item = item else { return }
        let effective = currentEffectiveStatus()
        let hasAddress = item.address?.isEmpty == false

        // Header: MANUAL (+ INVENTORY TRANSFER) + type + status
        var pills: [UIView] = [pill("MANUAL", bg: Palette.indigo.withAlphaComponent(0.18), fg: Palette.indigo)]
        if item.dispatch_subtype == "inventory_transfer" {
            pills.append(pill("INVENTORY TRANSFER", bg: Palette.amber.withAlphaComponent(0.18), fg: Palette.amber))
        }
        pills.append(UIView())
        pills.append(pill(effective ?? "", bg: Palette.blue.withAlphaComponent(0.18), fg: Palette.blue))
        let head = UIStackView(arrangedSubviews: pills)
        head.axis = .horizontal; head.alignment = .center; head.spacing = 6
        stack.addArrangedSubview(head)

        let title = UILabel()
        title.text = item.type
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = Palette.ink
        title.numberOfLines = 0
        stack.addArrangedSubview(title)

        // Task
        var taskRows: [(String, String?)] = [
            ("Type", item.type),
            ("Description", item.description),
            ("Instructions", item.instructions),
        ]
        // With an item list (2026-11) the Items card names every unit; the
        // single Equipment row is for tasks that carry no item list.
        if (item.items ?? []).isEmpty, let equipment = item.equipment?.name, !equipment.isEmpty {
            taskRows.append(("Equipment", equipment))
        }
        if item.dispatch_subtype == "inventory_transfer" {
            let movement = [item.origin_store?.name, item.destination_store?.name]
                .compactMap { ($0?.isEmpty == false) ? $0 : nil }
                .joined(separator: " → ")
            if !movement.isEmpty { taskRows.append(("Movement", movement)) }
        }
        stack.addArrangedSubview(section("Task", rows: taskRows))

        // Combined dispatch (2026-11): this task travels with others as ONE
        // assignment — one pickup, one destination. Each task is still
        // progressed on its own screen.
        if let combined = item.combined_dispatch, (combined.task_count ?? 0) > 1 {
            stack.addArrangedSubview(section("Combined Dispatch", rows: [
                ("Travels With", "\(combined.task_count ?? 0) tasks on one trip"),
                ("Pickup", combined.pickup ?? item.pickup_location),
                ("Destination", combined.destination ?? item.destination_location),
            ]))
        }

        // Items: every piece of equipment / inventory on this task, confirmed
        // one at a time. Confirming one never marks another, and completing
        // the task never marks an item nobody confirmed.
        let items = currentEffectiveItems()
        if !items.isEmpty {
            stack.addArrangedSubview(itemsSection(items, taskIsTerminal: DispatchManualStatus.isTerminal(effective)))
        }

        // Destination — one compact action below the card: pre-trip it both
        // records On My Way AND opens navigation in a single tap; once the
        // task is effectively On My Way (server-confirmed OR Pending Sync) it
        // becomes plain Navigate and only reopens Maps.
        stack.addArrangedSubview(section("Destination", rows: [
            ("Location", item.location_name),
            ("Address", item.address),
        ]))
        switch DispatchManualStatus.destinationAction(effectiveStatus: effective, hasAddress: hasAddress) {
        case .onMyWayNavigate:
            stack.addArrangedSubview(compactButton("On My Way – Navigate", bg: Palette.indigo, action: #selector(onMyWayNavigateTapped)))
        case .navigate:
            stack.addArrangedSubview(compactButton("Navigate", bg: Palette.blue, action: #selector(navigateTapped)))
        case .none:
            break
        }

        // Contact
        stack.addArrangedSubview(section("Contact", rows: [
            ("Name", item.contact_name),
            ("Phone", item.phone),
        ]))
        if let phone = item.phone, !phone.isEmpty {
            stack.addArrangedSubview(compactButton("Call", bg: Palette.green, action: #selector(callTapped)))
        }

        // Operational
        stack.addArrangedSubview(section("Operational", rows: [
            ("Store", item.store),
            ("Dispatch Date", item.date),
            ("Dispatch Time", item.time),
            ("Priority", item.priority.map { "\($0)" } ?? "Normal"),
            ("Status", effective),
        ]))

        // Status actions (non-terminal only). The On My Way step lives on the
        // combined Destination button when an address exists; an address-less
        // task keeps its plain advance button so the lifecycle is never blocked.
        if !DispatchManualStatus.isTerminal(effective) {
            if let step = DispatchManualStatus.bottomAdvance(effectiveStatus: effective, hasAddress: hasAddress) {
                stack.addArrangedSubview(compactButton(step, bg: Palette.indigo, action: #selector(advanceTapped)))
            }
            stack.addArrangedSubview(compactButton("Cancel Task", bg: .clear, fg: Palette.red, bordered: true, action: #selector(cancelTapped)))
        }
    }

    // MARK: - Actions

    /// One tap = "I'm leaving now — take me there": durably enqueue the
    /// canonical On My Way transition, then open navigation. Local-first —
    /// Maps is never blocked on Laravel; if durable local persistence itself
    /// fails, no status is claimed and no navigation launches.
    @objc private func onMyWayNavigateTapped() {
        guard let item = item else { return }
        let hasAddress = item.address?.isEmpty == false

        // Re-derive at tap time: already effectively On My Way (fast second
        // tap, or recorded elsewhere) → reopen Maps only, never a second
        // operation.
        guard DispatchManualStatus.destinationAction(effectiveStatus: currentEffectiveStatus(),
                                                     hasAddress: hasAddress) == .onMyWayNavigate else {
            openAddressInMap(address: item.address)
            return
        }

        guard let uid = item.unique_id, let engine = KabbaSync.engine else {
            showAlertMessage(strMessage: str.somethingWentWrong)
            return
        }
        do {
            let operation = try ManualDispatchSyncHandler.enqueue(into: engine,
                                                                  taskUniqueId: uid,
                                                                  status: DispatchManualStatus.onMyWay)
            KabbaSync.showStatusToast(for: operation.id)
            onChanged?()                 // list refresh — the driver stays here
            rebuild()                    // pill → On My Way, button → Navigate
            openAddressInMap(address: item.address)
        } catch {
            // Durable local save failed — no false status, no navigation.
            showAlertMessage(strMessage: str.somethingWentWrong)
        }
    }

    /// One item picked up / delivered: a durable, idempotent Sync Engine
    /// operation of its own. The driver stays on this screen.
    @objc private func itemStepTapped(_ sender: UIButton) {
        let items = currentEffectiveItems()
        guard sender.tag >= 0, sender.tag < items.count else { return }
        let target = items[sender.tag]
        guard let itemId = target.id,
              let step = DispatchManualItemProgress.nextStep(for: target),
              let uid = item?.unique_id, let engine = KabbaSync.engine else { return }
        do {
            let operation = try ManualDispatchItemProgressSyncHandler.enqueue(into: engine,
                                                                              taskUniqueId: uid,
                                                                              itemId: itemId,
                                                                              itemLabel: target.label ?? "Item",
                                                                              step: step)
            KabbaSync.showStatusToast(for: operation.id)
            onChanged?()
            rebuild()
        } catch {
            // Durable local save failed — claim nothing.
            showAlertMessage(strMessage: str.somethingWentWrong)
        }
    }

    @objc private func navigateTapped() {
        openAddressInMap(address: item?.address)
    }

    @objc private func callTapped() {
        guard var number = item?.phone, !number.isEmpty else { return }
        number = number.replacingOccurrences(of: "+1", with: "")
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Call \(number)", style: .default) { _ in
            guard let url = URL(string: "tel://+1\(number)") else { return }
            UIApplication.shared.open(url)
        })
        if MFMessageComposeViewController.canSendText() {
            sheet.addAction(UIAlertAction(title: "Send Message", style: .default) { [weak self] _ in
                let sms = MFMessageComposeViewController()
                sms.recipients = ["+1\(number)"]
                sms.messageComposeDelegate = self
                self?.present(sms, animated: true)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController { pop.sourceView = view; pop.sourceRect = view.bounds }
        present(sheet, animated: true)
    }

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }

    @objc private func advanceTapped() {
        // Effective status, so a task whose On My Way is still Pending Sync
        // advances to Arrived — never re-offered On My Way.
        guard let next = DispatchManualStatus.next(after: currentEffectiveStatus()) else { return }
        confirm("Mark this task as \(next)?") { [weak self] in
            self?.submitStatus(next)
        }
    }

    @objc private func cancelTapped() {
        confirm("Cancel this manual dispatch task?") { [weak self] in
            self?.submitStatus(DispatchManualStatus.cancelled)
        }
    }

    /// Durable, idempotent transition through the canonical Sync Engine.
    /// Online the engine kicks immediately (the toast lands on "Synced with
    /// Kabba" in moments); offline the operation stays Pending Sync and the
    /// server converges on reconnect. A reassigned-away task answers
    /// 403/409 — non-retryable — and parks as Needs Attention.
    private func submitStatus(_ status: String) {
        guard let uid = item?.unique_id, let engine = KabbaSync.engine else { return }
        do {
            let operation = try ManualDispatchSyncHandler.enqueue(into: engine, taskUniqueId: uid, status: status)
            KabbaSync.showStatusToast(for: operation.id)
            finishAfterChange()
        } catch {
            showAlertMessage(strMessage: str.somethingWentWrong)
        }
    }

    private func finishAfterChange() {
        onChanged?()
        navigationController?.popViewController(animated: true)
    }

    private func confirm(_ message: String, onYes: @escaping () -> Void) {
        let alert = UIAlertController(title: Application.appName, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: str.yes, style: .default) { _ in onYes() })
        alert.addAction(UIAlertAction(title: str.no, style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - UI helpers
    private func section(_ heading: String, rows: [(String, String?)]) -> UIStackView {
        let head = UILabel()
        head.text = heading.uppercased()
        head.font = .systemFont(ofSize: 12, weight: .bold)
        head.textColor = Palette.subtle

        let inner = UIStackView()
        inner.axis = .vertical; inner.spacing = 10
        inner.isLayoutMarginsRelativeArrangement = true
        inner.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        for (label, value) in rows {
            let v = (value?.isEmpty == false) ? value! : "—"
            let l = UILabel()
            l.font = .systemFont(ofSize: 11, weight: .semibold)
            l.textColor = Palette.subtle
            l.text = label.uppercased()
            let val = UILabel()
            val.font = .systemFont(ofSize: 15)
            val.textColor = Palette.ink
            val.numberOfLines = 0
            val.text = v
            let row = UIStackView(arrangedSubviews: [l, val])
            row.axis = .vertical; row.spacing = 2
            inner.addArrangedSubview(row)
        }

        let cardWrap = UIView()
        cardWrap.backgroundColor = Palette.card
        cardWrap.layer.cornerRadius = 12
        cardWrap.layer.borderWidth = 1
        cardWrap.layer.borderColor = Palette.border.cgColor
        inner.translatesAutoresizingMaskIntoConstraints = false
        cardWrap.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: cardWrap.topAnchor),
            inner.leadingAnchor.constraint(equalTo: cardWrap.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: cardWrap.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: cardWrap.bottomAnchor),
        ])

        let outer = UIStackView(arrangedSubviews: [head, cardWrap])
        outer.axis = .vertical; outer.spacing = 8
        return outer
    }

    /// The Items card: one row per item — label, its own instructions, its
    /// own state — with the single next confirmation for that item.
    private func itemsSection(_ items: [DispatchManualJob.ItemRef], taskIsTerminal: Bool) -> UIStackView {
        let head = UILabel()
        head.text = (DispatchManualItemProgress.summary(items) ?? "Items").uppercased()
        head.font = .systemFont(ofSize: 12, weight: .bold)
        head.textColor = Palette.subtle

        let inner = UIStackView()
        inner.axis = .vertical; inner.spacing = 14
        inner.isLayoutMarginsRelativeArrangement = true
        inner.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        for (index, entry) in items.enumerated() {
            let name = UILabel()
            name.font = .systemFont(ofSize: 15, weight: .semibold)
            name.textColor = Palette.ink
            name.numberOfLines = 0
            name.text = entry.label ?? "Item"

            let state = UILabel()
            state.font = .systemFont(ofSize: 12, weight: .bold)
            if entry.delivered == true {
                state.text = "DELIVERED"; state.textColor = Palette.green
            } else if entry.picked_up == true {
                state.text = "PICKED UP — NOT DELIVERED YET"; state.textColor = Palette.blue
            } else {
                state.text = "NOT PICKED UP YET"; state.textColor = Palette.subtle
            }

            let row = UIStackView(arrangedSubviews: [name])
            row.axis = .vertical; row.spacing = 4
            if let note = entry.instructions, !note.isEmpty {
                let instructions = UILabel()
                instructions.font = .systemFont(ofSize: 13)
                instructions.textColor = Palette.subtle
                instructions.numberOfLines = 0
                instructions.text = note
                row.addArrangedSubview(instructions)
            }
            row.addArrangedSubview(state)

            if !taskIsTerminal, let step = DispatchManualItemProgress.nextStep(for: entry) {
                let b = UIButton(type: .system)
                b.setTitle(step == .deliver ? "Mark Delivered" : "Mark Picked Up", for: .normal)
                b.setTitleColor(.white, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
                b.backgroundColor = step == .deliver ? Palette.green : Palette.indigo
                b.layer.cornerRadius = 8
                b.heightAnchor.constraint(equalToConstant: 44).isActive = true
                b.tag = index
                b.accessibilityIdentifier = "manual-item-step-\(entry.id ?? 0)"
                b.addTarget(self, action: #selector(itemStepTapped(_:)), for: .touchUpInside)
                row.setCustomSpacing(8, after: state)
                row.addArrangedSubview(b)
            }
            inner.addArrangedSubview(row)
        }

        let cardWrap = UIView()
        cardWrap.backgroundColor = Palette.card
        cardWrap.layer.cornerRadius = 12
        cardWrap.layer.borderWidth = 1
        cardWrap.layer.borderColor = Palette.border.cgColor
        inner.translatesAutoresizingMaskIntoConstraints = false
        cardWrap.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: cardWrap.topAnchor),
            inner.leadingAnchor.constraint(equalTo: cardWrap.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: cardWrap.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: cardWrap.bottomAnchor),
        ])

        let outer = UIStackView(arrangedSubviews: [head, cardWrap])
        outer.axis = .vertical; outer.spacing = 8
        return outer
    }

    private func pill(_ text: String, bg: UIColor, fg: UIColor) -> UIView {
        let label = PaddingLabelManual()
        label.text = text
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = fg
        label.backgroundColor = bg
        label.layer.cornerRadius = 5
        label.layer.masksToBounds = true
        return label
    }

    /// A compact, centered action button (mockup proportions) — intentional
    /// button, not a section-wide bar. Same palette, typography and corner
    /// radius as before; 48pt touch target.
    private func compactButton(_ title: String, bg: UIColor, fg: UIColor = .white, bordered: Bool = false, action: Selector) -> UIView {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(fg, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.backgroundColor = bg
        b.layer.cornerRadius = 10
        if bordered {
            b.layer.borderWidth = 1
            b.layer.borderColor = fg.withAlphaComponent(0.5).cgColor
        }
        b.heightAnchor.constraint(equalToConstant: 48).isActive = true
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        b.addTarget(self, action: action, for: .touchUpInside)

        let wrap = UIStackView(arrangedSubviews: [b])
        wrap.axis = .vertical
        wrap.alignment = .center
        return wrap
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
