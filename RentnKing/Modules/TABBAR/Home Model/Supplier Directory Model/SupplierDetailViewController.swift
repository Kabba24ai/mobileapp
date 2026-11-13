//
//  SupplierDetailViewController.swift
//  RentnKing
//
//  Supplier Directory — one supplier (2026-11-13), in three sections:
//
//      Company Information   phone · email · website · address (+ status, category, tags)
//      Contacts              primary · inside sales · technical support · billing
//      Other Information     payment terms (accounts payable only) · parts supplied
//
//  Tap a phone number to call, an email to write, the website to open it, the
//  address for Apple Maps directions; touch and hold any value to copy it. Only
//  what Kabba has on file is shown — an empty field is simply absent. Without a
//  connection the copy this phone saved is shown, marked as possibly out of date.
//

import UIKit

final class SupplierDetailViewController: UIViewController, UIGestureRecognizerDelegate {

    typealias Palette = EquipmentAuditRowCell.Palette

    private let uniqueId: String
    private let api: SupplierDirectoryAPI
    private(set) var envelope: SupplierDetailEnvelope?
    private(set) var cachedAt: Date?
    private(set) var failure: SupplierDirectoryFailure?
    private var isLoading = false

    /// Seam for tests: how a contact link is opened.
    var openURL: (URL) -> Void = { UIApplication.shared.open($0) }
    /// The actions shown, in order (tests read them): identifier → URL.
    private(set) var actionLinks: [(id: String, url: URL)] = []

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .large)

    init(uniqueId: String, title: String? = nil, initial: SupplierDetailEnvelope? = nil, api: SupplierDirectoryAPI = .shared) {
        self.uniqueId = uniqueId
        self.api = api
        self.envelope = initial
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.page
        view.accessibilityIdentifier = "suppliers.detail"
        overrideUserInterfaceStyle = .dark

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        let refresh = UIRefreshControl()
        refresh.tintColor = Palette.cyan
        refresh.addTarget(self, action: #selector(reload(_:)), for: .valueChanged)
        scroll.refreshControl = refresh
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
        ])
        spinner.color = Palette.cyan
        render()
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        tabBarController?.tabBar.isHidden = true
        setNavigationBarFor(controller: self, title: "Supplier", isTransperent: true, hideShadowImage: true,
                            leftIcon: "icon_back", rightIcon: "", isDetailsScree: false,
                            leftActionHandler: { [weak self] in self?.navigationController?.popViewController(animated: true) })
    }

    @objc private func reload(_ sender: UIRefreshControl) { load() }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        api.detail(uniqueId) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            self.scroll.refreshControl?.endRefreshing()
            switch result {
            case .success(let envelope):
                self.envelope = envelope
                self.cachedAt = nil
                self.failure = nil
            case .failure(let failure):
                self.failure = failure
                if failure.isOffline, let saved = self.api.offlineCopy.detail(self.uniqueId) {
                    self.envelope = saved.envelope
                    self.cachedAt = saved.savedAt
                } else if failure.isForbidden || failure.isNotFound {
                    self.envelope = nil
                }
            }
            self.render()
        }
    }

    // MARK: Rendering

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actionLinks = []

        guard let envelope = envelope else {
            if let failure = failure {
                let text = failure.isNotFound ? "This supplier is no longer in Kabba."
                    : failure.isOffline ? "No connection, and this supplier has not been opened on this phone before."
                    : failure.message
                stack.addArrangedSubview(label(text, 15, .medium, Palette.subtle, id: "suppliers.detail.message"))
            } else {
                spinner.startAnimating()
                stack.addArrangedSubview(spinner)
            }
            return
        }
        let s = envelope.supplier

        if let cachedAt = cachedAt {
            stack.addArrangedSubview(label(SupplierDirectoryPresentation.cachedNotice(savedAt: cachedAt), 13, .semibold, Palette.amber, id: "suppliers.detail.offline"))
        }

        // Heading
        stack.addArrangedSubview(label(s.name, 24, .bold, Palette.ink, id: "suppliers.detail.name"))
        stack.addArrangedSubview(label(SupplierDirectoryPresentation.statusLine(status: s.status, isPreferred: s.isPreferred), 14, .semibold,
                                       s.isActive ? Palette.greenText : Palette.amber, id: "suppliers.detail.status"))
        let classification = ([s.category?.name].compactMap { $0 } + s.tags.map(\.name)).joined(separator: " · ")
        if !classification.isEmpty { stack.addArrangedSubview(label(classification, 13, .medium, Palette.cyan, id: "suppliers.detail.classification")) }

        // Company Information
        var company: [UIView] = []
        if let phone = s.phone { company.append(row("phone", "Phone", phone, url: SupplierContactLinks.phoneURL(phone), id: "suppliers.detail.phone")) }
        if let email = s.email { company.append(row("envelope", "Email", email, url: SupplierContactLinks.emailURL(email), id: "suppliers.detail.email")) }
        if let website = s.website { company.append(row("safari", "Website", website, url: SupplierContactLinks.websiteURL(website), id: "suppliers.detail.website")) }
        if let line = s.address.oneLine {
            company.append(row("map", "Address · Directions", line, url: SupplierContactLinks.directionsURL(address: s.address), id: "suppliers.detail.address"))
        }
        section("Company Information", company.isEmpty ? [label("No phone, email, website or address on file.", 14, .medium, Palette.subtle)] : company)

        // Contacts
        let contacts: [UIView] = s.contacts.map { contact in
            var lines: [UIView] = [label(contact.label.uppercased(), 11, .bold, Palette.subtle)]
            if let name = contact.name { lines.append(label(name, 16, .semibold, Palette.ink)) }
            if let phone = contact.phone {
                lines.append(row("phone", "Phone", phone, url: SupplierContactLinks.phoneURL(phone), id: "suppliers.detail.\(contact.role).phone"))
            }
            if let email = contact.email {
                lines.append(row("envelope", "Email", email, url: SupplierContactLinks.emailURL(email), id: "suppliers.detail.\(contact.role).email"))
            }
            let card = UIStackView(arrangedSubviews: lines)
            card.axis = .vertical
            card.spacing = 4
            card.accessibilityIdentifier = "suppliers.detail.contact.\(contact.role)"
            return card
        }
        section("Contacts", contacts.isEmpty ? [label("No contacts on file.", 14, .medium, Palette.subtle)] : contacts)

        // Other Information
        var other: [UIView] = []
        if envelope.can.viewPaymentTerms {
            other.append(pair("Payment terms", s.paymentTerms ?? "Not on file", id: "suppliers.detail.paymentTerms"))
        }
        if s.parts.count > 0 {
            other.append(label("PARTS SUPPLIED (\(s.parts.count))", 11, .bold, Palette.subtle))
            for part in s.parts.items {
                let detail = SupplierDirectoryPresentation.partLine(part)
                other.append(pair(part.name, detail.isEmpty ? " " : detail, id: "suppliers.detail.part"))
            }
            if s.parts.count > s.parts.items.count {
                other.append(label("+ \(s.parts.count - s.parts.items.count) more in Kabba", 12, .medium, Palette.subtle))
            }
        } else {
            other.append(label("No parts on file for this supplier.", 14, .medium, Palette.subtle))
        }
        section("Other Information", other)
    }

    private func section(_ title: String, _ views: [UIView]) {
        let heading = label(title, 15, .bold, Palette.cyan)
        let card = UIStackView(arrangedSubviews: views)
        card.axis = .vertical
        card.spacing = 12
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        card.backgroundColor = UIColor(red: 0x14 / 255.0, green: 0x1C / 255.0, blue: 0x26 / 255.0, alpha: 1)
        card.layer.cornerRadius = 12
        card.layer.borderWidth = 1
        card.layer.borderColor = Palette.border.cgColor
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last ?? heading)
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(card)
    }

    private func label(_ text: String, _ size: CGFloat, _ weight: UIFont.Weight, _ color: UIColor, id: String? = nil) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.numberOfLines = 0
        l.accessibilityIdentifier = id
        return l
    }

    private func pair(_ title: String, _ value: String, id: String) -> UIView {
        let v = UIStackView(arrangedSubviews: [label(title, 14, .semibold, Palette.ink), label(value, 13, .medium, Palette.subtle)])
        v.axis = .vertical
        v.spacing = 2
        v.accessibilityIdentifier = id
        return v
    }

    /// A value the employee can act on: tap opens the link, touch and hold copies the value.
    private func row(_ symbol: String, _ title: String, _ value: String, url: URL?, id: String) -> UIView {
        let button = SupplierValueButton(type: .system)
        button.copyValue = value
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = id
        button.accessibilityLabel = "\(title): \(value)"
        button.accessibilityValue = value

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = url == nil ? Palette.subtle : Palette.cyan
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let valueLabel = label(value, 16, .medium, url == nil ? Palette.ink : Palette.cyan)
        if symbol == "envelope" || symbol == "safari" {
            // One unbroken line for an address on the web: shrink, never split mid-word.
            valueLabel.numberOfLines = 1
            valueLabel.adjustsFontSizeToFitWidth = true
            valueLabel.minimumScaleFactor = 0.6
            valueLabel.lineBreakMode = .byTruncatingMiddle
        }
        let text = UIStackView(arrangedSubviews: [label(title, 11, .semibold, Palette.subtle), valueLabel])
        text.axis = .vertical
        text.spacing = 1
        let content = UIStackView(arrangedSubviews: [icon, text])
        content.spacing = 12
        content.alignment = .center
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
            content.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -2),
            content.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])

        if let url = url {
            actionLinks.append((id, url))
            button.addAction(UIAction { [weak self] _ in self?.openURL(url) }, for: .touchUpInside)
        }
        button.addInteraction(UIContextMenuInteraction(delegate: CopyMenu.shared))
        return button
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}

/// A tappable supplier value that remembers what it shows, for Copy.
final class SupplierValueButton: UIButton {
    var copyValue = ""
}

/// Touch and hold a value → Copy.
private final class CopyMenu: NSObject, UIContextMenuInteractionDelegate {
    static let shared = CopyMenu()

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let value = (interaction.view as? SupplierValueButton)?.copyValue, !value.isEmpty else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = value }])
        }
    }
}
