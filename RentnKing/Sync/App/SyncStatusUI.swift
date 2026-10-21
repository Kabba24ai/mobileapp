//
//  SyncStatusUI.swift
//  RentnKing — Sync App layer (UIKit; self-contained, themed by injection)
//
//  Just enough presentation so an employee is never misled:
//   • SyncStatusToast        — after a save: "Saved · Pending Sync" → "Synced" / "Needs Attention"
//   • SyncStatusSummaryView  — one line for Settings: "2 pending · 1 needs attention"
//   • SyncStatusViewController — Settings → Sync: records grouped by what a person must do,
//                              Sync Now with a result, and the review screen per record
//                              (SyncRecordReviewUI.swift) with Try Again / Remove.
//  The list never shows payload contents, images or credentials — only the review screen
//  shows a record's own photos/signature thumbnails, so a person can decide about it.
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

enum SyncStatusFormat {
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
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
        case .superseded:        return theme.secondaryText
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

    /// A plain transient confirmation ("✓ Checklist successfully completed"):
    /// non-blocking, no button, auto-dismisses, survives the navigation that
    /// follows. Reflects DURABLE LOCAL success only — it never waits for (or
    /// implies) server synchronization.
    static func showMessage(_ text: String, in window: UIWindow?, theme: SyncStatusTheme = .system, duration: TimeInterval = 1.3) {
        guard let window = window else { return }
        let toast = MessageToastView(text: text, theme: theme)
        toast.present(in: window, duration: duration)
    }

    private final class MessageToastView: UIView {
        private let label = UILabel()

