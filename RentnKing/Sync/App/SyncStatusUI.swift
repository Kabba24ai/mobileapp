//
//  SyncStatusUI.swift
//  RentnKing — Sync App layer (UIKit; self-contained, themed by injection)
//
//  Just enough presentation so an employee is never misled:
//   • SyncStatusToast        — after a save: "Saved · Pending Sync" → "Synced" / "Needs Attention"
//   • SyncStatusSummaryView  — one line for Settings: "2 pending · 1 needs attention"
//   • SyncStatusViewController — the diagnostics list (type, captured, attempts, sanitized error,
//                              request/operation ids) with Retry / Discard / Sync Now.
//  No payload contents, images or credentials are ever shown.
//

import UIKit

struct SyncStatusTheme {
    var background: UIColor
    var card: UIColor
    var accent: UIColor
    var text: UIColor
    var secondaryText: UIColor
    var success: UIColor
    var warning: UIColor
    var bold: (CGFloat) -> UIFont
    var regular: (CGFloat) -> UIFont

    static let system = SyncStatusTheme(
        background: .systemBackground,
        card: .secondarySystemBackground,
        accent: .systemTeal,
        text: .label,
        secondaryText: .secondaryLabel,
        success: .systemGreen,
        warning: .systemOrange,
        bold: { UIFont.boldSystemFont(ofSize: $0) },
        regular: { UIFont.systemFont(ofSize: $0) }
    )
}

private enum SyncStatusFormat {
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    static func relative(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86_400 { return "\(seconds / 3600) h ago" }
        return dateTime.string(from: date)
    }

    static func color(for state: SyncState, theme: SyncStatusTheme) -> UIColor {
        switch state {
        case .synced:            return theme.success
        case .needsAttention:    return theme.warning
        case .pending, .syncing: return theme.accent
        }
    }
}

// MARK: - Toast

enum SyncStatusToast {

    /// Shows a transient status line for one operation. Lives on the window so it survives
    /// the screen transition that usually follows a save (e.g. opening Maps).
    static func show(operationId: String, in window: UIWindow?, theme: SyncStatusTheme = .system) {
        guard let window = window, let engine = KabbaSync.engine else { return }
        let toast = ToastView(operationId: operationId, engine: engine, theme: theme)
        toast.present(in: window)
    }

    private final class ToastView: UIView {
        private let operationId: String
        private let engine: SyncEngine
        private let theme: SyncStatusTheme
        private let label = UILabel()
        private var observer: NSObjectProtocol?
        private var dismissWorkItem: DispatchWorkItem?

        init(operationId: String, engine: SyncEngine, theme: SyncStatusTheme) {
            self.operationId = operationId
            self.engine = engine
            self.theme = theme
            super.init(frame: .zero)
            backgroundColor = theme.card.withAlphaComponent(0.96)
            layer.cornerRadius = 12
            layer.borderWidth = 1
            layer.borderColor = theme.accent.withAlphaComponent(0.5).cgColor
            translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 2
            label.textAlignment = .center
            label.font = theme.bold(14)
            label.textColor = theme.text
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            ])
            isAccessibilityElement = true
            accessibilityTraits = .staticText
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func present(in window: UIWindow) {
            window.addSubview(self)
            NSLayoutConstraint.activate([
                centerXAnchor.constraint(equalTo: window.centerXAnchor),
                bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -72),
                widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, constant: -32),
            ])
            alpha = 0
            render(state: engine.operation(id: operationId)?.state ?? .pending)
            UIView.animate(withDuration: 0.2) { self.alpha = 1 }

            observer = NotificationCenter.default.addObserver(forName: .kabbaSyncOperationChanged, object: nil, queue: .main) { [weak self] note in
                guard let self = self, note.userInfo?["operationId"] as? String == self.operationId,
                      let raw = note.userInfo?["state"] as? String, let state = SyncState(rawValue: raw) else { return }
                self.render(state: state)
            }
            scheduleDismiss(after: 4)
        }

        private func render(state: SyncState) {
            switch state {
            case .pending, .syncing:
                label.text = "Saved on this phone · Pending Sync"
                layer.borderColor = theme.accent.withAlphaComponent(0.5).cgColor
            case .synced:
                label.text = "Synced with Kabba"
                layer.borderColor = theme.success.withAlphaComponent(0.7).cgColor
                scheduleDismiss(after: 1.5)
            case .needsAttention:
                label.text = "Saved · Needs Attention — see Settings › Sync"
                layer.borderColor = theme.warning.withAlphaComponent(0.8).cgColor
                scheduleDismiss(after: 6)
            }
            accessibilityLabel = label.text
        }

        private func scheduleDismiss(after seconds: TimeInterval) {
            dismissWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.dismiss() }
            dismissWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        }

        private func dismiss() {
            if let observer = observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            UIView.animate(withDuration: 0.25, animations: { self.alpha = 0 }) { _ in self.removeFromSuperview() }
        }
    }
}

