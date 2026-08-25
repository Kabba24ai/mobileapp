//
//  KabbaUpdateGate.swift
//  RentnKing — Sync App layer (UIKit)
//
//  Phase 5 — what the phone does with 426 APP_UPDATE_REQUIRED.
//
//   • The verdict is persisted (UpdateRequiredStore) so it survives relaunch;
//     the Sync Engine is paused (.appUpdate) so nothing incompatible is sent;
//     every queued operation and file stays exactly where it is.
//   • The Update Required screen explains, quotes how much saved work is
//     waiting, and opens the App Store (server-provided URL, else the app's).
//   • At launch the stored verdict is re-checked against the RUNNING build:
//     still below the minimum → paused + screen again; compatible build →
//     verdict cleared, engine resumed, queue drains (after sign-in if needed).
//   • A phone that is merely offline is never gated: only a real 426 (or its
//     persisted verdict) blocks.
//

import UIKit

final class KabbaUpdateGate {

    static let shared = KabbaUpdateGate()

    static let fallbackStoreURL = "https://apps.apple.com/us/app/kabba-ai/id6751110122"

    private(set) var store: UpdateRequiredStore?
    private(set) var state: UpdateRequiredState?
    private weak var engine: SyncEngine?
    private weak var presented: UpdateRequiredViewController?

    /// CFBundleVersion of the running build (sanitized like the header the server compared).
    var currentBuild: String = MobileClientMetadata.sanitize(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0")

    var isBlocking: Bool { state != nil }

    /// Launch: re-evaluate a persisted verdict against the running build.
    func configure(rootDirectory: URL, engine: SyncEngine) {
        let store = UpdateRequiredStore(directory: rootDirectory)
        self.store = store
        self.engine = engine

        switch store.resolution(currentBuild: currentBuild) {
        case .none:
            state = nil
        case .stillRequired(let stored):
            state = stored
            engine.appUpdateRequired()
            DispatchQueue.main.async { [weak self] in self?.present() }
        case .resolved:
            // The employee installed a compatible build: forget the verdict, resume the queue.
            store.clear()
            state = nil
            engine.appUpdated()
        }
    }

    /// A live 426 reached either network layer.
    func handle(policyBody: Data?, requestId: String?) {
        guard let policy = ReleasePolicy.decode(envelopeData: policyBody) ?? fallbackPolicy() else { return }
        let stored = UpdateRequiredState(policy: policy, receivedAt: Date(), blockedBuild: currentBuild, requestId: requestId)
        state = stored
        try? store?.save(stored)
        engine?.appUpdateRequired()
        DispatchQueue.main.async { [weak self] in self?.present() }
    }

    func storeURL() -> URL {
        URL(string: state?.policy.storeURL ?? "") ?? URL(string: KabbaUpdateGate.fallbackStoreURL)!
    }

    // MARK: - Presentation

    func present(in window: UIWindow? = nil) {
        guard let state = state, presented == nil else { presented?.refresh(); return }
        let window = window ?? (UIApplication.shared.delegate?.window ?? nil) ?? UIApplication.shared.windows.first { $0.isKeyWindow }
        guard let root = window?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController { top = next }
        let controller = UpdateRequiredViewController(state: state, pendingCount: KabbaSession.pendingWorkCount(), storeURL: storeURL())
        controller.modalPresentationStyle = .fullScreen
        controller.isModalInPresentation = true
        presented = controller
        top.present(controller, animated: true)
    }

    private func fallbackPolicy() -> ReleasePolicy? {
        ReleasePolicy(platform: "ios", state: "update_required", clientBuild: currentBuild, clientVersion: nil,
                      minimumSupportedBuild: nil, recommendedBuild: nil, recommendedVersion: nil,
                      updateMessage: nil, storeURL: nil, updateRequired: true, updateRecommended: false)
    }
}

/// Full-screen, non-dismissable. Deliberately plain UIKit; no design-system dependency.
final class UpdateRequiredViewController: UIViewController {

    private let state: UpdateRequiredState
    private var pendingCount: Int
    private let storeURL: URL
    private let pendingLabel = UILabel()

    init(state: UpdateRequiredState, pendingCount: Int, storeURL: URL) {
        self.state = state
        self.pendingCount = pendingCount
        self.storeURL = storeURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "Update Required"
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textAlignment = .center
        title.numberOfLines = 0

        let message = UILabel()
        message.text = state.policy.employeeMessage
        message.font = .systemFont(ofSize: 17)
        message.textColor = .label
        message.textAlignment = .center
        message.numberOfLines = 0

        var detail = "This version of the Kabba app can no longer sync with Kabba."
        if let minimum = state.policy.minimumSupportedBuild {
            detail += " Installed build \(state.blockedBuild); minimum supported build \(minimum)"
            if let version = state.policy.recommendedVersion { detail += " (version \(version))" }
            detail += "."
        }
        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 14)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        pendingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        pendingLabel.textColor = .label
        pendingLabel.textAlignment = .center
        pendingLabel.numberOfLines = 0
        refresh()

        let button = UIButton(type: .system)
        button.setTitle("Open the App Store", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 24, bottom: 14, right: 24)
        button.addTarget(self, action: #selector(openStore), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, message, detailLabel, pendingLabel, button])
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
        ])
    }

    func refresh() {
        pendingCount = KabbaSession.pendingWorkCount()
        pendingLabel.text = pendingCount > 0
            ? "\(pendingCount) item\(pendingCount == 1 ? "" : "s") saved on this phone \(pendingCount == 1 ? "is" : "are") kept and will sync automatically after you update and sign in."
            : "Nothing is waiting to sync. Your saved work is kept through the update."
    }

    @objc private func openStore() {
        UIApplication.shared.open(storeURL, options: [:], completionHandler: nil)
    }
}