        init(text: String, theme: SyncStatusTheme) {
            super.init(frame: .zero)
            backgroundColor = theme.card.withAlphaComponent(0.96)
            layer.cornerRadius = 12
            layer.borderWidth = 1
            layer.borderColor = theme.success.withAlphaComponent(0.7).cgColor
            translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 2
            label.textAlignment = .center
            label.font = theme.bold(15)
            label.textColor = theme.text
            label.text = text
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            ])
            isAccessibilityElement = true
            accessibilityTraits = .staticText
            accessibilityLabel = text
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func present(in window: UIWindow, duration: TimeInterval) {
            window.addSubview(self)
            NSLayoutConstraint.activate([
                centerXAnchor.constraint(equalTo: window.centerXAnchor),
                centerYAnchor.constraint(equalTo: window.centerYAnchor),
                widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, constant: -48),
            ])
            alpha = 0
            UIView.animate(withDuration: 0.15) { self.alpha = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self = self else { return }
                UIView.animate(withDuration: 0.25, animations: { self.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
            }
        }
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
            case .superseded:
                // Retired history — never announced as a fresh save.
                label.text = "Retired — the assigned machine changed"
                layer.borderColor = theme.secondaryText.withAlphaComponent(0.5).cgColor
                scheduleDismiss(after: 1.5)
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

/// Settings → Sync. Groups what is on this phone by what a person must do about it
/// (MOBILE-QUALITY-01, items 01/02):
///
///   Needs your attention — Kabba refused it; never retried automatically; tap to review
///   Waiting to sync      — saved on this phone; sends by itself (and why it hasn't yet)
///   Synced recently      — Kabba has it (7 days of history)
///   Retired              — history the world moved past
///   Removed from this phone — a content-free trace of records a person removed (30 days)
///
/// Sync Now runs one pass and says what it did — including "nothing new to send" when
/// everything left was refused, which before looked like a dead button.
final class SyncStatusViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private enum Section {
        case attention, waiting, synced, retired, removed

        var title: String {
            switch self {
            case .attention: return "Needs your attention"
            case .waiting:   return "Waiting to sync"
            case .synced:    return "Synced recently"
            case .retired:   return "Retired"
            case .removed:   return "Removed from this phone · last 30 days"
            }
        }
    }

    private enum Row {
        case record(SyncOperation)
        case removed(SyncRemovedRecord)
    }

    private let theme: SyncStatusTheme
    private let engineProvider: () -> SyncEngine?
    private let removedLogProvider: () -> SyncRemovedRecordLog?
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let headerStack = UIStackView()
    private let summaryLabel = UILabel()
    private let reportLabel = UILabel()
    private let installLabel = UILabel()
    private var sections: [(Section, [Row])] = []
    private var observer: NSObjectProtocol?
    private var lastReport: SyncPassReport?
    private var syncing = false

    /// The providers are seams for hosted tests; the app uses the one engine.
    init(theme: SyncStatusTheme = .system,
         engine: @escaping () -> SyncEngine? = { KabbaSync.engine },
         removedRecords: @escaping () -> SyncRemovedRecordLog? = { KabbaSync.removedRecords }) {
        self.theme = theme
        self.engineProvider = engine
        self.removedLogProvider = removedRecords
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
        let syncButton = UIBarButtonItem(title: "Sync Now", style: .plain, target: self, action: #selector(syncNow))
        syncButton.tintColor = theme.accent
        syncButton.accessibilityIdentifier = "sync.status.syncNow"
        navigationItem.rightBarButtonItem = syncButton

        for label in [summaryLabel, reportLabel, installLabel] {
            label.numberOfLines = 0
            label.textAlignment = .left
        }
        summaryLabel.font = theme.bold(16)
        summaryLabel.textColor = theme.text
        reportLabel.font = theme.regular(14)
        reportLabel.textColor = theme.secondaryText
        reportLabel.accessibilityIdentifier = "sync.status.report"
        installLabel.font = theme.regular(12)
        installLabel.textColor = theme.secondaryText
        headerStack.axis = .vertical
        headerStack.spacing = 6
        headerStack.isLayoutMarginsRelativeArrangement = true
        headerStack.layoutMargins = UIEdgeInsets(top: 14, left: 20, bottom: 6, right: 20)
        [summaryLabel, reportLabel, installLabel].forEach(headerStack.addArrangedSubview)

        table.dataSource = self
        table.delegate = self
        table.backgroundColor = theme.background
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        table.translatesAutoresizingMaskIntoConstraints = false
        table.tableHeaderView = headerStack
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeaderToFit()
    }

    private func sizeHeaderToFit() {
        guard table.bounds.width > 0 else { return }
        let size = headerStack.systemLayoutSizeFitting(CGSize(width: table.bounds.width, height: 0),
                                                       withHorizontalFittingPriority: .required,
                                                       verticalFittingPriority: .fittingSizeLevel)
        if abs(headerStack.frame.height - size.height) > 0.5 || headerStack.frame.width != table.bounds.width {
            headerStack.frame = CGRect(x: 0, y: 0, width: table.bounds.width, height: size.height)
            table.tableHeaderView = headerStack
        }
    }

    private func reload() {
        guard let engine = engineProvider() else {
            sections = []
            summaryLabel.text = "Sync engine unavailable"
            reportLabel.text = nil
            installLabel.text = nil
            table.reloadData()
            return
        }
        let ops = engine.snapshot()
        let attention = ops.filter { $0.state == .needsAttention }
        let waiting = ops.filter { $0.state == .pending || $0.state == .syncing }
        let synced = ops.filter { $0.state == .synced }.sorted { $0.queuedAt > $1.queuedAt }
        let retired = ops.filter { $0.state == .superseded }.sorted { $0.queuedAt > $1.queuedAt }
        let removed = removedLogProvider()?.entries() ?? []

        sections = [
            (.attention, attention.map(Row.record)),
            (.waiting, waiting.map(Row.record)),
            (.synced, synced.map(Row.record)),
            (.retired, retired.map(Row.record)),
            (.removed, removed.map(Row.removed)),
        ].filter { !$0.1.isEmpty }

        let summary = engine.summary()
        var line = summary.line
        if summary.pause == .authentication { line += " · paused until you sign in" }
        if summary.pause == .appUpdate { line += " · paused until the app is updated" }
        summaryLabel.text = line
        summaryLabel.textColor = summary.needsAttention > 0 ? theme.warning : theme.text
        renderReport()
        installLabel.text = KabbaSync.installation.map { "Install id: \($0.identifier())" }
        table.reloadData()
        sizeHeaderToFit()
    }

    private func renderReport() {
        if syncing {
            reportLabel.text = "Syncing…"
            reportLabel.isHidden = false
            return
        }
        guard let report = lastReport else {
            reportLabel.text = nil
            reportLabel.isHidden = true
            return
        }
        let text = NSMutableAttributedString(string: report.headline,
                                             attributes: [.font: theme.bold(14), .foregroundColor: theme.text])
        for line in report.lines(timeFormatter: { SyncStatusFormat.time.string(from: $0) }) {
            text.append(NSAttributedString(string: "\n" + line, attributes: [.font: theme.regular(14), .foregroundColor: theme.secondaryText]))
        }
        reportLabel.attributedText = text
        reportLabel.isHidden = false
    }

    @objc private func syncNow() {
        guard !syncing else { return }
        guard let engine = engineProvider() else { return }
        syncing = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.rightBarButtonItem?.title = "Syncing…"
        renderReport()
        sizeHeaderToFit()

        let before = Dictionary(uniqueKeysWithValues: engine.snapshot().map { ($0.id, $0.state) })
        var answered = false
        let finish: (SyncPassReport) -> Void = { [weak self] report in
            guard let self = self, !answered else { return }
            answered = true
            self.syncing = false
            self.lastReport = report
            self.navigationItem.rightBarButtonItem?.isEnabled = true
            self.navigationItem.rightBarButtonItem?.title = "Sync Now"
            self.reload()
            UIAccessibility.post(notification: .announcement, argument: report.headline)
        }
        engine.syncNow(reason: "Sync Now (Settings)") { report in
            DispatchQueue.main.async { finish(report) }
        }
        // A large upload can outlast the screen's patience: say what is known so far.
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            finish(SyncPassReport.make(before: before, after: engine.snapshot(), pause: engine.pause, timedOut: true))
        }
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { max(sections.count, 1) }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections.isEmpty ? 1 : sections[section].1.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard !sections.isEmpty else { return nil }
        let (kind, rows) = sections[section]
        let label = UILabel()
        label.font = theme.bold(13)
        label.textColor = kind == .attention ? theme.warning : theme.secondaryText
        label.text = kind == .removed ? kind.title.uppercased() : "\(kind.title.uppercased()) (\(rows.count))"
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
        return container
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.backgroundColor = theme.card
        cell.textLabel?.numberOfLines = 0

        guard !sections.isEmpty else {
            cell.textLabel?.attributedText = nil
            cell.textLabel?.text = "Nothing on this phone is waiting to sync."
            cell.textLabel?.font = theme.regular(15)
            cell.textLabel?.textColor = theme.secondaryText
            cell.accessoryType = .none
            cell.selectionStyle = .none
            return cell
        }

        switch sections[indexPath.section].1[indexPath.row] {
        case .record(let op):
            cell.textLabel?.attributedText = SyncStatusRowText.make(for: op, theme: theme)
            cell.accessibilityIdentifier = "sync.status.row.\(op.id)"
        case .removed(let trace):
            cell.textLabel?.attributedText = SyncStatusRowText.make(for: trace, theme: theme)
            cell.accessibilityIdentifier = "sync.status.removed.\(trace.operationId)"
        }
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !sections.isEmpty else { return }
        switch sections[indexPath.section].1[indexPath.row] {
        case .record(let op):
            let engineProvider = self.engineProvider
            let logProvider = self.removedLogProvider
            let review = SyncRecordReviewViewController(operationId: op.id, theme: theme, engine: engineProvider,
                                                        remove: { try KabbaSync.removeRecord($0, engine: engineProvider(), log: logProvider()) })
            navigationController?.pushViewController(review, animated: true)
        case .removed(let trace):
            presentTrace(trace)
        }
    }

    private func presentTrace(_ trace: SyncRemovedRecord) {
        var lines = [
            "Removed: \(SyncStatusFormat.dateTime.string(from: trace.removedAt))\(trace.removedByName.map { " by \($0)" } ?? "")",
            "Captured: \(SyncStatusFormat.dateTime.string(from: trace.capturedAt))",
            "Kabba never received it.",
        ]
        if !trace.contentsSummary.isEmpty { lines.append("It held: \(trace.contentsSummary) (deleted)") }
        if let code = trace.errorCode { lines.append("Refusal: \(code)") }
        if !trace.identitySummary.isEmpty { lines.append(trace.identitySummary) }
        lines.append("Operation id: \(trace.operationId)")
        if let request = trace.requestId { lines.append("Request id: \(request)") }
        let alert = UIAlertController(title: trace.title, message: lines.joined(separator: "\n"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Copy IDs", style: .default) { _ in
            UIPasteboard.general.string = "operation_id=\(trace.operationId) request_id=\(trace.requestId ?? "-")"
        })
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }
}

/// One list row's text: title, what is going on, references, and what exists only here.
enum SyncStatusRowText {