// MARK: - Summary row (Settings)

final class SyncStatusSummaryView: UIControl {

    var onTap: (() -> Void)?

    private let theme: SyncStatusTheme
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    private var observer: NSObjectProtocol?

    init(theme: SyncStatusTheme = .system) {
        self.theme = theme
        super.init(frame: .zero)
        build()
        refresh()
        observer = NotificationCenter.default.addObserver(forName: .kabbaSyncQueueChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func build() {
        titleLabel.text = "Sync:  "
        titleLabel.font = theme.bold(17)
        titleLabel.textColor = theme.accent
        valueLabel.font = theme.regular(16)
        valueLabel.textColor = theme.secondaryText
        valueLabel.numberOfLines = 0
        chevron.tintColor = theme.accent
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func refresh() {
        guard let engine = KabbaSync.engine else {
            valueLabel.text = "Unavailable"
            accessibilityLabel = "Sync unavailable"
            return
        }
        let summary = engine.summary()
        var text = summary.line
        if summary.pause == .authentication { text += " · paused until sign-in" }
        if summary.pause == .appUpdate { text += " · paused until app update" }
        valueLabel.text = text
        valueLabel.textColor = summary.needsAttention > 0 ? theme.warning : theme.secondaryText
        accessibilityLabel = "Sync status: \(text). Opens sync details."
    }

    @objc private func tapped() { onTap?() }
}

// MARK: - Diagnostics screen

final class SyncStatusViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let theme: SyncStatusTheme
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let headerLabel = UILabel()
    private var entries: [SyncDiagnosticEntry] = []
    private var observer: NSObjectProtocol?

    init(theme: SyncStatusTheme = .system) {
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        title = "Sync Status"
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Sync Now", style: .plain, target: self, action: #selector(syncNow))
        navigationItem.rightBarButtonItem?.tintColor = theme.accent

        headerLabel.numberOfLines = 0
        headerLabel.font = theme.regular(15)
        headerLabel.textColor = theme.secondaryText
        headerLabel.textAlignment = .center

        table.dataSource = self
        table.delegate = self
        table.backgroundColor = theme.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        observer = NotificationCenter.default.addObserver(forName: .kabbaSyncQueueChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.tintColor = theme.accent
        reload()
    }

    private func reload() {
        guard let engine = KabbaSync.engine else {
            entries = []
            headerLabel.text = "Sync engine unavailable"
            table.reloadData()
            return
        }
        entries = engine.diagnostics()
        let summary = engine.summary()
        var lines = [summary.line]
        if summary.pause == .authentication { lines.append("Paused — sign in to resume.") }
        if summary.pause == .appUpdate { lines.append("Paused — update the app to resume.") }
        if let install = KabbaSync.installation { lines.append("Install id: \(install.identifier())") }
        headerLabel.text = lines.joined(separator: "\n")
        table.reloadData()
    }

    @objc private func syncNow() {
        KabbaSync.kick("Sync Now (Settings)", ignoreBackoff: true)
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(entries.count, 1) }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let container = UIView()
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.removeFromSuperview()
        container.addSubview(headerLabel)
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            headerLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])
        return container
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.backgroundColor = theme.card
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0

        guard !entries.isEmpty else {
            cell.textLabel?.text = "Nothing waiting to sync."
            cell.textLabel?.font = theme.regular(15)
            cell.textLabel?.textColor = theme.secondaryText
            cell.accessoryType = .none
            cell.selectionStyle = .none
            return cell
        }

        let entry = entries[indexPath.row]
        let stateColor = SyncStatusFormat.color(for: entry.state, theme: theme)

        let text = NSMutableAttributedString(string: entry.title + "\n",
                                             attributes: [.font: theme.bold(15), .foregroundColor: theme.text])
        text.append(NSAttributedString(string: entry.stateLabel,
                                       attributes: [.font: theme.bold(13), .foregroundColor: stateColor]))
        var detail = "  ·  captured \(SyncStatusFormat.dateTime.string(from: entry.capturedAt))"
        if entry.attemptCount > 0 { detail += "  ·  \(entry.attemptCount) attempt\(entry.attemptCount == 1 ? "" : "s")" }
        if let last = entry.lastAttemptedAt { detail += ", last \(SyncStatusFormat.relative(last))" }
        text.append(NSAttributedString(string: detail, attributes: [.font: theme.regular(13), .foregroundColor: theme.secondaryText]))
        if !entry.identitySummary.isEmpty {
            text.append(NSAttributedString(string: "\n" + entry.identitySummary, attributes: [.font: theme.regular(12), .foregroundColor: theme.secondaryText]))
        }
        if entry.state == .needsAttention, let reason = entry.errorSummary {
            text.append(NSAttributedString(string: "\n" + reason, attributes: [.font: theme.regular(13), .foregroundColor: theme.warning]))
        }
        cell.textLabel?.attributedText = text
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < entries.count else { return }
        presentDetail(for: entries[indexPath.row])
    }

