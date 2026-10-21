//
//  SyncRecordReviewUI.swift
//  RentnKing — Sync App layer (UIKit; themed by injection)
//
//  One record from Settings → Sync, reviewed by the signed-in employee before
//  deciding about it (MOBILE-QUALITY-01, item 01):
//
//    • what happened and what to do (SyncRejectionCatalog — plain words, the
//      server's code and message kept for support);
//    • what the record holds that exists ONLY on this phone, with thumbnails of
//      its own photos / signature / license image;
//    • Try Again — one more attempt, for when the situation changed on Kabba;
//    • Remove from Sync Queue… — a deliberate, confirmed removal of THIS record
//      only. The confirmation lists what will be deleted and what the phone will
//      show afterwards. Nothing here ever says a refused record reached Kabba.
//

import UIKit

final class SyncRecordReviewViewController: UIViewController {

    private let operationId: String
    private let theme: SyncStatusTheme
    private let engineProvider: () -> SyncEngine?
    private let remover: (String) throws -> Void
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var observer: NSObjectProtocol?
    /// Set once this screen removed the record, so the queue notification that follows
    /// is not mistaken for the record vanishing elsewhere.
    private var removedHere = false

    /// `engine` / `remove` are seams for hosted tests; the app uses the one engine.
    init(operationId: String,
         theme: SyncStatusTheme = .system,
         engine: @escaping () -> SyncEngine? = { KabbaSync.engine },
         remove: @escaping (String) throws -> Void = { try KabbaSync.removeRecord($0) }) {
        self.operationId = operationId
        self.theme = theme
        self.engineProvider = engine
        self.remover = remove
        super.init(nibName: nil, bundle: nil)
        title = "Sync Record"
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.background
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
        ])
        observer = NotificationCenter.default.addObserver(forName: .kabbaSyncQueueChanged, object: nil, queue: .main) { [weak self] _ in
            self?.render()
        }
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: Render

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let engine = engineProvider(), let op = engine.operation(id: operationId) else {
            if !removedHere {
                stack.addArrangedSubview(paragraph("This record is no longer on this phone.", font: theme.bold(16), color: theme.text))
            }
            return
        }
        let review = SyncRecordReview.of(op)

        stack.addArrangedSubview(paragraph(review.title, font: theme.bold(19), color: theme.text))
        stack.addArrangedSubview(paragraph(stateLine(op, review), font: theme.bold(14),
                                           color: SyncStatusFormat.color(for: op.state, theme: theme)))

        if let why = review.explanation {
            let card = cardStack()
            card.addArrangedSubview(paragraph(why.headline, font: theme.bold(16), color: theme.text))
            card.addArrangedSubview(paragraph(why.detail, font: theme.regular(15), color: theme.secondaryText))
            card.addArrangedSubview(paragraph("What you can do", font: theme.bold(14), color: theme.accent))
            card.addArrangedSubview(paragraph(why.advice, font: theme.regular(15), color: theme.secondaryText))
            if review.officeSees {
                card.addArrangedSubview(paragraph("The office also sees this under Manage Schedule Conflicts → Mobile Sync Issues. Removing it here does not clear it there.",
                                                  font: theme.regular(13), color: theme.secondaryText))
            }
            stack.addArrangedSubview(wrap(card))
        } else if review.problem != .none {
            let card = cardStack()
            card.addArrangedSubview(paragraph("Saved on this phone. It sends to Kabba automatically — nothing for you to do.",
                                              font: theme.regular(15), color: theme.secondaryText))
            stack.addArrangedSubview(wrap(card))
        }

        if op.state != .synced && op.state != .superseded && !review.contents.items.isEmpty {
            let card = cardStack()
            card.addArrangedSubview(paragraph("Saved only on this phone", font: theme.bold(15), color: theme.text))
            card.addArrangedSubview(paragraph(review.contents.items.map { "• \($0)" }.joined(separator: "\n"),
                                              font: theme.regular(15), color: theme.secondaryText))
            card.addArrangedSubview(paragraph("Kabba has not received any of this.", font: theme.regular(13), color: theme.warning))
            if let strip = thumbnails(for: op, assetsDirectory: engine.store.assetsDirectory) { card.addArrangedSubview(strip) }
            stack.addArrangedSubview(wrap(card))
        }

        stack.addArrangedSubview(paragraph(details(op, review), font: theme.regular(12), color: theme.secondaryText))

        if review.canRetry {
            let retry = button(op.state == .needsAttention ? "Try Again" : "Send Now", style: .primary, id: "sync.review.retry")
            retry.addTarget(self, action: #selector(tryAgain), for: .touchUpInside)
            stack.addArrangedSubview(retry)
            if let why = review.explanation, !why.retryMayHelp {
                stack.addArrangedSubview(paragraph("Kabba is expected to refuse this same copy again.", font: theme.regular(12), color: theme.secondaryText))
            }
        }
        if review.canRemove {
            let remove = button("Remove from Sync Queue…", style: .destructive, id: "sync.review.remove")
            remove.addTarget(self, action: #selector(confirmRemove), for: .touchUpInside)
            stack.addArrangedSubview(remove)
        }
        let copy = button("Copy IDs for Support", style: .plain, id: "sync.review.copy")
        copy.addTarget(self, action: #selector(copyIds), for: .touchUpInside)
        stack.addArrangedSubview(copy)
    }

    private func stateLine(_ op: SyncOperation, _ review: SyncRecordReview) -> String {
        switch op.state {
        case .needsAttention: return "Needs Attention — Kabba refused this record"
        case .synced:         return "Synced with Kabba"
        case .superseded:     return "Retired — kept as history"
        case .pending, .syncing: return SyncStatusRowText.status(op, review)
        }
    }

    private func details(_ op: SyncOperation, _ review: SyncRecordReview) -> String {
        var lines = ["Captured: \(SyncStatusFormat.dateTime.string(from: op.capturedAt))",
                     "Queued: \(SyncStatusFormat.dateTime.string(from: op.queuedAt))",
                     "Attempts: \(op.attempts.attemptCount)"]
        if let last = op.attempts.lastAttemptedAt { lines.append("Last attempt: \(SyncStatusFormat.dateTime.string(from: last))") }
        if let next = op.attempts.nextAttemptAt, op.state == .pending { lines.append("Next attempt: \(SyncStatusFormat.dateTime.string(from: next))") }
        if let acked = op.acknowledgment?.acknowledgedAt { lines.append("Kabba confirmed: \(SyncStatusFormat.dateTime.string(from: acked))") }
        if let status = op.attempts.lastStatusCode { lines.append("HTTP status: \(status)") }
        if let code = review.errorCode { lines.append("Error code: \(code)") }
        if let message = review.serverMessage, op.state != .synced { lines.append("Kabba said: \(message)") }
        if !op.identity.summary.isEmpty { lines.append(op.identity.summary) }
        lines.append("Operation id: \(op.id)")
        if let request = op.attempts.lastRequestId ?? op.acknowledgment?.requestId { lines.append("Request id: \(request)") }
        return lines.joined(separator: "\n")
    }

    // MARK: Actions

    @objc private func tryAgain() {
        engineProvider()?.retryNow(operationId: operationId)
        KabbaSync.showConfirmationToast("Trying again…", duration: 1.0)
    }

    @objc private func copyIds() {
        guard let op = engineProvider()?.operation(id: operationId) else { return }
        UIPasteboard.general.string = "operation_id=\(op.id) request_id=\(op.attempts.lastRequestId ?? "-")"
        KabbaSync.showConfirmationToast("Copied", duration: 0.8)
    }

    @objc private func confirmRemove() {
        guard let op = engineProvider()?.operation(id: operationId) else { return }
        let review = SyncRecordReview.of(op)
        guard review.canRemove else { return }
        let alert = UIAlertController(title: "Remove this record from the phone?",
                                      message: Self.removalMessage(op: op, review: review),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep It", style: .cancel))
        let destructive = UIAlertAction(title: review.contents.holdsCapturedWork ? "Delete and Remove" : "Remove", style: .destructive) { [weak self] _ in
            self?.remove()
        }
        alert.addAction(destructive)
        present(alert, animated: true)
    }

    /// The confirmation's words: never claims Kabba has it; lists what is deleted; says what changes.
    static func removalMessage(op: SyncOperation, review: SyncRecordReview) -> String {
        var parts = ["Kabba has not received this record."]
        if !review.contents.items.isEmpty {
            parts.append("This permanently deletes from this phone: " + review.contents.items.joined(separator: ", ") + ".")
        }
        parts.append(review.removalConsequence)
        if op.state == .pending {
            parts.append("It is still waiting to send and would reach Kabba once this phone can connect.")
        }
        if review.officeSees {
            parts.append("The office's Mobile Sync Issue stays open until the work is recorded.")
        }
        return parts.joined(separator: "\n\n")
    }

    private func remove() {
        do {
            removedHere = true
            try remover(operationId)
            KabbaSync.showConfirmationToast("Removed from this phone", duration: 1.2)
            navigationController?.popViewController(animated: true)
        } catch SyncEngineError.notRemovable(_, let state) where state == .syncing {
            removedHere = false
            showError("This record is being sent right now. Wait a moment, then try again.")
        } catch {
            removedHere = false
            render()
            showError("This record could not be removed. Nothing was deleted.")
        }
    }

    private func showError(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: Building blocks

    private func paragraph(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = font
        label.textColor = color
        label.text = text
        return label
    }

    private func cardStack() -> UIStackView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 8
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        return card
    }

    private func wrap(_ card: UIStackView) -> UIView {
        let box = UIView()
        box.backgroundColor = theme.card
        box.layer.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: box.topAnchor),
            card.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        ])
        return box
    }

    private enum ButtonStyle { case primary, destructive, plain }

    private func button(_ title: String, style: ButtonStyle, id: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = theme.bold(16)
        b.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        b.layer.cornerRadius = 10
        b.accessibilityIdentifier = id
        switch style {
        case .primary:
            b.backgroundColor = theme.accent
            b.setTitleColor(theme.background, for: .normal)
        case .destructive:
            b.layer.borderWidth = 1.5
            b.layer.borderColor = UIColor.systemRed.cgColor
            b.setTitleColor(.systemRed, for: .normal)
        case .plain:
            b.setTitleColor(theme.accent, for: .normal)
        }
        return b
    }

    /// Small previews of the record's own images, so a person sees what removal deletes.
    private func thumbnails(for op: SyncOperation, assetsDirectory: URL) -> UIView? {
        let images: [UIImage] = op.assets.prefix(6).compactMap { asset in
            guard asset.mimeType.lowercased().hasPrefix("image/") else { return nil }
            let url = SyncAssetWriter.url(of: asset, in: assetsDirectory)
            return UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 128, height: 128))
        }
        guard !images.isEmpty else { return nil }
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .leading
        for image in images {
            let view = UIImageView(image: image)
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.layer.cornerRadius = 6
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: 56), view.heightAnchor.constraint(equalToConstant: 56)])
            row.addArrangedSubview(view)
        }
        let scrollRow = UIScrollView()
        scrollRow.showsHorizontalScrollIndicator = false
        row.translatesAutoresizingMaskIntoConstraints = false
        scrollRow.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scrollRow.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scrollRow.contentLayoutGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scrollRow.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scrollRow.contentLayoutGuide.trailingAnchor),
            scrollRow.heightAnchor.constraint(equalToConstant: 56),
        ])
        return scrollRow
    }
}