    static func make(for op: SyncOperation, theme: SyncStatusTheme) -> NSAttributedString {
        let review = SyncRecordReview.of(op)
        let text = NSMutableAttributedString(string: review.title + "\n",
                                             attributes: [.font: theme.bold(15), .foregroundColor: theme.text])
        text.append(NSAttributedString(string: status(op, review),
                                       attributes: [.font: theme.bold(13), .foregroundColor: SyncStatusFormat.color(for: op.state, theme: theme)]))
        var detail = "\ncaptured \(SyncStatusFormat.dateTime.string(from: op.capturedAt))"
        if !op.identity.summary.isEmpty { detail += " · \(op.identity.summary)" }
        text.append(NSAttributedString(string: detail, attributes: [.font: theme.regular(12), .foregroundColor: theme.secondaryText]))
        if op.state != .synced && op.state != .superseded && !review.contents.summary.isEmpty {
            text.append(NSAttributedString(string: "\nOnly on this phone: " + review.contents.summary,
                                           attributes: [.font: theme.regular(12), .foregroundColor: theme.secondaryText]))
        }
        return text
    }

    static func make(for trace: SyncRemovedRecord, theme: SyncStatusTheme) -> NSAttributedString {
        let text = NSMutableAttributedString(string: trace.title + "\n",
                                             attributes: [.font: theme.bold(15), .foregroundColor: theme.secondaryText])
        var line = "Removed \(SyncStatusFormat.dateTime.string(from: trace.removedAt))"
        if let name = trace.removedByName, !name.isEmpty { line += " by \(name)" }
        text.append(NSAttributedString(string: line, attributes: [.font: theme.regular(13), .foregroundColor: theme.secondaryText]))
        return text
    }

    static func status(_ op: SyncOperation, _ review: SyncRecordReview) -> String {
        switch review.problem {
        case .rejected:
            return "Kabba refused this · " + (review.explanation?.headline ?? "needs review")
        case .waiting:
            return op.state == .syncing ? "Sending now…" : "Waiting to send"
        case .waitingForConnection:
            return "Waiting for a connection · sends automatically"
        case .temporaryFailure:
            if let next = op.attempts.nextAttemptAt { return "Kabba unavailable · retries automatically at \(SyncStatusFormat.time.string(from: next))" }
            return "Kabba unavailable · retries automatically"
        case .paused:
            return op.attempts.lastDisposition == .waitForAppUpdate ? "Paused until the app is updated" : "Paused until you sign in"
        case .none:
            if op.state == .superseded { return "Retired" + (op.supersession.map { " · \($0.summary)" } ?? "") }
            return "Synced · \(SyncStatusFormat.relative(op.acknowledgment?.acknowledgedAt))"
        }
    }
}