    private func presentDetail(for entry: SyncDiagnosticEntry) {
        var lines: [String] = [
            "State: \(entry.stateLabel)",
            "Captured: \(SyncStatusFormat.dateTime.string(from: entry.capturedAt))",
            "Queued: \(SyncStatusFormat.dateTime.string(from: entry.queuedAt))",
            "Attempts: \(entry.attemptCount)",
        ]
        if let last = entry.lastAttemptedAt { lines.append("Last attempt: \(SyncStatusFormat.dateTime.string(from: last))") }
        if let next = entry.nextAttemptAt, entry.state == .pending { lines.append("Next attempt: \(SyncStatusFormat.dateTime.string(from: next))") }
        if let acked = entry.acknowledgedAt { lines.append("Acknowledged: \(SyncStatusFormat.dateTime.string(from: acked))\(entry.replayed ? " (replayed)" : "")") }
        if let status = entry.lastStatusCode { lines.append("Last HTTP status: \(status)") }
        if let code = entry.lastErrorCode { lines.append("Error code: \(code)") }
        if let error = entry.errorSummary { lines.append("Error: \(error)") }
        if !entry.identitySummary.isEmpty { lines.append(entry.identitySummary) }
        if entry.assetCount > 0 { lines.append("Files: \(entry.assetCount)") }
        lines.append("Operation id: \(entry.operationId)")
        if let requestId = entry.lastRequestId { lines.append("Request id: \(requestId)") }

        let alert = UIAlertController(title: entry.title, message: lines.joined(separator: "\n"), preferredStyle: .alert)

        if entry.state == .needsAttention || entry.state == .pending {
            alert.addAction(UIAlertAction(title: "Retry Now", style: .default) { _ in
                KabbaSync.engine?.retryNow(operationId: entry.operationId)
            })
        }
        alert.addAction(UIAlertAction(title: "Copy IDs", style: .default) { _ in
            UIPasteboard.general.string = "operation_id=\(entry.operationId) request_id=\(entry.lastRequestId ?? "-")"
        })
        if entry.state != .synced {
            alert.addAction(UIAlertAction(title: "Discard…", style: .destructive) { [weak self] _ in
                self?.confirmDiscard(entry)
            })
        }
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }

    private func confirmDiscard(_ entry: SyncDiagnosticEntry) {
        let confirm = UIAlertController(
            title: "Discard this record?",
            message: "This removes \"\(entry.title)\" from this phone permanently. Kabba has NOT received it. Only do this if the work was redone another way.",
            preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirm.addAction(UIAlertAction(title: "Discard", style: .destructive) { _ in
            try? KabbaSync.engine?.discard(operationId: entry.operationId)
            NotificationCenter.default.post(name: .kabbaSyncQueueChanged, object: nil)
        })
        present(confirm, animated: true)
    }
}
